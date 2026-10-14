@tool
class_name ChirpInstrument
extends Resource
## Something an event plays. One stream = FMOD "single instrument";
## several streams = "multi instrument" (a playlist picked from on every trigger).
## A scatterer plays its streams at random intervals and positions; a programmer
## instrument plays a sound that game code supplies when it triggers.

enum Kind {
	SOUND, ## Plays one of its streams.
	EVENT, ## Plays another ChirpEvent inside this one. Parameters with the same name are linked.
	SILENCE, ## Plays nothing for its duration (e.g. a gap in a consecutive sheet).
	SCATTERER, ## Keeps playing its streams at random intervals, scattered around the event (rain, birds).
	PROGRAMMER, ## Plays a sound supplied by game code at trigger time (dialogue, localisation).
}

enum Selection { SHUFFLE, RANDOM, SEQUENTIAL }

enum CutBehavior {
	STOP, ## Stop as soon as the instrument is untriggered.
	PLAY_TO_END, ## Let the current sound finish.
}

@export var kind := Kind.SOUND:
	set(value):
		kind = value
		notify_property_list_changed()
@export var streams: Array[AudioStream] = []
## SHUFFLE plays every entry once in random order and never repeats back-to-back.
@export var selection := Selection.SHUFFLE
## Replays when it finishes until the event is stopped (SOUND and PROGRAMMER). For gapless
## loops, enable looping in the stream's import settings instead.
@export var loop := false
@export_range(-80.0, 24.0, 0.1, "suffix:dB") var volume_db := 0.0
@export_range(-24.0, 24.0, 0.01, "suffix:st") var pitch_semitones := 0.0
## The nested event, for EVENT instruments.
@export var event: ChirpEvent
## How long a SILENCE instrument lasts.
@export_range(0.0, 60.0, 0.01, "or_greater", "suffix:s") var duration := 1.0
## PROGRAMMER: the name game code is asked for (see ChirpEventInstance.programmer_sound_requested).
@export var programmer_key := ""

@export_group("Scatterer")
## Shortest time between two scattered sounds.
@export_range(0.0, 60.0, 0.01, "or_greater", "suffix:s") var spawn_interval_min := 1.0
## Longest time between two scattered sounds.
@export_range(0.0, 60.0, 0.01, "or_greater", "suffix:s") var spawn_interval_max := 3.0
## Most scattered sounds playing at once; a spawn is skipped while full. 0 = unlimited.
@export_range(0, 64) var polyphony := 0
## Sounds to play before the scatterer ends. 0 = until it is stopped.
@export_range(0, 1000, 1, "or_greater") var spawn_total := 0
## Nearest a scattered sound is placed to the event (pixels in 2D, meters in 3D). Spatial events only.
@export_range(0.0, 1000.0, 0.01, "or_greater") var scatter_distance_min := 0.0
## Furthest a scattered sound is placed from the event.
@export_range(0.0, 1000.0, 0.01, "or_greater") var scatter_distance_max := 0.0

@export_group("Timeline & Parameter Sheet")
## Where the instrument starts: on a TIMELINE event in its timeline units, on a PARAMETER sheet
## in parameter units.
@export var start := 0.0
## How far it reaches. TIMELINE: 0 = the length of its longest stream.
## PARAMETER: 0 = to the end of the parameter's range.
@export var length := 0.0
## Plays to its own end once triggered, instead of following the timeline playhead or the
## parameter leaving its range.
@export var async_playback := false
## PARAMETER sheets: parameter distance over which the volume rises from silence after start.
@export_range(0.0, 100.0, 0.001, "or_greater") var fade_in := 0.0
## PARAMETER sheets: parameter distance over which the volume falls to silence before the end.
@export_range(0.0, 100.0, 0.001, "or_greater") var fade_out := 0.0

@export_group("Randomization")
## Each trigger is quieter by a random amount up to this.
@export_range(0.0, 24.0, 0.1, "suffix:dB") var random_volume_db := 0.0
## Each trigger is detuned by a random amount within ± this.
@export_range(0.0, 12.0, 0.01, "suffix:st") var random_pitch_semitones := 0.0

@export_group("Trigger")
## Seconds to wait before playing (action and consecutive sheets).
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s") var delay := 0.0
@export_range(0.0, 100.0, 1.0, "suffix:%") var probability := 100.0
## Local or global parameter that must be within [condition_min, condition_max]. Empty = always.
@export var condition_parameter := ""
@export var condition_min := 0.0
@export var condition_max := 1.0
## What happens when the condition stops holding, or a timeline jump leaves the instrument.
@export var cut_behavior := CutBehavior.STOP

const _KIND_FIELDS := {
	"streams": [Kind.SOUND, Kind.SCATTERER], "selection": [Kind.SOUND, Kind.SCATTERER],
	"loop": [Kind.SOUND, Kind.PROGRAMMER],
	"random_pitch_semitones": [Kind.SOUND, Kind.SCATTERER, Kind.PROGRAMMER],
	"event": [Kind.EVENT], "duration": [Kind.SILENCE], "programmer_key": [Kind.PROGRAMMER],
	"spawn_interval_min": [Kind.SCATTERER], "spawn_interval_max": [Kind.SCATTERER],
	"polyphony": [Kind.SCATTERER], "spawn_total": [Kind.SCATTERER],
	"scatter_distance_min": [Kind.SCATTERER], "scatter_distance_max": [Kind.SCATTERER],
}

# Playlist state is shared by every instance of the event, like FMOD's.
var _bag: Array[int] = []
var _next := 0
var _last := -1


func pick_stream() -> AudioStream:
	var count := streams.size()
	if count == 0:
		return null
	if count == 1:
		return streams[0]
	var index := 0
	match selection:
		Selection.RANDOM:
			index = randi() % count
		Selection.SEQUENTIAL:
			index = _next % count
			_next += 1
		_:
			if _bag.is_empty():
				for i in count:
					_bag.append(i)
				_bag.shuffle()
				# pop_back takes the last entry; keep it from repeating the previous pick.
				if _bag[-1] == _last:
					_bag[-1] = _bag[0]
					_bag[0] = _last
			index = _bag.pop_back()
	_last = index
	return streams[index]


## Longest stream, in seconds (0 if unknown); SILENCE gives its duration.
## SCATTERER, PROGRAMMER and EVENT give 0: their length isn't known in advance.
func get_length() -> float:
	match kind:
		Kind.SILENCE:
			return duration
		Kind.SOUND:
			var longest := 0.0
			for stream in streams:
				if stream:
					longest = maxf(longest, stream.get_length())
			return longest
	return 0.0


func _validate_property(property: Dictionary) -> void:
	if _KIND_FIELDS.has(property.name) and kind not in _KIND_FIELDS[property.name]:
		property.usage = PROPERTY_USAGE_NO_EDITOR
