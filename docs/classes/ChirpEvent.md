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
| float | [min_distance](#property-min_distance) | `1.0` |
| float | [max_distance](#property-max_distance) | `20.0` |
| float | [max_distance_2d](#property-max_distance_2d) | `2000.0` |
| float | [max_distance_3d](#property-max_distance_3d) | `0.0` |
| Array[[ChirpLFO](ChirpLFO.md)] | [modulators](#property-modulators) | `[]` |
| Array[[ChirpParameter](ChirpParameter.md)] | [parameters](#property-parameters) | `[]` |
| bool | [persistent](#property-persistent) | `false` |
| String | [sheet_parameter](#property-sheet_parameter) | `""` |
| float | [pitch_scale](#property-pitch_scale) | `1.0` |
| [Rolloff](#enum-rolloff) | [rolloff](#property-rolloff) | `GODOT` |
| Curve | [rolloff_curve](#property-rolloff_curve) | `null` |
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
| float | [rolloff_gain](#method-rolloff_gain)(distance: float, near: float = min_distance, far: float = max_distance) |

## Enumerations

<a id="enum-sheetmode"></a>
### enum SheetMode

- **SIMULTANEOUS** = `0`: trigger every instrument when the event starts.
- **CONSECUTIVE** = `1`: trigger instruments one after another, in list order. Each starts when the
  previous one finishes; instruments skipped by their probability or condition are passed over.
- **TIMELINE** = `2`: instruments sit on a timeline (their `start` / `length`); a playhead moves
  along it and [markers](#property-markers) control it.
- **PARAMETER** = `3`: a parameter sheet. Instruments sit on the axis of
  [sheet_parameter](#property-sheet_parameter) (their `start` / `length`, in parameter units), and
  each plays while the parameter's value is inside its range: engine RPM layers, wind strength,
  footsteps by surface. An instrument triggers when the value enters its range (and again only
  after leaving and coming back), and stops when it leaves (or plays on, with `PLAY_TO_END` or
  `async_playback`). Its `fade_in` / `fade_out` crossfade it at the edges of its range. A
  non-persistent event ends once nothing is playing, e.g. when the value is outside every range.

---

<a id="enum-timelineunits"></a>
### enum TimelineUnits

- **SECONDS** = `0`: timeline positions are in seconds.
- **BEATS** = `1`: positions are in beats of the TEMPO markers (120 BPM before the first one).

---

<a id="enum-rolloff"></a>
### enum Rolloff

How volume falls off with distance from the listener on spatial events. Every mode but GODOT is
applied by Chirp, between [min_distance](#property-min_distance) and [max_distance](#property-max_distance),
measured from Chirp's listener (see [ChirpListener3D](ChirpListener3D.md)); Godot's own distance
attenuation is switched off for the event's players, while its panning and Doppler still apply.

- **GODOT** = `0`: Godot's attenuation, from [attenuation_2d](#property-attenuation_2d) /
  [max_distance_2d](#property-max_distance_2d) and [unit_size_3d](#property-unit_size_3d) /
  [max_distance_3d](#property-max_distance_3d). The default.
- **LINEAR** = `1`: full volume up to min_distance, falling in a straight line to silence at max_distance.
- **LINEAR_SQUARED** = `2`: LINEAR squared: falls quickly near the listener, gently toward max_distance.
- **INVERSE** = `3`: the natural falloff, `min_distance / distance`. It stops falling at
  max_distance, so the event never goes silent.
- **INVERSE_TAPERED** = `4`: INVERSE nearby, tapering (as LINEAR_SQUARED) to silence at max_distance.
- **CUSTOM** = `5`: [rolloff_curve](#property-rolloff_curve), its X axis from min_distance (0) to
  max_distance (1), Y the volume.

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


Ignored with a [rolloff](#property-rolloff) other than GODOT.
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
Ignored by other sheet modes, and hidden in the inspector for them.

---

<a id="property-max_distance"></a>
### float max_distance = `20.0`

With a [rolloff](#property-rolloff) other than GODOT: where the roll-off ends (silent, except
INVERSE), in pixels (2D) or meters (3D). Also the far end of the `DISTANCE_NORMALIZED` built-in
parameter. An emitter's attenuation override replaces it with its `max_distance`.

---

<a id="property-max_distance_2d"></a>
### float max_distance_2d = `2000.0`

2D: distance beyond which the event is inaudible. Also the range of the `DISTANCE_NORMALIZED`
built-in parameter in 2D.


Ignored with a [rolloff](#property-rolloff) other than GODOT.
---

<a id="property-max_distance_3d"></a>
### float max_distance_3d = `0.0`

3D: distance beyond which the event is inaudible. `0` = no limit. Also the far end of the
`DISTANCE_NORMALIZED` built-in parameter in 3D.


Ignored with a [rolloff](#property-rolloff) other than GODOT.
---

<a id="property-max_instances"></a>
### int max_instances = `0`

Maximum instances of this event playing at once. `0` = unlimited. See [stealing](#property-stealing).

---

<a id="property-min_distance"></a>
### float min_distance = `1.0`

With a [rolloff](#property-rolloff) other than GODOT: the event plays at full volume up to this
distance. Also the near end of the `DISTANCE_NORMALIZED` built-in parameter. A 3D emitter's
attenuation override replaces it with its `unit_size`.

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

<a id="property-rolloff"></a>
### [Rolloff](#enum-rolloff) rolloff = `GODOT`

How volume falls off with distance. See [Rolloff](#enum-rolloff). The inspector shows the
settings the chosen mode uses.

---

<a id="property-rolloff_curve"></a>
### Curve rolloff_curve = `null`

CUSTOM: the volume (Y, 0..1) from [min_distance](#property-min_distance) (X at the curve's min
domain) to [max_distance](#property-max_distance) (X at its max domain). Without a curve, CUSTOM
falls back to LINEAR.

---

<a id="property-sheet_mode"></a>
### [SheetMode](#enum-sheetmode) sheet_mode = `SIMULTANEOUS`

How the instruments are played. See [SheetMode](#enum-sheetmode).

---

<a id="property-sheet_parameter"></a>
### String sheet_parameter = `""`

PARAMETER sheets: the parameter whose value places the "playhead": one of the event's own
parameters, else a global one. Changing it with a `seek_speed` glides through crossfades.
Unknown names play nothing (with a warning).

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


Ignored with a [rolloff](#property-rolloff) other than GODOT.
---

<a id="property-volume_db"></a>
### float volume_db = `0.0`

Volume of the whole event, in dB.

## Method Descriptions

<a id="method-find_parameter"></a>
### [ChirpParameter](ChirpParameter.md) find_parameter(parameter_name: String)

The local parameter with this name (case-insensitive), or `null`.

---

<a id="method-rolloff_gain"></a>
### float rolloff_gain(distance: float, near: float = min_distance, far: float = max_distance)

The linear volume at `distance` for the event's [rolloff](#property-rolloff), between `near` and
`far`. `1.0` for GODOT.

---

<a id="method-is_one_shot"></a>
### bool is_one_shot()

`true` when the event ends by itself: not [persistent](#property-persistent), no looping
instruments, no scatterers without a `spawn_total`, and (on a TIMELINE event) no loop regions or sustain points. Emitters use this to
decide between stacking one-shots and restarting looping sounds.
