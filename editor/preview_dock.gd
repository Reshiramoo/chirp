@tool
extends EditorDock
## Bottom dock for auditioning in the editor: play / stop / key-off the selected event,
## drive its parameters and the global parameters, start snapshots, and watch the
## playhead, beats and markers live. Uses the editor's preview copy of Chirp.

const LOG_LINES := 40

var _chirp: Node # the editor's preview copy of Chirp
var _event: ChirpEvent
var _event_label := ""
var _snapshot: ChirpSnapshot
var _instance: ChirpEventInstance
var _snapshot_instance: ChirpSnapshotInstance
var _local_values := {} # parameter name -> value, applied when an instance starts

var _title: Label
var _transport: HBoxContainer
var _play: Button
var _stop: Button
var _stop_now: Button
var _key_off: Button
var _status: Label
var _parameters: GridContainer
var _log: RichTextLabel
var _log_lines: Array[String] = []


func setup(chirp: Node) -> void:
	_chirp = chirp
	title = "Chirp Preview"
	_set_dock_icon(self, "preview.svg")
	layout_key = "chirp_preview"
	default_slot = DOCK_SLOT_BOTTOM
	available_layouts = DOCK_LAYOUT_HORIZONTAL | DOCK_LAYOUT_FLOATING
	custom_minimum_size.y = 260

	var box := VBoxContainer.new()
	add_child(box)
	_transport = HBoxContainer.new()
	box.add_child(_transport)
	_title = Label.new()
	_title.text = "Select an event or snapshot in the Chirp dock"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	_transport.add_child(_title)
	_play = _button("Play", "Play", _on_play)
	_stop = _button("Stop", "Stop", func() -> void: _stop_preview(true))
	_stop_now = _button("Stop Now", "Stop", func() -> void: _stop_preview(false))
	_stop_now.tooltip_text = "Stop without the fade-out"
	_key_off = _button("Key Off", "KeyAudio", func() -> void:
		if _instance:
			_instance.key_off())
	_key_off.tooltip_text = "Release the sustain point holding the playhead"
	_status = Label.new()
	_status.add_theme_color_override(&"font_color", EditorInterface.get_editor_theme().get_color(&"disabled_font_color", &"Editor"))
	box.add_child(_status)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(split)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(scroll)
	_parameters = GridContainer.new()
	_parameters.columns = 3
	_parameters.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_parameters)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.custom_minimum_size.x = 260
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(_log)
	_show_nothing()


## Loads an event path, ChirpEvent or ChirpSnapshot into the dock. Other items are ignored.
func show_item(item: Variant) -> void:
	if item is String:
		var event: ChirpEvent = _chirp.events.get_event(item)
		if event:
			_load_event(event, item)
	elif item is ChirpEvent:
		_load_event(item, item.resource_path.get_file() if item.resource_path else "Event")
	elif item is ChirpSnapshot:
		_load_snapshot(item)


func play_item(item: Variant) -> void:
	show_item(item)
	_on_play()


func _process(_delta: float) -> void:
	if _chirp == null:
		return
	if _instance and _instance.is_playing():
		var parts := ["Playing" if _instance.get_state() == ChirpEventInstance.State.PLAYING else "Stopping",
			"%d voice%s" % [_instance._voices.size(), "" if _instance._voices.size() == 1 else "s"]]
		if _event.sheet_mode == ChirpEvent.SheetMode.TIMELINE:
			parts.append("playhead %.2fs" % _instance.get_timeline_position())
			if _instance.is_sustaining():
				parts.append("held at sustain point")
		_status.text = "  ·  ".join(parts)
	elif _snapshot_instance and _snapshot_instance.is_playing():
		_status.text = "Snapshot active  ·  level %.2f" % _snapshot_instance.get_level()
	elif _event or _snapshot:
		_status.text = "Stopped"
	_key_off.disabled = not (_instance and _instance.is_sustaining())
	# Hand the project's buses back once nothing is being auditioned.
	if _chirp.mixer.is_live() and _chirp.events.get_active_instances().is_empty() \
			and _chirp.mixer.get_active_snapshots().is_empty():
		_chirp.mixer.set_live(false)


func _exit_tree() -> void:
	_stop_preview(false)


func _load_event(event: ChirpEvent, label: String) -> void:
	_stop_preview(false)
	_event = event
	_event_label = label
	_snapshot = null
	_local_values.clear()
	_title.text = label
	_play.text = "Play"
	_stop_now.visible = true
	_key_off.visible = event.sheet_mode == ChirpEvent.SheetMode.TIMELINE
	_set_transport_enabled(true)
	_clear_children(_parameters)
	_add_header("Event parameters")
	if event.parameters.is_empty():
		_add_note("none")
	for parameter in event.parameters:
		if parameter:
			_add_parameter_row(parameter, false)
	_add_global_parameters()


func _load_snapshot(snapshot: ChirpSnapshot) -> void:
	_stop_preview(false)
	_event = null
	_snapshot = snapshot
	_title.text = "Snapshot: %s" % (snapshot.name if snapshot.name else "(unnamed)")
	_play.text = "Start"
	_stop_now.visible = true
	_key_off.visible = false
	_set_transport_enabled(true)
	_clear_children(_parameters)
	_add_header("Snapshot")
	var label := Label.new()
	label.text = "Intensity"
	_parameters.add_child(label)
	var slider := _slider(0.0, 1.0, 0.01, 1.0)
	var value_label := Label.new()
	value_label.text = "1.00"
	slider.value_changed.connect(func(value: float) -> void:
		value_label.text = "%.2f" % value
		if _snapshot_instance:
			_snapshot_instance.intensity = value)
	_parameters.add_child(slider)
	_parameters.add_child(value_label)
	_add_global_parameters()


func _show_nothing() -> void:
	_set_transport_enabled(false)
	_key_off.visible = false
	_status.text = ""


func _on_play() -> void:
	if _event == null and _snapshot == null:
		return
	_chirp.mixer.set_live(true)
	if _snapshot:
		if _snapshot_instance and _snapshot_instance.is_playing():
			return
		var intensity := 1.0
		for child in _parameters.get_children():
			if child is HSlider:
				intensity = child.value
				break
		_snapshot_instance = _chirp.mixer.start_snapshot(_snapshot)
		if _snapshot_instance:
			_snapshot_instance.intensity = intensity
			_log_line("[color=gray]snapshot started[/color]")
		return
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


func _stop_preview(allow_fadeout: bool) -> void:
	if _instance:
		_instance.stop(allow_fadeout)
		if not allow_fadeout:
			_instance = null
	if _snapshot_instance:
		_snapshot_instance.stop(allow_fadeout)
		if not allow_fadeout:
			_snapshot_instance = null


func _add_global_parameters() -> void:
	var config: ChirpConfig = _chirp.config
	if config.global_parameters.is_empty():
		return
	_add_header("Global parameters")
	for parameter in config.global_parameters:
		if parameter:
			_add_parameter_row(parameter, true)


func _add_parameter_row(parameter: ChirpParameter, global: bool) -> void:
	var label := Label.new()
	label.text = parameter.name
	_parameters.add_child(label)
	var current: float = _chirp.parameters.get_value(parameter.name) if global \
		else parameter.clamp_value(parameter.default_value)
	var value_label := Label.new()
	value_label.custom_minimum_size.x = 70
	var apply := func(value: float) -> void:
		if global:
			_chirp.parameters.set_value(parameter.name, value)
		else:
			_local_values[parameter.name] = value
			if _instance and _instance.is_playing():
				_instance.set_parameter(parameter.name, value)

	if parameter.built_in != ChirpParameter.BuiltIn.NONE:
		var note := Label.new()
		note.text = "built-in: %s" % ChirpParameter.BuiltIn.keys()[parameter.built_in].to_lower()
		note.add_theme_color_override(&"font_color", EditorInterface.get_editor_theme().get_color(&"disabled_font_color", &"Editor"))
		_parameters.add_child(note)
		_parameters.add_child(Control.new())
	elif parameter.kind == ChirpParameter.Kind.LABELED:
		var options := OptionButton.new()
		for option in parameter.labels:
			options.add_item(option)
		options.select(int(current))
		options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		options.item_selected.connect(func(index: int) -> void: apply.call(float(index)))
		_parameters.add_child(options)
		_parameters.add_child(value_label)
	else:
		var step := 1.0 if parameter.kind == ChirpParameter.Kind.DISCRETE else (parameter.get_max() - parameter.get_min()) / 1000.0
		var slider := _slider(parameter.get_min(), parameter.get_max(), step, current)
		value_label.text = "%.2f" % current
		slider.value_changed.connect(func(value: float) -> void:
			value_label.text = "%.2f" % value
			apply.call(value))
		_parameters.add_child(slider)
		_parameters.add_child(value_label)


func _slider(lo: float, hi: float, step: float, value: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size.x = 160
	return slider


func _add_header(text: String) -> void:
	var header := Label.new()
	header.text = text
	header.add_theme_color_override(&"font_color", EditorInterface.get_editor_theme().get_color(&"accent_color", &"Editor"))
	_parameters.add_child(header)
	_parameters.add_child(Control.new())
	_parameters.add_child(Control.new())


func _add_note(text: String) -> void:
	var note := Label.new()
	note.text = text
	note.add_theme_color_override(&"font_color", EditorInterface.get_editor_theme().get_color(&"disabled_font_color", &"Editor"))
	_parameters.add_child(note)
	_parameters.add_child(Control.new())
	_parameters.add_child(Control.new())


func _log_line(line: String) -> void:
	_log_lines.append(line)
	if _log_lines.size() > LOG_LINES:
		_log_lines.pop_front()
	_log.text = "\n".join(_log_lines)


func _button(text: String, icon_name: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	var theme := EditorInterface.get_editor_theme()
	if theme.has_icon(icon_name, &"EditorIcons"):
		button.icon = theme.get_icon(icon_name, &"EditorIcons")
	button.pressed.connect(callback)
	_transport.add_child(button)
	return button


func _set_transport_enabled(enabled: bool) -> void:
	for button: Button in [_play, _stop, _stop_now, _key_off]:
		button.disabled = not enabled


static func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


## Loaded (not preloaded) so a freshly pulled icon that isn't imported yet can't break the plugin.
static func _set_dock_icon(dock: EditorDock, file: String) -> void:
	var path: String = (dock.get_script() as Script).resource_path.get_base_dir().path_join("../icons").path_join(file).simplify_path()
	if ResourceLoader.exists(path):
		dock.dock_icon = load(path)
		dock.force_show_icon = true
