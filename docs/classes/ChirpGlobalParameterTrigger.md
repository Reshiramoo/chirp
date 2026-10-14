# ChirpGlobalParameterTrigger

**Inherits:** [Node](https://docs.godotengine.org/en/stable/classes/class_node.html)

Sets global parameters when a trigger fires.

## Description

The equivalent of FMOD for Unity's Global Parameter Trigger. When [trigger_on](#property-trigger_on)
fires (or [trigger()](#method-trigger) is called), it sets each global parameter in
[parameters](#property-parameters) with [Chirp.parameters.set_value()](ChirpParameters.md#method-set_value),
and each one in [labels](#property-labels) with [set_label()](ChirpParameters.md#method-set_label).

It uses the same triggers as the emitters (see [Trigger](ChirpEmitter2D.md#enum-trigger)), with the
trigger source defaulting to the parent. With no visibility of its own, SHOWN and HIDDEN follow
the trigger source's visibility.

```gdscript
# Raise the tension while the player is in the boss arena:
# Area2D "Arena"
#   ├ ChirpGlobalParameterTrigger  trigger_on = ENTERED, trigger_group = "player", parameters = {"Danger": 1.0}
#   └ ChirpGlobalParameterTrigger  trigger_on = EXITED,  trigger_group = "player", parameters = {"Danger": 0.0}
```

## Tutorials

- [Parameter triggers](../../README.md#parameter-triggers)

## Properties

| Type | Name | Default |
|---|---|---|
| Dictionary[String, String] | [labels](#property-labels) | `{}` |
| Dictionary[String, float] | [parameters](#property-parameters) | `{}` |
| StringName | [trigger_group](#property-trigger_group) | `&""` |
| [Trigger](ChirpEmitter2D.md#enum-trigger) | [trigger_on](#property-trigger_on) | `NONE` |
| bool | [trigger_once](#property-trigger_once) | `false` |
| NodePath | [trigger_source](#property-trigger_source) | `NodePath("")` |

## Methods

| Return | Signature |
|---|---|
| void | [trigger](#method-trigger)() |

## Property Descriptions

<a id="property-labels"></a>
### Dictionary[String, String] labels = `{}`

Labeled global parameters to set by label, e.g. `{"Weather": "Rain"}`.

---

<a id="property-parameters"></a>
### Dictionary[String, float] parameters = `{}`

Global parameter values to set, e.g. `{"Danger": 1.0}`.

---

<a id="property-trigger_group"></a>
### StringName trigger_group = `&""`

ENTERED / EXITED: only bodies and areas in this group fire. Empty = any.

---

<a id="property-trigger_on"></a>
### [Trigger](ChirpEmitter2D.md#enum-trigger) trigger_on = `NONE`

When to apply the values. `NONE`: only through [trigger()](#method-trigger). Set before the node
enters the tree.

---

<a id="property-trigger_once"></a>
### bool trigger_once = `false`

Only the first trigger applies.

---

<a id="property-trigger_source"></a>
### NodePath trigger_source = `NodePath("")`

The node whose signals drive ENTERED, EXITED, MOUSE_*, SHOWN and HIDDEN. Empty = the parent.

## Method Descriptions

<a id="method-trigger"></a>
### void trigger()

Applies the values now (unless [trigger_once](#property-trigger_once) already fired).
