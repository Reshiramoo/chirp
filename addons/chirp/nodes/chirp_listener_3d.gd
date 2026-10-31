@icon("res://addons/chirp/icons/listener_3d.svg")
class_name ChirpListener3D
extends Node3D
## Where Chirp listens from in 3D: distance roll-off, built-in parameters and FURTHEST stealing
## are measured from here instead of the camera.
##
## Put it on the camera (or wherever you hear from). Set attenuation_object to measure distance from
## another node, e.g. the player character in a third-person game, while direction and panning
## still follow this node. With drive_audio_listener on, it also makes Godot's AudioListener3D
## follow this node, so panning and Doppler match.

## Make this the listener Chirp uses. The most recently made current listener wins.
@export var current := true:
	set(value):
		current = value
		if is_inside_tree():
			_sync_current()
## Distance is measured from this node instead (e.g. the player character). Empty = this node.
@export var attenuation_object: NodePath
## Also make an AudioListener3D at this node current, so Godot's panning follows it.
@export var drive_audio_listener := true

var _audio_listener: AudioListener3D


func _enter_tree() -> void:
	_sync_current()


func _exit_tree() -> void:
	var chirp := _chirp()
	if chirp:
		chirp.events._remove_listener(self)


## Makes this the current listener.
func make_current() -> void:
	current = true


## Stops being the current listener; Chirp falls back to the previous one, else the camera.
func clear_current() -> void:
	current = false


func is_current() -> bool:
	var chirp := _chirp()
	return chirp != null and chirp.events._current_listener(true) == self


## Global position distance is measured from: the attenuation object's, else this node's.
func get_attenuation_position() -> Vector3:
	var object := get_node_or_null(attenuation_object) as Node3D if not attenuation_object.is_empty() else null
	return object.global_position if object else global_position


func _sync_current() -> void:
	var chirp := _chirp()
	if chirp:
		if current:
			chirp.events._add_listener(self)
		else:
			chirp.events._remove_listener(self)
	if drive_audio_listener and current:
		if _audio_listener == null:
			_audio_listener = AudioListener3D.new()
			_audio_listener.name = "AudioListener3D"
			add_child(_audio_listener, false, INTERNAL_MODE_FRONT)
		if _audio_listener.is_inside_tree():
			_audio_listener.make_current()
		else:
			_audio_listener.ready.connect(_audio_listener.make_current, CONNECT_ONE_SHOT)
	elif _audio_listener and _audio_listener.is_inside_tree():
		_audio_listener.clear_current()


func _chirp() -> Node:
	return get_node_or_null("/root/Chirp") if is_inside_tree() else null
