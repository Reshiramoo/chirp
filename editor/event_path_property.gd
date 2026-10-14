@tool
extends EditorProperty
## Inspector editor for an "event:/..." path: a text field plus a searchable list of every
## event Chirp knows about.

var chirp: Node # the editor's preview copy of Chirp

var _field := LineEdit.new()
var _popup := PopupPanel.new()
var _search := LineEdit.new()
var _list := ItemList.new()
var _updating := false


func _init() -> void:
	var row := HBoxContainer.new()
	add_child(row)
	_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field.placeholder_text = "event:/..."
	_field.text_submitted.connect(func(text: String) -> void: _set_path(text))
	_field.focus_exited.connect(func() -> void: _set_path(_field.text))
	row.add_child(_field)
	add_focusable(_field)
	var pick := Button.new()
	pick.icon = EditorInterface.get_editor_theme().get_icon(&"Search", &"EditorIcons")
	pick.tooltip_text = "Pick an event"
	pick.pressed.connect(_open_picker)
	row.add_child(pick)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(320, 360)
	_popup.add_child(box)
	_search.placeholder_text = "Filter events"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_text: String) -> void: _fill_list())
	box.add_child(_search)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_activated.connect(func(index: int) -> void:
		_set_path(_list.get_item_text(index))
		_popup.hide())
	box.add_child(_list)
	add_child(_popup)


func _update_property() -> void:
	_updating = true
	_field.text = get_edited_object()[get_edited_property()]
	_updating = false


func _set_path(path: String) -> void:
	if _updating or path == get_edited_object()[get_edited_property()]:
		return
	emit_changed(get_edited_property(), path)


func _open_picker() -> void:
	_search.text = ""
	_fill_list()
	_popup.popup_centered()
	_search.grab_focus()


func _fill_list() -> void:
	_list.clear()
	var paths := Array(chirp.events.get_event_paths())
	paths.sort()
	for path: String in paths:
		if _search.text.is_empty() or path.findn(_search.text) != -1:
			_list.add_item(path)
