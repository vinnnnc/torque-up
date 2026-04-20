## ClutchPlacementHandler
## Handles clutch snap preview, port-facing alignment, and single-click placement.
## Extracted from PlacementController.
extends "res://scripts/features/placement/handlers/placement_handler_base.gd"

const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")

const COMPONENT_CLUTCH := PROJECT_PATHS_SCRIPT.COMPONENT_CLUTCH
const OUTER_RADIUS := PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS * 1.05

const VALID_PREVIEW_COLOR := Color(0.45, 1.0, 0.45, 0.65)
const INVALID_PREVIEW_COLOR := Color(1.0, 0.35, 0.35, 0.65)

# -- Per-frame -----------------------------------------------------------------

func update_preview(mouse_pos: Vector2, preview_node: Node2D) -> void:
	if preview_node == null:
		return

	var selected_radius := get_connection_radius()
	var blocked_positions := ctx.get_cached_blocked_positions()
	var snap_result: Dictionary = ctx.placement_rules.get_snap_result(
		mouse_pos,
		ctx.components_container,
		ctx.get_cached_seed_positions(),
		blocked_positions,
		selected_radius
	)
	var snapped_pos: Vector2 = snap_result.get("position", mouse_pos)
	var use_snap := bool(snap_result.get("valid", false))
	preview_node.global_position = snapped_pos if use_snap else mouse_pos

	if use_snap:
		align_instance_with_origin(preview_node, snapped_pos, snap_result.get("origin", {}))

	var preview_is_clear: bool = ctx.placement_rules.can_place_at(
		preview_node.global_position, ctx.components_container, blocked_positions, selected_radius
	)
	ctx.socket_markers = ctx.placement_rules.get_nearest_available_socket_positions(
		mouse_pos, ctx.components_container,
		ctx.get_cached_seed_positions(), blocked_positions, selected_radius
	)
	ctx.active_socket_position = snapped_pos
	ctx.has_active_socket = use_snap and snap_result.get("origin", null) != null

	if preview_is_clear:
		preview_node.modulate = VALID_PREVIEW_COLOR
		ctx.active_socket_valid = use_snap
	else:
		preview_node.modulate = INVALID_PREVIEW_COLOR
		ctx.active_socket_valid = false

# -- Input ---------------------------------------------------------------------

func on_mouse_down(world_pos: Vector2) -> void:
	place(world_pos)

# -- Instance configuration ---------------------------------------------------

func configure_instance(instance: Node2D) -> void:
	if instance == null:
		return
	instance.set_meta("component_type", COMPONENT_CLUTCH)
	var visual := instance.get_node_or_null("Visual")
	if visual == null:
		return
	visual.set("visual_mode", "clutch")
	visual.set("use_module_profile", false)
	visual.set("outer_radius", OUTER_RADIUS)
	visual.set("inner_radius", OUTER_RADIUS * 0.56)
	visual.set("hub_radius", OUTER_RADIUS * 0.2)
	visual.set("body_color", Color(0.64, 0.55, 0.36, 1.0))
	visual.set("tooth_color", Color(0.86, 0.72, 0.46, 1.0))
	if visual.has_method("_sync_module_profile"):
		visual.call("_sync_module_profile")

# -- Placement -----------------------------------------------------------------

func place(world_pos: Vector2) -> void:
	var selected_radius := get_connection_radius()
	var blocked_positions := ctx.get_cached_blocked_positions()
	var snap_result: Dictionary = ctx.placement_rules.get_snap_result(
		world_pos,
		ctx.components_container,
		ctx.get_cached_seed_positions(),
		blocked_positions,
		selected_radius
	)
	var use_snap := bool(snap_result.get("valid", false))
	var snapped_pos: Vector2 = snap_result.get("position", world_pos)
	var target_pos := snapped_pos if use_snap else world_pos
	if not ctx.placement_rules.can_place_at(target_pos, ctx.components_container, blocked_positions, selected_radius):
		return

	var chosen_scene := ctx.get_scene(COMPONENT_CLUTCH)
	if chosen_scene == null:
		return
	var instance := chosen_scene.instantiate() as Node2D
	configure_instance(instance)
	if use_snap:
		align_instance_with_origin(instance, target_pos, snap_result.get("origin", {}))
	instance.global_position = target_pos
	ctx.components_container.add_child(instance)
	ctx.emit_gear_placed(instance)
	ctx.mark_dirty()

## Rotate so the clutch faces the origin gear (port toward the meshing point).
func align_instance_with_origin(gear: Node2D, snapped_pos: Vector2, origin_data: Variant) -> void:
	if gear == null or not origin_data is Dictionary:
		return
	var origin_node := (origin_data as Dictionary).get("node", null) as Node2D
	if origin_node == null:
		return
	var connection_angle := (snapped_pos - origin_node.global_position).angle()
	var toward_origin := wrapf(connection_angle + PI, -PI, PI)
	gear.rotation = toward_origin + (PI * 0.5)

# -- Radius helpers ------------------------------------------------------------

func get_outer_radius() -> float:
	return OUTER_RADIUS

func get_connection_radius() -> float:
	return maxf(2.0, OUTER_RADIUS - PROJECT_PATHS_SCRIPT.GEAR_MESH_CONTACT_MARGIN)
