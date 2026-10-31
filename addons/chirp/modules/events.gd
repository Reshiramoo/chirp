@tool
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
##
## Files load the first time their event is used and then stay loaded. To avoid that first-use
## stall (on mobile especially), load them ahead of time with [method preload_events]; free them
## with [method unload_events].

## No preloads are pending any more (emitted on a later frame, so it can always be awaited).
signal preload_finished

const EVENT_PREFIX := "event:/"
const SETTING_MAX_VOICES := "chirp/max_voices"
const SETTING_VIRTUALIZE_BELOW_DB := "chirp/virtualize_below_db"
const DEFAULT_VIRTUALIZE_BELOW_DB := -80.0
const AUDIO_EXTENSIONS: Array[String] = ["wav", "ogg", "mp3"]
const RESOURCE_EXTENSIONS: Array[String] = ["tres", "res"]

var _chirp: Node
var _entries := {} # "event:/sfxs/coin" -> {path: String, bus: String, event: ChirpEvent}
var _directories := {} # directory -> bus path
var _active: Array[ChirpEventInstance] = []
var _last_start_msec := {} # ChirpEvent instance id -> Time.get_ticks_msec() (ids, so events can be freed)
var _start_counter := 0
# Listener state, refreshed every frame for built-in parameters and stealing.
var _listener_2d := Transform2D.IDENTITY
var _listener_2d_velocity := Vector2.ZERO
var _listener_3d := Transform3D.IDENTITY
var _listener_3d_velocity := Vector3.ZERO
var _listener_ready := false
var _listener_nodes: Array[Node] = [] # ChirpListener2D/3D that are current, most recent last
var _preloading := {} # file path -> event paths waiting for its threaded load
var _preload_total := 0 # files in the current preload batch
var _preload_done := 0
var _preload_signal_queued := false

## Supplies sounds for PROGRAMMER instruments that their instance didn't get one for:
## [code]func(key: String, instance: ChirpEventInstance) -> AudioStream[/code]. E.g. a lookup of
## localised dialogue by key.
var programmer_sound_provider := Callable()
## Most sounds playing at once; 0 = no limit. Over it, the least important instances go virtual:
## their sounds pause but they keep running, and pick up where they'd be once there's room.
## Importance: ChirpEvent.priority, then how loud they are at the listener. Nested events count
## with the instance that plays them. From the "chirp/max_voices" project setting.
var max_voices := 0
## Instances quieter than this at the listener go virtual even under the budget (distant or faded
## out sounds cost nothing). -120 or lower turns this off. From the "chirp/virtualize_below_db"
## project setting.
var virtualize_below_db := DEFAULT_VIRTUALIZE_BELOW_DB
var _voice_usage := {real = 0, virtual = 0}


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


## The file behind an event path (a ChirpEvent resource or an audio file), or "" for code events.
func get_event_file(event_path: String) -> String:
	var entry: Variant = _entries.get(event_path)
	return entry.path if entry else ""


## Accepts a ChirpEvent or an "event:/..." path.
func get_event(event_or_path: Variant) -> ChirpEvent:
	if event_or_path is ChirpEvent:
		return event_or_path
	var entry: Variant = _entries.get(String(event_or_path))
	if entry == null:
		_chirp._error("Chirp: unknown event '%s'.%s" % [event_or_path, _unknown_hint(String(event_or_path))])
		return null
	if entry.event == null:
		entry.event = _load_event(entry.path, entry.bus)
	return entry.event


## Loads events ahead of their first use, so playing them doesn't stall. [param targets] is an
## "event:/..." path, a folder of them ("event:/sfxs" covers everything under it), or an Array of
## either; by default every event. With [param threaded] the files load in the background;
## [signal preload_finished] fires once nothing is pending ([method get_preload_progress] tracks it).
## [codeblock]
## Chirp.events.preload_events(["event:/sfxs", "event:/bgms/level_2"])
## await Chirp.events.preload_finished
## [/codeblock]
func preload_events(targets: Variant = EVENT_PREFIX, threaded := true) -> void:
	for event_path in _matching(targets):
		var entry: Dictionary = _entries[event_path]
		if entry.event or entry.path.is_empty():
			continue
		if not threaded:
			entry.event = _load_event(entry.path, entry.bus)
			continue
		if not _preloading.has(entry.path):
			if ResourceLoader.load_threaded_request(entry.path) != OK:
				_chirp._warn("Chirp: couldn't start loading '%s'." % entry.path)
				continue
			_preloading[entry.path] = []
			_preload_total += 1
		_preloading[entry.path].append(event_path)
	if _preloading.is_empty():
		_queue_preload_finished()


## Lets Godot free events' files: Chirp drops its references (playing instances keep theirs), and
## the next use loads them again. Same [param targets] as [method preload_events]. Events added
## with [method register_event] are kept.
func unload_events(targets: Variant = EVENT_PREFIX) -> void:
	for event_path in _matching(targets):
		var entry: Dictionary = _entries[event_path]
		if not entry.path.is_empty():
			entry.event = null


## True when [param event_path]'s file is loaded (or it was added with [method register_event]).
func is_event_loaded(event_path: String) -> bool:
	var entry: Variant = _entries.get(event_path)
	return entry != null and entry.event != null


## True while threaded preloads are pending.
func is_preloading() -> bool:
	return not _preloading.is_empty()


## Progress of the current threaded preloads, 0..1 (1 when none are pending).
func get_preload_progress() -> float:
	if _preloading.is_empty() or _preload_total == 0:
		return 1.0
	var progress := float(_preload_done)
	for path: String in _preloading:
		var file_progress := []
		ResourceLoader.load_threaded_get_status(path, file_progress)
		progress += file_progress[0] if not file_progress.is_empty() else 0.0
	return clampf(progress / _preload_total, 0.0, 1.0)


## Known paths that end the same way as [param event_path], e.g. "event:/audio/coin" for "event:/coin".
func suggest_paths(event_path: String) -> PackedStringArray:
	var tail := "/" + event_path.trim_prefix(EVENT_PREFIX).trim_prefix("/")
	var matches := PackedStringArray()
	for known: String in _entries:
		if known.ends_with(tail) or known.to_lower().ends_with(tail.to_lower()):
			matches.append(known)
	matches.sort()
	return matches


func _unknown_hint(event_path: String) -> String:
	var matches := suggest_paths(event_path)
	if not matches.is_empty():
		var quoted := PackedStringArray()
		for known in matches.slice(0, 3):
			quoted.append("'%s'" % known)
		return " Did you mean %s? Paths start with the sound directory's folder name." % " or ".join(quoted)
	if _entries.is_empty():
		return " No events found: check the \"chirp/sound_directories\" project setting."
	return ""


func create_instance(event_or_path: Variant) -> ChirpEventInstance:
	var event := get_event(event_or_path)
	if event == null:
		return null
	var instance := ChirpEventInstance.new(_chirp, event, _chirp.mixer.resolve_bus(_bus_path(event)))
	instance._label = event_or_path if event_or_path is String else _label_of(event)
	return instance


## A readable name for [param event]: its event path when registered, else its file.
func _label_of(event: ChirpEvent) -> String:
	for path: String in _entries:
		if _entries[path].get("event") == event:
			return path
	if not event.resource_path.is_empty():
		return event.resource_path.get_file()
	return event.resource_name if event.resource_name else "(event)"


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
	if not _preloading.is_empty():
		_poll_preloads()
	_update_listeners(delta)
	for instance in _active.duplicate():
		instance._process(delta)
	_update_virtualization()


## Sounds playing now: {real, virtual, limit} (limit 0 = none). Virtual ones are paused, waiting
## for room or for being loud enough.
func get_voice_usage() -> Dictionary:
	return {real = _voice_usage.real, virtual = _voice_usage.virtual, limit = max_voices}


## Ranks the playing instances (with their nested events) and makes the ones that don't fit the
## voice budget, or can't be heard, virtual.
func _update_virtualization() -> void:
	var families := {} # root instance -> [instances]
	for instance in _active:
		if instance._applied_paused or not instance.is_playing():
			continue
		var root := _root_of(instance)
		if not families.has(root):
			families[root] = []
		families[root].append(instance)
	var ranked: Array = families.keys()
	var audibility := {}
	for root: ChirpEventInstance in ranked:
		audibility[root] = root.get_audibility()
	ranked.sort_custom(func(a: ChirpEventInstance, b: ChirpEventInstance) -> bool:
		if a._event.priority != b._event.priority:
			return a._event.priority > b._event.priority
		if not is_equal_approx(audibility[a], audibility[b]):
			return audibility[a] > audibility[b]
		return a._start_order < b._start_order)
	var real := 0
	var virtual := 0
	var quiet := db_to_linear(virtualize_below_db) if virtualize_below_db > -120.0 else -1.0
	for root: ChirpEventInstance in ranked:
		var members: Array = families[root]
		var voices := 0
		for instance: ChirpEventInstance in members:
			voices += instance._player_count()
		# A little hysteresis, so a sound hovering at the threshold doesn't flicker.
		var threshold := quiet * (1.4 if root._virtual else 1.0)
		var go_virtual: bool = audibility[root] < threshold or (max_voices > 0 and real + voices > max_voices)
		if go_virtual:
			virtual += voices
		else:
			real += voices
		for instance: ChirpEventInstance in members:
			instance._set_virtual(go_virtual)
	_voice_usage = {real = real, virtual = virtual}


func _root_of(instance: ChirpEventInstance) -> ChirpEventInstance:
	var root := instance
	for _i in 16:
		var parent := instance_from_id(root._parent_id) as ChirpEventInstance if root._parent_id else null
		if parent == null or not parent.is_playing():
			break
		root = parent
	return root


## The current ChirpListener2D/3D, else the current AudioListener2D/3D, else the current camera.
func _update_listeners(delta: float) -> void:
	var viewport: Viewport = _chirp.get_viewport()
	var listener_2d := Transform2D(0.0, viewport.get_visible_rect().size / 2.0)
	var audio_listener_2d := viewport.get_audio_listener_2d()
	var camera_2d := viewport.get_camera_2d()
	var chirp_listener_2d: ChirpListener2D = _current_listener(false)
	if chirp_listener_2d:
		listener_2d = Transform2D(chirp_listener_2d.global_rotation, chirp_listener_2d.get_attenuation_position())
	elif audio_listener_2d:
		listener_2d = audio_listener_2d.global_transform
	elif camera_2d:
		var rotation := 0.0 if camera_2d.ignore_rotation else camera_2d.global_rotation
		listener_2d = Transform2D(rotation, camera_2d.get_screen_center_position())

	var listener_3d := Transform3D.IDENTITY
	var audio_listener_3d := viewport.get_audio_listener_3d()
	var camera_3d := viewport.get_camera_3d()
	var chirp_listener_3d: ChirpListener3D = _current_listener(true)
	if chirp_listener_3d:
		listener_3d = Transform3D(chirp_listener_3d.global_basis.orthonormalized(),
			chirp_listener_3d.get_attenuation_position())
	elif audio_listener_3d:
		listener_3d = audio_listener_3d.get_listener_transform()
	elif camera_3d:
		listener_3d = camera_3d.global_transform

	if _listener_ready and delta > 0.0:
		_listener_2d_velocity = (listener_2d.origin - _listener_2d.origin) / delta
		_listener_3d_velocity = (listener_3d.origin - _listener_3d.origin) / delta
	_listener_2d = listener_2d
	_listener_3d = listener_3d
	_listener_ready = true


func _add_listener(listener: Node) -> void:
	_listener_nodes.erase(listener)
	_listener_nodes.append(listener)


func _remove_listener(listener: Node) -> void:
	_listener_nodes.erase(listener)


## The most recently made current ChirpListener3D ([param is_3d]) or ChirpListener2D, or null.
func _current_listener(is_3d: bool) -> Node:
	for i in range(_listener_nodes.size() - 1, -1, -1):
		var listener := _listener_nodes[i]
		if not is_instance_valid(listener) or not listener.is_inside_tree():
			_listener_nodes.remove_at(i)
			continue
		if (is_3d and listener is ChirpListener3D) or (not is_3d and listener is ChirpListener2D):
			return listener
	return null


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
	return _as_event(load(path), path, bus)


## Collects finished threaded preloads.
func _poll_preloads() -> void:
	for path: String in _preloading.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		var resource: Resource = ResourceLoader.load_threaded_get(path) if status == ResourceLoader.THREAD_LOAD_LOADED else null
		if resource == null:
			_chirp._warn("Chirp: couldn't preload '%s'." % path)
		for event_path: String in _preloading[path]:
			var entry: Variant = _entries.get(event_path)
			if resource and entry and entry.event == null and entry.path == path: # skip if loaded meanwhile or rescanned
				entry.event = _as_event(resource, path, entry.bus)
		_preloading.erase(path)
		_preload_done += 1
	if _preloading.is_empty():
		_queue_preload_finished()


func _queue_preload_finished() -> void:
	if not _preload_signal_queued:
		_preload_signal_queued = true
		_emit_preload_finished.call_deferred()


func _emit_preload_finished() -> void:
	_preload_signal_queued = false
	if _preloading.is_empty():
		_preload_total = 0
		_preload_done = 0
		preload_finished.emit()


## Event paths [param targets] names: a path, a folder of paths, or an Array of either.
func _matching(targets: Variant) -> PackedStringArray:
	var found := PackedStringArray()
	var list: Array = targets if targets is Array else Array(targets) if targets is PackedStringArray else [targets]
	for target in list:
		if not (target is String or target is StringName):
			continue # ChirpEvent resources are loaded already
		var prefix := String(target).trim_suffix("/") # "event:/" -> "event:", which prefixes every path
		var matched := false
		for event_path: String in _entries:
			if event_path == prefix or event_path.begins_with(prefix + "/"):
				if event_path not in found:
					found.append(event_path)
				matched = true
		if not matched:
			_chirp._warn_once("match:" + prefix, "Chirp: no events at '%s'.%s" % [prefix, _unknown_hint(prefix)])
	return found


## The event for a loaded file: a ChirpEvent as is, an audio file wrapped in a one-instrument event.
func _as_event(resource: Resource, path: String, bus: String) -> ChirpEvent:
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
	_chirp._error("Chirp: '%s' is neither a ChirpEvent nor an AudioStream." % path)
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
	var id := event.get_instance_id()
	if event.cooldown > 0.0 and not instance.is_playing() and _last_start_msec.has(id):
		if Time.get_ticks_msec() - _last_start_msec[id] < event.cooldown * 1000.0:
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
	if instance._event.cooldown > 0.0:
		_last_start_msec[instance._event.get_instance_id()] = Time.get_ticks_msec()
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
