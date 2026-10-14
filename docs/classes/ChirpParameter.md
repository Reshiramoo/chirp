# ChirpParameter

**Inherits:** [Resource](https://docs.godotengine.org/en/stable/classes/class_resource.html)

A named value that drives an event (local) or the whole mix (global).

## Description

Mirrors FMOD Studio's continuous, discrete and labeled parameters. Add it to
[ChirpEvent.parameters](ChirpEvent.md#property-parameters) for a local parameter, set per instance
with [ChirpEventInstance.set_parameter()](ChirpEventInstance.md#method-set_parameter), or to
[ChirpConfig.global_parameters](ChirpConfig.md#property-global_parameters) for a global one, set
with [Chirp.parameters.set_value()](ChirpParameters.md#method-set_value).

Parameters drive [ChirpAutomation](ChirpAutomation.md) and
[ChirpBusAutomation](ChirpBusAutomation.md) curves, instrument and marker conditions, and snapshot
intensity. A [built_in](#property-built_in) parameter is set by Chirp every frame from the event's
position relative to the listener.

```gdscript
var rpm := ChirpParameter.new()
rpm.name = "RPM"
rpm.max_value = 8000.0
rpm.seek_speed = 4000.0 # glide 4000 RPM per second
```

## Tutorials

- [Parameters](../../README.md#parameters)

## Properties

| Type | Name | Default |
|---|---|---|
| [BuiltIn](#enum-builtin) | [built_in](#property-built_in) | `NONE` |
| float | [default_value](#property-default_value) | `0.0` |
| [Kind](#enum-kind) | [kind](#property-kind) | `CONTINUOUS` |
| PackedStringArray | [labels](#property-labels) | `[]` |
| float | [max_value](#property-max_value) | `1.0` |
| float | [min_value](#property-min_value) | `0.0` |
| String | [name](#property-name) | `""` |
| float | [seek_speed](#property-seek_speed) | `0.0` |

## Methods

| Return | Signature |
|---|---|
| float | [clamp_value](#method-clamp_value)(value: float) |
| float | [get_max](#method-get_max)() |
| float | [get_min](#method-get_min)() |
| float | [label_to_value](#method-label_to_value)(label: String) |

## Enumerations

<a id="enum-kind"></a>
### enum Kind

- **CONTINUOUS** = `0`: any value between [min_value](#property-min_value) and [max_value](#property-max_value).
- **DISCRETE** = `1`: whole numbers between min_value and max_value.
- **LABELED** = `2`: one of the [labels](#property-labels); the value is the label's index.

---

<a id="enum-builtin"></a>
### enum BuiltIn

Built-in parameters are set every frame from the event's position relative to the listener (the
current [ChirpListener2D](ChirpListener2D.md)/[3D](ChirpListener3D.md), else `AudioListener2D/3D`,
else the current camera). Game code can't set them. Angles are in
degrees. They need a positioned instance (see
[ChirpEventInstance.set_position()](ChirpEventInstance.md#method-set_position)); otherwise they stay
at their default.

- **NONE** = `0`: a normal parameter, set by game code.
- **DISTANCE** = `1`: distance to the listener. Set [max_value](#property-max_value) to the distance you care about.
- **DISTANCE_NORMALIZED** = `2`: 0 at the event's min distance, 1 at its max distance (with a Chirp
  roll-off: `min_distance` to `max_distance`; otherwise 2D: 0 to `max_distance_2d`, 3D:
  `unit_size_3d` to `max_distance_3d`). Range 0..1.
- **DIRECTION** = `3`: where the event is around the listener: 0 ahead, 90 right, -90 left, ±180
  behind. In 2D "ahead" is up. Range -180..180.
- **ELEVATION** = `4`: angle above (+) or below (-) the listener's horizontal plane. Always 0 in 2D.
  Range -90..90.
- **EVENT_CONE_ANGLE** = `5`: angle between where the emitter faces (+X in 2D, -Z in 3D) and the
  listener: 0 facing it, 180 facing away. Range 0..180.
- **EVENT_ORIENTATION** = `6`: like EVENT_CONE_ANGLE but signed: + when the listener is to the
  emitter's right. Range -180..180.
- **SPEED** = `7`: speed of the event relative to the listener. Set max_value as needed.
- **SPEED_ABSOLUTE** = `8`: speed of the event itself. Set max_value as needed.

The angle-based built-ins and DISTANCE_NORMALIZED use the fixed ranges above, ignoring
min_value and max_value.

## Property Descriptions

<a id="property-built_in"></a>
### [BuiltIn](#enum-builtin) built_in = `NONE`

Makes this a built-in parameter. Only meaningful for local parameters.

---

<a id="property-default_value"></a>
### float default_value = `0.0`

The value a new instance (or, for globals, a newly applied config) starts with.

---

<a id="property-kind"></a>
### [Kind](#enum-kind) kind = `CONTINUOUS`

See [Kind](#enum-kind).

---

<a id="property-labels"></a>
### PackedStringArray labels = `[]`

LABELED: the labels, in order. The value is the index of the label, from 0 to `labels.size() - 1`.

---

<a id="property-max_value"></a>
### float max_value = `1.0`

Highest value (not used by LABELED).

---

<a id="property-min_value"></a>
### float min_value = `0.0`

Lowest value (not used by LABELED, whose range starts at 0).

---

<a id="property-name"></a>
### String name = `""`

The name used to set and find the parameter. Case-insensitive.

---

<a id="property-seek_speed"></a>
### float seek_speed = `0.0`

Units per second the value glides toward a newly set target. `0` = jump instantly. A stopped
instance's parameters always jump.

## Method Descriptions

<a id="method-clamp_value"></a>
### float clamp_value(value: float)

`value` clamped to the range, and rounded for DISCRETE and LABELED parameters.

---

<a id="method-get_max"></a>
### float get_max()

The highest value: the built-in's fixed maximum, `labels.size() - 1` for LABELED, else
[max_value](#property-max_value).

---

<a id="method-get_min"></a>
### float get_min()

The lowest value: the built-in's fixed minimum, `0` for LABELED, else [min_value](#property-min_value).

---

<a id="method-label_to_value"></a>
### float label_to_value(label: String)

The value of `label` (case-insensitive), or `-1.0` if there is no such label.
