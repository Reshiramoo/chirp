# ChirpAutomation

**Inherits:** [Resource](https://docs.godotengine.org/en/stable/classes/class_resource.html)

Maps a parameter onto an event's volume or pitch through a curve.

## Description

Add to [ChirpEvent.automations](ChirpEvent.md#property-automations). Every frame, the parameter's
position in its range is looked up on the [curve](#property-curve): the curve's X axis spans the
parameter's range (its `min_domain` = the parameter's minimum, its `max_domain` = the maximum),
and its Y value multiplies the target: linear gain for VOLUME, pitch scale for PITCH. Raise the
curve's `max_value` above 1 to boost or pitch up.

Example: a sound that fades out with distance, using a `DISTANCE_NORMALIZED` built-in parameter
named `"Distance"` and a curve going from 1 down to 0:

```gdscript
var fade := ChirpAutomation.new()
fade.parameter = "Distance"
fade.curve = preload("res://audio/curves/fade_out.tres")
event.automations.append(fade)
```

## Tutorials

- [Parameters](../../README.md#parameters)

## Properties

| Type | Name | Default |
|---|---|---|
| Curve | [curve](#property-curve) | `null` |
| bool | [global](#property-global) | `false` |
| String | [parameter](#property-parameter) | `""` |
| [Target](#enum-target) | [target](#property-target) | `VOLUME` |

## Methods

| Return | Signature |
|---|---|
| float | [evaluate](#method-evaluate)(definition: [ChirpParameter](ChirpParameter.md), value: float) |
| float | [sample_curve](#method-sample_curve)(curve: Curve, definition: [ChirpParameter](ChirpParameter.md), value: float) static |

## Enumerations

<a id="enum-target"></a>
### enum Target

- **VOLUME** = `0`: the curve's Y is a linear gain.
- **PITCH** = `1`: the curve's Y is a pitch scale (2.0 = an octave up).

## Property Descriptions

<a id="property-curve"></a>
### Curve curve = `null`

The mapping. Without a curve, the automation has no effect.

---

<a id="property-global"></a>
### bool global = `false`

Read a global parameter (from [ChirpConfig](ChirpConfig.md)) instead of the event's own.

---

<a id="property-parameter"></a>
### String parameter = `""`

Name of the parameter (case-insensitive). If it doesn't exist, the automation has no effect.

---

<a id="property-target"></a>
### [Target](#enum-target) target = `VOLUME`

What the curve drives. See [Target](#enum-target).

## Method Descriptions

<a id="method-evaluate"></a>
### float evaluate(definition: [ChirpParameter](ChirpParameter.md), value: float)

The multiplier for `value` of the parameter `definition`: `sample_curve(curve, definition, value)`.

---

<a id="method-sample_curve"></a>
### float sample_curve(curve: Curve, definition: [ChirpParameter](ChirpParameter.md), value: float) static

Samples `curve` at `value`'s position within the parameter's range (clamped). Returns `1.0` for a
`null` curve. Also used by [ChirpBusAutomation](ChirpBusAutomation.md).
