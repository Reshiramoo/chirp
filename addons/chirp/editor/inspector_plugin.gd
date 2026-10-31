@tool
extends EditorInspectorPlugin
## Adds a Preview button to events and snapshots, and a searchable picker for
## the emitters' event_path property.

const EventPathProperty := preload("event_path_property.gd")

var chirp: Node # the editor's preview copy of Chirp
var preview: Callable # preview(item) plays an event or snapshot in the preview dock


func _can_handle(object: Object) -> bool:
	return object is ChirpEvent or object is ChirpSnapshot \
		or object is ChirpEmitter2D or object is ChirpEmitter3D


func _parse_begin(object: Object) -> void:
	if not (object is ChirpEvent or object is ChirpSnapshot):
		return
	var button := Button.new()
	button.text = "Preview"
	var theme := EditorInterface.get_editor_theme()
	button.icon = theme.get_icon(&"Play", &"EditorIcons")
	button.tooltip_text = "Play this in the Chirp Preview dock"
	button.pressed.connect(func() -> void: preview.call(object))
	add_custom_control(button)


func _parse_property(object: Object, _type: Variant.Type, name: String, _hint_type: PropertyHint,
		_hint_string: String, _usage_flags: int, _wide: bool) -> bool:
	if name == "event_path" and (object is ChirpEmitter2D or object is ChirpEmitter3D):
		var editor := EventPathProperty.new()
		editor.chirp = chirp
		add_property_editor(name, editor)
		return true
	return false
