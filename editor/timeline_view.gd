@tool
extends Control
## Draws a TIMELINE ChirpEvent and edits it with the mouse. Drags are applied live and
## reported through drag_finished so the dock can record one undo action per drag.
##
## Mouse: drag blocks/markers to move, drag their edges to resize (Shift: no snapping),
## click the ruler to seek, right-click for the add/delete menu, middle-drag to pan,
## Shift+wheel to scroll, Ctrl/Cmd+wheel to zoom. Delete removes the selection.

signal item_selected(resource: Resource)
signal drag_finished(resource: Resource, before: Dictionary, after: Dictionary)
signal delete_requested(resource: Resource)
signal context_requested(screen_position: Vector2, hit: Dictionary)
signal seek_requested(unit: float)

const TimelineModel := preload("timeline_model.gd")

const INSTRUMENT_COLORS := {
	ChirpInstrument.Kind.SOUND: Color(0.36, 0.6, 0.95),
	ChirpInstrument.Kind.EVENT: Color(0.68, 0.48, 0.95),
	ChirpInstrument.Kind.SILENCE: Color(0.55, 0.55, 0.58),
}
const MARKER_COLORS := {
	ChirpMarker.Kind.MARKER: Color(0.45, 0.7, 1.0),
	ChirpMarker.Kind.TEMPO: Color(0.75, 0.75, 0.75),
	ChirpMarker.Kind.LOOP_REGION: Color(0.35, 0.82, 0.45),
	ChirpMarker.Kind.SUSTAIN_POINT: Color(0.98, 0.8, 0.3),
	ChirpMarker.Kind.DESTINATION: Color(0.78, 0.55, 1.0),
	ChirpMarker.Kind.TRANSITION: Color(1.0, 0.55, 0.25),
	ChirpMarker.Kind.TRANSITION_REGION: Color(1.0, 0.55, 0.25),
}
const PLAYHEAD_COLOR := Color(1.0, 0.3, 0.3)

var model := TimelineModel.new()
var selected: Resource
## Playhead in timeline units; negative hides it.
var playhead := -1.0
## Shown when there is nothing to draw.
var empty_message := "Select a ChirpEvent whose sheet mode is Timeline."

var _drag := {} # {resource, part, origin, start_unit}
var _panning := false


func _init() -> void:
	focus_mode = Control.FOCUS_CLICK
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func _draw() -> void:
	var font := get_theme_font(&"font", &"Label")
	var font_size := get_theme_font_size(&"font_size", &"Label")
	var small := maxi(font_size - 3, 8)
	var text_color := get_theme_color(&"font_color", &"Label")
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.18))
	if model.event == null:
		draw_string(font, Vector2(16, 30), empty_message, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color.darkened(0.3))
		return
	var event := model.event
	var left := model.header_width
	var from := model.x_to_unit(left)
	var to := model.x_to_unit(size.x)
	var instruments_top := model.instrument_y(0)

	# Lane backgrounds
	draw_rect(Rect2(0, 0, size.x, model.ruler_height), Color(0, 0, 0, 0.25))
	draw_rect(Rect2(0, model.regions_lane_y(), size.x, model.lane_height * model.region_lane_count()), Color(1, 1, 1, 0.02))
	for i in event.instruments.size():
		if i % 2 == 1:
			draw_rect(Rect2(0, model.instrument_y(i), size.x, model.row_height), Color(1, 1, 1, 0.02))

	# Grid and ruler
	for line in model.grid_lines(from, to):
		var x := model.unit_to_x(line.position)
		var bar: bool = line.beat == 1
		draw_line(Vector2(x, model.ruler_height), Vector2(x, size.y), Color(1, 1, 1, 0.13 if bar else 0.05))
		draw_line(Vector2(x, model.ruler_height - (10 if bar else 5)), Vector2(x, model.ruler_height), Color(1, 1, 1, 0.5 if bar else 0.25))
		if bar:
			draw_string(font, Vector2(x + 3, model.ruler_height - 8), str(line.bar), HORIZONTAL_ALIGNMENT_LEFT, -1, small, text_color.darkened(0.2))
	for y in [model.ruler_height, model.regions_lane_y(), instruments_top]:
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(1, 1, 1, 0.08))

	# Regions
	for marker in event.markers:
		if marker == null or not marker.is_region():
			continue
		var color: Color = MARKER_COLORS[marker.kind]
		var rect := Rect2(model.unit_to_x(marker.position), model.regions_lane_y() + model.region_lane(marker) * model.lane_height + 3,
			(marker.end - marker.position) * model.zoom, model.lane_height - 6)
		draw_rect(rect, Color(color, 0.22))
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, 3)), color)
		if marker == selected:
			draw_rect(rect, Color.WHITE, false, 2.0)
		var label := "loop" if marker.kind == ChirpMarker.Kind.LOOP_REGION else "→ " + marker.destination
		if not marker.condition_parameter.is_empty():
			label += "  if %s" % marker.condition_parameter
		_draw_clipped_text(font, small, label, rect.grow_individual(-4, 0, 0, 0), color.lightened(0.4))

	# Point markers
	for marker in event.markers:
		if marker == null or marker.is_region():
			continue
		var color: Color = MARKER_COLORS[marker.kind]
		var x := model.unit_to_x(marker.position)
		if x < left - 200 or x > size.x:
			continue
		draw_line(Vector2(x, model.markers_lane_y()), Vector2(x, size.y), Color(color, 0.45), 1.0)
		var label := _marker_label(marker)
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x + 10
		var flag := Rect2(x, model.markers_lane_y() + 3, width, model.lane_height - 6)
		draw_rect(flag, Color(color, 0.85))
		if marker == selected:
			draw_rect(flag, Color.WHITE, false, 2.0)
		_draw_clipped_text(font, small, label, flag.grow_individual(-5, 0, 0, 0), Color(0.08, 0.08, 0.1))

	# Instruments
	for i in event.instruments.size():
		var instrument := event.instruments[i]
		if instrument == null:
			continue
		var span := model.instrument_span(instrument)
		var x0 := model.unit_to_x(span.x)
		var x1 := model.unit_to_x(span.y) if span.y != INF else size.x + 10
		var rect := Rect2(x0, model.instrument_y(i) + 3, x1 - x0, model.row_height - 6)
		var color: Color = INSTRUMENT_COLORS[instrument.kind]
		draw_rect(rect, Color(color, 0.5 if span.y != INF else 0.3))
		draw_rect(Rect2(rect.position, Vector2(3, rect.size.y)), color)
		if instrument.length <= 0.0 and span.y != INF:
			draw_dashed_line(Vector2(x1, rect.position.y), Vector2(x1, rect.end.y), color, 1.0, 3.0)
		if instrument == selected:
			draw_rect(rect, Color.WHITE, false, 2.0)
		var label := TimelineModel.instrument_label(instrument)
		var tags: PackedStringArray = []
		if instrument.async_playback:
			tags.append("async")
		if instrument.loop:
			tags.append("loop")
		if not instrument.condition_parameter.is_empty():
			tags.append("if " + instrument.condition_parameter)
		if not tags.is_empty():
			label += "  (%s)" % ", ".join(tags)
		_draw_clipped_text(font, small, label, rect.grow_individual(-8, 0, 0, 0), text_color)

	# Playhead
	if playhead >= 0.0:
		var x := model.unit_to_x(playhead)
		if x >= left:
			draw_line(Vector2(x, 0), Vector2(x, size.y), PLAYHEAD_COLOR, 2.0)
			draw_colored_polygon(PackedVector2Array([Vector2(x - 6, 0), Vector2(x + 6, 0), Vector2(x, 8)]), PLAYHEAD_COLOR)

	# Header column, drawn last so blocks scroll under it
	draw_rect(Rect2(0, 0, left, size.y), get_theme_color(&"base_color", &"Editor"))
	draw_line(Vector2(left, 0), Vector2(left, size.y), Color(1, 1, 1, 0.12))
	var header := func(text: String, y: float, height: float, color: Color) -> void:
		_draw_header_text(font, small, text, Rect2(8, y, left - 12, height), color)
	header.call("Bars (%s)" % ("beats" if model.in_beats() else "seconds"), 0, model.ruler_height, text_color.darkened(0.35))
	header.call("Markers", model.markers_lane_y(), model.lane_height, text_color.darkened(0.2))
	header.call("Regions", model.regions_lane_y(), model.lane_height, text_color.darkened(0.2))
	for i in event.instruments.size():
		var instrument := event.instruments[i]
		var label := "%d  %s" % [i + 1, TimelineModel.instrument_label(instrument) if instrument else "(empty)"]
		header.call(label, model.instrument_y(i), model.row_height, text_color)
	if event.instruments.is_empty():
		_draw_header_text(font, small, "No instruments: right-click to add one",
			Rect2(8, instruments_top, size.x, model.row_height), text_color.darkened(0.35))


func _gui_input(input: InputEvent) -> void:
	if model.event == null:
		return
	if input is InputEventMouseButton:
		_on_mouse_button(input)
	elif input is InputEventMouseMotion:
		_on_mouse_motion(input)
	elif input is InputEventPanGesture:
		model.scroll = maxf(model.scroll + input.delta.x * 20.0 / model.zoom, 0.0)
		accept_event()
		queue_redraw()
	elif input is InputEventMagnifyGesture:
		model.zoom_at(input.factor, input.position.x)
		accept_event()
		queue_redraw()
	elif input is InputEventKey and input.pressed:
		if input.keycode in [KEY_DELETE, KEY_BACKSPACE] and selected:
			delete_requested.emit(selected)
			accept_event()
		elif input.keycode == KEY_ESCAPE and not _drag.is_empty():
			_apply(_drag.resource, _drag.origin)
			_drag = {}
			accept_event()


func _on_mouse_button(button: InputEventMouseButton) -> void:
	var zoom_modifier := button.ctrl_pressed or button.meta_pressed
	match button.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if not button.pressed:
				return
			var up := button.button_index == MOUSE_BUTTON_WHEEL_UP
			if zoom_modifier:
				model.zoom_at(1.15 if up else 1.0 / 1.15, button.position.x)
			elif button.shift_pressed:
				model.scroll = maxf(model.scroll + (-40.0 if up else 40.0) / model.zoom, 0.0)
			else:
				return # let the scroll container scroll rows
			accept_event()
			queue_redraw()
		MOUSE_BUTTON_MIDDLE:
			_panning = button.pressed
			accept_event()
		MOUSE_BUTTON_LEFT:
			accept_event()
			if button.pressed:
				grab_focus()
				var hit := model.hit_test(button.position)
				match hit.area:
					"ruler":
						var unit: float = hit.unit if button.shift_pressed else model.snap_unit(hit.unit)
						seek_requested.emit(maxf(unit, 0.0))
					"instrument", "marker":
						var resource := model.hit_resource(hit)
						_select(resource)
						_drag = {resource = resource, part = hit.part, origin = model.drag_origin(resource), start_unit = hit.unit}
					_:
						_select(null)
			elif not _drag.is_empty():
				var after := model.drag_origin(_drag.resource)
				if after != _drag.origin:
					drag_finished.emit(_drag.resource, _drag.origin, after)
				_drag = {}
		MOUSE_BUTTON_RIGHT:
			if button.pressed:
				accept_event()
				var hit := model.hit_test(button.position)
				var resource := model.hit_resource(hit)
				if resource:
					_select(resource)
				context_requested.emit(get_screen_position() + button.position, hit)


func _on_mouse_motion(motion: InputEventMouseMotion) -> void:
	if _panning:
		model.scroll = maxf(model.scroll - motion.relative.x / model.zoom, 0.0)
		queue_redraw()
	elif not _drag.is_empty():
		var delta := model.x_to_unit(motion.position.x) - float(_drag.start_unit)
		var mode := TimelineModel.Snap.OFF if motion.shift_pressed else model.snap
		_apply(_drag.resource, model.drag_values(_drag.resource, _drag.part, _drag.origin, delta, mode))
	else:
		var hit := model.hit_test(motion.position)
		if hit.area in ["instrument", "marker"]:
			mouse_default_cursor_shape = Control.CURSOR_HSIZE if hit.part != "body" else Control.CURSOR_MOVE
		else:
			mouse_default_cursor_shape = Control.CURSOR_ARROW


func _select(resource: Resource) -> void:
	selected = resource
	item_selected.emit(resource)
	queue_redraw()


func _apply(resource: Resource, values: Dictionary) -> void:
	for property: String in values:
		resource.set(property, values[property])
	queue_redraw()


func _marker_label(marker: ChirpMarker) -> String:
	match marker.kind:
		ChirpMarker.Kind.TEMPO:
			var bpm := str(int(marker.bpm)) if is_equal_approx(marker.bpm, roundf(marker.bpm)) else str(snappedf(marker.bpm, 0.01))
			return "%s BPM  %d/%d" % [bpm, marker.beats_per_bar, marker.beat_unit]
		ChirpMarker.Kind.SUSTAIN_POINT:
			return "sustain" + ("  if " + marker.condition_parameter if marker.condition_parameter else "")
		ChirpMarker.Kind.DESTINATION:
			return "◆ " + marker.name
		ChirpMarker.Kind.TRANSITION:
			return "→ " + marker.destination
	return marker.name if marker.name else "marker"


## Text trimmed to [param rect] (and kept right of the header column), centred vertically.
func _draw_clipped_text(font: Font, font_size: int, text: String, rect: Rect2, color: Color) -> void:
	var visible_left := maxf(rect.position.x, model.header_width + 4)
	_draw_line_text(font, font_size, text, Rect2(visible_left, rect.position.y, minf(rect.end.x, size.x) - visible_left, rect.size.y), color)


func _draw_header_text(font: Font, font_size: int, text: String, rect: Rect2, color: Color) -> void:
	_draw_line_text(font, font_size, text, rect, color)


func _draw_line_text(font: Font, font_size: int, text: String, rect: Rect2, color: Color) -> void:
	var visible_left := rect.position.x
	var width := rect.size.x
	if width < 12:
		return
	var line := TextLine.new()
	line.add_string(text, font, font_size)
	line.width = width
	line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.draw(get_canvas_item(), Vector2(visible_left, rect.position.y + (rect.size.y - line.get_size().y) / 2.0), color)
