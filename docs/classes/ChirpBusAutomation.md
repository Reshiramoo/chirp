# ChirpBusAutomation

**Inherits:** [Resource](https://docs.godotengine.org/en/stable/classes/class_resource.html)

Maps a global parameter onto a bus's volume or one of its effect properties.

## Description

Add to [ChirpConfig.bus_automations](ChirpConfig.md#property-bus_automations). The
[curve](#property-curve)'s X axis spans the parameter's range (0 = min, 1 = max), as in
[ChirpAutomation](ChirpAutomation.md).

Example: as `"Danger"` rises, close a low-pass filter (effect 0) on the music bus. Give the curve a
`max_value` of 20000 and points from 20000 down to 800:

```gdscript
var tension := ChirpBusAutomation.new()
tension.bus = "bus:/Music"
tension.parameter = "Danger"
tension.target = ChirpBusAutomation.Target.EFFECT_PROPERTY
tension.effect_index = 0
tension.effect_property = "cutoff_hz"
tension.curve = preload("res://audio/curves/danger_cutoff.tres")
```

## Tutorials

- [Bus automation](../../README.md#bus-automation)

## Properties

| Type | Name | Default |
|---|---|---|
| String | [bus](#property-bus) | `"bus:/"` |
| Curve | [curve](#property-curve) | `null` |
| int | [effect_index](#property-effect_index) | `0` |
| String | [effect_property](#property-effect_property) | `""` |
| String | [parameter](#property-parameter) | `""` |
| [Target](#enum-target) | [target](#property-target) | `VOLUME` |

## Enumerations

<a id="enum-target"></a>
### enum Target

- **VOLUME** = `0`: the curve's Y multiplies the bus volume (linear gain), on top of the base
  volume and VCAs.
- **EFFECT_PROPERTY** = `1`: the curve's Y is the property's value. Raise the curve's `max_value`
  as needed.

## Property Descriptions

<a id="property-bus"></a>
### String bus = `"bus:/"`

The bus path, e.g. `"bus:/Music"`; `"bus:/"` is Master.

---

<a id="property-curve"></a>
### Curve curve = `null`

The mapping. Without a curve, the automation has no effect.

---

<a id="property-effect_index"></a>
### int effect_index = `0`

EFFECT_PROPERTY: position of the effect in the bus's effect list (from 0).

---

<a id="property-effect_property"></a>
### String effect_property = `""`

EFFECT_PROPERTY: the numeric property to drive, e.g. `"cutoff_hz"`.

---

<a id="property-parameter"></a>
### String parameter = `""`

Name of a global parameter. If it doesn't exist, the automation has no effect.

---

<a id="property-target"></a>
### [Target](#enum-target) target = `VOLUME`

What the curve drives. See [Target](#enum-target).
