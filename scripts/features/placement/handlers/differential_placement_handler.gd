## DifferentialPlacementHandler
## Handles differential snap preview, best-port alignment, and single-click placement.
## Extracted from PlacementController.
extends "res://scripts/features/placement/handlers/placement_handler_base.gd"

const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")

const COMPONENT_DIFFERENTIAL := PROJECT_PATHS_SCRIPT.COMPONENT_DIFFERENTIAL
const OUTER_RADIUS := PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS * 1.25

## Local port angles (radians) that the differential exposes as valid input faces.
## Matches the port positions defined in the differential visual.
const INPUT_PORT_ANGLES: Array = [-2.35, -0.79]

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
	instance.set_meta("component_type", COMPONENT_DIFFERENTIAL)
	var visual := instance.get_node_or_null("Visual")
	if visual == null:
		return
	visual.set("visual_mode", "differential")
	visual.set("use_module_profile", false)
	visual.set("outer_radius", OUTER_RADIUS)
	visual.set("inner_radius", OUTER_RADIUS * 0.62)
	visual.set("hub_radius", OUTER_RADIUS * 0.22)
	visual.set("body_color", Color(0.41, 0.47, 0.55, 1.0))
	visual.set("tooth_color", Color(0.62, 0.7, 0.8, 1.0))
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

	var chosen_scene := ctx.get_scene(COMPONENT_DIFFERENTIAL)
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

## Rotate so the nearest input port faces the origin gear.
func align_instance_with_origin(gear: Node2D, snapped_pos: Vector2, origin_data: Variant) -> void:
	if gear == null or not origin_data is Dictionary:
		return
	var origin_node := (origin_data as Dictionary).get("node", null) as Node2D
	if origin_node == null:
		return
	var connection_angle := (snapped_pos - origin_node.global_position).angle()
	var toward_origin := wrapf(connection_angle + PI, -PI, PI)
	gear.rotation = _best_port_rotation(toward_origin, INPUT_PORT_ANGLES, gear.rotation)

## Pick the port rotation that minimises the delta from the current rotation.
func _best_port_rotation(target_world_angle: float, local_port_angles: Array, current_rotation: float) -> float:
	if local_port_angles.is_empty():
		return target_world_angle
	var best_rotation := target_world_angle - float(local_port_angles[0])
	var best_delta := INF
	for port_raw in local_port_angles:
		var port_angle := float(port_raw)
		var candidate := target_world_angle - port_angle
		var delta := absf(wrapf(candidate - current_rotation, -PI, PI))
		if delta < best_delta:
			best_delta = delta
			best_rotation = candidate
	return wrapf(best_rotation, -PI, PI)

# -- Radius helpers ------------------------------------------------------------

func get_outer_radius() -> float:
	return OUTER_RADIUS

func get_connection_radius() -> float:
	return maxf(2.0, OUTER_RADIUS - PROJECT_PATHS_SCRIPT.GEAR_MESH_CONTACT_MARGIN)
