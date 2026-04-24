@tool
extends GearVisual

# const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")

func _ready() -> void:
	visual_mode = "gear"
	outer_radius = PROJECT_PATHS_SCRIPT.LARGE_GEAR_OUTER_RADIUS
	# Calculate inner_radius based on module to match actual gear geometry
	var tooth_depth: float = PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_ADDENDUM + PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_DEDENDUM
	inner_radius = maxf(1.0, outer_radius - tooth_depth)
	tooth_count = max(tooth_count, 20)
	queue_redraw()

