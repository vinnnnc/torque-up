@tool
extends GearVisual

# const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")

func _ready() -> void:
	visual_mode = "gear"
	use_module_profile = true
	outer_radius = PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS
	body_color = PROJECT_PATHS_SCRIPT.PALETTE_AMBER
	tooth_color = PROJECT_PATHS_SCRIPT.PALETTE_AMBER
	outline_color = PROJECT_PATHS_SCRIPT.PALETTE_CRIMSON
	spoke_count = 5
	spoke_width = 2.8
	_sync_module_profile()
	queue_redraw()
