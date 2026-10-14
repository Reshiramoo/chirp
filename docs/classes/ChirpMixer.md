# ChirpMixer

**Inherits:** [RefCounted](https://docs.godotengine.org/en/stable/classes/class_refcounted.html)

`Chirp.mixer`: bus volumes, VCAs, snapshots, bus automation and pausing.

## Description

Not a global class: reach it through the autoload as `Chirp.mixer`.

Buses are named by bus paths: `"bus:/SFX"` or `"bus:/SFX/UI"`, where the last segment names the
Godot bus; `"bus:/"` is Master. Plain bus names (`"SFX"`) work too.

Every frame, each bus Chirp manages is recomputed as:
**base volume × VCAs × bus automation**, then **snapshots blended in by priority**.
A bus becomes managed when [set_bus_volume()](#method-set_bus_volume), a VCA, a bus automation or
a snapshot first touches it; its volume at that moment becomes its base. Effect properties work
the same way, starting from the value they had when first touched. Buses Chirp never touches are
left alone.

## Tutorials

- [Mixing](../../README.md#mixing)

## Methods

| Return | Signature |
|---|---|
| Array[[ChirpSnapshotInstance](ChirpSnapshotInstance.md)] | [get_active_snapshots](#method-get_active_snapshots)() |
| float | [get_bus_volume](#method-get_bus_volume)(bus_path: String) |
| float | [get_vca_volume](#method-get_vca_volume)(vca_name: String) |
| bool | [is_live](#method-is_live)() |
| void | [mute_all](#method-mute_all)(mute: bool) |
| void | [pause_all](#method-pause_all)(paused: bool) |
| StringName | [resolve_bus](#method-resolve_bus)(bus_path: String) |
| void | [set_bus_mute](#method-set_bus_mute)(bus_path: String, mute: bool) |
| void | [set_bus_paused](#method-set_bus_paused)(bus_path: String, paused: bool) |
| void | [set_bus_volume](#method-set_bus_volume)(bus_path: String, volume: float) |
| void | [set_live](#method-set_live)(live: bool) |
| void | [set_vca_volume](#method-set_vca_volume)(vca_name: String, volume: float) |
| [ChirpSnapshotInstance](ChirpSnapshotInstance.md) | [start_snapshot](#method-start_snapshot)(snapshot_or_name: Variant) |
| void | [stop_all_snapshots](#method-stop_all_snapshots)(allow_fadeout: bool = true) |
| void | [stop_bus_events](#method-stop_bus_events)(bus_path: String, allow_fadeout: bool = true) |

## Constants

- **BUS_PREFIX** = `"bus:/"`

## Method Descriptions

<a id="method-get_active_snapshots"></a>
### Array[[ChirpSnapshotInstance](ChirpSnapshotInstance.md)] get_active_snapshots()

Snapshots that are playing or fading out, in the order they started.

---

<a id="method-get_bus_volume"></a>
### float get_bus_volume(bus_path: String)

Linear volume set with [set_bus_volume()](#method-set_bus_volume), not counting VCAs, automation
or snapshots. For a bus Chirp doesn't manage, the AudioServer's current volume.

---

<a id="method-get_vca_volume"></a>
### float get_vca_volume(vca_name: String)

Linear volume of a VCA. `1.0` for unknown VCAs.

---

<a id="method-is_live"></a>
### bool is_live()

`false` while the mixer is idle (see [set_live()](#method-set_live)). Always `true` in a game.

---

<a id="method-mute_all"></a>
### void mute_all(mute: bool)

Mutes or unmutes the Master bus.

---

<a id="method-pause_all"></a>
### void pause_all(paused: bool)

Pauses or resumes every event, e.g. while an ad is showing. Paused events keep their place: their
players are paused, and their timelines, envelopes, delays and LFOs stop advancing.

---

<a id="method-resolve_bus"></a>
### StringName resolve_bus(bus_path: String)

The Godot bus name for a bus path: `"bus:/SFX/UI"` → `&"UI"`. Empty paths and `"bus:/"` give
`&"Master"`; unknown buses also give `&"Master"`, with a warning.

---

<a id="method-set_bus_mute"></a>
### void set_bus_mute(bus_path: String, mute: bool)

Mutes or unmutes a bus on the AudioServer.

---

<a id="method-set_bus_paused"></a>
### void set_bus_paused(bus_path: String, paused: bool)

Pauses every event routed into this bus or any bus that sends into it, e.g. pausing `"bus:/SFX"`
also pauses events on a `UI` bus that sends to `SFX`. Events resume where they were.

```gdscript
func _on_pause_menu_opened() -> void:
	Chirp.mixer.set_bus_paused("bus:/SFX", true)
	Chirp.mixer.start_snapshot("Paused")
```

---

<a id="method-set_bus_volume"></a>
### void set_bus_volume(bus_path: String, volume: float)

Sets a bus's base volume (linear; `0.0` is -80 dB). VCAs, bus automation and snapshots apply on
top of it.

---

<a id="method-set_live"></a>
### void set_live(live: bool)

While not live, the mixer computes and writes nothing. Going idle restores every managed bus volume,
effect property and effect switch to its base; going live re-reads their current values as the
new base. Used by the editor preview so the project's bus layout is only touched while something
is being auditioned.

**Note:** go idle only when no snapshot is active: snapshots still active when the mixer goes live
again stop affecting their buses.

---

<a id="method-set_vca_volume"></a>
### void set_vca_volume(vca_name: String, volume: float)

Sets the linear volume of a [ChirpVCA](ChirpVCA.md) from the config, scaling every bus it covers.
Reports an error for unknown VCAs.

```gdscript
func _on_music_slider_changed(value: float) -> void:
	Chirp.mixer.set_vca_volume("Music", value)
```

---

<a id="method-start_snapshot"></a>
### [ChirpSnapshotInstance](ChirpSnapshotInstance.md) start_snapshot(snapshot_or_name: Variant)

Starts a snapshot, by name (from [ChirpConfig.snapshots](ChirpConfig.md#property-snapshots)) or as a
[ChirpSnapshot](ChirpSnapshot.md) resource. Starting the same snapshot twice gives two independent
instances. Returns `null` and reports an error if the name is unknown.

---

<a id="method-stop_all_snapshots"></a>
### void stop_all_snapshots(allow_fadeout: bool = true)

Stops every active snapshot. With `allow_fadeout`, each plays its envelope's release first.

---

<a id="method-stop_bus_events"></a>
### void stop_bus_events(bus_path: String, allow_fadeout: bool = true)

Stops every event routed into this bus or any bus that sends into it.
