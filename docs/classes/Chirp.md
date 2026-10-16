# Chirp

**Inherits:** [Node](https://docs.godotengine.org/en/stable/classes/class_node.html)

The Chirp autoload: the runtime entry point.

## Description

Enabling the plugin registers this script as the `Chirp` autoload. It owns the three modules
that do the work, loads the project settings, and runs everything once per frame.

```gdscript
Chirp.play_one_shot("event:/sfxs/coin")          # shortcuts for the common calls
var music := Chirp.create_instance("event:/bgms/main")
music.start()
Chirp.parameters.set_value("Danger", 0.8)        # global parameters
Chirp.mixer.start_snapshot("Paused")             # buses, VCAs, snapshots, pausing
Chirp.events.get_active_instances()              # event registry and instances
```

Chirp keeps running while the scene tree is paused (`process_mode` is `PROCESS_MODE_ALWAYS`);
pause sounds with [ChirpMixer](ChirpMixer.md) instead. In the editor the project's autoload stays
idle; the plugin auditions sounds through a separate copy with [preview](#property-preview) set.

## Tutorials

- [Installation](../../README.md#installation)
- [Playing events from code](../../README.md#playing-events-from-code)

## Properties

| Type | Name | Default |
|---|---|---|
| [ChirpConfig](ChirpConfig.md) | [config](#property-config) | |
| [ChirpEvents](ChirpEvents.md) | [events](#property-events) | |
| float | [latency_offset](#property-latency_offset) | `0.0` |
| [ChirpMixer](ChirpMixer.md) | [mixer](#property-mixer) | |
| [ChirpParameters](ChirpParameters.md) | [parameters](#property-parameters) | |
| bool | [preview](#property-preview) | `false` |

## Methods

| Return | Signature |
|---|---|
| void | [apply_config](#method-apply_config)(new_config: [ChirpConfig](ChirpConfig.md)) |
| [ChirpEventInstance](ChirpEventInstance.md) | [create_instance](#method-create_instance)(event_or_path: Variant) |
| float | [get_output_latency](#method-get_output_latency)() |
| Dictionary | [get_stats](#method-get_stats)() |
| bool | [is_instrument_muted](#method-is_instrument_muted)(instrument: [ChirpInstrument](ChirpInstrument.md)) |
| bool | [is_instrument_soloed](#method-is_instrument_soloed)(instrument: [ChirpInstrument](ChirpInstrument.md)) |
| [ChirpEventInstance](ChirpEventInstance.md) | [play_one_shot](#method-play_one_shot)(event_or_path: Variant, position: Variant = null) |
| [ChirpEventInstance](ChirpEventInstance.md) | [play_one_shot_attached](#method-play_one_shot_attached)(event_or_path: Variant, node: Node) |
| void | [reload_settings](#method-reload_settings)() |
| void | [set_instrument_muted](#method-set_instrument_muted)(instrument: [ChirpInstrument](ChirpInstrument.md), muted: bool) |
| void | [set_instrument_soloed](#method-set_instrument_soloed)(instrument: [ChirpInstrument](ChirpInstrument.md), soloed: bool) |

## Signals

<a id="signal-warning_issued"></a>
### warning_issued(message: String, is_error: bool)

Emitted for every warning and error Chirp reports, which are also printed to the Output panel as
usual: unknown events, buses, parameters or snapshots, missing destinations, a full effect-bus
pool... Warnings that Chirp reports only once (per bus, parameter...) are signalled once too. The
Chirp Event dock shows the editor preview's in its log; connect it to show them in a debug
overlay of your own.

## Constants

- **SETTING_CONFIG** = `"chirp/config"`: project setting holding the path of the [ChirpConfig](ChirpConfig.md).
- **SETTING_SOUND_DIRECTORIES** = `"chirp/sound_directories"`: project setting mapping sound directories to bus paths.
- **SETTING_PAUSE_IN_BACKGROUND** = `"chirp/pause_on_app_background"`: project setting; pause every event while a mobile app is in the background.
- **DEFAULT_CONFIG** = `"res://audio/chirp_config.tres"`
- **DEFAULT_SOUND_DIRECTORIES** = `{"res://audio": ""}`

## Property Descriptions

<a id="property-config"></a>
### [ChirpConfig](ChirpConfig.md) config

The configuration in use: loaded from `chirp/config` by [reload_settings()](#method-reload_settings),
or an empty ChirpConfig if that file does not exist. Replace it with [apply_config()](#method-apply_config).

---

<a id="property-events"></a>
### [ChirpEvents](ChirpEvents.md) events

Event registry and instances: finding events by path, creating and playing instances,
voice limits.

---

<a id="property-latency_offset"></a>
### float latency_offset = `0.0`

Extra seconds between mixing and hearing, on top of what the audio driver reports, used by the
rhythm helpers ([get_audible_position()](ChirpEventInstance.md#method-get_audible_position),
[call_on_beat()](ChirpEventInstance.md#method-call_on_beat)). Let players calibrate it: Bluetooth
headphones add 100–300 ms. Negative values are allowed.

---

<a id="property-mixer"></a>
### [ChirpMixer](ChirpMixer.md) mixer

Bus volumes, VCAs, snapshots, bus automation and pausing.

---

<a id="property-parameters"></a>
### [ChirpParameters](ChirpParameters.md) parameters

Global parameters.

---

<a id="property-preview"></a>
### bool preview = `false`

Set by the editor plugin on its own copy of Chirp, used to audition sounds in the editor.
A preview Chirp only changes the project's buses while something is playing
(see [ChirpMixer.set_live()](ChirpMixer.md#method-set_live)). You don't need to set this.

## Method Descriptions

<a id="method-apply_config"></a>
### void apply_config(new_config: [ChirpConfig](ChirpConfig.md))

Replaces the global parameters, VCAs, snapshots and bus automation with those of
`new_config`. Global parameters go back to their defaults and VCA volumes back to 1.0.
Instances and snapshots already playing keep playing.

---

<a id="method-create_instance"></a>
### [ChirpEventInstance](ChirpEventInstance.md) create_instance(event_or_path: Variant)

Shortcut for [Chirp.events.create_instance()](ChirpEvents.md#method-create_instance).

---

<a id="method-get_output_latency"></a>
### float get_output_latency()

Seconds between Chirp mixing a sound and it being heard: `AudioServer.get_output_latency()` plus
[latency_offset](#property-latency_offset).

---

<a id="method-get_stats"></a>
### Dictionary get_stats()

What Chirp is doing right now: the data behind the editor's profiler (Debugger → Chirp), for your
own debug overlay too.

```
{
  voices = {real, virtual, limit},            # see Chirp.events.get_voice_usage()
  effect_buses = [used, total],
  instances = [{event, state, virtual, paused, voices, bus, position, level_db}],
  buses = [{name, volume_db, peak_db, duck_db, muted}],
  snapshots = [{name, level}],
  parameters = {name: value},                  # global parameters
}
```

`event` is the event path the instance was created from (or its registered path, or its file),
`state` is `"playing"`, `"sustaining"`, `"stopping"` or `"stopped"`, `voices` the sounds it's
playing, `position` its timeline position in seconds (`-1` without a timeline), and `level_db` its
loudness at the listener. While the game runs from the editor, Chirp sends this to the profiler
four times a second; exported games skip it.

---

<a id="method-is_instrument_muted"></a>
### bool is_instrument_muted(instrument: [ChirpInstrument](ChirpInstrument.md))

`true` while [set_instrument_muted()](#method-set_instrument_muted) mutes it.

---

<a id="method-is_instrument_soloed"></a>
### bool is_instrument_soloed(instrument: [ChirpInstrument](ChirpInstrument.md))

`true` while [set_instrument_soloed()](#method-set_instrument_soloed) solos it.

---

<a id="method-play_one_shot"></a>
### [ChirpEventInstance](ChirpEventInstance.md) play_one_shot(event_or_path: Variant, position: Variant = null)

Shortcut for [Chirp.events.play_one_shot()](ChirpEvents.md#method-play_one_shot).

---

<a id="method-play_one_shot_attached"></a>
### [ChirpEventInstance](ChirpEventInstance.md) play_one_shot_attached(event_or_path: Variant, node: Node)

Shortcut for [Chirp.events.play_one_shot_attached()](ChirpEvents.md#method-play_one_shot_attached).

---

<a id="method-reload_settings"></a>
### void reload_settings()

Loads the `chirp/config` resource (as with [apply_config()](#method-apply_config)) and rescans
`chirp/sound_directories` (as with [ChirpEvents.scan()](ChirpEvents.md#method-scan)).
Called automatically when Chirp starts. Call it yourself after changing those project settings
at run time.

---

<a id="method-set_instrument_muted"></a>
### void set_instrument_muted(instrument: [ChirpInstrument](ChirpInstrument.md), muted: bool)

Auditioning: silences `instrument` in every event that plays it while `muted`. The **M** buttons in
the Chirp Event dock use this on the editor's preview Chirp; it isn't saved and doesn't affect the
game. Usable at run time too, e.g. for debugging a mix.

---

<a id="method-set_instrument_soloed"></a>
### void set_instrument_soloed(instrument: [ChirpInstrument](ChirpInstrument.md), soloed: bool)

Auditioning: while any instrument of an event is soloed, that event's other instruments are silent
(other events are unaffected). The **S** buttons in the Chirp Event dock use this on the editor's
preview Chirp.
