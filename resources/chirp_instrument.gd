@tool
class_name ChirpInstrument
extends Resource
## Something an event plays. One stream = FMOD "single instrument";
## several streams = "multi instrument" (a playlist picked from on every trigger).

enum Selection { SHUFFLE, RANDOM, SEQUENTIAL }

@export var streams: Array[AudioStream] = []
## SHUFFLE plays every entry once in random order and never repeats back-to-back.
@export var selection := Selection.SHUFFLE
## Replays when it finishes until the event is stopped. For gapless loops,
## enable looping in the stream's import settings instead.
@export var loop := false
@export_range(-80.0, 24.0, 0.1, "suffix:dB") var volume_db := 0.0
@export_range(-24.0, 24.0, 0.01, "suffix:st") var pitch_semitones := 0.0

@export_group("Randomization")
## Each trigger is quieter by a random amount up to this.
@export_range(0.0, 24.0, 0.1, "suffix:dB") var random_volume_db := 0.0
## Each trigger is detuned by a random amount within ± this.
@export_range(0.0, 12.0, 0.01, "suffix:st") var random_pitch_semitones := 0.0

@export_group("Trigger")
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s") var delay := 0.0
@export_range(0.0, 100.0, 1.0, "suffix:%") var probability := 100.0

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
