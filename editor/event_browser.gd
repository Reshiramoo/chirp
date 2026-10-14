@tool
extends EditorDock
## The Chirp dock: every event from the sound directories, plus the snapshots, VCAs and
## global parameters of the ChirpConfig. Selecting an item inspects it and loads it into
## the preview dock; double-clicking also plays it.

signal item_selected(item: Variant) # String event path or a ChirpSnapshot / ChirpVCA / ChirpParameter
signal item_activated(item: Variant)

const RESOURCE_EXTENSIONS: Array[String] = ["tres", "res"]

var _plugin: EditorPlugin
var _chirp: Node # the editor's preview copy of Chirp
var _search: LineEdit
var _tree: Tree
var _create_button: Button


func setup(plugin: EditorPlugin, chirp: Node) -> void:
	_plugin = plugin
	_chirp = chirp
	title = "Chirp"
	_set_dock_icon(self, "chirp.svg")
	layout_key = "chirp_browser"
	default_slot = DOCK_SLOT_RIGHT_UL
	available_layouts = DOCK_LAYOUT_VERTICAL | DOCK_LAYOUT_FLOATING

	var box := VBoxContainer.new()
	add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	_search = LineEdit.new()
	_search.placeholder_text = "Filter events"
	_search.clear_button_enabled = true
	_search.right_icon = _icon("Search")
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_text: String) -> void: refresh())
	top.add_child(_search)
	var reload := Button.new()
	reload.icon = _icon("Reload")
	reload.flat = true
	reload.tooltip_text = "Reload Chirp settings and rescan sound directories"
	reload.pressed.connect(func() -> void:
		_chirp.reload_settings()
		refresh())
	top.add_child(reload)

	_tree = Tree.new()
	_tree.hide_root = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.item_selected.connect(_on_item_selected)
	_tree.item_activated.connect(_on_item_activated)
	_tree.set_drag_forwarding(_get_tree_drag_data, Callable(), Callable())
	box.add_child(_tree)

	_create_button = Button.new()
	_create_button.text = "Create Emitter"
	_create_button.icon = _icon("Add")
	_create_button.tooltip_text = "Add a ChirpEmitter2D/3D for the selected event under the selected node"
	_create_button.disabled = true
	_create_button.pressed.connect(_create_emitter)
	box.add_child(_create_button)


## Rebuilds the tree from the preview Chirp's registry and config.
func refresh() -> void:
	if _tree == null:
		return
	var filter := _search.text.strip_edges()
	_tree.clear()
	var root := _tree.create_item()

	var events := _section(root, "Events", "AudioStreamPlayer")
	var folders := {}
	var paths := Array(_chirp.events.get_event_paths())
	paths.sort()
	for path: String in paths:
		if not filter.is_empty() and path.findn(filter) == -1:
			continue
		var segments := path.trim_prefix("event:/").split("/")
		var parent := events
		var folder_key := ""
		for i in segments.size() - 1:
			folder_key += "/" + segments[i]
			if not folders.has(folder_key):
				var folder := _tree.create_item(parent)
				folder.set_text(0, segments[i])
				folder.set_icon(0, _icon("Folder"))
				folder.set_selectable(0, false)
				folders[folder_key] = folder
			parent = folders[folder_key]
		var item := _tree.create_item(parent)
		var file: String = _chirp.events.get_event_file(path)
		item.set_text(0, segments[-1])
		item.set_icon(0, _icon("AudioStreamPlayer"))
		item.set_tooltip_text(0, "%s\n%s" % [path, file])
		item.set_metadata(0, path)
		if file.get_extension() not in RESOURCE_EXTENSIONS:
			# Plain audio file: no ChirpEvent resource behind it.
			item.set_custom_color(0, EditorInterface.get_editor_theme().get_color(&"disabled_font_color", &"Editor"))
	if events.get_child_count() == 0:
		events.free()

	var config: ChirpConfig = _chirp.config
	_resource_section(root, "Snapshots", "AudioBusLayout", config.snapshots, filter)
	_resource_section(root, "VCAs", "HSlider", config.vcas, filter)
	_resource_section(root, "Global Parameters", "Range", config.global_parameters, filter)
	_on_item_selected()


func _section(root: TreeItem, text: String, icon: String) -> TreeItem:
	var section := _tree.create_item(root)
	section.set_text(0, text)
	section.set_icon(0, _icon(icon))
	section.set_selectable(0, false)
	section.set_custom_color(0, EditorInterface.get_editor_theme().get_color(&"accent_color", &"Editor"))
	return section


func _resource_section(root: TreeItem, text: String, icon: String, resources: Array, filter: String) -> void:
	var section := _section(root, text, icon)
	for resource: Resource in resources:
		if resource == null:
			continue
		var resource_name: String = resource.get("name")
		if not filter.is_empty() and resource_name.findn(filter) == -1:
			continue
		var item := _tree.create_item(section)
		item.set_text(0, resource_name if resource_name else "(unnamed)")
		item.set_icon(0, _icon(icon))
		item.set_metadata(0, resource)
	if section.get_child_count() == 0:
		section.free()


func _selected() -> Variant:
	var item := _tree.get_selected()
	return item.get_metadata(0) if item else null


func _on_item_selected() -> void:
	var selected: Variant = _selected()
	_create_button.disabled = not selected is String
	if selected == null:
		return
	if selected is String:
		var file: String = _chirp.events.get_event_file(selected)
		if file.get_extension() in RESOURCE_EXTENSIONS:
			EditorInterface.edit_resource(load(file))
		elif not file.is_empty():
			EditorInterface.select_file(file)
	else:
		EditorInterface.edit_resource(selected)
	item_selected.emit(selected)


func _on_item_activated() -> void:
	var selected: Variant = _selected()
	if selected != null:
		item_activated.emit(selected)


func _get_tree_drag_data(at_position: Vector2) -> Variant:
	var item := _tree.get_item_at_position(at_position)
	if item == null or not item.get_metadata(0) is String:
		return null
	var file: String = _chirp.events.get_event_file(item.get_metadata(0))
	if file.is_empty():
		return null
	var label := Label.new()
	label.text = item.get_metadata(0)
	set_drag_preview(label)
	return {type = "files", files = PackedStringArray([file])}


func _create_emitter() -> void:
	var path: Variant = _selected()
	var scene_root := EditorInterface.get_edited_scene_root()
	if not path is String or scene_root == null:
		return
	var selected_nodes := EditorInterface.get_selection().get_selected_nodes()
	var parent: Node = selected_nodes[0] if not selected_nodes.is_empty() else scene_root
	var emitter: Node = ChirpEmitter3D.new() if parent is Node3D else ChirpEmitter2D.new()
	emitter.name = String(path).get_file().to_pascal_case() + "Emitter"
	var file: String = _chirp.events.get_event_file(path)
	var resource: Resource = load(file) if file.get_extension() in RESOURCE_EXTENSIONS else null
	if resource is ChirpEvent:
		emitter.event = resource
	else:
		emitter.event_path = path

	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Create Chirp Emitter")
	undo_redo.add_do_method(parent, "add_child", emitter, true)
	undo_redo.add_do_method(emitter, "set_owner", scene_root)
	undo_redo.add_do_reference(emitter)
	undo_redo.add_undo_method(parent, "remove_child", emitter)
	undo_redo.commit_action()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(emitter)


func _icon(icon_name: String) -> Texture2D:
	var theme := EditorInterface.get_editor_theme()
	return theme.get_icon(icon_name, &"EditorIcons") if theme.has_icon(icon_name, &"EditorIcons") else null


## Loaded (not preloaded) so a freshly pulled icon that isn't imported yet can't break the plugin.
static func _set_dock_icon(dock: EditorDock, file: String) -> void:
	var path: String = (dock.get_script() as Script).resource_path.get_base_dir().path_join("../icons").path_join(file).simplify_path()
	if ResourceLoader.exists(path):
		dock.dock_icon = load(path)
		dock.force_show_icon = true
