class_name ChirpEmitterCore
extends RefCounted
## Shared behaviour of ChirpEmitter2D and ChirpEmitter3D, and the trigger wiring used by the
## parameter trigger nodes too.

enum Trigger {
	NONE, ## Only via play() / stop() from script.
	READY, ## When the emitter enters the scene.
	EXIT_TREE, ## When the emitter leaves the scene (e.g. is freed).
	SHOWN, ## When the node becomes visible (nodes without visibility: their trigger source).
	HIDDEN, ## When the node becomes hidden (nodes without visibility: their trigger source).
	ENTERED, ## Trigger source Area / RigidBody: a body or area entered (filtered by trigger group).
	EXITED, ## Trigger source Area / RigidBody: a body or area exited (filtered by trigger group).
	MOUSE_ENTERED, ## Trigger source CollisionObject / Control: pointer entered.
	MOUSE_EXITED, ## Trigger source CollisionObject / Control: pointer exited.
	MOUSE_DOWN, ## Trigger source CollisionObject / Control: left button pressed (or touch).
	MOUSE_UP, ## Trigger source CollisionObject / Control: left button released (or touch).
}

var _host # the emitter node (untyped: its exported properties are read dynamically); its exported properties configure this core
var _instances: Array[ChirpEventInstance] = []
var _played := false


func _init(host) -> void:
	_host = host


func setup() -> void:
	wire(_host.play_on, play)
	wire(_host.stop_on, stop)
	if _host.preload_event and _host.event == null and not _host.event_path.is_empty():
		_chirp().events.preload_events(_host.event_path)


func on_exit_tree() -> void:
	if _host.play_on == Trigger.EXIT_TREE:
		play()
	if _host.stop_on == Trigger.EXIT_TREE:
		stop()
	# Looping sounds belong to the emitter; one-shots are left to finish where they are.
	for instance in _instances:
		if instance.is_playing() and not instance.get_event().is_one_shot():
			instance.stop(_host.allow_fadeout)


func play() -> void:
	var event := _resolve_event()
	if event == null:
		return
	if _host.trigger_once and _played:
		return
	_played = true
	_prune()
	if not event.is_one_shot():
		# A looping event restarts rather than stacking.
		for instance in _instances:
			if instance.is_playing():
				instance.start()
				return
	var instance: ChirpEventInstance = _chirp().create_instance(event)
	if instance == null:
		return
	instance.attach_to(_host)
	for parameter_name: String in _host.parameters:
		instance.set_parameter(parameter_name, _host.parameters[parameter_name])
	_apply_attenuation(instance)
	instance.start()
	_instances.append(instance)


## Stops the most recently started instance.
func stop() -> void:
	for i in range(_instances.size() - 1, -1, -1):
		if _instances[i].is_playing():
			_instances[i].stop(_host.allow_fadeout)
			return


func set_parameter(parameter_name: String, value: float) -> void:
	_host.parameters[parameter_name] = value
	for instance in _instances:
		if instance.is_playing():
			instance.set_parameter(parameter_name, value)


func is_playing() -> bool:
	for instance in _instances:
		if instance.is_playing():
			return true
	return false


func _chirp() -> Node:
	return _host.get_node("/root/Chirp")


func _resolve_event() -> ChirpEvent:
	if _host.event:
		return _host.event
	if _host.event_path.is_empty():
		push_warning("%s: no event assigned." % _host.get_path())
		return null
	return _chirp().events.get_event(_host.event_path)


func _prune() -> void:
	_instances.assign(_instances.filter(func(i: ChirpEventInstance) -> bool:
		return i.is_playing() or not i.get_event().is_one_shot()))


func _apply_attenuation(instance: ChirpEventInstance) -> void:
	if not _host.override_attenuation:
		return
	if _host is Node2D:
		instance.set_attenuation_2d(_host.max_distance, _host.attenuation)
	else:
		instance.set_attenuation_3d(_host.unit_size, _host.max_distance)


func _source() -> Node:
	var path: NodePath = _host.trigger_source
	return _host.get_parent() if path.is_empty() else _host.get_node_or_null(path)


func _matches_group(other: Node) -> bool:
	var group: StringName = _host.trigger_group
	return group.is_empty() or other.is_in_group(group)


## Calls [param action] whenever [param trigger] fires, using the host's trigger_source and
## trigger_group. EXIT_TREE is left to the host's _exit_tree().
func wire(trigger: Trigger, action: Callable) -> void:
	match trigger:
		Trigger.NONE, Trigger.EXIT_TREE:
			pass
		Trigger.READY:
			action.call_deferred()
		Trigger.SHOWN, Trigger.HIDDEN:
			var want_visible := trigger == Trigger.SHOWN
			var visual: Node = _host if _host.has_signal(&"visibility_changed") else _source()
			if visual == null or not visual.has_signal(&"visibility_changed"):
				_bad_source(trigger, "a CanvasItem or Node3D")
				return
			visual.visibility_changed.connect(func() -> void:
				if visual.is_visible_in_tree() == want_visible:
					action.call())
		Trigger.ENTERED, Trigger.EXITED:
			_wire_contact(trigger == Trigger.ENTERED, action)
		Trigger.MOUSE_ENTERED, Trigger.MOUSE_EXITED:
			var source = _source()
			if not (source is CollisionObject2D or source is CollisionObject3D or source is Control):
				_bad_source(trigger, "a CollisionObject2D/3D or Control")
				return
			if source is CollisionObject2D:
				source.input_pickable = true
			elif source is CollisionObject3D:
				source.input_ray_pickable = true
			var signal_name := &"mouse_entered" if trigger == Trigger.MOUSE_ENTERED else &"mouse_exited"
			source.connect(signal_name, action)
		Trigger.MOUSE_DOWN, Trigger.MOUSE_UP:
			_wire_click(trigger == Trigger.MOUSE_DOWN, action)


func _wire_contact(entered: bool, action: Callable) -> void:
	var source = _source()
	var on_contact := func(other: Node) -> void:
		if _matches_group(other):
			action.call()
	if source is Area2D or source is Area3D:
		source.connect(&"body_entered" if entered else &"body_exited", on_contact)
		source.connect(&"area_entered" if entered else &"area_exited", on_contact)
	elif source is RigidBody2D or source is RigidBody3D:
		source.contact_monitor = true
		source.max_contacts_reported = maxi(source.max_contacts_reported, 1)
		source.connect(&"body_entered" if entered else &"body_exited", on_contact)
	else:
		_bad_source(Trigger.ENTERED if entered else Trigger.EXITED, "an Area2D/3D or RigidBody2D/3D")


func _wire_click(pressed: bool, action: Callable) -> void:
	var source = _source()
	var is_click := func(event: InputEvent) -> bool:
		return event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed == pressed
	if source is Control:
		source.gui_input.connect(func(event: InputEvent) -> void:
			if is_click.call(event):
				action.call())
	elif source is CollisionObject2D:
		source.input_pickable = true
		source.input_event.connect(func(_viewport: Node, event: InputEvent, _shape: int) -> void:
			if is_click.call(event):
				action.call())
	elif source is CollisionObject3D:
		source.input_ray_pickable = true
		source.input_event.connect(func(_camera: Node, event: InputEvent, _position: Vector3,
				_normal: Vector3, _shape: int) -> void:
			if is_click.call(event):
				action.call())
	else:
		_bad_source(Trigger.MOUSE_DOWN if pressed else Trigger.MOUSE_UP, "a CollisionObject2D/3D or Control")


func _bad_source(trigger: Trigger, expected: String) -> void:
	push_warning("%s: trigger %s needs its trigger source to be %s." % [
		_host.get_path(), Trigger.keys()[trigger], expected])
