@tool
@icon("res://addons/chirp/icons/snapshot.svg")
class_name ChirpSnapshot
extends Resource
## A saved mixer state that is blended in while active, e.g. "Paused" muffling the
## game and ducking the music. Start with Chirp.mixer.start_snapshot("Paused").

@export var name := ""
@export var bus_overrides: Array[ChirpBusOverride] = []
## Higher priority is applied later, so it wins where snapshots overlap.
@export var priority := 0
## Fades the snapshot in (attack) and out when stopped (release).
@export var envelope: ChirpEnvelope
## Global parameter that drives the snapshot's intensity (its range maps to 0..1). Empty = none.
@export var intensity_parameter := ""
