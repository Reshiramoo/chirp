@tool
extends VBoxContainer
## The Chirp profiler tab: a summary line, the playing instances, bus meters, active snapshots
## and global parameters. Fed by show_stats() with Chirp.get_stats() from the game.

const HISTORY := 120 # voice-count samples kept for the graph (30 s at 4 per second)

var _summary: Label
var _instances: Tree
var _meters: Control
var _side: Tree
var _history: PackedInt32Array = []
var _buses: Array = []


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_summary = Label.new()
	_summary.text = "Run the project to see what Chirp is doing."
	add_child(_summary)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	_instances = Tree.new()
	_instances.columns = 7
	_instances.column_titles_visible = true
	_instances.hide_root = true
	_instances.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_instances.size_flags_stretch_ratio = 2.0
	for column in 7:
		_instances.set_column_title(column, ["Event", "State", "Voices", "Bus", "Position", "Level", ""][column])
		_instances.set_column_expand(column, column == 0)
	split.add_child(_instances)
	var right := VSplitContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	_meters = Control.new()
	_meters.custom_minimum_size = Vector2(220, 120)
	_meters.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_meters.draw.connect(_draw_meters)
	right.add_child(_meters)
	_side = Tree.new()
	_side.columns = 2
	_side.hide_root = true
	_side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_side)


func clear() -> void:
	_history.clear()
	_buses.clear()
	_instances.clear()
	_side.clear()
	_summary.text = "Waiting for the game..."
	_meters.queue_redraw()


func show_stats(stats: Dictionary) -> void:
	var voices: Dictionary = stats.get("voices", {})
	var fx: Array = stats.get("effect_buses", [0, 0])
	var instances: Array = stats.get("instances", [])
	var limit: int = voices.get("limit", 0)
	_summary.text = "Voices %d%s (%d virtual)  ·  Instances %d  ·  Effect buses %d / %d" % [
		voices.get("real", 0), " / %d" % limit if limit > 0 else "", voices.get("virtual", 0),
		instances.size(), fx[0], fx[1]]
	_history.append(voices.get("real", 0))
	if _history.size() > HISTORY:
		_history = _history.slice(_history.size() - HISTORY)

	_instances.clear()
	var root := _instances.create_item()
	var dim := get_theme_color(&"font_disabled_color", &"Editor") if has_theme_color(&"font_disabled_color", &"Editor") else Color(1, 1, 1, 0.5)
	for info: Dictionary in instances:
		var item := _instances.create_item(root)
		var state: String = info.get("state", "")
		if info.get("virtual", false):
			state += " (virtual)"
		elif info.get("paused", false):
			state += " (paused)"
		var position: float = info.get("position", -1.0)
		var texts := [info.get("event", "?"), state, str(info.get("voices", 0)), info.get("bus", ""),
			"%.2f s" % position if position >= 0.0 else "", "%.0f dB" % info.get("level_db", -100.0), ""]
		for column in 6:
			item.set_text(column, texts[column])
			if info.get("virtual", false) or info.get("paused", false):
				item.set_custom_color(column, dim)

	_side.clear()
	var side_root := _side.create_item()
	_section(side_root, "Snapshots", stats.get("snapshots", []).map(func(s: Dictionary) -> Array:
		return [s.get("name", ""), "%d%%" % roundi(s.get("level", 0.0) * 100.0)]))
	var values: Dictionary = stats.get("parameters", {})
	_section(side_root, "Global parameters", values.keys().map(func(key: String) -> Array:
		return [key, "%.2f" % values[key]]))
	_buses = stats.get("buses", [])
	_meters.custom_minimum_size.y = 40.0 + _buses.size() * 22.0
	_meters.queue_redraw()


func _section(root: TreeItem, title: String, rows: Array) -> void:
	var header := _side.create_item(root)
	header.set_text(0, "%s (%d)" % [title, rows.size()])
	for row: Array in rows:
		var item := _side.create_item(header)
		item.set_text(0, row[0])
		item.set_text(1, row[1])


## One row per bus: name, a peak meter (-60..+6 dB) with the fader position marked, and the
## ducking taken off; then a graph of the voice count.
func _draw_meters() -> void:
	var font := get_theme_font(&"font", &"Label")
	var font_size := get_theme_font_size(&"font_size", &"Label") - 2
	var text := get_theme_color(&"font_color", &"Label")
	var width := _meters.size.x
	var label_w := minf(110.0, width * 0.35)
	var y := 4.0
	for bus: Dictionary in _buses:
		var bar := Rect2(label_w, y + 3, maxf(width - label_w - 60.0, 10.0), 12)
		_meters.draw_string(font, Vector2(4, y + 14), bus.get("name", ""), HORIZONTAL_ALIGNMENT_LEFT, label_w - 8, font_size,
			text.darkened(0.4) if bus.get("muted", false) else text)
		_meters.draw_rect(bar, Color(0, 0, 0, 0.3))
		var peak := clampf(inverse_lerp(-60.0, 6.0, bus.get("peak_db", -100.0)), 0.0, 1.0)
		var color := Color(0.4, 0.85, 0.45) if bus.get("peak_db", -100.0) < -6.0 else (Color(0.95, 0.8, 0.3) if bus.get("peak_db", -100.0) < 0.0 else Color(1.0, 0.35, 0.3))
		_meters.draw_rect(Rect2(bar.position, Vector2(bar.size.x * peak, bar.size.y)), color)
		var fader := bar.position.x + bar.size.x * clampf(inverse_lerp(-60.0, 6.0, bus.get("volume_db", 0.0)), 0.0, 1.0)
		_meters.draw_line(Vector2(fader, bar.position.y - 2), Vector2(fader, bar.end.y + 2), text, 2.0)
		var note := "%.0f dB" % bus.get("volume_db", 0.0)
		if bus.get("duck_db", 0.0) < -0.05:
			note = "duck %.0f" % bus.duck_db
		_meters.draw_string(font, Vector2(bar.end.x + 6, y + 14), note, HORIZONTAL_ALIGNMENT_LEFT, 54, font_size, text.darkened(0.2))
		y += 22.0
	if _history.size() < 2:
		return
	var graph := Rect2(4, y + 6, width - 8, maxf(_meters.size.y - y - 10, 24.0))
	_meters.draw_rect(graph, Color(0, 0, 0, 0.2))
	var top := maxi(Array(_history).max(), 1)
	var points := PackedVector2Array()
	for i in _history.size():
		points.append(Vector2(graph.position.x + graph.size.x * i / float(HISTORY - 1),
			graph.end.y - graph.size.y * _history[i] / float(top)))
	_meters.draw_polyline(points, Color(0.45, 0.75, 1.0), 1.5)
	_meters.draw_string(font, graph.position + Vector2(4, font_size + 2), "voices (peak %d)" % top,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text.darkened(0.3))
