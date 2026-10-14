@tool
class_name ChirpInstrument
extends Resource
## Something an event plays. One stream = FMOD "single instrument";
## several streams = "multi instrument" (a playlist picked from on every trigger).

enum Kind {
	SOUND, ## Plays one of its streams.
	EVENT, ## Plays another ChirpEvent inside this one. Parameters with the same name are linked.
	SILENCE, ## Plays nothing for its duration (e.g. a gap in a consecutive sheet).
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
## Replays when it finishes until the event is stopped. For gapless loops,
## enable looping in the stream's import settings instead.
@export var loop := false
@export_range(-80.0, 24.0, 0.1, "suffix:dB") var volume_db := 0.0
@export_range(-24.0, 24.0, 0.01, "suffix:st") var pitch_semitones := 0.0
## The nested event, for EVENT instruments.
@export var event: ChirpEvent
## How long a SILENCE instrument lasts.
@export_range(0.0, 60.0, 0.01, "or_greater", "suffix:s") var duration := 1.0

@export_group("Timeline")
## Where the instrument starts on a TIMELINE event, in the event's timeline units.
@export var start := 0.0
## How long it stays on the timeline. 0 = the length of its longest stream.
@export var length := 0.0
## Plays to its own end once triggered, instead of following the timeline playhead.
@export var async_playback := false

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
	"streams": Kind.SOUND, "selection": Kind.SOUND, "loop": Kind.SOUND,
	"random_pitch_semitones": Kind.SOUND, "event": Kind.EVENT, "duration": Kind.SILENCE,
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
	if _KIND_FIELDS.has(property.name) and _KIND_FIELDS[property.name] != kind:
		property.usage = PROPERTY_USAGE_NO_EDITOR
