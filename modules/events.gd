extends RefCounted
## Chirp.events: finds events by path, creates and plays instances, enforces instance limits.
##
## Events are found in the "chirp/sound_directories" project setting. Each directory's
## folder name starts the path, and its files become events:
## [codeblock]
## res://assets/sounds/sfxs/coin.mp3        -> "event:/sfxs/coin"   (plain audio file)
## res://assets/sounds/sfxs/ui/click.tres   -> "event:/sfxs/ui/click" (ChirpEvent resource)
## [/codeblock]
## A ChirpEvent resource wins over an audio file with the same name.

const EVENT_PREFIX := "event:/"
const AUDIO_EXTENSIONS: Array[String] = ["wav", "ogg", "mp3"]
const RESOURCE_EXTENSIONS: Array[String] = ["tres", "res"]

var _chirp: Node
var _entries := {} # "event:/sfxs/coin" -> {path: String, bus: String, event: ChirpEvent}
var _directories := {} # directory -> bus path
var _active: Array[ChirpEventInstance] = []
var _last_start_msec := {} # ChirpEvent -> Time.get_ticks_msec()
var _start_counter := 0
# Listener state, refreshed every frame for built-in parameters and stealing.
var _listener_2d := Transform2D.IDENTITY
var _listener_2d_velocity := Vector2.ZERO
var _listener_3d := Transform3D.IDENTITY
var _listener_3d_velocity := Vector3.ZERO
var _listener_ready := false


func _init(chirp: Node) -> void:
	_chirp = chirp


## Rebuilds the path registry from {directory: bus path}. Use "" as the bus for Master.
func scan(directories: Dictionary) -> void:
	_entries.clear()
	_directories.clear()
	for directory: String in directories:
		var root := directory.trim_suffix("/")
		_directories[root] = String(directories[directory])
		if not DirAccess.dir_exists_absolute(root):
			_chirp._warn_once("dir:" + root, "Chirp: sound directory '%s' does not exist." % root)
			continue
		_scan_directory(root, EVENT_PREFIX + root.get_file(), _directories[root])


## Makes [param event] addressable as [param event_path] ("event:/..."), e.g. for events built in code.
func register_event(event_path: String, event: ChirpEvent) -> void:
	_entries[event_path] = {path = "", bus = "", event = event}


func get_event_paths() -> PackedStringArray:
	return PackedStringArray(_entries.keys())


## Accepts a ChirpEvent or an "event:/..." path.
func get_event(event_or_path: Variant) -> ChirpEvent:
	if event_or_path is ChirpEvent:
		return event_or_path
	var entry: Variant = _entries.get(String(event_or_path))
	if entry == null:
		push_error("Chirp: unknown event '%s'." % event_or_path)
		return null
	if entry.event == null:
		entry.event = _load_event(entry.path, entry.bus)
	return entry.event


func create_instance(event_or_path: Variant) -> ChirpEventInstance:
	var event := get_event(event_or_path)
	if event == null:
		return null
	return ChirpEventInstance.new(_chirp, event, _chirp.mixer.resolve_bus(_bus_path(event)))


## Fire-and-forget. [param position] may be null (non-spatial), a Vector2 or a Vector3.
func play_one_shot(event_or_path: Variant, position: Variant = null) -> ChirpEventInstance:
	var instance := create_instance(event_or_path)
	if instance == null:
		return null
	if position != null:
		instance.set_position(position)
	instance.start()
	instance.release()
	return instance


## Fire-and-forget, following [param node] while it lives.
func play_one_shot_attached(event_or_path: Variant, node: Node) -> ChirpEventInstance:
	var instance := create_instance(event_or_path)
	if instance == null:
		return null
	instance.attach_to(node)
	instance.start()
	instance.release()
	return instance


## Instances that are playing or stopping, optionally only those of [param event_or_path].
func get_active_instances(event_or_path: Variant = null) -> Array[ChirpEventInstance]:
	if event_or_path == null:
		return _active.duplicate()
	var event := get_event(event_or_path)
	var result: Array[ChirpEventInstance] = []
	result.assign(_active.filter(func(i: ChirpEventInstance) -> bool: return i._event == event))
	return result


func stop_all(allow_fadeout := true) -> void:
	for instance in _active.duplicate():
		instance.stop(allow_fadeout)


# --- internals ---------------------------------------------------------------------

func _process(delta: float) -> void:
	_update_listeners(delta)
	for instance in _active.duplicate():
		instance._process(delta)


## The current AudioListener2D/3D if there is one, else the current camera.
func _update_listeners(delta: float) -> void:
	var viewport: Viewport = _chirp.get_viewport()
	var listener_2d := Transform2D(0.0, viewport.get_visible_rect().size / 2.0)
	var audio_listener_2d := viewport.get_audio_listener_2d()
	var camera_2d := viewport.get_camera_2d()
	if audio_listener_2d:
		listener_2d = audio_listener_2d.global_transform
	elif camera_2d:
		var rotation := 0.0 if camera_2d.ignore_rotation else camera_2d.global_rotation
		listener_2d = Transform2D(rotation, camera_2d.get_screen_center_position())

	var listener_3d := Transform3D.IDENTITY
	var audio_listener_3d := viewport.get_audio_listener_3d()
	var camera_3d := viewport.get_camera_3d()
	if audio_listener_3d:
		listener_3d = audio_listener_3d.get_listener_transform()
	elif camera_3d:
		listener_3d = camera_3d.global_transform

	if _listener_ready and delta > 0.0:
		_listener_2d_velocity = (listener_2d.origin - _listener_2d.origin) / delta
		_listener_3d_velocity = (listener_3d.origin - _listener_3d.origin) / delta
	_listener_2d = listener_2d
	_listener_3d = listener_3d
	_listener_ready = true


func _scan_directory(directory: String, prefix: String, bus: String) -> void:
	for entry in ResourceLoader.list_directory(directory):
		if entry.ends_with("/"):
			var sub := entry.trim_suffix("/")
			_scan_directory(directory.path_join(sub), prefix + "/" + sub, bus)
			continue
		var extension := entry.get_extension().to_lower()
		var is_resource := extension in RESOURCE_EXTENSIONS
		if not is_resource and extension not in AUDIO_EXTENSIONS:
			continue
		var key := prefix + "/" + entry.get_basename()
		var existing: Variant = _entries.get(key)
		if existing and not is_resource and existing.path.get_extension() in RESOURCE_EXTENSIONS:
			continue
		_entries[key] = {path = directory.path_join(entry), bus = bus, event = null}


func _load_event(path: String, bus: String) -> ChirpEvent:
	var resource := load(path)
	if resource is ChirpEvent:
		return resource
	if resource is AudioStream:
		# A plain audio file: wrap it in a one-instrument event on the directory's bus.
		var instrument := ChirpInstrument.new()
		instrument.streams.append(resource)
		var event := ChirpEvent.new()
		event.instruments.append(instrument)
		event.bus = bus
		return event
	push_error("Chirp: '%s' is neither a ChirpEvent nor an AudioStream." % path)
	return null


## The event's own bus, else the bus of the sound directory it was saved in, else Master.
func _bus_path(event: ChirpEvent) -> String:
	if not event.bus.is_empty():
		return event.bus
	for directory: String in _directories:
		if event.resource_path.begins_with(directory + "/"):
			return _directories[directory]
	return ""


func _can_start(instance: ChirpEventInstance) -> bool:
	var event := instance._event
	if event.cooldown > 0.0 and not instance.is_playing() and _last_start_msec.has(event):
		if Time.get_ticks_msec() - _last_start_msec[event] < event.cooldown * 1000.0:
			return false
	if event.max_instances <= 0:
		return true
	var others := _active.filter(func(i: ChirpEventInstance) -> bool:
		return i._event == event and i != instance)
	while others.size() >= event.max_instances:
		var victim: ChirpEventInstance = null
		match event.stealing:
			ChirpEvent.Stealing.NONE:
				return false
			ChirpEvent.Stealing.QUIETEST:
				victim = _min_by(others, func(i: ChirpEventInstance) -> float: return i._get_level())
			ChirpEvent.Stealing.FURTHEST:
				victim = _min_by(others, func(i: ChirpEventInstance) -> float: return -_listener_distance(i))
			_:
				victim = _min_by(others, func(i: ChirpEventInstance) -> float: return i._start_order)
		others.erase(victim)
		victim.stop(false)
	return true


func _register_start(instance: ChirpEventInstance) -> void:
	_start_counter += 1
	instance._start_order = _start_counter
	_last_start_msec[instance._event] = Time.get_ticks_msec()
	if not _active.has(instance):
		_active.append(instance)


func _register_stop(instance: ChirpEventInstance) -> void:
	_active.erase(instance)


func _listener_distance(instance: ChirpEventInstance) -> float:
	var position: Variant = instance._position
	if position is Vector2:
		return position.distance_to(_listener_2d.origin)
	if position is Vector3:
		return position.distance_to(_listener_3d.origin)
	return 0.0


static func _min_by(items: Array, key: Callable) -> ChirpEventInstance:
	var best: ChirpEventInstance = null
	var best_key := INF
	for item: ChirpEventInstance in items:
		var k: float = key.call(item)
		if k < best_key:
			best_key = k
			best = item
	return best
