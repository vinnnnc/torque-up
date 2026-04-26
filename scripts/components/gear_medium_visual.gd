@tool
extends GearVisual

# const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")

func _ready() -> void:
	visual_mode = "gear"
	use_module_profile = true
	outer_radius = PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS
	body_color = Color(0.5, 0.37, 0.24, 1.0)
	tooth_color = Color(0.87, 0.68, 0.44, 1.0)
	outline_color = Color(0.24, 0.14, 0.07, 1.0)
	spoke_count = 5
	spoke_width = 2.8
	_sync_module_profile()
	queue_redraw()
