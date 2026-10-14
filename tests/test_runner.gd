extends Node
## Headless test suite for the Audio Events addon.
## Run: godot --headless --path . res://tests/test_runner.tscn


var _failures: Array[String] = []
var _current := ""
var _checks := 0


func _ready() -> void:
	_add_bus("SFX", "Master")
	_add_bus("UI", "SFX")
	var tests: Array[String] = []
	for method in get_method_list():
		if method.name.begins_with("test_"):
			tests.append(method.name)
	for test_name in tests:
		_current = test_name
		_reset()
		await call(test_name)
	await _wait(0.05)
	print("\n%d tests, %d checks, %d failures" % [tests.size(), _checks, _failures.size()])
	for failure in _failures:
		printerr("  FAIL " + failure)
	get_tree().quit(1 if _failures else 0)


# --- tests -----------------------------------------------------------------------

func test_event_path_lookup() -> void:
	var event := AudioEvents.get_event("event:/sfx/flap")
	check(event != null, "event:/sfx/flap found by scanning events_dir")
	if event:
		check(is_equal_approx(event.volume_db, -3.0), "loaded event keeps its properties")
		check(event.bus == "bus:/SFX", "loaded event keeps its bus")
	AudioEvents.register_event("event:/code/beep", _event([_instrument([_wav(0.1)])]))
	check(AudioEvents.create_instance("event:/code/beep") != null, "register_event makes code events addressable")


func test_one_shot_ends_and_is_destroyed() -> void:
	var event := _event([_instrument([_wav(0.1)])])
	var destroyed := [false]
	var instance := AudioEvents.play_one_shot(event)
	instance.destroyed.connect(func() -> void: destroyed[0] = true)
	check(instance.is_playing(), "one-shot plays")
	check(instance._voices.size() == 1, "one voice created")
	await _wait(0.6)
	check(not instance.is_playing(), "one-shot ends naturally")
	check(destroyed[0] and not instance.is_valid(), "released one-shot is destroyed after ending")
	check(AudioEvents.get_active_instances().is_empty(), "no active instances left")
	check(AudioEvents._voice_root.get_child_count() == 0, "voice players freed")


func test_looping_until_stopped() -> void:
	var instrument := _instrument([_wav(0.05)])
	instrument.loop = true
	var instance := AudioEvents.create_instance(_event([instrument]))
	instance.start()
	await _wait(0.4)
	check(instance.is_playing(), "looping instrument keeps the event playing")
	instance.stop(false)
	check(instance.get_state() == AudioEventInstance.State.STOPPED, "stop(false) stops immediately")
	check(instance.is_valid(), "unreleased instance survives stopping")
	instance.start()
	check(instance.is_playing(), "stopped instance can start again")
	instance.stop(false)


func test_parameter_kinds() -> void:
	var event := _event([_looping_instrument()])
	event.parameters = [
		_param("Speed", AudioEventParameter.Kind.CONTINUOUS, 0, 10),
		_param("Gear", AudioEventParameter.Kind.DISCRETE, 0, 4),
		_param("Surface", AudioEventParameter.Kind.LABELED, 0, 0, ["Grass", "Stone"]),
	]
	var instance := AudioEvents.create_instance(event)
	instance.set_parameter("speed", 15.0)
	check(is_equal_approx(instance.get_parameter("Speed"), 10.0), "continuous clamps to max, name case-insensitive")
	instance.set_parameter("Gear", 2.6)
	check(is_equal_approx(instance.get_parameter("Gear"), 3.0), "discrete rounds")
	instance.set_parameter_by_label("Surface", "stone")
	check(is_equal_approx(instance.get_parameter("Surface"), 1.0), "labeled set by label")


func test_seek_speed() -> void:
	var event := _event([_looping_instrument()])
	var parameter := _param("Intensity", AudioEventParameter.Kind.CONTINUOUS, 0, 10)
	parameter.seek_speed = 10.0
	event.parameters = [parameter]
	var instance := AudioEvents.create_instance(event)
	instance.start()
	instance.set_parameter("Intensity", 10.0)
	await _wait(0.3)
	var mid := instance.get_parameter("Intensity")
	check(mid > 0.5 and mid < 9.5, "value glides toward target (got %.2f)" % mid)
	await _wait(1.0)
	check(is_equal_approx(instance.get_parameter("Intensity"), 10.0), "value reaches target")
	instance.stop(false)


func test_volume_automation() -> void:
	var event := _event([_looping_instrument()])
	event.parameters = [_param("Distance", AudioEventParameter.Kind.CONTINUOUS, 0, 1)]
	event.automations = [_automation("Distance", AudioEventAutomation.Target.VOLUME, [Vector2(0, 0), Vector2(1, 1)])]
	var instance := AudioEvents.create_instance(event)
	instance.start()
	var player: AudioStreamPlayer = instance._voices[0].player
	check(player.volume_db <= -79.0, "curve at 0 silences the voice (got %.1f dB)" % player.volume_db)
	instance.set_parameter("Distance", 1.0)
	await _frames(2)
	check(absf(player.volume_db) < 0.1, "curve at 1 gives full volume (got %.1f dB)" % player.volume_db)
	instance.stop(false)


func test_global_parameter_pitch_automation() -> void:
	var config := _config()
	config.global_parameters = [_param("Speed", AudioEventParameter.Kind.CONTINUOUS, 0, 1)]
	AudioEvents.apply_config(config)
	var event := _event([_looping_instrument()])
	var automation := _automation("Speed", AudioEventAutomation.Target.PITCH, [Vector2(0, 1), Vector2(1, 2)], 2.0)
	automation.global = true
	event.automations = [automation]
	var instance := AudioEvents.create_instance(event)
	instance.start()
	AudioEvents.set_global_parameter("Speed", 1.0)
	await _frames(2)
	var player: AudioStreamPlayer = instance._voices[0].player
	check(is_equal_approx(player.pitch_scale, 2.0), "global parameter drives pitch (got %.2f)" % player.pitch_scale)
	instance.stop(false)


func test_envelope_fadeout() -> void:
	var event := _event([_looping_instrument()])
	event.envelope = AudioEventEnvelope.new()
	event.envelope.release = 0.2
	var instance := AudioEvents.create_instance(event)
	instance.start()
	await _frames(1)
	instance.stop()
	check(instance.get_state() == AudioEventInstance.State.STOPPING, "stop() with release fades out")
	await _wait(0.1)
	var player: AudioStreamPlayer = instance._voices[0].player
	check(player.volume_db < -1.0, "volume is falling during release (got %.1f dB)" % player.volume_db)
	await _wait(0.3)
	check(instance.get_state() == AudioEventInstance.State.STOPPED, "stopped after release")
	instance.start()
	instance.stop(false)
	check(instance.get_state() == AudioEventInstance.State.STOPPED, "stop(false) skips the release")


func test_envelope_attack() -> void:
	var event := _event([_looping_instrument()])
	event.envelope = AudioEventEnvelope.new()
	event.envelope.attack = 0.5
	var instance := AudioEvents.create_instance(event)
	instance.start()
	var player: AudioStreamPlayer = instance._voices[0].player
	check(player.volume_db <= -79.0, "attack starts silent")
	await _wait(0.7)
	check(absf(player.volume_db) < 0.1, "attack reaches full volume")
	instance.stop(false)


func test_max_instances_steal_oldest() -> void:
	var event := _event([_looping_instrument()])
	event.max_instances = 2
	var a := AudioEvents.create_instance(event)
	var b := AudioEvents.create_instance(event)
	var c := AudioEvents.create_instance(event)
	a.start()
	b.start()
	c.start()
	check(not a.is_playing() and b.is_playing() and c.is_playing(), "oldest instance is stolen")
	event.stealing = AudioEvent.Stealing.NONE
	a.start()
	check(not a.is_playing(), "stealing NONE refuses the new instance")
	b.stop(false)
	c.stop(false)


func test_max_instances_steal_quietest() -> void:
	var event := _event([_looping_instrument()])
	event.max_instances = 2
	event.stealing = AudioEvent.Stealing.QUIETEST
	var loud := AudioEvents.create_instance(event)
	var quiet := AudioEvents.create_instance(event)
	quiet.volume = 0.1
	loud.start()
	quiet.start()
	var newest := AudioEvents.create_instance(event)
	newest.start()
	check(loud.is_playing() and not quiet.is_playing() and newest.is_playing(), "quietest instance is stolen")
	loud.stop(false)
	newest.stop(false)


func test_cooldown() -> void:
	var event := _event([_instrument([_wav(0.1)])])
	event.cooldown = 0.5
	var first := AudioEvents.play_one_shot(event)
	var second := AudioEvents.play_one_shot(event)
	check(first.is_playing() and not second.is_playing(), "second start inside cooldown is ignored")
	await _wait(0.6)
	check(AudioEvents.play_one_shot(event).is_playing(), "plays again after cooldown")


func test_consecutive_sheet() -> void:
	var first_stream := _wav(0.1)
	var second_stream := _wav(0.1)
	var event := _event([_instrument([first_stream]), _instrument([second_stream])])
	event.sheet_mode = AudioEvent.SheetMode.CONSECUTIVE
	var instance := AudioEvents.create_instance(event)
	instance.start()
	var order: Array = []
	var overlapped := false
	for i in 120:
		overlapped = overlapped or instance._voices.size() > 1
		for voice in instance._voices:
			if order.is_empty() or order[-1] != voice.player.stream:
				order.append(voice.player.stream)
		if not instance.is_playing():
			break
		await _frames(1)
	check(order == [first_stream, second_stream], "instruments play in order")
	check(not overlapped, "never more than one at a time")
	check(not instance.is_playing(), "event ends after the last instrument")


func test_instrument_delay_and_probability() -> void:
	var delayed := _instrument([_wav(0.1)])
	delayed.delay = 0.2
	var never := _instrument([_wav(0.1)])
	never.probability = 0.0
	var instance := AudioEvents.create_instance(_event([delayed, never]))
	instance.start()
	check(instance._voices.is_empty() and instance.is_playing(), "delayed instrument waits, event stays alive")
	await _wait(0.3)
	check(instance._voices.size() == 1, "delayed instrument triggers; 0% instrument never does")
	instance.stop(false)


func test_shuffle_never_repeats() -> void:
	var streams: Array[AudioStream] = [_wav(0.1), _wav(0.1), _wav(0.1)]
	var instrument := _instrument(streams)
	var seen := {}
	var previous: AudioStream = null
	var repeated := false
	for i in 60:
		var stream := instrument.pick_stream()
		repeated = repeated or stream == previous
		previous = stream
		seen[stream] = true
	check(not repeated, "shuffle never repeats back-to-back")
	check(seen.size() == 3, "shuffle uses every entry")


func test_buses_and_vcas() -> void:
	var config := _config()
	var vca := AudioEventVCA.new()
	vca.name = "Effects"
	vca.buses = PackedStringArray(["bus:/SFX"])
	config.vcas = [vca]
	AudioEvents.apply_config(config)
	var sfx := AudioServer.get_bus_index("SFX")
	AudioEvents.set_bus_volume("bus:/SFX", 1.0)
	AudioEvents.set_vca_volume("Effects", 0.5)
	check(is_equal_approx(snappedf(AudioServer.get_bus_volume_db(sfx), 0.01), -6.02), "VCA scales its buses")
	AudioEvents.set_bus_volume("bus:/SFX", 0.5)
	check(is_equal_approx(snappedf(AudioServer.get_bus_volume_db(sfx), 0.01), -12.04), "bus volume and VCA multiply")
	AudioEvents.set_vca_volume("Effects", 1.0)
	check(is_equal_approx(snappedf(AudioServer.get_bus_volume_db(sfx), 0.01), -6.02), "VCA back to 1 leaves bus volume")
	check(is_equal_approx(AudioEvents.get_bus_volume("bus:/SFX"), 0.5), "get_bus_volume ignores VCAs")
	AudioEvents.set_bus_volume("bus:/SFX", 1.0)

	var event := _event([_looping_instrument()])
	event.bus = "bus:/SFX/UI"
	var instance := AudioEvents.create_instance(event)
	instance.start()
	check(instance._voices[0].player.bus == &"UI", "bus path resolves to the Godot bus")
	instance.stop(false)


func test_bus_pause_and_stop() -> void:
	var event := _event([_looping_instrument()])
	event.bus = "bus:/SFX/UI"
	var instance := AudioEvents.create_instance(event)
	instance.start()
	AudioEvents.set_bus_paused("bus:/SFX", true)
	await _frames(2)
	check(instance._voices[0].player.stream_paused, "pausing a parent bus pauses child-bus events")
	AudioEvents.set_bus_paused("bus:/SFX", false)
	await _frames(2)
	check(not instance._voices[0].player.stream_paused, "unpausing resumes")
	AudioEvents.pause_all(true)
	await _frames(2)
	check(instance._voices[0].player.stream_paused, "pause_all pauses")
	AudioEvents.pause_all(false)
	AudioEvents.stop_all_bus_events("bus:/SFX", false)
	check(not instance.is_playing(), "stop_all_bus_events stops child-bus events")


func test_spatial_one_shot_2d() -> void:
	var instance := AudioEvents.play_one_shot(_event([_instrument([_wav(0.3)])]), Vector2(100, 50))
	var player = instance._voices[0].player
	check(player is AudioStreamPlayer2D, "Vector2 position uses a 2D player")
	check(player.global_position == Vector2(100, 50), "2D player placed at position")
	var instance_3d := AudioEvents.play_one_shot(_event([_instrument([_wav(0.3)])]), Vector3(1, 2, 3))
	check(instance_3d._voices[0].player is AudioStreamPlayer3D, "Vector3 position uses a 3D player")


func test_emitter_one_shot_and_loop() -> void:
	var one_shot := _emitter(_event([_instrument([_wav(0.3)])]))
	add_child(one_shot)
	one_shot.play()
	one_shot.play()
	check(AudioEvents.get_active_instances(one_shot.event).size() == 2, "one-shot emitter stacks instances")
	one_shot.stop()
	check(AudioEvents.get_active_instances(one_shot.event).size() == 1, "stop() stops only the newest")

	var looping := _emitter(_event([_looping_instrument()]))
	add_child(looping)
	looping.play()
	looping.play()
	check(AudioEvents.get_active_instances(looping.event).size() == 1, "looping emitter restarts instead of stacking")
	looping.position = Vector2(300, 0)
	await _frames(2)
	var player = AudioEvents.get_active_instances(looping.event)[0]._voices[0].player
	check(player.global_position == Vector2(300, 0), "voice follows the emitter")
	var looping_event := looping.event
	looping.queue_free()
	await _frames(1)
	check(AudioEvents.get_active_instances(looping_event).is_empty(), "freeing the emitter stops its loop")
	one_shot.queue_free()


func test_emitter_triggers() -> void:
	var on_ready := _emitter(_event([_looping_instrument()]))
	on_ready.play_on = AudioEventEmitterCore.Trigger.READY
	add_child(on_ready)
	await _frames(1)
	check(on_ready.is_playing(), "READY trigger plays")
	on_ready.queue_free()

	var area := Area2D.new()
	add_child(area)
	var on_enter := _emitter(_event([_looping_instrument()]))
	on_enter.play_on = AudioEventEmitterCore.Trigger.ENTERED
	on_enter.stop_on = AudioEventEmitterCore.Trigger.EXITED
	on_enter.trigger_group = &"player"
	area.add_child(on_enter)
	var stranger := Node2D.new()
	var hero := Node2D.new()
	hero.add_to_group(&"player")
	area.body_entered.emit(stranger)
	check(not on_enter.is_playing(), "group filter ignores other bodies")
	area.body_entered.emit(hero)
	check(on_enter.is_playing(), "ENTERED trigger plays for the group")
	area.body_exited.emit(hero)
	check(not on_enter.is_playing(), "EXITED trigger stops")

	var once := _emitter(_event([_instrument([_wav(0.3)])]))
	once.trigger_once = true
	add_child(once)
	once.play()
	once.play()
	check(AudioEvents.get_active_instances(once.event).size() == 1, "trigger_once ignores later plays")

	var button := Button.new()
	add_child(button)
	var on_click := _emitter(_event([_instrument([_wav(0.3)])]))
	on_click.play_on = AudioEventEmitterCore.Trigger.MOUSE_DOWN
	button.add_child(on_click)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	button.gui_input.emit(click)
	check(on_click.is_playing(), "MOUSE_DOWN trigger on a Control plays")

	for node: Node in [area, stranger, hero, once, button]:
		node.queue_free()


func test_emitter_parameters() -> void:
	var event := _event([_looping_instrument()])
	event.parameters = [_param("Wind", AudioEventParameter.Kind.CONTINUOUS, 0, 1)]
	var emitter := _emitter(event)
	emitter.parameters = {"Wind": 0.25}
	add_child(emitter)
	emitter.play()
	var instance: AudioEventInstance = AudioEvents.get_active_instances(event)[0]
	check(is_equal_approx(instance.get_parameter("Wind"), 0.25), "emitter applies initial parameters")
	emitter.set_parameter("Wind", 0.75)
	check(is_equal_approx(instance.get_parameter("Wind"), 0.75), "emitter forwards parameter changes")
	emitter.queue_free()


# --- helpers -----------------------------------------------------------------------

func check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   %s: %s" % [_current, message])
	else:
		_failures.append("%s: %s" % [_current, message])
		printerr("  FAIL %s: %s" % [_current, message])


func _reset() -> void:
	for instance in AudioEvents.get_active_instances():
		instance.stop(false)
	AudioEvents.pause_all(false)
	AudioEvents.apply_config(_config())


func _config() -> AudioEventsConfig:
	var config := AudioEventsConfig.new()
	config.events_dir = "res://tests/events"
	return config


func _event(instruments: Array) -> AudioEvent:
	var event := AudioEvent.new()
	event.instruments.assign(instruments)
	return event


func _instrument(streams: Array) -> AudioEventInstrument:
	var instrument := AudioEventInstrument.new()
	instrument.streams.assign(streams)
	return instrument


func _looping_instrument() -> AudioEventInstrument:
	var instrument := _instrument([_wav(0.2)])
	instrument.loop = true
	return instrument


func _param(param_name: String, kind: AudioEventParameter.Kind, lo: float, hi: float,
		labels: Array = []) -> AudioEventParameter:
	var parameter := AudioEventParameter.new()
	parameter.name = param_name
	parameter.kind = kind
	parameter.min_value = lo
	parameter.max_value = hi
	parameter.labels = PackedStringArray(labels)
	return parameter


func _automation(param_name: String, target: AudioEventAutomation.Target, points: Array,
		max_value := 1.0) -> AudioEventAutomation:
	var automation := AudioEventAutomation.new()
	automation.parameter = param_name
	automation.target = target
	automation.curve = Curve.new()
	automation.curve.max_value = max_value
	for point: Vector2 in points:
		automation.curve.add_point(point, 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	return automation


func _emitter(event: AudioEvent) -> AudioEventEmitter2D:
	var emitter := AudioEventEmitter2D.new()
	emitter.event = event
	return emitter


## Silent 16-bit mono clip of the given length.
func _wav(seconds: float) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var data := PackedByteArray()
	data.resize(int(seconds * stream.mix_rate) * 2)
	stream.data = data
	return stream


func _add_bus(bus_name: String, send: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, send)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
