@tool
extends RefCounted
## Chirp.mixer: bus volumes, VCAs, snapshots, bus automation and pausing.
## Bus paths look like "bus:/SFX" or "bus:/SFX/UI"; the last segment names the Godot bus.
##
## Every frame, each bus Chirp manages is recomputed as:
## base volume × VCAs × bus automation, then snapshots blended in by priority.
## Effect properties work the same way, starting from the value they had when first touched.
##
## Events with effects play through buses from a small pool ("Chirp FX 1", ...), created the first
## time one is needed ("chirp/effect_bus_pool_size" of them) and lent to instances while they play.

const BUS_PREFIX := "bus:/"
## Names of the pool's effect buses start with this.
const EFFECT_BUS_PREFIX := "Chirp FX "
const SETTING_EFFECT_POOL := "chirp/effect_bus_pool_size"
const DEFAULT_EFFECT_POOL := 8

var _chirp: Node
var _vcas: Array[ChirpVCA] = []
var _vca_gain := {} # VCA name -> linear gain
var _bus_automations: Array[ChirpBusAutomation] = []
var _snapshots: Array[ChirpSnapshot] = []
var _snapshot_instances: Array[ChirpSnapshotInstance] = []
var _snapshot_counter := 0
var _managed_buses := {} # Godot bus name -> true
var _bus_base_db := {} # Godot bus name -> volume before VCAs, automation and snapshots
var _effects := {} # "bus|index|property" -> {bus, index, property, base}
var _effect_switches := {} # "bus|index" -> {bus, index, base}
var _paused_buses := {} # Godot bus name -> true
var _all_paused := false
var _background_paused := false
var _live := true # false: compute nothing, write nothing (editor preview while idle)
var _fx_created := false
var _fx_free: Array[StringName] = [] # pool buses not lent out
var _fx_lent := {} # pool bus -> true
var _event_fx := {} # ChirpEvent instance id -> {bus, effects, count}: EVENT-scope sharing
var _duckings: Array[ChirpDucking] = []
var _duck_state := {} # ChirpDucking -> {level: 0..1, held: seconds since the trigger was last busy}


func _init(chirp: Node) -> void:
	_chirp = chirp


# --- buses -------------------------------------------------------------------------

## Linear volume of a bus, not counting VCAs, automation or snapshots.
func set_bus_volume(bus_path: String, volume: float) -> void:
	var bus := resolve_bus(bus_path)
	_manage_bus(bus)
	_bus_base_db[bus] = linear_to_db(volume) if volume > 0.00001 else -80.0
	_update()


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


# --- VCAs ---------------------------------------------------------------------------

func set_vca_volume(vca_name: String, volume: float) -> void:
	var vca := _find_vca(vca_name)
	if vca == null:
		_chirp._error("Chirp: unknown VCA '%s'." % vca_name)
		return
	_vca_gain[vca.name] = maxf(volume, 0.0)
	_update()


func get_vca_volume(vca_name: String) -> float:
	return _vca_gain.get(vca_name, 1.0)


# --- snapshots ------------------------------------------------------------------------

## Starts a snapshot by name (from the ChirpConfig) or resource.
func start_snapshot(snapshot_or_name: Variant) -> ChirpSnapshotInstance:
	var snapshot := _find_snapshot(snapshot_or_name)
	if snapshot == null:
		_chirp._error("Chirp: unknown snapshot '%s'." % snapshot_or_name)
		return null
	for override in snapshot.bus_overrides:
		if override == null:
			continue
		var bus := resolve_bus(override.bus)
		if override.override_volume:
			_manage_bus(bus)
		if override.effect_index >= 0 and not override.effect_property.is_empty():
			_manage_effect(bus, override.effect_index, override.effect_property)
		if override.effect_index >= 0 and override.enable_effect:
			_manage_effect_switch(bus, override.effect_index)
	var instance := ChirpSnapshotInstance.new(_chirp, snapshot)
	_snapshot_counter += 1
	instance._start(_snapshot_counter)
	_snapshot_instances.append(instance)
	_update()
	return instance


func get_active_snapshots() -> Array[ChirpSnapshotInstance]:
	return _snapshot_instances.duplicate()


func stop_all_snapshots(allow_fadeout := true) -> void:
	for instance in _snapshot_instances.duplicate():
		instance.stop(allow_fadeout)


# --- pausing ------------------------------------------------------------------------

## Pauses or resumes every event (e.g. while an ad is showing).
func pause_all(paused: bool) -> void:
	_all_paused = paused


func mute_all(mute: bool) -> void:
	AudioServer.set_bus_mute(0, mute)


## While not live, the mixer leaves every bus and effect alone. Going live re-reads their
## current values as the base; going idle restores them. Used by the editor preview so the
## project's bus layout is only touched while something is being auditioned.
func set_live(live: bool) -> void:
	if live == _live:
		return
	if live:
		_live = true
		_recapture()
	else:
		_restore()
		_remove_effect_buses() # so the editor's bus layout is left as it was
		_live = false


func is_live() -> bool:
	return _live


## Pool effect buses currently lent to events, and the pool's size (0 before first use).
# --- ducking ---------------------------------------------------------------------------

## Adds a ducking at runtime (config duckings are added on start).
func add_ducking(ducking: ChirpDucking) -> void:
	if ducking == null or _duckings.has(ducking):
		return
	_duckings.append(ducking)
	_duck_state[ducking] = {level = 0.0, held = INF}
	_manage_bus(resolve_bus(ducking.target_bus))


## Removes a ducking; its bus comes back up at once.
func remove_ducking(ducking: ChirpDucking) -> void:
	_duckings.erase(ducking)
	_duck_state.erase(ducking)
	_update()


## How far (0..1) [param ducking] is pulling its bus down right now.
func get_ducking_level(ducking: ChirpDucking) -> float:
	return _duck_state.get(ducking, {}).get("level", 0.0)


## dB the duckings are taking off a bus right now (0.0 when none).
func get_bus_duck_db(bus_path: String) -> float:
	var bus := resolve_bus(bus_path)
	var db := 0.0
	for ducking in _duckings:
		if resolve_bus(ducking.target_bus) == bus:
			db += ducking.amount_db * _duck_state[ducking].level
	return db


func _configure_duckings(duckings: Array[ChirpDucking]) -> void:
	for ducking in _duckings.duplicate():
		remove_ducking(ducking)
	for ducking in duckings:
		add_ducking(ducking)
	_update()


func _step_duckings(delta: float) -> void:
	for ducking in _duckings:
		var state: Dictionary = _duck_state[ducking]
		if _ducking_triggered(ducking):
			state.held = 0.0
		else:
			state.held += delta
		if state.held <= ducking.hold:
			state.level = minf(state.level + delta / ducking.attack, 1.0) if ducking.attack > 0.0 else 1.0
		else:
			state.level = maxf(state.level - delta / ducking.release, 0.0) if ducking.release > 0.0 else 0.0


func _ducking_triggered(ducking: ChirpDucking) -> bool:
	var bus := resolve_bus(ducking.trigger_bus)
	if ducking.trigger == ChirpDucking.Trigger.LEVEL:
		var index := AudioServer.get_bus_index(bus)
		var peak := maxf(AudioServer.get_bus_peak_volume_left_db(index, 0), AudioServer.get_bus_peak_volume_right_db(index, 0))
		return peak > ducking.threshold_db
	for instance: ChirpEventInstance in _chirp.events.get_active_instances():
		if instance.is_playing() and not instance._applied_paused and _bus_is_under(instance._bus, bus):
			return true
	return false


func get_effect_bus_usage() -> Vector2i:
	return Vector2i(_fx_lent.size(), _fx_lent.size() + _fx_free.size())


# --- internals ---------------------------------------------------------------------

func _configure(vcas: Array[ChirpVCA], bus_automations: Array[ChirpBusAutomation],
		snapshots: Array[ChirpSnapshot]) -> void:
	_vcas.clear()
	_vca_gain.clear()
	for vca in vcas:
		if vca:
			_vcas.append(vca)
			_vca_gain[vca.name] = 1.0
			for bus_path in vca.buses:
				_manage_bus(resolve_bus(bus_path))
	_bus_automations.clear()
	for automation in bus_automations:
		if automation == null:
			continue
		_bus_automations.append(automation)
		var bus := resolve_bus(automation.bus)
		if automation.target == ChirpBusAutomation.Target.VOLUME:
			_manage_bus(bus)
		else:
			_manage_effect(bus, automation.effect_index, automation.effect_property)
	_snapshots.assign(snapshots.filter(func(s: ChirpSnapshot) -> bool: return s != null))
	_update()


func _process(delta: float) -> void:
	for instance in _snapshot_instances.duplicate():
		instance._process(delta)
	_step_duckings(delta)
	_update()


func _snapshot_stopped(instance: ChirpSnapshotInstance) -> void:
	_snapshot_instances.erase(instance)
	_update()


func _update() -> void:
	if not _live:
		return
	var active := _snapshot_instances.filter(func(s: ChirpSnapshotInstance) -> bool: return s.get_level() > 0.0)
	active.sort_custom(func(a: ChirpSnapshotInstance, b: ChirpSnapshotInstance) -> bool:
		if a._snapshot.priority != b._snapshot.priority:
			return a._snapshot.priority < b._snapshot.priority
		return a._order < b._order)
	for bus: StringName in _managed_buses:
		_update_bus_volume(bus, active)
	for target: Dictionary in _effects.values():
		_update_effect(target, active)
	for target: Dictionary in _effect_switches.values():
		_update_effect_switch(target, active)


func _update_bus_volume(bus: StringName, active: Array) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index == -1:
		return
	var gain := db_to_linear(_bus_base_db[bus])
	for vca in _vcas:
		for bus_path in vca.buses:
			if resolve_bus(bus_path) == bus:
				gain *= _vca_gain.get(vca.name, 1.0)
				break
	for automation in _bus_automations:
		if automation.target == ChirpBusAutomation.Target.VOLUME and resolve_bus(automation.bus) == bus:
			var state := _chirp.parameters._get_state(automation.parameter) as ChirpParameter.State
			if state:
				gain *= ChirpAutomation.sample_curve(automation.curve, state.def, state.value)
	var db := linear_to_db(gain) if gain > 0.00001 else -80.0
	for instance: ChirpSnapshotInstance in active:
		var weight := instance.get_level()
		for override in instance._snapshot.bus_overrides:
			if override and override.override_volume and resolve_bus(override.bus) == bus:
				if override.mode == ChirpBusOverride.Mode.OVERRIDE:
					db = lerpf(db, override.volume_db, weight)
				else:
					db += override.volume_db * weight
	for ducking in _duckings:
		if resolve_bus(ducking.target_bus) == bus:
			db += ducking.amount_db * _duck_state[ducking].level
	AudioServer.set_bus_volume_db(index, maxf(db, -80.0))


func _update_effect(target: Dictionary, active: Array) -> void:
	var effect := _get_effect(target.bus, target.index)
	if effect == null:
		return
	var value := float(target.base)
	for automation in _bus_automations:
		if automation.target == ChirpBusAutomation.Target.EFFECT_PROPERTY \
				and automation.effect_index == target.index \
				and automation.effect_property == target.property \
				and resolve_bus(automation.bus) == target.bus:
			var state := _chirp.parameters._get_state(automation.parameter) as ChirpParameter.State
			if state and automation.curve:
				value = ChirpAutomation.sample_curve(automation.curve, state.def, state.value)
	for instance: ChirpSnapshotInstance in active:
		var weight := instance.get_level()
		for override in instance._snapshot.bus_overrides:
			if override and override.effect_index == target.index \
					and override.effect_property == target.property \
					and resolve_bus(override.bus) == target.bus:
				if override.mode == ChirpBusOverride.Mode.OVERRIDE:
					value = lerpf(value, override.effect_value, weight)
				else:
					value += override.effect_value * weight
	if target.base is int:
		effect.set(target.property, roundi(value))
	else:
		effect.set(target.property, value)


func _update_effect_switch(target: Dictionary, active: Array) -> void:
	var index := AudioServer.get_bus_index(target.bus)
	if index == -1 or target.index >= AudioServer.get_bus_effect_count(index):
		return
	var enabled: bool = target.base
	for instance: ChirpSnapshotInstance in active:
		for override in instance._snapshot.bus_overrides:
			if override and override.enable_effect and override.effect_index == target.index \
					and resolve_bus(override.bus) == target.bus:
				enabled = true
	AudioServer.set_bus_effect_enabled(index, target.index, enabled)


func _recapture() -> void:
	_managed_buses.clear()
	_bus_base_db.clear()
	_effects.clear()
	_effect_switches.clear()
	_configure(_vcas.duplicate(), _bus_automations.duplicate(), _snapshots.duplicate())


func _restore() -> void:
	for bus: StringName in _managed_buses:
		var index := AudioServer.get_bus_index(bus)
		if index != -1:
			AudioServer.set_bus_volume_db(index, _bus_base_db[bus])
	for target: Dictionary in _effects.values():
		var effect := _get_effect(target.bus, target.index)
		if effect:
			effect.set(target.property, target.base)
	for target: Dictionary in _effect_switches.values():
		var index := AudioServer.get_bus_index(target.bus)
		if index != -1 and target.index < AudioServer.get_bus_effect_count(index):
			AudioServer.set_bus_effect_enabled(index, target.index, target.base)


func _manage_bus(bus: StringName) -> void:
	if _managed_buses.has(bus):
		return
	var index := AudioServer.get_bus_index(bus)
	if index == -1:
		return
	_managed_buses[bus] = true
	if not _bus_base_db.has(bus):
		_bus_base_db[bus] = AudioServer.get_bus_volume_db(index)


func _manage_effect(bus: StringName, effect_index: int, property: String) -> void:
	var key := "%s|%d|%s" % [bus, effect_index, property]
	if _effects.has(key):
		return
	var effect := _get_effect(bus, effect_index)
	if effect == null:
		_chirp._warn_once("effect:" + key, "Chirp: bus '%s' has no effect at index %d." % [bus, effect_index])
		return
	var base: Variant = effect.get(property)
	if not (base is float or base is int):
		_chirp._warn_once("prop:" + key, "Chirp: %s has no numeric property '%s'." % [effect.get_class(), property])
		return
	_effects[key] = {bus = bus, index = effect_index, property = property, base = base}


func _manage_effect_switch(bus: StringName, effect_index: int) -> void:
	var key := "%s|%d" % [bus, effect_index]
	if _effect_switches.has(key) or _get_effect(bus, effect_index) == null:
		return
	var enabled := AudioServer.is_bus_effect_enabled(AudioServer.get_bus_index(bus), effect_index)
	_effect_switches[key] = {bus = bus, index = effect_index, base = enabled}


func _get_effect(bus: StringName, effect_index: int) -> AudioEffect:
	var index := AudioServer.get_bus_index(bus)
	if index == -1 or effect_index < 0 or effect_index >= AudioServer.get_bus_effect_count(index):
		return null
	return AudioServer.get_bus_effect(index, effect_index)


# --- effect bus pool ------------------------------------------------------------------

## Lends a pool bus carrying [param effects] and sending into [param send_to]; &"" when the pool
## is used up (the caller plays without effects).
func _acquire_effect_bus(send_to: StringName, effects: Array[AudioEffect]) -> StringName:
	if not _fx_created:
		_create_effect_buses()
	if _fx_free.is_empty():
		_chirp._warn_once("fx_pool", "Chirp: all %d effect buses are in use; playing without effects. Raise the \"%s\" project setting." \
			% [_fx_lent.size(), SETTING_EFFECT_POOL])
		return &""
	var bus: StringName = _fx_free.pop_back()
	_fx_lent[bus] = true
	var index := AudioServer.get_bus_index(bus)
	_clear_effects(index)
	for effect in effects:
		AudioServer.add_bus_effect(index, effect)
	AudioServer.set_bus_send(index, send_to)
	AudioServer.set_bus_volume_db(index, 0.0)
	AudioServer.set_bus_mute(index, false)
	AudioServer.set_bus_bypass_effects(index, false)
	return bus


func _release_effect_bus(bus: StringName) -> void:
	if not _fx_lent.has(bus):
		return
	_fx_lent.erase(bus)
	var index := AudioServer.get_bus_index(bus)
	if index != -1:
		_clear_effects(index)
		_fx_free.append(bus)


## EVENT scope: the bus and effects shared by every instance of [param event], lent on first use.
## [param make_effects] builds the effect copies. Returns {bus, effects}, or {} when the pool is used up.
func _acquire_event_effects(event: ChirpEvent, send_to: StringName, make_effects: Callable) -> Dictionary:
	var key := event.get_instance_id()
	if _event_fx.has(key):
		_event_fx[key].count += 1
		return _event_fx[key]
	var effects: Array[AudioEffect] = make_effects.call()
	var bus := _acquire_effect_bus(send_to, effects)
	if bus.is_empty():
		return {}
	_event_fx[key] = {bus = bus, effects = effects, count = 1}
	return _event_fx[key]


func _release_event_effects(event: ChirpEvent) -> void:
	var key := event.get_instance_id()
	if not _event_fx.has(key):
		return
	_event_fx[key].count -= 1
	if _event_fx[key].count <= 0:
		_release_effect_bus(_event_fx[key].bus)
		_event_fx.erase(key)


func _create_effect_buses() -> void:
	_fx_created = true
	var size: int = ProjectSettings.get_setting(SETTING_EFFECT_POOL, DEFAULT_EFFECT_POOL)
	for i in size:
		AudioServer.add_bus()
		var bus := StringName(EFFECT_BUS_PREFIX + str(i + 1))
		AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
		_fx_free.append(bus)


## Removes the pool's buses (and any left in a saved bus layout by an earlier run).
func _remove_effect_buses() -> void:
	for index in range(AudioServer.bus_count - 1, 0, -1):
		if AudioServer.get_bus_name(index).begins_with(EFFECT_BUS_PREFIX):
			AudioServer.remove_bus(index)
	_fx_created = false
	_fx_free.clear()
	_fx_lent.clear()
	_event_fx.clear()


static func _clear_effects(index: int) -> void:
	for i in range(AudioServer.get_bus_effect_count(index) - 1, -1, -1):
		AudioServer.remove_bus_effect(index, i)


func _find_snapshot(snapshot_or_name: Variant) -> ChirpSnapshot:
	if snapshot_or_name is ChirpSnapshot:
		return snapshot_or_name
	for snapshot in _snapshots:
		if snapshot.name == String(snapshot_or_name):
			return snapshot
	return null


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
