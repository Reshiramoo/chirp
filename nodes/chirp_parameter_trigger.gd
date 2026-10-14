@icon("res://addons/chirp/icons/parameter_trigger.svg")
class_name ChirpParameterTrigger
extends Node
## Sets parameters on emitters when a trigger fires, e.g. switch the music to "Cave" when the
## player enters an Area. Uses the same triggers as ChirpEmitter2D/3D.

## When to apply the parameters. NONE: only via trigger() from script.
@export var trigger_on := ChirpEmitterCore.Trigger.NONE
## ChirpEmitter2D/3D to set the parameters on. Empty = the parent.
@export var targets: Array[NodePath] = []
## Parameter values to apply (local parameters of the targets' events).
@export var parameters: Dictionary[String, float] = {}
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


## Applies the parameters to every target now. Targets keep the values for instances they start later.
func trigger() -> void:
	if trigger_once and _triggered:
		return
	_triggered = true
	for target in get_targets():
		for parameter_name: String in parameters:
			target.set_parameter(parameter_name, parameters[parameter_name])


## The emitters [member targets] resolve to (the parent when empty). Paths that don't lead to an
## emitter are skipped with a warning.
func get_targets() -> Array[Node]:
	var found: Array[Node] = []
	var paths: Array[NodePath] = targets.duplicate()
	if paths.is_empty():
		paths.append(NodePath(".."))
	for path in paths:
		var node := get_node_or_null(path)
		if node is ChirpEmitter2D or node is ChirpEmitter3D:
			found.append(node)
		else:
			push_warning("%s: target '%s' is not a ChirpEmitter2D/3D." % [get_path(), path])
	return found
