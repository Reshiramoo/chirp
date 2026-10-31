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
const BASE_AUTOMATION_HEIGHT := 52.0
const BASE_POINT_RADIUS := 4.0
const BASE_EDGE_SNAP := 8.0 # pixels within which an item edge pulls a drag onto it
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
var automation_height := BASE_AUTOMATION_HEIGHT
var point_radius := BASE_POINT_RADIUS
var edge_snap := BASE_EDGE_SNAP

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
	automation_height = BASE_AUTOMATION_HEIGHT * display_scale
	point_radius = BASE_POINT_RADIUS * display_scale
	edge_snap = BASE_EDGE_SNAP * display_scale


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
	# (markers removed since the last rebuild() would leave stale indices: lay out again)
	if not _flags_cache.is_empty() and _flags_cache.count == (event.markers.size() if event else 0):
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
	_flags_cache = {flags = flags, lanes = maxi(lane_ends.size(), 1), count = event.markers.size() if event else 0}
	return _flags_cache


## Top of instrument row [param index]. Each instrument's own automation lanes sit right below it.
func instrument_y(index: int) -> float:
	var y := regions_lane_y() + (0.0 if is_sheet() else _region_lane_count * lane_height)
	if event == null:
		return y
	for i in mini(index, event.instruments.size()):
		y += row_height + _shown_lanes(event.instruments[i].automations if event.instruments[i] else []).size() * automation_height
	return y + maxi(index - event.instruments.size(), 0) * row_height


## The instrument row at [param y], or -1 (lanes and empty space aren't rows).
func instrument_row_at(y: float) -> int:
	if event == null:
		return -1
	for i in event.instruments.size():
		var top := instrument_y(i)
		if y >= top and y < top + row_height:
			return i if event.instruments[i] else -1
	return -1


func content_height() -> float:
	if event == null:
		return instrument_y(0) + 8.0
	return instrument_y(event.instruments.size()) + _shown_lanes(event.automations).size() * automation_height + 8.0


# --- timeline automation lanes ------------------------------------------------------------

## Automation lanes in display order: each instrument's own right below it, then the event's.
## [{automation, owner, index, y}]: owner is the instrument's index, or -1 for the event's lanes;
## index is the automation's position in its owner's automations; y is the lane's top.
## TIMELINE events show TIMELINE-source automations. PARAMETER sheets show PARAMETER-source ones
## with a curve on the sheet parameter (an empty parameter name means the sheet's).
func automation_lanes() -> Array[Dictionary]:
	var lanes: Array[Dictionary] = []
	if event == null:
		return lanes
	for i in event.instruments.size():
		var instrument := event.instruments[i]
		if instrument == null:
			continue
		var y := instrument_y(i) + row_height
		for entry in _shown_lanes(instrument.automations):
			lanes.append({automation = entry.automation, owner = i, index = entry.index, y = y})
			y += automation_height
	var y := instrument_y(event.instruments.size())
	for entry in _shown_lanes(event.automations):
		lanes.append({automation = entry.automation, owner = -1, index = entry.index, y = y})
		y += automation_height
	return lanes


## The automations of [param automations] that get a lane here: [{automation, index}].
func _shown_lanes(automations: Array) -> Array[Dictionary]:
	var shown: Array[Dictionary] = []
	for i in automations.size():
		var automation: ChirpAutomation = automations[i]
		if automation == null:
			continue
		if is_sheet():
			if automation.source == ChirpAutomation.Source.PARAMETER and automation.curve and (automation.parameter.is_empty() \
					or automation.parameter.nocasecmp_to(event.sheet_parameter) == 0):
				shown.append({automation = automation, index = i})
		elif automation.source == ChirpAutomation.Source.TIMELINE:
			shown.append({automation = automation, index = i})
	return shown


## Top of automation lane [param lane] (an index into automation_lanes()).
func automation_y(lane: int) -> float:
	var lanes := automation_lanes()
	if lane < lanes.size():
		return lanes[lane].y
	if not lanes.is_empty(): # past the last lane: continue after it
		return lanes[-1].y + (lane - lanes.size() + 1) * automation_height
	return instrument_y(event.instruments.size() if event else 0) + lane * automation_height


## Value range a lane shows: its curve's on parameter sheets, else from its target.
func automation_range(automation: ChirpAutomation) -> Vector2:
	if automation.source == ChirpAutomation.Source.PARAMETER and automation.curve:
		return Vector2(automation.curve.min_value, maxf(automation.curve.max_value, automation.curve.min_value + EPSILON))
	return automation.lane_range()


func value_to_y(automation: ChirpAutomation, value: float, lane: int) -> float:
	var span := automation_range(automation)
	var t := clampf((value - span.x) / (span.y - span.x), 0.0, 1.0)
	var pad := point_radius + 2.0
	return automation_y(lane) + pad + (1.0 - t) * (automation_height - pad * 2.0)


func y_to_value(automation: ChirpAutomation, y: float, lane: int) -> float:
	var span := automation_range(automation)
	var pad := point_radius + 2.0
	var t := 1.0 - (y - automation_y(lane) - pad) / (automation_height - pad * 2.0)
	return lerpf(span.x, span.y, clampf(t, 0.0, 1.0))


## A lane's points in axis units (timeline units, or sheet parameter values) and values.
func lane_points(automation: ChirpAutomation) -> PackedVector2Array:
	if automation.source == ChirpAutomation.Source.TIMELINE:
		return automation.points
	var points := PackedVector2Array()
	for i in automation.curve.point_count:
		var point := automation.curve.get_point_position(i)
		points.append(Vector2(_from_domain(automation.curve, point.x), point.y))
	return points


## A lane's value at [param unit] (curves are sampled, so their tangents show).
func lane_value_at(automation: ChirpAutomation, unit: float) -> float:
	if automation.source == ChirpAutomation.Source.TIMELINE:
		return automation.value_at(unit)
	return automation.curve.sample(_to_domain(automation.curve, unit))


## Adds a point to a lane; returns its index.
func lane_insert(automation: ChirpAutomation, unit: float, value: float) -> int:
	if automation.source == ChirpAutomation.Source.TIMELINE:
		var added := automation_insert(automation.points, unit, value)
		automation.points = added.points
		return added.index
	return automation.curve.add_point(Vector2(_to_domain(automation.curve, unit), value), 0.0, 0.0,
		Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)


## Moves a lane's point (keeping a curve point's tangents); returns its new index.
func lane_move(automation: ChirpAutomation, index: int, unit: float, value: float) -> int:
	if automation.source == ChirpAutomation.Source.TIMELINE:
		var moved := automation_move(automation.points, index, unit, value)
		automation.points = moved.points
		return moved.index
	automation.curve.set_point_value(index, value)
	return automation.curve.set_point_offset(index, _to_domain(automation.curve, unit))


func lane_remove(automation: ChirpAutomation, index: int) -> void:
	if automation.source == ChirpAutomation.Source.TIMELINE:
		var points := automation.points.duplicate()
		points.remove_at(index)
		automation.points = points
	else:
		automation.curve.remove_point(index)


## What undo needs to restore a lane: {object, property, value}.
func lane_state(automation: ChirpAutomation) -> Dictionary:
	if automation.source == ChirpAutomation.Source.TIMELINE:
		return {object = automation, property = "points", value = automation.points.duplicate()}
	return {object = automation.curve, property = "_data", value = automation.curve.get("_data").duplicate()}


func _to_domain(curve: Curve, unit: float) -> float:
	var axis := sheet_range()
	var t := clampf((unit - axis.x) / (axis.y - axis.x), 0.0, 1.0)
	return lerpf(curve.min_domain, curve.max_domain, t)


func _from_domain(curve: Curve, x: float) -> float:
	var span := curve.max_domain - curve.min_domain
	var t := 0.0 if span <= 0.0 else (x - curve.min_domain) / span
	return lerpf(sheet_range().x, sheet_range().y, t)


## [param points] with a point added at ([param unit], [param value]), kept sorted:
## {points, index} where index is the new point's.
static func automation_insert(points: PackedVector2Array, unit: float, value: float) -> Dictionary:
	var result := points.duplicate()
	var index := 0
	while index < result.size() and result[index].x <= unit:
		index += 1
	result.insert(index, Vector2(unit, value))
	return {points = result, index = index}


## [param points] with point [param index] moved to ([param unit], [param value]), kept sorted.
static func automation_move(points: PackedVector2Array, index: int, unit: float, value: float) -> Dictionary:
	var result := points.duplicate()
	result.remove_at(index)
	return automation_insert(result, unit, value)


## A lane's name: "Volume", "Pitch", "Pan", or the effect and property ("LowPassFilter cutoff_hz").
func automation_title(automation: ChirpAutomation) -> String:
	if automation.target != ChirpAutomation.Target.EFFECT:
		return ChirpAutomation.Target.keys()[automation.target].capitalize()
	var effect: AudioEffect = event.effects[automation.effect_index] \
		if automation.effect_index >= 0 and automation.effect_index < event.effects.size() else null
	var kind := effect.get_class().trim_prefix("AudioEffect") if effect else "(no effect %d)" % (automation.effect_index + 1)
	return "%s %s" % [kind, automation.effect_property if automation.effect_property else "(no property)"]


## The value meaning "no change", drawn as a dashed line: 1 for volume and pitch, 0 for pan; NAN for effects.
static func automation_neutral(automation: ChirpAutomation) -> float:
	match automation.target:
		ChirpAutomation.Target.PAN:
			return 0.0
		ChirpAutomation.Target.EFFECT:
			return NAN
	return 1.0


## Numeric properties of [param effect] with a range, for effect automation menus: [{name, range}].
static func effect_properties(effect: AudioEffect) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if effect == null:
		return found
	for info in effect.get_property_list():
		if info.usage & PROPERTY_USAGE_EDITOR == 0 or info.type not in [TYPE_FLOAT, TYPE_INT] \
				or info.hint != PROPERTY_HINT_RANGE:
			continue
		var parts: PackedStringArray = info.hint_string.split(",")
		if parts.size() >= 2 and parts[0].is_valid_float() and parts[1].is_valid_float():
			found.append({name = info.name, range = Vector2(parts[0].to_float(), parts[1].to_float())})
	return found


## A display string for a lane value: dB for volume, a multiplier for pitch, L/R for pan.
static func automation_text(automation: ChirpAutomation, value: float) -> String:
	match automation.target:
		ChirpAutomation.Target.PITCH:
			return "×%.2f" % value
		ChirpAutomation.Target.PAN:
			if absf(value) < 0.005:
				return "C"
			return "%s %d%%" % ["L" if value < 0.0 else "R", roundi(absf(value) * 100.0)]
		ChirpAutomation.Target.EFFECT:
			return _number(value)
	return "-∞ dB" if value <= 0.00001 else "%.1f dB" % linear_to_db(value)


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


## Nearest beat or bar line to [param unit] (or [param unit] itself when snapping is off). On
## timelines, an item edge within edge_snap pixels wins over the grid: where an instrument's block
## starts or ends, where its sound ends, a marker or region edge. [param exclude] is the item
## being dragged, whose own edges don't count.
func snap_unit(unit: float, mode := snap, exclude: Resource = null) -> float:
	if mode != Snap.OFF and not is_sheet():
		var edge := edge_near(unit, exclude)
		if edge != INF:
			return edge
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


## The item edge nearest [param unit] within edge_snap pixels, or INF.
func edge_near(unit: float, exclude: Resource = null) -> float:
	var best := INF
	var reach := edge_snap / zoom
	for edge in item_edges(exclude):
		if absf(edge - unit) <= reach and absf(edge - unit) < absf(best - unit):
			best = edge
	return best


## Edges items snap to, in units: instrument blocks' starts and ends, where their sounds end, and
## markers' positions and region ends.
func item_edges(exclude: Resource = null) -> PackedFloat64Array:
	var edges := PackedFloat64Array()
	if event == null:
		return edges
	for instrument in event.instruments:
		if instrument == null or instrument == exclude:
			continue
		var span := instrument_span(instrument)
		edges.append(span.x)
		if span.y != INF:
			edges.append(span.y)
		var sound_end := sound_end_unit(instrument)
		if sound_end != INF:
			edges.append(sound_end)
	for marker in event.markers:
		if marker and marker != exclude and marker.kind != ChirpMarker.Kind.TEMPO:
			edges.append(marker.position)
			if marker.is_region():
				edges.append(marker.end)
	return edges


## Where an instrument's (longest) sound ends on the timeline, in units, from its start offset;
## INF when unknown (no sound, nested events).
func sound_end_unit(instrument: ChirpInstrument) -> float:
	var seconds := instrument.get_length() - instrument.start_offset
	if seconds <= 0.0 or timeline == null or instrument.kind != ChirpInstrument.Kind.SOUND:
		return INF
	return timeline.to_units(timeline.to_seconds(instrument.start) + seconds)


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


## The stream whose waveform an instrument block shows: a SOUND instrument's first one, else null.
static func waveform_stream(instrument: ChirpInstrument) -> AudioStream:
	if instrument == null or instrument.kind != ChirpInstrument.Kind.SOUND:
		return null
	for stream in instrument.streams:
		if stream:
			return stream
	return null


## Seconds into an instrument's sound heard at [param unit] on the timeline; -1 when silent there.
## Accounts for start_offset and looping. PARAMETER sheets don't map position to time: there the
## whole sound is stretched across [param span] (the block's start and end in units).
func waveform_time(instrument: ChirpInstrument, unit: float, sound_length: float, span: Vector2) -> float:
	if sound_length <= 0.0 or unit < span.x or unit > span.y:
		return -1.0
	if is_sheet():
		var width := span.y - span.x
		return 0.0 if width <= 0.0 else (unit - span.x) / width * sound_length
	var seconds := unit - span.x
	if timeline:
		seconds = timeline.to_seconds(unit) - timeline.to_seconds(span.x)
	seconds += instrument.start_offset
	if instrument.loop:
		return fposmod(seconds, sound_length)
	return seconds if seconds <= sound_length else -1.0


## PARAMETER sheets: instrument index -> how far (0..1) each sounding layer of [param instance] is
## through its sound, for the progress lines in the blocks.
static func sheet_progress(instance: ChirpEventInstance) -> Dictionary:
	var progress := {}
	for index: int in instance._entry_voices:
		var voice: ChirpEventInstance.Voice = instance._entry_voices[index]
		if voice == null or voice.player == null or not is_instance_valid(voice.player):
			continue
		var stream: AudioStream = voice.player.stream
		if stream == null or stream.get_length() <= 0.0:
			continue
		progress[index] = voice.player.get_playback_position() / stream.get_length()
	return progress


## Mute, solo and volume knob in instrument row [param row]'s header: {mute, solo, knob} rects.
func header_controls(row: int) -> Dictionary:
	var size := row_height - 10.0
	var top := instrument_y(row) + 5.0
	var knob := Rect2(header_width - 6.0 - size, top, size, size)
	var solo := Rect2(knob.position.x - 3.0 - size, top, size, size)
	var mute := Rect2(solo.position.x - 2.0 - size, top, size, size)
	return {mute = mute, solo = solo, knob = knob}


## What is at [param point]: {area, index, part, unit}. area is "ruler", "marker",
## "instrument" or "empty"; part is "body", "start" or "end".
func hit_test(point: Vector2) -> Dictionary:
	var unit := x_to_unit(point.x)
	var hit := {area = "empty", index = -1, part = "body", unit = unit}
	if event == null:
		return hit
	if point.x < header_width:
		var row := instrument_row_at(point.y)
		if row >= 0:
			hit.area = "header"
			hit.index = row
			hit.part = "label"
			var controls := header_controls(row)
			for part: String in controls:
				if controls[part].grow(2.0).has_point(point):
					hit.part = part
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
	var lanes := automation_lanes()
	for lane in lanes.size():
		if point.y >= lanes[lane].y and point.y < lanes[lane].y + automation_height:
			var automation: ChirpAutomation = lanes[lane].automation
			hit.area = "automation"
			hit.index = lane
			hit.point = -1
			hit.value = y_to_value(automation, point.y, lane)
			var nearest := INF
			var points := lane_points(automation)
			for i in points.size():
				var at := Vector2(unit_to_x(points[i].x), value_to_y(automation, points[i].y, lane))
				var distance := at.distance_to(point)
				if distance <= point_radius + 4.0 and distance < nearest:
					nearest = distance
					hit.point = i
			return hit
	var row := instrument_row_at(point.y)
	if row >= 0:
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
	if hit.area == "automation":
		return automation_lanes()[hit.index].automation
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
				var new_start := minf(snap_unit(start + delta, mode, resource), end - _min_length(end))
				if end == INF:
					return {start = new_start, length = origin.length}
				return {start = new_start, length = end - new_start}
			"end":
				var new_end := maxf(snap_unit(end + delta, mode, resource), start + _min_length(start))
				return {start = start, length = new_end - start}
			_:
				return {start = _snap_move(start, end, delta, mode, resource), length = origin.length}
	var marker := resource as ChirpMarker
	var position: float = origin.position
	var marker_end: float = origin.end
	match part:
		"start":
			return {position = minf(snap_unit(position + delta, mode, resource), marker_end - _min_length(marker_end)), end = marker_end}
		"end":
			return {position = position, end = maxf(snap_unit(marker_end + delta, mode, resource), position + _min_length(position))}
		_:
			var new_position := _snap_move(position, marker_end if marker.is_region() else INF, delta, mode, resource)
			return {position = new_position, end = new_position + (marker_end - position) if marker.is_region() else marker_end}


## Where an item moved by [param delta] starts: its start snapped, unless its end lands on an
## item edge (then the end snaps there and the start follows).
func _snap_move(start: float, end: float, delta: float, mode: Snap, resource: Resource) -> float:
	if mode != Snap.OFF and end != INF and not is_sheet():
		var start_edge := edge_near(start + delta, resource)
		var end_edge := edge_near(end + delta, resource)
		if end_edge != INF and (start_edge == INF or absf(end_edge - end - delta) < absf(start_edge - start - delta)):
			return maxf(end_edge - (end - start), min_unit())
	return snap_unit(start + delta, mode, resource)


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
			return "→ " + marker.destination + transition_suffix(marker)
	return marker.name if marker.name else "marker"


## "  (crossfade 2)" / "  (bridge 1, + stinger)": how a transition sounds, for its label.
static func transition_suffix(marker: ChirpMarker) -> String:
	var parts: PackedStringArray = []
	if marker.transition_mode != ChirpMarker.TransitionMode.CUT and marker.transition_length > 0.0:
		parts.append("%s %s" % [ChirpMarker.TransitionMode.keys()[marker.transition_mode].to_lower(),
			_number(marker.transition_length)])
	if marker.transition_event:
		parts.append("+ stinger" if marker.transition_mode != ChirpMarker.TransitionMode.BRIDGE else "+ fill")
	return "  (%s)" % ", ".join(parts) if not parts.is_empty() else ""


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
