@tool
@icon("res://addons/chirp/icons/envelope.svg")
class_name ChirpEnvelope
extends Resource
## AHDSR volume envelope for an event. Release is the fade-out used when the event
## is stopped with fade-out allowed.

@export_range(0.0, 10.0, 0.001, "or_greater", "suffix:s") var attack := 0.0
@export_range(0.0, 10.0, 0.001, "or_greater", "suffix:s") var hold := 0.0
@export_range(0.0, 10.0, 0.001, "or_greater", "suffix:s") var decay := 0.0
@export_range(0.0, 1.0, 0.01) var sustain := 1.0
@export_range(0.0, 10.0, 0.001, "or_greater", "suffix:s") var release := 0.0


## Linear level [param time] seconds after the event started.
func level_at(time: float) -> float:
	if time < attack:
		return time / attack
	time -= attack
	if time < hold:
		return 1.0
	time -= hold
	if time < decay:
		return lerpf(1.0, sustain, time / decay)
	return sustain
