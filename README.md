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
2. **Project → Project Settings → Plugins** → enable **Chirp**. This adds the `AudioEvents` autoload.
3. Optional: create an `AudioEventsConfig` resource, save it as `res://audio/audio_events_config.tres`
   (or point the `audio_events/config` project setting at it) to set the events folder,
   global parameters and VCAs.

## Make an event

Create an **AudioEvent** resource and save it under the events folder (default `res://audio/events`).
Its path becomes its name: `res://audio/events/SFX/Flap.tres` → `"event:/SFX/Flap"`.

| Property | Meaning |
|---|---|
| `instruments` | What plays. One stream = single sound; several = playlist (shuffle / random / sequential). Per-instrument volume, pitch, random volume/pitch, delay, probability, loop. |
| `sheet_mode` | `SIMULTANEOUS` triggers all instruments; `CONSECUTIVE` plays them one after another. |
| `bus` | `"bus:/"` = Master, `"bus:/SFX/UI"` = the Godot bus named `UI`. |
| `parameters` | Local parameters: continuous, discrete or labeled, with optional seek speed. |
| `automations` | Parameter → volume or pitch through a `Curve` (X = parameter range 0..1). Tick `global` to read a global parameter. |
| `envelope` | AHDSR. `release` is the fade-out used by `stop()`. |
| `max_instances` / `stealing` / `cooldown` | Voice limits: steal oldest, quietest, furthest, or refuse. |

## Play it from code

```gdscript
# Fire and forget
AudioEvents.play_one_shot("event:/SFX/Flap")
AudioEvents.play_one_shot("event:/SFX/Explosion", global_position) # Vector2 or Vector3
AudioEvents.play_one_shot_attached("event:/SFX/Engine", self)

# Keep a handle
var music := AudioEvents.create_instance("event:/Music/Level")
music.set_parameter("Intensity", 0.0)
music.start()
music.set_parameter_by_label("Area", "Cave")
music.stop()          # plays the envelope release
music.stop(false)     # cuts immediately
music.release()       # destroy once stopped
music.stopped.connect(_on_music_stopped)

# Mixing
AudioEvents.set_global_parameter("Danger", 0.8)
AudioEvents.set_vca_volume("Music", 0.5)       # settings-menu slider
AudioEvents.set_bus_volume("bus:/SFX", 0.7)
AudioEvents.set_bus_paused("bus:/SFX", true)   # pause menu
AudioEvents.stop_all_bus_events("bus:/SFX")
AudioEvents.pause_all(true)                    # e.g. while an ad shows
```

Events pause automatically while a mobile app is in the background (`pause_on_app_background`).

## Play it from the scene

Add an **AudioEventEmitter2D** or **AudioEventEmitter3D**, assign the event, then choose
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

## Known limits (v0.1)

- No timeline, logic markers, snapshots, banks or event editor yet (see `FEATURES.md`).
- Godot effects live on buses only, so there are no per-event effect chains.
- `loop` on an instrument replays the stream when it ends; for gapless loops, enable looping
  in the stream's import settings.
- Bus volumes set directly on `AudioServer` are overwritten when a VCA covering that bus changes;
  use `AudioEvents.set_bus_volume()` instead.
