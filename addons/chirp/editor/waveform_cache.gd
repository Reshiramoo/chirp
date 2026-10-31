@tool
extends RefCounted
## Waveform peaks for the timeline editor: each sound is decoded once (a few milliseconds of
## work per frame, so long tracks don't freeze the editor) into PEAKS_PER_SECOND peaks, and kept
## until the stream changes. Editor-only.

const PEAKS_PER_SECOND := 100
const STRIDE := 16 # frames skipped between samples when finding a peak (plenty for a display)
const CHUNK := 4096 # frames decoded per call

var _done := {} # stream instance id -> {peaks: PackedFloat32Array (0..1), length: the stream's length then}
var _jobs: Array[Dictionary] = [] # {id, stream, length, playback, total, decoded, per_peak, peaks, peak, in_peak}


## Peaks (0..1, PEAKS_PER_SECOND per second) of [param stream]; empty until decoded, and queues it.
func get_peaks(stream: AudioStream) -> PackedFloat32Array:
	if stream == null:
		return PackedFloat32Array()
	var id := stream.get_instance_id()
	if _done.has(id):
		if is_equal_approx(_done[id].length, stream.get_length()):
			return _done[id].peaks
		_done.erase(id) # edited in place (new data) without a changed signal
	if not _jobs.any(func(job: Dictionary) -> bool: return job.id == id):
		_queue(stream)
	return PackedFloat32Array()


## Decodes queued sounds for up to [param budget_usec]. Returns true when one finished.
func step(budget_usec := 4000) -> bool:
	var finished := false
	var until := Time.get_ticks_usec() + budget_usec
	while not _jobs.is_empty() and Time.get_ticks_usec() < until:
		var job := _jobs[0]
		if _decode_chunk(job):
			_done[job.id] = {peaks = job.peaks, length = job.length}
			if is_instance_valid(job.stream) and not job.stream.changed.is_connected(_forget.bind(job.id)):
				job.stream.changed.connect(_forget.bind(job.id), CONNECT_ONE_SHOT)
			_jobs.pop_front()
			finished = true
	return finished


func is_busy() -> bool:
	return not _jobs.is_empty()


func _queue(stream: AudioStream) -> void:
	var length := stream.get_length()
	var id := stream.get_instance_id()
	if length <= 0.0:
		_done[id] = {peaks = PackedFloat32Array(), length = length} # generators and the like: nothing to draw
		return
	var playback := stream.instantiate_playback()
	if playback == null or not playback.has_method("mix_audio"):
		_done[id] = {peaks = PackedFloat32Array(), length = length}
		return
	playback.start(0.0)
	var rate := AudioServer.get_mix_rate()
	_jobs.append({id = id, stream = stream, length = length, playback = playback, total = int(length * rate),
		decoded = 0, per_peak = maxi(int(rate / PEAKS_PER_SECOND), 1), peaks = PackedFloat32Array(),
		peak = 0.0, in_peak = 0})


## Decodes one chunk of [param job]; true once the whole sound is done.
func _decode_chunk(job: Dictionary) -> bool:
	var wanted := mini(CHUNK, job.total - job.decoded)
	var chunk: PackedVector2Array = job.playback.mix_audio(1.0, wanted) if wanted > 0 else PackedVector2Array()
	if chunk.is_empty():
		if job.in_peak > 0:
			job.peaks.append(job.peak)
		return true
	var i := 0
	while i < chunk.size():
		var frame := chunk[i]
		job.peak = maxf(job.peak, maxf(absf(frame.x), absf(frame.y)))
		job.in_peak += STRIDE
		if job.in_peak >= job.per_peak:
			job.peaks.append(minf(job.peak, 1.0))
			job.peak = 0.0
			job.in_peak -= job.per_peak # carry the remainder so peaks don't drift
		i += STRIDE
	job.decoded += chunk.size()
	return job.decoded >= job.total


func _forget(id: int) -> void:
	_done.erase(id)
