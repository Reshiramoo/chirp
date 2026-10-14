@tool
class_name ChirpParameter
extends Resource
## A named value that game code sets at run time to drive an event (local) or the
## whole mix (global). Mirrors FMOD Studio's continuous / discrete / labeled parameters.

enum Kind { CONTINUOUS, DISCRETE, LABELED }

## Built-in parameters are set automatically every frame from the event's position
## relative to the listener; game code can't set them. Angles are in degrees.
enum BuiltIn {
	NONE, ## A normal parameter, set by game code.
	DISTANCE, ## Distance to the listener. Set max_value to the distance you care about.
	DISTANCE_NORMALIZED, ## 0 at the event's min distance, 1 at its max distance.
	DIRECTION, ## Where the event is around the listener: 0 ahead, 90 right, -90 left, ±180 behind. In 2D "ahead" is up.
	ELEVATION, ## Angle above (+) or below (-) the listener's horizontal plane. Always 0 in 2D.
	EVENT_CONE_ANGLE, ## Angle between where the emitter faces and the listener: 0 facing it, 180 facing away.
	EVENT_ORIENTATION, ## Like EVENT_CONE_ANGLE but signed: + when the listener is to the emitter's right.
	SPEED, ## Speed of the event relative to the listener. Set max_value as needed.
	SPEED_ABSOLUTE, ## Speed of the event itself. Set max_value as needed.
}

@export var name := ""
@export var kind := Kind.CONTINUOUS
@export var built_in := BuiltIn.NONE
@export var min_value := 0.0
@export var max_value := 1.0
@export var default_value := 0.0
## Only used by LABELED parameters; the value is the index of the label.
@export var labels := PackedStringArray()
## Units per second the value glides toward a newly set target. 0 = jump instantly.
@export_range(0.0, 1000.0, 0.01, "or_greater") var seek_speed := 0.0


func get_min() -> float:
	match built_in:
		BuiltIn.DISTANCE_NORMALIZED, BuiltIn.EVENT_CONE_ANGLE:
			return 0.0
		BuiltIn.DIRECTION, BuiltIn.EVENT_ORIENTATION:
			return -180.0
		BuiltIn.ELEVATION:
			return -90.0
	return 0.0 if kind == Kind.LABELED else min_value


func get_max() -> float:
	match built_in:
		BuiltIn.DISTANCE_NORMALIZED:
			return 1.0
		BuiltIn.DIRECTION, BuiltIn.EVENT_ORIENTATION, BuiltIn.EVENT_CONE_ANGLE:
			return 180.0
		BuiltIn.ELEVATION:
			return 90.0
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
