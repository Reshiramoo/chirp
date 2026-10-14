class_name ChirpSnapshotInstance
extends RefCounted
## One active snapshot. Create with Chirp.mixer.start_snapshot().

signal stopped

enum State { STOPPED, PLAYING, STOPPING }

## How strongly the snapshot applies, 0..1. Multiplied with its envelope and intensity parameter.
var intensity := 1.0

var _snapshot: ChirpSnapshot
var _chirp: Node # the Chirp autoload
var _state := State.STOPPED
var _time := 0.0
var _release_time := 0.0
var _release_from := 0.0
var _env_level := 1.0
var _order := 0


func _init(chirp: Node, snapshot: ChirpSnapshot) -> void:
	_chirp = chirp
	_snapshot = snapshot


func get_snapshot() -> ChirpSnapshot:
	return _snapshot


func get_state() -> State:
	return _state


func is_playing() -> bool:
	return _state != State.STOPPED


## The weight the mixer applies right now, 0..1.
func get_level() -> float:
	if _state == State.STOPPED:
		return 0.0
	return clampf(_env_level * intensity * _parameter_factor(), 0.0, 1.0)


## Stops the snapshot. With [param allow_fadeout] its envelope's release is played first.
func stop(allow_fadeout := true) -> void:
	if _state == State.STOPPED:
		return
	var release := _snapshot.envelope.release if _snapshot.envelope else 0.0
	if allow_fadeout and release > 0.0:
		if _state == State.PLAYING:
			_state = State.STOPPING
			_release_time = 0.0
			_release_from = _env_level
		return
	_finish()


# --- driven by Chirp.mixer ------------------------------------------------------

func _start(order: int) -> void:
	_order = order
	_time = 0.0
	_env_level = _snapshot.envelope.level_at(0.0) if _snapshot.envelope else 1.0
	_state = State.PLAYING


func _process(delta: float) -> void:
	_time += delta
	if _state == State.STOPPING:
		_release_time += delta
		_env_level = _release_from * (1.0 - _release_time / _snapshot.envelope.release)
		if _env_level <= 0.0:
			_finish()
	elif _snapshot.envelope:
		_env_level = _snapshot.envelope.level_at(_time)


func _parameter_factor() -> float:
	if _snapshot.intensity_parameter.is_empty():
		return 1.0
	var state: ChirpParameter.State = _chirp.parameters._get_state(_snapshot.intensity_parameter)
	if state == null:
		return 1.0
	var lo := state.def.get_min()
	var hi := state.def.get_max()
	return 0.0 if hi <= lo else (state.value - lo) / (hi - lo)


func _finish() -> void:
	_env_level = 0.0
	_state = State.STOPPED
	_chirp.mixer._snapshot_stopped(self)
	stopped.emit()
