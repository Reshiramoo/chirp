# ChirpEvents

**Inherits:** [RefCounted](https://docs.godotengine.org/en/stable/classes/class_refcounted.html)

`Chirp.events`: finds events by path, creates and plays instances, enforces voice limits.

## Description

Not a global class: reach it through the autoload as `Chirp.events`.

Events are found in the directories of the `chirp/sound_directories` project setting. Each
directory's folder name starts the path, and its files become events:

```
res://assets/sounds/sfxs/coin.mp3        -> "event:/sfxs/coin"     (plain audio file)
res://assets/sounds/sfxs/ui/click.tres   -> "event:/sfxs/ui/click" (ChirpEvent resource)
```

A [ChirpEvent](ChirpEvent.md) resource wins over an audio file with the same name. Plain audio
files become a one-instrument event on their directory's bus.

Files load the first time their event is used, and then stay loaded. That first load can stall a
frame, on mobile especially; load events ahead of time with [preload_events()](#method-preload_events),
e.g. behind a loading screen, and free them with [unload_events()](#method-unload_events).

Every method that takes `event_or_path` accepts a [ChirpEvent](ChirpEvent.md) or an
`"event:/..."` path.

## Tutorials

- [Events and event paths](../../README.md#events-and-event-paths)

## Properties

| Type | Name | Default |
|---|---|---|
| Callable | [programmer_sound_provider](#property-programmer_sound_provider) | `Callable()` |

## Methods

| Return | Signature |
|---|---|
| [ChirpEventInstance](ChirpEventInstance.md) | [create_instance](#method-create_instance)(event_or_path: Variant) |
| Array[[ChirpEventInstance](ChirpEventInstance.md)] | [get_active_instances](#method-get_active_instances)(event_or_path: Variant = null) |
| [ChirpEvent](ChirpEvent.md) | [get_event](#method-get_event)(event_or_path: Variant) |
| float | [get_preload_progress](#method-get_preload_progress)() |
| String | [get_event_file](#method-get_event_file)(event_path: String) |
| PackedStringArray | [get_event_paths](#method-get_event_paths)() |
| bool | [is_event_loaded](#method-is_event_loaded)(event_path: String) |
| bool | [is_preloading](#method-is_preloading)() |
| [ChirpEventInstance](ChirpEventInstance.md) | [play_one_shot](#method-play_one_shot)(event_or_path: Variant, position: Variant = null) |
| [ChirpEventInstance](ChirpEventInstance.md) | [play_one_shot_attached](#method-play_one_shot_attached)(event_or_path: Variant, node: Node) |
| void | [preload_events](#method-preload_events)(targets: Variant = "event:/", threaded: bool = true) |
| void | [register_event](#method-register_event)(event_path: String, event: [ChirpEvent](ChirpEvent.md)) |
| void | [scan](#method-scan)(directories: Dictionary) |
| void | [stop_all](#method-stop_all)(allow_fadeout: bool = true) |
| PackedStringArray | [suggest_paths](#method-suggest_paths)(event_path: String) |
| void | [unload_events](#method-unload_events)(targets: Variant = "event:/") |

## Signals

<a id="signal-preload_finished"></a>
### preload_finished()

Emitted once no threaded preloads are pending any more. Always emitted on a later frame than the
[preload_events()](#method-preload_events) call (even when there was nothing to load), so it can be
awaited right after the call.

## Constants

- **EVENT_PREFIX** = `"event:/"`
- **AUDIO_EXTENSIONS** = `["wav", "ogg", "mp3"]`: audio files picked up by [scan()](#method-scan).
- **RESOURCE_EXTENSIONS** = `["tres", "res"]`: resource files picked up by [scan()](#method-scan).

## Property Descriptions

<a id="property-programmer_sound_provider"></a>
### Callable programmer_sound_provider = `Callable()`

Supplies sounds for PROGRAMMER instruments that their instance didn't get one for, e.g. a lookup of
localised dialogue by key. Called as `func(key: String, instance: ChirpEventInstance) -> AudioStream`;
return `null` for no sound. Works with [play_one_shot()](#method-play_one_shot), where there is no
chance to connect to the instance first.

```gdscript
Chirp.events.programmer_sound_provider = func(key: String, _instance: ChirpEventInstance) -> AudioStream:
	return load("res://voice/%s/%s.ogg" % [TranslationServer.get_locale(), key])
Chirp.play_one_shot("event:/voice/bark") # its programmer instrument's key picks the file
```

## Method Descriptions

<a id="method-create_instance"></a>
### [ChirpEventInstance](ChirpEventInstance.md) create_instance(event_or_path: Variant)

Creates a stopped instance of the event, routed to its bus: the event's own `bus`, else the bus
of the sound directory it was saved in, else Master. Call
[ChirpEventInstance.start()](ChirpEventInstance.md#method-start) to play it and
[release()](ChirpEventInstance.md#method-release) when you no longer need it.

Returns `null` (and reports an error) if the path is unknown.

```gdscript
var engine := Chirp.events.create_instance("event:/sfxs/engine")
engine.attach_to(car)
engine.start()
```

---

<a id="method-get_active_instances"></a>
### Array[[ChirpEventInstance](ChirpEventInstance.md)] get_active_instances(event_or_path: Variant = null)

Instances that are playing or stopping, in the order they started. Pass an event to get only
its instances.

---

<a id="method-get_event"></a>
### [ChirpEvent](ChirpEvent.md) get_event(event_or_path: Variant)

The event behind a path, loading it if needed. Given a ChirpEvent, returns it unchanged.
Returns `null` and reports an error for an unknown path. The error suggests known paths that end
the same way (see [suggest_paths()](#method-suggest_paths)), e.g. `"event:/audio/coin"` for
`"event:/coin"`.

---

<a id="method-get_event_file"></a>
### String get_event_file(event_path: String)

The file behind an event path (a ChirpEvent resource or an audio file). Returns `""` for
unknown paths and for events added with [register_event()](#method-register_event).

---

<a id="method-get_preload_progress"></a>
### float get_preload_progress()

Progress of the current threaded preloads, 0..1, for a loading bar. `1.0` when none are pending.

---

<a id="method-get_event_paths"></a>
### PackedStringArray get_event_paths()

Every known event path, from the sound directories and [register_event()](#method-register_event).

---

<a id="method-is_event_loaded"></a>
### bool is_event_loaded(event_path: String)

`true` when the event's file is loaded (or it was added with [register_event()](#method-register_event)).

---

<a id="method-is_preloading"></a>
### bool is_preloading()

`true` while threaded preloads are pending.

---

<a id="method-play_one_shot"></a>
### [ChirpEventInstance](ChirpEventInstance.md) play_one_shot(event_or_path: Variant, position: Variant = null)

Fire-and-forget: creates, starts and releases an instance. `position` may be `null`
(non-spatial), a `Vector2` (2D) or a `Vector3` (3D).

The returned instance is already released: it is destroyed once it stops. You can still use it
while it plays, e.g. to connect to its `stopped` signal.

---

<a id="method-play_one_shot_attached"></a>
### [ChirpEventInstance](ChirpEventInstance.md) play_one_shot_attached(event_or_path: Variant, node: Node)

Like [play_one_shot()](#method-play_one_shot), but the sound follows `node` (a Node2D or Node3D)
while it lives, and stays where the node was last seen if it is freed.

---

<a id="method-preload_events"></a>
### void preload_events(targets: Variant = "event:/", threaded: bool = true)

Loads events ahead of their first use, so playing them doesn't stall. `targets` is an
`"event:/..."` path, a folder of them (`"event:/sfxs"` covers everything under it, matching whole
path segments), or an Array of either; the default is every event. Events already loaded are
skipped, and unknown targets are reported once.

With `threaded`, the files load on Godot's background loader threads: watch
[get_preload_progress()](#method-get_preload_progress) and wait for [preload_finished](#signal-preload_finished).
Without it, they load before the call returns. Using an event while it is still loading in the
background just loads it right away.

```gdscript
func _on_level_loading() -> void:
	Chirp.events.preload_events(["event:/sfxs", "event:/bgms/level_2"])
	while Chirp.events.is_preloading():
		$LoadingBar.value = Chirp.events.get_preload_progress()
		await get_tree().process_frame
	start_level()
```

---

<a id="method-register_event"></a>
### void register_event(event_path: String, event: [ChirpEvent](ChirpEvent.md))

Makes `event` addressable as `event_path`, e.g. for events built in code. Replaces any event
already at that path until the next [scan()](#method-scan).

```gdscript
var beep := ChirpEvent.new()
var instrument := ChirpInstrument.new()
instrument.streams.append(preload("res://beep.wav"))
beep.instruments.append(instrument)
Chirp.events.register_event("event:/code/beep", beep)
```

---

<a id="method-scan"></a>
### void scan(directories: Dictionary)

Rebuilds the path registry from `{directory: bus path}`; use `""` as the bus for Master.
Clears events added with [register_event()](#method-register_event).
[Chirp.reload_settings()](Chirp.md#method-reload_settings) calls this with the
`chirp/sound_directories` project setting. Directories that don't exist are skipped with a warning.

---

<a id="method-stop_all"></a>
### void stop_all(allow_fadeout: bool = true)

Stops every active instance. With `allow_fadeout`, each plays its envelope's release first.

---

<a id="method-suggest_paths"></a>
### PackedStringArray suggest_paths(event_path: String)

Known paths ending with the same path segments as `event_path` (case-insensitive), sorted. Useful
when a path is missing its sound directory's folder name or its `event:/` prefix:

```gdscript
Chirp.events.suggest_paths("event:/coin")  # ["event:/audio/coin"] with the default res://audio
```

---

<a id="method-unload_events"></a>
### void unload_events(targets: Variant = "event:/")

Lets Godot free events' files: Chirp drops its references to them, so they are freed once nothing
else uses them (instances still playing keep theirs, and so do emitters with an `event` resource
assigned). The next use loads them again. Same `targets` as [preload_events()](#method-preload_events).
Events added with [register_event()](#method-register_event) are kept, since there's no file to
reload them from.
