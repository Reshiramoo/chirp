@tool
@icon("res://addons/chirp/icons/lfo.svg")
class_name ChirpLFO
extends Resource
## Low-frequency oscillator that modulates an event's volume or pitch over time,
## independent of parameters (tremolo, vibrato, wobbling engines). With tempo_sync, its cycle
## follows the beats of a TIMELINE event's TEMPO markers instead of a rate in Hz.

enum Target { VOLUME, PITCH }

enum Shape {
	SINE,
	TRIANGLE,
	SQUARE,
	SAW_UP,
	SAW_DOWN,
	RANDOM, ## A new random level every cycle (sample and hold).
}

@export var target := Target.VOLUME
@export var shape := Shape.SINE
## Cycles per second, without tempo_sync.
@export_range(0.01, 50.0, 0.01, "or_greater", "suffix:Hz") var rate := 1.0
## Lock the cycle to the beat: on TIMELINE events, to the beat grid of the current TEMPO marker
## (aligned with timeline_beat); elsewhere at 120 BPM from the start.
@export var tempo_sync := false:
	set(value):
		tempo_sync = value
		notify_property_list_changed()
## With tempo_sync: beats per cycle. 1 = one cycle per beat, 0.5 = eighth notes, 4 = a 4/4 bar.
@export_range(0.0625, 64.0, 0.0625, "or_greater") var beats_per_cycle := 1.0
## VOLUME: share of the volume removed at the wave's lowest point (0..1).
## PITCH: semitones up and down from the base pitch.
@export_range(0.0, 24.0, 0.01) var depth := 0.5
## Starting point in the cycle (0..1).
@export_range(0.0, 1.0, 0.01) var phase := 0.0


## Multiplier for the target property [param time] seconds after the event started.
## [param seed] keeps RANDOM different between instances.
func factor(time: float, seed: int) -> float:
	return factor_at_cycle(time * rate, seed)


## Multiplier with tempo_sync, [param beats] beats into the beat grid.
func factor_at_beat(beats: float, seed: int) -> float:
	return factor_at_cycle(beats / maxf(beats_per_cycle, 0.0001), seed)


## Multiplier at [param cycle] cycles in (before [member phase] is added).
func factor_at_cycle(cycle: float, seed: int) -> float:
	var wave := sample_at_cycle(cycle, seed)
	if target == Target.PITCH:
		return pow(2.0, depth * wave / 12.0)
	return 1.0 - clampf(depth, 0.0, 1.0) * (1.0 - wave) * 0.5


## The raw wave, -1..1, [param time] seconds in at [member rate].
func sample(time: float, seed: int) -> float:
	return sample_at_cycle(time * rate, seed)


## The raw wave, -1..1, [param cycle] cycles in (before [member phase] is added).
func sample_at_cycle(cycle: float, seed: int) -> float:
	cycle += phase
	var t := cycle - floorf(cycle)
	match shape:
		Shape.TRIANGLE:
			return 1.0 - 4.0 * absf(t - 0.5)
		Shape.SQUARE:
			return 1.0 if t < 0.5 else -1.0
		Shape.SAW_UP:
			return 2.0 * t - 1.0
		Shape.SAW_DOWN:
			return 1.0 - 2.0 * t
		Shape.RANDOM:
			return float(hash(Vector2i(int(floorf(cycle)), seed)) % 20001) / 10000.0 - 1.0
	return sin(t * TAU)


func _validate_property(property: Dictionary) -> void:
	if property.name == "rate" and tempo_sync or property.name == "beats_per_cycle" and not tempo_sync:
		property.usage = PROPERTY_USAGE_NO_EDITOR
