@tool
extends RefCounted
## Layout, grid, snapping, hit-testing and drag maths for the timeline editor.
## Kept free of drawing and input so it can be tested. Positions are in the event's
## timeline units (seconds or beats), the same values stored on instruments and markers;
## on a PARAMETER sheet they are values of the sheet parameter, and there are no marker lanes.

const Timeline := preload("../runtime/timeline.gd")

enum Snap { OFF, BEAT, BAR }

# Sizes at editor scale 1; multiplied by set_display_scale().
const BASE_HEADER_WIDTH := 150.0
const BASE_RULER_HEIGHT := 22.0
const BASE_LANE_HEIGHT := 24.0
const BASE_ROW_HEIGHT := 30.0
const BASE_EDGE_GRAB := 6.0
const MIN_ZOOM := 2.0
const MAX_ZOOM := 2000.0
const EPSILON := 0.000001

var event: ChirpEvent
## Pixels per timeline unit.
var zoom := 60.0:
	set(value):
		zoom = value
		_flags_cache.clear() # flag stacking depends on pixel widths
## Timeline unit shown at the left edge of the track area.
var scroll := 0.0
var snap := Snap.BEAT
var timeline: Timeline
## PARAMETER sheets: the sheet parameter's definition (set by the dock, which can see globals).
## Null = a 0..1 range.
var sheet_definition: ChirpParameter

var header_width := BASE_HEADER_WIDTH
var ruler_height := BASE_RULER_HEIGHT
var lane_height := BASE_LANE_HEIGHT
var row_height := BASE_ROW_HEIGHT
var edge_grab := BASE_EDGE_GRAB

## Width in pixels of a marker label; the view sets this from its font.
var measure_text := func(text: String) -> float: return text.length() * 7.0

var _region_lanes := {} # region ChirpMarker -> sub-lane index, so overlapping regions stack
var _region_lane_count := 1
var _flags_cache := {} # point-marker flags laid out at the current zoom: {flags, lanes}


## Scales every size by the editor's display scale (EditorInterface.get_editor_scale()).
func set_display_scale(display_scale: float) -> void:
	_flags_cache.clear()
	header_width = BASE_HEADER_WIDTH * display_scale
	ruler_height = BASE_RULER_HEIGHT * display_scale
	lane_height = BASE_LANE_HEIGHT * display_scale
	row_height = BASE_ROW_HEIGHT * display_scale
	edge_grab = BASE_EDGE_GRAB * display_scale


## Recompiles the event's timeline and region stacking (cheap; call whenever the event may have changed).
func rebuild() -> void:
	_flags_cache.clear()
	timeline = Timeline.new(event) if event else null
	_region_lanes.clear()
	_region_lane_count = 1
	if event == null:
		return
	var regions := event.markers.filter(func(m: ChirpMarker) -> bool: return m != null and m.is_region())
	regions.sort_custom(func(a: ChirpMarker, b: ChirpMarker) -> bool: return a.position < b.position)
	var lane_ends: Array[float] = []
	for region: ChirpMarker in regions:
		var lane := lane_ends.size()
		for i in lane_ends.size():
			if lane_ends[i] <= region.position + EPSILON:
				lane = i
				break
		if lane == lane_ends.size():
			lane_ends.append(region.end)
		else:
			lane_ends[lane] = region.end
		_region_lanes[region] = lane
	_region_lane_count = maxi(lane_ends.size(), 1)


## Sub-lane of a region marker within the regions lane.
func region_lane(marker: ChirpMarker) -> int:
	return _region_lanes.get(marker, 0)


func region_lane_count() -> int:
	return _region_lane_count


func in_beats() -> bool:
	return event != null and event.timeline_units == ChirpEvent.TimelineUnits.BEATS and not is_sheet()


## True for PARAMETER sheets: the axis is a parameter, not time.
func is_sheet() -> bool:
	return event != null and event.sheet_mode == ChirpEvent.SheetMode.PARAMETER


## PARAMETER sheets: the sheet parameter's (min, max).
func sheet_range() -> Vector2:
	if sheet_definition == null:
		return Vector2(0.0, 1.0)
	var lo := sheet_definition.get_min()
	return Vector2(lo, maxf(sheet_definition.get_max(), lo + EPSILON))


## Lowest unit the view can scroll to: 0, or a sheet parameter's minimum.
func min_unit() -> float:
	return minf(sheet_range().x, 0.0) if is_sheet() else 0.0


## PARAMETER sheets: grid step for [param mode] (BAR = coarse, BEAT = fine), from the range.
func sheet_step(mode := Snap.BEAT) -> float:
	var span := sheet_range().y - sheet_range().x
	var coarse := _nice_step(span / 10.0)
	if mode == Snap.BAR:
		return coarse
	if sheet_definition and sheet_definition.kind != ChirpParameter.Kind.CONTINUOUS:
		return maxf(coarse / 5.0, 1.0)
	return coarse / 5.0


## 1, 2 or 5 × a power of ten, at least [param raw].
static func _nice_step(raw: float) -> float:
	if raw <= 0.0:
		return 1.0
	var power := pow(10.0, floorf(log(raw) / log(10.0)))
	for factor in [1.0, 2.0, 5.0, 10.0]:
		if factor * power >= raw - EPSILON:
			return factor * power
	return 10.0 * power


# --- coordinates -------------------------------------------------------------------

func unit_to_x(unit: float) -> float:
	return header_width + (unit - scroll) * zoom


func x_to_unit(x: float) -> float:
	return scroll + (x - header_width) / zoom


func markers_lane_y() -> float:
	return ruler_height


func regions_lane_y() -> float:
	return ruler_height + (0.0 if is_sheet() else marker_lane_count() * lane_height)


## Rows the point markers need so their flags don't overlap.
func marker_lane_count() -> int:
	return _flag_layout().lanes


## Point markers' flags: [{index, marker, lane, rect}], rect in view pixels. Flags that would
## overlap are stacked in rows, earliest first.
func marker_flags() -> Array[Dictionary]:
	var flags: Array[Dictionary] = []
	for flag: Dictionary in _flag_layout().flags:
		var marker: ChirpMarker = event.markers[flag.index]
		flags.append({index = flag.index, marker = marker, lane = flag.lane, rect = Rect2(unit_to_x(marker.position),
			markers_lane_y() + flag.lane * lane_height + 3.0, flag.width, lane_height - 6.0)})
	return flags


## Where marker [param index] is drawn: its flag, or its region bar. Empty when off-lane.
func marker_rect(index: int) -> Rect2:
	var marker := event.markers[index]
	if marker.is_region():
		return Rect2(unit_to_x(marker.position), regions_lane_y() + region_lane(marker) * lane_height + 3.0,
			(marker.end - marker.position) * zoom, lane_height - 6.0)
	for flag in marker_flags():
		if flag.index == index:
			return flag.rect
	return Rect2()


func _flag_layout() -> Dictionary:
	if not _flags_cache.is_empty():
		return _flags_cache
	var flags := []
	if event and not is_sheet():
		for i in event.markers.size():
			var marker := event.markers[i]
			if marker and not marker.is_region():
				flags.append({index = i, position = marker.position, width = measure_text.call(marker_label(marker)) + 10.0})
	flags.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.position < b.position or a.position == b.position and a.index < b.index)
	var lane_ends: Array[float] = [] # right edge of the last flag in each row, in units
	for flag: Dictionary in flags:
		var lane := lane_ends.size()
		for i in lane_ends.size():
			if lane_ends[i] <= flag.position + EPSILON:
				lane = i
				break
		var end: float = flag.position + (flag.width + 4.0) / zoom
		if lane == lane_ends.size():
			lane_ends.append(end)
		else:
			lane_ends[lane] = end
		flag.lane = lane
	_flags_cache = {flags = flags, lanes = maxi(lane_ends.size(), 1)}
	return _flags_cache


func instrument_y(index: int) -> float:
	return regions_lane_y() + (0.0 if is_sheet() else _region_lane_count * lane_height) + index * row_height


func content_height() -> float:
	return instrument_y(event.instruments.size() if event else 0) + 8.0


## Zooms by [param factor], keeping the unit under [param anchor_x] in place.
func zoom_at(factor: float, anchor_x: float) -> void:
	var anchor := x_to_unit(anchor_x)
	zoom = clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	scroll = maxf(anchor - (anchor_x - header_width) / zoom, min_unit())


## Shows everything from 0 to the end of the content in [param width] pixels
## (a sheet parameter's whole range on PARAMETER sheets).
func fit(width: float) -> void:
	if is_sheet():
		var sheet := sheet_range()
		var margin := (sheet.y - sheet.x) * 0.02
		zoom = clampf((width - header_width) / (sheet.y - sheet.x + margin * 2.0), 0.0001, MAX_ZOOM)
		scroll = sheet.x - margin
		return
	var end := maxf(content_end(), 1.0) * 1.1 # a little room after the last item
	zoom = clampf((width - header_width) / end, MIN_ZOOM, MAX_ZOOM)
	scroll = 0.0


## The last finite instrument end or marker position, in units.
func content_end() -> float:
	var end := 0.0
	if event == null:
		return end
	for instrument in event.instruments:
		if instrument:
			var span := instrument_span(instrument)
			end = maxf(end, span.y if span.y != INF else span.x)
	for marker in event.markers:
		if marker:
			end = maxf(end, marker.end if marker.is_region() else marker.position)
	return end


# --- tempo grid --------------------------------------------------------------------

## Tempo segments in units: [{start, bpm, beats_per_bar, beat_unit, beat}], where beat is the
## length of one beat in units. 120 BPM 4/4 applies before the first TEMPO marker.
func tempo_segments() -> Array[Dictionary]:
	var tempos: Array[ChirpMarker] = []
	if event:
		for marker in event.markers:
			if marker and marker.kind == ChirpMarker.Kind.TEMPO:
				tempos.append(marker)
	tempos.sort_custom(func(a: ChirpMarker, b: ChirpMarker) -> bool: return a.position < b.position)
	var segments: Array[Dictionary] = []
	if tempos.is_empty() or tempos[0].position > EPSILON:
		segments.append({start = 0.0, bpm = Timeline.DEFAULT_BPM, beats_per_bar = 4, beat_unit = 4})
	for tempo in tempos:
		segments.append({start = tempo.position, bpm = tempo.bpm,
			beats_per_bar = tempo.beats_per_bar, beat_unit = tempo.beat_unit})
	for segment in segments:
		segment.beat = 1.0 if in_beats() else 60.0 / segment.bpm
	return segments


## Grid lines in [from, to]: [{position, bar, beat, label}]; beat 1 is a bar line (a coarse step on
## PARAMETER sheets) and label is the text to show for it.
## Beats are left out when they would be closer than [param min_spacing] pixels.
func grid_lines(from: float, to: float, min_spacing := 6.0) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	if is_sheet():
		var coarse := sheet_step(Snap.BAR)
		var fine := sheet_step(Snap.BEAT)
		var fine_visible := fine * zoom >= min_spacing
		var sheet := sheet_range()
		var per_coarse := maxi(roundi(coarse / fine), 1)
		var k := int(ceilf(maxf(from, sheet.x) / fine - EPSILON)) # grid aligned to multiples of the step
		var position := k * fine
		while position <= minf(to, sheet.y) + EPSILON and lines.size() < 4000:
			var major := posmod(k, per_coarse) == 0
			if major or fine_visible:
				lines.append({position = position, bar = 0, beat = 1 if major else 2, label = _number(position)})
			k += 1
			position = k * fine
		return lines
	var segments := tempo_segments()
	for i in segments.size():
		var segment := segments[i]
		var segment_end: float = segments[i + 1].start if i + 1 < segments.size() else INF
		if segment_end <= from or segment.start > to:
			continue
		var beats_only_bars: bool = segment.beat * zoom < min_spacing
		var k := maxi(0, int(ceilf((maxf(from, segment.start) - segment.start) / segment.beat - EPSILON)))
		var position: float = segment.start + k * segment.beat
		while position <= to + EPSILON and position < segment_end - EPSILON and lines.size() < 4000:
			var beat: int = k % segment.beats_per_bar + 1
			if beat == 1 or not beats_only_bars:
				var bar: int = k / segment.beats_per_bar + 1
				lines.append({position = position, bar = bar, beat = beat, label = str(bar)})
			k += 1
			position = segment.start + k * segment.beat
	return lines


## Length of one bar, in units, at [param unit] (a coarse grid step on PARAMETER sheets).
func bar_length_at(unit: float) -> float:
	if is_sheet():
		return sheet_step(Snap.BAR)
	var length := 0.0
	for segment in tempo_segments():
		if segment.start <= unit + EPSILON or length == 0.0:
			length = segment.beat * segment.beats_per_bar
	return length


## Nearest beat or bar line to [param unit] (or [param unit] itself when snapping is off).
func snap_unit(unit: float, mode := snap) -> float:
	if is_sheet():
		var sheet := sheet_range()
		if mode != Snap.OFF:
			var grid := snappedf(unit, sheet_step(mode))
			for edge in [sheet.x, sheet.y]: # the range ends snap too
				if absf(unit - edge) < absf(unit - grid):
					grid = edge
			unit = grid
		return clampf(unit, sheet.x, sheet.y)
	if mode == Snap.OFF:
		return maxf(unit, 0.0)
	var segments := tempo_segments()
	var best := unit
	var best_distance := INF
	for i in segments.size():
		var segment := segments[i]
		var segment_end: float = segments[i + 1].start if i + 1 < segments.size() else INF
		var step: float = segment.beat * (segment.beats_per_bar if mode == Snap.BAR else 1)
		var clamped := clampf(unit, segment.start, segment_end)
		var candidates: Array[float] = [segment.start]
		var k := roundf((clamped - segment.start) / step)
		candidates.append(segment.start + k * step)
		if segment_end != INF:
			candidates.append(segment_end)
		for candidate in candidates:
			if candidate <= segment_end + EPSILON and absf(candidate - unit) < best_distance:
				best_distance = absf(candidate - unit)
				best = candidate
	return maxf(best, 0.0)


# --- items ---------------------------------------------------------------------------

## Start and end of an instrument in units. End is INF when its length is unknown.
func instrument_span(instrument: ChirpInstrument) -> Vector2:
	var start := instrument.start
	if instrument.length > 0.0:
		return Vector2(start, start + instrument.length)
	if is_sheet():
		return Vector2(start, maxf(sheet_range().y, start)) # length 0 runs to the end of the range
	var seconds := instrument.get_length()
	if seconds <= 0.0 or timeline == null:
		return Vector2(start, INF)
	return Vector2(start, timeline.to_units(timeline.to_seconds(start) + seconds))


## What is at [param point]: {area, index, part, unit}. area is "ruler", "marker",
## "instrument" or "empty"; part is "body", "start" or "end".
func hit_test(point: Vector2) -> Dictionary:
	var unit := x_to_unit(point.x)
	var hit := {area = "empty", index = -1, part = "body", unit = unit}
	if event == null or point.x < header_width:
		return hit
	if point.y < ruler_height:
		hit.area = "ruler"
		return hit
	if point.y < regions_lane_y():
		var flags := marker_flags()
		for i in range(flags.size() - 1, -1, -1): # drawn last = on top
			if flags[i].rect.grow(1.0).has_point(point):
				hit.area = "marker"
				hit.index = flags[i].index
				return hit
		# Off any flag: the nearest marker line within grab distance.
		var nearest := INF
		for flag in flags:
			var distance := absf(flag.rect.position.x - point.x)
			if distance <= edge_grab and distance < nearest:
				nearest = distance
				hit.area = "marker"
				hit.index = flag.index
		return hit
	if point.y < instrument_y(0):
		var lane := int((point.y - regions_lane_y()) / lane_height)
		for i in range(event.markers.size() - 1, -1, -1):
			var marker := event.markers[i]
			if marker == null or not marker.is_region() or region_lane(marker) != lane:
				continue
			var part := _span_part(point.x, marker.position, marker.end)
			if not part.is_empty():
				hit.area = "marker"
				hit.index = i
				hit.part = part
				return hit
		return hit
	var row := int((point.y - instrument_y(0)) / row_height)
	if row < event.instruments.size() and event.instruments[row]:
		var span := instrument_span(event.instruments[row])
		var part := _span_part(point.x, span.x, span.y)
		if not part.is_empty():
			hit.area = "instrument"
			hit.index = row
			hit.part = part
	return hit


func _span_part(x: float, start: float, end: float) -> String:
	var start_x := unit_to_x(start)
	var end_x := unit_to_x(end) if end != INF else INF
	if x < start_x - edge_grab or x > end_x + edge_grab:
		return ""
	if absf(x - start_x) <= edge_grab:
		return "start"
	if end != INF and absf(x - end_x) <= edge_grab:
		return "end"
	return "body"


## The resource a hit refers to.
func hit_resource(hit: Dictionary) -> Resource:
	if hit.area == "instrument":
		return event.instruments[hit.index]
	if hit.area == "marker":
		return event.markers[hit.index]
	return null


## Snapshot of the properties a drag can change, to compute from and to undo to.
func drag_origin(resource: Resource) -> Dictionary:
	if resource is ChirpInstrument:
		return {start = resource.start, length = resource.length}
	return {position = resource.position, end = resource.end}


## New property values after dragging [param part] of [param resource] by [param delta] units.
func drag_values(resource: Resource, part: String, origin: Dictionary, delta: float, mode := snap) -> Dictionary:
	if resource is ChirpInstrument:
		var span := instrument_span(resource)
		var start: float = origin.start
		var end: float = start + origin.length if origin.length > 0.0 else span.y
		match part:
			"start":
				var new_start := minf(snap_unit(start + delta, mode), end - _min_length(end))
				if end == INF:
					return {start = new_start, length = origin.length}
				return {start = new_start, length = end - new_start}
			"end":
				var new_end := maxf(snap_unit(end + delta, mode), start + _min_length(start))
				return {start = start, length = new_end - start}
			_:
				return {start = snap_unit(start + delta, mode), length = origin.length}
	var marker := resource as ChirpMarker
	var position: float = origin.position
	var marker_end: float = origin.end
	match part:
		"start":
			return {position = minf(snap_unit(position + delta, mode), marker_end - _min_length(marker_end)), end = marker_end}
		"end":
			return {position = position, end = maxf(snap_unit(marker_end + delta, mode), position + _min_length(position))}
		_:
			var new_position := snap_unit(position + delta, mode)
			return {position = new_position, end = new_position + (marker_end - position) if marker.is_region() else marker_end}


## The smallest length an item can be resized to near [param unit]: one grid step when snapping.
func _min_length(unit: float) -> float:
	if is_sheet():
		return sheet_step(Snap.BEAT) if snap != Snap.OFF else (sheet_range().y - sheet_range().x) / 1000.0
	if snap == Snap.OFF:
		return 0.01
	var length := 0.01
	for segment in tempo_segments():
		if segment.start <= unit:
			length = segment.beat
	return length


## What dropping [param resources] (AudioStreams and ChirpEvents) at [param point] would do:
## {action = "append", index, streams} adds audio to the SOUND or SCATTERER instrument under the
## point; {action = "create", unit, instruments} adds new instruments there (one per resource, or
## one playlist of all the audio with [param as_playlist]). Empty when nothing can be dropped.
func plan_drop(point: Vector2, resources: Array, as_playlist := false) -> Dictionary:
	if event == null:
		return {}
	var streams: Array[AudioStream] = []
	var events: Array[ChirpEvent] = []
	for resource in resources:
		if resource is AudioStream:
			streams.append(resource)
		elif resource is ChirpEvent and resource != event:
			events.append(resource)
	if streams.is_empty() and events.is_empty():
		return {}
	var hit := hit_test(point)
	if hit.area == "instrument" and events.is_empty():
		var target: ChirpInstrument = event.instruments[hit.index]
		if target.kind in [ChirpInstrument.Kind.SOUND, ChirpInstrument.Kind.SCATTERER]:
			return {action = "append", index = hit.index, streams = streams}
	var unit := snap_unit(maxf(x_to_unit(maxf(point.x, header_width)), min_unit()))
	var instruments: Array[ChirpInstrument] = []
	if as_playlist and not streams.is_empty():
		var playlist := ChirpInstrument.new()
		playlist.streams = streams
		instruments.append(playlist)
	else:
		for stream in streams:
			var single := ChirpInstrument.new()
			single.streams.append(stream)
			instruments.append(single)
	for nested in events:
		var instrument := ChirpInstrument.new()
		instrument.kind = ChirpInstrument.Kind.EVENT
		instrument.event = nested
		instruments.append(instrument)
	for instrument in instruments:
		instrument.start = unit
		# Timelines: length 0 follows the sound. Sheets: one coarse step (0 would run to the end).
		instrument.length = bar_length_at(unit) if is_sheet() else 0.0
	return {action = "create", unit = unit, instruments = instruments}


## Text on a point marker's flag.
static func marker_label(marker: ChirpMarker) -> String:
	match marker.kind:
		ChirpMarker.Kind.TEMPO:
			var bpm := str(int(marker.bpm)) if is_equal_approx(marker.bpm, roundf(marker.bpm)) else str(snappedf(marker.bpm, 0.01))
			return "%s BPM  %d/%d" % [bpm, marker.beats_per_bar, marker.beat_unit]
		ChirpMarker.Kind.SUSTAIN_POINT:
			return "sustain" + ("  if " + marker.condition_parameter if marker.condition_parameter else "")
		ChirpMarker.Kind.DESTINATION:
			return "◆ " + marker.name
		ChirpMarker.Kind.TRANSITION:
			return "→ " + marker.destination
	return marker.name if marker.name else "marker"


## The text property renaming a marker edits: "name", "destination" (transitions), or "" (none).
static func rename_property(marker: ChirpMarker) -> String:
	match marker.kind:
		ChirpMarker.Kind.MARKER, ChirpMarker.Kind.DESTINATION:
			return "name"
		ChirpMarker.Kind.TRANSITION, ChirpMarker.Kind.TRANSITION_REGION:
			return "destination"
	return ""


## The property changes renaming [param marker] to [param text] makes: [{resource, property,
## before, after}]. Renaming a DESTINATION also retargets the transitions that pointed to it.
func rename_changes(marker: ChirpMarker, text: String) -> Array[Dictionary]:
	var changes: Array[Dictionary] = []
	var property := rename_property(marker)
	var old_text: String = marker.get(property) if property else ""
	text = text.strip_edges()
	if property.is_empty() or text == old_text:
		return changes
	changes.append({resource = marker, property = property, before = old_text, after = text})
	if marker.kind == ChirpMarker.Kind.DESTINATION and not old_text.is_empty():
		for other in event.markers:
			if other and other.kind in [ChirpMarker.Kind.TRANSITION, ChirpMarker.Kind.TRANSITION_REGION] \
					and other.destination == old_text:
				changes.append({resource = other, property = "destination", before = old_text, after = text})
	return changes


## A grid value as short text: no trailing zeros.
static func _number(value: float) -> String:
	value = snappedf(value, 0.0001)
	if is_equal_approx(value, roundf(value)):
		return str(roundi(value))
	return String.num(value, 4)


## Display name for an instrument block.
static func instrument_label(instrument: ChirpInstrument) -> String:
	match instrument.kind:
		ChirpInstrument.Kind.SILENCE:
			return "silence"
		ChirpInstrument.Kind.EVENT:
			if instrument.event == null:
				return "(no event)"
			return instrument.event.resource_path.get_file().get_basename() if instrument.event.resource_path else "nested event"
		ChirpInstrument.Kind.PROGRAMMER:
			return "programmer: %s" % instrument.programmer_key if instrument.programmer_key else "programmer"
	var named := instrument.streams.filter(func(s: AudioStream) -> bool: return s != null)
	if named.is_empty():
		return "(no sound)"
	var first: String = named[0].resource_path.get_file() if named[0].resource_path else "sound"
	var label := first if named.size() == 1 else "%s +%d" % [first, named.size() - 1]
	return "scatter: " + label if instrument.kind == ChirpInstrument.Kind.SCATTERER else label
