@tool
extends Node
## Chirp autoload: the runtime entry point. Each area lives in its own module:
##
## [codeblock]
## Chirp.play_one_shot("event:/sfxs/coin")          # shortcuts for the common calls
## var music := Chirp.create_instance("event:/bgms/main")
## music.start()
## Chirp.parameters.set_value("Danger", 0.8)        # global parameters
## Chirp.mixer.start_snapshot("Paused")             # buses, VCAs, snapshots, pausing
## Chirp.events.get_active_instances()              # event registry and instances
## [/codeblock]

const Events := preload("modules/events.gd")
const Mixer := preload("modules/mixer.gd")
const Parameters := preload("modules/parameters.gd")

const SETTING_CONFIG := "chirp/config"
const SETTING_SOUND_DIRECTORIES := "chirp/sound_directories"
const SETTING_PAUSE_IN_BACKGROUND := "chirp/pause_on_app_background"
const DEFAULT_CONFIG := "res://audio/chirp_config.tres"
const DEFAULT_SOUND_DIRECTORIES := {"res://audio": ""}

var events: Events
var mixer: Mixer
var parameters: Parameters
## Global parameters, VCAs, snapshots and bus automation, from the "chirp/config" project setting.
var config: ChirpConfig

## Set by the editor plugin on its own copy used to audition sounds in the editor.
## The project's Chirp autoload stays idle in the editor.
var preview := false
## Extra seconds between mixing and hearing, on top of what the audio driver reports, for the
## rhythm helpers (ChirpEventInstance.get_audible_position(), call_on_beat()). Let players
## calibrate it (Bluetooth headphones add 100-300 ms); negative values are allowed.
var latency_offset := 0.0

## Emitted for every warning and error Chirp reports, also printed to the Output panel as usual:
## unknown events, buses, parameters or snapshots, missing destinations... The Chirp Event dock
## shows the editor preview's in its log.
signal warning_issued(message: String, is_error: bool)

const DEBUGGER_MESSAGE := "chirp:stats"
const DEBUGGER_INTERVAL := 0.25 # seconds between stats sent to the editor's Chirp profiler

var _voice_root: Node
var _debugger_in := 0.0
const MAX_TICK := 1.0 # seconds: a longer gap (the app was suspended) isn't played catch-up on
var _clock_usec := 0 # Time.get_ticks_usec() at the last frame, 0 to restart the clock
var _warned := {}
var _muted := {} # ChirpInstrument -> true (auditioning)
var _soloed := {} # ChirpInstrument -> true (auditioning)


## Seconds between Chirp mixing a sound and it being heard: the driver's output latency plus
## [member latency_offset].
func get_output_latency() -> float:
	return AudioServer.get_output_latency() + latency_offset


func _warn(message: String) -> void:
	push_warning(message)
	warning_issued.emit(message, false)


func _error(message: String) -> void:
	push_error(message)
	warning_issued.emit(message, true)


func _init() -> void:
	events = Events.new(self)
	mixer = Mixer.new(self)
	parameters = Parameters.new(self)


func _ready() -> void:
	if Engine.is_editor_hint() and not preview:
		set_process(false)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	mixer._remove_effect_buses() # left in a saved bus layout by an earlier run
	_voice_root = Node.new()
	_voice_root.name = "Voices"
	add_child(_voice_root)
	if preview:
		mixer.set_live(false)
	reload_settings()


## Reloads the "chirp/config" resource and rescans "chirp/sound_directories".
func reload_settings() -> void:
	var path: String = ProjectSettings.get_setting(SETTING_CONFIG, DEFAULT_CONFIG)
	var loaded: ChirpConfig = null
	if ResourceLoader.exists(path):
		loaded = load(path) as ChirpConfig
	apply_config(loaded if loaded else ChirpConfig.new())
	events.max_voices = ProjectSettings.get_setting(Events.SETTING_MAX_VOICES, 0)
	events.virtualize_below_db = ProjectSettings.get_setting(Events.SETTING_VIRTUALIZE_BELOW_DB,
		Events.DEFAULT_VIRTUALIZE_BELOW_DB)
	events.scan(ProjectSettings.get_setting(SETTING_SOUND_DIRECTORIES, DEFAULT_SOUND_DIRECTORIES))


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var elapsed := (now - _clock_usec) / 1000000.0 if _clock_usec > 0 else delta
	_clock_usec = now
	_tick(clampf(elapsed, 0.0, MAX_TICK))


## Advances Chirp by [param delta] seconds. _process() feeds it the real time since the last
## frame rather than Godot's delta, which is smoothed (application/run/delta_smoothing) and scaled
## by Engine.time_scale: the audio plays in real time, so timelines, beats and delays must too, or
## they slip a frame against the music after every hitch.
func _tick(delta: float) -> void:
	parameters._process(delta)
	events._process(delta)
	mixer._process(delta)
	if not preview and EngineDebugger.is_active():
		_debugger_in -= delta
		if _debugger_in <= 0.0:
			_debugger_in = DEBUGGER_INTERVAL
			EngineDebugger.send_message(DEBUGGER_MESSAGE, [get_stats()])


## What Chirp is doing right now, for the editor's profiler (Debugger → Chirp) or an in-game
## overlay: [code]{voices: {real, virtual, limit}, effect_buses: [used, total], instances: [{event,
## state, virtual, paused, voices, bus, position, level_db}], buses: [{name, volume_db, peak_db,
## duck_db}], snapshots: [{name, level}], parameters: {name: value}}[/code]. position is the
## timeline position in seconds, or -1 without a timeline.
func get_stats() -> Dictionary:
	var instances: Array[Dictionary] = []
	for instance in events.get_active_instances():
		var level := instance.get_audibility()
		instances.append({
			event = instance._label,
			state = "sustaining" if instance.is_sustaining() else ChirpEventInstance.State.keys()[instance.get_state()].to_lower(),
			virtual = instance.is_virtual(),
			paused = instance._applied_paused,
			voices = instance._player_count(),
			bus = String(instance._bus),
			position = instance.get_timeline_position() if instance._timeline else -1.0,
			level_db = linear_to_db(level) if level > 0.00001 else -100.0,
		})
	var buses: Array[Dictionary] = []
	for i in AudioServer.bus_count:
		var bus_name := AudioServer.get_bus_name(i)
		if bus_name.begins_with(Mixer.EFFECT_BUS_PREFIX):
			continue
		buses.append({
			name = bus_name,
			volume_db = AudioServer.get_bus_volume_db(i),
			peak_db = maxf(AudioServer.get_bus_peak_volume_left_db(i, 0), AudioServer.get_bus_peak_volume_right_db(i, 0)),
			duck_db = mixer.get_bus_duck_db(bus_name),
			muted = AudioServer.is_bus_mute(i),
		})
	var snapshots: Array[Dictionary] = []
	for snapshot in mixer.get_active_snapshots():
		snapshots.append({name = snapshot.get_snapshot().name, level = snapshot.get_level()})
	var values := {}
	for definition in config.global_parameters if config else []:
		if definition:
			values[definition.name] = parameters.get_value(definition.name)
	var fx := mixer.get_effect_bus_usage()
	return {
		voices = events.get_voice_usage(),
		effect_buses = [fx.x, fx.y],
		instances = instances,
		buses = buses,
		snapshots = snapshots,
		parameters = values,
	}


func _exit_tree() -> void:
	if Engine.is_editor_hint() and not preview:
		return
	# Players still mixing at shutdown keep their playbacks alive and leak.
	events.stop_all(false)
	mixer.stop_all_snapshots(false)
	if preview:
		mixer.set_live(false)


func _notification(what: int) -> void:
	if Engine.is_editor_hint():
		return
	if what == NOTIFICATION_APPLICATION_RESUMED:
		_clock_usec = 0 # the time away isn't time the sounds played
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_RESUMED:
		if ProjectSettings.get_setting(SETTING_PAUSE_IN_BACKGROUND, true):
			mixer._background_paused = what == NOTIFICATION_APPLICATION_PAUSED


## Replaces the global parameters, VCAs, snapshots and bus automation.
func apply_config(new_config: ChirpConfig) -> void:
	config = new_config
	parameters._configure(config.global_parameters)
	mixer._configure(config.vcas, config.bus_automations, config.snapshots)
	mixer._configure_duckings(config.duckings)


## Shortcut for [code]Chirp.events.create_instance()[/code].
func create_instance(event_or_path: Variant) -> ChirpEventInstance:
	return events.create_instance(event_or_path)


## Shortcut for [code]Chirp.events.play_one_shot()[/code].
func play_one_shot(event_or_path: Variant, position: Variant = null) -> ChirpEventInstance:
	return events.play_one_shot(event_or_path, position)


## Shortcut for [code]Chirp.events.play_one_shot_attached()[/code].
func play_one_shot_attached(event_or_path: Variant, node: Node) -> ChirpEventInstance:
	return events.play_one_shot_attached(event_or_path, node)


## Auditioning (used by the editor's preview): silences [param instrument] while [param muted].
func set_instrument_muted(instrument: ChirpInstrument, muted: bool) -> void:
	if muted:
		_muted[instrument] = true
	else:
		_muted.erase(instrument)


func is_instrument_muted(instrument: ChirpInstrument) -> bool:
	return _muted.has(instrument)


## Auditioning: while any instrument of an event is soloed, that event's other instruments are silent.
func set_instrument_soloed(instrument: ChirpInstrument, soloed: bool) -> void:
	if soloed:
		_soloed[instrument] = true
	else:
		_soloed.erase(instrument)


func is_instrument_soloed(instrument: ChirpInstrument) -> bool:
	return _soloed.has(instrument)


## Gain from mute and solo for [param instrument] of [param event]: 0 or 1.
func _audition_gain(event: ChirpEvent, instrument: ChirpInstrument) -> float:
	if _muted.is_empty() and _soloed.is_empty():
		return 1.0
	if _muted.has(instrument):
		return 0.0
	if not _soloed.is_empty() and not _soloed.has(instrument):
		for other in event.instruments:
			if _soloed.has(other):
				return 0.0 # another instrument of this event is soloed
	return 1.0


func _warn_once(key: String, message: String) -> void:
	if not _warned.has(key):
		_warned[key] = true
		_warn(message)
