extends RefCounted
## Compiled form of a TIMELINE event: every position converted to seconds, plus
## tempo-map queries. Built once per event instance.

const EPSILON := 0.000001
const DEFAULT_BPM := 120.0


## An instrument placed on the timeline.
class Entry:
	var instrument: ChirpInstrument
	var index := 0
	var start := 0.0
	var end := INF # INF when the instrument's length is unknown (e.g. nested events)


## A marker, with its position (and region end) in seconds.
class Mark:
	var marker: ChirpMarker
	var time := 0.0
	var end := 0.0


var entries: Array[Entry] = []
## Every marker except TEMPO, sorted by time.
var marks: Array[Mark] = []
## TEMPO markers, sorted by time.
var tempos: Array[Mark] = []
## DESTINATION name -> Mark.
var destinations := {}
## End of the last finite instrument or marker, in seconds.
var length := 0.0

var _beat_tempos: Array[ChirpMarker] = [] # TEMPO markers sorted by beat position (BEATS units only)
var _in_beats := false


func _init(event: ChirpEvent) -> void:
	_in_beats = event.timeline_units == ChirpEvent.TimelineUnits.BEATS
	for marker in event.markers:
		if marker and marker.kind == ChirpMarker.Kind.TEMPO:
			_beat_tempos.append(marker)
	_beat_tempos.sort_custom(func(a: ChirpMarker, b: ChirpMarker) -> bool: return a.position < b.position)

	for marker in event.markers:
		if marker == null:
			continue
		var mark := Mark.new()
		mark.marker = marker
		mark.time = to_seconds(marker.position)
		mark.end = to_seconds(marker.end) if marker.is_region() else mark.time
		length = maxf(length, maxf(mark.time, mark.end))
		if marker.kind == ChirpMarker.Kind.TEMPO:
			tempos.append(mark)
		else:
			marks.append(mark)
			if marker.kind == ChirpMarker.Kind.DESTINATION:
				destinations[marker.name] = mark
	var by_time := func(a: Mark, b: Mark) -> bool: return a.time < b.time
	tempos.sort_custom(by_time)
	marks.sort_custom(by_time)

	for i in event.instruments.size():
		var instrument := event.instruments[i]
		if instrument == null:
			continue
		var entry := Entry.new()
		entry.instrument = instrument
		entry.index = i
		entry.start = to_seconds(instrument.start)
		if instrument.length > 0.0:
			entry.end = to_seconds(instrument.start + instrument.length)
		elif instrument.get_length() > 0.0:
			entry.end = entry.start + instrument.get_length()
		if entry.end != INF:
			length = maxf(length, entry.end)
		entries.append(entry)


## Converts a position in the event's timeline units to seconds.
func to_seconds(position: float) -> float:
	if not _in_beats:
		return position
	var seconds := 0.0
	var beat := 0.0
	var bpm := DEFAULT_BPM
	for tempo in _beat_tempos:
		if tempo.position >= position:
			break
		seconds += (tempo.position - beat) * 60.0 / bpm
		beat = tempo.position
		bpm = tempo.bpm
	return seconds + (position - beat) * 60.0 / bpm


## The TEMPO marker in effect at [param time], or null before the first one.
func tempo_at(time: float) -> Mark:
	var current: Mark = null
	for tempo in tempos:
		if tempo.time > time + EPSILON:
			break
		current = tempo
	return current


## Beats in (from, to], each {time, bar, beat, tempo: Mark}. Bars and beats count from 1,
## starting at their TEMPO marker.
func beats_between(from: float, to: float) -> Array[Dictionary]:
	var beats: Array[Dictionary] = []
	for i in tempos.size():
		var tempo := tempos[i]
		var segment_end := tempos[i + 1].time if i + 1 < tempos.size() else INF
		if segment_end <= from or tempo.time > to:
			continue
		var beat_length := 60.0 / tempo.marker.bpm
		var k := 0
		if from >= tempo.time:
			k = int(floorf((from - tempo.time) / beat_length + EPSILON)) + 1
		var time := tempo.time + k * beat_length
		while time <= to + EPSILON and time < segment_end - EPSILON:
			beats.append({
				time = time,
				bar = k / tempo.marker.beats_per_bar + 1,
				beat = k % tempo.marker.beats_per_bar + 1,
				tempo = tempo,
			})
			k += 1
			time = tempo.time + k * beat_length
	return beats


## The first beat or bar line at or after [param time]. Without tempo markers, [param time].
func next_boundary(time: float, quantization: ChirpMarker.Quantization) -> float:
	if quantization == ChirpMarker.Quantization.NONE or tempos.is_empty():
		return time
	var tempo := tempo_at(time)
	if tempo == null:
		return tempos[0].time
	var unit := 60.0 / tempo.marker.bpm
	if quantization == ChirpMarker.Quantization.BAR:
		unit *= tempo.marker.beats_per_bar
	var boundary := tempo.time + ceilf((time - tempo.time) / unit - EPSILON) * unit
	var index := tempos.find(tempo)
	if index + 1 < tempos.size():
		boundary = minf(boundary, tempos[index + 1].time)
	return boundary
