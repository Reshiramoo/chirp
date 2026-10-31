@icon("res://addons/chirp/icons/beat_monitor.svg")
class_name ChirpBeatMonitor
extends Control
## An on-screen metronome for checking that gameplay is in time with the music, by eye or in a
## screen recording. Point [member instance] at a playing TIMELINE event instance:
## [codeblock]
## $ChirpBeatMonitor.instance = music
## [/codeblock]
## It draws the beats of the current bar (the one being heard lights up and fades through the
## beat), a sweep through the bar, bar.beat / tempo / how far Chirp's playhead is from the music /
## the output latency, a tick under a beat when timeline_beat fires for it, and a flash naming
## each of the instance's sounds as it starts. Redrawn every frame, so a 60 FPS recording shows
## it exactly. With [member record_mix] it also records what the game outputs to a WAV file, with
## a CSV of the beats and sounds Chirp signalled, for checking the sound itself.

## The instance to show. Its sounds and beats are tracked from when it's set.
var instance: ChirpEventInstance:
	set(value):
		if instance and instance.timeline_beat.is_connected(_on_beat):
			instance.timeline_beat.disconnect(_on_beat)
			instance.sound_played.disconnect(_on_sound)
		instance = value
		if instance:
			instance.timeline_beat.connect(_on_beat)
			instance.sound_played.connect(_on_sound)
## Show the beat being heard (Chirp's audible position: the playhead minus the output latency).
## Off: the playhead (what's being mixed).
@export var audible := true
## Record the game's output (the Master bus) while this node is in the tree, saved to
## [member record_path] when it leaves, with a CSV of beats and sounds next to it.
@export var record_mix := false
@export var record_path := "user://chirp_monitor.wav"

const FLASH_SECONDS := 0.6
const TICK_SECONDS := 0.12

var _flashes: Array[Dictionary] = [] # {text, usec}
var _beat_tick := {} # {beat, usec}: the last timeline_beat signal
var _recorder: AudioEffectRecord
var _record_start_usec := 0
var _log := PackedStringArray(["seconds,kind,detail"])


func _init() -> void:
	custom_minimum_size = Vector2(340, 92)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	if record_mix and not Engine.is_editor_hint():
		_recorder = AudioEffectRecord.new()
		AudioServer.add_bus_effect(0, _recorder)
		_recorder.set_recording_active(true)
		_record_start_usec = Time.get_ticks_usec()


func _exit_tree() -> void:
	if _recorder == null:
		return
	_recorder.set_recording_active(false)
	var recording := _recorder.get_recording()
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) == _recorder:
			AudioServer.remove_bus_effect(0, i)
			break
	_recorder = null
	if recording:
		recording.save_to_wav(record_path)
		var csv := FileAccess.open(record_path.get_basename() + ".csv", FileAccess.WRITE)
		if csv:
			csv.store_string("\n".join(_log) + "\n")
		print("ChirpBeatMonitor: recorded %s (+ .csv)" % ProjectSettings.globalize_path(record_path))


func _process(_delta: float) -> void:
	queue_redraw()


## Seconds since recording started (0 when not recording), for the CSV.
func _now() -> float:
	return (Time.get_ticks_usec() - _record_start_usec) / 1000000.0 if _record_start_usec else 0.0


func _on_beat(bar: int, beat: int, position: float, _tempo: float, _signature: Vector2i) -> void:
	_beat_tick = {beat = beat, usec = Time.get_ticks_usec()}
	if _recorder:
		_log.append("%.4f,beat,%d.%d at %.4f s" % [_now(), bar, beat, position])


func _on_sound(instrument: ChirpInstrument, stream: AudioStream) -> void:
	var name := stream.resource_path.get_file() if stream and stream.resource_path else \
		(instrument.event.resource_path.get_file() if instrument.event else "sound")
	_flashes.append({text = name, usec = Time.get_ticks_usec()})
	if _flashes.size() > 4:
		_flashes.pop_front()
	if _recorder:
		_log.append("%.4f,sound,%s" % [_now(), name])


## Milliseconds between Chirp's playhead and the music as mixed (NAN without a sound to compare):
## near 0 when the timeline follows the music.
func music_offset_ms() -> float:
	if instance == null:
		return NAN
	for entry_voice in instance._entry_voices.values():
		var player = entry_voice.player
		if player == null or not player.playing or entry_voice.detached:
			continue
		var heard: float = player.get_playback_position() + AudioServer.get_time_since_last_mix()
		var entry := instance._timeline_entry(entry_voice)
		if entry == null:
			continue
		var error: float = instance.get_timeline_position() - entry.start + entry_voice.start_shift - heard
		var length: float = player.stream.get_length()
		if length > 0.0 and absf(error) > length / 2.0:
			error = fposmod(error + length / 2.0, length) - length / 2.0 # it looped
		return error * 1000.0
	return NAN


func _draw() -> void:
	var font := get_theme_default_font()
	var font_size := 13
	var text := Color(0.92, 0.92, 0.95)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.05, 0.08, 0.85))
	if instance == null or instance._timeline == null or not instance.is_playing():
		draw_string(font, Vector2(8, 20), "ChirpBeatMonitor: no timeline playing", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text)
		return
	var time := instance.get_audible_position() if audible else instance.get_timeline_position()
	var tempo := instance._timeline.tempo_at(time)
	var per_bar: int = tempo.marker.beats_per_bar if tempo else 4
	var beat_position := instance.get_beat_position(audible)
	var bar_position := instance.get_bar_position(audible)
	var current := int(fposmod(beat_position, per_bar))
	var phase := fposmod(beat_position, 1.0)
	var now := Time.get_ticks_usec()

	# The bar's beats: the one heard lights up and fades through the beat
	var cell_w := (size.x - 16.0 - (per_bar - 1) * 4.0) / per_bar
	for i in per_bar:
		var cell := Rect2(8.0 + i * (cell_w + 4.0), 8.0, cell_w, 26.0)
		var base := Color(1.0, 0.75, 0.25) if i == 0 else Color(0.4, 0.75, 1.0)
		draw_rect(cell, Color(base, 0.15))
		if i == current:
			draw_rect(cell, Color(base, 1.0 - phase * 0.85))
		draw_string(font, cell.position + Vector2(5, 18), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
			Color(0, 0, 0) if i == current and phase < 0.5 else text)
		# A tick under the beat timeline_beat last fired for (the signal comes on the playhead's frame)
		if not _beat_tick.is_empty() and _beat_tick.beat == i + 1 and now - _beat_tick.usec < TICK_SECONDS * 1000000.0:
			draw_rect(Rect2(cell.position.x, cell.end.y + 2.0, cell.size.x, 3.0), Color.WHITE)

	# A sweep through the bar
	var bar_rect := Rect2(8, 42, size.x - 16, 6)
	draw_rect(bar_rect, Color(1, 1, 1, 0.12))
	var x := bar_rect.position.x + bar_rect.size.x * fposmod(bar_position, 1.0)
	draw_rect(Rect2(bar_rect.position, Vector2(x - bar_rect.position.x, bar_rect.size.y)), Color(1, 1, 1, 0.35))
	draw_line(Vector2(x, bar_rect.position.y - 3), Vector2(x, bar_rect.end.y + 3), Color.WHITE, 2.0)

	var offset := music_offset_ms()
	var line := "bar %d · beat %d   %.1f BPM   sync %s   latency %.0f ms%s" % [int(bar_position) + 1, current + 1,
		instance.get_tempo(), "%+.1f ms" % offset if not is_nan(offset) else "–",
		instance._chirp.get_output_latency() * 1000.0, "   REC" if _recorder else ""]
	draw_string(font, Vector2(8, 66), line, HORIZONTAL_ALIGNMENT_LEFT, size.x - 16, font_size, text)

	# A flash for each sound as it starts
	var fx := 8.0
	for flash in _flashes:
		var age: float = (now - flash.usec) / 1000000.0
		if age > FLASH_SECONDS:
			continue
		var label: String = flash.text
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 10.0
		draw_rect(Rect2(fx, 72, width, 16), Color(1.0, 0.85, 0.3, 1.0 - age / FLASH_SECONDS))
		draw_string(font, Vector2(fx + 5, 85), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size - 1, Color(0, 0, 0))
		fx += width + 4.0
