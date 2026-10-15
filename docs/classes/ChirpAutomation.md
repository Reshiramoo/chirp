# ChirpAutomation

**Inherits:** [Resource](https://docs.godotengine.org/en/stable/classes/class_resource.html)

Drives an event's volume, pitch, pan or an effect property from a parameter, or along its timeline.

## Description

Add to [ChirpEvent.automations](ChirpEvent.md#property-automations) for the whole event, or to an
instrument's [automations](ChirpInstrument.md#property-automations) (VOLUME and PITCH) for that
instrument alone. Every frame the automation gives
a value for its [target](#property-target). VOLUME (linear gain) and PITCH (pitch scale) are
multipliers, and several automations on them multiply. PAN (-1 left to 1 right) and EFFECT (the
effect property's own value, e.g. a cutoff in Hz) set the value; with several on the same property,
the last one wins. PAN and EFFECT act on the event's effect bus (see
[ChirpEvent.effects](ChirpEvent.md#property-effects)); for PAN, Chirp adds a panner to it.

**PARAMETER source** (the default): the parameter's position in its range is looked up on the
[curve](#property-curve). The curve's X axis spans the parameter's range (its `min_domain` = the
parameter's minimum, its `max_domain` = the maximum). Raise the curve's `max_value` above 1 to
boost or pitch up.

**TIMELINE source** (TIMELINE events): the value follows the playhead through [points](#property-points),
placed in the event's timeline units: a fade-in over the first bars of a track, a pitch dive at a
marker. Loops and jumps carry the value with the playhead. Draw them in the **Chirp Event** dock:
**Add → Add Volume Automation** adds a lane under the instruments; click to add points, drag them,
right-click or Delete to remove them. On events without a timeline, TIMELINE automations do nothing.

On a PARAMETER sheet, automations on the sheet parameter appear as lanes in the dock too, along the
parameter's axis. They edit [curve](#property-curve) point by point, so tangents shaped in the
inspector are kept, and their value range is the curve's `min_value` / `max_value`.

Example: a sound that fades out with distance, using a `DISTANCE_NORMALIZED` built-in parameter
named `"Distance"` and a curve going from 1 down to 0:

```gdscript
var fade := ChirpAutomation.new()
fade.parameter = "Distance"
fade.curve = preload("res://audio/curves/fade_out.tres")
event.automations.append(fade)
```

A two-second fade-in on a timeline, in code:

```gdscript
var fade_in := ChirpAutomation.new()
fade_in.source = ChirpAutomation.Source.TIMELINE
fade_in.points = PackedVector2Array([Vector2(0.0, 0.0), Vector2(2.0, 1.0)])
music_event.automations.append(fade_in)
```

## Tutorials

- [Parameters](../../README.md#parameters)
- [Timelines and interactive music](../../README.md#timelines-and-interactive-music)

## Properties

| Type | Name | Default |
|---|---|---|
| Curve | [curve](#property-curve) | `null` |
| int | [effect_index](#property-effect_index) | `0` |
| String | [effect_property](#property-effect_property) | `""` |
| bool | [global](#property-global) | `false` |
| String | [parameter](#property-parameter) | `""` |
| PackedVector2Array | [points](#property-points) | `PackedVector2Array()` |
| [Source](#enum-source) | [source](#property-source) | `PARAMETER` |
| [Target](#enum-target) | [target](#property-target) | `VOLUME` |
| Vector2 | [value_range](#property-value_range) | `Vector2(0, 1)` |

## Methods

| Return | Signature |
|---|---|
| float | [evaluate](#method-evaluate)(definition: [ChirpParameter](ChirpParameter.md), value: float) |
| Vector2 | [lane_range](#method-lane_range)() |
| float | [sample_curve](#method-sample_curve)(curve: Curve, definition: [ChirpParameter](ChirpParameter.md), value: float) static |
| float | [value_at](#method-value_at)(position: float) |

## Enumerations

<a id="enum-target"></a>
### enum Target

- **VOLUME** = `0`: the value is a linear gain multiplier.
- **PITCH** = `1`: the value is a pitch scale multiplier (2.0 = an octave up).
- **PAN** = `2`: the value is the stereo pan, -1 (left) to 1 (right). Chirp adds an
  `AudioEffectPanner` to the event's effect bus.
- **EFFECT** = `3`: the value is set on [effect_property](#property-effect_property) of the event's
  effect number [effect_index](#property-effect_index).

---

<a id="enum-source"></a>
### enum Source

- **PARAMETER** = `0`: a parameter's value, through [curve](#property-curve).
- **TIMELINE** = `1`: the playhead position on a TIMELINE event, through [points](#property-points).

## Constants

- **TIMELINE_RANGE** = `{VOLUME: Vector2(0, 1), PITCH: Vector2(0.5, 2), PAN: Vector2(-1, 1)}`: the
  value range timeline lanes edit within, per target (EFFECT lanes use [value_range](#property-value_range)).

## Property Descriptions

<a id="property-curve"></a>
### Curve curve = `null`

PARAMETER: the mapping. Without a curve, the automation has no effect.

---

<a id="property-effect_index"></a>
### int effect_index = `0`

EFFECT: which of the event's effects, by its position in [ChirpEvent.effects](ChirpEvent.md#property-effects).

---

<a id="property-effect_property"></a>
### String effect_property = `""`

EFFECT: the numeric property to set, e.g. `"cutoff_hz"` on `AudioEffectLowPassFilter`. Integer
properties are rounded.

---

<a id="property-global"></a>
### bool global = `false`

PARAMETER: read a global parameter (from [ChirpConfig](ChirpConfig.md)) instead of the event's own.

---

<a id="property-parameter"></a>
### String parameter = `""`

PARAMETER: name of the parameter (case-insensitive). On a PARAMETER sheet, empty means the sheet
parameter (lanes added in the dock leave it empty, so they follow the sheet parameter even if it is
renamed). If the parameter doesn't exist, the automation has no effect.

---

<a id="property-points"></a>
### PackedVector2Array points = `PackedVector2Array()`

TIMELINE: (position in the event's timeline units, value) pairs, sorted by position. The value is
linear between points and holds before the first and after the last; two points at the same
position make a step. Empty = no change.

---

<a id="property-source"></a>
### [Source](#enum-source) source = `PARAMETER`

What drives the value. See [Source](#enum-source). The inspector shows the fields the source uses.

---

<a id="property-target"></a>
### [Target](#enum-target) target = `VOLUME`

What the value drives. See [Target](#enum-target).

---

<a id="property-value_range"></a>
### Vector2 value_range = `Vector2(0, 1)`

EFFECT on a timeline: the range its lane edits within. The dock's **Add → Add Effect Automation**
fills it in from the property's range in Godot (e.g. 1..20500 for a cutoff). On parameter sheets,
the curve's `min_value` / `max_value` play this role.

## Method Descriptions

<a id="method-evaluate"></a>
### float evaluate(definition: [ChirpParameter](ChirpParameter.md), value: float)

PARAMETER: the multiplier for `value` of the parameter `definition`: `sample_curve(curve, definition, value)`.

---

<a id="method-lane_range"></a>
### Vector2 lane_range()

The value range a timeline lane edits within: [value_range](#property-value_range) for EFFECT, else
[TIMELINE_RANGE](#constants) for the target.

---

<a id="method-sample_curve"></a>
### float sample_curve(curve: Curve, definition: [ChirpParameter](ChirpParameter.md), value: float) static

Samples `curve` at `value`'s position within the parameter's range (clamped). Returns `1.0` for a
`null` curve. Also used by [ChirpBusAutomation](ChirpBusAutomation.md).

---

<a id="method-value_at"></a>
### float value_at(position: float)

TIMELINE: the value at `position`, in timeline units. `1.0` without points.
