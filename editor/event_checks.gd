@tool
extends RefCounted
## Authoring checks for the Chirp Event dock: things in an event that would warn, misbehave or
## quietly do nothing when it plays. Editor-only; cheap enough to run a few times a second.

const Timeline := preload("../runtime/timeline.gd")

enum Severity {
	WARNING, ## Broken: something won't play or won't work as set up.
	NOTE, ## Works, but maybe not the way you expect (e.g. a loop region that isn't seamless).
}


## The issues in [param event]: [code]{severity, message, resource}[/code], where resource is the
## instrument, marker, automation or the event itself to select. [param globals]: the project's
## global parameter definitions (ChirpConfig.global_parameters).
static func check(event: ChirpEvent, globals: Array) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	if event == null:
		return issues
	var add := func(severity: Severity, message: String, resource: Resource) -> void:
		issues.append({severity = severity, message = message, resource = resource})
	var sheet := event.sheet_mode == ChirpEvent.SheetMode.PARAMETER

	if sheet:
		if event.sheet_parameter.is_empty():
			add.call(Severity.WARNING, "No sheet parameter: set Sheet Parameter so the layers know where they are.", event)
		elif not _known(event, globals, event.sheet_parameter):
			add.call(Severity.WARNING, "Sheet parameter '%s' doesn't exist (event or global)." % event.sheet_parameter, event)

	for i in event.instruments.size():
		var instrument := event.instruments[i]
		var name := "Instrument %d" % (i + 1)
		if instrument == null:
			add.call(Severity.NOTE, "%s is empty." % name, event)
			continue
		match instrument.kind:
			ChirpInstrument.Kind.SOUND, ChirpInstrument.Kind.SCATTERER:
				if not instrument.streams.any(func(stream: AudioStream) -> bool: return stream != null):
					add.call(Severity.WARNING, "%s has no sounds: it plays nothing." % name, instrument)
			ChirpInstrument.Kind.EVENT:
				if instrument.event == null:
					add.call(Severity.WARNING, "%s has no event to play." % name, instrument)
				elif instrument.event == event:
					add.call(Severity.WARNING, "%s plays this event inside itself." % name, instrument)
			ChirpInstrument.Kind.PROGRAMMER:
				if instrument.programmer_key.is_empty():
					add.call(Severity.WARNING, "%s has no programmer key." % name, instrument)
		if not instrument.condition_parameter.is_empty() and not _known(event, globals, instrument.condition_parameter):
			add.call(Severity.WARNING, "%s: condition parameter '%s' doesn't exist; it's treated as met."
				% [name, instrument.condition_parameter], instrument)
		for automation in instrument.automations:
			_check_automation(event, globals, automation, name, add)

	for automation in event.automations:
		_check_automation(event, globals, automation, "Event", add)
	for i in event.effects.size():
		if event.effects[i] == null:
			add.call(Severity.NOTE, "Effect %d is empty." % (i + 1), event)

	if event.sheet_mode == ChirpEvent.SheetMode.TIMELINE:
		_check_markers(event, globals, add)
	return issues


## Severity of the worst issue about each resource: resource -> Severity.
static func by_resource(issues: Array[Dictionary]) -> Dictionary:
	var worst := {}
	for issue in issues:
		if not worst.has(issue.resource) or issue.severity < worst[issue.resource]:
			worst[issue.resource] = issue.severity
	return worst


static func _known(event: ChirpEvent, globals: Array, parameter_name: String) -> bool:
	return event.find_parameter(parameter_name) != null or _global(globals, parameter_name) != null


static func _global(globals: Array, parameter_name: String) -> ChirpParameter:
	for definition: ChirpParameter in globals:
		if definition and definition.name.nocasecmp_to(parameter_name) == 0:
			return definition
	return null


static func _check_automation(event: ChirpEvent, globals: Array, automation: ChirpAutomation, owner: String,
		add: Callable) -> void:
	if automation == null:
		return
	var title := "%s automation (%s)" % [owner, ChirpAutomation.Target.keys()[automation.target].to_lower()]
	if automation.source == ChirpAutomation.Source.PARAMETER:
		if automation.parameter.is_empty():
			if event.sheet_mode != ChirpEvent.SheetMode.PARAMETER:
				add.call(Severity.WARNING, "%s has no parameter to follow." % title, automation)
		elif automation.global and _global(globals, automation.parameter) == null:
			add.call(Severity.WARNING, "%s: global parameter '%s' doesn't exist." % [title, automation.parameter], automation)
		elif not automation.global and event.find_parameter(automation.parameter) == null:
			add.call(Severity.WARNING, "%s: the event has no parameter '%s'%s." % [title, automation.parameter,
				" (it's global: tick Global)" if _global(globals, automation.parameter) else ""], automation)
	elif event.sheet_mode != ChirpEvent.SheetMode.TIMELINE:
		add.call(Severity.WARNING, "%s follows the timeline, but the event has none." % title, automation)
	if automation.target == ChirpAutomation.Target.EFFECT:
		if automation.effect_index < 0 or automation.effect_index >= event.effects.size() \
				or event.effects[automation.effect_index] == null:
			add.call(Severity.WARNING, "%s: there's no effect %d." % [title, automation.effect_index + 1], automation)
		elif not typeof(event.effects[automation.effect_index].get(automation.effect_property)) in [TYPE_FLOAT, TYPE_INT]:
			add.call(Severity.WARNING, "%s: %s has no number property '%s'." % [title,
				event.effects[automation.effect_index].get_class(), automation.effect_property], automation)


static func _check_markers(event: ChirpEvent, globals: Array, add: Callable) -> void:
	var destinations := {}
	for marker in event.markers:
		if marker and marker.kind == ChirpMarker.Kind.DESTINATION:
			if destinations.has(marker.name):
				add.call(Severity.WARNING, "Two destinations are named '%s'; transitions use the last one." % marker.name, marker)
			destinations[marker.name] = true
	var timeline := Timeline.new(event)
	for mark in timeline.marks:
		var marker := mark.marker
		var label: String = "'%s'" % marker.name if marker.name else ChirpMarker.Kind.keys()[marker.kind].to_lower().replace("_", " ")
		if marker.kind in [ChirpMarker.Kind.TRANSITION, ChirpMarker.Kind.TRANSITION_REGION]:
			if marker.destination.is_empty():
				add.call(Severity.WARNING, "Transition %s has no destination." % label, marker)
			elif not destinations.has(marker.destination):
				add.call(Severity.WARNING, "Transition %s goes to '%s', but there's no destination by that name."
					% [label, marker.destination], marker)
		if marker.kind in [ChirpMarker.Kind.TRANSITION, ChirpMarker.Kind.TRANSITION_REGION, ChirpMarker.Kind.MAGNET_REGION]:
			if marker.transition_mode != ChirpMarker.TransitionMode.CUT and marker.transition_length <= 0.0:
				add.call(Severity.NOTE, "Transition %s is a %s with no length: it cuts." % [label,
					ChirpMarker.TransitionMode.keys()[marker.transition_mode].to_lower()], marker)
			if marker.transition_event == event:
				add.call(Severity.WARNING, "Transition %s plays this event as its stinger." % label, marker)
		if marker.kind == ChirpMarker.Kind.MAGNET_REGION and marker.condition_parameter.is_empty() and mark.end > mark.time:
			add.call(Severity.NOTE, "Magnet %s has no condition: it always holds the playhead inside it." % label, marker)
		if marker.is_region() and mark.end <= mark.time:
			add.call(Severity.WARNING, "Region %s ends where it starts: it never %s." % [label,
				"loops" if marker.kind == ChirpMarker.Kind.LOOP_REGION else "acts"], marker)
		if not marker.condition_parameter.is_empty() and not _known(event, globals, marker.condition_parameter):
			add.call(Severity.WARNING, "Marker %s: condition parameter '%s' doesn't exist; it's treated as met."
				% [label, marker.condition_parameter], marker)
		if marker.kind == ChirpMarker.Kind.LOOP_REGION and mark.end > mark.time:
			_check_seamless(timeline, mark, label, add)


## Notes the ways a loop region falls back to frame-accurate jumps (see the README's Timing rules).
static func _check_seamless(timeline: Timeline, region: Timeline.Mark, label: String, add: Callable) -> void:
	if region.marker.probability < 100.0:
		add.call(Severity.NOTE, "Loop %s isn't seamless: its probability is below 100%%." % label, region.marker)
		return
	for entry in timeline.entries:
		var instrument := entry.instrument
		if instrument.kind != ChirpInstrument.Kind.SOUND or entry.end <= region.time or entry.start >= region.end:
			continue
		var name := "Instrument %d" % (entry.index + 1)
		if entry.start > region.time + Timeline.EPSILON:
			add.call(Severity.NOTE, "%s starts inside loop %s, so it restarts on every pass." % [name, label], instrument)
			continue
		if instrument.random_start_offset > 0.0:
			continue
		var to := region.end - entry.start + instrument.start_offset
		for stream in instrument.streams:
			if not (stream is AudioStreamOggVorbis or stream is AudioStreamMP3) or to > stream.get_length() + Timeline.EPSILON:
				continue
			if absf(to - stream.get_length()) > 0.02:
				add.call(Severity.NOTE, "Loop %s isn't seamless for %s: Ogg Vorbis and MP3 only loop back from their end, and the region ends %.2f s into a %.2f s sound. End the region with the sound, or use WAV."
					% [label, name, to, stream.get_length()], instrument)
				break
