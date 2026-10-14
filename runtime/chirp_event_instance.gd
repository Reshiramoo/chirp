class_name ChirpEventInstance
extends RefCounted
## One live playback of a ChirpEvent. Create with Chirp.create_instance().
##
## Lifecycle: start() -> [playing] -> stop() or natural end -> [stopped].
## Call release() when you no longer need the handle; a released instance is
## destroyed as soon as it stops. All signals fire on the main thread.

signal started
signal restarted
signal stopped
signal destroyed

enum State { STOPPED, PLAYING, STOPPING }

enum Spatial { NONE, SPATIAL_2D, SPATIAL_3D }

## Linear volume multiplier for this instance.
var volume := 1.0
## Pitch multiplier for this instance.
var pitch := 1.0

var _event: ChirpEvent
var _chirp: Node # the Chirp autoload
var _bus: StringName = &"Master"
var _state := State.STOPPED
var _released := false
var _destroyed := false
var _paused := false
var _applied_paused := false
var _params := {} # lowercase name -> ChirpParameter.State
var _voices: Array[Voice] = []
var _pending: Array[Pending] = []
var _next_consecutive := 0
var _time := 0.0
var _release_time := 0.0
var _release_from := 1.0
var _env_level := 1.0
var _spatial := Spatial.NONE
var _position: Variant = null
var _attached: WeakRef
var _attenuation := {}
var _start_order := 0
var _previous_position: Variant = null
var _velocity: Variant = null # Vector2 or Vector3, from position changes
var _lfo_seed := 0
var _has_built_ins := false


class Voice:
	var player # AudioStreamPlayer, AudioStreamPlayer2D or AudioStreamPlayer3D
	var gain := 1.0
	var pitch := 1.0
	var instrument: ChirpInstrument


class Pending:
	var instrument: ChirpInstrument
	var time_left := 0.0


func _init(chirp: Node, event: ChirpEvent, bus: StringName) -> void:
	_chirp = chirp
	_event = event
	_bus = bus
	for definition in event.parameters:
		if definition:
			_params[definition.name.to_lower()] = ChirpParameter.State.new(definition)
			_has_built_ins = _has_built_ins or definition.built_in != ChirpParameter.BuiltIn.NONE


func get_event() -> ChirpEvent:
	return _event


func get_state() -> State:
	return _state


func is_playing() -> bool:
	return _state != State.STOPPED


func is_valid() -> bool:
	return not _destroyed


## Starts playback, or restarts it from the beginning if already playing.
func start() -> void:
	if _destroyed:
		push_error("ChirpEventInstance: start() called on a destroyed instance.")
		return
	if not _chirp.events._can_start(self):
		return
	var was_playing := is_playing()
	_clear_voices()
	_pending.clear()
	_time = 0.0
	_lfo_seed = randi()
	_env_level = _event.envelope.level_at(0.0) if _event.envelope else 1.0
	_state = State.PLAYING
	_chirp.events._register_start(self)
	if _has_built_ins:
		_update_built_ins()
	if _event.sheet_mode == ChirpEvent.SheetMode.CONSECUTIVE:
		_next_consecutive = 0
		_schedule_next_consecutive()
	else:
		for instrument in _event.instruments:
			if instrument:
				_schedule(instrument)
	if was_playing:
		restarted.emit()
	else:
		started.emit()


## Stops playback. With [param allow_fadeout] the envelope's release is played first.
func stop(allow_fadeout := true) -> void:
	if _state == State.STOPPED:
		return
	var release := _event.envelope.release if _event.envelope else 0.0
	if allow_fadeout and release > 0.0:
		if _state == State.PLAYING:
			_state = State.STOPPING
			_release_time = 0.0
			_release_from = _env_level
			_pending.clear()
		return
	_finish_stop()


## Marks the instance for destruction once it has stopped.
func release() -> void:
	_released = true
	if _state == State.STOPPED:
		_destroy()


func set_paused(paused: bool) -> void:
	_paused = paused
	_sync_pause()


func get_paused() -> bool:
	return _paused


func set_parameter(parameter_name: String, value: float) -> void:
	var state := _settable_state(parameter_name)
	if state:
		state.set_target(value, _state == State.STOPPED)


func set_parameter_by_label(parameter_name: String, label: String) -> void:
	var state := _settable_state(parameter_name)
	if state == null:
		return
	var value := state.def.label_to_value(label)
	if value < 0.0:
		push_warning("Chirp: parameter '%s' has no label '%s'." % [parameter_name, label])
		return
	state.set_target(value, _state == State.STOPPED)


func get_parameter(parameter_name: String) -> float:
	var state: ChirpParameter.State = _params.get(parameter_name.to_lower())
	return state.value if state else 0.0


## Plays the event at a fixed position. Pass a Vector2 for 2D or a Vector3 for 3D.
func set_position(position: Variant) -> void:
	if position is Vector2:
		_spatial = Spatial.SPATIAL_2D
	elif position is Vector3:
		_spatial = Spatial.SPATIAL_3D
	else:
		push_error("ChirpEventInstance.set_position() expects a Vector2 or Vector3.")
		return
	_attached = null
	_position = position


## Follows [param node] (a Node2D or Node3D). If the node is freed, the sound
## stays where the node was last seen.
func attach_to(node: Node) -> void:
	if node is Node2D:
		_spatial = Spatial.SPATIAL_2D
	elif node is Node3D:
		_spatial = Spatial.SPATIAL_3D
	else:
		_spatial = Spatial.NONE
		return
	_attached = weakref(node)
	if node.is_inside_tree():
		_position = node.global_position


## Overrides the event's 2D attenuation for this instance.
func set_attenuation_2d(max_distance: float, attenuation: float) -> void:
	_attenuation = {max_distance = max_distance, attenuation = attenuation}


## Overrides the event's 3D attenuation for this instance.
func set_attenuation_3d(unit_size: float, max_distance: float) -> void:
	_attenuation = {unit_size = unit_size, max_distance = max_distance}


# --- driven by the Chirp autoload --------------------------------------------

func _process(delta: float) -> void:
	_sync_pause()
	if _applied_paused:
		return
	_time += delta
	if _attached:
		var node = _attached.get_ref()
		if node and node.is_inside_tree():
			_position = node.global_position
	_track_velocity(delta)
	if _has_built_ins:
		_update_built_ins()
	for state: ChirpParameter.State in _params.values():
		state.step(delta)

	for i in range(_pending.size() - 1, -1, -1):
		var pending := _pending[i]
		pending.time_left -= delta
		if pending.time_left <= 0.0:
			_pending.remove_at(i)
			_trigger(pending.instrument)

	if _state == State.STOPPING:
		_release_time += delta
		var release := _event.envelope.release
		_env_level = _release_from * (1.0 - _release_time / release)
		if _env_level <= 0.0:
			_finish_stop()
			return
	elif _event.envelope:
		_env_level = _event.envelope.level_at(_time)

	var volume_factor := _automation(ChirpAutomation.Target.VOLUME)
	var pitch_factor := _automation(ChirpAutomation.Target.PITCH)
	for voice in _voices:
		_apply(voice, volume_factor, pitch_factor)

	if _state == State.PLAYING and _voices.is_empty() and _pending.is_empty():
		_finish_stop()


## Current linear volume before automation and instrument gain; used for stealing.
func _get_level() -> float:
	return db_to_linear(_event.volume_db) * volume * _env_level


func _schedule(instrument: ChirpInstrument) -> bool:
	if randf() * 100.0 >= instrument.probability:
		return false
	if instrument.delay > 0.0:
		var pending := Pending.new()
		pending.instrument = instrument
		pending.time_left = instrument.delay
		_pending.append(pending)
	else:
		_trigger(instrument)
	return true


func _schedule_next_consecutive() -> void:
	while _next_consecutive < _event.instruments.size():
		var instrument := _event.instruments[_next_consecutive]
		_next_consecutive += 1
		if instrument and _schedule(instrument):
			return


func _trigger(instrument: ChirpInstrument) -> void:
	var stream := instrument.pick_stream()
	if stream == null:
		return
	var player # AudioStreamPlayer, AudioStreamPlayer2D or AudioStreamPlayer3D
	match _spatial:
		Spatial.SPATIAL_2D:
			var player_2d := AudioStreamPlayer2D.new()
			player_2d.max_distance = _attenuation.get("max_distance", _event.max_distance_2d)
			player_2d.attenuation = _attenuation.get("attenuation", _event.attenuation_2d)
			player = player_2d
		Spatial.SPATIAL_3D:
			var player_3d := AudioStreamPlayer3D.new()
			player_3d.unit_size = _attenuation.get("unit_size", _event.unit_size_3d)
			player_3d.max_distance = _attenuation.get("max_distance", _event.max_distance_3d)
			player = player_3d
		_:
			player = AudioStreamPlayer.new()
	player.stream = stream
	player.bus = _bus

	var voice := Voice.new()
	voice.player = player
	voice.instrument = instrument
	voice.gain = db_to_linear(instrument.volume_db - randf() * instrument.random_volume_db)
	var detune := randf_range(-instrument.random_pitch_semitones, instrument.random_pitch_semitones)
	voice.pitch = pow(2.0, (instrument.pitch_semitones + detune) / 12.0)
	_voices.append(voice)

	_chirp._voice_root.add_child(player)
	_apply(voice, _automation(ChirpAutomation.Target.VOLUME), _automation(ChirpAutomation.Target.PITCH))
	player.finished.connect(_on_voice_finished.bind(voice))
	player.play()
	player.stream_paused = _applied_paused


func _on_voice_finished(voice: Voice) -> void:
	if voice.instrument.loop and _state == State.PLAYING:
		voice.player.play()
		return
	_voices.erase(voice)
	voice.player.queue_free()
	if _state == State.PLAYING and _event.sheet_mode == ChirpEvent.SheetMode.CONSECUTIVE:
		_schedule_next_consecutive()


func _apply(voice: Voice, volume_factor: float, pitch_factor: float) -> void:
	var player = voice.player
	var gain := _get_level() * voice.gain * volume_factor
	player.volume_db = linear_to_db(gain) if gain > 0.00001 else -80.0
	player.pitch_scale = maxf(_event.pitch_scale * pitch * voice.pitch * pitch_factor, 0.01)
	if _position is Vector2 and player is AudioStreamPlayer2D:
		player.global_position = _position
	elif _position is Vector3 and player is AudioStreamPlayer3D:
		player.global_position = _position


func _automation(target: ChirpAutomation.Target) -> float:
	var factor := 1.0
	for automation in _event.automations:
		if automation == null or automation.target != target:
			continue
		var state: ChirpParameter.State
		if automation.global:
			state = _chirp.parameters._get_state(automation.parameter)
		else:
			state = _params.get(automation.parameter.to_lower())
		if state:
			factor *= automation.evaluate(state.def, state.value)
	for modulator in _event.modulators:
		if modulator and int(modulator.target) == int(target):
			factor *= modulator.factor(_time, _lfo_seed)
	return factor


func _settable_state(parameter_name: String) -> ChirpParameter.State:
	var state: ChirpParameter.State = _params.get(parameter_name.to_lower())
	if state == null:
		_chirp._warn_once("param:%s:%s" % [_event.resource_path, parameter_name],
			"Chirp: event has no parameter '%s'." % parameter_name)
	elif state.def.built_in != ChirpParameter.BuiltIn.NONE:
		_chirp._warn_once("builtin:%s:%s" % [_event.resource_path, parameter_name],
			"Chirp: '%s' is a built-in parameter and is set automatically." % parameter_name)
		return null
	return state


func _track_velocity(delta: float) -> void:
	if _position == null or delta <= 0.0:
		return
	if _previous_position != null and typeof(_previous_position) == typeof(_position):
		_velocity = (_position - _previous_position) / delta
	_previous_position = _position


## Facing direction of the attached node: +X in 2D, -Z in 3D.
func _forward() -> Variant:
	var node = _attached.get_ref() if _attached else null
	if _position is Vector2:
		return Vector2.RIGHT.rotated(node.global_rotation) if node is Node2D else Vector2.RIGHT
	return -node.global_basis.z if node is Node3D else Vector3.FORWARD


func _update_built_ins() -> void:
	if _position == null:
		return
	var events = _chirp.events
	var distance := 0.0
	var direction := 0.0
	var elevation := 0.0
	var orientation := 0.0
	var cone := 0.0
	var speed := 0.0
	var speed_absolute := 0.0
	var max_distance := 0.0
	var min_distance := 0.0
	if _position is Vector2:
		var listener: Transform2D = events._listener_2d
		var offset: Vector2 = _position - listener.origin
		var ahead := Vector2.UP.rotated(listener.get_rotation())
		var facing: Vector2 = _forward()
		distance = offset.length()
		if distance > 0.0:
			direction = rad_to_deg(ahead.angle_to(offset))
			orientation = rad_to_deg(facing.angle_to(-offset))
		var velocity: Vector2 = _velocity if _velocity is Vector2 else Vector2.ZERO
		speed = (velocity - events._listener_2d_velocity).length()
		speed_absolute = velocity.length()
		max_distance = _attenuation.get("max_distance", _event.max_distance_2d)
	else:
		var listener: Transform3D = events._listener_3d
		var offset: Vector3 = _position - listener.origin
		var ahead := -listener.basis.z
		var up := listener.basis.y
		var right := listener.basis.x
		var facing: Vector3 = _forward()
		distance = offset.length()
		if distance > 0.0:
			direction = rad_to_deg(atan2(offset.dot(right), offset.dot(ahead)))
			elevation = rad_to_deg(asin(clampf(offset.normalized().dot(up), -1.0, 1.0)))
			var to_listener := -offset
			var facing_right := facing.cross(Vector3.UP)
			orientation = rad_to_deg(atan2(to_listener.dot(facing_right), to_listener.dot(facing)))
		var velocity: Vector3 = _velocity if _velocity is Vector3 else Vector3.ZERO
		speed = (velocity - events._listener_3d_velocity).length()
		speed_absolute = velocity.length()
		min_distance = _attenuation.get("unit_size", _event.unit_size_3d)
		max_distance = _attenuation.get("max_distance", _event.max_distance_3d)
	cone = absf(orientation)
	var normalized := 0.0
	if max_distance > min_distance:
		normalized = clampf((distance - min_distance) / (max_distance - min_distance), 0.0, 1.0)

	for state: ChirpParameter.State in _params.values():
		var value := 0.0
		match state.def.built_in:
			ChirpParameter.BuiltIn.NONE:
				continue
			ChirpParameter.BuiltIn.DISTANCE:
				value = distance
			ChirpParameter.BuiltIn.DISTANCE_NORMALIZED:
				value = normalized
			ChirpParameter.BuiltIn.DIRECTION:
				value = direction
			ChirpParameter.BuiltIn.ELEVATION:
				value = elevation
			ChirpParameter.BuiltIn.EVENT_CONE_ANGLE:
				value = cone
			ChirpParameter.BuiltIn.EVENT_ORIENTATION:
				value = orientation
			ChirpParameter.BuiltIn.SPEED:
				value = speed
			ChirpParameter.BuiltIn.SPEED_ABSOLUTE:
				value = speed_absolute
		state.set_target(value, true)


func _sync_pause() -> void:
	var paused: bool = _paused or _chirp.mixer._is_bus_paused(_bus)
	if paused == _applied_paused:
		return
	_applied_paused = paused
	for voice in _voices:
		voice.player.stream_paused = paused


func _finish_stop() -> void:
	_clear_voices()
	_pending.clear()
	_state = State.STOPPED
	_chirp.events._register_stop(self)
	stopped.emit()
	if _released:
		_destroy()


func _clear_voices() -> void:
	for voice in _voices:
		if is_instance_valid(voice.player):
			voice.player.stop()
			voice.player.queue_free()
	_voices.clear()


func _destroy() -> void:
	if _destroyed:
		return
	_destroyed = true
	destroyed.emit()
