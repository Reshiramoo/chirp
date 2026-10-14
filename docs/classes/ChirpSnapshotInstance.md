# ChirpSnapshotInstance

**Inherits:** [RefCounted](https://docs.godotengine.org/en/stable/classes/class_refcounted.html)

One active [ChirpSnapshot](ChirpSnapshot.md).

## Description

Created by [Chirp.mixer.start_snapshot()](ChirpMixer.md#method-start_snapshot). While active, the
snapshot's bus overrides are blended into the mix with a weight of
[get_level()](#method-get_level): envelope × [intensity](#property-intensity) × intensity parameter.

```gdscript
var underwater := Chirp.mixer.start_snapshot("Underwater")
underwater.intensity = depth_ratio
# later
underwater.stop()
```

## Tutorials

- [Snapshots](../../README.md#snapshots)

## Properties

| Type | Name | Default |
|---|---|---|
| float | [intensity](#property-intensity) | `1.0` |

## Methods

| Return | Signature |
|---|---|
| float | [get_level](#method-get_level)() |
| [ChirpSnapshot](ChirpSnapshot.md) | [get_snapshot](#method-get_snapshot)() |
| [State](#enum-state) | [get_state](#method-get_state)() |
| bool | [is_playing](#method-is_playing)() |
| void | [stop](#method-stop)(allow_fadeout: bool = true) |

## Signals

<a id="signal-stopped"></a>
### stopped()

Emitted when the snapshot stops: after [stop()](#method-stop), at the end of its release.

## Enumerations

<a id="enum-state"></a>
### enum State

- **STOPPED** = `0`: no longer applied.
- **PLAYING** = `1`: applied.
- **STOPPING** = `2`: fading out after [stop()](#method-stop).

## Property Descriptions

<a id="property-intensity"></a>
### float intensity = `1.0`

How strongly the snapshot applies, 0..1. Multiplied with its envelope and intensity parameter.
Takes effect on the next frame.

## Method Descriptions

<a id="method-get_level"></a>
### float get_level()

The weight the mixer applies right now, 0..1: envelope level × [intensity](#property-intensity) ×
the snapshot's intensity parameter (mapped from its range to 0..1). `0.0` once stopped.

---

<a id="method-get_snapshot"></a>
### [ChirpSnapshot](ChirpSnapshot.md) get_snapshot()

The snapshot resource.

---

<a id="method-get_state"></a>
### [State](#enum-state) get_state()

The current [State](#enum-state).

---

<a id="method-is_playing"></a>
### bool is_playing()

`true` while playing or stopping.

---

<a id="method-stop"></a>
### void stop(allow_fadeout: bool = true)

Stops the snapshot. With `allow_fadeout` and an envelope with a `release`, it fades out first.
A stopped snapshot instance can't be restarted; start the snapshot again instead.
