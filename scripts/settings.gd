extends Node
## Autoload: player preferences, persisted to user://settings.cfg.
##
## Kept apart from SaveManager because settings and game progress have different
## lifetimes -- wiping a stuck save should not reset the player's preferences,
## and settings must be readable before any game exists.
##
## There are currently no options. The named set_option/get_option pair stays so
## that adding one is a single variable plus a toggle, rather than rebuilding the
## plumbing.
##
## No class_name: an autoload's singleton name and a global class name would
## collide.

signal changed()

const CONFIG_PATH := "user://settings.cfg"
const SECTION := "gameplay"



func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	changed.emit()


func save_settings() -> void:
	var config := ConfigFile.new()
	config.save(CONFIG_PATH)


## Named access so a settings screen can drive every option through one path
## instead of a branch per toggle. Writes through to disk immediately: settings
## changes are rare and losing one to a crash is more annoying than the write.
func set_option(option: String, value: bool) -> void:
	if not has_option(option):
		push_warning("Unknown setting: %s" % option)
		return
	if bool(get(option)) == value:
		return
	set(option, value)
	save_settings()
	changed.emit()


func get_option(option: String) -> bool:
	return bool(get(option)) if has_option(option) else false


func has_option(option: String) -> bool:
	for property in get_property_list():
		if property["name"] == option and property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			return true
	return false
