@tool
extends GearVisual

# const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")

func _ready() -> void:
	visual_mode = "gear"
	use_module_profile = true
	outer_radius = PROJECT_PATHS_SCRIPT.SMALL_GEAR_OUTER_RADIUS
	body_color = PROJECT_PATHS_SCRIPT.PALETTE_BLUE
	tooth_color = PROJECT_PATHS_SCRIPT.PALETTE_BLUE
	outline_color = PROJECT_PATHS_SCRIPT.PALETTE_SLATE
	spoke_count = 4
	spoke_width = 1.5
	_sync_module_profile()
	queue_redraw()
