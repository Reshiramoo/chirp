@tool
@icon("res://addons/chirp/icons/automation.svg")
class_name ChirpAutomation
extends Resource
## Drives an event's volume or pitch from a parameter (through a curve) or along its timeline.
##
## PARAMETER source: the curve's X axis spans the parameter's range (0 = min, 1 = max).
## TIMELINE source (TIMELINE events): [member points] give the value along the timeline.
## VOLUME and PITCH values multiply the property (linear gain, pitch scale); PAN and EFFECT values
## set it (PAN -1 left .. 1 right; EFFECT: the effect property's own value).

enum Target {
	VOLUME, ## Linear gain multiplier.
	PITCH, ## Pitch scale multiplier.
	PAN, ## Stereo pan, -1 (left) to 1 (right). Chirp adds a panner to the event's effect chain.
	EFFECT, ## A property of one of the event's effects: effect_index, effect_property.
}

enum Source {
	PARAMETER, ## A parameter's value, through [member curve].
	TIMELINE, ## The playhead position on a TIMELINE event, through [member points].
}

## Value range the timeline lane edits within, per target (EFFECT lanes use value_range).
const TIMELINE_RANGE := {Target.VOLUME: Vector2(0.0, 1.0), Target.PITCH: Vector2(0.5, 2.0),
	Target.PAN: Vector2(-1.0, 1.0)}

@export var source := Source.PARAMETER:
	set(value):
		source = value
		notify_property_list_changed()
@export var parameter := ""
## Read the value from a global parameter instead of the event's own.
@export var global := false
@export var target := Target.VOLUME:
	set(value):
		target = value
		notify_property_list_changed()
## EFFECT: which of the event's effects (its position in ChirpEvent.effects).
@export var effect_index := 0
## EFFECT: the effect property to set, e.g. "cutoff_hz".
@export var effect_property := ""
## EFFECT on a timeline: the value range its lane edits within (e.g. 20..20000 for a cutoff).
@export var value_range := Vector2(0.0, 1.0)
@export var curve: Curve
## TIMELINE: (position in the event's timeline units, value) pairs, sorted by position. The value
## is linear between points and holds before the first and after the last. Empty = no change.
@export var points := PackedVector2Array()


func evaluate(definition: ChirpParameter, value: float) -> float:
	return sample_curve(curve, definition, value)


## The value range a timeline lane edits within: value_range for EFFECT, else from the target.
func lane_range() -> Vector2:
	return value_range if target == Target.EFFECT else TIMELINE_RANGE[target]


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
			or source == Source.PARAMETER and property.name in ["points", "value_range"] \
			or target != Target.EFFECT and property.name in ["effect_index", "effect_property", "value_range"]:
		property.usage = PROPERTY_USAGE_NO_EDITOR
