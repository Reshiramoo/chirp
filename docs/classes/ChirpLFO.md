# ChirpLFO

**Inherits:** [Resource](https://docs.godotengine.org/en/stable/classes/class_resource.html)

A low-frequency oscillator on an event's volume or pitch.

## Description

Add to [ChirpEvent.modulators](ChirpEvent.md#property-modulators) for tremolo, vibrato or wobbling
engines, independent of parameters. The wave starts when the instance starts. Several LFOs on the
same target multiply.

With [tempo_sync](#property-tempo_sync), the cycle follows the beat instead of [rate](#property-rate):
[beats_per_cycle](#property-beats_per_cycle) beats per cycle. On TIMELINE events it locks to the
beat grid of the TEMPO marker in effect (the grid [timeline_beat](ChirpEventInstance.md#signal-timeline_beat)
counts on), so a wobble stays on the beat through tempo changes and jumps; elsewhere it runs at
120 BPM from the start.

```gdscript
var vibrato := ChirpLFO.new()
vibrato.target = ChirpLFO.Target.PITCH
vibrato.rate = 5.0   # Hz
vibrato.depth = 0.3  # semitones up and down
event.modulators.append(vibrato)
```

## Properties

| Type | Name | Default |
|---|---|---|
| float | [depth](#property-depth) | `0.5` |
| float | [phase](#property-phase) | `0.0` |
| float | [beats_per_cycle](#property-beats_per_cycle) | `1.0` |
| float | [rate](#property-rate) | `1.0` |
| [Shape](#enum-shape) | [shape](#property-shape) | `SINE` |
| [Target](#enum-target) | [target](#property-target) | `VOLUME` |
| bool | [tempo_sync](#property-tempo_sync) | `false` |

## Methods

| Return | Signature |
|---|---|
| float | [factor](#method-factor)(time: float, seed: int) |
| float | [factor_at_beat](#method-factor_at_beat)(beats: float, seed: int) |
| float | [factor_at_cycle](#method-factor_at_cycle)(cycle: float, seed: int) |
| float | [sample](#method-sample)(time: float, seed: int) |
| float | [sample_at_cycle](#method-sample_at_cycle)(cycle: float, seed: int) |

## Enumerations

<a id="enum-target"></a>
### enum Target

- **VOLUME** = `0`: tremolo.
- **PITCH** = `1`: vibrato.

---

<a id="enum-shape"></a>
### enum Shape

- **SINE** = `0`
- **TRIANGLE** = `1`: lowest at the start of the cycle, highest half way.
- **SQUARE** = `2`: high for the first half of the cycle, low for the second.
- **SAW_UP** = `3`: rises from low to high over the cycle.
- **SAW_DOWN** = `4`: falls from high to low over the cycle.
- **RANDOM** = `5`: a new random level every cycle (sample and hold), different for each instance.

## Property Descriptions

<a id="property-beats_per_cycle"></a>
### float beats_per_cycle = `1.0`

With [tempo_sync](#property-tempo_sync): beats per cycle. 1 = one cycle per beat, 0.5 = eighth
notes, 0.25 = sixteenths, 4 = a bar of 4/4.

---

<a id="property-depth"></a>
### float depth = `0.5`

VOLUME: share of the volume removed at the wave's lowest point (0..1; 1 = silent at the trough).
PITCH: semitones up and down from the base pitch.

---

<a id="property-phase"></a>
### float phase = `0.0`

Starting point in the cycle, 0..1 (0.25 starts a sine at its peak).

---

<a id="property-rate"></a>
### float rate = `1.0`

Cycles per second (Hz), without [tempo_sync](#property-tempo_sync).

---

<a id="property-shape"></a>
### [Shape](#enum-shape) shape = `SINE`

The wave. See [Shape](#enum-shape).

---

<a id="property-tempo_sync"></a>
### bool tempo_sync = `false`

Follow the beat instead of [rate](#property-rate). See the description above. The inspector shows
[beats_per_cycle](#property-beats_per_cycle) instead of rate while it's on.

---

<a id="property-target"></a>
### [Target](#enum-target) target = `VOLUME`

What the LFO modulates. See [Target](#enum-target).

## Method Descriptions

<a id="method-factor"></a>
### float factor(time: float, seed: int)

The multiplier for the target, `time` seconds after the instance started. VOLUME:
`1 - depth × (1 - wave) / 2`, between `1 - depth` and 1. PITCH: `2^(depth × wave / 12)`.
`seed` keeps RANDOM waves different between instances.

---

<a id="method-factor_at_beat"></a>
### float factor_at_beat(beats: float, seed: int)

The multiplier `beats` beats into the beat grid, at [beats_per_cycle](#property-beats_per_cycle) beats per cycle (used with [tempo_sync](#property-tempo_sync)).

---

<a id="method-factor_at_cycle"></a>
### float factor_at_cycle(cycle: float, seed: int)

The multiplier `cycle` cycles in ([phase](#property-phase) is added).

---

<a id="method-sample"></a>
### float sample(time: float, seed: int)

The raw wave at `time`, between -1 and 1.

---

<a id="method-sample_at_cycle"></a>
### float sample_at_cycle(cycle: float, seed: int)

The raw wave `cycle` cycles in ([phase](#property-phase) is added), between -1 and 1.
