extends RefCounted
## Chirp.mixer: bus volumes, VCAs and pausing.
## Bus paths look like "bus:/SFX" or "bus:/SFX/UI"; the last segment names the Godot bus.

const BUS_PREFIX := "bus:/"

var _chirp: Node
var _vcas: Array[ChirpVCA] = []
var _vca_gain := {} # VCA name -> linear gain
var _bus_base_db := {} # Godot bus name -> volume set through this API, before VCAs
var _paused_buses := {} # Godot bus name -> true
var _all_paused := false
var _background_paused := false


func _init(chirp: Node) -> void:
	_chirp = chirp


## Linear volume of a bus, not counting VCAs.
func set_bus_volume(bus_path: String, volume: float) -> void:
	var bus := resolve_bus(bus_path)
	_bus_base_db[bus] = linear_to_db(volume) if volume > 0.00001 else -80.0
	_apply_bus_volume(bus)


func get_bus_volume(bus_path: String) -> float:
	var bus := resolve_bus(bus_path)
	if not _bus_base_db.has(bus):
		return db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus)))
	return db_to_linear(_bus_base_db[bus])


func set_bus_mute(bus_path: String, mute: bool) -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index(resolve_bus(bus_path)), mute)


## Pauses every event routed into this bus or any bus below it.
func set_bus_paused(bus_path: String, paused: bool) -> void:
	var bus := resolve_bus(bus_path)
	if paused:
		_paused_buses[bus] = true
	else:
		_paused_buses.erase(bus)


## Stops every event routed into this bus or any bus below it.
func stop_bus_events(bus_path: String, allow_fadeout := true) -> void:
	var bus := resolve_bus(bus_path)
	for instance: ChirpEventInstance in _chirp.events.get_active_instances():
		if _bus_is_under(instance._bus, bus):
			instance.stop(allow_fadeout)


func set_vca_volume(vca_name: String, volume: float) -> void:
	var vca := _find_vca(vca_name)
	if vca == null:
		push_error("Chirp: unknown VCA '%s'." % vca_name)
		return
	_vca_gain[vca.name] = maxf(volume, 0.0)
	for bus_path in vca.buses:
		_apply_bus_volume(resolve_bus(bus_path))


func get_vca_volume(vca_name: String) -> float:
	return _vca_gain.get(vca_name, 1.0)


## Pauses or resumes every event (e.g. while an ad is showing).
func pause_all(paused: bool) -> void:
	_all_paused = paused


func mute_all(mute: bool) -> void:
	AudioServer.set_bus_mute(0, mute)


## "bus:/SFX/UI" -> &"UI". Empty or unknown buses fall back to Master.
func resolve_bus(bus_path: String) -> StringName:
	var trimmed := bus_path.trim_prefix(BUS_PREFIX).trim_suffix("/")
	if trimmed.is_empty():
		return &"Master"
	var bus_name := trimmed.get_slice("/", trimmed.get_slice_count("/") - 1)
	if AudioServer.get_bus_index(bus_name) == -1:
		_chirp._warn_once("bus:" + bus_name,
			"Chirp: no Godot bus named '%s' (from '%s'); using Master." % [bus_name, bus_path])
		return &"Master"
	return StringName(bus_name)


# --- internals ---------------------------------------------------------------------

func _configure(vcas: Array[ChirpVCA]) -> void:
	_vcas.clear()
	_vca_gain.clear()
	for vca in vcas:
		if vca:
			_vcas.append(vca)
			_vca_gain[vca.name] = 1.0


func _is_bus_paused(bus: StringName) -> bool:
	if _all_paused or _background_paused:
		return true
	for paused_bus in _paused_buses:
		if _bus_is_under(bus, paused_bus):
			return true
	return false


func _bus_is_under(bus: StringName, ancestor: StringName) -> bool:
	for _i in AudioServer.bus_count + 1:
		if bus == ancestor:
			return true
		var index := AudioServer.get_bus_index(bus)
		if index <= 0:
			return false
		bus = AudioServer.get_bus_send(index)
	return false


func _find_vca(vca_name: String) -> ChirpVCA:
	for vca in _vcas:
		if vca.name == vca_name:
			return vca
	return null


func _apply_bus_volume(bus: StringName) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index == -1:
		return
	if not _bus_base_db.has(bus):
		_bus_base_db[bus] = AudioServer.get_bus_volume_db(index)
	var gain := db_to_linear(_bus_base_db[bus])
	for vca in _vcas:
		for bus_path in vca.buses:
			if resolve_bus(bus_path) == bus:
				gain *= _vca_gain.get(vca.name, 1.0)
				break
	AudioServer.set_bus_volume_db(index, linear_to_db(gain) if gain > 0.00001 else -80.0)
