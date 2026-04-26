@tool
extends GearVisual

# const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")

func _ready() -> void:
	visual_mode = "gear"
	use_module_profile = true
	outer_radius = PROJECT_PATHS_SCRIPT.SMALL_GEAR_OUTER_RADIUS
	body_color = Color(0.28, 0.36, 0.56, 1.0)
	tooth_color = Color(0.62, 0.82, 1.0, 1.0)
	outline_color = Color(0.07, 0.11, 0.2, 1.0)
	spoke_count = 4
	spoke_width = 1.5
	_sync_module_profile()
	queue_redraw()
