@tool
class_name ChirpAutomation
extends Resource
## Maps a parameter onto an event property through a curve.
## The curve's X axis spans the parameter's range (0 = min, 1 = max).
## Its Y value multiplies the property: linear gain for VOLUME, pitch scale for PITCH
## (raise the curve's max value above 1 to pitch up).

enum Target { VOLUME, PITCH }

@export var parameter := ""
## Read the value from a global parameter instead of the event's own.
@export var global := false
@export var target := Target.VOLUME
@export var curve: Curve


func evaluate(definition: ChirpParameter, value: float) -> float:
	if curve == null:
		return 1.0
	var lo := definition.get_min()
	var hi := definition.get_max()
	var t := 0.0 if hi <= lo else clampf((value - lo) / (hi - lo), 0.0, 1.0)
	return curve.sample_baked(lerpf(curve.min_domain, curve.max_domain, t))
