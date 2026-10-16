@tool
@icon("res://addons/chirp/icons/ducking.svg")
class_name ChirpDucking
extends Resource
## Turns one bus down while another is busy: music under dialogue, ambience under a big
## explosion. Add it to ChirpConfig.duckings, or at runtime with Chirp.mixer.add_ducking().

enum Trigger {
	EVENTS, ## While any event routed into trigger_bus (or a bus below it) is playing.
	LEVEL, ## While trigger_bus is louder than threshold_db (a sidechain: follows the actual sound).
}

## The bus turned down, as a bus path ("bus:/Music") or a Godot bus name.
@export var target_bus := ""
## The bus whose activity turns target_bus down.
@export var trigger_bus := ""
@export var trigger := Trigger.EVENTS:
	set(value):
		trigger = value
		notify_property_list_changed()
## How far down target_bus goes when fully ducked.
@export_range(-80.0, 0.0, 0.1, "suffix:dB") var amount_db := -12.0
## LEVEL: trigger_bus's peak level that counts as busy.
@export_range(-80.0, 6.0, 0.1, "suffix:dB") var threshold_db := -40.0
## Seconds to go fully down once triggered.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s") var attack := 0.1
## Seconds to stay down after the trigger stops (bridges gaps between lines of dialogue).
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s") var hold := 0.2
## Seconds to come back up after the hold.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s") var release := 0.5


func _validate_property(property: Dictionary) -> void:
	if property.name == "threshold_db" and trigger != Trigger.LEVEL:
		property.usage = PROPERTY_USAGE_NO_EDITOR
