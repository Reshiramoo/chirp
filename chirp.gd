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

var _voice_root: Node
var _warned := {}
var _muted := {} # ChirpInstrument -> true (auditioning)
var _soloed := {} # ChirpInstrument -> true (auditioning)


func _init() -> void:
	events = Events.new(self)
	mixer = Mixer.new(self)
	parameters = Parameters.new(self)


func _ready() -> void:
	if Engine.is_editor_hint() and not preview:
		set_process(false)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	events.scan(ProjectSettings.get_setting(SETTING_SOUND_DIRECTORIES, DEFAULT_SOUND_DIRECTORIES))


func _process(delta: float) -> void:
	parameters._process(delta)
	events._process(delta)
	mixer._process(delta)


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
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_RESUMED:
		if ProjectSettings.get_setting(SETTING_PAUSE_IN_BACKGROUND, true):
			mixer._background_paused = what == NOTIFICATION_APPLICATION_PAUSED


## Replaces the global parameters, VCAs, snapshots and bus automation.
func apply_config(new_config: ChirpConfig) -> void:
	config = new_config
	parameters._configure(config.global_parameters)
	mixer._configure(config.vcas, config.bus_automations, config.snapshots)


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
		push_warning(message)
