@tool
extends EditorPlugin

const AUTOLOAD_NAME := "AudioEvents"
const CONFIG_SETTING := "audio_events/config"
const DEFAULT_CONFIG := "res://audio/audio_events_config.tres"


func _enable_plugin() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, get_script().resource_path.get_base_dir().path_join("audio_events.gd"))


func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)


func _enter_tree() -> void:
	if not ProjectSettings.has_setting(CONFIG_SETTING):
		ProjectSettings.set_setting(CONFIG_SETTING, DEFAULT_CONFIG)
	ProjectSettings.set_initial_value(CONFIG_SETTING, DEFAULT_CONFIG)
	ProjectSettings.add_property_info({
		name = CONFIG_SETTING,
		type = TYPE_STRING,
		hint = PROPERTY_HINT_FILE,
		hint_string = "*.tres,*.res",
	})
