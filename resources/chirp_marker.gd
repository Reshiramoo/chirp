@tool
class_name ChirpMarker
extends Resource
## Something placed on an event's timeline. Positions use the event's timeline_units
## (seconds or beats). The inspector only shows the fields the chosen kind uses.

enum Kind {
	MARKER, ## A named point; fires the instance's timeline_marker signal.
	TEMPO, ## Sets the tempo and time signature from here on; drives timeline_beat and quantization.
	LOOP_REGION, ## Loops between position and end while the condition holds.
	SUSTAIN_POINT, ## Holds the playhead here until key_off() or the condition stops holding.
	DESTINATION, ## A named point that transitions jump to.
	TRANSITION, ## When the playhead reaches it and the condition holds, jump to destination.
	TRANSITION_REGION, ## While the playhead is inside and the condition holds, jump to destination.
}

enum Quantization {
	NONE, ## Jump straight away.
	BEAT, ## Jump on the next beat.
	BAR, ## Jump on the next bar.
}

const _FIELDS := {
	Kind.MARKER: ["name", "position"],
	Kind.TEMPO: ["position", "bpm", "beats_per_bar", "beat_unit"],
	Kind.LOOP_REGION: ["position", "end", "condition_parameter", "condition_min", "condition_max", "probability"],
	Kind.SUSTAIN_POINT: ["position", "condition_parameter", "condition_min", "condition_max"],
	Kind.DESTINATION: ["name", "position"],
	Kind.TRANSITION: ["position", "destination", "quantization",
		"condition_parameter", "condition_min", "condition_max", "probability"],
	Kind.TRANSITION_REGION: ["position", "end", "destination", "quantization",
		"condition_parameter", "condition_min", "condition_max", "probability"],
}
const _ALL_FIELDS := ["name", "position", "end", "bpm", "beats_per_bar", "beat_unit", "destination",
	"quantization", "condition_parameter", "condition_min", "condition_max", "probability"]

@export var kind := Kind.MARKER:
	set(value):
		kind = value
		notify_property_list_changed()
@export var name := ""
@export var position := 0.0
## End of a region, in the same units as position.
@export var end := 0.0

@export_group("Tempo")
@export_range(1.0, 999.0, 0.01) var bpm := 120.0
@export_range(1, 32) var beats_per_bar := 4
@export_range(1, 32) var beat_unit := 4

@export_group("Transition")
## Name of a DESTINATION marker.
@export var destination := ""
@export var quantization := Quantization.NONE

@export_group("Condition")
## Local or global parameter that must be within [condition_min, condition_max]. Empty = always.
@export var condition_parameter := ""
@export var condition_min := 0.0
@export var condition_max := 1.0
## Chance the marker acts each time it's reached.
@export_range(0.0, 100.0, 1.0, "suffix:%") var probability := 100.0


func is_region() -> bool:
	return kind == Kind.LOOP_REGION or kind == Kind.TRANSITION_REGION


func _validate_property(property: Dictionary) -> void:
	if property.name in _ALL_FIELDS and property.name not in _FIELDS[kind]:
		property.usage = PROPERTY_USAGE_NO_EDITOR
