# Chirp

Sound design plugin for Godot 4.6+: FMOD-style audio events, built entirely on Godot's own audio engine.
No native libraries, so it runs anywhere Godot does (desktop, Android, iOS, web).

## Install

1. Clone this repository into your project's `addons` folder as `chirp`:
   ```bash
   git clone https://github.com/Reshiramoo/chirp.git addons/chirp
   ```
   (or add it as a submodule: `git submodule add https://github.com/Reshiramoo/chirp.git addons/chirp`).
   The folder must be named `chirp`.
2. **Project → Project Settings → Plugins** → enable **Chirp**. This adds the `Chirp` autoload.
3. Set up the **Chirp** section of Project Settings:

   | Setting | Default | Meaning |
   |---|---|---|
   | `chirp/sound_directories` | `{"res://audio": ""}` | Folders to find sounds in, each mapped to a bus path (`""` = Master). |
   | `chirp/config` | `res://audio/chirp_config.tres` | Optional `ChirpConfig` resource holding global parameters, VCAs, snapshots and bus automation. |
   | `chirp/pause_on_app_background` | `true` | Pause every event while a mobile app is in the background. |

   For example, for sounds in `res://assets/sounds/bgms` and `res://assets/sounds/sfxs`:
   ```
   "res://assets/sounds/bgms": "bus:/BGM"
   "res://assets/sounds/sfxs": "bus:/SFX"
   ```

## Sounds and events

Every sound in a sound directory gets an event path: the folder's name, then the file path
without its extension.

| File | Event path |
|---|---|
| `res://assets/sounds/sfxs/coin.mp3` | `"event:/sfxs/coin"` |
| `res://assets/sounds/sfxs/ui/click.ogg` | `"event:/sfxs/ui/click"` |
| `res://assets/sounds/bgms/main.tres` (a ChirpEvent) | `"event:/bgms/main"` |

Plain audio files (`.wav`, `.ogg`, `.mp3`) play as they are, on their directory's bus.
When a sound needs more, create a **ChirpEvent** resource. Saved next to an audio file with
the same name, it takes over that path.

| ChirpEvent property | Meaning |
|---|---|
| `instruments` | What plays. A `SOUND` instrument has one stream (single sound) or several (playlist: shuffle / random / sequential); `EVENT` nests another event; `SILENCE` waits. Per-instrument volume, pitch, random volume/pitch, delay, probability, a parameter condition and a cut behaviour. |
| `sheet_mode` | `SIMULTANEOUS` triggers all instruments; `CONSECUTIVE` plays them one after another; `TIMELINE` places them on a timeline (see below). |
| `persistent` | Keep playing after the content ends, until stopped. |
| `bus` | `"bus:/SFX/UI"` = the Godot bus named `UI`; `"bus:/"` = Master. Empty = its sound directory's bus. |
| `parameters` | Local parameters: continuous, discrete or labeled, with optional seek speed. Or built-in (see below). |
| `automations` | Parameter → volume or pitch through a `Curve` (X = parameter range 0..1). Tick `global` to read a global parameter. |
| `modulators` | `ChirpLFO`s: sine, triangle, square, saw or random waves on volume (tremolo) or pitch (vibrato). |
| `envelope` | AHDSR. `release` is the fade-out used by `stop()`. |
| `max_instances` / `stealing` / `cooldown` | Voice limits: steal oldest, quietest, furthest, or refuse. |

## Play it from code

```gdscript
# Fire and forget
Chirp.play_one_shot("event:/sfxs/coin")
Chirp.play_one_shot("event:/sfxs/explosion", global_position) # Vector2 or Vector3
Chirp.play_one_shot_attached("event:/sfxs/engine", self)

# Keep a handle
var music := Chirp.create_instance("event:/bgms/main")
music.set_parameter("Intensity", 0.0)
music.start()
music.set_parameter_by_label("Area", "Cave")
music.stop()          # plays the envelope release
music.stop(false)     # cuts immediately
music.release()       # destroy once stopped
music.stopped.connect(_on_music_stopped)

# Timeline events
music.timeline_beat.connect(func(bar, beat, position, tempo, signature): pass)
music.timeline_marker.connect(func(marker_name, position): pass)
music.key_off()                 # release a sustain point
music.set_timeline_position(12.0)
```

Everything else is grouped by module:

| Module | Calls |
|---|---|
| `Chirp.events` | `get_event`, `get_event_paths`, `register_event`, `create_instance`, `play_one_shot`, `play_one_shot_attached`, `get_active_instances`, `stop_all`, `scan` |
| `Chirp.mixer` | `set_bus_volume`, `get_bus_volume`, `set_bus_mute`, `set_bus_paused`, `stop_bus_events`, `set_vca_volume`, `get_vca_volume`, `start_snapshot`, `get_active_snapshots`, `stop_all_snapshots`, `pause_all`, `mute_all` |
| `Chirp.parameters` | `set_value`, `set_label`, `get_value` (global parameters) |

```gdscript
Chirp.parameters.set_value("Danger", 0.8)
Chirp.mixer.set_vca_volume("Music", 0.5)       # settings-menu slider
Chirp.mixer.set_bus_volume("bus:/SFX", 0.7)
Chirp.mixer.set_bus_paused("bus:/SFX", true)   # pause menu
Chirp.mixer.stop_bus_events("bus:/BGM")
Chirp.mixer.pause_all(true)                    # e.g. while an ad shows
```

### Timelines and interactive music

With `sheet_mode = TIMELINE`, each instrument has a `start` and `length` on the event's timeline
(`length` 0 = its sound's length). A playhead moves along the timeline: instruments start when it
enters them (at the matching point in their sound) and stop when it leaves, unless `async_playback`
lets them finish. Positions are in seconds, or in beats with `timeline_units = BEATS`.

Everything else on the timeline is a **ChirpMarker** in the event's `markers` list:

| Kind | Does |
|---|---|
| `MARKER` | Fires `timeline_marker(name, position)` |
| `TEMPO` | BPM and time signature from here on; fires `timeline_beat(bar, beat, ...)` and sets the grid for quantization |
| `LOOP_REGION` | Loops between `position` and `end` while its condition holds |
| `SUSTAIN_POINT` | Holds the playhead until `key_off()` or its condition stops holding |
| `DESTINATION` | A named point to jump to |
| `TRANSITION` / `TRANSITION_REGION` | Jump to a destination when reached / while inside, if the condition holds, optionally on the next `BEAT` or `BAR` |

Conditions are a parameter range (local or global) and a probability. Instruments can have
conditions too, and a cut behaviour (`STOP` or `PLAY_TO_END`) for when it stops holding or a
jump leaves them.

A typical adaptive track: intro, then a loop region on the verse that holds while `Intensity` < 0.5,
and a transition region over the verse that jumps to `"chorus"` on the next bar once `Intensity`
reaches 0.5.

**Timing:** the playhead moves once per frame, so markers and jumps are accurate to a frame, not a
sample. For seamless loops, import the music with looping on and make the loop region the same
length: when the playhead jumps, voices already at the right spot keep playing instead of
restarting (anything more than 50 ms off is re-seeked).

### Built-in parameters

Set a parameter's `built_in` and Chirp fills it in every frame from the event's position
relative to the listener (the current `AudioListener2D/3D`, else the current camera).
Automate on it like any other parameter, e.g. muffle a sound as it moves away.

| Built-in | Value |
|---|---|
| `DISTANCE` / `DISTANCE_NORMALIZED` | Distance to the listener / 0..1 between the event's min and max distance |
| `DIRECTION` | Where the event is around the listener: 0 ahead, 90 right, -90 left, ±180 behind (in 2D, "ahead" is up) |
| `ELEVATION` | Degrees above or below the listener (3D) |
| `EVENT_CONE_ANGLE` / `EVENT_ORIENTATION` | Angle between where the emitter faces (+X in 2D, -Z in 3D) and the listener, unsigned / signed |
| `SPEED` / `SPEED_ABSOLUTE` | Speed relative to the listener / of the event itself |

For `DISTANCE` and the speeds, set the parameter's `max_value` to the range you care about.

## Mixing

### Snapshots

A **ChirpSnapshot** is a mixer state blended in while it's active: a pause menu that muffles
the game, ducking music under dialogue, an underwater filter. Add snapshots to your `ChirpConfig`, then:

```gdscript
var paused := Chirp.mixer.start_snapshot("Paused")
paused.intensity = 0.5      # half strength
paused.stop()               # fades out with the snapshot's envelope release
```

Each snapshot has `bus_overrides`. An override can set a bus's volume, set one property of one of
its effects (e.g. `cutoff_hz` of a low-pass filter), and switch that effect on while active.
`OVERRIDE` mode moves toward the value as intensity rises; `BLEND` adds it.
Higher `priority` snapshots apply last. An optional `envelope` fades the snapshot in and out, and
`intensity_parameter` lets a global parameter drive its strength.

### Bus automation

`ChirpBusAutomation` entries in the `ChirpConfig` let a global parameter drive a bus's volume
or an effect property through a curve, e.g. `"Danger"` closing a low-pass filter on the music bus.

Chirp recomputes every bus it manages each frame: base volume × VCAs × bus automation, then
snapshots by priority. Effect properties start from the value they had when Chirp first touched them.

## Play it from the scene

Add a **ChirpEmitter2D** or **ChirpEmitter3D**, assign the event, then choose
`play_on` / `stop_on`:

| Trigger | Fires when |
|---|---|
| `READY` / `EXIT_TREE` | the emitter enters / leaves the scene |
| `SHOWN` / `HIDDEN` | the emitter's visibility changes |
| `ENTERED` / `EXITED` | a body or area enters/leaves the trigger source (`Area2D/3D`, or `RigidBody2D/3D` contact), filtered by `trigger_group` |
| `MOUSE_ENTERED` / `MOUSE_EXITED` / `MOUSE_DOWN` / `MOUSE_UP` | pointer on the trigger source (`CollisionObject2D/3D` or `Control`) |

The trigger source defaults to the emitter's parent. One-shot events start a new instance
on every `play()` and `stop()` stops the newest one; looping events restart instead of
stacking. Looping sounds stop when the emitter is freed; one-shots finish where they were.
Emitters also offer initial `parameters`, `allow_fadeout`, `trigger_once` and an attenuation override.

## Layout

| Path | Contents |
|---|---|
| `chirp.gd` | The `Chirp` autoload: creates the modules, shortcuts for common calls |
| `modules/` | `events.gd`, `mixer.gd`, `parameters.gd`. A new feature is a new module plus one line in `chirp.gd`. |
| `resources/` | `ChirpEvent`, `ChirpInstrument`, `ChirpMarker`, `ChirpParameter`, `ChirpAutomation`, `ChirpEnvelope`, `ChirpLFO`, `ChirpVCA`, `ChirpSnapshot`, `ChirpBusOverride`, `ChirpBusAutomation`, `ChirpConfig` |
| `runtime/` | `ChirpEventInstance`, `ChirpSnapshotInstance`, `timeline.gd` (compiled timelines and tempo maps) |
| `nodes/` | `ChirpEmitter2D`, `ChirpEmitter3D` |

## Known limits

- No banks or event editor yet; timelines are set up in the inspector.
- Timeline timing is frame-accurate, not sample-accurate (see Timelines).
- Bars and beats count from each `TEMPO` marker; there is no global bar count across tempo changes.
- `bpm` counts the bar's beats; `beat_unit` is only reported in `timeline_beat`.
- Godot effects live on buses only, so there are no per-event effect chains.
- `loop` on an instrument replays the stream when it ends; for gapless loops, enable looping
  in the stream's import settings.
- Once Chirp manages a bus (VCA, automation, snapshot or `set_bus_volume`), it rewrites its volume every frame,
  so set it with `Chirp.mixer.set_bus_volume()` rather than on `AudioServer`. The same goes for effect
  properties Chirp automates.
- Effects are addressed by their position in the bus's effect list, so reordering effects needs the
  overrides updated.
