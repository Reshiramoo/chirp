@tool
extends EditorPlugin

const AUTOLOAD_NAME := "Chirp"
const ChirpScript := preload("chirp.gd")
const EventBrowser := preload("editor/event_browser.gd")
const EventDock := preload("editor/event_dock.gd")
const InspectorPlugin := preload("editor/inspector_plugin.gd")
const AttenuationGizmo3D := preload("editor/attenuation_gizmo_3d.gd")
const AttenuationOverlay2D := preload("editor/attenuation_overlay_2d.gd")

var _preview_chirp: Node # a private Chirp used to audition sounds in the editor
var _browser: EventBrowser
var _event_dock: EventDock
var _inspector_plugin: InspectorPlugin
var _gizmo_3d: AttenuationGizmo3D
var _overlay_2d: AttenuationOverlay2D
var _reload_queued := false


func _enable_plugin() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, get_script().resource_path.get_base_dir().path_join("chirp.gd"))


func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)


func _enter_tree() -> void:
	_add_setting(ChirpScript.SETTING_SOUND_DIRECTORIES, ChirpScript.DEFAULT_SOUND_DIRECTORIES,
		TYPE_DICTIONARY, PROPERTY_HINT_DICTIONARY_TYPE, "String;String")
	_add_setting(ChirpScript.SETTING_CONFIG, ChirpScript.DEFAULT_CONFIG,
		TYPE_STRING, PROPERTY_HINT_FILE, "*.tres,*.res")
	_add_setting(ChirpScript.SETTING_PAUSE_IN_BACKGROUND, true, TYPE_BOOL)
	_add_setting(ChirpScript.Mixer.SETTING_EFFECT_POOL, ChirpScript.Mixer.DEFAULT_EFFECT_POOL,
		TYPE_INT, PROPERTY_HINT_RANGE, "0,64")

	_preview_chirp = ChirpScript.new()
	_preview_chirp.preview = true
	_preview_chirp.name = "ChirpPreview"
	EditorInterface.get_base_control().add_child(_preview_chirp)

	_browser = EventBrowser.new()
	_browser.setup(self, _preview_chirp)
	add_dock(_browser)
	_event_dock = EventDock.new()
	_event_dock.setup(self, _preview_chirp)
	add_dock(_event_dock)
	_browser.item_selected.connect(_event_dock.show_item)
	_browser.item_activated.connect(_play)

	_inspector_plugin = InspectorPlugin.new()
	_inspector_plugin.chirp = _preview_chirp
	_inspector_plugin.preview = _play
	add_inspector_plugin(_inspector_plugin)
	_gizmo_3d = AttenuationGizmo3D.new()
	_gizmo_3d.chirp = _preview_chirp
	add_node_3d_gizmo_plugin(_gizmo_3d)
	_overlay_2d = AttenuationOverlay2D.new()
	_overlay_2d.plugin = self
	_overlay_2d.chirp = _preview_chirp
	EditorInterface.get_inspector().property_edited.connect(_on_property_edited)

	ProjectSettings.settings_changed.connect(_queue_reload)
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_queue_reload)
	_browser.refresh()


func _exit_tree() -> void:
	ProjectSettings.settings_changed.disconnect(_queue_reload)
	EditorInterface.get_resource_filesystem().filesystem_changed.disconnect(_queue_reload)
	EditorInterface.get_inspector().property_edited.disconnect(_on_property_edited)
	remove_node_3d_gizmo_plugin(_gizmo_3d)
	remove_inspector_plugin(_inspector_plugin)
	remove_dock(_event_dock)
	_event_dock.queue_free()
	remove_dock(_browser)
	_browser.queue_free()
	_preview_chirp.queue_free()


func _handles(object: Object) -> bool:
	return object is ChirpEvent or object is ChirpSnapshot or object is ChirpEmitter2D


func _edit(object: Object) -> void:
	_overlay_2d.emitter = object as ChirpEmitter2D
	update_overlays()
	if object is ChirpEvent or object is ChirpSnapshot:
		_event_dock.show_item(object)


func _make_visible(visible: bool) -> void:
	if not visible:
		_overlay_2d.emitter = null
		update_overlays()


func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	_overlay_2d.draw(overlay)


func _forward_canvas_gui_input(event: InputEvent) -> bool:
	return _overlay_2d.input(event)


func _on_property_edited(_property: String) -> void:
	var edited := EditorInterface.get_inspector().get_edited_object()
	if edited is ChirpEmitter3D:
		edited.update_gizmos()
	elif edited is ChirpEmitter2D:
		update_overlays()


func _play(item: Variant) -> void:
	_event_dock.play_item(item)


## Settings and files often change in bursts; reload once per frame at most.
func _queue_reload() -> void:
	if _reload_queued:
		return
	_reload_queued = true
	_reload.call_deferred()


func _reload() -> void:
	_reload_queued = false
	_preview_chirp.reload_settings()
	_browser.refresh()


func _add_setting(setting: String, default: Variant, type: Variant.Type,
		hint := PROPERTY_HINT_NONE, hint_string := "") -> void:
	if not ProjectSettings.has_setting(setting):
		ProjectSettings.set_setting(setting, default)
	ProjectSettings.set_initial_value(setting, default)
	ProjectSettings.add_property_info({name = setting, type = type, hint = hint, hint_string = hint_string})
	ProjectSettings.set_as_basic(setting, true)
