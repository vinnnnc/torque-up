extends Node2D
## Semi-transparent dark overlay drawn above gameplay nodes for the area outside
## the unlocked frontier cone. Spawned and owned by blockade_visual.

const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")
const FRONTIER_GEOMETRY_SCRIPT = preload("res://scripts/features/world/frontier_geometry.gd")

var blockade: Node2D = null


func _draw() -> void:
	if blockade == null:
		return
	var half_w : Variant= blockade.world_half_width * 2.0
	var half_h : Variant= blockade.world_height * 2.0
	var apex: Vector2 = blockade.get_cone_apex_world()
	var pts := FRONTIER_GEOMETRY_SCRIPT.build_full_outside_polygon(
		apex,
		blockade.get_cone_half_angle_radians(),
		apex.x - half_w,
		apex.x + half_w,
		apex.y - half_h,
		apex.y + half_h
	)
	if pts.size() > 2:
		draw_colored_polygon(pts, blockade.outside_overlay_color)
