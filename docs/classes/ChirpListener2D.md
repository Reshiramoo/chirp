# ChirpListener2D

**Inherits:** [Node2D](https://docs.godotengine.org/en/stable/classes/class_node2d.html)

Where Chirp listens from in 2D.

## Description

Chirp measures distances and directions from a listener: for [roll-off](ChirpEvent.md#property-rolloff),
[built-in parameters](ChirpParameter.md#enum-builtin) and `FURTHEST` [voice stealing](ChirpEvent.md#enum-stealing).
Without a ChirpListener2D, that's the current `AudioListener2D`, else the current camera, else the screen centre.

Add a ChirpListener2D where you hear from, usually on the camera. Set
[attenuation_object](#property-attenuation_object) to measure distance from another node while the
listener's own position and rotation keep deciding direction, e.g. a top-down game: the camera pans, the character sets distance
(FMOD's "attenuation object").

With [drive_audio_listener](#property-drive_audio_listener), the node also makes an `AudioListener2D` at its
position current, so Godot's panning matches.

Several listeners can exist; the most recently made current one is used. One listener at a time:
FMOD's weighted multiple listeners are not supported.

```gdscript
# Scene: Camera > ChirpListener2D, attenuation_object = ../../Player
```

## Tutorials

- [Listeners and roll-off](../../README.md#listeners-and-roll-off)

## Properties

| Type | Name | Default |
|---|---|---|
| NodePath | [attenuation_object](#property-attenuation_object) | `NodePath("")` |
| bool | [current](#property-current) | `true` |
| bool | [drive_audio_listener](#property-drive_audio_listener) | `true` |

## Methods

| Return | Signature |
|---|---|
| void | [clear_current](#method-clear_current)() |
| Vector2 | [get_attenuation_position](#method-get_attenuation_position)() |
| bool | [is_current](#method-is_current)() |
| void | [make_current](#method-make_current)() |

## Property Descriptions

<a id="property-attenuation_object"></a>
### NodePath attenuation_object = `NodePath("")`

A Node2D to measure distance from instead of this node. Direction, elevation and orientation still
use this node's rotation. Empty, or a path that doesn't resolve, = this node.

---

<a id="property-current"></a>
### bool current = `true`

Whether Chirp uses this listener. Setting it to `true` (or entering the tree with it on) makes
this the current listener, ahead of any other ChirpListener2D.

---

<a id="property-drive_audio_listener"></a>
### bool drive_audio_listener = `true`

While current, also make an internal `AudioListener2D` child current, so Godot pans sounds from here.
Turn it off to keep Godot's listener elsewhere (e.g. your own `AudioListener2D`); Chirp still measures
from this node.

## Method Descriptions

<a id="method-clear_current"></a>
### void clear_current()

Stops being the current listener. Chirp falls back to the previously current ChirpListener2D, else
the `AudioListener2D` or camera.

---

<a id="method-get_attenuation_position"></a>
### Vector2 get_attenuation_position()

The global position distance is measured from: the [attenuation_object](#property-attenuation_object)'s,
else this node's.

---

<a id="method-is_current"></a>
### bool is_current()

`true` while Chirp uses this listener.

---

<a id="method-make_current"></a>
### void make_current()

Makes this the current listener (same as setting [current](#property-current) to `true`).
