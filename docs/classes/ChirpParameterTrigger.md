# ChirpParameterTrigger

**Inherits:** [Node](https://docs.godotengine.org/en/stable/classes/class_node.html)

Sets parameters on emitters when a trigger fires.

## Description

The equivalent of FMOD for Unity's Studio Parameter Trigger. When [trigger_on](#property-trigger_on)
fires (or [trigger()](#method-trigger) is called), every parameter in [parameters](#property-parameters)
is set on each of the [targets](#property-targets) through
[ChirpEmitter2D.set_parameter()](ChirpEmitter2D.md#method-set_parameter): playing instances
change right away, and the emitter keeps the values for instances it starts later.

It uses the same triggers as the emitters (see [Trigger](ChirpEmitter2D.md#enum-trigger)), with the
trigger source defaulting to the parent. With no visibility of its own, SHOWN and HIDDEN follow
the trigger source's visibility.

```gdscript
# Music switches to its cave section when the player walks in:
# Area3D "CaveEntrance"
#   └ ChirpParameterTrigger  trigger_on = ENTERED, trigger_group = "player",
#                            targets = [../../Music], parameters = {"Area": 2.0}
```

## Tutorials

- [Parameter triggers](../../README.md#parameter-triggers)

## Properties

| Type | Name | Default |
|---|---|---|
| Dictionary[String, float] | [parameters](#property-parameters) | `{}` |
| Array[NodePath] | [targets](#property-targets) | `[]` |
| StringName | [trigger_group](#property-trigger_group) | `&""` |
| [Trigger](ChirpEmitter2D.md#enum-trigger) | [trigger_on](#property-trigger_on) | `NONE` |
| bool | [trigger_once](#property-trigger_once) | `false` |
| NodePath | [trigger_source](#property-trigger_source) | `NodePath("")` |

## Methods

| Return | Signature |
|---|---|
| Array[Node] | [get_targets](#method-get_targets)() |
| void | [trigger](#method-trigger)() |

## Property Descriptions

<a id="property-parameters"></a>
### Dictionary[String, float] parameters = `{}`

Local parameter values to set, e.g. `{"Area": 2.0}`. For labeled parameters, use the label's
index.

---

<a id="property-targets"></a>
### Array[NodePath] targets = `[]`

The [ChirpEmitter2D](ChirpEmitter2D.md) / [ChirpEmitter3D](ChirpEmitter3D.md) nodes to set. Empty
= the parent. Paths that don't lead to an emitter are skipped with a warning.

---

<a id="property-trigger_group"></a>
### StringName trigger_group = `&""`

ENTERED / EXITED: only bodies and areas in this group fire. Empty = any.

---

<a id="property-trigger_on"></a>
### [Trigger](ChirpEmitter2D.md#enum-trigger) trigger_on = `NONE`

When to apply the parameters. `NONE`: only through [trigger()](#method-trigger). Set before the
node enters the tree.

---

<a id="property-trigger_once"></a>
### bool trigger_once = `false`

Only the first trigger applies.

---

<a id="property-trigger_source"></a>
### NodePath trigger_source = `NodePath("")`

The node whose signals drive ENTERED, EXITED, MOUSE_*, SHOWN and HIDDEN. Empty = the parent.

## Method Descriptions

<a id="method-get_targets"></a>
### Array[Node] get_targets()

The emitters [targets](#property-targets) resolves to (the parent when empty).

---

<a id="method-trigger"></a>
### void trigger()

Applies the parameters to every target now (unless [trigger_once](#property-trigger_once) already
fired).
