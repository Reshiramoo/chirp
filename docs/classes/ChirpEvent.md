# ChirpEvent

**Inherits:** [Resource](https://docs.godotengine.org/en/stable/classes/class_resource.html)

An instanceable unit of sound: instruments plus the parameters, automation and envelope that
control them.

## Description

The equivalent of an FMOD Studio event. Save it as a `.tres` in a sound directory to give it an
event path (it takes over an audio file with the same name), or use it directly:
[Chirp.create_instance()](Chirp.md#method-create_instance) accepts the resource itself.

What plays is the list of [instruments](#property-instruments); [sheet_mode](#property-sheet_mode)
decides when each one plays. Each playback is a [ChirpEventInstance](ChirpEventInstance.md).

The volume of each voice is: `volume_db` × instance `volume` × [envelope](#property-envelope) ×
instrument volume × volume [automations](#property-automations) × volume
[modulators](#property-modulators). Pitch works the same way with
[pitch_scale](#property-pitch_scale).

## Tutorials

- [Events and event paths](../../README.md#events-and-event-paths)
- [Timelines and interactive music](../../README.md#timelines-and-interactive-music)

## Properties

| Type | Name | Default |
|---|---|---|
| float | [attenuation_2d](#property-attenuation_2d) | `1.0` |
| Array[[ChirpAutomation](ChirpAutomation.md)] | [automations](#property-automations) | `[]` |
| String | [bus](#property-bus) | `""` |
| float | [cooldown](#property-cooldown) | `0.0` |
| [ChirpEnvelope](ChirpEnvelope.md) | [envelope](#property-envelope) | `null` |
| Array[[ChirpInstrument](ChirpInstrument.md)] | [instruments](#property-instruments) | `[]` |
| Array[[ChirpMarker](ChirpMarker.md)] | [markers](#property-markers) | `[]` |
| int | [max_instances](#property-max_instances) | `0` |
| float | [max_distance_2d](#property-max_distance_2d) | `2000.0` |
| float | [max_distance_3d](#property-max_distance_3d) | `0.0` |
| Array[[ChirpLFO](ChirpLFO.md)] | [modulators](#property-modulators) | `[]` |
| Array[[ChirpParameter](ChirpParameter.md)] | [parameters](#property-parameters) | `[]` |
| bool | [persistent](#property-persistent) | `false` |
| float | [pitch_scale](#property-pitch_scale) | `1.0` |
| [SheetMode](#enum-sheetmode) | [sheet_mode](#property-sheet_mode) | `SIMULTANEOUS` |
| [Stealing](#enum-stealing) | [stealing](#property-stealing) | `OLDEST` |
| [TimelineUnits](#enum-timelineunits) | [timeline_units](#property-timeline_units) | `SECONDS` |
| float | [unit_size_3d](#property-unit_size_3d) | `10.0` |
| float | [volume_db](#property-volume_db) | `0.0` |

## Methods

| Return | Signature |
|---|---|
| [ChirpParameter](ChirpParameter.md) | [find_parameter](#method-find_parameter)(parameter_name: String) |
| bool | [is_one_shot](#method-is_one_shot)() |

## Enumerations

<a id="enum-sheetmode"></a>
### enum SheetMode

- **SIMULTANEOUS** = `0`: trigger every instrument when the event starts.
- **CONSECUTIVE** = `1`: trigger instruments one after another, in list order. Each starts when the
  previous one finishes; instruments skipped by their probability or condition are passed over.
- **TIMELINE** = `2`: instruments sit on a timeline (their `start` / `length`); a playhead moves
  along it and [markers](#property-markers) control it.

---

<a id="enum-timelineunits"></a>
### enum TimelineUnits

- **SECONDS** = `0`: timeline positions are in seconds.
- **BEATS** = `1`: positions are in beats of the TEMPO markers (120 BPM before the first one).

---

<a id="enum-stealing"></a>
### enum Stealing

What happens when an instance starts while [max_instances](#property-max_instances) are already playing.

- **OLDEST** = `0`: stop the instance that started first.
- **QUIETEST** = `1`: stop the instance with the lowest current volume (event volume × instance
  `volume` × envelope).
- **FURTHEST** = `2`: stop the instance furthest from the listener.
- **NONE** = `3`: don't start the new instance.

## Property Descriptions

<a id="property-attenuation_2d"></a>
### float attenuation_2d = `1.0`

2D distance attenuation curve (an easing value, as `AudioStreamPlayer2D.attenuation`).

---

<a id="property-automations"></a>
### Array[[ChirpAutomation](ChirpAutomation.md)] automations = `[]`

Parameter → volume or pitch mappings. Several automations on the same target multiply.

---

<a id="property-bus"></a>
### String bus = `""`

Bus path: `"bus:/SFX"`, or `"bus:/SFX/UI"` where the last segment names the Godot bus; `"bus:/"` is
Master. Empty: the bus of the sound directory the event is saved in, else Master.

---

<a id="property-cooldown"></a>
### float cooldown = `0.0`

Minimum time in seconds between starts of this event (across all its instances). Starting a stopped
instance sooner is refused; restarting a playing one is not.

---

<a id="property-envelope"></a>
### [ChirpEnvelope](ChirpEnvelope.md) envelope = `null`

AHDSR volume envelope. Its `release` is the fade-out used by
[ChirpEventInstance.stop()](ChirpEventInstance.md#method-stop). No envelope = full volume, no fade.

---

<a id="property-instruments"></a>
### Array[[ChirpInstrument](ChirpInstrument.md)] instruments = `[]`

What the event plays.

---

<a id="property-markers"></a>
### Array[[ChirpMarker](ChirpMarker.md)] markers = `[]`

TIMELINE events: markers, tempo markers, loop regions, sustain points, destinations and transitions.
Ignored by other sheet modes.

---

<a id="property-max_distance_2d"></a>
### float max_distance_2d = `2000.0`

2D: distance beyond which the event is inaudible. Also the range of the `DISTANCE_NORMALIZED`
built-in parameter in 2D.

---

<a id="property-max_distance_3d"></a>
### float max_distance_3d = `0.0`

3D: distance beyond which the event is inaudible. `0` = no limit. Also the far end of the
`DISTANCE_NORMALIZED` built-in parameter in 3D.

---

<a id="property-max_instances"></a>
### int max_instances = `0`

Maximum instances of this event playing at once. `0` = unlimited. See [stealing](#property-stealing).

---

<a id="property-modulators"></a>
### Array[[ChirpLFO](ChirpLFO.md)] modulators = `[]`

LFOs on volume (tremolo) or pitch (vibrato). Each instance starts them at a random seed, so
`RANDOM` waves differ between instances.

---

<a id="property-parameters"></a>
### Array[[ChirpParameter](ChirpParameter.md)] parameters = `[]`

Local parameters. Each instance has its own values, set with
[ChirpEventInstance.set_parameter()](ChirpEventInstance.md#method-set_parameter).

---

<a id="property-persistent"></a>
### bool persistent = `false`

Keep playing after the content ends, until stopped. Without it, the event stops once nothing is
playing or waiting to play.

---

<a id="property-pitch_scale"></a>
### float pitch_scale = `1.0`

Pitch multiplier for the whole event.

---

<a id="property-sheet_mode"></a>
### [SheetMode](#enum-sheetmode) sheet_mode = `SIMULTANEOUS`

How the instruments are played. See [SheetMode](#enum-sheetmode).

---

<a id="property-stealing"></a>
### [Stealing](#enum-stealing) stealing = `OLDEST`

What to do when [max_instances](#property-max_instances) is reached. See [Stealing](#enum-stealing).

---

<a id="property-timeline_units"></a>
### [TimelineUnits](#enum-timelineunits) timeline_units = `SECONDS`

Units of instrument `start` / `length` and marker positions on a TIMELINE event. Signals and
[ChirpEventInstance](ChirpEventInstance.md)'s timeline methods always use seconds.

---

<a id="property-unit_size_3d"></a>
### float unit_size_3d = `10.0`

3D: distance at which the event is at full volume (as `AudioStreamPlayer3D.unit_size`). Also the
near end of the `DISTANCE_NORMALIZED` built-in parameter in 3D.

---

<a id="property-volume_db"></a>
### float volume_db = `0.0`

Volume of the whole event, in dB.

## Method Descriptions

<a id="method-find_parameter"></a>
### [ChirpParameter](ChirpParameter.md) find_parameter(parameter_name: String)

The local parameter with this name (case-insensitive), or `null`.

---

<a id="method-is_one_shot"></a>
### bool is_one_shot()

`true` when the event ends by itself: not [persistent](#property-persistent), no looping
instruments, no scatterers without a `spawn_total`, and (on a TIMELINE event) no loop regions or sustain points. Emitters use this to
decide between stacking one-shots and restarting looping sounds.
