# ChirpDucking

**Inherits:** [Resource](https://docs.godotengine.org/en/stable/classes/class_resource.html)

Turns one bus down while another is busy.

## Description

Music under dialogue, ambience under a big explosion. Add duckings to
[ChirpConfig.duckings](ChirpConfig.md#property-duckings), or at runtime with
[Chirp.mixer.add_ducking()](ChirpMixer.md#method-add_ducking).

While the trigger is busy, the ducking's level rises to 1 over `attack` seconds and `target_bus`
goes down by `amount_db` × level. When the trigger stops, the level stays up for `hold` seconds
(bridging the gaps between lines of dialogue), then falls back to 0 over `release` seconds.
Ducking stacks on top of the bus's base volume, VCAs, bus automation and snapshots.

```gdscript
var duck := ChirpDucking.new()
duck.target_bus = "bus:/Music"
duck.trigger_bus = "bus:/Dialogue"
duck.amount_db = -10.0
Chirp.mixer.add_ducking(duck)
```

## Tutorials

- [Ducking](../../README.md#ducking)

## Properties

| Type | Name | Default |
|---|---|---|
| float | [amount_db](#property-amount_db) | `-12.0` |
| float | [attack](#property-attack) | `0.1` |
| float | [hold](#property-hold) | `0.2` |
| float | [release](#property-release) | `0.5` |
| String | [target_bus](#property-target_bus) | `""` |
| float | [threshold_db](#property-threshold_db) | `-40.0` |
| [Trigger](#enum-trigger) | [trigger](#property-trigger) | `EVENTS` |
| String | [trigger_bus](#property-trigger_bus) | `""` |

## Enumerations

<a id="enum-trigger"></a>
### enum Trigger

- **EVENTS** = `0`: busy while any event routed into `trigger_bus` (or a bus below it) is playing
  and not paused.
- **LEVEL** = `1`: busy while `trigger_bus`'s peak level is above `threshold_db`: a sidechain that
  follows the actual sound, so pauses inside a long voice line let the music come back up.

## Property Descriptions

<a id="property-amount_db"></a>
### float amount_db = `-12.0`

How far down `target_bus` goes when fully ducked.

---

<a id="property-attack"></a>
### float attack = `0.1`

Seconds to go fully down once triggered. `0` ducks at once.

---

<a id="property-hold"></a>
### float hold = `0.2`

Seconds to stay down after the trigger stops being busy.

---

<a id="property-release"></a>
### float release = `0.5`

Seconds to come back up after the hold. `0` comes back at once.

---

<a id="property-target_bus"></a>
### String target_bus = `""`

The bus turned down: a bus path (`"bus:/Music"`) or a Godot bus name.

---

<a id="property-threshold_db"></a>
### float threshold_db = `-40.0`

`LEVEL` only: the peak level of `trigger_bus` that counts as busy.

---

<a id="property-trigger"></a>
### [Trigger](#enum-trigger) trigger = `EVENTS`

What makes `trigger_bus` count as busy.

---

<a id="property-trigger_bus"></a>
### String trigger_bus = `""`

The bus whose activity turns `target_bus` down.
