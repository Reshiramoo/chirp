@icon("res://addons/audio_events/icons/emitter.svg")
class_name AudioEventEmitter2D
extends Node2D
## Plays an AudioEvent at this node's position, following it as it moves.
## One-shot events start a new instance on every play(); looping events restart.

@export var event: AudioEvent
@export var play_on := AudioEventEmitterCore.Trigger.NONE
@export var stop_on := AudioEventEmitterCore.Trigger.NONE
## Node whose signals drive ENTERED / EXITED / MOUSE_* triggers. Empty = parent.
@export var trigger_source: NodePath
## Only bodies/areas in this group fire ENTERED / EXITED. Empty = any.
@export var trigger_group: StringName
## Parameter values applied when an instance starts.
@export var parameters: Dictionary[String, float] = {}
## Stopping plays the event's envelope release instead of cutting off.
@export var allow_fadeout := true
## Only the first play() succeeds.
@export var trigger_once := false

@export_group("Attenuation")
@export var override_attenuation := false
@export var max_distance := 2000.0
@export_exp_easing("attenuation") var attenuation := 1.0

var _core := AudioEventEmitterCore.new(self)


func _ready() -> void:
	_core.setup()


func _exit_tree() -> void:
	_core.on_exit_tree()


func play() -> void:
	_core.play()


func stop() -> void:
	_core.stop()


func set_parameter(parameter_name: String, value: float) -> void:
	_core.set_parameter(parameter_name, value)


func is_playing() -> bool:
	return _core.is_playing()
