# ChirpEnvelope

**Inherits:** [Resource](https://docs.godotengine.org/en/stable/classes/class_resource.html)

An AHDSR volume envelope for an event or a snapshot.

## Description

On a [ChirpEvent](ChirpEvent.md), the envelope shapes the volume from the moment an instance
starts: it rises over [attack](#property-attack), stays at full level for [hold](#property-hold),
falls to [sustain](#property-sustain) over [decay](#property-decay), and stays there.
[ChirpEventInstance.stop()](ChirpEventInstance.md#method-stop) fades from the current level to
silence over [release](#property-release).

On a [ChirpSnapshot](ChirpSnapshot.md), it shapes the snapshot's weight the same way.

## Properties

| Type | Name | Default |
|---|---|---|
| float | [attack](#property-attack) | `0.0` |
| float | [decay](#property-decay) | `0.0` |
| float | [hold](#property-hold) | `0.0` |
| float | [release](#property-release) | `0.0` |
| float | [sustain](#property-sustain) | `1.0` |

## Methods

| Return | Signature |
|---|---|
| float | [level_at](#method-level_at)(time: float) |

## Property Descriptions

<a id="property-attack"></a>
### float attack = `0.0`

Seconds to rise from silence to full level.

---

<a id="property-decay"></a>
### float decay = `0.0`

Seconds to fall from full level to [sustain](#property-sustain), after the hold.

---

<a id="property-hold"></a>
### float hold = `0.0`

Seconds to stay at full level after the attack.

---

<a id="property-release"></a>
### float release = `0.0`

Seconds to fade to silence when stopped with fade-out allowed. `0` = stop at once.

---

<a id="property-sustain"></a>
### float sustain = `1.0`

Level (0..1) held after the decay, until stopped.

## Method Descriptions

<a id="method-level_at"></a>
### float level_at(time: float)

The linear level `time` seconds after the start, not counting the release.
