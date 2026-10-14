# ChirpSnapshot

**Inherits:** [Resource](https://docs.godotengine.org/en/stable/classes/class_resource.html)

A mixer state blended in while active.

## Description

A pause menu that muffles the game, music ducking under dialogue, an underwater filter. Add the
snapshot to [ChirpConfig.snapshots](ChirpConfig.md#property-snapshots) and start it by name, or
pass the resource itself to [Chirp.mixer.start_snapshot()](ChirpMixer.md#method-start_snapshot).
Each start gives a [ChirpSnapshotInstance](ChirpSnapshotInstance.md).

While active, each of its [bus_overrides](#property-bus_overrides) is applied with the instance's
weight ([ChirpSnapshotInstance.get_level()](ChirpSnapshotInstance.md#method-get_level)). Snapshots
apply after VCAs and bus automation, lowest [priority](#property-priority) first; among equal
priorities, in the order they started.

## Tutorials

- [Snapshots](../../README.md#snapshots)

## Properties

| Type | Name | Default |
|---|---|---|
| Array[[ChirpBusOverride](ChirpBusOverride.md)] | [bus_overrides](#property-bus_overrides) | `[]` |
| [ChirpEnvelope](ChirpEnvelope.md) | [envelope](#property-envelope) | `null` |
| String | [intensity_parameter](#property-intensity_parameter) | `""` |
| String | [name](#property-name) | `""` |
| int | [priority](#property-priority) | `0` |

## Property Descriptions

<a id="property-bus_overrides"></a>
### Array[[ChirpBusOverride](ChirpBusOverride.md)] bus_overrides = `[]`

The changes the snapshot makes.

---

<a id="property-envelope"></a>
### [ChirpEnvelope](ChirpEnvelope.md) envelope = `null`

Fades the snapshot in (attack, hold, decay, sustain) and out when stopped (release). No envelope =
applied fully at once and removed at once.

---

<a id="property-intensity_parameter"></a>
### String intensity_parameter = `""`

Name of a global parameter that drives the snapshot's strength: its range maps to 0..1.
Empty = none. An unknown parameter has no effect.

---

<a id="property-name"></a>
### String name = `""`

The name used by [start_snapshot()](ChirpMixer.md#method-start_snapshot).

---

<a id="property-priority"></a>
### int priority = `0`

Higher priority is applied later, so it wins where snapshots overlap.
