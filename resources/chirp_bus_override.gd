@tool
@icon("res://addons/chirp/icons/bus_override.svg")
class_name ChirpBusOverride
extends Resource
## One change a snapshot makes to a bus: its volume, one property of one of its
## effects, and/or switching one of its effects on.

enum Mode {
	OVERRIDE, ## Move toward the value as the snapshot's intensity rises.
	BLEND, ## Add the value, scaled by the snapshot's intensity.
}

## "bus:/SFX", or "bus:/" for Master.
@export var bus := "bus:/"
@export var mode := Mode.OVERRIDE

@export_group("Volume")
@export var override_volume := false
## OVERRIDE: target volume. BLEND: dB added at full intensity.
@export_range(-80.0, 24.0, 0.1, "suffix:dB") var volume_db := 0.0

@export_group("Effect")
## Position of the effect in the bus's effect list (as shown in the Audio panel). -1 = none.
@export var effect_index := -1
## Property to change, e.g. "cutoff_hz" on AudioEffectLowPassFilter. Empty = none.
@export var effect_property := ""
## OVERRIDE: target value. BLEND: amount added at full intensity.
@export var effect_value := 0.0
## Switch the effect on while the snapshot is active, even if it's disabled on the bus.
@export var enable_effect := false
