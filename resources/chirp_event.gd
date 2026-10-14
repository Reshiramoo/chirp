@tool
class_name ChirpEvent
extends Resource
## An instanceable unit of sound: instruments plus the parameters, automation and
## envelope that control them. Equivalent to an FMOD Studio event with an action sheet.

enum SheetMode {
	SIMULTANEOUS, ## Trigger every instrument when the event starts.
	CONSECUTIVE, ## Trigger instruments one after another, in list order.
	TIMELINE, ## Instruments sit on a timeline (their start/length); markers control the playhead.
}

enum TimelineUnits {
	SECONDS,
	BEATS, ## Beats of the TEMPO markers (120 BPM before the first one).
}

enum Stealing {
	OLDEST, ## Stop the instance that started first.
	QUIETEST, ## Stop the instance with the lowest current volume.
	FURTHEST, ## Stop the instance furthest from the camera.
	NONE, ## Don't start the new instance.
}

@export var instruments: Array[ChirpInstrument] = []
@export var sheet_mode := SheetMode.SIMULTANEOUS
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

@export_group("Timeline")
## Units for instrument start/length and marker positions on a TIMELINE event.
@export var timeline_units := TimelineUnits.SECONDS
@export var markers: Array[ChirpMarker] = []

@export_group("Instance Limits")
## 0 = unlimited.
@export_range(0, 64) var max_instances := 0
@export var stealing := Stealing.OLDEST
## Minimum time between starts of this event.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s") var cooldown := 0.0

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


func find_parameter(parameter_name: String) -> ChirpParameter:
	for parameter in parameters:
		if parameter and parameter.name.nocasecmp_to(parameter_name) == 0:
			return parameter
	return null
