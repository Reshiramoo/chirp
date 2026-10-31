@tool
@icon("res://addons/chirp/icons/bus_automation.svg")
class_name ChirpBusAutomation
extends Resource
## Maps a global parameter onto a bus's volume or one of its effect properties.
## The curve's X axis spans the parameter's range (0 = min, 1 = max).

enum Target {
	VOLUME, ## Curve Y multiplies the bus volume (linear gain).
	EFFECT_PROPERTY, ## Curve Y is the property's value (raise the curve's max value as needed).
}

## "bus:/Music", or "bus:/" for Master.
@export var bus := "bus:/"
## Name of a global parameter.
@export var parameter := ""
@export var target := Target.VOLUME
## Position of the effect in the bus's effect list. Used by EFFECT_PROPERTY.
@export var effect_index := 0
## E.g. "cutoff_hz". Used by EFFECT_PROPERTY.
@export var effect_property := ""
@export var curve: Curve
