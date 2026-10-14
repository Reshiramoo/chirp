# ChirpParameters

**Inherits:** [RefCounted](https://docs.godotengine.org/en/stable/classes/class_refcounted.html)

`Chirp.parameters`: global parameters, shared by every event and the mixer.

## Description

Not a global class: reach it through the autoload as `Chirp.parameters`.

Global parameters are [ChirpParameter](ChirpParameter.md)s listed in
[ChirpConfig.global_parameters](ChirpConfig.md#property-global_parameters). Event automations read
them when their `global` flag is set; event conditions, snapshots' `intensity_parameter` and
[ChirpBusAutomation](ChirpBusAutomation.md) read them too. Names are case-insensitive.

Values are clamped to the parameter's range (and rounded for discrete and labeled parameters).
With a `seek_speed`, the value glides toward a newly set target.

```gdscript
Chirp.parameters.set_value("Danger", 0.8)
Chirp.parameters.set_label("Weather", "Rain")
```

## Tutorials

- [Parameters](../../README.md#parameters)

## Methods

| Return | Signature |
|---|---|
| float | [get_value](#method-get_value)(parameter_name: String) |
| void | [set_label](#method-set_label)(parameter_name: String, label: String) |
| void | [set_value](#method-set_value)(parameter_name: String, value: float) |

## Method Descriptions

<a id="method-get_value"></a>
### float get_value(parameter_name: String)

The current value (which may still be gliding toward its target). `0.0` for unknown parameters.

---

<a id="method-set_label"></a>
### void set_label(parameter_name: String, label: String)

Sets a labeled parameter by label (case-insensitive). Unknown labels are ignored with a warning.

---

<a id="method-set_value"></a>
### void set_value(parameter_name: String, value: float)

Sets the target value. Unknown parameters are ignored with a warning (once per name).
