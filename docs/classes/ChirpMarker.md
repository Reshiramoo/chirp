# ChirpMarker

**Inherits:** [Resource](https://docs.godotengine.org/en/stable/classes/class_resource.html)

Something placed on the timeline of a TIMELINE [ChirpEvent](ChirpEvent.md).

## Description

Add to [ChirpEvent.markers](ChirpEvent.md#property-markers). The [kind](#property-kind) decides what
the marker does; the inspector only shows the fields that kind uses. Positions are in the event's
[timeline_units](ChirpEvent.md#property-timeline_units) (seconds or beats).

Point markers (MARKER, TEMPO, SUSTAIN_POINT, DESTINATION, TRANSITION) sit at
[position](#property-position). Regions (LOOP_REGION, TRANSITION_REGION) span
[position](#property-position) to [end](#property-end).

Loop regions, sustain points and transitions can have a **condition**: a local or global
parameter that must be within [[condition_min](#property-condition_min),
[condition_max](#property-condition_max)] for the marker to act. Loop regions and transitions also
have a [probability](#property-probability).

Example: a verse that loops until `Intensity` reaches 0.5, then moves to the chorus on the next bar:

```gdscript
var loop := ChirpMarker.new()
loop.kind = ChirpMarker.Kind.LOOP_REGION
loop.position = 8.0
loop.end = 24.0
loop.condition_parameter = "Intensity"
loop.condition_max = 0.49

var go := ChirpMarker.new()
go.kind = ChirpMarker.Kind.TRANSITION_REGION
go.position = 8.0
go.end = 24.0
go.destination = "chorus"
go.quantization = ChirpMarker.Quantization.BAR
go.condition_parameter = "Intensity"
go.condition_min = 0.5
```

## Tutorials

- [Timelines and interactive music](../../README.md#timelines-and-interactive-music)

## Properties

| Type | Name | Default |
|---|---|---|
| int | [beat_unit](#property-beat_unit) | `4` |
| int | [beats_per_bar](#property-beats_per_bar) | `4` |
| float | [bpm](#property-bpm) | `120.0` |
| String | [condition_parameter](#property-condition_parameter) | `""` |
| float | [condition_max](#property-condition_max) | `1.0` |
| float | [condition_min](#property-condition_min) | `0.0` |
| String | [destination](#property-destination) | `""` |
| float | [end](#property-end) | `0.0` |
| [Kind](#enum-kind) | [kind](#property-kind) | `MARKER` |
| String | [name](#property-name) | `""` |
| float | [position](#property-position) | `0.0` |
| float | [probability](#property-probability) | `100.0` |
| [Quantization](#enum-quantization) | [quantization](#property-quantization) | `NONE` |

## Methods

| Return | Signature |
|---|---|
| bool | [is_region](#method-is_region)() |

## Enumerations

<a id="enum-kind"></a>
### enum Kind

- **MARKER** = `0`: a named point; fires
  [ChirpEventInstance.timeline_marker](ChirpEventInstance.md#signal-timeline_marker) when the
  playhead passes it. Uses `name`, `position`.
- **TEMPO** = `1`: sets the tempo and time signature from here on. Drives
  [timeline_beat](ChirpEventInstance.md#signal-timeline_beat), quantization, the editor's grid, and
  (with BEATS units) the conversion of beats to seconds. Uses `position`, `bpm`, `beats_per_bar`,
  `beat_unit`.
- **LOOP_REGION** = `2`: when the playhead reaches `end` and the condition holds, it jumps back to
  `position`. Uses `position`, `end`, the condition and `probability` (checked each time round).
  Seamless for WAV, Ogg Vorbis and MP3 sounds that span the region (Ogg and MP3: when it ends where
  the sound does) while the loop is certain; see [Timelines and interactive music](../../README.md#timelines-and-interactive-music) for the rules.
- **SUSTAIN_POINT** = `3`: holds the playhead here until
  [key_off()](ChirpEventInstance.md#method-key_off) or the condition stops holding. Uses
  `position` and the condition.
- **DESTINATION** = `4`: a named point that transitions jump to. Uses `name`, `position`.
- **TRANSITION** = `5`: when the playhead reaches it and the condition holds, jump to the
  DESTINATION named `destination`. Uses `position`, `destination`, `quantization`, the condition
  and `probability`.
- **TRANSITION_REGION** = `6`: like TRANSITION, but checked every frame while the playhead is
  inside the region. Uses `position`, `end`, `destination`, `quantization`, the condition and
  `probability` (rolled every frame the condition holds, until a jump is armed).

When several things happen in the same frame, the earliest on the timeline wins. A quantized transition, once armed, jumps at its
beat or bar line even if the playhead has left the region by then.

---

<a id="enum-quantization"></a>
### enum Quantization

When a transition jumps, once triggered.

- **NONE** = `0`: straight away.
- **BEAT** = `1`: on the next beat of the TEMPO marker in effect.
- **BAR** = `2`: on the next bar line. Bars count from their TEMPO marker; a later TEMPO marker
  also counts as a boundary.

Without TEMPO markers, quantized transitions jump straight away. Before the first TEMPO marker,
they wait for it.

## Property Descriptions

<a id="property-beat_unit"></a>
### int beat_unit = `4`

TEMPO: the bottom of the time signature (4 = quarter notes). Reported by
[timeline_beat](ChirpEventInstance.md#signal-timeline_beat); the tempo counts `bpm` beats per minute
regardless.

---

<a id="property-beats_per_bar"></a>
### int beats_per_bar = `4`

TEMPO: the top of the time signature.

---

<a id="property-bpm"></a>
### float bpm = `120.0`

TEMPO: beats per minute.

---

<a id="property-condition_parameter"></a>
### String condition_parameter = `""`

A local or global parameter that must be within [[condition_min](#property-condition_min),
[condition_max](#property-condition_max)] for the marker to act. Local parameters are looked up
first. Empty = always. A parameter that doesn't exist counts as met (with a warning).

---

<a id="property-condition_max"></a>
### float condition_max = `1.0`

Upper bound of the condition range (inclusive).

---

<a id="property-condition_min"></a>
### float condition_min = `0.0`

Lower bound of the condition range (inclusive).

---

<a id="property-destination"></a>
### String destination = `""`

TRANSITION / TRANSITION_REGION: the `name` of the DESTINATION to jump to. A missing destination is
skipped with a warning.

---

<a id="property-end"></a>
### float end = `0.0`

LOOP_REGION / TRANSITION_REGION: where the region ends, in the same units as
[position](#property-position).

---

<a id="property-kind"></a>
### [Kind](#enum-kind) kind = `MARKER`

What the marker does. See [Kind](#enum-kind).

---

<a id="property-name"></a>
### String name = `""`

MARKER: the name sent with `timeline_marker`. DESTINATION: the name transitions refer to.

---

<a id="property-position"></a>
### float position = `0.0`

Where the marker is, or where the region starts.

---

<a id="property-probability"></a>
### float probability = `100.0`

LOOP_REGION / TRANSITION / TRANSITION_REGION: chance, in percent, that the marker acts when
reached.

---

<a id="property-quantization"></a>
### [Quantization](#enum-quantization) quantization = `NONE`

TRANSITION / TRANSITION_REGION: see [Quantization](#enum-quantization).

## Method Descriptions

<a id="method-is_region"></a>
### bool is_region()

`true` for LOOP_REGION and TRANSITION_REGION.
