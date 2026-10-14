@tool
@icon("res://addons/chirp/icons/automation.svg")
class_name ChirpAutomation
extends Resource
## Drives an event's volume or pitch from a parameter (through a curve) or along its timeline.
##
## PARAMETER source: the curve's X axis spans the parameter's range (0 = min, 1 = max).
## TIMELINE source (TIMELINE events): [member points] give the value along the timeline.
## Either way the value multiplies the property: linear gain for VOLUME, pitch scale for PITCH.

enum Target { VOLUME, PITCH }

enum Source {
	PARAMETER, ## A parameter's value, through [member curve].
	TIMELINE, ## The playhead position on a TIMELINE event, through [member points].
}

## Value range the timeline lane edits within, per target.
const TIMELINE_RANGE := {Target.VOLUME: Vector2(0.0, 1.0), Target.PITCH: Vector2(0.5, 2.0)}

@export var source := Source.PARAMETER:
	set(value):
		source = value
		notify_property_list_changed()
@export var parameter := ""
## Read the value from a global parameter instead of the event's own.
@export var global := false
@export var target := Target.VOLUME
@export var curve: Curve
## TIMELINE: (position in the event's timeline units, value) pairs, sorted by position. The value
## is linear between points and holds before the first and after the last. Empty = no change.
@export var points := PackedVector2Array()


func evaluate(definition: ChirpParameter, value: float) -> float:
	return sample_curve(curve, definition, value)


## TIMELINE: the value at [param position] (timeline units).
func value_at(position: float) -> float:
	if points.is_empty():
		return 1.0
	if position <= points[0].x:
		return points[0].y
	for i in range(1, points.size()):
		if position < points[i].x:
			var a := points[i - 1]
			var b := points[i]
			return lerpf(a.y, b.y, (position - a.x) / (b.x - a.x)) if b.x > a.x else b.y
	return points[-1].y


## Samples [param curve] at [param value]'s position within the parameter's range.
## A missing curve gives 1.0 (no change).
static func sample_curve(curve: Curve, definition: ChirpParameter, value: float) -> float:
	if curve == null:
		return 1.0
	var lo := definition.get_min()
	var hi := definition.get_max()
	var t := 0.0 if hi <= lo else clampf((value - lo) / (hi - lo), 0.0, 1.0)
	return curve.sample_baked(lerpf(curve.min_domain, curve.max_domain, t))


func _validate_property(property: Dictionary) -> void:
	if source == Source.TIMELINE and property.name in ["parameter", "global", "curve"] \
			or source == Source.PARAMETER and property.name == "points":
		property.usage = PROPERTY_USAGE_NO_EDITOR
