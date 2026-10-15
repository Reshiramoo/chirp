# ChirpInstrument

**Inherits:** [Resource](https://docs.godotengine.org/en/stable/classes/class_resource.html)

Something a [ChirpEvent](ChirpEvent.md) plays: a sound, a playlist, a nested event, a silence, a
scatterer or a programmer sound.

## Description

A `SOUND` instrument with one stream is FMOD's single instrument; with several streams it is a
multi instrument, picking one stream per trigger according to [selection](#property-selection).
An `EVENT` instrument plays another ChirpEvent inside this one, and a `SILENCE` instrument plays
nothing for its [duration](#property-duration), e.g. a gap in a consecutive sheet.

A `SCATTERER` keeps playing sounds from its [streams](#property-streams) at random intervals and,
on spatial events, at random positions around the event: rain, birds, distant gunfire. A
`PROGRAMMER` instrument plays a sound that game code supplies when it triggers: dialogue lines,
localised voice-over, user content (see
[ChirpEventInstance.programmer_sound_requested](ChirpEventInstance.md#signal-programmer_sound_requested)).

```gdscript
# Birdsong around the player: one bird every 2 to 6 s, at most 3 at once, 5 to 20 m away.
var birds := ChirpInstrument.new()
birds.kind = ChirpInstrument.Kind.SCATTERER
birds.streams = [preload("res://audio/bird_1.ogg"), preload("res://audio/bird_2.ogg")]
birds.spawn_interval_min = 2.0
birds.spawn_interval_max = 6.0
birds.polyphony = 3
birds.scatter_distance_min = 5.0
birds.scatter_distance_max = 20.0
birds.random_pitch_semitones = 2.0
```

The inspector only shows the properties the chosen [kind](#property-kind) uses.

## Tutorials

- [Events and event paths](../../README.md#events-and-event-paths)

## Properties

| Type | Name | Default |
|---|---|---|
| bool | [async_playback](#property-async_playback) | `false` |
| Array[[ChirpAutomation](ChirpAutomation.md)] | [automations](#property-automations) | `[]` |
| String | [condition_parameter](#property-condition_parameter) | `""` |
| float | [condition_max](#property-condition_max) | `1.0` |
| float | [condition_min](#property-condition_min) | `0.0` |
| [CutBehavior](#enum-cutbehavior) | [cut_behavior](#property-cut_behavior) | `STOP` |
| float | [delay](#property-delay) | `0.0` |
| float | [duration](#property-duration) | `1.0` |
| float | [fade_in](#property-fade_in) | `0.0` |
| float | [fade_out](#property-fade_out) | `0.0` |
| [ChirpEvent](ChirpEvent.md) | [event](#property-event) | `null` |
| [Kind](#enum-kind) | [kind](#property-kind) | `SOUND` |
| float | [length](#property-length) | `0.0` |
| bool | [loop](#property-loop) | `false` |
| float | [pitch_semitones](#property-pitch_semitones) | `0.0` |
| int | [polyphony](#property-polyphony) | `0` |
| float | [probability](#property-probability) | `100.0` |
| [Quantization](ChirpMarker.md#enum-quantization) | [quantization](#property-quantization) | `NONE` |
| String | [programmer_key](#property-programmer_key) | `""` |
| float | [random_pitch_semitones](#property-random_pitch_semitones) | `0.0` |
| float | [random_start_offset](#property-random_start_offset) | `0.0` |
| float | [random_volume_db](#property-random_volume_db) | `0.0` |
| float | [scatter_distance_max](#property-scatter_distance_max) | `0.0` |
| float | [scatter_distance_min](#property-scatter_distance_min) | `0.0` |
| [Selection](#enum-selection) | [selection](#property-selection) | `SHUFFLE` |
| float | [spawn_interval_max](#property-spawn_interval_max) | `3.0` |
| float | [spawn_interval_min](#property-spawn_interval_min) | `1.0` |
| int | [spawn_total](#property-spawn_total) | `0` |
| float | [start](#property-start) | `0.0` |
| float | [start_offset](#property-start_offset) | `0.0` |
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
- **SCATTERER** = `3`: plays its [streams](#property-streams) one after another at random intervals
  ([spawn_interval_min](#property-spawn_interval_min)..[spawn_interval_max](#property-spawn_interval_max)),
  each at a random position around the event. The first sound plays as soon as it triggers. It
  keeps going until it is stopped or has played [spawn_total](#property-spawn_total) sounds.
- **PROGRAMMER** = `4`: plays a sound supplied by game code when it triggers, looked up by
  [programmer_key](#property-programmer_key). Plays nothing (with a warning) if none is supplied.

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

What happens when the instrument's condition stops holding, a timeline jump leaves it, or a
parameter sheet's value leaves its range.

- **STOP** = `0`: stop at once.
- **PLAY_TO_END** = `1`: let the current sound finish. A scatterer stops spawning and lets the
  sounds already playing finish.

## Property Descriptions

<a id="property-async_playback"></a>
### bool async_playback = `false`

TIMELINE events and PARAMETER sheets: once triggered, play to the sound's own end instead of
following the playhead or the parameter (not stopped when the playhead or value leaves, not
re-seeked by jumps). An async scatterer stops spawning
when the playhead leaves, and lets its sounds finish.

---

<a id="property-automations"></a>
### Array[[ChirpAutomation](ChirpAutomation.md)] automations = `[]`

VOLUME and PITCH automation of this instrument alone, e.g. two layers crossfading over a timeline
or along a parameter. They multiply with the event's own automations. In the **Chirp Event** dock,
right-click the instrument → **Add Volume Automation (this instrument)**; its lanes sit right under
it. PAN and EFFECT targets work on the whole event only.

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

<a id="property-fade_in"></a>
### float fade_in = `0.0`

PARAMETER sheets: over this much of the parameter's axis from [start](#property-start), the volume
rises from silence to full. Overlap two instruments and give them matching fades to crossfade.

---

<a id="property-fade_out"></a>
### float fade_out = `0.0`

PARAMETER sheets: over this much of the axis before the end of the range
([start](#property-start) + [length](#property-length)), the volume falls to silence. Needs a
length. An instrument that plays on after leaving its range (`PLAY_TO_END`, async) keeps the
volume it had.

---

<a id="property-kind"></a>
### [Kind](#enum-kind) kind = `SOUND`

What the instrument plays. See [Kind](#enum-kind).

---

<a id="property-length"></a>
### float length = `0.0`

TIMELINE events: how long the instrument stays on the timeline, in the event's timeline units.
PARAMETER sheets: how far its range reaches on the parameter's axis; `0` = to the end of the
parameter's range. Ranges include their start and exclude their end, except an end at the
parameter's maximum.
`0` = the length of its longest stream (or its duration, for SILENCE); a nested event, scatterer
or programmer instrument with length `0` never leaves the timeline: it plays until it ends by
itself. Give scatterers a length on timelines.

---

<a id="property-loop"></a>
### bool loop = `false`

SOUND and PROGRAMMER: replay when the stream finishes, until the event is stopped. For gapless loops, enable
looping in the stream's import settings instead.

---

<a id="property-pitch_semitones"></a>
### float pitch_semitones = `0.0`

Pitch offset in semitones.

---

<a id="property-polyphony"></a>
### int polyphony = `0`

SCATTERER: the most sounds playing at once. A spawn due while it is full is skipped (and doesn't
count toward [spawn_total](#property-spawn_total)). `0` = unlimited.

---

<a id="property-probability"></a>
### float probability = `100.0`

Chance, in percent, that the instrument plays each time it is triggered.

---

<a id="property-programmer_key"></a>
### String programmer_key = `""`

PROGRAMMER: the name game code is asked for. Several instruments can share a key.

---

<a id="property-quantization"></a>
### [Quantization](ChirpMarker.md#enum-quantization) quantization = `NONE`

TIMELINE events: when the instrument becomes due part way through its region (its condition starts
holding, or a jump lands inside it), wait for the next beat or bar line of the TEMPO markers and play
it **from its beginning**. Without quantization it starts right away at the matching point of its
sound, in sync with the timeline. Use it for stingers triggered by gameplay over music:

```gdscript
# A brass hit gated by "Combo" (condition_min 10), over the whole verse, quantization BAR:
music.set_parameter("Combo", combo) # once it reaches 10, the hit plays on the next bar
```

A quantized instrument isn't re-seeked by jumps (it keeps playing from where it is), but still stops
when the playhead leaves its region, unless it is async. If the condition stops holding before the
line, it doesn't play. Without TEMPO markers it plays right away, from its beginning.

---

<a id="property-random_pitch_semitones"></a>
### float random_pitch_semitones = `0.0`

SOUND, SCATTERER, PROGRAMMER: each trigger (for a scatterer, each scattered sound) is detuned by a
random amount within ± this many semitones.

---

<a id="property-random_start_offset"></a>
### float random_start_offset = `0.0`

SOUND, SCATTERER, PROGRAMMER: each trigger (each scattered sound) starts up to this many seconds
further into the sound, at random, on top of [start_offset](#property-start_offset), so long
ambient loops played several times don't start in unison. Wraps past the sound's end.

---

<a id="property-random_volume_db"></a>
### float random_volume_db = `0.0`

Each trigger (for a scatterer, each scattered sound) is quieter by a random amount up to this many dB.

---

<a id="property-scatter_distance_max"></a>
### float scatter_distance_max = `0.0`

SCATTERER: the furthest a sound is placed from the event, in pixels (2D) or meters (3D). Each
sound keeps its offset from the event as the event moves. Non-spatial events ignore it.

---

<a id="property-scatter_distance_min"></a>
### float scatter_distance_min = `0.0`

SCATTERER: the nearest a sound is placed to the event.

---

<a id="property-selection"></a>
### [Selection](#enum-selection) selection = `SHUFFLE`

SOUND and SCATTERER with several streams: how the next one is picked. See [Selection](#enum-selection).

**Note:** playlist state is stored on the instrument, so it is shared by every instance of the
event (as in FMOD).

---

<a id="property-spawn_interval_max"></a>
### float spawn_interval_max = `3.0`

SCATTERER: the longest wait between two sounds, in seconds. Each wait is random between
[spawn_interval_min](#property-spawn_interval_min) and this.

---

<a id="property-spawn_interval_min"></a>
### float spawn_interval_min = `1.0`

SCATTERER: the shortest wait between two sounds, in seconds.

---

<a id="property-spawn_total"></a>
### int spawn_total = `0`

SCATTERER: how many sounds to play before it ends (once the last one finishes). `0` = until it is
stopped; such an event never ends by itself.

---

<a id="property-start"></a>
### float start = `0.0`

TIMELINE events: where the instrument starts on the timeline, in the event's timeline units.
PARAMETER sheets: where its range starts on the parameter's axis.

---

<a id="property-start_offset"></a>
### float start_offset = `0.0`

SOUND, SCATTERER, PROGRAMMER: seconds into the sound every trigger starts at. Wraps past the sound's
end. On a timeline, the sound runs this far ahead of the playhead, and re-seeks after jumps keep it.

---

<a id="property-streams"></a>
### Array[AudioStream] streams = `[]`

SOUND: the stream, or the playlist of streams. SCATTERER: the sounds it picks from.

---

<a id="property-volume_db"></a>
### float volume_db = `0.0`

Volume offset in dB. Read every frame, so changing it (e.g. with the volume knob in the Chirp Event
dock) is heard while the instrument plays. [random_volume_db](#property-random_volume_db) is drawn
once per trigger on top of it.

## Method Descriptions

<a id="method-get_length"></a>
### float get_length()

SOUND: the longest stream's length in seconds (`0` if unknown). SILENCE: its
[duration](#property-duration). EVENT, SCATTERER, PROGRAMMER: `0` (not known in advance).

---

<a id="method-pick_stream"></a>
### AudioStream pick_stream()

The next stream to play, according to [selection](#property-selection). Advances the playlist.
`null` if there are no streams.
