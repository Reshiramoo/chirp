@tool
extends EditorDock
## Bottom dock with a visual editor for TIMELINE events (instruments as blocks, markers as
## flags and regions, a beat/bar grid from the tempo markers, the preview playhead) and
## PARAMETER sheets (instruments along the sheet parameter's range, with their fades; the
## preview's parameter value as the playhead). Every edit goes through the editor's undo/redo.

const TimelineView := preload("timeline_view.gd")
const TimelineModel := preload("timeline_model.gd")

const ADD_INSTRUMENT := 100
const DELETE := 200
const INSPECT := 201

var _plugin: EditorPlugin
var _preview_dock: Node # the Chirp Preview dock, for the playhead and seeking
var _event: ChirpEvent
var _view: TimelineView
var _title: Label
var _snap: OptionButton
var _add: MenuButton
var _context := PopupMenu.new()
var _context_unit := 0.0
var _context_resource: Resource
var _needs_fit := false
var _shown_mode := -1 # sheet mode the view was set up for; switching it re-runs edit()


func setup(plugin: EditorPlugin, preview_dock: Node) -> void:
	_plugin = plugin
	_preview_dock = preview_dock
	title = "Chirp Timeline"
	layout_key = "chirp_timeline"
	default_slot = DOCK_SLOT_BOTTOM
	available_layouts = DOCK_LAYOUT_HORIZONTAL | DOCK_LAYOUT_FLOATING
	custom_minimum_size.y = 260

	var box := VBoxContainer.new()
	add_child(box)
	var toolbar := HBoxContainer.new()
	box.add_child(toolbar)
	_title = Label.new()
	_title.text = "No timeline or parameter sheet event selected"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	toolbar.add_child(_title)

	var snap_label := Label.new()
	snap_label.text = "Snap"
	toolbar.add_child(snap_label)
	_snap = OptionButton.new()
	for option in ["Off", "Beat", "Bar"]:
		_snap.add_item(option)
	_snap.select(TimelineModel.Snap.BEAT)
	_snap.tooltip_text = "Snap moves and resizes to the grid (hold Shift to ignore)"
	_snap.item_selected.connect(func(index: int) -> void: _view.model.snap = index)
	toolbar.add_child(_snap)
	toolbar.add_child(VSeparator.new())
	_tool_button(toolbar, "ZoomLess", "Zoom out", func() -> void: _zoom(1.0 / 1.4))
	_tool_button(toolbar, "ZoomMore", "Zoom in", func() -> void: _zoom(1.4))
	_tool_button(toolbar, "DistractionFree", "Fit the whole timeline", func() -> void:
		_view.model.fit(_view.size.x)
		_view.queue_redraw())
	toolbar.add_child(VSeparator.new())
	_add = MenuButton.new()
	_add.text = "Add"
	_add.icon = _icon("Add")
	_add.flat = false
	_fill_add_menu(_add.get_popup())
	_add.get_popup().id_pressed.connect(func(id: int) -> void: _on_add(id, _insert_unit()))
	_add.about_to_popup.connect(func() -> void:
		_add.get_popup().clear()
		_fill_add_menu(_add.get_popup()))
	toolbar.add_child(_add)
	_tool_button(toolbar, "Save", "Save the event", func() -> void:
		if _event and not _event.resource_path.is_empty():
			ResourceSaver.save(_event))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_view = TimelineView.new()
	_view.model.set_display_scale(EditorInterface.get_editor_scale())
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_view)
	_view.item_selected.connect(_on_item_selected)
	_view.drag_finished.connect(_on_drag_finished)
	_view.delete_requested.connect(_delete)
	_view.context_requested.connect(_on_context_requested)
	_view.seek_requested.connect(_seek)

	var hint := Label.new()
	hint.text = "Drag to move · drag edges to resize · Shift: no snap · right-click to add · Del deletes · Ctrl/Cmd+wheel zooms · Shift+wheel scrolls · click the ruler to seek"
	hint.add_theme_color_override(&"font_color", EditorInterface.get_editor_theme().get_color(&"disabled_font_color", &"Editor"))
	hint.clip_text = true
	box.add_child(hint)

	_context.id_pressed.connect(func(id: int) -> void: _on_add(id, _context_unit))
	add_child(_context)


## Shows [param event] if its sheet mode is TIMELINE or PARAMETER.
func edit(event: ChirpEvent) -> void:
	if event == _event and _shown_mode == (event.sheet_mode if event else -1):
		return
	_event = event
	_shown_mode = event.sheet_mode if event else -1
	var editable := _is_editable(event)
	_view.model.event = event if editable else null
	_view.selected = null
	_view.empty_message = "Select a ChirpEvent whose sheet mode is Timeline or Parameter." if event == null \
		else "%s has no timeline: set its sheet mode to Timeline or Parameter." % _event_name(event)
	var kind := "parameter sheet" if event and event.sheet_mode == ChirpEvent.SheetMode.PARAMETER else "timeline"
	_title.text = "%s (%s)" % [_event_name(event), kind] if editable else "No timeline or parameter sheet event selected"
	_add.disabled = not editable
	var sheet := _view.model.is_sheet()
	for option in 3:
		_snap.set_item_text(option, ["Off", "Fine", "Coarse"][option] if sheet else ["Off", "Beat", "Bar"][option])
	_needs_fit = editable
	_view.queue_redraw()


static func _is_editable(event: ChirpEvent) -> bool:
	return event != null and event.sheet_mode in [ChirpEvent.SheetMode.TIMELINE, ChirpEvent.SheetMode.PARAMETER]


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var model := _view.model
	if _event and _event.sheet_mode != _shown_mode:
		edit(_event) # the sheet mode was just switched
	if model.event == null:
		return
	if model.is_sheet():
		model.sheet_definition = _sheet_definition()
	model.rebuild()
	if _needs_fit and _view.size.x > _view.model.header_width:
		model.fit(_view.size.x)
		_needs_fit = false
	_view.custom_minimum_size.y = model.content_height()
	var instance: ChirpEventInstance = _preview_dock._instance
	if instance and instance.is_playing() and instance.get_event() == model.event:
		if model.is_sheet():
			var state := instance._sheet_state()
			_view.playhead = state.value if state else NAN
		else:
			_view.playhead = model.timeline.to_units(instance.get_timeline_position())
	else:
		_view.playhead = NAN
	_view.queue_redraw()


## The sheet parameter's definition: the event's own, else the preview Chirp's global one.
func _sheet_definition() -> ChirpParameter:
	var local := _event.find_parameter(_event.sheet_parameter)
	if local:
		return local
	var chirp: Node = _preview_dock._chirp
	if chirp and chirp.config:
		for definition in chirp.config.global_parameters:
			if definition and definition.name.nocasecmp_to(_event.sheet_parameter) == 0:
				return definition
	return null


func _on_item_selected(resource: Resource) -> void:
	if resource:
		EditorInterface.inspect_object(resource, "", true)


func _on_drag_finished(resource: Resource, before: Dictionary, after: Dictionary) -> void:
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Move %s" % ("Instrument" if resource is ChirpInstrument else "Marker"))
	for property: String in after:
		undo_redo.add_do_property(resource, property, after[property])
		undo_redo.add_undo_property(resource, property, before[property])
	undo_redo.add_do_method(self, "_changed", resource)
	undo_redo.add_undo_method(self, "_changed", resource)
	undo_redo.commit_action()


func _on_context_requested(screen_position: Vector2, hit: Dictionary) -> void:
	_context.clear()
	_context_unit = maxf(hit.unit, 0.0)
	_context_resource = _view.model.hit_resource(hit)
	if _context_resource:
		_context.add_icon_item(_icon("Edit"), "Inspect", INSPECT)
		_context.add_icon_item(_icon("Remove"), "Delete", DELETE)
		_context.add_separator()
	_fill_add_menu(_context)
	_context.position = Vector2i(screen_position)
	_context.reset_size()
	_context.popup()


func _fill_add_menu(menu: PopupMenu) -> void:
	menu.add_icon_item(_icon("AudioStreamPlayer"), "Add Instrument", ADD_INSTRUMENT)
	if _view and _view.model.is_sheet():
		return # parameter sheets have no markers
	menu.add_separator("Add Marker")
	for kind: int in ChirpMarker.Kind.values():
		menu.add_item(ChirpMarker.Kind.keys()[kind].capitalize(), kind)


func _on_add(id: int, unit: float) -> void:
	if _event == null or _view.model.event == null:
		return
	var model := _view.model
	var at := model.snap_unit(unit)
	match id:
		DELETE:
			_delete(_context_resource)
		INSPECT:
			_on_item_selected(_context_resource)
		ADD_INSTRUMENT:
			var instrument := ChirpInstrument.new()
			instrument.start = at
			instrument.length = model.bar_length_at(at)
			_add_to("instruments", instrument, "Add Instrument")
		_:
			var marker := ChirpMarker.new()
			marker.kind = id
			marker.position = at
			if marker.is_region():
				marker.end = at + model.bar_length_at(at) * 2.0
			if marker.kind == ChirpMarker.Kind.MARKER or marker.kind == ChirpMarker.Kind.DESTINATION:
				marker.name = "%s %d" % ["marker" if marker.kind == ChirpMarker.Kind.MARKER else "destination", _event.markers.size() + 1]
			_add_to("markers", marker, "Add %s" % ChirpMarker.Kind.keys()[id].capitalize())


func _add_to(property: String, resource: Resource, action: String) -> void:
	var before: Array = _event.get(property)
	var after := before.duplicate()
	after.append(resource)
	_commit_array(property, before.duplicate(), after, action)
	_view.selected = resource
	_on_item_selected(resource)


func _delete(resource: Resource) -> void:
	if _event == null or resource == null:
		return
	var property := "instruments" if resource is ChirpInstrument else "markers"
	var before: Array = _event.get(property)
	var after := before.duplicate()
	after.erase(resource)
	_commit_array(property, before.duplicate(), after, "Delete %s" % ("Instrument" if resource is ChirpInstrument else "Marker"))
	_view.selected = null


func _commit_array(property: String, before: Array, after: Array, action: String) -> void:
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action(action)
	undo_redo.add_do_property(_event, property, after)
	undo_redo.add_undo_property(_event, property, before)
	undo_redo.add_do_method(self, "_changed", _event)
	undo_redo.add_undo_method(self, "_changed", _event)
	undo_redo.commit_action()


func _changed(resource: Resource) -> void:
	resource.emit_changed()
	resource.notify_property_list_changed()
	_view.queue_redraw()


func _seek(unit: float) -> void:
	var model := _view.model
	var instance: ChirpEventInstance = _preview_dock._instance
	if not (instance and instance.is_playing() and instance.get_event() == model.event):
		_preview_dock.make_visible()
		_preview_dock.play_item(model.event)
		instance = _preview_dock._instance
	if instance == null:
		return
	if model.is_sheet():
		# Auditions the crossfade: the event's own parameter, else the global one.
		if model.event.find_parameter(model.event.sheet_parameter):
			instance.set_parameter(model.event.sheet_parameter, unit)
		else:
			_preview_dock._chirp.parameters.set_value(model.event.sheet_parameter, unit)
	else:
		instance.set_timeline_position(model.timeline.to_seconds(unit))


## Where toolbar "Add" puts new items: the playhead if previewing, else the left of the view.
func _insert_unit() -> float:
	if not is_nan(_view.playhead):
		return _view.playhead
	return _view.model.scroll


func _zoom(factor: float) -> void:
	_view.model.zoom_at(factor, _view.model.header_width + (_view.size.x - _view.model.header_width) / 2.0)
	_view.queue_redraw()


func _tool_button(parent: Control, icon_name: String, tooltip: String, callback: Callable) -> Button:
	var button := Button.new()
	button.icon = _icon(icon_name)
	button.flat = true
	button.tooltip_text = tooltip
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


static func _event_name(event: ChirpEvent) -> String:
	if event == null:
		return ""
	return event.resource_path.get_file() if event.resource_path else "Unsaved event"


static func _icon(icon_name: String) -> Texture2D:
	var theme := EditorInterface.get_editor_theme()
	return theme.get_icon(icon_name, &"EditorIcons") if theme.has_icon(icon_name, &"EditorIcons") else null
