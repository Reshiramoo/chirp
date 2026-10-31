@tool
extends EditorDebuggerPlugin
## Debugger → Chirp: what Chirp is doing in the running game (instances, voices, buses,
## snapshots, global parameters), from the stats the game's Chirp sends a few times a second.

const ProfilerView := preload("profiler_view.gd")
const MESSAGE := "chirp:stats"

var _views := {} # session id -> ProfilerView


func _has_capture(capture: String) -> bool:
	return capture == "chirp"


func _capture(message: String, data: Array, session_id: int) -> bool:
	if message != MESSAGE or data.is_empty() or not _views.has(session_id):
		return false
	_views[session_id].show_stats(data[0])
	return true


func _setup_session(session_id: int) -> void:
	var view := ProfilerView.new()
	view.name = "Chirp"
	_views[session_id] = view
	var session := get_session(session_id)
	session.started.connect(view.clear)
	session.add_session_tab(view)
