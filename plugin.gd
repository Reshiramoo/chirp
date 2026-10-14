@tool
extends EditorPlugin

const AUTOLOAD_NAME := "Chirp"
const ChirpScript := preload("chirp.gd")


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


func _add_setting(setting: String, default: Variant, type: Variant.Type,
		hint := PROPERTY_HINT_NONE, hint_string := "") -> void:
	if not ProjectSettings.has_setting(setting):
		ProjectSettings.set_setting(setting, default)
	ProjectSettings.set_initial_value(setting, default)
	ProjectSettings.add_property_info({name = setting, type = type, hint = hint, hint_string = hint_string})
	ProjectSettings.set_as_basic(setting, true)
