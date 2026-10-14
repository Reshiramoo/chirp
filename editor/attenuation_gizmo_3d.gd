@tool
extends EditorNode3DGizmoPlugin
## Spheres for a ChirpEmitter3D's unit size (amber) and max distance (blue). With
## override_attenuation on they're bright and have handles; otherwise they show the
## event's values, dimmed.

const UNIT_COLOR := Color(1.0, 0.78, 0.35)
const MAX_COLOR := Color(0.4, 0.72, 1.0)
const SEGMENTS := 64

var chirp: Node # the editor's preview copy of Chirp, to resolve event paths


func _init() -> void:
	create_material("unit", UNIT_COLOR)
	create_material("unit_dim", Color(UNIT_COLOR, 0.3))
	create_material("max", MAX_COLOR)
	create_material("max_dim", Color(MAX_COLOR, 0.3))
	create_handle_material("handles")


func _get_gizmo_name() -> String:
	return "ChirpEmitter3D"


func _has_gizmo(node: Node3D) -> bool:
	return node is ChirpEmitter3D


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var emitter: ChirpEmitter3D = gizmo.get_node_3d()
	var distances := attenuation(emitter, chirp)
	if distances.is_empty():
		return
	var suffix := "" if emitter.override_attenuation else "_dim"
	if distances.unit_size > 0.0:
		gizmo.add_lines(_sphere_lines(distances.unit_size), get_material("unit" + suffix, gizmo))
	if distances.max_distance > 0.0:
		gizmo.add_lines(_sphere_lines(distances.max_distance), get_material("max" + suffix, gizmo))
	if emitter.override_attenuation:
		var max_handle: float = distances.max_distance if distances.max_distance > 0.0 else distances.unit_size * 2.0
		gizmo.add_handles(PackedVector3Array([Vector3(distances.unit_size, 0, 0), Vector3(max_handle, 0, 0)]),
			get_material("handles", gizmo), PackedInt32Array([0, 1]))


func _get_handle_name(_gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool) -> String:
	return "Unit Size" if handle_id == 0 else "Max Distance"


func _get_handle_value(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool) -> Variant:
	var emitter: ChirpEmitter3D = gizmo.get_node_3d()
	return emitter.unit_size if handle_id == 0 else emitter.max_distance


func _set_handle(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool, camera: Camera3D, screen_position: Vector2) -> void:
	var emitter: ChirpEmitter3D = gizmo.get_node_3d()
	var transform := emitter.global_transform
	var ray_from := camera.project_ray_origin(screen_position)
	var ray_to := ray_from + camera.project_ray_normal(screen_position) * 4096.0
	var axis := transform.basis.x.normalized() * 4096.0
	var closest := Geometry3D.get_closest_points_between_segments(ray_from, ray_to, transform.origin - axis, transform.origin + axis)
	var distance := maxf(absf((transform.affine_inverse() * closest[1]).x), 0.01)
	emitter.set("unit_size" if handle_id == 0 else "max_distance", snappedf(distance, 0.01))
	emitter.update_gizmos()


func _commit_handle(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool, restore: Variant, cancel: bool) -> void:
	var emitter: ChirpEmitter3D = gizmo.get_node_3d()
	var property := "unit_size" if handle_id == 0 else "max_distance"
	if cancel:
		emitter.set(property, restore)
	else:
		var undo_redo := EditorInterface.get_editor_undo_redo()
		undo_redo.create_action("Change Chirp Emitter %s" % property.capitalize())
		undo_redo.add_do_property(emitter, property, emitter.get(property))
		undo_redo.add_undo_property(emitter, property, restore)
		undo_redo.add_do_method(emitter, "update_gizmos")
		undo_redo.add_undo_method(emitter, "update_gizmos")
		undo_redo.commit_action()
	emitter.update_gizmos()


## The attenuation an emitter will use: its override, or its event's values.
## {unit_size, max_distance} for 3D, {max_distance} for 2D; empty when unknown.
static func attenuation(emitter: Node, preview_chirp: Node) -> Dictionary:
	var is_3d := emitter is ChirpEmitter3D
	if emitter.override_attenuation:
		return {unit_size = emitter.unit_size, max_distance = emitter.max_distance} if is_3d \
			else {max_distance = emitter.max_distance}
	var event: ChirpEvent = emitter.event
	if event == null and not emitter.event_path.is_empty() and preview_chirp \
			and emitter.event_path in preview_chirp.events.get_event_paths():
		event = preview_chirp.events.get_event(emitter.event_path)
	if event == null:
		return {}
	return {unit_size = event.unit_size_3d, max_distance = event.max_distance_3d} if is_3d \
		else {max_distance = event.max_distance_2d}


static func _sphere_lines(radius: float) -> PackedVector3Array:
	var lines := PackedVector3Array()
	for plane in 3:
		for i in SEGMENTS:
			var a := TAU * i / SEGMENTS
			var b := TAU * (i + 1) / SEGMENTS
			for angle in [a, b]:
				var point := Vector2(cos(angle), sin(angle)) * radius
				match plane:
					0:
						lines.append(Vector3(point.x, point.y, 0))
					1:
						lines.append(Vector3(point.x, 0, point.y))
					_:
						lines.append(Vector3(0, point.x, point.y))
	return lines
