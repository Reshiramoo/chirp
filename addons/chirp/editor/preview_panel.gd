@tool
extends VBoxContainer
## Auditioning for the Chirp Event dock: plays the shown event or snapshot through the editor's
## preview copy of Chirp, with sliders for its parameters and the global ones, and a log of
## beats and markers. The dock puts [member transport] and [method status_text] in its toolbar
## and this panel at its side.

const LOG_LINES := 40

## Play / Stop / Stop Now / Key Off, for the dock's toolbar.
var transport: HBoxContainer

var _chirp: Node # the editor's preview copy of Chirp
var _event: ChirpEvent
var _event_label := ""
var _snapshot: ChirpSnapshot
var _instance: ChirpEventInstance
var _snapshot_instance: ChirpSnapshotInstance
var _local_values := {} # parameter name -> value, applied when an instance starts
var _rows := {} # lowercase parameter name -> {slider or options, value_label}
var _intensity: HSlider
var _rows_signature := "" # parameter list the rows were built for; rebuilt when it changes

var _play: Button
var _stop: Button
var _stop_now: Button
var _key_off: Button
var _parameters: VBoxContainer # one row per parameter: name, control, value
var _log: RichTextLabel
var _log_lines: Array[String] = []


func setup(chirp: Node) -> void:
	_chirp = chirp
	custom_minimum_size.x = 170 * EditorInterface.get_editor_scale()
	transport = HBoxContainer.new()
	_play = _button("Play", "Play", "Play (Space)", play)
	_stop = _button("", "Stop", "Stop with the fade-out (Space)", func() -> void: stop(true))
	_stop_now = _button("", "Close", "Stop now, without the fade-out", func() -> void: stop(false))
	_key_off = _button("Key Off", "KeyAudio", "Release the sustain point holding the playhead", func() -> void:
		if _instance:
			_instance.key_off())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_parameters = VBoxContainer.new()
	_parameters.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_parameters)
	add_child(_section_label("Log"))
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.custom_minimum_size.y = 72 * EditorInterface.get_editor_scale()
	add_child(_log)
	chirp.warning_issued.connect(_on_warning)
	show_nothing()


## Loads an event path, ChirpEvent or ChirpSnapshot. Returns the ChirpEvent shown, if any.
func show_item(item: Variant) -> ChirpEvent:
	if item is String:
		var event: ChirpEvent = _chirp.events.get_event(item)
		if event:
			_load_event(event, item)
			return event
	elif item is ChirpEvent:
		_load_event(item, item.resource_path.get_file() if item.resource_path else "Event")
		return item
	elif item is ChirpSnapshot:
		_load_snapshot(item)
	return null


func show_nothing() -> void:
	stop(false)
	_event = null
	_snapshot = null
	_clear_children(_parameters)
	_rows.clear()
	_add_note("Select an event or snapshot to preview it.")
	_set_transport_enabled(false)
	_key_off.visible = false


func play() -> void:
	if _event == null and _snapshot == null:
		return
	_chirp.mixer.set_live(true)
	if _snapshot:
		if _snapshot_instance and _snapshot_instance.is_playing():
			return
		_snapshot_instance = _chirp.mixer.start_snapshot(_snapshot)
		if _snapshot_instance:
			_snapshot_instance.intensity = _intensity.value if _intensity else 1.0
			_log_line("[color=gray]snapshot started[/color]")
		return
	_chirp._warned.clear() # report the event's problems again on every audition
	# A fresh instance each time, so edits to the event (instruments, markers) are picked up.
	if _instance:
		_instance.stop(false)
	_instance = _chirp.create_instance(_event)
	if _instance == null:
		return
	for parameter_name: String in _local_values:
		_instance.set_parameter(parameter_name, _local_values[parameter_name])
	_instance.timeline_beat.connect(func(bar: int, beat: int, position: float, _tempo: float, _signature: Vector2i) -> void:
		_log_line("[color=gray]%6.2fs[/color]  beat %d.%d" % [position, bar, beat]))
	_instance.timeline_marker.connect(func(marker_name: String, position: float) -> void:
		_log_line("[color=gray]%6.2fs[/color]  [b]marker %s[/b]" % [position, marker_name]))
	_instance.stopped.connect(func() -> void: _log_line("[color=gray]stopped[/color]"))
	_instance.start()
	_log_line("[color=gray]started %s[/color]" % _event_label)


func stop(allow_fadeout: bool) -> void:
	if _instance:
		_instance.stop(allow_fadeout)
		if not allow_fadeout:
			_instance = null
	if _snapshot_instance:
		_snapshot_instance.stop(allow_fadeout)
		if not allow_fadeout:
			_snapshot_instance = null


func is_playing() -> bool:
	return _instance != null and _instance.is_playing() or _snapshot_instance != null and _snapshot_instance.is_playing()


## Play, or stop with the fade-out (the Space key).
func toggle_play() -> void:
	if is_playing():
		stop(true)
	else:
		play()


## The playing instance of [param event], or null.
func instance_of(event: ChirpEvent) -> ChirpEventInstance:
	return _instance if _instance and _instance.is_playing() and _instance.get_event() == event else null


## Sets a parameter of the shown event (local first, then global) and moves its slider.
func set_parameter_value(parameter_name: String, value: float) -> void:
	var local := _event.find_parameter(parameter_name) if _event else null
	if local:
		value = local.clamp_value(value)
		_local_values[local.name] = value
		if _instance and _instance.is_playing():
			_instance.set_parameter(local.name, value)
	else:
		_chirp.parameters.set_value(parameter_name, value)
		value = _chirp.parameters.get_value(parameter_name)
	var row: Dictionary = _rows.get(parameter_name.to_lower(), {})
	if row.has("slider"):
		row.slider.set_value_no_signal(value)
	elif row.has("options"):
		row.options.select(int(value))
	if row.has("value_label"):
		row.value_label.text = _format(value)


## For the dock's toolbar: what is playing, its voices and playhead or sheet parameter.
func status_text() -> String:
	if _instance and _instance.is_playing():
		var parts := ["Playing" if _instance.get_state() == ChirpEventInstance.State.PLAYING else "Stopping",
			"%d voice%s" % [_instance._voices.size(), "" if _instance._voices.size() == 1 else "s"]]
		match _event.sheet_mode:
			ChirpEvent.SheetMode.TIMELINE:
				parts.append("%.2fs" % _instance.get_timeline_position())
				if _instance.is_sustaining():
					parts.append("sustaining")
			ChirpEvent.SheetMode.PARAMETER:
				var state := _instance._sheet_state()
				if state:
					parts.append("%s %s" % [_event.sheet_parameter, _format(state.value)])
		return "  ·  ".join(parts)
	if _snapshot_instance and _snapshot_instance.is_playing():
		return "Active  ·  level %.2f" % _snapshot_instance.get_level()
	return "Stopped" if _event or _snapshot else ""


func _process(_delta: float) -> void:
	if _chirp == null:
		return
	if _event and _signature() != _rows_signature:
		_build_event_rows() # parameters were added, removed or changed in the inspector
	_key_off.disabled = not (_instance and _instance.is_sustaining())
	_play.text = "Restart" if _instance and _instance.is_playing() else ("Start" if _snapshot else "Play")
	# Hand the project's buses back once nothing is being auditioned.
	if _chirp.mixer.is_live() and _chirp.events.get_active_instances().is_empty() \
			and _chirp.mixer.get_active_snapshots().is_empty():
		_chirp.mixer.set_live(false)


func _exit_tree() -> void:
	stop(false)


func _load_event(event: ChirpEvent, label: String) -> void:
	if event == _event:
		return
	stop(false)
	_event = event
	_event_label = label
	_snapshot = null
	_local_values.clear()
	_key_off.visible = event.sheet_mode == ChirpEvent.SheetMode.TIMELINE
	_set_transport_enabled(true)
	_build_event_rows()


func _build_event_rows() -> void:
	_rows_signature = _signature()
	_clear_children(_parameters)
	_rows.clear()
	_add_header("Event parameters")
	if _event.parameters.is_empty():
		_add_note("none")
	for parameter in _event.parameters:
		if parameter:
			_add_parameter_row(parameter, false)
	_add_global_parameters()


## Names, kinds and ranges of the shown event's and the global parameters.
func _signature() -> String:
	var parts := []
	for parameter in _event.parameters + _chirp.config.global_parameters:
		if parameter:
			parts.append([parameter.name, parameter.kind, parameter.built_in, parameter.get_min(),
				parameter.get_max(), parameter.labels])
	return var_to_str(parts)


func _load_snapshot(snapshot: ChirpSnapshot) -> void:
	if snapshot == _snapshot:
		return
	stop(false)
	_event = null
	_snapshot = snapshot
	_key_off.visible = false
	_set_transport_enabled(true)
	_clear_children(_parameters)
	_rows.clear()
	_add_header("Snapshot")
	var label := _name_label("Intensity")
	_intensity = _slider(0.0, 1.0, 0.01, 1.0)
	var value_label := _value_label()
	value_label.text = "1.00"
	_intensity.value_changed.connect(func(value: float) -> void:
		value_label.text = "%.2f" % value
		if _snapshot_instance:
			_snapshot_instance.intensity = value)
	_add_row([label, _intensity, value_label])
	_add_global_parameters()


func _add_global_parameters() -> void:
	var config: ChirpConfig = _chirp.config
	if config.global_parameters.is_empty():
		return
	_add_header("Global parameters")
	for parameter in config.global_parameters:
		if parameter:
			_add_parameter_row(parameter, true)


func _add_parameter_row(parameter: ChirpParameter, global: bool) -> void:
	var label := _name_label(parameter.name)
	var current: float = _chirp.parameters.get_value(parameter.name) if global \
		else _local_values.get(parameter.name, parameter.clamp_value(parameter.default_value))
	var value_label := _value_label()
	var row := {value_label = value_label}
	if not global or not _rows.has(parameter.name.to_lower()): # a local parameter shadows a global one
		_rows[parameter.name.to_lower()] = row

	if parameter.built_in != ChirpParameter.BuiltIn.NONE:
		var note := Label.new()
		note.text = "built-in: %s" % ChirpParameter.BuiltIn.keys()[parameter.built_in].to_lower()
		note.add_theme_color_override(&"font_color", _theme_color(&"disabled_font_color"))
		note.clip_text = true
		note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_add_row([label, note])
	elif parameter.kind == ChirpParameter.Kind.LABELED:
		var options := OptionButton.new()
		for option in parameter.labels:
			options.add_item(option)
		options.select(int(current))
		options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		options.item_selected.connect(func(index: int) -> void: set_parameter_value(parameter.name, float(index)))
		row.options = options
		_add_row([label, options, value_label])
	else:
		var step := 1.0 if parameter.kind == ChirpParameter.Kind.DISCRETE else (parameter.get_max() - parameter.get_min()) / 1000.0
		var slider := _slider(parameter.get_min(), parameter.get_max(), step, current)
		value_label.text = _format(current)
		slider.value_changed.connect(func(value: float) -> void: set_parameter_value(parameter.name, value))
		row.slider = slider
		_add_row([label, slider, value_label])


func _slider(lo: float, hi: float, step: float, value: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size.x = 50 * EditorInterface.get_editor_scale()
	return slider


func _add_header(text: String) -> void:
	var header := _section_label(text)
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_parameters.add_child(header)


func _add_row(cells: Array) -> void:
	var row := HBoxContainer.new()
	for cell: Control in cells:
		row.add_child(cell)
	_parameters.add_child(row)


## A parameter's name: a fixed width so the sliders line up, the full name in the tooltip.
func _name_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.tooltip_text = text
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.clip_text = true
	label.custom_minimum_size.x = 70 * EditorInterface.get_editor_scale()
	return label


func _value_label() -> Label:
	var label := Label.new()
	label.custom_minimum_size.x = 44 * EditorInterface.get_editor_scale()
	label.clip_text = true
	return label


func _section_label(text: String) -> Label:
	var header := Label.new()
	header.text = text
	header.add_theme_color_override(&"font_color", _theme_color(&"accent_color"))
	return header


func _add_note(text: String) -> void:
	var note := Label.new()
	note.text = text
	note.add_theme_color_override(&"font_color", _theme_color(&"disabled_font_color"))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_parameters.add_child(note)


## Chirp's warnings and errors while auditioning, in the log.
func _on_warning(message: String, is_error: bool) -> void:
	var color := _theme_color(&"error_color") if is_error else _theme_color(&"warning_color")
	_log_line("[color=#%s]%s %s[/color]" % [color.to_html(false), "✖" if is_error else "⚠",
		message.trim_prefix("Chirp: ").replace("[", "[lb]")])


func _log_line(line: String) -> void:
	_log_lines.append(line)
	if _log_lines.size() > LOG_LINES:
		_log_lines.pop_front()
	_log.text = "\n".join(_log_lines)


func _button(text: String, icon_name: String, tooltip: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.flat = true
	button.tooltip_text = tooltip
	var theme := EditorInterface.get_editor_theme()
	if theme.has_icon(icon_name, &"EditorIcons"):
		button.icon = theme.get_icon(icon_name, &"EditorIcons")
	button.pressed.connect(callback)
	transport.add_child(button)
	return button


func _set_transport_enabled(enabled: bool) -> void:
	for button: Button in [_play, _stop, _stop_now, _key_off]:
		button.disabled = not enabled


static func _format(value: float) -> String:
	return str(roundi(value)) if is_equal_approx(value, roundf(value)) and absf(value) >= 10.0 else "%.2f" % value


static func _theme_color(color_name: StringName) -> Color:
	return EditorInterface.get_editor_theme().get_color(color_name, &"Editor")


static func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
