@tool
class_name ChirpVCA
extends Resource
## A volume control over several buses that does not route audio itself,
## e.g. a "Music" slider covering both the music and stinger buses.

@export var name := ""
## Bus paths ("bus:/Music") or plain Godot bus names.
@export var buses := PackedStringArray()
