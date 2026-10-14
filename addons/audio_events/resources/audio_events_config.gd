@tool
class_name AudioEventsConfig
extends Resource
## Project-wide settings. Point the "audio_events/config" project setting at a saved copy.

## Every AudioEvent saved under this folder is addressable by path:
## res://audio/events/SFX/Flap.tres -> "event:/SFX/Flap".
@export_dir var events_dir := "res://audio/events"
@export var global_parameters: Array[AudioEventParameter] = []
@export var vcas: Array[AudioEventVCA] = []
## Pause all events while a mobile app is in the background.
@export var pause_on_app_background := true
