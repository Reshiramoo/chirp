@tool
class_name ChirpParameter
extends Resource
## A named value that game code sets at run time to drive an event (local) or the
## whole mix (global). Mirrors FMOD Studio's continuous / discrete / labeled parameters.

enum Kind { CONTINUOUS, DISCRETE, LABELED }

@export var name := ""
@export var kind := Kind.CONTINUOUS
@export var min_value := 0.0
@export var max_value := 1.0
@export var default_value := 0.0
## Only used by LABELED parameters; the value is the index of the label.
@export var labels := PackedStringArray()
## Units per second the value glides toward a newly set target. 0 = jump instantly.
@export_range(0.0, 1000.0, 0.01, "or_greater") var seek_speed := 0.0


func get_min() -> float:
	return 0.0 if kind == Kind.LABELED else min_value


func get_max() -> float:
	return float(maxi(labels.size() - 1, 0)) if kind == Kind.LABELED else max_value


func clamp_value(value: float) -> float:
	if kind != Kind.CONTINUOUS:
		value = roundf(value)
	return clampf(value, get_min(), get_max())


## Returns the value for [param label], or -1 if the label does not exist.
func label_to_value(label: String) -> float:
	for i in labels.size():
		if labels[i].nocasecmp_to(label) == 0:
			return float(i)
	return -1.0


## Live value of one parameter, owned by an event instance (local) or the manager (global).
class State:
	var def: ChirpParameter
	var value := 0.0
	var target := 0.0

	func _init(definition: ChirpParameter) -> void:
		def = definition
		value = def.clamp_value(def.default_value)
		target = value

	func set_target(new_value: float, instant: bool) -> void:
		target = def.clamp_value(new_value)
		if instant or def.seek_speed <= 0.0:
			value = target

	func step(delta: float) -> void:
		if value != target:
			value = move_toward(value, target, def.seek_speed * delta)
