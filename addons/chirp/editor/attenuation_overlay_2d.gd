@tool
extends RefCounted
## Draws a selected ChirpEmitter2D's max distance (and min distance, with a Chirp roll-off) over
## the 2D editor viewport, with a handle to drag the max when override_attenuation is on (dimmed
## event values otherwise).

const AttenuationGizmo3D := preload("attenuation_gizmo_3d.gd")
const COLOR := Color(0.4, 0.72, 1.0)
const MIN_COLOR := Color(1.0, 0.78, 0.35) # min distance of a Chirp roll-off, as the 3D gizmo's unit size
const HANDLE_RADIUS := 6.0

var plugin: EditorPlugin
var chirp: Node # the editor's preview copy of Chirp
var emitter: ChirpEmitter2D

var _dragging := false
var _drag_from := 0.0


func draw(overlay: Control) -> void:
	if not _valid():
		return
	var distances := AttenuationGizmo3D.attenuation(emitter, chirp)
	if distances.is_empty() or distances.max_distance <= 0.0:
		return
	var transform := _screen_transform()
	var center := transform.origin
	var radius: float = (transform.basis_xform(Vector2(distances.max_distance, 0))).length()
	var color := COLOR if emitter.override_attenuation else Color(COLOR, 0.35)
	overlay.draw_arc(center, radius, 0.0, TAU, 128, color, 2.0 * EditorInterface.get_editor_scale(), true)
	if distances.get("min_distance", 0.0) > 0.0:
		var min_radius: float = (transform.basis_xform(Vector2(distances.min_distance, 0))).length()
		overlay.draw_arc(center, min_radius, 0.0, TAU, 96, Color(MIN_COLOR, color.a),
			1.5 * EditorInterface.get_editor_scale(), true)
	if emitter.override_attenuation:
		overlay.draw_circle(_handle_position(), HANDLE_RADIUS * EditorInterface.get_editor_scale(), COLOR)


## Returns true when the input was used to drag the handle.
func input(event: InputEvent) -> bool:
	if not _valid() or not emitter.override_attenuation:
		return false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and event.position.distance_to(_handle_position()) <= HANDLE_RADIUS * 2.0 * EditorInterface.get_editor_scale():
			_dragging = true
			_drag_from = emitter.max_distance
			return true
		if not event.pressed and _dragging:
			_dragging = false
			var undo_redo := plugin.get_undo_redo()
			undo_redo.create_action("Change Chirp Emitter Max Distance")
			undo_redo.add_do_property(emitter, "max_distance", emitter.max_distance)
			undo_redo.add_undo_property(emitter, "max_distance", _drag_from)
			undo_redo.add_do_method(plugin, "update_overlays")
			undo_redo.add_undo_method(plugin, "update_overlays")
			undo_redo.commit_action()
			return true
	elif event is InputEventMouseMotion and _dragging:
		var local := _screen_transform().affine_inverse() * (event.position as Vector2)
		emitter.max_distance = snappedf(maxf(local.length(), 1.0), 1.0)
		plugin.update_overlays()
		return true
	return false


func _handle_position() -> Vector2:
	return _screen_transform() * Vector2(emitter.max_distance, 0)


func _screen_transform() -> Transform2D:
	return emitter.get_viewport_transform() * emitter.get_global_transform()


func _valid() -> bool:
	return emitter != null and is_instance_valid(emitter) and emitter.is_inside_tree()
