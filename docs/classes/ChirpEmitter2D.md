# ChirpEmitter2D

**Inherits:** [Node2D](https://docs.godotengine.org/en/stable/classes/class_node2d.html)

Plays a [ChirpEvent](ChirpEvent.md) at this node's position, following it as it moves.

## Description

A drop-in replacement for an `AudioStreamPlayer2D` that plays Chirp events. Assign an
[event](#property-event) (or an [event_path](#property-event_path)), then either call
[play()](#method-play) / [stop()](#method-stop) from script or pick triggers with
[play_on](#property-play_on) and [stop_on](#property-stop_on).

One-shot events (see [ChirpEvent.is_one_shot()](ChirpEvent.md#method-is_one_shot)) start a new
instance on every [play()](#method-play), so rapid triggers overlap. Looping events restart instead
of stacking. When the emitter leaves the tree, its looping instances stop (with fade-out if
[allow_fadeout](#property-allow_fadeout)); one-shots finish where they were.

The instance follows the emitter, so it plays as 2D audio.

```gdscript
# A coin that chimes when the player touches it.
# Scene: Area2D "Coin" > ChirpEmitter2D (play_on = ENTERED, trigger_group = "player")
```

## Tutorials

- [Emitter nodes](../../README.md#emitter-nodes)

## Properties

| Type | Name | Default |
|---|---|---|
| bool | [allow_fadeout](#property-allow_fadeout) | `true` |
| float | [attenuation](#property-attenuation) | `1.0` |
| [ChirpEvent](ChirpEvent.md) | [event](#property-event) | `null` |
| String | [event_path](#property-event_path) | `""` |
| float | [max_distance](#property-max_distance) | `2000.0` |
| bool | [override_attenuation](#property-override_attenuation) | `false` |
| Dictionary[String, float] | [parameters](#property-parameters) | `{}` |
| [Trigger](#enum-trigger) | [play_on](#property-play_on) | `NONE` |
| [Trigger](#enum-trigger) | [stop_on](#property-stop_on) | `NONE` |
| StringName | [trigger_group](#property-trigger_group) | `&""` |
| bool | [trigger_once](#property-trigger_once) | `false` |
| NodePath | [trigger_source](#property-trigger_source) | `NodePath("")` |

## Methods

| Return | Signature |
|---|---|
| bool | [is_playing](#method-is_playing)() |
| void | [play](#method-play)() |
| void | [set_parameter](#method-set_parameter)(parameter_name: String, value: float) |
| void | [stop](#method-stop)() |

## Enumerations

<a id="enum-trigger"></a>
### enum ChirpEmitterCore.Trigger

Shared by ChirpEmitter2D and ChirpEmitter3D; write it as `ChirpEmitterCore.Trigger.READY` in code.
The trigger source is [trigger_source](#property-trigger_source), or the emitter's parent.

- **NONE** = `0`: only through [play()](#method-play) / [stop()](#method-stop) from script.
- **READY** = `1`: when the emitter enters the scene (deferred to the end of the frame).
- **EXIT_TREE** = `2`: when the emitter leaves the scene, e.g. is freed.
- **SHOWN** = `3`: when the emitter becomes visible in the tree.
- **HIDDEN** = `4`: when the emitter becomes hidden.
- **ENTERED** = `5`: a body or area entered the trigger source, an `Area2D` (body or area) or a
  `RigidBody2D` (body contact; contact monitoring is switched on for you). Filtered by
  [trigger_group](#property-trigger_group).
- **EXITED** = `6`: a body or area left the trigger source. Same sources as ENTERED.
- **MOUSE_ENTERED** = `7`: the pointer entered the trigger source, a `CollisionObject2D` (made
  pickable for you) or a `Control`.
- **MOUSE_EXITED** = `8`: the pointer left the trigger source.
- **MOUSE_DOWN** = `9`: left mouse button (or touch) pressed on the trigger source.
- **MOUSE_UP** = `10`: left mouse button (or touch) released on the trigger source.

A trigger whose source has the wrong type is ignored with a warning.

## Property Descriptions

<a id="property-allow_fadeout"></a>
### bool allow_fadeout = `true`

Stopping plays the event's envelope release instead of cutting off.

---

<a id="property-attenuation"></a>
### float attenuation = `1.0`

With [override_attenuation](#property-override_attenuation): the distance attenuation curve
(an easing value, as `AudioStreamPlayer2D.attenuation`), instead of the event's `attenuation_2d`.

---

<a id="property-event"></a>
### [ChirpEvent](ChirpEvent.md) event = `null`

The event to play. Takes precedence over [event_path](#property-event_path).

---

<a id="property-event_path"></a>
### String event_path = `""`

Used when [event](#property-event) is empty: any `"event:/..."` path, including plain audio files
in the sound directories. The inspector offers a searchable picker.

---

<a id="property-max_distance"></a>
### float max_distance = `2000.0`

With [override_attenuation](#property-override_attenuation): distance beyond which the sound is
inaudible, instead of the event's `max_distance_2d`.

---

<a id="property-override_attenuation"></a>
### bool override_attenuation = `false`

Use this emitter's attenuation properties instead of the event's. The editor gizmo gets drag
handles while this is on.

---

<a id="property-parameters"></a>
### Dictionary[String, float] parameters = `{}`

Parameter values applied to each instance when it starts, e.g. `{"Size": 2.0}`.
[set_parameter()](#method-set_parameter) updates this too.

---

<a id="property-play_on"></a>
### [Trigger](#enum-trigger) play_on = `NONE`

When to call [play()](#method-play). See [Trigger](#enum-trigger). Set before the emitter enters
the tree.

---

<a id="property-stop_on"></a>
### [Trigger](#enum-trigger) stop_on = `NONE`

When to call [stop()](#method-stop). See [Trigger](#enum-trigger). Set before the emitter enters
the tree.

---

<a id="property-trigger_group"></a>
### StringName trigger_group = `&""`

ENTERED / EXITED: only bodies and areas in this group fire. Empty = any.

---

<a id="property-trigger_once"></a>
### bool trigger_once = `false`

Only the first [play()](#method-play) succeeds.

---

<a id="property-trigger_source"></a>
### NodePath trigger_source = `NodePath("")`

The node whose signals drive ENTERED, EXITED and the MOUSE_* triggers. Empty = the parent.

## Method Descriptions

<a id="method-is_playing"></a>
### bool is_playing()

`true` while any instance started by this emitter is playing or stopping.

---

<a id="method-play"></a>
### void play()

Plays the event: a new instance for a one-shot event, or a restart of the playing instance for a
looping one. Applies [parameters](#property-parameters) and the attenuation override. Does nothing
without an event, or after the first play with [trigger_once](#property-trigger_once).

---

<a id="method-set_parameter"></a>
### void set_parameter(parameter_name: String, value: float)

Sets a local parameter on every playing instance, and stores it in
[parameters](#property-parameters) for future ones.

---

<a id="method-stop"></a>
### void stop()

Stops the most recently started instance that is still playing, with fade-out if
[allow_fadeout](#property-allow_fadeout).
