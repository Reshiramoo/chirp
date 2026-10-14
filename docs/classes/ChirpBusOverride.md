# ChirpBusOverride

**Inherits:** [Resource](https://docs.godotengine.org/en/stable/classes/class_resource.html)

One change a [ChirpSnapshot](ChirpSnapshot.md) makes to a bus.

## Description

An override can change a bus's volume, one numeric property of one of its effects, and/or switch
one of its effects on, all while the snapshot is active. Use several overrides for several buses
or effect properties.

Example: muffle the game while paused, with a low-pass filter (disabled in the bus layout) at index
0 of the `SFX` bus:

```gdscript
var muffle := ChirpBusOverride.new()
muffle.bus = "bus:/SFX"
muffle.effect_index = 0
muffle.effect_property = "cutoff_hz"
muffle.effect_value = 800.0
muffle.enable_effect = true
```

## Tutorials

- [Snapshots](../../README.md#snapshots)

## Properties

| Type | Name | Default |
|---|---|---|
| String | [bus](#property-bus) | `"bus:/"` |
| int | [effect_index](#property-effect_index) | `-1` |
| String | [effect_property](#property-effect_property) | `""` |
| float | [effect_value](#property-effect_value) | `0.0` |
| bool | [enable_effect](#property-enable_effect) | `false` |
| [Mode](#enum-mode) | [mode](#property-mode) | `OVERRIDE` |
| bool | [override_volume](#property-override_volume) | `false` |
| float | [volume_db](#property-volume_db) | `0.0` |

## Enumerations

<a id="enum-mode"></a>
### enum Mode

- **OVERRIDE** = `0`: move toward the value as the snapshot's weight rises (at weight 1, the value
  replaces what was there).
- **BLEND** = `1`: add the value, scaled by the snapshot's weight.

## Property Descriptions

<a id="property-bus"></a>
### String bus = `"bus:/"`

The bus path, e.g. `"bus:/SFX"`; `"bus:/"` is Master.

---

<a id="property-effect_index"></a>
### int effect_index = `-1`

Position of the effect in the bus's effect list, as shown in the Audio panel (from 0). `-1` = no effect.

---

<a id="property-effect_property"></a>
### String effect_property = `""`

Numeric property of the effect to change, e.g. `"cutoff_hz"` on `AudioEffectLowPassFilter`.
Empty = none. Integer properties are rounded.

---

<a id="property-effect_value"></a>
### float effect_value = `0.0`

OVERRIDE: the property's target value. BLEND: the amount added at full weight.

---

<a id="property-enable_effect"></a>
### bool enable_effect = `false`

Switch the effect at [effect_index](#property-effect_index) on while the snapshot is active, even
if it's disabled on the bus.

---

<a id="property-mode"></a>
### [Mode](#enum-mode) mode = `OVERRIDE`

How the volume and effect value combine with what's already there. See [Mode](#enum-mode).

---

<a id="property-override_volume"></a>
### bool override_volume = `false`

Change the bus's volume.

---

<a id="property-volume_db"></a>
### float volume_db = `0.0`

OVERRIDE: the target volume in dB. BLEND: dB added at full weight (use negative values to duck).
