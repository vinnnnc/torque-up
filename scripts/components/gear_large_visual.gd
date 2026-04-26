@tool
extends GearVisual

# const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")

func _ready() -> void:
	visual_mode = "gear"
	use_module_profile = true
	outer_radius = PROJECT_PATHS_SCRIPT.LARGE_GEAR_OUTER_RADIUS
	body_color = Color(0.26, 0.47, 0.33, 1.0)
	tooth_color = Color(0.68, 0.9, 0.56, 1.0)
	outline_color = Color(0.08, 0.18, 0.11, 1.0)
	spoke_count = 7
	spoke_width = 4.5
	_sync_module_profile()
	queue_redraw()

