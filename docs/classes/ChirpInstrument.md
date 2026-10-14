# ChirpInstrument

**Inherits:** [Resource](https://docs.godotengine.org/en/stable/classes/class_resource.html)

Something a [ChirpEvent](ChirpEvent.md) plays: a sound, a playlist, a nested event or a silence.

## Description

A `SOUND` instrument with one stream is FMOD's single instrument; with several streams it is a
multi instrument, picking one stream per trigger according to [selection](#property-selection).
An `EVENT` instrument plays another ChirpEvent inside this one, and a `SILENCE` instrument plays
nothing for its [duration](#property-duration), e.g. a gap in a consecutive sheet.

The inspector only shows the properties the chosen [kind](#property-kind) uses.

## Tutorials

- [Events and event paths](../../README.md#events-and-event-paths)

## Properties

| Type | Name | Default |
|---|---|---|
| bool | [async_playback](#property-async_playback) | `false` |
| String | [condition_parameter](#property-condition_parameter) | `""` |
| float | [condition_max](#property-condition_max) | `1.0` |
| float | [condition_min](#property-condition_min) | `0.0` |
| [CutBehavior](#enum-cutbehavior) | [cut_behavior](#property-cut_behavior) | `STOP` |
| float | [delay](#property-delay) | `0.0` |
| float | [duration](#property-duration) | `1.0` |
| [ChirpEvent](ChirpEvent.md) | [event](#property-event) | `null` |
| [Kind](#enum-kind) | [kind](#property-kind) | `SOUND` |
| float | [length](#property-length) | `0.0` |
| bool | [loop](#property-loop) | `false` |
| float | [pitch_semitones](#property-pitch_semitones) | `0.0` |
| float | [probability](#property-probability) | `100.0` |
| float | [random_pitch_semitones](#property-random_pitch_semitones) | `0.0` |
| float | [random_volume_db](#property-random_volume_db) | `0.0` |
| [Selection](#enum-selection) | [selection](#property-selection) | `SHUFFLE` |
| float | [start](#property-start) | `0.0` |
| Array[AudioStream] | [streams](#property-streams) | `[]` |
| float | [volume_db](#property-volume_db) | `0.0` |

## Methods

| Return | Signature |
|---|---|
| float | [get_length](#method-get_length)() |
| AudioStream | [pick_stream](#method-pick_stream)() |

## Enumerations

<a id="enum-kind"></a>
### enum Kind

- **SOUND** = `0`: plays one of its [streams](#property-streams).
- **EVENT** = `1`: plays another [ChirpEvent](ChirpEvent.md) inside this one. Parameters with the
  same name are linked: the nested event receives the parent's values.
- **SILENCE** = `2`: plays nothing for its [duration](#property-duration).

---

<a id="enum-selection"></a>
### enum Selection

How a playlist (several streams) picks the next stream.

- **SHUFFLE** = `0`: every entry once, in random order, never the same entry twice in a row.
- **RANDOM** = `1`: any entry, independently each time (repeats possible).
- **SEQUENTIAL** = `2`: in list order, wrapping around.

---

<a id="enum-cutbehavior"></a>
### enum CutBehavior

What happens when the instrument's condition stops holding, or a timeline jump leaves it.

- **STOP** = `0`: stop at once.
- **PLAY_TO_END** = `1`: let the current sound finish.

## Property Descriptions

<a id="property-async_playback"></a>
### bool async_playback = `false`

TIMELINE events: once triggered, play to the sound's own end instead of following the playhead
(not stopped when the playhead leaves, not re-seeked by jumps).

---

<a id="property-condition_parameter"></a>
### String condition_parameter = `""`

A local or global parameter that must be within [[condition_min](#property-condition_min),
[condition_max](#property-condition_max)] for the instrument to trigger. Local parameters are
looked up first. Empty = always. A parameter that doesn't exist counts as met (with a warning).

While playing, the condition is checked every frame; when it stops holding, the
[cut_behavior](#property-cut_behavior) applies. On a TIMELINE event, an instrument whose condition
starts holding while the playhead is inside it starts part way through.

---

<a id="property-condition_max"></a>
### float condition_max = `1.0`

Upper bound of the condition range (inclusive).

---

<a id="property-condition_min"></a>
### float condition_min = `0.0`

Lower bound of the condition range (inclusive).

---

<a id="property-cut_behavior"></a>
### [CutBehavior](#enum-cutbehavior) cut_behavior = `STOP`

See [CutBehavior](#enum-cutbehavior).

---

<a id="property-delay"></a>
### float delay = `0.0`

Seconds to wait before playing, on SIMULTANEOUS and CONSECUTIVE sheets.

---

<a id="property-duration"></a>
### float duration = `1.0`

SILENCE: how long it lasts, in seconds.

---

<a id="property-event"></a>
### [ChirpEvent](ChirpEvent.md) event = `null`

EVENT: the nested event. An event can't nest itself.

---

<a id="property-kind"></a>
### [Kind](#enum-kind) kind = `SOUND`

What the instrument plays. See [Kind](#enum-kind).

---

<a id="property-length"></a>
### float length = `0.0`

TIMELINE events: how long the instrument stays on the timeline, in the event's timeline units.
`0` = the length of its longest stream (or its duration, for SILENCE); a nested event with length
`0` never leaves the timeline: it plays until it ends by itself.

---

<a id="property-loop"></a>
### bool loop = `false`

SOUND: replay when the stream finishes, until the event is stopped. For gapless loops, enable
looping in the stream's import settings instead.

---

<a id="property-pitch_semitones"></a>
### float pitch_semitones = `0.0`

Pitch offset in semitones.

---

<a id="property-probability"></a>
### float probability = `100.0`

Chance, in percent, that the instrument plays each time it is triggered.

---

<a id="property-random_pitch_semitones"></a>
### float random_pitch_semitones = `0.0`

SOUND: each trigger is detuned by a random amount within ± this many semitones.

---

<a id="property-random_volume_db"></a>
### float random_volume_db = `0.0`

Each trigger is quieter by a random amount up to this many dB.

---

<a id="property-selection"></a>
### [Selection](#enum-selection) selection = `SHUFFLE`

SOUND with several streams: how the next one is picked. See [Selection](#enum-selection).

**Note:** playlist state is stored on the instrument, so it is shared by every instance of the
event (as in FMOD).

---

<a id="property-start"></a>
### float start = `0.0`

TIMELINE events: where the instrument starts on the timeline, in the event's timeline units.

---

<a id="property-streams"></a>
### Array[AudioStream] streams = `[]`

SOUND: the stream, or the playlist of streams.

---

<a id="property-volume_db"></a>
### float volume_db = `0.0`

Volume offset in dB.

## Method Descriptions

<a id="method-get_length"></a>
### float get_length()

SOUND: the longest stream's length in seconds (`0` if unknown). SILENCE: its
[duration](#property-duration). EVENT: `0`.

---

<a id="method-pick_stream"></a>
### AudioStream pick_stream()

The next stream to play, according to [selection](#property-selection). Advances the playlist.
`null` if there are no streams.
