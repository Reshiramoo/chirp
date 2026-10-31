@tool
extends EditorDock
## The Chirp Event bottom dock: edit and audition the selected event or snapshot in one place.
## The toolbar has the transport (play, stop, key off) and status; the side panel has parameter
## sliders and a beat/marker log. TIMELINE events and PARAMETER sheets are shown and edited
## visually (instruments as blocks, markers as flags and regions, the playhead or sheet value);
## other events and snapshots are auditioned only. Every edit goes through the editor's undo/redo.

const TimelineView := preload("timeline_view.gd")
const TimelineModel := preload("timeline_model.gd")
const PreviewPanel := preload("preview_panel.gd")
const WaveformCache := preload("waveform_cache.gd")
const EventChecks := preload("event_checks.gd")
const CHECK_INTERVAL := 0.5 # seconds between re-running the authoring checks

const ADD_INSTRUMENT := 100
const ADD_VOLUME_LANE := 101
const ADD_PITCH_LANE := 102
const ADD_PAN_LANE := 103
const ADD_INSTRUMENT_VOLUME_LANE := 104
const ADD_INSTRUMENT_PITCH_LANE := 105
const ADD_EFFECT_LANE := 1000 # + an index into _effect_menu
const DELETE := 200
const INSPECT := 201
const RENAME := 202
const DELETE_POINT := 203

var _plugin: EditorPlugin
var _chirp: Node # the editor's preview copy of Chirp
var _preview: PreviewPanel
var _status: Label
var _event: ChirpEvent
var _item_label := "" # what the transport plays when it isn't a timeline (snapshot, other event)
var _view: TimelineView
var _title: Label
var _snap: OptionButton
var _add: MenuButton
var _context := PopupMenu.new()
var _context_unit := 0.0
var _context_resource: Resource
var _needs_fit := false
var _effect_menu: Array[Dictionary] = [] # the Add menu's effect properties: {index, property, range}
var _rename_edit: LineEdit
var _waveforms := WaveformCache.new()
var _issues: Array[Dictionary] = [] # EventChecks results for the shown event
var _issues_button: Button
var _issues_menu := PopupMenu.new()
var _check_in := 0.0
var _renaming: ChirpMarker
var _shown_mode := -1 # sheet mode the view was set up for; switching it re-runs edit()


func setup(plugin: EditorPlugin, chirp: Node) -> void:
	_plugin = plugin
	_chirp = chirp
	title = "Chirp Event"
	_set_dock_icon(self, "timeline.svg")
	layout_key = "chirp_event"
	default_slot = DOCK_SLOT_BOTTOM
	available_layouts = DOCK_LAYOUT_HORIZONTAL | DOCK_LAYOUT_FLOATING
	custom_minimum_size.y = 260
	_preview = PreviewPanel.new()
	_preview.setup(chirp)

	var box := VBoxContainer.new()
	add_child(box)
	var toolbar := HBoxContainer.new()
	box.add_child(toolbar)
	_title = Label.new()
	_title.text = "Select an event or snapshot"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	_title.custom_minimum_size.x = 80 * EditorInterface.get_editor_scale()
	toolbar.add_child(_title)
	toolbar.add_child(_preview.transport)
	_status = Label.new()
	_status.add_theme_color_override(&"font_color", EditorInterface.get_editor_theme().get_color(&"disabled_font_color", &"Editor"))
	_status.custom_minimum_size.x = 170 * EditorInterface.get_editor_scale()
	_status.clip_text = true
	toolbar.add_child(_status)
	_issues_button = Button.new()
	_issues_button.flat = true
	_issues_button.visible = false
	_issues_button.pressed.connect(_show_issues)
	toolbar.add_child(_issues_button)
	_issues_menu.id_pressed.connect(_on_issue_chosen)
	add_child(_issues_menu)
	toolbar.add_child(VSeparator.new())

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
	var panel_toggle := _tool_button(toolbar, "HSlider", "Show the parameters and log", func() -> void: pass)
	panel_toggle.toggle_mode = true
	panel_toggle.button_pressed = true
	panel_toggle.toggled.connect(func(on: bool) -> void: _preview.visible = on)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(split)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(scroll)
	split.add_child(_preview)
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
	_view.drop_requested.connect(_on_drop)
	_view.rename_requested.connect(_start_rename)
	_view.play_toggle_requested.connect(_preview.toggle_play)
	_view.automation_edited.connect(_on_automation_edited)
	_view.instrument_volume_changed.connect(_on_instrument_volume_changed)
	_view.audition = chirp
	_view.waveforms = _waveforms

	var hint := Label.new()
	hint.text = "Space plays/stops · click an automation lane to add points · drop audio files to add (Shift: as one playlist) · double-click or F2 renames a marker · drag to move · drag edges to resize · Shift: no snap · right-click to add · Del deletes · Ctrl/Cmd+wheel zooms · Shift+wheel scrolls · click the ruler to seek"
	hint.add_theme_color_override(&"font_color", EditorInterface.get_editor_theme().get_color(&"disabled_font_color", &"Editor"))
	hint.clip_text = true
	box.add_child(hint)

	_context.id_pressed.connect(func(id: int) -> void: _on_add(id, _context_unit))
	add_child(_context)


## Shows an event path, ChirpEvent or ChirpSnapshot: ready to audition, and editable when it's
## a TIMELINE event or PARAMETER sheet.
func show_item(item: Variant) -> void:
	if not (item is String or item is ChirpEvent or item is ChirpSnapshot):
		return # VCAs, global parameters...: nothing to audition
	var event := _preview.show_item(item)
	if item is ChirpSnapshot:
		_item_label = "Snapshot: %s" % (item.name if item.name else "(unnamed)")
	elif item is String:
		_item_label = item
	else:
		_item_label = ""
	edit(event)


## Shows [param item] and plays it, bringing the dock to the front.
func play_item(item: Variant) -> void:
	make_visible()
	show_item(item)
	_preview.play()


## Shows [param event] if its sheet mode is TIMELINE or PARAMETER.
func edit(event: ChirpEvent) -> void:
	if event == _event and _shown_mode == (event.sheet_mode if event else -1):
		return
	_event = event
	_shown_mode = event.sheet_mode if event else -1
	var editable := _is_editable(event)
	_view.model.event = event if editable else null
	_view.selected = null
	if event == null:
		_view.empty_message = "Snapshots have no timeline: start it and move the sliders on the right." \
			if _item_label.begins_with("Snapshot") else "Select an event or snapshot in the Chirp dock or the FileSystem."
	else:
		_view.empty_message = "No timeline to edit: play it here, or set its sheet mode to Timeline or Parameter to lay instruments out."
	var kind := ""
	if event:
		kind = ["simultaneous", "consecutive", "timeline", "parameter sheet"][event.sheet_mode]
	var name := _item_label if not _item_label.is_empty() else _event_name(event)
	_title.text = ("%s (%s)" % [name, kind] if event else name) if name else "Select an event or snapshot"
	_add.disabled = not editable
	var sheet := _view.model.is_sheet()
	for option in 3:
		_snap.set_item_text(option, ["Off", "Fine", "Coarse"][option] if sheet else ["Off", "Beat", "Bar"][option])
	_needs_fit = editable
	refresh_issues()
	_view.queue_redraw()


static func _is_editable(event: ChirpEvent) -> bool:
	return event != null and event.sheet_mode in [ChirpEvent.SheetMode.TIMELINE, ChirpEvent.SheetMode.PARAMETER]


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var model := _view.model
	_status.text = _preview.status_text()
	_check_in -= delta
	if _check_in <= 0.0:
		refresh_issues()
	if _event and _event.sheet_mode != _shown_mode:
		edit(_event) # the sheet mode was just switched
	if model.event == null:
		return
	_waveforms.step()
	if model.is_sheet():
		model.sheet_definition = _sheet_definition()
	model.rebuild()
	if _needs_fit and _view.size.x > _view.model.header_width:
		model.fit(_view.size.x)
		_needs_fit = false
	_view.custom_minimum_size.y = model.content_height()
	var instance := _preview.instance_of(model.event)
	if instance:
		if model.is_sheet():
			var state := instance._sheet_state()
			_view.playhead = state.value if state else NAN
			_view.voice_progress = TimelineModel.sheet_progress(instance)
		else:
			_view.playhead = model.timeline.to_units(instance.get_timeline_position())
	else:
		_view.playhead = NAN
	if instance == null or not model.is_sheet():
		_view.voice_progress = {}
	_view.queue_redraw()


## Re-runs the authoring checks on the shown event: the toolbar's warning button and the marks in
## the view.
func refresh_issues() -> void:
	_check_in = CHECK_INTERVAL
	var globals: Array = _chirp.config.global_parameters if _chirp and _chirp.config else []
	_issues = EventChecks.check(_event, globals)
	_view.issues = EventChecks.by_resource(_issues)
	var warnings := _issues.filter(func(issue: Dictionary) -> bool: return issue.severity == EventChecks.Severity.WARNING).size()
	_issues_button.visible = not _issues.is_empty()
	_issues_button.icon = _icon("NodeWarning")
	_issues_button.modulate = TimelineView.ISSUE_COLORS[0 if warnings > 0 else 1]
	_issues_button.text = str(_issues.size())
	_issues_button.tooltip_text = "%d warning(s), %d note(s): click to list them" % [warnings, _issues.size() - warnings]


func _show_issues() -> void:
	_issues_menu.clear()
	for i in _issues.size():
		var issue: Dictionary = _issues[i]
		_issues_menu.add_item(("⚠ " if issue.severity == EventChecks.Severity.WARNING else "ⓘ ") + issue.message, i)
	var at := _issues_button.get_screen_position() + Vector2(0, _issues_button.size.y)
	_issues_menu.popup(Rect2i(Vector2i(at), Vector2i.ZERO))


## Selects what an issue is about, in the view and the Inspector.
func _on_issue_chosen(index: int) -> void:
	if index < 0 or index >= _issues.size():
		return
	var resource: Resource = _issues[index].resource
	_view.selected = resource if resource != _event else null
	_view.queue_redraw()
	_on_item_selected(resource)


## The sheet parameter's definition: the event's own, else the preview Chirp's global one.
func _sheet_definition() -> ChirpParameter:
	var local := _event.find_parameter(_event.sheet_parameter)
	if local:
		return local
	if _chirp and _chirp.config:
		for definition in _chirp.config.global_parameters:
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
		if _context_resource is ChirpMarker and not TimelineModel.rename_property(_context_resource).is_empty():
			_context.add_icon_item(_icon("Rename"), "Rename", RENAME)
		if hit.area == "automation" and hit.point >= 0:
			_context.add_icon_item(_icon("Remove"), "Delete Point", DELETE_POINT)
		if _context_resource is ChirpInstrument:
			_context.add_icon_item(_icon("Curve"), "Add Volume Automation (this instrument)", ADD_INSTRUMENT_VOLUME_LANE)
			_context.add_icon_item(_icon("Curve"), "Add Pitch Automation (this instrument)", ADD_INSTRUMENT_PITCH_LANE)
		_context.add_icon_item(_icon("Remove"), "Delete Lane" if _context_resource is ChirpAutomation else "Delete", DELETE)
		_context.add_separator()
	_fill_add_menu(_context)
	_context.position = Vector2i(screen_position)
	_context.reset_size()
	_context.popup()


func _fill_add_menu(menu: PopupMenu) -> void:
	menu.add_icon_item(_icon("AudioStreamPlayer"), "Add Instrument", ADD_INSTRUMENT)
	if _view and _view.model.event:
		menu.add_icon_item(_icon("Curve"), "Add Volume Automation", ADD_VOLUME_LANE)
		menu.add_icon_item(_icon("Curve"), "Add Pitch Automation", ADD_PITCH_LANE)
		menu.add_icon_item(_icon("Curve"), "Add Pan Automation", ADD_PAN_LANE)
		_effect_menu.clear()
		var effects: Array[AudioEffect] = _view.model.event.effects
		for i in effects.size():
			for property in TimelineModel.effect_properties(effects[i]):
				_effect_menu.append({index = i, property = property.name, range = property.range})
				menu.add_icon_item(_icon("Curve"), "Add Effect Automation: %d %s %s" % [i + 1,
					effects[i].get_class().trim_prefix("AudioEffect"), property.name], ADD_EFFECT_LANE + _effect_menu.size() - 1)
	if _view and _view.model.is_sheet():
		return # parameter sheets have no markers
	menu.add_separator("Add Marker")
	for kind: int in ChirpMarker.Kind.values():
		menu.add_icon_item(_marker_icon(kind), ChirpMarker.Kind.keys()[kind].capitalize(), kind)


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
		DELETE_POINT:
			_view.delete_selected_point()
		RENAME:
			var index := _event.markers.find(_context_resource)
			if index >= 0:
				_start_rename(_context_resource, model.marker_rect(index))
		ADD_INSTRUMENT:
			var instrument := ChirpInstrument.new()
			instrument.start = at
			instrument.length = model.bar_length_at(at)
			_add_to("instruments", instrument, "Add Instrument")
		ADD_VOLUME_LANE, ADD_PITCH_LANE, ADD_PAN_LANE:
			_add_lane(id, at)
		ADD_INSTRUMENT_VOLUME_LANE, ADD_INSTRUMENT_PITCH_LANE:
			if _context_resource is ChirpInstrument:
				_add_lane(ADD_VOLUME_LANE if id == ADD_INSTRUMENT_VOLUME_LANE else ADD_PITCH_LANE, at, _context_resource)
		_:
			if id >= ADD_EFFECT_LANE:
				if id - ADD_EFFECT_LANE < _effect_menu.size():
					_add_lane(id, at)
			else:
				_add_marker(id, at)


## Adds an automation lane (volume, pitch, pan, or an effect property from the Add menu) with one
## point at [param at], at the property's current value: to [param instrument] (volume and pitch
## only), else to the event.
func _add_lane(id: int, at: float, instrument: ChirpInstrument = null) -> void:
	var model := _view.model
	var automation := ChirpAutomation.new()
	var start_value := 1.0
	match id:
		ADD_VOLUME_LANE:
			automation.target = ChirpAutomation.Target.VOLUME
		ADD_PITCH_LANE:
			automation.target = ChirpAutomation.Target.PITCH
		ADD_PAN_LANE:
			automation.target = ChirpAutomation.Target.PAN
			start_value = 0.0
		_:
			var item: Dictionary = _effect_menu[id - ADD_EFFECT_LANE]
			automation.target = ChirpAutomation.Target.EFFECT
			automation.effect_index = item.index
			automation.effect_property = item.property
			automation.value_range = item.range
			start_value = float(_event.effects[item.index].get(item.property))
	var span := automation.lane_range()
	start_value = clampf(start_value, span.x, span.y)
	if model.is_sheet():
		# A curve along the sheet parameter (an empty name follows it), spanning the property's range.
		automation.curve = Curve.new()
		automation.curve.min_value = span.x
		automation.curve.max_value = span.y
		model.lane_insert(automation, at, start_value)
	else:
		automation.source = ChirpAutomation.Source.TIMELINE
		automation.points = PackedVector2Array([Vector2(at, start_value)])
	if instrument:
		_add_to("automations", automation, "Add Instrument %s Automation" % model.automation_title(automation), instrument)
	else:
		_add_to("automations", automation, "Add %s Automation" % model.automation_title(automation))


func _add_marker(kind: int, at: float) -> void:
	var model := _view.model
	var marker := ChirpMarker.new()
	marker.kind = kind
	marker.position = at
	if marker.is_region():
		marker.end = at + model.bar_length_at(at) * 2.0
	if marker.kind == ChirpMarker.Kind.MARKER or marker.kind == ChirpMarker.Kind.DESTINATION:
		marker.name = "%s %d" % ["marker" if marker.kind == ChirpMarker.Kind.MARKER else "destination", _event.markers.size() + 1]
	_add_to("markers", marker, "Add %s" % ChirpMarker.Kind.keys()[kind].capitalize())


## Applies a TimelineModel.plan_drop() result as one undoable action.
func _on_drop(plan: Dictionary) -> void:
	if _event == null or _view.model.event == null:
		return
	if plan.action == "append":
		var instrument: ChirpInstrument = _event.instruments[plan.index]
		var before := instrument.streams.duplicate()
		var after := instrument.streams.duplicate()
		after.append_array(plan.streams)
		var undo_redo := _plugin.get_undo_redo()
		undo_redo.create_action("Add %d Sound%s to Playlist" % [plan.streams.size(), "" if plan.streams.size() == 1 else "s"])
		undo_redo.add_do_property(instrument, "streams", after)
		undo_redo.add_undo_property(instrument, "streams", before)
		undo_redo.add_do_method(self, "_changed", instrument)
		undo_redo.add_undo_method(self, "_changed", instrument)
		undo_redo.commit_action()
		_view.selected = instrument
		_on_item_selected(instrument)
		return
	var added: Array = plan.instruments
	var before: Array = _event.instruments
	var after := before.duplicate()
	after.append_array(added)
	_commit_array("instruments", before.duplicate(), after,
		"Add %d Instrument%s" % [added.size(), "" if added.size() == 1 else "s"])
	_view.selected = added[0]
	_on_item_selected(added[0])


## Shows a text field over [param marker] to rename it (or retarget a transition).
func _start_rename(marker: ChirpMarker, rect: Rect2) -> void:
	var property := TimelineModel.rename_property(marker)
	if property.is_empty():
		return
	if _rename_edit == null:
		_rename_edit = LineEdit.new()
		_rename_edit.select_all_on_focus = true
		_rename_edit.text_submitted.connect(func(_text: String) -> void: _finish_rename(true))
		_rename_edit.focus_exited.connect(func() -> void: _finish_rename(true))
		_rename_edit.gui_input.connect(func(input: InputEvent) -> void:
			if input is InputEventKey and input.pressed and input.keycode == KEY_ESCAPE:
				_finish_rename(false)
				_rename_edit.accept_event())
		_view.add_child(_rename_edit)
	_renaming = marker
	_rename_edit.placeholder_text = "Destination name" if property == "destination" else "Name"
	_rename_edit.text = marker.get(property)
	_rename_edit.position = Vector2(rect.position.x, rect.position.y - 2.0)
	_rename_edit.size = Vector2(maxf(rect.size.x, 160.0 * EditorInterface.get_editor_scale()), 0.0)
	_rename_edit.show()
	_rename_edit.grab_focus()


func _finish_rename(apply: bool) -> void:
	var marker := _renaming
	_renaming = null # before hiding: hiding drops focus, which calls this again
	if marker == null:
		return
	_rename_edit.hide()
	_view.grab_focus()
	if not apply:
		return
	var changes := _view.model.rename_changes(marker, _rename_edit.text)
	if changes.is_empty():
		return
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Rename Marker" if changes.size() == 1 else "Rename Destination and Transitions")
	for change in changes:
		undo_redo.add_do_property(change.resource, change.property, change.after)
		undo_redo.add_undo_property(change.resource, change.property, change.before)
	undo_redo.add_do_method(self, "_changed", _event)
	undo_redo.add_undo_method(self, "_changed", _event)
	undo_redo.commit_action()


## A small flag (point markers) or bar (regions) in the marker kind's timeline colour.
static func _marker_icon(kind: int) -> Texture2D:
	var unit := maxi(roundi(EditorInterface.get_editor_scale()), 1)
	var image := Image.create_empty(16 * unit, 16 * unit, false, Image.FORMAT_RGBA8)
	var color: Color = TimelineView.MARKER_COLORS[kind]
	if kind in [ChirpMarker.Kind.LOOP_REGION, ChirpMarker.Kind.TRANSITION_REGION, ChirpMarker.Kind.MAGNET_REGION]:
		image.fill_rect(Rect2i(Vector2i(1, 5) * unit, Vector2i(14, 6) * unit), Color(color, 0.45))
		image.fill_rect(Rect2i(Vector2i(1, 5) * unit, Vector2i(14, 2) * unit), color)
	else:
		image.fill_rect(Rect2i(Vector2i(3, 1) * unit, Vector2i(2, 14) * unit), color)
		image.fill_rect(Rect2i(Vector2i(5, 2) * unit, Vector2i(9, 6) * unit), color)
	return ImageTexture.create_from_image(image)


## Appends [param resource] to [param property] of [param owner] (the event by default), undoably.
func _add_to(property: String, resource: Resource, action: String, owner: Resource = null) -> void:
	owner = owner if owner else _event
	var before: Array = owner.get(property)
	var after := before.duplicate()
	after.append(resource)
	_commit_array(property, before.duplicate(), after, action, owner)
	_view.selected = resource
	_on_item_selected(resource)


func _delete(resource: Resource) -> void:
	if _event == null or resource == null:
		return
	var property := "instruments" if resource is ChirpInstrument \
		else "automations" if resource is ChirpAutomation else "markers"
	var owner: Resource = _event
	if resource is ChirpAutomation and resource not in _event.automations:
		for instrument in _event.instruments: # an instrument's own lane
			if instrument and resource in instrument.automations:
				owner = instrument
	var before: Array = owner.get(property)
	var after := before.duplicate()
	after.erase(resource)
	var noun := "Instrument" if resource is ChirpInstrument else "Automation Lane" if resource is ChirpAutomation else "Marker"
	_commit_array(property, before.duplicate(), after, "Delete %s" % noun, owner)
	_view.selected = null
	_view.selected_point = {}


## One undo action per click, drag or delete on an automation lane.
func _on_automation_edited(object: Object, property: String, before: Variant, after: Variant) -> void:
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Edit Automation")
	undo_redo.add_do_property(object, property, after)
	undo_redo.add_undo_property(object, property, before)
	undo_redo.add_do_method(self, "_changed", object)
	undo_redo.add_undo_method(self, "_changed", object)
	undo_redo.commit_action()


func _on_instrument_volume_changed(instrument: ChirpInstrument, before_db: float, after_db: float) -> void:
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Change Instrument Volume")
	undo_redo.add_do_property(instrument, "volume_db", after_db)
	undo_redo.add_undo_property(instrument, "volume_db", before_db)
	undo_redo.add_do_method(self, "_changed", instrument)
	undo_redo.add_undo_method(self, "_changed", instrument)
	undo_redo.commit_action()


func _commit_array(property: String, before: Array, after: Array, action: String, owner: Resource = null) -> void:
	owner = owner if owner else _event
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action(action)
	undo_redo.add_do_property(owner, property, after)
	undo_redo.add_undo_property(owner, property, before)
	undo_redo.add_do_method(self, "_changed", owner)
	undo_redo.add_undo_method(self, "_changed", owner)
	undo_redo.commit_action()


func _changed(resource: Resource) -> void:
	resource.emit_changed()
	resource.notify_property_list_changed()
	_view.queue_redraw()


func _seek(unit: float) -> void:
	var model := _view.model
	if model.is_sheet():
		# Auditions the crossfade: sets the sheet parameter (and its slider), then plays if needed,
		# so a fresh preview starts on the right layers.
		_preview.set_parameter_value(model.event.sheet_parameter, unit)
		if _preview.instance_of(model.event) == null:
			_preview.play()
		return
	if _preview.instance_of(model.event) == null:
		_preview.play()
	var instance := _preview.instance_of(model.event)
	if instance:
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


## Loaded (not preloaded) so a freshly pulled icon that isn't imported yet can't break the plugin.
static func _set_dock_icon(dock: EditorDock, file: String) -> void:
	var path: String = (dock.get_script() as Script).resource_path.get_base_dir().path_join("../icons").path_join(file).simplify_path()
	if ResourceLoader.exists(path):
		dock.dock_icon = load(path)
		dock.force_show_icon = true
