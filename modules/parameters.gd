@tool
extends RefCounted
## Chirp.parameters: global parameters, shared by every event that automates on them.
## Define them in the ChirpConfig resource ("chirp/config" project setting).

var _chirp: Node
var _states := {} # lowercase name -> ChirpParameter.State


func _init(chirp: Node) -> void:
	_chirp = chirp


func set_value(parameter_name: String, value: float) -> void:
	var state := _get_state(parameter_name)
	if state == null:
		_chirp._warn_once("global:" + parameter_name, "Chirp: unknown global parameter '%s'." % parameter_name)
		return
	state.set_target(value, false)


func set_label(parameter_name: String, label: String) -> void:
	var state := _get_state(parameter_name)
	if state == null:
		set_value(parameter_name, 0.0) # reports the missing parameter
		return
	var value := state.def.label_to_value(label)
	if value < 0.0:
		_chirp._warn("Chirp: global parameter '%s' has no label '%s'." % [parameter_name, label])
		return
	state.set_target(value, false)


func get_value(parameter_name: String) -> float:
	var state := _get_state(parameter_name)
	return state.value if state else 0.0


# --- internals ---------------------------------------------------------------------

func _configure(definitions: Array[ChirpParameter]) -> void:
	_states.clear()
	for definition in definitions:
		if definition:
			_states[definition.name.to_lower()] = ChirpParameter.State.new(definition)


func _process(delta: float) -> void:
	for state: ChirpParameter.State in _states.values():
		state.step(delta)


func _get_state(parameter_name: String) -> ChirpParameter.State:
	return _states.get(parameter_name.to_lower())
