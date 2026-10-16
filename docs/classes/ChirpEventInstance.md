# ChirpEventInstance

**Inherits:** [RefCounted](https://docs.godotengine.org/en/stable/classes/class_refcounted.html)

One live playback of a [ChirpEvent](ChirpEvent.md).

## Description

Create instances with [Chirp.create_instance()](Chirp.md#method-create_instance) (or
[Chirp.play_one_shot()](Chirp.md#method-play_one_shot) for fire-and-forget sounds). Don't call
`new()` yourself.

Lifecycle: [start()](#method-start) → playing → [stop()](#method-stop) or the content ends →
stopped. A stopped instance can be started again. Call [release()](#method-release) when you no
longer need the handle: a released instance is destroyed as soon as it stops, after which it
can't be started again.

An event without `persistent` stops by itself once nothing is playing or waiting to play (and,
on a TIMELINE event, once the playhead is past the end with no sustain point or pending
transition).

All signals fire on the main thread, during Chirp's frame processing or inside the call that
caused them.

```gdscript
var footsteps := Chirp.create_instance("event:/sfxs/footsteps")
footsteps.attach_to(self)
footsteps.set_parameter_by_label("Surface", "Gravel")
footsteps.start()
```

## Tutorials

- [Instances and their lifecycle](../../README.md#instances-and-their-lifecycle)
- [Timelines and interactive music](../../README.md#timelines-and-interactive-music)

## Properties

| Type | Name | Default |
|---|---|---|
| float | [pitch](#property-pitch) | `1.0` |
| float | [volume](#property-volume) | `1.0` |

## Methods

| Return | Signature |
|---|---|
| void | [attach_to](#method-attach_to)(node: Node) |
| void | [call_on_beat](#method-call_on_beat)(callback: Callable, quantization: [Quantization](ChirpMarker.md#enum-quantization) = BEAT, audible: bool = true) |
| float | [get_audible_position](#method-get_audible_position)() |
| float | [get_bar_phase](#method-get_bar_phase)(audible: bool = true) |
| float | [get_bar_position](#method-get_bar_position)(audible: bool = true) |
| float | [get_beat_phase](#method-get_beat_phase)(audible: bool = true) |
| float | [get_beat_position](#method-get_beat_position)(audible: bool = true) |
| [ChirpEvent](ChirpEvent.md) | [get_event](#method-get_event)() |
| float | [get_parameter](#method-get_parameter)(parameter_name: String) |
| bool | [get_paused](#method-get_paused)() |
| [State](#enum-state) | [get_state](#method-get_state)() |
| float | [get_tempo](#method-get_tempo)() |
| float | [get_timeline_position](#method-get_timeline_position)() |
| bool | [is_playing](#method-is_playing)() |
| bool | [is_sustaining](#method-is_sustaining)() |
| bool | [is_valid](#method-is_valid)() |
| void | [key_off](#method-key_off)() |
| void | [release](#method-release)() |
| void | [set_attenuation_2d](#method-set_attenuation_2d)(max_distance: float, attenuation: float) |
| void | [set_attenuation_3d](#method-set_attenuation_3d)(unit_size: float, max_distance: float) |
| void | [set_parameter](#method-set_parameter)(parameter_name: String, value: float) |
| void | [set_parameter_by_label](#method-set_parameter_by_label)(parameter_name: String, label: String) |
| void | [set_paused](#method-set_paused)(paused: bool) |
| void | [set_position](#method-set_position)(position: Variant) |
| void | [set_programmer_sound](#method-set_programmer_sound)(key: String, stream: AudioStream) |
| void | [set_timeline_position](#method-set_timeline_position)(position: float) |
| void | [start](#method-start)() |
| void | [stop](#method-stop)(allow_fadeout: bool = true) |

## Signals

<a id="signal-destroyed"></a>
### destroyed()

Emitted once, when a released instance is destroyed (see [release()](#method-release)).

---

<a id="signal-programmer_sound_requested"></a>
### programmer_sound_requested(key: String, instrument: [ChirpInstrument](ChirpInstrument.md))

A PROGRAMMER instrument is about to play and asks for its sound by
[programmer_key](ChirpInstrument.md#property-programmer_key). Emitted synchronously, every time the
instrument triggers: call [set_programmer_sound()](#method-set_programmer_sound) from the handler to
supply it. Requests from nested events are re-emitted on their parent.

If no sound is set for the key after the signal, Chirp asks
[Chirp.events.programmer_sound_provider](ChirpEvents.md#property-programmer_sound_provider); if that
gives nothing either, the instrument plays nothing (with a warning).

```gdscript
var line := Chirp.create_instance("event:/voice/npc_line")
line.programmer_sound_requested.connect(func(key: String, _instrument: ChirpInstrument) -> void:
	line.set_programmer_sound(key, load("res://voice/%s/%s.ogg" % [TranslationServer.get_locale(), dialogue_id])))
line.start()
```

---

<a id="signal-restarted"></a>
### restarted()

Emitted when [start()](#method-start) is called on an instance that is already playing or stopping.

---

<a id="signal-started"></a>
### started()

Emitted when [start()](#method-start) starts a stopped instance.

---

<a id="signal-stopped"></a>
### stopped()

Emitted when the instance becomes stopped: after [stop()](#method-stop) (once the release has
finished), when the content ends, or when a voice limit steals it.

---

<a id="signal-timeline_beat"></a>
### timeline_beat(bar: int, beat: int, position: float, tempo: float, time_signature: Vector2i)

TIMELINE events: the playhead crossed a beat of a TEMPO marker. `bar` and `beat` count from 1,
starting at the current TEMPO marker. `position` is in seconds, `tempo` in BPM, and
`time_signature` is (beats per bar, beat unit). Beats fire for every frame's stretch of timeline,
so several can arrive in one frame.

```gdscript
music.timeline_beat.connect(func(bar: int, beat: int, _position: float, _tempo: float, _signature: Vector2i) -> void:
	if beat == 1:
		$Lights.flash())
```

---

<a id="signal-timeline_marker"></a>
### timeline_marker(marker_name: String, position: float)

TIMELINE events: the playhead passed a MARKER. `position` is in seconds. Markers skipped by a jump
don't fire.

## Enumerations

<a id="enum-state"></a>
### enum State

- **STOPPED** = `0`: not playing.
- **PLAYING** = `1`: playing.
- **STOPPING** = `2`: playing the envelope's release after [stop()](#method-stop).

---

<a id="enum-spatial"></a>
### enum Spatial

How the instance's players are positioned; set by [set_position()](#method-set_position) and [attach_to()](#method-attach_to).

- **NONE** = `0`: non-spatial (`AudioStreamPlayer`).
- **SPATIAL_2D** = `1`: `AudioStreamPlayer2D`.
- **SPATIAL_3D** = `2`: `AudioStreamPlayer3D`.

## Constants

- **ROLLOFF_FAR** = `1.0e7`: `AudioStreamPlayer2D.max_distance` while Chirp applies the roll-off.
- **RESYNC_TOLERANCE** = `0.05`: how far (seconds) a voice may drift from the playhead after a
  timeline jump before it is re-seeked.

## Property Descriptions

<a id="property-pitch"></a>
### float pitch = `1.0`

Pitch multiplier for this instance, applied on top of the event's `pitch_scale`, the instruments'
pitch, automation and LFOs. Takes effect on the next frame.

---

<a id="property-volume"></a>
### float volume = `1.0`

Linear volume multiplier for this instance, applied on top of the event's `volume_db`, the
envelope, automation and LFOs. Takes effect on the next frame. Also used by
[ChirpEvent.Stealing](ChirpEvent.md#enum-stealing) `QUIETEST`.

## Method Descriptions

<a id="method-attach_to"></a>
### void attach_to(node: Node)

Makes the instance follow `node`: a Node2D gives 2D playback, a Node3D 3D playback. If the node is
freed, the sound stays where the node was last seen. Any other node makes the instance
non-spatial. Call before [start()](#method-start): players already playing keep their type.

---

<a id="method-call_on_beat"></a>
### void call_on_beat(callback: Callable, quantization: [Quantization](ChirpMarker.md#enum-quantization) = BEAT, audible: bool = true)

Calls `callback(bar, beat)` once, on the next beat (or the next bar line when `quantization` is
`BAR`) of the TEMPO grid. With `audible`, it waits
[Chirp.get_output_latency()](Chirp.md#method-get_output_latency) more, so it lands when the beat is
heard. Forgotten if the instance stops first. Needs a TEMPO marker.

```gdscript
music.call_on_beat(func(_bar, _beat): spawn_enemy(), ChirpMarker.Quantization.BAR)
```

---

<a id="method-get_audible_position"></a>
### float get_audible_position()

TIMELINE events: where the listener is in the timeline right now, in seconds. That's the playhead,
moved on by the time since Chirp's last update (so it's smooth between frames), minus
[Chirp.get_output_latency()](Chirp.md#method-get_output_latency), since sound reaches the speakers
a little after it's mixed. Use it to line visuals up with what's heard. Right after a loop or jump
it can briefly read just before the jump's destination. Stops moving while paused or held at a
sustain point. `0.0` for other events.

---

<a id="method-get_bar_phase"></a>
### float get_bar_phase(audible: bool = true)

How far through the current bar, `0.0` (on the bar line) to `1.0`. Drive anything that should hit
on the bar from it:

```gdscript
func _process(_delta: float) -> void:
	$Player.position.x = lerpf(start_x, wall_x, music.get_bar_phase()) # reaches the wall on each bar
```

---

<a id="method-get_bar_position"></a>
### float get_bar_position(audible: bool = true)

Bars since the TEMPO marker in effect (`0.0` at its first bar line), using its `beats_per_bar`.
Fractional; see [get_beat_position()](#method-get_beat_position).

---

<a id="method-get_beat_phase"></a>
### float get_beat_phase(audible: bool = true)

How far through the current beat, `0.0` (on the beat) to `1.0`.

---

<a id="method-get_beat_position"></a>
### float get_beat_position(audible: bool = true)

Beats since the TEMPO marker in effect: `0.0` on its bar 1 beat 1, the same grid
[timeline_beat](#signal-timeline_beat) counts on (120 BPM from `0` before any TEMPO marker).
Fractional. With `audible`, at [get_audible_position()](#method-get_audible_position); otherwise at
the playhead.

---

<a id="method-get_event"></a>
### [ChirpEvent](ChirpEvent.md) get_event()

The event this instance plays.

---

<a id="method-get_parameter"></a>
### float get_parameter(parameter_name: String)

Current value of a local parameter (case-insensitive), which may still be gliding toward its
target. `0.0` if the event has no such parameter.

---

<a id="method-get_paused"></a>
### bool get_paused()

The value set with [set_paused()](#method-set_paused). Doesn't report pausing by bus or
[ChirpMixer.pause_all()](ChirpMixer.md#method-pause_all).

---

<a id="method-get_state"></a>
### [State](#enum-state) get_state()

The current [State](#enum-state).

---

<a id="method-get_tempo"></a>
### float get_tempo()

BPM of the TEMPO marker in effect at the playhead (120 before any).

---

<a id="method-get_timeline_position"></a>
### float get_timeline_position()

TIMELINE events: the playhead position in seconds. `0.0` for other events.

---

<a id="method-is_playing"></a>
### bool is_playing()

`true` while playing or stopping.

---

<a id="method-is_sustaining"></a>
### bool is_sustaining()

`true` while a SUSTAIN_POINT marker is holding the playhead.

---

<a id="method-is_valid"></a>
### bool is_valid()

`false` once the instance has been destroyed (see [release()](#method-release)).

---

<a id="method-key_off"></a>
### void key_off()

Releases the SUSTAIN_POINT currently holding the playhead. The playhead won't stop at that sustain
point again until it jumps or the instance restarts. Does nothing if no sustain point is holding it.

---

<a id="method-release"></a>
### void release()

Marks the instance for destruction once it has stopped. If it is already stopped, it is
destroyed now, emitting [destroyed](#signal-destroyed).

**Note:** Chirp only keeps a reference to an instance while it plays. Like any RefCounted, the
instance is freed once neither Chirp nor your code references it, released or not.

---

<a id="method-set_attenuation_2d"></a>
### void set_attenuation_2d(max_distance: float, attenuation: float)

Overrides the event's `max_distance_2d` and `attenuation_2d` for this instance. With a Chirp
[roll-off](ChirpEvent.md#property-rolloff), `max_distance` replaces the event's `max_distance`
instead and `attenuation` is ignored. Applies to players started afterwards.

---

<a id="method-set_attenuation_3d"></a>
### void set_attenuation_3d(unit_size: float, max_distance: float)

Overrides the event's `unit_size_3d` and `max_distance_3d` for this instance. With a Chirp
[roll-off](ChirpEvent.md#property-rolloff), they replace `min_distance` and `max_distance` (a
`max_distance` of 0 keeps the event's). Applies to players started afterwards.

---

<a id="method-set_parameter"></a>
### void set_parameter(parameter_name: String, value: float)

Sets a local parameter (case-insensitive). The value is clamped to the parameter's range and
rounded for discrete and labeled parameters. With a `seek_speed` the value glides there while
playing; while stopped it jumps.

Unknown parameters are ignored with a warning, and so are built-in parameters, which Chirp sets
itself. Global parameters are set with
[Chirp.parameters.set_value()](ChirpParameters.md#method-set_value).

---

<a id="method-set_parameter_by_label"></a>
### void set_parameter_by_label(parameter_name: String, label: String)

Sets a labeled parameter by label (case-insensitive). Unknown labels are ignored with a warning.

---

<a id="method-set_paused"></a>
### void set_paused(paused: bool)

Pauses or resumes this instance. A paused instance keeps its place: its players are paused, and
its timeline, envelope, delays and LFOs stop advancing. An instance also pauses while its bus is
paused (see [ChirpMixer.set_bus_paused()](ChirpMixer.md#method-set_bus_paused)).

---

<a id="method-set_position"></a>
### void set_position(position: Variant)

Plays the event at a fixed position: a `Vector2` for 2D, a `Vector3` for 3D. Can be called every
frame to move it. Stops following a node set with [attach_to()](#method-attach_to). Call before
[start()](#method-start) to choose between 2D and 3D: players already playing keep their type.

---

<a id="method-set_programmer_sound"></a>
### void set_programmer_sound(key: String, stream: AudioStream)

Supplies the sound for PROGRAMMER instruments with this `key`, before [start()](#method-start) or
from [programmer_sound_requested](#signal-programmer_sound_requested). It is kept for later triggers
and shared with nested events. Pass `null` to forget it.

---

<a id="method-set_timeline_position"></a>
### void set_timeline_position(position: float)

TIMELINE events: moves the playhead to `position` seconds. Instruments follow: those under the new
position start (part way through their sound), those no longer under it stop (or play to their
end, per their cut behaviour), and those still under it are re-seeked if they drifted more than
[RESYNC_TOLERANCE](#constants). Pending transitions and sustain holds are cleared. Warns on other
events.

---

<a id="method-start"></a>
### void start()

Starts playback from the beginning, or restarts it if already playing (emitting
[restarted](#signal-restarted) instead of [started](#signal-started)).

Starting can be refused: by the event's `cooldown`, or by `max_instances` with `stealing = NONE`.
Otherwise, when the event is at its `max_instances`, another instance of it is stopped at once.
Reports an error if the instance was destroyed.

---

<a id="method-stop"></a>
### void stop(allow_fadeout: bool = true)

Stops playback. With `allow_fadeout` and an envelope with a `release`, the instance fades out
first (state STOPPING), and [stopped](#signal-stopped) fires at the end of the release. Otherwise
it stops now. Calling `stop(false)` while stopping cuts the release short.
