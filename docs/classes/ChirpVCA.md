# ChirpVCA

**Inherits:** [Resource](https://docs.godotengine.org/en/stable/classes/class_resource.html)

A volume control over several buses that does not route audio itself.

## Description

For settings-menu sliders that should cover several buses, e.g. a "Music" slider over both the
music and stinger buses. Add to [ChirpConfig.vcas](ChirpConfig.md#property-vcas) and set with
[Chirp.mixer.set_vca_volume()](ChirpMixer.md#method-set_vca_volume). The VCA's volume multiplies
each bus's base volume; a bus under several VCAs is scaled by each.

## Tutorials

- [VCAs](../../README.md#vcas)

## Properties

| Type | Name | Default |
|---|---|---|
| PackedStringArray | [buses](#property-buses) | `[]` |
| String | [name](#property-name) | `""` |

## Property Descriptions

<a id="property-buses"></a>
### PackedStringArray buses = `[]`

Bus paths (`"bus:/Music"`) or plain Godot bus names.

---

<a id="property-name"></a>
### String name = `""`

The name used by `set_vca_volume()` and `get_vca_volume()`.
