@tool
@icon("res://addons/chirp/icons/lfo.svg")
class_name ChirpLFO
extends Resource
## Low-frequency oscillator that modulates an event's volume or pitch over time,
## independent of parameters (tremolo, vibrato, wobbling engines).

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
@export_range(0.01, 50.0, 0.01, "or_greater", "suffix:Hz") var rate := 1.0
## VOLUME: share of the volume removed at the wave's lowest point (0..1).
## PITCH: semitones up and down from the base pitch.
@export_range(0.0, 24.0, 0.01) var depth := 0.5
## Starting point in the cycle (0..1).
@export_range(0.0, 1.0, 0.01) var phase := 0.0


## Multiplier for the target property [param time] seconds after the event started.
## [param seed] keeps RANDOM different between instances.
func factor(time: float, seed: int) -> float:
	var wave := sample(time, seed)
	if target == Target.PITCH:
		return pow(2.0, depth * wave / 12.0)
	return 1.0 - clampf(depth, 0.0, 1.0) * (1.0 - wave) * 0.5


## The raw wave, -1..1.
func sample(time: float, seed: int) -> float:
	var cycle := time * rate + phase
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
