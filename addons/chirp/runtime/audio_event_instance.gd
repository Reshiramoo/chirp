class_name AudioEventInstance
extends RefCounted
## One live playback of an AudioEvent. Create with AudioEvents.create_instance().
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

var _event: AudioEvent
var _manager: Node
var _bus: StringName = &"Master"
var _state := State.STOPPED
var _released := false
var _destroyed := false
var _paused := false
var _applied_paused := false
var _params := {} # lowercase name -> AudioEventParameter.State
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


class Voice:
	var player # AudioStreamPlayer, AudioStreamPlayer2D or AudioStreamPlayer3D
	var gain := 1.0
	var pitch := 1.0
	var instrument: AudioEventInstrument


class Pending:
	var instrument: AudioEventInstrument
	var time_left := 0.0


func _init(manager: Node, event: AudioEvent, bus: StringName) -> void:
	_manager = manager
	_event = event
	_bus = bus
	for definition in event.parameters:
		if definition:
			_params[definition.name.to_lower()] = AudioEventParameter.State.new(definition)


func get_event() -> AudioEvent:
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
		push_error("AudioEventInstance: start() called on a destroyed instance.")
		return
	if not _manager._can_start(self):
		return
	var was_playing := is_playing()
	_clear_voices()
	_pending.clear()
	_time = 0.0
	_env_level = _event.envelope.level_at(0.0) if _event.envelope else 1.0
	_state = State.PLAYING
	_manager._register_start(self)
	if _event.sheet_mode == AudioEvent.SheetMode.CONSECUTIVE:
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
	var state: AudioEventParameter.State = _params.get(parameter_name.to_lower())
	if state == null:
		_manager._warn_once("param:%s:%s" % [_event.resource_path, parameter_name],
			"AudioEvents: event has no parameter '%s'." % parameter_name)
		return
	state.set_target(value, _state == State.STOPPED)


func set_parameter_by_label(parameter_name: String, label: String) -> void:
	var state: AudioEventParameter.State = _params.get(parameter_name.to_lower())
	if state == null:
		set_parameter(parameter_name, 0.0) # reports the missing parameter
		return
	var value := state.def.label_to_value(label)
	if value < 0.0:
		push_warning("AudioEvents: parameter '%s' has no label '%s'." % [parameter_name, label])
		return
	state.set_target(value, _state == State.STOPPED)


func get_parameter(parameter_name: String) -> float:
	var state: AudioEventParameter.State = _params.get(parameter_name.to_lower())
	return state.value if state else 0.0


## Plays the event at a fixed position. Pass a Vector2 for 2D or a Vector3 for 3D.
func set_position(position: Variant) -> void:
	if position is Vector2:
		_spatial = Spatial.SPATIAL_2D
	elif position is Vector3:
		_spatial = Spatial.SPATIAL_3D
	else:
		push_error("AudioEventInstance.set_position() expects a Vector2 or Vector3.")
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


# --- driven by the AudioEvents singleton ---------------------------------------

func _process(delta: float) -> void:
	_sync_pause()
	if _applied_paused:
		return
	_time += delta
	for state: AudioEventParameter.State in _params.values():
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

	if _attached:
		var node = _attached.get_ref()
		if node and node.is_inside_tree():
			_position = node.global_position

	var volume_factor := _automation(AudioEventAutomation.Target.VOLUME)
	var pitch_factor := _automation(AudioEventAutomation.Target.PITCH)
	for voice in _voices:
		_apply(voice, volume_factor, pitch_factor)

	if _state == State.PLAYING and _voices.is_empty() and _pending.is_empty():
		_finish_stop()


## Current linear volume before automation and instrument gain; used for stealing.
func _get_level() -> float:
	return db_to_linear(_event.volume_db) * volume * _env_level


func _schedule(instrument: AudioEventInstrument) -> bool:
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


func _trigger(instrument: AudioEventInstrument) -> void:
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

	_manager._voice_root.add_child(player)
	_apply(voice, _automation(AudioEventAutomation.Target.VOLUME), _automation(AudioEventAutomation.Target.PITCH))
	player.finished.connect(_on_voice_finished.bind(voice))
	player.play()
	player.stream_paused = _applied_paused


func _on_voice_finished(voice: Voice) -> void:
	if voice.instrument.loop and _state == State.PLAYING:
		voice.player.play()
		return
	_voices.erase(voice)
	voice.player.queue_free()
	if _state == State.PLAYING and _event.sheet_mode == AudioEvent.SheetMode.CONSECUTIVE:
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


func _automation(target: AudioEventAutomation.Target) -> float:
	var factor := 1.0
	for automation in _event.automations:
		if automation == null or automation.target != target:
			continue
		var state: AudioEventParameter.State
		if automation.global:
			state = _manager._get_global_state(automation.parameter)
		else:
			state = _params.get(automation.parameter.to_lower())
		if state:
			factor *= automation.evaluate(state.def, state.value)
	return factor


func _sync_pause() -> void:
	var paused: bool = _paused or _manager._is_bus_paused(_bus)
	if paused == _applied_paused:
		return
	_applied_paused = paused
	for voice in _voices:
		voice.player.stream_paused = paused


func _finish_stop() -> void:
	_clear_voices()
	_pending.clear()
	_state = State.STOPPED
	_manager._register_stop(self)
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
