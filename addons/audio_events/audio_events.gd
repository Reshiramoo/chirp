extends Node
## AudioEvents autoload: the runtime entry point.
##
## [codeblock]
## AudioEvents.play_one_shot("event:/SFX/Flap")
## var music := AudioEvents.create_instance("event:/Music/Level")
## music.start()
## AudioEvents.set_global_parameter("Danger", 0.8)
## AudioEvents.set_vca_volume("Music", 0.5)
## [/codeblock]

const EVENT_PREFIX := "event:/"
const BUS_PREFIX := "bus:/"
const CONFIG_SETTING := "audio_events/config"
const DEFAULT_CONFIG := "res://audio/audio_events_config.tres"

var config: AudioEventsConfig

var _event_paths := {} # "event:/SFX/Flap" -> resource path
var _active: Array[AudioEventInstance] = []
var _globals := {} # lowercase name -> AudioEventParameter.State
var _vca_gain := {} # VCA name -> linear gain
var _bus_base_db := {} # Godot bus name -> volume set through this API, before VCAs
var _paused_buses := {} # Godot bus name -> true
var _all_paused := false
var _background_paused := false
var _last_start_msec := {} # AudioEvent -> Time.get_ticks_msec()
var _start_counter := 0
var _warned := {}
var _voice_root: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_voice_root = Node.new()
	_voice_root.name = "Voices"
	add_child(_voice_root)
	var path: String = ProjectSettings.get_setting(CONFIG_SETTING, DEFAULT_CONFIG)
	var loaded: AudioEventsConfig = null
	if ResourceLoader.exists(path):
		loaded = load(path) as AudioEventsConfig
	apply_config(loaded if loaded else AudioEventsConfig.new())


func _process(delta: float) -> void:
	for state: AudioEventParameter.State in _globals.values():
		state.step(delta)
	for instance in _active.duplicate():
		instance._process(delta)


func _exit_tree() -> void:
	# Players still mixing at shutdown keep their playbacks alive and leak.
	for instance in _active.duplicate():
		instance.stop(false)


func _notification(what: int) -> void:
	if config and config.pause_on_app_background:
		if what == NOTIFICATION_APPLICATION_PAUSED:
			_background_paused = true
		elif what == NOTIFICATION_APPLICATION_RESUMED:
			_background_paused = false


## Replaces the active configuration (events folder, global parameters, VCAs).
func apply_config(new_config: AudioEventsConfig) -> void:
	config = new_config
	_event_paths.clear()
	if DirAccess.dir_exists_absolute(config.events_dir):
		_scan_events(config.events_dir)
	_globals.clear()
	for definition in config.global_parameters:
		if definition:
			_globals[definition.name.to_lower()] = AudioEventParameter.State.new(definition)
	_vca_gain.clear()
	for vca in config.vcas:
		if vca:
			_vca_gain[vca.name] = 1.0


# --- events --------------------------------------------------------------------

## Makes [param event] addressable as [param event_path] ("event:/..."), e.g. for events built in code.
func register_event(event_path: String, event: AudioEvent) -> void:
	_event_paths[event_path] = event


## Accepts an AudioEvent or an "event:/..." path.
func get_event(event_or_path: Variant) -> AudioEvent:
	if event_or_path is AudioEvent:
		return event_or_path
	var entry: Variant = _event_paths.get(String(event_or_path))
	if entry is AudioEvent:
		return entry
	if entry is String:
		var event := load(entry) as AudioEvent
		if event:
			return event
		push_error("AudioEvents: '%s' is not an AudioEvent." % entry)
		return null
	push_error("AudioEvents: unknown event '%s'." % event_or_path)
	return null


func get_event_paths() -> PackedStringArray:
	return PackedStringArray(_event_paths.keys())


func create_instance(event_or_path: Variant) -> AudioEventInstance:
	var event := get_event(event_or_path)
	if event == null:
		return null
	return AudioEventInstance.new(self, event, _resolve_bus(event.bus))


## Fire-and-forget. [param position] may be null (non-spatial), a Vector2 or a Vector3.
func play_one_shot(event_or_path: Variant, position: Variant = null) -> AudioEventInstance:
	var instance := create_instance(event_or_path)
	if instance == null:
		return null
	if position != null:
		instance.set_position(position)
	instance.start()
	instance.release()
	return instance


## Fire-and-forget, following [param node] while it lives.
func play_one_shot_attached(event_or_path: Variant, node: Node) -> AudioEventInstance:
	var instance := create_instance(event_or_path)
	if instance == null:
		return null
	instance.attach_to(node)
	instance.start()
	instance.release()
	return instance


## Instances that are playing or stopping, optionally only those of [param event_or_path].
func get_active_instances(event_or_path: Variant = null) -> Array[AudioEventInstance]:
	if event_or_path == null:
		return _active.duplicate()
	var event := get_event(event_or_path)
	var result: Array[AudioEventInstance] = []
	result.assign(_active.filter(func(i: AudioEventInstance) -> bool: return i._event == event))
	return result


# --- global parameters ---------------------------------------------------------

func set_global_parameter(parameter_name: String, value: float) -> void:
	var state := _get_global_state(parameter_name)
	if state == null:
		_warn_once("global:" + parameter_name, "AudioEvents: unknown global parameter '%s'." % parameter_name)
		return
	state.set_target(value, false)


func set_global_parameter_by_label(parameter_name: String, label: String) -> void:
	var state := _get_global_state(parameter_name)
	if state == null:
		set_global_parameter(parameter_name, 0.0) # reports the missing parameter
		return
	var value := state.def.label_to_value(label)
	if value < 0.0:
		push_warning("AudioEvents: global parameter '%s' has no label '%s'." % [parameter_name, label])
		return
	state.set_target(value, false)


func get_global_parameter(parameter_name: String) -> float:
	var state := _get_global_state(parameter_name)
	return state.value if state else 0.0


# --- buses & VCAs ----------------------------------------------------------------

## Linear volume of a bus ("bus:/SFX"), not counting VCAs.
func set_bus_volume(bus_path: String, volume: float) -> void:
	var bus := _resolve_bus(bus_path)
	_bus_base_db[bus] = linear_to_db(volume) if volume > 0.00001 else -80.0
	_apply_bus_volume(bus)


func get_bus_volume(bus_path: String) -> float:
	var bus := _resolve_bus(bus_path)
	if not _bus_base_db.has(bus):
		return db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus)))
	return db_to_linear(_bus_base_db[bus])


func set_bus_mute(bus_path: String, mute: bool) -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index(_resolve_bus(bus_path)), mute)


## Pauses every event routed into this bus or any bus below it.
func set_bus_paused(bus_path: String, paused: bool) -> void:
	var bus := _resolve_bus(bus_path)
	if paused:
		_paused_buses[bus] = true
	else:
		_paused_buses.erase(bus)


func stop_all_bus_events(bus_path: String, allow_fadeout := true) -> void:
	var bus := _resolve_bus(bus_path)
	for instance in _active.duplicate():
		if _bus_is_under(instance._bus, bus):
			instance.stop(allow_fadeout)


func set_vca_volume(vca_name: String, volume: float) -> void:
	var vca := _find_vca(vca_name)
	if vca == null:
		push_error("AudioEvents: unknown VCA '%s'." % vca_name)
		return
	_vca_gain[vca.name] = maxf(volume, 0.0)
	for bus_path in vca.buses:
		_apply_bus_volume(_resolve_bus(bus_path))


func get_vca_volume(vca_name: String) -> float:
	return _vca_gain.get(vca_name, 1.0)


## Pauses or resumes every event (e.g. while an ad is showing).
func pause_all(paused: bool) -> void:
	_all_paused = paused


func mute_all(mute: bool) -> void:
	AudioServer.set_bus_mute(0, mute)


# --- internals used by AudioEventInstance ----------------------------------------

func _can_start(instance: AudioEventInstance) -> bool:
	var event := instance._event
	if event.cooldown > 0.0 and not instance.is_playing() and _last_start_msec.has(event):
		if Time.get_ticks_msec() - _last_start_msec[event] < event.cooldown * 1000.0:
			return false
	if event.max_instances <= 0:
		return true
	var others := _active.filter(func(i: AudioEventInstance) -> bool:
		return i._event == event and i != instance)
	while others.size() >= event.max_instances:
		var victim: AudioEventInstance = null
		match event.stealing:
			AudioEvent.Stealing.NONE:
				return false
			AudioEvent.Stealing.QUIETEST:
				victim = _min_by(others, func(i: AudioEventInstance) -> float: return i._get_level())
			AudioEvent.Stealing.FURTHEST:
				victim = _min_by(others, func(i: AudioEventInstance) -> float: return -_listener_distance(i))
			_:
				victim = _min_by(others, func(i: AudioEventInstance) -> float: return i._start_order)
		others.erase(victim)
		victim.stop(false)
	return true


func _register_start(instance: AudioEventInstance) -> void:
	_start_counter += 1
	instance._start_order = _start_counter
	_last_start_msec[instance._event] = Time.get_ticks_msec()
	if not _active.has(instance):
		_active.append(instance)


func _register_stop(instance: AudioEventInstance) -> void:
	_active.erase(instance)


func _get_global_state(parameter_name: String) -> AudioEventParameter.State:
	return _globals.get(parameter_name.to_lower())


func _is_bus_paused(bus: StringName) -> bool:
	if _all_paused or _background_paused:
		return true
	for paused_bus in _paused_buses:
		if _bus_is_under(bus, paused_bus):
			return true
	return false


func _warn_once(key: String, message: String) -> void:
	if not _warned.has(key):
		_warned[key] = true
		push_warning(message)


func _scan_events(dir: String) -> void:
	for entry in ResourceLoader.list_directory(dir):
		var path := dir.path_join(entry)
		if entry.ends_with("/"):
			_scan_events(path.trim_suffix("/"))
		elif entry.get_extension() in ["tres", "res"]:
			var relative := path.trim_prefix(config.events_dir).trim_prefix("/").get_basename()
			_event_paths[EVENT_PREFIX + relative] = path


## "bus:/SFX/UI" -> &"UI". Unknown buses fall back to Master.
func _resolve_bus(bus_path: String) -> StringName:
	var trimmed := bus_path.trim_prefix(BUS_PREFIX).trim_suffix("/")
	if trimmed.is_empty():
		return &"Master"
	var bus_name := trimmed.get_slice("/", trimmed.get_slice_count("/") - 1)
	if AudioServer.get_bus_index(bus_name) == -1:
		_warn_once("bus:" + bus_name,
			"AudioEvents: no Godot bus named '%s' (from '%s'); using Master." % [bus_name, bus_path])
		return &"Master"
	return StringName(bus_name)


func _bus_is_under(bus: StringName, ancestor: StringName) -> bool:
	for _i in AudioServer.bus_count + 1:
		if bus == ancestor:
			return true
		var index := AudioServer.get_bus_index(bus)
		if index <= 0:
			return false
		bus = AudioServer.get_bus_send(index)
	return false


func _find_vca(vca_name: String) -> AudioEventVCA:
	for vca in config.vcas:
		if vca and vca.name == vca_name:
			return vca
	return null


func _apply_bus_volume(bus: StringName) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index == -1:
		return
	if not _bus_base_db.has(bus):
		_bus_base_db[bus] = AudioServer.get_bus_volume_db(index)
	var gain := db_to_linear(_bus_base_db[bus])
	for vca in config.vcas:
		if vca == null:
			continue
		for bus_path in vca.buses:
			if _resolve_bus(bus_path) == bus:
				gain *= _vca_gain.get(vca.name, 1.0)
				break
	AudioServer.set_bus_volume_db(index, linear_to_db(gain) if gain > 0.00001 else -80.0)


func _listener_distance(instance: AudioEventInstance) -> float:
	var position: Variant = instance._position
	if position is Vector2:
		var camera := get_viewport().get_camera_2d()
		var listener := camera.get_screen_center_position() if camera else get_viewport().get_visible_rect().size / 2.0
		return position.distance_to(listener)
	if position is Vector3:
		var camera_3d := get_viewport().get_camera_3d()
		return position.distance_to(camera_3d.global_position) if camera_3d else position.length()
	return 0.0


static func _min_by(items: Array, key: Callable) -> AudioEventInstance:
	var best: AudioEventInstance = null
	var best_key := INF
	for item: AudioEventInstance in items:
		var k: float = key.call(item)
		if k < best_key:
			best_key = k
			best = item
	return best
