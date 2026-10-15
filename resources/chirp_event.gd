@tool
@icon("res://addons/chirp/icons/event.svg")
class_name ChirpEvent
extends Resource
## An instanceable unit of sound: instruments plus the parameters, automation and
## envelope that control them. Equivalent to an FMOD Studio event with an action sheet.

enum SheetMode {
	SIMULTANEOUS, ## Trigger every instrument when the event starts.
	CONSECUTIVE, ## Trigger instruments one after another, in list order.
	TIMELINE, ## Instruments sit on a timeline (their start/length); markers control the playhead.
	PARAMETER, ## Instruments sit on sheet_parameter's axis (their start/length); each plays while the value is in its range.
}

enum TimelineUnits {
	SECONDS,
	BEATS, ## Beats of the TEMPO markers (120 BPM before the first one).
}

## How volume falls off with distance from the listener, on spatial events.
enum Rolloff {
	GODOT, ## Godot's own attenuation: attenuation_2d / max_distance_2d, unit_size_3d / max_distance_3d.
	LINEAR, ## Full volume up to min_distance, falling in a straight line to silence at max_distance.
	LINEAR_SQUARED, ## Like LINEAR, squared: falls faster near the listener, gentler toward max_distance.
	INVERSE, ## Natural falloff: min_distance / distance. Stops falling at max_distance (never silent).
	INVERSE_TAPERED, ## INVERSE nearby, tapering to silence at max_distance.
	CUSTOM, ## rolloff_curve from min_distance (X 0) to max_distance (X 1).
}

## Who gets their own copy of [member effects].
enum EffectScope {
	INSTANCE, ## Each instance plays through its own effect bus (e.g. occlusion per emitter).
	EVENT, ## All instances share one effect bus (cheaper; e.g. this event always sounds like a radio).
}

enum Stealing {
	OLDEST, ## Stop the instance that started first.
	QUIETEST, ## Stop the instance with the lowest current volume.
	FURTHEST, ## Stop the instance furthest from the camera.
	NONE, ## Don't start the new instance.
}

@export var instruments: Array[ChirpInstrument] = []
@export var sheet_mode := SheetMode.SIMULTANEOUS:
	set(value):
		sheet_mode = value
		notify_property_list_changed()
## A persistent event keeps playing after its content ends, until stopped.
@export var persistent := false
## "bus:/SFX" or "bus:/SFX/UI" (the last segment names the Godot bus), "bus:/" for Master.
## Empty = the bus of the sound directory the event is saved in (see the "chirp/sound_directories" setting).
@export var bus := ""
@export_range(-80.0, 24.0, 0.1, "suffix:dB") var volume_db := 0.0
@export_range(0.01, 4.0, 0.01) var pitch_scale := 1.0
@export var parameters: Array[ChirpParameter] = []
@export var automations: Array[ChirpAutomation] = []
@export var modulators: Array[ChirpLFO] = []
@export var envelope: ChirpEnvelope

@export_group("Effects")
## Effects the event plays through, in order (e.g. AudioEffectLowPassFilter). They run on a bus
## borrowed from Chirp's pool (see Chirp.mixer), which feeds the event's bus. Automate their
## properties with EFFECT automations. Keep reverbs on a shared bus instead: they are expensive.
@export var effects: Array[AudioEffect] = []
@export var effect_scope := EffectScope.INSTANCE

@export_group("Timeline")
## Units for instrument start/length and marker positions on a TIMELINE event.
@export var timeline_units := TimelineUnits.SECONDS
@export var markers: Array[ChirpMarker] = []

@export_group("Parameter Sheet")
## PARAMETER sheets: the local or global parameter whose value places the playhead.
@export var sheet_parameter := ""

@export_group("Instance Limits")
## 0 = unlimited.
@export_range(0, 64) var max_instances := 0
@export var stealing := Stealing.OLDEST
## Minimum time between starts of this event.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s") var cooldown := 0.0

@export_group("Attenuation")
## How volume falls off with distance. Anything but GODOT replaces the 2D/3D attenuation settings
## with min_distance and max_distance, measured from Chirp's listener (see ChirpListener2D/3D).
@export var rolloff := Rolloff.GODOT:
	set(value):
		rolloff = value
		notify_property_list_changed()
## Distance up to which the event plays at full volume (pixels in 2D, meters in 3D).
@export_range(0.0, 1000.0, 0.01, "or_greater") var min_distance := 1.0
## Distance at which the roll-off ends (silent, except INVERSE).
@export_range(0.0, 10000.0, 0.01, "or_greater") var max_distance := 20.0
## CUSTOM: volume (Y, 0..1) from min_distance (X 0) to max_distance (X 1).
@export var rolloff_curve: Curve

@export_group("Spatial 2D")
@export var max_distance_2d := 2000.0
@export_exp_easing("attenuation") var attenuation_2d := 1.0

@export_group("Spatial 3D")
@export var unit_size_3d := 10.0
## 0 = no limit.
@export var max_distance_3d := 0.0


## True when the event ends by itself: not persistent, no looping instruments, no endless
## scatterers, and no loop regions or sustain points.
func is_one_shot() -> bool:
	if persistent:
		return false
	for instrument in instruments:
		if instrument and (instrument.loop and instrument.kind in [ChirpInstrument.Kind.SOUND, ChirpInstrument.Kind.PROGRAMMER]
				or instrument.kind == ChirpInstrument.Kind.SCATTERER and instrument.spawn_total == 0):
			return false
	if sheet_mode == SheetMode.TIMELINE:
		for marker in markers:
			if marker and (marker.kind == ChirpMarker.Kind.LOOP_REGION or marker.kind == ChirpMarker.Kind.SUSTAIN_POINT):
				return false
	return true


## Linear volume at [param distance] for [member rolloff] between [param near] and [param far]
## (the event's min/max distance unless overridden). 1.0 for GODOT.
func rolloff_gain(distance: float, near := min_distance, far := max_distance) -> float:
	far = maxf(far, near)
	var t := 0.0 if far <= near else clampf((distance - near) / (far - near), 0.0, 1.0)
	var inverse := 1.0 if distance <= near or near <= 0.0 else near / minf(distance, far)
	match rolloff:
		Rolloff.LINEAR:
			return 1.0 - t
		Rolloff.LINEAR_SQUARED:
			return (1.0 - t) * (1.0 - t)
		Rolloff.INVERSE:
			return inverse
		Rolloff.INVERSE_TAPERED:
			return minf(inverse, (1.0 - t) * (1.0 - t))
		Rolloff.CUSTOM:
			if rolloff_curve == null:
				return 1.0 - t
			return clampf(rolloff_curve.sample_baked(lerpf(rolloff_curve.min_domain, rolloff_curve.max_domain, t)), 0.0, 1.0)
	return 1.0


func find_parameter(parameter_name: String) -> ChirpParameter:
	for parameter in parameters:
		if parameter and parameter.name.nocasecmp_to(parameter_name) == 0:
			return parameter
	return null


const _GODOT_ATTENUATION := ["max_distance_2d", "attenuation_2d", "unit_size_3d", "max_distance_3d"]


func _validate_property(property: Dictionary) -> void:
	var name: String = property.name
	if name == "sheet_parameter" and sheet_mode != SheetMode.PARAMETER \
			or name in ["timeline_units", "markers"] and sheet_mode != SheetMode.TIMELINE:
		property.usage = PROPERTY_USAGE_NO_EDITOR
		return
	if rolloff == Rolloff.GODOT and name in ["min_distance", "max_distance", "rolloff_curve"] \
			or rolloff != Rolloff.GODOT and name in _GODOT_ATTENUATION \
			or name == "rolloff_curve" and rolloff != Rolloff.CUSTOM:
		property.usage = PROPERTY_USAGE_NO_EDITOR
