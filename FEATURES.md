# FMOD-style audio for Godot — feature list

A Godot 4 plugin that gives Godot the *workflow* of FMOD Studio (data-driven events,
parameters, mixer snapshots, banks) built on Godot's own audio engine. No FMOD code
or binaries are used; behaviour is modelled on FMOD's public documentation
(FMOD Engine 2.02 Studio API guide, FMOD Studio manual, FMOD for Unity docs).

Legend: **[G]** = Godot already provides this (wrap/extend it), **[N]** = needs new code.
Priority: **P0** MVP · **P1** v1 · **P2** later.

---

## 1. Core concepts (the data model)

| FMOD concept | What it is | Godot plan | Pri |
|---|---|---|---|
| **Event** | A named, instanceable unit of sound (`event:/Weapons/Gunshot`) made of tracks, instruments and parameters | Custom `Resource` (`AudioEvent`) with a path, tracks, parameters, properties | P0 |
| **Event description vs instance** | Description = authored data; instance = one live playback with its own parameter values | `AudioEvent` (Resource) → `AudioEventInstance` (RefCounted) | P0 |
| **Bank** | File grouping events + sample data; loaded/unloaded at runtime | `AudioBank` resource listing events; loading = preloading their streams | P1 |
| **Strings bank / GUIDs** | Path ↔ ID lookup | Godot UIDs + a path registry singleton | P1 |
| **Master bank** | Holds the global mixer; must stay loaded | The project's bus layout + snapshot definitions | P1 |

## 2. Events

### 2.1 Lifecycle & playback (runtime API)
- [ ] Create instance, `start()`, `stop(mode)`, `release()` (destroy when finished) — **P0**
- [ ] Stop modes: *allow fade-out* (runs AHDSR release) vs *immediate* — **P0**
- [ ] Playback states: starting (waiting on load), playing, sustaining, stopping, stopped — **P0**
- [ ] One-shot helper: `play_one_shot(path, position)` — create, start, release in one call — **P0**
- [ ] Pause / resume, per-instance volume & pitch — **P0**
- [ ] Timeline position get/set (seek) — **P1**
- [ ] Persistent events (don't end naturally when timeline content runs out) — **P1**
- [ ] Event properties: max instances, stealing mode (oldest / quietest / none / furthest), cooldown, priority — **P1**
- [ ] Virtualisation: inaudible/low-priority instances stop consuming a voice but keep their timeline running — **P2**

### 2.2 Callbacks / signals
- [ ] `started`, `stopped`, `restarted`, `destroyed` — **P0**
- [ ] `timeline_marker(name, position)` — **P1**
- [ ] `timeline_beat(bar, beat, tempo, time_signature)` from tempo markers — **P1** (rhythm gameplay)
- [ ] `sound_played` / `sound_stopped` per instrument — **P2**
- [ ] Callbacks fired on the main thread (FMOD's "deferred callbacks" mode) to keep GDScript safe — **P0**

### 2.3 Timeline & tracks
- [ ] Timeline: instruments placed at time offsets on audio tracks — **P1**
- [ ] Audio tracks with volume/pan and effect chains, routed to an event master track — **P1**
- [ ] Return tracks + sends inside an event — **P2**
- [ ] Action sheet (instruments with no timeline: fire all / fire one, consecutive/simultaneous) — **P0** (simplest event type, covers most SFX)

### 2.4 Logic markers (timeline control — interactive music)
- [ ] **Loop region** — playback loops between two points while its condition holds — **P1**
- [ ] **Sustain point** — playback pauses here until a key-off/condition — **P1**
- [ ] **Destination marker** + **transition marker / region** — jump to a named destination when a condition is met — **P1**
- [ ] **Transition timelines** (crossfade/stinger while jumping) — **P2**
- [ ] **Magnet region** — pulls playback into the region from outside — **P2**
- [ ] **Tempo marker** + **quantisation** (transitions/instrument triggers snap to beat/bar) — **P1**
- [ ] Marker conditions: parameter value range, event state, probability — **P1**
- [G] Godot 4.3+ `AudioStreamInteractive` already does clip-to-clip music transitions; evaluate as a building block — **P1**

## 3. Instruments

| Instrument | Behaviour | Godot plan | Pri |
|---|---|---|---|
| **Single** | Plays one audio file | `AudioStream` reference | P0 |
| **Multi** | Playlist; picks an entry each trigger (random / shuffle / sequential) | [G] `AudioStreamRandomizer` covers random/no-repeat; add sequential | P0 |
| **Silence** | Plays nothing for a duration (for playlists) | trivial | P1 |
| **Event (nested / referenced)** | Plays another event inside this one, with linked parameters | `AudioEvent` reference | P1 |
| **Scatterer** | Spawns sounds randomly in time and 3D around the emitter (rain, birds) | [N] spawn interval, min/max distance, polyphony | P1 |
| **Programmer** | Game code supplies the sound at trigger time (dialogue, localisation) | signal `create_programmer_sound` returning an `AudioStream` | P1 |
| **Command** | Issues an API command (stop another event, set a parameter) | small command enum | P2 |
| **Plug-in** | Generator plug-in | [G] `AudioStreamGenerator` | P2 |

Per-instrument properties:
- [ ] Volume, pitch, start offset, looping, **async** (plays independently of timeline) — **P0/P1**
- [ ] Trigger conditions (parameter range, event state) + **trigger probability** — **P1**
- [ ] Trigger delay, quantisation — **P1**
- [ ] Cut behaviour when untriggered: cut / play to end — **P1**
- [ ] Randomisation of volume/pitch/start offset per trigger — **P0**

## 4. Parameters

- [ ] **Local** (per instance) and **global** (shared, also drive mixer & snapshots) — **P0**
- [ ] Types: **continuous** (float range), **discrete** (integers), **labelled** (named values, set by label) — **P0**
- [ ] Set by name or by ID — **P0**
- [ ] Initial value, min/max, **seek speed** (value glides toward target instead of jumping) — **P1**
- [ ] **Hold value during playback** option — **P2**
- [ ] **Built-in parameters** auto-fed from 3D state: distance, normalised distance, direction, elevation, event cone angle, event orientation, speed (relative/absolute) — **P1**
- [ ] **Automation**: curves mapping parameter → any property (volume, pitch, effect params, pan) — **P0** for volume/pitch, **P1** general
- [ ] Parameter sheets: instruments placed along a parameter axis instead of time (e.g. engine RPM layers) — **P1**
- [ ] Parameter linking between parent and nested events — **P2**

## 5. Modulators

- [ ] **Random** — randomise a property per trigger — **P0**
- [ ] **AHDSR** — attack/hold/decay/sustain/release envelope on start/stop (drives fade-out on stop) — **P0**
- [ ] **LFO** — periodic modulation (sine, square, saw, triangle, random), rate optionally tempo-synced — **P1**
- [ ] **Sidechain** — one signal's level drives another property (ducking) — **P2**
- [ ] **Autopitch** — pitch follows a parameter (engines) — **P2**

## 6. Mixer

- [ ] **Buses / group buses** with volume, pitch, mute, pause, effect chains — [G] `AudioServer` buses — **P0**
- [ ] Bus paths (`bus:/SFX/UI`) mapped onto Godot bus names — **P0**
- [ ] **VCAs** — volume controls that span several buses without routing audio (the "Music volume" slider) — [N] apply multiplicatively to member buses — **P0**
- [ ] **Return buses + sends** (pre/post-fader) — [G] partially via bus sends — **P1**
- [ ] **Snapshots** — saved mixer states blended in/out with intensity and AHDSR (pause-menu muffle, underwater) — **P1**
- [ ] Snapshot priority/blending when several are active — **P1**
- [ ] Snapshots that are themselves 3D (intensity by distance) — **P2**
- [ ] Global parameters automating bus/effect properties — **P1**
- [ ] Port buses (platform-specific outputs like controller speaker) — **P2**

### Effects
- [G] Godot already has: EQ, compressor, limiter, reverb, delay, chorus, distortion, filters, phaser, pitch shift, panner, stereo enhance, spectrum analyser.
- [ ] Per-event / per-track effect chains (Godot effects are bus-only → need per-instance buses or a DSP path) — **P1**
- [ ] Effect parameters automatable/modulatable — **P1**

## 7. 3D / spatialisation

- [ ] Event emitter 3D attributes: position, velocity, forward/up — **P0**
- [ ] **Listeners** — up to 8, with weights; attenuation position can differ from camera (third-person) — **P1** (P0: one listener = Godot camera/`AudioListener3D`)
- [ ] Min/max distance and **attenuation override** per emitter — **P0**
- [ ] Roll-off curves: linear, linear-squared, inverse, inverse-tapered, custom — **P1**
- [ ] **Doppler** (needs velocity) — [G] partially in `AudioStreamPlayer3D` — **P1**
- [ ] Sound cones (directional sources) — **P2**
- [ ] Spread/extent (sound gets wider when close) — **P2**
- [ ] Core reverb zones: 3D reverb areas with a per-event reverb send level — [G] `Area3D` reverb bus — **P1**
- [ ] 2D support (`Node2D` emitters, `AudioListener2D`) — **P0** (Floppy Birb is 2D)

## 8. Banks, loading & memory

- [ ] Load / unload bank; unloading destroys its instances — **P1**
- [ ] Blocking and non-blocking (threaded) load with loading state — **P1**
- [ ] Sample data loading three ways: whole bank, per-event, automatic on instance create; reference counted — **P1**
- [ ] Instance in *starting* state until its data is loaded — **P1**
- [ ] Streaming vs preloaded audio chosen per asset — [G] Ogg/MP3 stream, WAV in memory — **P1**
- [ ] Idle pool: recently used sounds kept briefly to avoid reload thrash — **P2**
- [ ] Localised banks / audio tables (key → audio file per language) feeding programmer instruments — **P2**

## 9. Godot nodes (equivalents of the Unity components)

| Unity component | Godot node | Key options | Pri |
|---|---|---|---|
| Studio Event Emitter | `AudioEventEmitter2D` / `3D` | event path picker; play/stop trigger; initial parameter values; allow fade-out; trigger once; preload sample data; attenuation override (min/max with gizmo); compute velocity without a physics body | P0 |
| Studio Listener | `AudioEventListener2D` / `3D` | listener index; separate attenuation object | P1 |
| Studio Bank Loader | `AudioBankLoader` | bank list; load/unload trigger; preload sample data | P1 |
| Studio Parameter Trigger | `AudioParameterTrigger` | target emitter; parameter values to apply; trigger | P1 |
| Global Parameter Trigger | `AudioGlobalParameterTrigger` | global parameter values; trigger | P1 |

**Trigger conditions** (Unity's list, mapped to Godot signals) — **P0**:
`ready` (Object Start) · `tree_exiting` (Object Destroy) · `visibility_changed` (Enable/Disable) ·
`Area2D/3D body_entered / body_exited` with group filter (Trigger Enter/Exit + tag) ·
`body_entered` on `RigidBody` (Collision Enter/Exit) ·
`CollisionObject mouse_entered / mouse_exited / input_event` (Object Mouse Enter/Exit/Down/Up) ·
`Control mouse_entered / mouse_exited / gui_input` (UI Mouse Enter/Exit/Down/Up) · *None* (call `play()`/`stop()` from script).

One-shot rule from the Unity emitter: each `play()` on a one-shot spawns a new instance and `stop()` stops only the newest; a looping event restarts if played again.

## 10. Scripting API (singleton `AudioEvents`)

- [ ] `play_one_shot(path, position = null)` / `play_one_shot_attached(path, node)` — **P0**
- [ ] `create_instance(path) -> AudioEventInstance` — **P0**
- [ ] `set_global_parameter(name, value)` / `_with_label(name, label)` — **P0**
- [ ] `get_bus(path)`, `get_vca(path)` → volume/mute/pause/stop-all-events — **P0**
- [ ] `load_bank(path, blocking = true)`, `unload_bank`, `is_bank_loaded` — **P1**
- [ ] `start_snapshot(path) -> instance` — **P1**
- [ ] `pause_all()` / `mute_all()` (app focus loss, ads) — **P0** (mobile ads + backgrounding)
- [ ] Main-thread processing each frame (FMOD's `update()` equivalent, automatic) — **P0**

## 11. Editor tooling

- [ ] **Event browser** dock: tree of events, banks, buses, VCAs, snapshots, global parameters; search; drag event into scene → creates emitter — **P1**
- [ ] Event path picker in the inspector with search — **P0**
- [ ] **Event editor**: action-sheet editor (P0), timeline editor with tracks, instruments, logic markers (P1), parameter sheets + automation curve editor (P1) — the biggest piece of work
- [ ] Audition / preview an event in the editor with live parameter sliders — **P1**
- [ ] Attenuation gizmo on emitters — **P1**
- [ ] Mixer view for buses/VCAs/snapshots — **P2**
- [ ] Profiler panel: live instances, voices, CPU — **P2**
- [ ] Live update (tweak a running game's mix from the editor) — **P2**

## 12. Platform & integration
- [ ] Works on desktop, Android, iOS, web (pure GDScript/C++ on Godot audio → no per-platform native libs) — **P0**
- [ ] Mobile: pause on app background, resume on focus; respect silent switch where possible — **P0**
- [ ] Pure GDScript first; move hot paths (scheduling, modulators) to a GDExtension only if profiling demands it — **P0**

---

## Suggested MVP (P0 only)

Enough to replace scattered `AudioStreamPlayer`s in a game like Floppy Birb:

1. `AudioEvent` resource: action sheet of single/multi instruments with randomised volume/pitch, AHDSR fade, max instances + stealing.
2. Local + global parameters (continuous/discrete/labelled) automating volume and pitch.
3. `AudioEventInstance` with start/stop/release, states, signals on the main thread.
4. Bus paths + VCAs over Godot's `AudioServer`.
5. `AudioEventEmitter2D/3D` with trigger conditions, inspector event picker.
6. `AudioEvents` singleton: one-shots, global parameters, pause/mute all.

Timeline + logic markers (interactive music), snapshots, banks and the event browser make up v1.

## Sources
- FMOD Engine 2.02 — Studio API Guide: https://www.fmod.com/docs/2.02/api/studio-guide.html
- FMOD for Unity 2.02 — Game Components: https://www.fmod.com/docs/2.02/unity/game-components.html
- FMOD Studio 2.02 — Glossary: https://www.fmod.com/docs/2.02/studio/glossary.html
