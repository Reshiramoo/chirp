@icon("res://addons/chirp/icons/global_parameter_trigger.svg")
class_name ChirpGlobalParameterTrigger
extends Node
## Sets global parameters when a trigger fires, e.g. raise "Danger" while the player is inside
## an Area. Uses the same triggers as ChirpEmitter2D/3D.

## When to apply the values. NONE: only via trigger() from script.
@export var trigger_on := ChirpEmitterCore.Trigger.NONE
## Global parameter values to apply.
@export var parameters: Dictionary[String, float] = {}
## Global labeled parameters to set by label, e.g. {"Weather": "Rain"}.
@export var labels: Dictionary[String, String] = {}
## Node whose signals drive ENTERED / EXITED / MOUSE_* (and SHOWN / HIDDEN). Empty = parent.
@export var trigger_source: NodePath
## Only bodies/areas in this group fire ENTERED / EXITED. Empty = any.
@export var trigger_group: StringName
## Only the first trigger applies.
@export var trigger_once := false

var _core := ChirpEmitterCore.new(self)
var _triggered := false


func _ready() -> void:
	_core.wire(trigger_on, trigger)


func _exit_tree() -> void:
	if trigger_on == ChirpEmitterCore.Trigger.EXIT_TREE:
		trigger()


## Applies the values now.
func trigger() -> void:
	if trigger_once and _triggered:
		return
	_triggered = true
	var chirp := get_node_or_null("/root/Chirp")
	if chirp == null:
		return
	for parameter_name: String in parameters:
		chirp.parameters.set_value(parameter_name, parameters[parameter_name])
	for parameter_name: String in labels:
		chirp.parameters.set_label(parameter_name, labels[parameter_name])
