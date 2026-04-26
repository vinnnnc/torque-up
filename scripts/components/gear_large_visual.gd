@tool
extends GearVisual

# const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")

func _ready() -> void:
	visual_mode = "gear"
	use_module_profile = true
	outer_radius = PROJECT_PATHS_SCRIPT.LARGE_GEAR_OUTER_RADIUS
	body_color = PROJECT_PATHS_SCRIPT.PALETTE_TEAL
	tooth_color = PROJECT_PATHS_SCRIPT.PALETTE_TEAL
	outline_color = PROJECT_PATHS_SCRIPT.PALETTE_SLATE
	spoke_count = 7
	spoke_width = 4.5
	_sync_module_profile()
	queue_redraw()

