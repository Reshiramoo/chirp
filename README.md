# Chirp

Sound design plugin for Godot 4.6+: FMOD-style audio events, built entirely on Godot's own audio engine.
No native libraries, so it runs anywhere Godot does (desktop, Android, iOS, web).

- **Events** instead of loose `AudioStreamPlayer` nodes: playlists, randomization, layering, delays,
  envelopes, voice limits, all as resources you can tweak without touching code.
- **Parameters** that game code sets (`"Speed"`, `"Danger"`) or that Chirp fills in from the
  listener (distance, direction, speed), driving volume and pitch through curves.
- **Timelines** for interactive music: loop regions, sustain points, transitions quantized to
  beats or bars, tempo markers and beat signals.
- **Mixing**: bus volumes, VCAs, snapshots (pause muffle), ducking (music under dialogue), bus automation, pausing by bus.
- **Emitters**: drop-in 2D/3D nodes that play on ready, on contact, on click, and so on.
- **Editor tools**: an event browser, a preview dock with live parameter sliders, a visual timeline
  editor and attenuation gizmos.

## Contents

- [Installation](#installation)
- [Quick start](#quick-start)
- [Events and event paths](#events-and-event-paths)
  - [Scatterer and programmer instruments](#scatterer-and-programmer-instruments)
- [Playing events from code](#playing-events-from-code)
  - [Loading](#loading)
- [Instances and their lifecycle](#instances-and-their-lifecycle)
  - [Voice budget and virtual instances](#voice-budget-and-virtual-instances)
- [Parameters](#parameters)
- [Timelines and interactive music](#timelines-and-interactive-music)
- [Parameter sheets](#parameter-sheets)
- [Listeners and roll-off](#listeners-and-roll-off)
- [Mixing](#mixing)
  - [Effects per event](#effects-per-event)
- [Emitter nodes](#emitter-nodes)
  - [Parameter triggers](#parameter-triggers)
- [Editor tools](#editor-tools)
- [Class reference](#class-reference)
- [Limitations](#limitations)

## Installation

1. Clone this repository into your project's `addons` folder as `chirp`:
   ```bash
   git clone https://github.com/Reshiramoo/chirp.git addons/chirp
   ```
   (or add it as a submodule: `git submodule add https://github.com/Reshiramoo/chirp.git addons/chirp`).
   The folder must be named `chirp`.
2. **Project → Project Settings → Plugins** → enable **Chirp**. This adds the `Chirp` autoload
   (see [Chirp](docs/classes/Chirp.md)).
3. Set up the **Chirp** section of Project Settings:

   | Setting | Type | Default | Meaning |
   |---|---|---|---|
   | `chirp/sound_directories` | `Dictionary[String, String]` | `{"res://audio": ""}` | Folders to find sounds in, each mapped to a bus path (`""` = Master). |
   | `chirp/config` | `String` | `"res://audio/chirp_config.tres"` | Optional [ChirpConfig](docs/classes/ChirpConfig.md) holding global parameters, VCAs, snapshots, bus automation and ducking. |
   | `chirp/pause_on_app_background` | `bool` | `true` | Pause every event while a mobile app is in the background. |
   | `chirp/effect_bus_pool_size` | `int` | `8` | Buses lent to events with effects (see [Effects per event](#effects-per-event)). |
   | `chirp/max_voices` | `int` | `0` | Most sounds playing at once; `0` = no limit (see [Voice budget](#voice-budget-and-virtual-instances)). |
   | `chirp/virtualize_below_db` | `float` | `-80.0` | Instances quieter than this at the listener go virtual; `-120` turns it off. |

   For example, for sounds in `res://assets/sounds/bgms` and `res://assets/sounds/sfxs`:
   ```
   "res://assets/sounds/bgms": "bus:/BGM"
   "res://assets/sounds/sfxs": "bus:/SFX"
   ```
   Bus paths name Godot buses from the **Audio** panel: `"bus:/SFX"` is the bus named `SFX`,
   `"bus:/SFX/UI"` the bus named `UI` (the last segment counts), `"bus:/"` is Master.
   Unknown buses fall back to Master with a warning.

## Quick start

```gdscript
# Any audio file in a sound directory is an event already.
Chirp.play_one_shot("event:/sfxs/coin")

# Play at a position (Vector2 for 2D, Vector3 for 3D), or follow a node.
Chirp.play_one_shot("event:/sfxs/explosion", global_position)
Chirp.play_one_shot_attached("event:/sfxs/engine", self)

# Keep a handle for anything that loops or needs control.
var music := Chirp.create_instance("event:/bgms/main")
music.start()
music.set_parameter("Intensity", 0.8)
music.stop()       # fades out with the event's envelope release
music.release()    # free it once it has stopped
```

Or skip code: add a [ChirpEmitter2D](docs/classes/ChirpEmitter2D.md) /
[ChirpEmitter3D](docs/classes/ChirpEmitter3D.md), pick the event and set `play_on`.

## Events and event paths

Every sound in a sound directory gets an event path: `event:/`, the directory's folder name,
then the file's path inside it without its extension.

| File | Event path |
|---|---|
| `res://assets/sounds/sfxs/coin.mp3` | `"event:/sfxs/coin"` |
| `res://assets/sounds/sfxs/ui/click.ogg` | `"event:/sfxs/ui/click"` |
| `res://assets/sounds/bgms/main.tres` (a ChirpEvent) | `"event:/bgms/main"` |

The folder name is part of the path: with the default `res://audio` directory, `res://audio/coin.mp3`
is `"event:/audio/coin"`, not `"event:/coin"`. An unknown path reports an error suggesting the
closest known paths, and the **Chirp** dock lists every path.

Plain audio files (`.wav`, `.ogg`, `.mp3`) play as they are, on their directory's bus.
When a sound needs more, create a [ChirpEvent](docs/classes/ChirpEvent.md) resource. Saved next
to an audio file with the same name, it takes over that path. Events built in code can be given
a path with [`Chirp.events.register_event()`](docs/classes/ChirpEvents.md#method-register_event).

A ChirpEvent is a list of [ChirpInstrument](docs/classes/ChirpInstrument.md)s plus what controls them:

| ChirpEvent property | Meaning |
|---|---|
| `instruments` | What plays. A `SOUND` instrument has one stream (single sound) or several (playlist: shuffle / random / sequential); `EVENT` nests another event; `SILENCE` waits; `SCATTERER` plays sounds at random intervals and positions; `PROGRAMMER` plays a sound game code supplies. Per-instrument volume, pitch, random volume/pitch, a fixed or random start offset, delay, probability, a parameter condition, a cut behaviour and (on timelines) quantization. |
| `sheet_mode` | `SIMULTANEOUS` triggers all instruments; `CONSECUTIVE` plays them one after another; `TIMELINE` places them on a timeline; `PARAMETER` places them along a parameter. |
| `persistent` | Keep playing after the content ends, until stopped. |
| `bus` | Bus path; empty = its sound directory's bus. |
| `parameters` | Local [ChirpParameter](docs/classes/ChirpParameter.md)s: continuous, discrete or labeled, with optional seek speed. Or built-in. |
| `automations` | [ChirpAutomation](docs/classes/ChirpAutomation.md): volume, pitch, pan or an effect property, from a parameter through a `Curve` or drawn along a timeline. |
| `effects` / `effect_scope` | Effects the event plays through, per instance or shared (see [Effects per event](#effects-per-event)). |
| `modulators` | [ChirpLFO](docs/classes/ChirpLFO.md): sine, triangle, square, saw or random waves on volume or pitch, in Hz or synced to the tempo. |
| `envelope` | [ChirpEnvelope](docs/classes/ChirpEnvelope.md) (AHDSR). `release` is the fade-out used by `stop()`. |
| `max_instances` / `stealing` / `cooldown` | Voice limits: steal oldest, quietest, furthest, or refuse. |
| `priority` | Who keeps playing when the [voice budget](#voice-budget-and-virtual-instances) runs out. |
| `rolloff` / `min_distance` / `max_distance` | Distance roll-off: Godot's, or linear, inverse, tapered or a custom curve (see [Listeners and roll-off](#listeners-and-roll-off)). |

### Scatterer and programmer instruments

A **scatterer** keeps spawning sounds from its playlist, every `spawn_interval_min` to
`spawn_interval_max` seconds, with at most `polyphony` at once and, if set, `spawn_total` in all. On
a spatial event each sound lands `scatter_distance_min` to `scatter_distance_max` away from the
event and keeps that offset as it moves: rain on a roof, birds in a forest, distant battle.

A **programmer** instrument plays whatever sound game code supplies for its `programmer_key` when
it triggers, so one event can carry the volume, bus, envelope and 3D settings for every dialogue line:

```gdscript
var line := Chirp.create_instance("event:/voice/npc")
line.set_programmer_sound("line", load("res://voice/en/intro_01.ogg"))
line.start()

# Or answer on demand, which also works for one-shots:
Chirp.events.programmer_sound_provider = func(key: String, _instance) -> AudioStream:
	return load("res://voice/%s/%s.ogg" % [TranslationServer.get_locale(), key])
```

Instances also emit `programmer_sound_requested(key, instrument)` just before the lookup.

## Playing events from code

The [Chirp](docs/classes/Chirp.md) autoload has shortcuts for the common calls; everything else is
grouped by module:

| Module | Calls |
|---|---|
| [`Chirp.events`](docs/classes/ChirpEvents.md) | `preload_events`, `unload_events`, `is_event_loaded`, `get_preload_progress`, `programmer_sound_provider`, `get_event`, `get_event_paths`, `get_event_file`, `register_event`, `create_instance`, `play_one_shot`, `play_one_shot_attached`, `get_active_instances`, `stop_all`, `scan` |
| [`Chirp.mixer`](docs/classes/ChirpMixer.md) | `set_bus_volume`, `get_bus_volume`, `set_bus_mute`, `set_bus_paused`, `stop_bus_events`, `resolve_bus`, `set_vca_volume`, `get_vca_volume`, `start_snapshot`, `get_active_snapshots`, `stop_all_snapshots`, `pause_all`, `mute_all` |
| [`Chirp.parameters`](docs/classes/ChirpParameters.md) | `set_value`, `set_label`, `get_value` (global parameters) |

```gdscript
Chirp.parameters.set_value("Danger", 0.8)
Chirp.mixer.set_vca_volume("Music", 0.5)       # settings-menu slider
Chirp.mixer.set_bus_volume("bus:/SFX", 0.7)
Chirp.mixer.set_bus_paused("bus:/SFX", true)   # pause menu
Chirp.mixer.stop_bus_events("bus:/BGM")
Chirp.mixer.pause_all(true)                    # e.g. while an ad shows
```

Every call accepts either an `"event:/..."` path or a ChirpEvent resource.

### Loading

An event's file loads the first time it plays, then stays loaded. That first load can cause a small
hitch, most noticeable on mobile, so load what a level needs up front, e.g. behind a loading screen:

```gdscript
Chirp.events.preload_events(["event:/sfxs", "event:/bgms/level_2"])   # in the background
await Chirp.events.preload_finished                                      # or poll get_preload_progress()

Chirp.events.unload_events("event:/bgms/level_1")   # let Godot free what's no longer needed
```

Folders cover everything under them. Unloading never cuts off a sound that is playing, and the next
play loads the file again. On emitters that use `event_path`, tick `preload_event` to load when the
emitter enters the scene.

## Instances and their lifecycle

`create_instance()` returns a [ChirpEventInstance](docs/classes/ChirpEventInstance.md): one
playback of an event.

```
create_instance() ──▶ STOPPED ──start()──▶ PLAYING ──stop()──▶ STOPPING ──release done──▶ STOPPED
                                              │                                          ▲
                                              └──── content ends (non-persistent) ───────┘
```

- `start()` on a playing instance restarts it (`restarted` instead of `started`).
- `stop()` plays the envelope's release; `stop(false)` cuts at once.
- `release()` marks the handle as no longer needed: the instance is destroyed as soon as it is
  stopped (`destroyed` fires, `is_valid()` turns false). `play_one_shot()` releases for you.
- An instance may refuse to start: a voice limit with `stealing = NONE`, or a `cooldown`.
  Otherwise a voice limit stops another instance of the same event to make room.

```gdscript
var music := Chirp.create_instance("event:/bgms/main")
music.started.connect(func(): print("music on"))
music.stopped.connect(_on_music_stopped)
music.start()
```

### Voice budget and virtual instances

Every sound playing costs mixing time, which adds up on phones. Two project settings keep it down
without cutting anything off:

- `chirp/max_voices` (default `0`, no limit): the most sounds playing at once. Over it, the least
  important instances go **virtual**: their sounds pause, but the instance keeps running
  (timeline, parameters, signals). When there's room again they pick up where they would be by
  then, as if they'd played all along; one-shots that would have ended meanwhile end. Importance
  is the event's `priority`, then how loud the instance is at the listener (its volume and
  distance). Nested events count with the instance that plays them.
- `chirp/virtualize_below_db` (default `-80`): instances quieter than this at the listener go
  virtual even under the budget: distant 3D sounds, faded-out layers. `-120` turns it off.

`instance.is_virtual()` and the `virtual_changed` signal tell you when it happens;
`Chirp.events.get_voice_usage()` returns `{real, virtual, limit}`. Both settings can be changed at
runtime through `Chirp.events.max_voices` and `Chirp.events.virtualize_below_db`.

## Parameters

Parameters are named values that drive automation curves and conditions.

- **Local** parameters live on the event (`ChirpEvent.parameters`); each instance has its own
  values: `instance.set_parameter("RPM", 3000.0)`.
- **Global** parameters live in the [ChirpConfig](docs/classes/ChirpConfig.md) and are shared:
  `Chirp.parameters.set_value("Danger", 0.8)`. Automations read them with `global` ticked;
  conditions look for a local parameter first, then a global one.
- **Labeled** parameters take a label: `set_parameter_by_label("Surface", "Gravel")`.
- With `seek_speed` set, a value glides toward its new target instead of jumping (while the
  instance is stopped it always jumps).
- Nested events receive the values of same-named parameters from their parent.

### Built-in parameters

Set a parameter's `built_in` and Chirp fills it in every frame from the event's position
relative to the listener (see [Listeners and roll-off](#listeners-and-roll-off)). Automate on it like any other parameter, e.g. muffle a
sound as it moves away. Built-ins can't be set from code.

| Built-in | Value |
|---|---|
| `DISTANCE` / `DISTANCE_NORMALIZED` | Distance to the listener / 0..1 between the event's min and max distance |
| `DIRECTION` | Where the event is around the listener: 0 ahead, 90 right, -90 left, ±180 behind (in 2D, "ahead" is up) |
| `ELEVATION` | Degrees above or below the listener (3D) |
| `EVENT_CONE_ANGLE` / `EVENT_ORIENTATION` | Angle between where the emitter faces (+X in 2D, -Z in 3D) and the listener, unsigned / signed |
| `SPEED` / `SPEED_ABSOLUTE` | Speed relative to the listener / of the event itself |

For `DISTANCE` and the speeds, set the parameter's `max_value` to the range you care about.

## Timelines and interactive music

With `sheet_mode = TIMELINE`, each instrument has a `start` and `length` on the event's timeline
(`length` 0 = its sound's length). A playhead moves along the timeline: instruments start when it
enters them (at the matching point in their sound) and stop when it leaves, unless `async_playback`
lets them finish. Positions are in seconds, or in beats with `timeline_units = BEATS`.

Everything else on the timeline is a [ChirpMarker](docs/classes/ChirpMarker.md) in the event's
`markers` list:

| Kind | Does |
|---|---|
| `MARKER` | Fires `timeline_marker(name, position)` |
| `TEMPO` | BPM and time signature from here on; fires `timeline_beat(bar, beat, ...)` and sets the grid for quantization |
| `LOOP_REGION` | Loops between `position` and `end` while its condition holds |
| `SUSTAIN_POINT` | Holds the playhead until `key_off()` or its condition stops holding |
| `DESTINATION` | A named point to jump to |
| `TRANSITION` / `TRANSITION_REGION` | Jump to a destination when reached / while inside, if the condition holds, optionally on the next `BEAT` or `BAR` |
| `MAGNET_REGION` | While its condition holds, pulls the playhead in from wherever it is (optionally on the next beat or bar), and keeps it there |

**Transitions** cut by default. Set a transition's `transition_mode` to `CROSSFADE` (fade the old
section out and the new one in) or `BRIDGE` (hold, fading the old section out, then jump), with a
`transition_length` in the event's units: `4` beats is a bar of 4/4. `transition_event` plays an
event as the transition starts: a stinger over the cut or crossfade, or the drum fill of a bridge.
The timeline shows them on the marker, e.g. `→ chorus  (bridge 4, + fill)`.

Conditions are a parameter range (local or global) and a probability. Instruments can have
conditions too, and a cut behaviour (`STOP` or `PLAY_TO_END`) for when it stops holding or a
jump leaves them. An instrument with `quantization` (beat or bar) that becomes due part way through
its region waits for the next beat or bar and plays from its beginning: a stinger over the music
when gameplay sets a parameter. LFOs with `tempo_sync` wobble in time with the tempo markers.

A typical adaptive track: intro, then a loop region on the verse that holds while `Intensity` < 0.5,
and a transition region over the verse that jumps to `"chorus"` on the next bar once `Intensity`
reaches 0.5.

```gdscript
music.timeline_beat.connect(func(bar, beat, position, tempo, signature): pulse_lights())
music.timeline_marker.connect(func(marker_name, position): print(marker_name))
music.sound_played.connect(func(instrument, stream): if stream: print("playing ", stream.resource_path))
music.set_parameter("Intensity", 1.0)   # the transition region jumps on the next bar
music.key_off()                         # release a sustain point
music.set_timeline_position(12.0)       # seek, in seconds
```

**Syncing gameplay to the music:** signals fire when the playhead crosses a beat, accurate to a
frame. For smooth motion, read the position instead. The `get_*_position()` / `get_*_phase()`
helpers default to the *audible* position: the playhead moved on to this moment, minus the output
latency, so what you draw matches what's heard. Players can calibrate the latency with
`Chirp.latency_offset`.

```gdscript
$Player.position.x = lerpf(start_x, wall_x, music.get_bar_phase())   # touches the wall on each bar
$Logo.scale = Vector2.ONE * (1.1 - 0.1 * music.get_beat_phase())      # pulses on each beat
music.call_on_beat(func(bar, beat): spawn_wave(), ChirpMarker.Quantization.BAR)  # next bar, once
```

**Automation lanes:** volume and pitch can follow the timeline too. In the **Chirp Event** dock,
**Add → Add Volume Automation** (or Pitch) adds a lane for the whole event, below the instruments;
right-click an instrument → **Add Volume Automation (this instrument)** adds one for that instrument
alone, right under it (e.g. two layers crossfading). Click to add points,
drag them (snapping to the grid, Shift to ignore), right-click a point or press Delete to remove it.
The value follows the playhead through loops and jumps; a fade-in over the intro, a pitch dive
before a drop.

**Timing:** the playhead moves once per frame, so markers and jumps are accurate to a frame, not a
sample. Loop regions are seamless anyway: while the playhead is inside one, every WAV, Ogg Vorbis or
MP3 sound spanning it loops that exact stretch in the mixer (sample-accurate), so the playhead's
jump back finds it already there. When the condition switches off, the sounds play on through the
region's end without a seam. It applies when:

- the sound starts by the region's start and reaches its end within one pass;
- for Ogg Vorbis and MP3, the region ends where the sound does (they can only loop back from their
  end; WAV can loop any stretch, so prefer WAV for intro / loop / outro in one file);
- the loop is certain: probability 100%, and no sustain point, transition or pending quantized jump
  before the region's end.

Otherwise the region loops as before, accurate to a frame: voices already at the right spot keep
playing (a looping instrument whose loop region is a whole number of its passes, say), and anything
more than 50 ms off is re-seeked. Instruments that start inside a region restart on each pass.

## Parameter sheets

With `sheet_mode = PARAMETER`, instruments sit along a parameter instead of a timeline: name it in
`sheet_parameter` (the event's own, else a global one), and give each instrument a `start` and
`length` in that parameter's units (`length` 0 = to the end of its range). Each instrument plays
while the value is inside its range; `fade_in` and `fade_out` crossfade it at the edges.

A car engine, with an `RPM` parameter from 0 to 6000 and looping layers:

| Instrument | start | length | fade_in | fade_out |
|---|---|---|---|---|
| `idle.ogg` | 0 | 1500 | 0 | 500 |
| `low.ogg` | 1000 | 2500 | 500 | 500 |
| `high.ogg` | 3000 | 0 | 500 | 0 |

```gdscript
engine.set_parameter("RPM", rpm)   # give RPM a seek_speed to glide smoothly between layers
```

Automation lanes work on parameter sheets too: **Add → Add Volume Automation** draws the event's
volume (or pitch) along the sheet parameter, e.g. the whole engine getting louder with RPM, and an
instrument's own lanes shape that layer alone. (For a simple crossfade, the instruments' `fade_in`
/ `fade_out` are enough.) These
lanes edit the automation's `Curve`, so smooth curves shaped in the inspector show and keep their
shape.

An instrument triggers when the value enters its range and stops when it leaves (or plays on with
`PLAY_TO_END` / `async_playback`), so one-shot instruments work too, e.g. a different landing
sound per surface. The **Chirp Event** dock edits parameter sheets as well, with the fades drawn
on each block; clicking its ruler or moving the parameter's slider sets the value while previewing, so you can hear the crossfades.

## Listeners and roll-off

Chirp measures distance and direction from a listener: the current
[ChirpListener2D](docs/classes/ChirpListener2D.md) / [ChirpListener3D](docs/classes/ChirpListener3D.md),
else Godot's current `AudioListener2D/3D`, else the current camera (in 2D without one, the screen
centre). Add a ChirpListener to the camera and point its `attenuation_object` at the player
character to measure distance from the character while panning follows the camera, as in many
third-person games. It also drives Godot's audio listener, so panning matches.

By default an event uses Godot's own distance attenuation (`rolloff = GODOT`). Pick another
`rolloff` on the [ChirpEvent](docs/classes/ChirpEvent.md#enum-rolloff) and Chirp applies it
between `min_distance` and `max_distance`, the same way in 2D and 3D:

| Roll-off | Volume |
|---|---|
| `LINEAR` | Full to `min_distance`, straight line to silence at `max_distance` |
| `LINEAR_SQUARED` | Same, squared: steeper near, gentler far |
| `INVERSE` | `min_distance / distance` (natural); stops falling at `max_distance` |
| `INVERSE_TAPERED` | Inverse nearby, tapering to silence at `max_distance` |
| `CUSTOM` | Your `Curve`, X from `min_distance` to `max_distance` |

The emitter gizmos show the min and max distances.

## Mixing

Chirp recomputes every bus it manages each frame: base volume × VCAs × bus automation, then
snapshots by priority, then ducking. Effect properties start from the value they had when Chirp first touched
them. Buses Chirp never touches are left alone.

### VCAs

A [ChirpVCA](docs/classes/ChirpVCA.md) scales several buses without routing audio, e.g. a "Music"
slider over both the music and stinger buses: `Chirp.mixer.set_vca_volume("Music", 0.5)`.

### Snapshots

A [ChirpSnapshot](docs/classes/ChirpSnapshot.md) is a mixer state blended in while it's active: a
pause menu that muffles the game, ducking music under dialogue, an underwater filter. Add snapshots
to your ChirpConfig, then:

```gdscript
var paused := Chirp.mixer.start_snapshot("Paused")
paused.intensity = 0.5      # half strength
paused.stop()               # fades out with the snapshot's envelope release
```

Each snapshot has [ChirpBusOverride](docs/classes/ChirpBusOverride.md)s. An override can set a
bus's volume, set one property of one of its effects (e.g. `cutoff_hz` of a low-pass filter), and
switch that effect on while active. `OVERRIDE` mode moves toward the value as intensity rises;
`BLEND` adds it. Higher `priority` snapshots apply last. An optional `envelope` fades the snapshot
in and out, and `intensity_parameter` lets a global parameter drive its strength.

### Ducking

A [ChirpDucking](docs/classes/ChirpDucking.md) turns one bus down while another is busy: music
under dialogue, ambience under an explosion. Add them to the ChirpConfig's `duckings`, or with
`Chirp.mixer.add_ducking()`. The trigger is either *events* (any event playing on the trigger bus)
or *level* (the trigger bus's actual loudness, so the music swells back in the pauses between
lines). `attack`, `hold` and `release` shape how it moves.

### Bus automation

[ChirpBusAutomation](docs/classes/ChirpBusAutomation.md) entries in the ChirpConfig let a global
parameter drive a bus's volume or an effect property through a curve, e.g. `"Danger"` closing a
low-pass filter on the music bus.

### Effects per event

Give an event `effects` (e.g. an `AudioEffectLowPassFilter`) and it plays through them, without
setting up a bus: each instance borrows a bus from Chirp's pool that carries copies of the effects
and feeds the event's bus. With `effect_scope = INSTANCE` (the default) every instance has its own,
so automation can differ per emitter; `EVENT` shares one bus between all instances.

Drive effect properties with EFFECT automations, from a parameter, along the timeline or along a
parameter sheet; **Add → Add Effect Automation** in the Chirp Event dock lists every property of the
event's effects with its range. PAN automation pans the event (Chirp adds the panner).

Occlusion, per emitter: an `Occlusion` parameter (0 = clear, 1 = behind a wall) set from a raycast,
automating the low-pass's `cutoff_hz` from 20000 down to 800 (and volume a little):

```gdscript
var blocked := space_state.intersect_ray(query).size() > 0
footsteps.set_parameter("Occlusion", 1.0 if blocked else 0.0)   # give it a seek_speed to smooth it
```

Cost: the buses are nearly free and simple filters are cheap (dozens are fine); reverbs, chorus,
delay and pitch shift are expensive, so keep reverb on a shared bus and route events to it. If more
instances with effects play at once than `chirp/effect_bus_pool_size`, the extra ones play without
effects (with a warning).

### Pausing and muting

`Chirp.mixer.set_bus_paused("bus:/SFX", true)` pauses every event routed into `SFX` or any bus
that sends into it; `pause_all(true)` pauses everything. Paused events keep their place and resume
where they were. `set_bus_mute` and `mute_all` mute at the AudioServer level. With
`chirp/pause_on_app_background`, mobile apps pause their sound while in the background.

## Emitter nodes

Add a [ChirpEmitter2D](docs/classes/ChirpEmitter2D.md) or
[ChirpEmitter3D](docs/classes/ChirpEmitter3D.md), assign the event (or an `event_path`, which also
covers plain audio files), then choose `play_on` / `stop_on`:

| Trigger | Fires when |
|---|---|
| `READY` / `EXIT_TREE` | the emitter enters / leaves the scene |
| `SHOWN` / `HIDDEN` | the emitter's visibility changes |
| `ENTERED` / `EXITED` | a body or area enters/leaves the trigger source (`Area2D/3D`, or `RigidBody2D/3D` contact), filtered by `trigger_group` |
| `MOUSE_ENTERED` / `MOUSE_EXITED` / `MOUSE_DOWN` / `MOUSE_UP` | pointer on the trigger source (`CollisionObject2D/3D` or `Control`) |

The trigger source defaults to the emitter's parent. One-shot events start a new instance
on every `play()` and `stop()` stops the newest one; looping events restart instead of
stacking. Looping sounds stop when the emitter is freed; one-shots finish where they were.

### Parameter triggers

[ChirpParameterTrigger](docs/classes/ChirpParameterTrigger.md) sets parameters on emitters, and
[ChirpGlobalParameterTrigger](docs/classes/ChirpGlobalParameterTrigger.md) sets global ones, on
the same triggers: switch the music to its cave section when the player enters an `Area3D`,
raise `"Danger"` in a boss arena and drop it on the way out, without code.

```
Area2D "Arena"
  ├ ChirpGlobalParameterTrigger  trigger_on = ENTERED, trigger_group = "player", parameters = {"Danger": 1.0}
  └ ChirpGlobalParameterTrigger  trigger_on = EXITED,  trigger_group = "player", parameters = {"Danger": 0.0}
```

## Editor tools

Enabling the plugin adds two docks, a debugger tab and some inspector helpers. Sounds play through a private
preview copy of Chirp, so nothing leaks into your game. Previewing snapshots or bus automation
changes the project's buses only while something is playing, and puts them back afterwards.

| Tool | Where | What it does |
|---|---|---|
| **Chirp** | Right dock | Every event from your sound directories (plain audio files dimmed), plus snapshots, VCAs and global parameters. Filter, select to inspect, double-click to play, drag onto resource slots. **Create Emitter** adds a ChirpEmitter2D/3D for the selected event under the selected node. |
| **Chirp Event** | Bottom dock | Edit and audition in one place. The toolbar has Play / Stop / Stop Now / Key Off (Space plays and stops) and a live status (state, voices, playhead or sheet value); the side panel has sliders for the event's and the global parameters and a log of beats, markers and Chirp's warnings while auditioning (unknown buses or parameters, missing destinations; toggle the panel from the toolbar). Snapshots and events without a timeline are auditioned here too. The editor area shows TIMELINE events and PARAMETER sheets (instruments along the parameter's range, fades drawn, ruler sets the parameter). A warning button in the toolbar counts authoring problems in the shown event (instruments with no sound, transitions to missing destinations, unknown condition or automation parameters, automations aimed at missing effects, a missing sheet parameter...) plus notes such as a loop region that won't be seamless and why; click it for the list, and click an item to select what it's about. Flagged instruments, markers and lanes get a small triangle (yellow: warning, blue: note). Sound instruments show their waveform (decoded in the background, a few milliseconds per frame; on timelines it lines up with time, start offset and looping included; on parameter sheets the whole sound spans the block, with a progress line through each layer while the preview plays). For timelines: instruments as blocks, markers as flags (flags that would overlap stack in rows; double-click or F2 renames a marker, and renaming a destination updates the transitions that point to it), regions in stacked rows, volume and pitch automation lanes (click to add points, drag, right-click or Delete to remove; on parameter sheets they draw along the parameter), mute / solo buttons and a volume knob on each instrument (M and S only affect the editor preview; drag the knob, double-click for 0 dB), a bar/beat grid from the tempo markers, and the preview playhead. Drop audio files or events from the FileSystem or Chirp dock to add instruments where you drop them (onto a sound instrument: added to its playlist; Shift: several files as one playlist). Drag to move, drag edges to resize (snapping to beat or bar, Shift to ignore), right-click to add or delete, Delete key removes, Ctrl/Cmd+wheel zooms, Shift+wheel scrolls, click the ruler to seek. Everything is undoable. |
| **Chirp profiler** | Debugger → Chirp | While the game runs from the editor: voices in use (real / virtual / budget) with a graph, effect buses, every playing instance (event, state, sounds, bus, timeline position, level at the listener; virtual ones dimmed), a meter per bus with its fader and any ducking, active snapshots and global parameter values. Updated four times a second; costs nothing in exported games. The same data is available in game from `Chirp.get_stats()` for your own overlay. |
| **Inspector** | | A **Preview** button on events and snapshots; a searchable picker for emitters' `event_path`. |
| **Gizmos** | 2D / 3D viewports | Max distance circle (2D) or unit size and max distance spheres (3D) on emitters, with drag handles when `override_attenuation` is on; dimmed event values otherwise. |

## Class reference

One page per class, in the layout of Godot's class reference.

**Runtime**

| Class | Inherits | Brief |
|---|---|---|
| [Chirp](docs/classes/Chirp.md) | Node | The autoload: entry point, shortcuts, settings and config. |
| [ChirpEvents](docs/classes/ChirpEvents.md) (`Chirp.events`) | RefCounted | Event registry, instances, one-shots, voice limits. |
| [ChirpMixer](docs/classes/ChirpMixer.md) (`Chirp.mixer`) | RefCounted | Buses, VCAs, snapshots, bus automation, ducking, pausing. |
| [ChirpParameters](docs/classes/ChirpParameters.md) (`Chirp.parameters`) | RefCounted | Global parameters. |
| [ChirpEventInstance](docs/classes/ChirpEventInstance.md) | RefCounted | One playback of an event. |
| [ChirpSnapshotInstance](docs/classes/ChirpSnapshotInstance.md) | RefCounted | One active snapshot. |

**Resources**

| Class | Inherits | Brief |
|---|---|---|
| [ChirpEvent](docs/classes/ChirpEvent.md) | Resource | An instanceable sound: instruments, parameters, automation, envelope, limits. |
| [ChirpInstrument](docs/classes/ChirpInstrument.md) | Resource | A sound, playlist, nested event or silence inside an event. |
| [ChirpParameter](docs/classes/ChirpParameter.md) | Resource | A local or global parameter definition. |
| [ChirpAutomation](docs/classes/ChirpAutomation.md) | Resource | Parameter → event volume or pitch through a curve. |
| [ChirpLFO](docs/classes/ChirpLFO.md) | Resource | Oscillator on an event's volume or pitch. |
| [ChirpEnvelope](docs/classes/ChirpEnvelope.md) | Resource | AHDSR envelope for events and snapshots. |
| [ChirpMarker](docs/classes/ChirpMarker.md) | Resource | Markers, tempo, loops, sustain points and transitions on a timeline. |
| [ChirpConfig](docs/classes/ChirpConfig.md) | Resource | Global parameters, VCAs, snapshots, bus automation and ducking. |
| [ChirpSnapshot](docs/classes/ChirpSnapshot.md) | Resource | A mixer state blended in while active. |
| [ChirpBusOverride](docs/classes/ChirpBusOverride.md) | Resource | One change a snapshot makes to a bus. |
| [ChirpBusAutomation](docs/classes/ChirpBusAutomation.md) | Resource | Global parameter → bus volume or effect property. |
| [ChirpVCA](docs/classes/ChirpVCA.md) | Resource | A volume control over several buses. |
| [ChirpDucking](docs/classes/ChirpDucking.md) | Resource | Turns one bus down while another is busy. |

**Nodes**

| Class | Inherits | Brief |
|---|---|---|
| [ChirpEmitter2D](docs/classes/ChirpEmitter2D.md) | Node2D | Plays an event at its position, on triggers. |
| [ChirpEmitter3D](docs/classes/ChirpEmitter3D.md) | Node3D | Plays an event at its position, on triggers. |
| [ChirpListener2D](docs/classes/ChirpListener2D.md) | Node2D | Where Chirp measures distance and direction from. |
| [ChirpListener3D](docs/classes/ChirpListener3D.md) | Node3D | Where Chirp measures distance and direction from. |
| [ChirpParameterTrigger](docs/classes/ChirpParameterTrigger.md) | Node | Sets parameters on emitters, on triggers. |
| [ChirpGlobalParameterTrigger](docs/classes/ChirpGlobalParameterTrigger.md) | Node | Sets global parameters, on triggers. |

## Limitations

- **Frame timing.** Chirp runs once per frame, so delays, markers, beats and jumps are accurate to
  a frame (about 17 ms at 60 FPS), not a sample.
- **Members starting with `_`** are internal and may change between versions.
- Exported games and mobile devices are not yet tested.
