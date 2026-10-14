# ChirpConfig

**Inherits:** [Resource](https://docs.godotengine.org/en/stable/classes/class_resource.html)

Global parameters, VCAs, snapshots and bus automation.

## Description

Save one as a `.tres` and point the `chirp/config` project setting at it (default
`res://audio/chirp_config.tres`). Chirp loads it at startup; swap it at run time with
[Chirp.apply_config()](Chirp.md#method-apply_config).

Sound directories and background pausing are project settings, not part of the config.

## Tutorials

- [Installation](../../README.md#installation)
- [Mixing](../../README.md#mixing)

## Properties

| Type | Name | Default |
|---|---|---|
| Array[[ChirpBusAutomation](ChirpBusAutomation.md)] | [bus_automations](#property-bus_automations) | `[]` |
| Array[[ChirpParameter](ChirpParameter.md)] | [global_parameters](#property-global_parameters) | `[]` |
| Array[[ChirpSnapshot](ChirpSnapshot.md)] | [snapshots](#property-snapshots) | `[]` |
| Array[[ChirpVCA](ChirpVCA.md)] | [vcas](#property-vcas) | `[]` |

## Property Descriptions

<a id="property-bus_automations"></a>
### Array[[ChirpBusAutomation](ChirpBusAutomation.md)] bus_automations = `[]`

Global parameters driving bus volumes and effect properties.

---

<a id="property-global_parameters"></a>
### Array[[ChirpParameter](ChirpParameter.md)] global_parameters = `[]`

Parameters shared by every event and the mixer, set with
[Chirp.parameters](ChirpParameters.md).

---

<a id="property-snapshots"></a>
### Array[[ChirpSnapshot](ChirpSnapshot.md)] snapshots = `[]`

Snapshots that can be started by name with
[Chirp.mixer.start_snapshot()](ChirpMixer.md#method-start_snapshot).

---

<a id="property-vcas"></a>
### Array[[ChirpVCA](ChirpVCA.md)] vcas = `[]`

Volume controls over groups of buses, set with
[Chirp.mixer.set_vca_volume()](ChirpMixer.md#method-set_vca_volume).
