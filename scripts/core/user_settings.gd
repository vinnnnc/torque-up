extends Node

const CONFIG_PATH: String = "user://settings.cfg"
const DEFAULT_SECTION: String = "preferences"

var _config: ConfigFile = ConfigFile.new()

func _ready() -> void:
	_load_config()

func _load_config() -> void:
	_config = ConfigFile.new()
	if _config.load(CONFIG_PATH) != OK:
		_config = ConfigFile.new()

func get_bool(key: String, default_val: bool = false, section: String = DEFAULT_SECTION) -> bool:
	if _config.has_section_key(section, key):
		return bool(_config.get_value(section, key))
	return default_val

func get_int(key: String, default_val: int = 0, section: String = DEFAULT_SECTION) -> int:
	if _config.has_section_key(section, key):
		return int(_config.get_value(section, key))
	return default_val

func get_float(key: String, default_val: float = 0.0, section: String = DEFAULT_SECTION) -> float:
	if _config.has_section_key(section, key):
		return float(_config.get_value(section, key))
	return default_val

func get_string(key: String, default_val: String = "", section: String = DEFAULT_SECTION) -> String:
	if _config.has_section_key(section, key):
		return str(_config.get_value(section, key))
	return default_val

func set_value(key: String, value, section: String = DEFAULT_SECTION) -> void:
	_config.set_value(section, key, value)

func save() -> Error:
	return _config.save(CONFIG_PATH)
