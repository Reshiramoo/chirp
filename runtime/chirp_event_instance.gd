@tool
@icon("res://addons/chirp/icons/event.svg")
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
## The playhead passed a MARKER on a TIMELINE event.
signal timeline_marker(marker_name: String, position: float)
## The playhead crossed a beat. Bars and beats count from 1, starting at the current TEMPO marker.
signal timeline_beat(bar: int, beat: int, position: float, tempo: float, time_signature: Vector2i)
## A PROGRAMMER instrument is about to play and asks for its sound. Emitted synchronously:
## call set_programmer_sound(key, stream) from the handler to supply it.
signal programmer_sound_requested(key: String, instrument: ChirpInstrument)

enum State { STOPPED, PLAYING, STOPPING }

enum Spatial { NONE, SPATIAL_2D, SPATIAL_3D }

const Timeline := preload("timeline.gd")
## How far (seconds) a voice may drift from the playhead after a jump before it is re-seeked.
const RESYNC_TOLERANCE := 0.05
## AudioStreamPlayer2D.max_distance while Chirp applies the roll-off (effectively no limit).
const ROLLOFF_FAR := 1.0e7

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
var _programmer_sounds := {} # programmer key -> AudioStream; shared with nested instances
var _send_to: StringName # where the output goes: the event's bus, or a parent event's output
var _fx_bus: StringName = &"" # pool bus carrying the event's effects while playing
var _fx_effects: Array[AudioEffect] = [] # the effects on _fx_bus (this instance's, or the event's shared ones)
var _panner: AudioEffectPanner # appended to the effects when the event has PAN automation

# Timeline playback (TIMELINE events only)
var _timeline: Timeline
var _playhead := 0.0
var _sustain: Timeline.Mark # the sustain point holding the playhead, if any
var _released_sustains := {} # Mark -> true: let past for the rest of this pass
var _jump := {} # pending (quantized) transition: {time, target: Mark}
var _jumped := false # the playhead jumped this frame
var _entry_voices := {} # timeline / parameter sheet instrument index -> Voice
var _entry_done := {} # instrument index -> true once triggered (until it leaves its range)
var _quantized := {} # timeline entry index -> playhead time a quantized instrument waits for


class Voice:
	var player # AudioStreamPlayer, AudioStreamPlayer2D or AudioStreamPlayer3D (SOUND, PROGRAMMER)
	var child: ChirpEventInstance # EVENT
	var silence_left := 0.0 # SILENCE
	var scattered: Array[Scattered] = [] # SCATTERER: sounds playing
	var next_spawn := 0.0 # SCATTERER: seconds until the next spawn
	var spawned := 0 # SCATTERER: sounds started so far
	var spawning := true # SCATTERER: false once spawn_total is reached or it was cut
	var gain := 1.0
	var pitch := 1.0
	var instrument: ChirpInstrument
	var entry := -1 # timeline entry index, -1 when not following the timeline
	var detached := false # left to play to its end, no longer controlled
	var fade := 1.0 # PARAMETER sheets: crossfade gain, kept at its last value once detached
	var start_shift := 0.0 # seconds the sound runs ahead of its timeline position (start offsets)


## One sound started by a SCATTERER voice.
class Scattered:
	var player
	var gain := 1.0
	var pitch := 1.0
	var offset: Variant = null # Vector2 / Vector3 from the event's position, null when not spatial


class Pending:
	var instrument: ChirpInstrument
	var time_left := 0.0


func _init(chirp: Node, event: ChirpEvent, bus: StringName) -> void:
	_chirp = chirp
	_event = event
	_bus = bus
	_send_to = bus
	for definition in event.parameters:
		if definition:
			_params[definition.name.to_lower()] = ChirpParameter.State.new(definition)
			_has_built_ins = _has_built_ins or definition.built_in != ChirpParameter.BuiltIn.NONE
	if event.sheet_mode == ChirpEvent.SheetMode.TIMELINE:
		_timeline = Timeline.new(event)


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
	if _fx_bus.is_empty() and _needs_effects():
		_acquire_effects()
	if _has_built_ins:
		_update_built_ins()
	match _event.sheet_mode:
		ChirpEvent.SheetMode.CONSECUTIVE:
			_next_consecutive = 0
			_schedule_next_consecutive()
		ChirpEvent.SheetMode.TIMELINE:
			_playhead = 0.0
			_reset_timeline_pass()
			_emit_timeline_events(-Timeline.EPSILON, 0.0)
			_sync_entries()
		ChirpEvent.SheetMode.PARAMETER:
			_entry_done.clear()
			_sync_sheet()
		_:
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


## Playhead position in seconds (TIMELINE events).
func get_timeline_position() -> float:
	return _playhead


## Moves the playhead (TIMELINE events), in seconds. Instruments follow it.
func set_timeline_position(position: float) -> void:
	if _timeline == null:
		push_warning("Chirp: set_timeline_position() needs a TIMELINE event.")
		return
	_jump_to(maxf(position, 0.0))
	if is_playing():
		_sync_entries()
		_jumped = false


## Supplies the sound for PROGRAMMER instruments with this [param key]. Kept for later triggers
## and shared with nested events. Pass null to forget it.
func set_programmer_sound(key: String, stream: AudioStream) -> void:
	if stream:
		_programmer_sounds[key] = stream
	else:
		_programmer_sounds.erase(key)


## Releases the sustain point currently holding the playhead.
func key_off() -> void:
	if _sustain:
		_released_sustains[_sustain] = true
		_sustain = null


## True while a sustain point is holding the playhead.
func is_sustaining() -> bool:
	return _sustain != null


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

	if _timeline:
		_advance_timeline(delta)
		_sync_entries()
	elif _event.sheet_mode == ChirpEvent.SheetMode.PARAMETER:
		_sync_sheet()
	for voice in _voices.duplicate():
		if not _voices.has(voice):
			continue # removed by an earlier voice this frame
		if voice.instrument.kind == ChirpInstrument.Kind.SILENCE:
			voice.silence_left -= delta
			if voice.silence_left <= 0.0:
				_on_voice_finished(voice)
			continue
		if voice.instrument.kind == ChirpInstrument.Kind.SCATTERER:
			_step_scatterer(voice, delta)
		if _voices.has(voice) and voice.entry == -1 and not voice.detached \
				and not _instrument_condition(voice.instrument):
			_cut(voice)

	if _state == State.STOPPING:
		_release_time += delta
		var release := _event.envelope.release
		_env_level = _release_from * (1.0 - _release_time / release)
		if _env_level <= 0.0:
			_finish_stop()
			return
	elif _event.envelope:
		_env_level = _event.envelope.level_at(_time)

	if not _fx_effects.is_empty():
		_apply_effect_automation()
	var volume_factor := _automation(ChirpAutomation.Target.VOLUME)
	var pitch_factor := _automation(ChirpAutomation.Target.PITCH)
	for voice in _voices:
		_apply(voice, volume_factor, pitch_factor)

	if _state == State.PLAYING and _voices.is_empty() and _pending.is_empty() \
			and not _event.persistent and _timeline_finished():
		_finish_stop()


## Current linear volume before automation and instrument gain; used for stealing.
func _get_level() -> float:
	return db_to_linear(_event.volume_db) * volume * _env_level


# --- action and consecutive sheets -------------------------------------------------

func _schedule(instrument: ChirpInstrument) -> bool:
	if randf() * 100.0 >= instrument.probability or not _instrument_condition(instrument):
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


# --- timeline ------------------------------------------------------------------------

func _reset_timeline_pass() -> void:
	_sustain = null
	_released_sustains.clear()
	_jump = {}
	_jumped = false
	_entry_voices.clear()
	_entry_done.clear()
	_quantized.clear()


func _timeline_finished() -> bool:
	if _timeline == null:
		return true
	return _playhead >= _timeline.length and _sustain == null and _jump.is_empty()


## Moves the playhead forward by [param delta], handling sustain points, loop regions
## and transitions. Several jumps can happen in one frame.
func _advance_timeline(delta: float) -> void:
	_jumped = false
	if _sustain:
		if _marker_condition(_sustain.marker):
			return
		_released_sustains[_sustain] = true
		_sustain = null
	var remaining := delta
	for _i in 32: # guards against transitions that jump into themselves
		if remaining <= 0.0:
			return
		var from := _playhead
		var to := from + remaining
		_schedule_transition(from, to)
		var stop_at := to
		var action := ""
		var target: Timeline.Mark = null
		for mark in _timeline.marks:
			match mark.marker.kind:
				ChirpMarker.Kind.SUSTAIN_POINT:
					if mark.time > from and _earliest(mark.time, stop_at, action) \
							and not _released_sustains.has(mark) and _marker_condition(mark.marker):
						stop_at = mark.time
						action = "sustain"
						target = mark
				ChirpMarker.Kind.LOOP_REGION:
					if mark.end > mark.time and mark.end > from and _earliest(mark.end, stop_at, action) \
							and _marker_condition(mark.marker):
						stop_at = mark.end
						action = "loop"
						target = mark
		if not _jump.is_empty() and _jump.time >= from and _jump.time <= stop_at:
			stop_at = _jump.time
			action = "jump"
		_emit_timeline_events(from, stop_at)
		_playhead = stop_at
		remaining -= stop_at - from
		match action:
			"sustain":
				_sustain = target
				return
			"loop":
				if randf() * 100.0 < target.marker.probability:
					_jump_to(target.time)
			"jump":
				_jump_to(_jump.target.time)


## True when [param time] comes before the current stop point (or ties with the end of the frame).
static func _earliest(time: float, stop_at: float, action: String) -> bool:
	return time < stop_at or (time == stop_at and action.is_empty())


## Arms a jump for the first transition reached in (from, to] whose condition holds.
func _schedule_transition(from: float, to: float) -> void:
	if not _jump.is_empty():
		return
	for mark in _timeline.marks:
		var reached := -1.0
		match mark.marker.kind:
			ChirpMarker.Kind.TRANSITION:
				if mark.time > from and mark.time <= to:
					reached = mark.time
			ChirpMarker.Kind.TRANSITION_REGION:
				if mark.time <= to and mark.end > from:
					reached = maxf(from, mark.time)
		if reached < 0.0 or not _marker_condition(mark.marker) or randf() * 100.0 >= mark.marker.probability:
			continue
		var destination: Timeline.Mark = _timeline.destinations.get(mark.marker.destination)
		if destination == null:
			_chirp._warn_once("dest:%s:%s" % [_event.resource_path, mark.marker.destination],
				"Chirp: no DESTINATION marker named '%s'." % mark.marker.destination)
			continue
		_jump = {time = _timeline.next_boundary(reached, mark.marker.quantization), target = destination}
		return


func _jump_to(time: float) -> void:
	_playhead = time
	_jumped = true
	_jump = {}
	_sustain = null
	_released_sustains.clear()


## Emits timeline_marker and timeline_beat for everything in (from, to], in order.
func _emit_timeline_events(from: float, to: float) -> void:
	if to <= from:
		return
	var events: Array[Dictionary] = []
	for mark in _timeline.marks:
		if mark.marker.kind == ChirpMarker.Kind.MARKER and mark.time > from and mark.time <= to:
			events.append({time = mark.time, marker = mark.marker})
	events.append_array(_timeline.beats_between(from, to))
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time < b.time)
	for event in events:
		if event.has("marker"):
			timeline_marker.emit(event.marker.name, event.time)
		else:
			var tempo: ChirpMarker = event.tempo.marker
			timeline_beat.emit(event.bar, event.beat, event.time, tempo.bpm,
				Vector2i(tempo.beats_per_bar, tempo.beat_unit))


## Starts, stops and re-seeks instruments so they match the playhead.
func _sync_entries() -> void:
	if _jumped:
		_quantized.clear() # boundaries worked out before the jump are stale
	for entry in _timeline.entries:
		var inside := _playhead >= entry.start and _playhead < entry.end
		var holds := _instrument_condition(entry.instrument)
		var voice: Voice = _entry_voices.get(entry.index)
		if voice:
			if not inside:
				if entry.instrument.async_playback \
						or (_jumped and entry.instrument.cut_behavior == ChirpInstrument.CutBehavior.PLAY_TO_END):
					_detach(voice)
				else:
					_stop_voice(voice)
			elif not holds:
				_cut(voice)
			elif _jumped and not entry.instrument.async_playback \
					and entry.instrument.quantization == ChirpMarker.Quantization.NONE:
				_resync(voice, _playhead - entry.start)
		if _entry_voices.has(entry.index):
			continue
		if not inside or _jumped:
			_entry_done.erase(entry.index)
		if not (inside and holds and _state == State.PLAYING) or _entry_done.has(entry.index):
			_quantized.erase(entry.index)
			continue
		var offset := _playhead - entry.start
		if entry.instrument.quantization != ChirpMarker.Quantization.NONE:
			# Wait for the next beat or bar line, then play from the beginning.
			# (A line past the region's end is never reached: leaving the region cancels the wait.)
			if not _quantized.has(entry.index):
				_quantized[entry.index] = _timeline.next_boundary(_playhead, entry.instrument.quantization)
			if _playhead < _quantized[entry.index] - Timeline.EPSILON:
				continue
			_quantized.erase(entry.index)
			offset = 0.0
		_entry_done[entry.index] = true
		if randf() * 100.0 < entry.instrument.probability:
			var started_voice := _trigger(entry.instrument, offset)
			if started_voice:
				started_voice.entry = entry.index
				_entry_voices[entry.index] = started_voice


func _resync(voice: Voice, expected: float) -> void:
	if voice.player:
		var length: float = voice.player.stream.get_length()
		if voice.start_shift > 0.0:
			if expected >= length and length > 0.0:
				_stop_voice(voice)
				return
			expected = _shifted(expected, voice.start_shift, length)
		var drift: float = absf(voice.player.get_playback_position() - expected)
		if length > 0.0:
			drift = minf(drift, absf(length - drift)) # a looping stream may have wrapped
		if drift > RESYNC_TOLERANCE:
			if length > 0.0 and expected >= length:
				_stop_voice(voice)
			else:
				voice.player.seek(expected)
	elif voice.child and voice.child._timeline:
		voice.child.set_timeline_position(expected)
	elif voice.instrument.kind == ChirpInstrument.Kind.SILENCE:
		voice.silence_left = voice.instrument.duration - expected


# --- parameter sheet -----------------------------------------------------------------

## Starts and stops instruments so they match the sheet parameter's value.
func _sync_sheet() -> void:
	var state := _sheet_state()
	for i in _event.instruments.size():
		var instrument := _event.instruments[i]
		if instrument == null:
			continue
		var inside := state != null and _sheet_inside(instrument, state)
		var holds := _instrument_condition(instrument)
		var voice: Voice = _entry_voices.get(i)
		if voice:
			if not inside:
				if instrument.async_playback or instrument.cut_behavior == ChirpInstrument.CutBehavior.PLAY_TO_END:
					_detach(voice)
				else:
					_stop_voice(voice)
			elif not holds:
				_cut(voice)
			if _entry_voices.has(i):
				continue
		if not inside:
			_entry_done.erase(i)
		elif holds and _state == State.PLAYING and not _entry_done.has(i):
			_entry_done[i] = true
			if randf() * 100.0 < instrument.probability:
				var started_voice := _trigger(instrument)
				if started_voice:
					started_voice.entry = i
					_entry_voices[i] = started_voice
					_apply(started_voice, _automation(ChirpAutomation.Target.VOLUME),
						_automation(ChirpAutomation.Target.PITCH))


## The sheet parameter's live state (local first, then global), or null with a warning.
func _sheet_state() -> ChirpParameter.State:
	var parameter_name := _event.sheet_parameter
	var state: ChirpParameter.State = _params.get(parameter_name.to_lower())
	if state == null:
		state = _chirp.parameters._get_state(parameter_name)
	if state == null:
		_chirp._warn_once("sheet:%s:%s" % [_event.resource_path, parameter_name],
			"Chirp: parameter sheet uses unknown parameter '%s'." % parameter_name)
	return state


## [start, end) on the parameter's axis; a range reaching the parameter's maximum includes it.
func _sheet_inside(instrument: ChirpInstrument, state: ChirpParameter.State) -> bool:
	var top := state.def.get_max()
	var end := instrument.start + instrument.length if instrument.length > 0.0 else INF
	if state.value < instrument.start - Timeline.EPSILON:
		return false
	return state.value < end - Timeline.EPSILON or end >= top - Timeline.EPSILON and state.value <= end + Timeline.EPSILON


## Crossfade gain from the instrument's fade_in / fade_out at the sheet parameter's value.
func _sheet_fade(instrument: ChirpInstrument) -> float:
	var state := _sheet_state()
	if state == null:
		return 1.0
	var fade := 1.0
	if instrument.fade_in > 0.0:
		fade *= clampf((state.value - instrument.start) / instrument.fade_in, 0.0, 1.0)
	if instrument.fade_out > 0.0 and instrument.length > 0.0:
		fade *= clampf((instrument.start + instrument.length - state.value) / instrument.fade_out, 0.0, 1.0)
	return fade


# --- conditions ----------------------------------------------------------------------

func _instrument_condition(instrument: ChirpInstrument) -> bool:
	return _condition(instrument.condition_parameter, instrument.condition_min, instrument.condition_max)


func _marker_condition(marker: ChirpMarker) -> bool:
	return _condition(marker.condition_parameter, marker.condition_min, marker.condition_max)


## True when [param parameter_name] (local first, then global) is within [lo, hi]. Empty = true.
func _condition(parameter_name: String, lo: float, hi: float) -> bool:
	if parameter_name.is_empty():
		return true
	var state: ChirpParameter.State = _params.get(parameter_name.to_lower())
	if state == null:
		state = _chirp.parameters._get_state(parameter_name)
	if state == null:
		_chirp._warn_once("cond:%s:%s" % [_event.resource_path, parameter_name],
			"Chirp: condition uses unknown parameter '%s'; treating it as met." % parameter_name)
		return true
	return state.value >= lo - Timeline.EPSILON and state.value <= hi + Timeline.EPSILON


# --- voices ----------------------------------------------------------------------------

## Starts [param instrument], [param offset] seconds into its sound. Returns null if nothing plays.
func _trigger(instrument: ChirpInstrument, offset := 0.0) -> Voice:
	var voice := Voice.new()
	voice.instrument = instrument
	if instrument.kind == ChirpInstrument.Kind.SCATTERER:
		# Randomized per scattered sound instead (see _spawn).
		voice.gain = 1.0
		voice.pitch = pow(2.0, instrument.pitch_semitones / 12.0)
	else:
		voice.gain = db_to_linear(-randf() * instrument.random_volume_db)
		var detune := randf_range(-instrument.random_pitch_semitones, instrument.random_pitch_semitones)
		voice.pitch = pow(2.0, (instrument.pitch_semitones + detune) / 12.0)
	match instrument.kind:
		ChirpInstrument.Kind.SILENCE:
			voice.silence_left = instrument.duration - offset
			if voice.silence_left <= 0.0:
				return null
			_voices.append(voice)
		ChirpInstrument.Kind.EVENT:
			if not _start_child(voice, offset):
				return null
		ChirpInstrument.Kind.SCATTERER:
			if not _start_scatterer(voice):
				return null
		ChirpInstrument.Kind.PROGRAMMER:
			voice.start_shift = _start_shift(instrument)
			if not _start_player(voice, offset, _programmer_stream(instrument)):
				return null
		_:
			voice.start_shift = _start_shift(instrument)
			if not _start_player(voice, offset, instrument.pick_stream()):
				return null
	return voice


func _start_player(voice: Voice, offset: float, stream: AudioStream) -> bool:
	if stream == null:
		return false
	if offset > 0.0 and stream.get_length() > 0.0 and offset >= stream.get_length():
		return false
	var player = _new_player(stream)
	voice.player = player
	_voices.append(voice)
	_apply(voice, _automation(ChirpAutomation.Target.VOLUME), _automation(ChirpAutomation.Target.PITCH))
	player.finished.connect(_on_voice_finished.bind(voice))
	player.play(_shifted(offset, voice.start_shift, stream.get_length()))
	player.stream_paused = _applied_paused
	return true


## A player of the right kind for this instance (plain, 2D or 3D), on its bus, in the tree.
func _new_player(stream: AudioStream) -> Node:
	var player # AudioStreamPlayer, AudioStreamPlayer2D or AudioStreamPlayer3D
	match _spatial:
		Spatial.SPATIAL_2D:
			var player_2d := AudioStreamPlayer2D.new()
			if _uses_rolloff():
				# Chirp applies the roll-off itself; keep Godot's attenuation out of the way.
				player_2d.max_distance = ROLLOFF_FAR
				player_2d.attenuation = 1.0
			else:
				player_2d.max_distance = _attenuation.get("max_distance", _event.max_distance_2d)
				player_2d.attenuation = _attenuation.get("attenuation", _event.attenuation_2d)
			player = player_2d
		Spatial.SPATIAL_3D:
			var player_3d := AudioStreamPlayer3D.new()
			if _uses_rolloff():
				player_3d.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
				player_3d.max_distance = 0.0
			else:
				player_3d.unit_size = _attenuation.get("unit_size", _event.unit_size_3d)
				player_3d.max_distance = _attenuation.get("max_distance", _event.max_distance_3d)
			player = player_3d
		_:
			player = AudioStreamPlayer.new()
	player.stream = stream
	player.bus = _output_bus()
	_chirp._voice_root.add_child(player)
	return player


## A trigger's start offset: the fixed one plus a random extra.
static func _start_shift(instrument: ChirpInstrument) -> float:
	return instrument.start_offset + randf() * instrument.random_start_offset


## [param position] moved on by [param shift], wrapped into a sound of [param length] seconds.
static func _shifted(position: float, shift: float, length: float) -> float:
	if shift <= 0.0:
		return position
	return fposmod(position + shift, length) if length > 0.0 else position + shift


## PROGRAMMER: asks game code for the sound (signal, then this instance's sounds, then the
## Chirp.events.programmer_sound_provider). Null when nobody supplies one.
func _programmer_stream(instrument: ChirpInstrument) -> AudioStream:
	var key := instrument.programmer_key
	programmer_sound_requested.emit(key, instrument)
	var stream: AudioStream = _programmer_sounds.get(key)
	if stream == null and _chirp.events.programmer_sound_provider.is_valid():
		var provided: Variant = _chirp.events.programmer_sound_provider.call(key, self)
		stream = provided as AudioStream
	if stream == null:
		_chirp._warn_once("programmer:%s:%s" % [_event.resource_path, key],
			"Chirp: no sound supplied for programmer instrument '%s'." % key)
	return stream


# --- scatterer ----------------------------------------------------------------------

func _start_scatterer(voice: Voice) -> bool:
	if voice.instrument.streams.filter(func(s: AudioStream) -> bool: return s != null).is_empty():
		return false
	_voices.append(voice)
	_step_scatterer(voice, 0.0) # the first sound plays straight away
	return _voices.has(voice)


## Counts down to the next spawn and spawns; ends the voice once it is done spawning and silent.
func _step_scatterer(voice: Voice, delta: float) -> void:
	var instrument := voice.instrument
	voice.next_spawn -= delta
	while voice.spawning and voice.next_spawn <= 0.0:
		if instrument.spawn_total > 0 and voice.spawned >= instrument.spawn_total:
			voice.spawning = false
			break
		if instrument.polyphony <= 0 or voice.scattered.size() < instrument.polyphony:
			_spawn(voice)
		voice.next_spawn += maxf(randf_range(instrument.spawn_interval_min,
			maxf(instrument.spawn_interval_max, instrument.spawn_interval_min)), 0.01)
	if not voice.spawning and voice.scattered.is_empty():
		_on_voice_finished(voice)


func _spawn(voice: Voice) -> void:
	var instrument := voice.instrument
	var stream := instrument.pick_stream()
	if stream == null:
		return
	var sound := Scattered.new()
	sound.gain = db_to_linear(-randf() * instrument.random_volume_db)
	sound.pitch = pow(2.0, randf_range(-instrument.random_pitch_semitones, instrument.random_pitch_semitones) / 12.0)
	sound.offset = _scatter_offset(instrument)
	sound.player = _new_player(stream)
	voice.scattered.append(sound)
	voice.spawned += 1
	_apply(voice, _automation(ChirpAutomation.Target.VOLUME), _automation(ChirpAutomation.Target.PITCH))
	sound.player.finished.connect(_on_scattered_finished.bind(voice, sound))
	sound.player.play(_shifted(0.0, _start_shift(instrument), stream.get_length()))
	sound.player.stream_paused = _applied_paused


## A random offset between the instrument's scatter distances, in any direction.
func _scatter_offset(instrument: ChirpInstrument) -> Variant:
	var distance := randf_range(instrument.scatter_distance_min,
		maxf(instrument.scatter_distance_max, instrument.scatter_distance_min))
	match _spatial:
		Spatial.SPATIAL_2D:
			return Vector2.RIGHT.rotated(randf() * TAU) * distance
		Spatial.SPATIAL_3D:
			var direction := Vector3.ZERO
			while direction.length_squared() < 0.0001 or direction.length_squared() > 1.0:
				direction = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
			return direction.normalized() * distance
	return null


func _on_scattered_finished(voice: Voice, sound: Scattered) -> void:
	voice.scattered.erase(sound)
	if is_instance_valid(sound.player):
		sound.player.queue_free()
	if _voices.has(voice) and not voice.spawning and voice.scattered.is_empty():
		_on_voice_finished(voice)


func _start_child(voice: Voice, offset: float) -> bool:
	var nested := voice.instrument.event
	if nested == null or nested == _event:
		return false
	var child: ChirpEventInstance = _chirp.events.create_instance(nested)
	if child == null:
		return false
	var node = _attached.get_ref() if _attached else null
	if node:
		child.attach_to(node)
	elif _position != null:
		child.set_position(_position)
	child._attenuation = _attenuation
	child._send_to = _output_bus() # nested events play into this event's effects
	child._programmer_sounds = _programmer_sounds
	child.programmer_sound_requested.connect(programmer_sound_requested.emit)
	voice.child = child
	_link_parameters(child)
	child.stopped.connect(_on_voice_finished.bind(voice))
	child.start()
	if not child.is_playing():
		return false
	if offset > 0.0 and child._timeline:
		child.set_timeline_position(offset)
	child.release()
	child.set_paused(_applied_paused)
	_voices.append(voice)
	_apply(voice, _automation(ChirpAutomation.Target.VOLUME), _automation(ChirpAutomation.Target.PITCH))
	return true


## Copies this instance's parameter values to same-named parameters of a nested event.
func _link_parameters(child: ChirpEventInstance) -> void:
	for parameter_name: String in child._params:
		var own: ChirpParameter.State = _params.get(parameter_name)
		var theirs: ChirpParameter.State = child._params[parameter_name]
		if own and theirs.def.built_in == ChirpParameter.BuiltIn.NONE:
			theirs.set_target(own.value, true)


func _on_voice_finished(voice: Voice) -> void:
	if not _voices.has(voice):
		return
	if voice.player and voice.instrument.loop and not voice.detached and _state == State.PLAYING:
		voice.player.play()
		return
	_remove_voice(voice)
	if voice.player:
		voice.player.queue_free()
	if _state == State.PLAYING and _event.sheet_mode == ChirpEvent.SheetMode.CONSECUTIVE and not voice.detached:
		_schedule_next_consecutive()


## Applies the instrument's cut behaviour: stop now, or let it finish on its own.
func _cut(voice: Voice) -> void:
	if voice.instrument.cut_behavior == ChirpInstrument.CutBehavior.PLAY_TO_END:
		_detach(voice)
	else:
		_stop_voice(voice)


func _detach(voice: Voice) -> void:
	_entry_voices.erase(voice.entry)
	voice.entry = -1
	voice.detached = true
	voice.spawning = false # a detached scatterer lets its sounds finish but starts no more
	if voice.instrument.kind == ChirpInstrument.Kind.SCATTERER and voice.scattered.is_empty():
		_on_voice_finished(voice)


func _stop_voice(voice: Voice) -> void:
	_remove_voice(voice)
	if voice.player and is_instance_valid(voice.player):
		voice.player.stop()
		voice.player.queue_free()
	elif voice.child:
		voice.child.stop(false)
	for sound in voice.scattered:
		if is_instance_valid(sound.player):
			sound.player.stop()
			sound.player.queue_free()
	voice.scattered.clear()


func _remove_voice(voice: Voice) -> void:
	_voices.erase(voice)
	if voice.entry >= 0 and _entry_voices.get(voice.entry) == voice:
		_entry_voices.erase(voice.entry)


func _clear_voices() -> void:
	for voice in _voices.duplicate():
		_stop_voice(voice)
	_entry_voices.clear()


func _apply(voice: Voice, volume_factor: float, pitch_factor: float) -> void:
	# The instrument's volume is read live, so the editor's volume knob is heard while playing.
	var gain: float = _get_level() * voice.gain * db_to_linear(voice.instrument.volume_db) * volume_factor \
		* _chirp._audition_gain(_event, voice.instrument)
	if _event.sheet_mode == ChirpEvent.SheetMode.PARAMETER:
		if voice.entry >= 0:
			voice.fade = _sheet_fade(voice.instrument)
		gain *= voice.fade
	var final_pitch := maxf(_event.pitch_scale * pitch * voice.pitch * pitch_factor, 0.01)
	if voice.player:
		_apply_player(voice.player, gain, final_pitch, null)
	elif voice.child:
		voice.child.volume = gain
		voice.child.pitch = final_pitch
		_link_parameters(voice.child)
	for sound in voice.scattered:
		if is_instance_valid(sound.player):
			_apply_player(sound.player, gain * sound.gain, maxf(final_pitch * sound.pitch, 0.01), sound.offset)


func _apply_player(player, gain: float, final_pitch: float, offset: Variant) -> void:
	if _position is Vector2 and player is AudioStreamPlayer2D:
		player.global_position = _position + (offset if offset is Vector2 else Vector2.ZERO)
		if _uses_rolloff():
			gain *= _rolloff_at(player.global_position.distance_to(_chirp.events._listener_2d.origin))
	elif _position is Vector3 and player is AudioStreamPlayer3D:
		player.global_position = _position + (offset if offset is Vector3 else Vector3.ZERO)
		if _uses_rolloff():
			gain *= _rolloff_at(player.global_position.distance_to(_chirp.events._listener_3d.origin))
	player.volume_db = linear_to_db(gain) if gain > 0.00001 else -80.0
	player.pitch_scale = final_pitch


func _uses_rolloff() -> bool:
	return _event.rolloff != ChirpEvent.Rolloff.GODOT and _spatial != Spatial.NONE


## Min and max distance for Chirp's roll-off: the event's, or an attenuation override's
## (3D unit_size and max_distance, 2D max_distance).
func _rolloff_range() -> Vector2:
	var near: float = _attenuation.get("unit_size", _event.min_distance)
	var far: float = _attenuation.get("max_distance", 0.0)
	return Vector2(near, far if far > 0.0 else _event.max_distance)


func _rolloff_at(distance: float) -> float:
	var distances := _rolloff_range()
	return _event.rolloff_gain(distance, distances.x, distances.y)


func _automation(target: ChirpAutomation.Target) -> float:
	var factor := 1.0
	for automation in _event.automations:
		if automation == null or automation.target != target:
			continue
		if automation.source == ChirpAutomation.Source.TIMELINE:
			if _timeline:
				factor *= automation.value_at(_timeline.to_units(_playhead))
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
			if modulator.tempo_sync:
				factor *= modulator.factor_at_beat(_timeline.beats_at(_playhead) if _timeline else _time * 2.0, _lfo_seed)
			else:
				factor *= modulator.factor(_time, _lfo_seed)
	return factor


# --- parameters & 3D ----------------------------------------------------------------

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
	if _event.rolloff != ChirpEvent.Rolloff.GODOT:
		var distances := _rolloff_range()
		min_distance = distances.x
		max_distance = distances.y
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


# --- effects --------------------------------------------------------------------------

## Where players (and nested events) send their audio: the effect bus, else _send_to.
func _output_bus() -> StringName:
	return _fx_bus if not _fx_bus.is_empty() else _send_to


func _needs_effects() -> bool:
	return not _event.effects.is_empty() or _has_automation(ChirpAutomation.Target.PAN)


func _has_automation(target: ChirpAutomation.Target) -> bool:
	for automation in _event.automations:
		if automation and automation.target == target:
			return true
	return false


## Copies of the event's effects (so automation never edits the resource), plus a panner if needed.
func _make_effects() -> Array[AudioEffect]:
	var effects: Array[AudioEffect] = []
	for effect in _event.effects:
		# An empty slot becomes a 0 dB amplify, so effect indices keep matching ChirpEvent.effects.
		effects.append(effect.duplicate() if effect else AudioEffectAmplify.new())
	if _has_automation(ChirpAutomation.Target.PAN):
		effects.append(AudioEffectPanner.new())
	return effects


func _acquire_effects() -> void:
	if _event.effect_scope == ChirpEvent.EffectScope.EVENT:
		var shared: Dictionary = _chirp.mixer._acquire_event_effects(_event, _send_to, _make_effects)
		if shared.is_empty():
			return
		_fx_bus = shared.bus
		_fx_effects = shared.effects
	else:
		var effects := _make_effects()
		_fx_bus = _chirp.mixer._acquire_effect_bus(_send_to, effects)
		if _fx_bus.is_empty():
			return
		_fx_effects = effects
	_panner = _fx_effects[-1] as AudioEffectPanner if not _fx_effects.is_empty() else null
	_apply_effect_automation()


func _release_effects() -> void:
	if _fx_bus.is_empty():
		return
	if _event.effect_scope == ChirpEvent.EffectScope.EVENT:
		_chirp.mixer._release_event_effects(_event)
	else:
		_chirp.mixer._release_effect_bus(_fx_bus)
	_fx_bus = &""
	_fx_effects = []
	_panner = null


## PAN and EFFECT automations set their property on this instance's effects.
func _apply_effect_automation() -> void:
	for automation in _event.automations:
		if automation == null or automation.target < ChirpAutomation.Target.PAN:
			continue
		var value: Variant = _automation_value(automation)
		if value == null:
			continue
		if automation.target == ChirpAutomation.Target.PAN:
			if _panner:
				_panner.pan = clampf(value, -1.0, 1.0)
		elif automation.effect_index >= 0 and automation.effect_index < _event.effects.size():
			var effect := _fx_effects[automation.effect_index] if automation.effect_index < _fx_effects.size() else null
			if effect and not automation.effect_property.is_empty():
				var current: Variant = effect.get(automation.effect_property)
				if current is int:
					effect.set(automation.effect_property, roundi(value))
				elif current is float:
					effect.set(automation.effect_property, value)
				else:
					_chirp._warn_once("fxprop:%s:%s" % [_event.resource_path, automation.effect_property],
						"Chirp: %s has no numeric property '%s'." % [effect.get_class(), automation.effect_property])


## The raw value an automation gives right now, or null when it has nothing to give.
func _automation_value(automation: ChirpAutomation) -> Variant:
	if automation.source == ChirpAutomation.Source.TIMELINE:
		if _timeline == null or automation.points.is_empty():
			return null
		return automation.value_at(_timeline.to_units(_playhead))
	var state: ChirpParameter.State
	if automation.global:
		state = _chirp.parameters._get_state(automation.parameter)
	else:
		state = _params.get(automation.parameter.to_lower())
	if state == null or automation.curve == null:
		return null
	return automation.evaluate(state.def, state.value)


# --- lifecycle ---------------------------------------------------------------------

func _sync_pause() -> void:
	var paused: bool = _paused or _chirp.mixer._is_bus_paused(_bus)
	if paused == _applied_paused:
		return
	_applied_paused = paused
	for voice in _voices:
		if voice.player:
			voice.player.stream_paused = paused
		elif voice.child:
			voice.child.set_paused(paused)
		for sound in voice.scattered:
			if is_instance_valid(sound.player):
				sound.player.stream_paused = paused


func _finish_stop() -> void:
	_clear_voices()
	_pending.clear()
	_release_effects()
	if _timeline:
		_reset_timeline_pass()
	_entry_done.clear()
	_state = State.STOPPED
	_chirp.events._register_stop(self)
	stopped.emit()
	if _released:
		_destroy()


func _destroy() -> void:
	if _destroyed:
		return
	_destroyed = true
	destroyed.emit()
