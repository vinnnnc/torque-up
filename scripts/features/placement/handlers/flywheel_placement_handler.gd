## FlywheelPlacementHandler
## Handles flywheel preview, two-click placement between two gear endpoints,
## and the connecting drag-line overlay. Extracted from PlacementController.
extends "res://scripts/features/placement/handlers/placement_handler_base.gd"

const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")

const COMPONENT_FLYWHEEL := PROJECT_PATHS_SCRIPT.COMPONENT_FLYWHEEL
const COMPONENT_GEAR_SMALL := PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_SMALL
const COMPONENT_GEAR_MEDIUM := PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_MEDIUM
const COMPONENT_GEAR_LARGE := PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_LARGE

const OUTER_RADIUS := PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS * 1.45

const VALID_PREVIEW_COLOR := Color(0.45, 1.0, 0.45, 0.65)
const INVALID_PREVIEW_COLOR := Color(1.0, 0.35, 0.35, 0.65)

# -- Click state ---------------------------------------------------------------
var _first_gear: GearComponent = null

# -- Lifecycle -----------------------------------------------------------------

func deactivate() -> void:
	_first_gear = null

func cancel() -> void:
	_first_gear = null

# -- Per-frame -----------------------------------------------------------------

func update_preview(mouse_pos: Vector2, preview_node: Node2D) -> void:
	if preview_node == null:
		return

	var selected_radius := get_connection_radius()
	var blocked_positions := ctx.get_cached_blocked_positions()

	if _first_gear == null:
		# No first gear yet — float the preview at the mouse and mark all
		# valid gear endpoints as socket candidates.
		preview_node.global_position = mouse_pos
		preview_node.rotation = 0.0
		preview_node.modulate = VALID_PREVIEW_COLOR
		ctx.socket_markers = []
		for child in ctx.components_container.get_children():
			if _is_gear_endpoint(child as Node2D):
				ctx.socket_markers.append((child as Node2D).global_position)

		var first_candidate := _get_nearest_gear_at(mouse_pos, maxf(28.0, ctx.snap_max_distance))
		ctx.has_active_socket = first_candidate != null
		ctx.active_socket_valid = first_candidate != null
		if first_candidate != null:
			ctx.active_socket_position = first_candidate.global_position
		return

	# First gear locked — compute the flywheel span toward the nearest second.
	ctx.socket_markers = [_first_gear.global_position]
	var second_gear := _get_nearest_gear_at(mouse_pos, maxf(28.0, ctx.snap_max_distance))
	if second_gear == null or second_gear == _first_gear:
		preview_node.global_position = mouse_pos
		preview_node.modulate = INVALID_PREVIEW_COLOR
		ctx.has_active_socket = false
		ctx.active_socket_valid = false
		return

	ctx.socket_markers.append(second_gear.global_position)
	var flywheel_data := compute_data(_first_gear, second_gear)
	if flywheel_data.is_empty():
		preview_node.global_position = mouse_pos
		preview_node.modulate = INVALID_PREVIEW_COLOR
		ctx.has_active_socket = true
		ctx.active_socket_position = second_gear.global_position
		ctx.active_socket_valid = false
		return

	var preview_pos: Vector2 = flywheel_data["position"]
	var preview_rotation: float = flywheel_data["rotation"]
	var preview_half_length: float = flywheel_data["visual_half_length"]
	var preview_is_clear: bool = ctx.placement_rules.can_place_at(
		preview_pos, ctx.components_container, blocked_positions, selected_radius
	)
	preview_node.global_position = preview_pos
	preview_node.rotation = preview_rotation
	var preview_visual := preview_node.get_node_or_null("Visual")
	if preview_visual:
		preview_visual.set("flywheel_shaft_half_length", preview_half_length)
	preview_node.modulate = VALID_PREVIEW_COLOR if preview_is_clear else INVALID_PREVIEW_COLOR
	ctx.has_active_socket = true
	ctx.active_socket_position = second_gear.global_position
	ctx.active_socket_valid = preview_is_clear

## Draw the drag line and anchor circle from the first selected gear.
func draw_overlay(draw_node: Node2D) -> void:
	if _first_gear == null:
		return
	var first_local := draw_node.to_local(_first_gear.global_position)
	var flywheel_target := draw_node.get_global_mouse_position()
	var second_gear := _get_nearest_gear_at(flywheel_target, maxf(28.0, ctx.snap_max_distance))
	if second_gear != null and second_gear != _first_gear:
		flywheel_target = second_gear.global_position
	var target_local := draw_node.to_local(flywheel_target)
	draw_node.draw_line(first_local, target_local, Color(0.92, 0.95, 1.0, 0.48), 2.2)
	draw_node.draw_circle(first_local, 24.0, Color(0.92, 0.95, 1.0, 0.18))

# -- Input: two-click placement ------------------------------------------------

func on_click(world_pos: Vector2) -> void:
	var clicked_gear := _get_nearest_gear_at(world_pos, maxf(28.0, ctx.snap_max_distance))
	if clicked_gear == null:
		return

	if _first_gear == null:
		_first_gear = clicked_gear
		return

	if clicked_gear == _first_gear:
		_first_gear = null
		return

	place(_first_gear, clicked_gear)
	_first_gear = null
	ctx.mark_dirty()

# -- Instance configuration ---------------------------------------------------

func configure_instance(instance: Node2D) -> void:
	if instance == null:
		return
	instance.set_meta("component_type", COMPONENT_FLYWHEEL)
	var visual := instance.get_node_or_null("Visual")
	if visual == null:
		return
	visual.set("visual_mode", "flywheel")
	visual.set("use_module_profile", false)
	visual.set("outer_radius", OUTER_RADIUS)
	visual.set("inner_radius", OUTER_RADIUS * 0.78)
	visual.set("hub_radius", OUTER_RADIUS * 0.24)
	visual.set("flywheel_shaft_half_length", OUTER_RADIUS + 10.0)
	visual.set("shaft_body_thickness", 8.0)
	visual.set("shaft_coupler_radius", 8.2)
	visual.set("body_color", Color(0.34, 0.37, 0.41, 1.0))
	visual.set("tooth_color", Color(0.52, 0.56, 0.60, 1.0))
	if visual.has_method("_sync_module_profile"):
		visual.call("_sync_module_profile")

# -- Placement -----------------------------------------------------------------

func place(first_gear: GearComponent, second_gear: GearComponent) -> void:
	if first_gear == null or second_gear == null:
		return

	var flywheel_data := compute_data(first_gear, second_gear)
	if flywheel_data.is_empty():
		return

	var flywheel_pos: Vector2 = flywheel_data["position"]
	var flywheel_rotation: float = flywheel_data["rotation"]
	var flywheel_connection_radius: float = flywheel_data["connection_radius"]
	var flywheel_visual_half_length: float = flywheel_data["visual_half_length"]
	var selected_radius := get_connection_radius()

	if not ctx.placement_rules.can_place_at(
		flywheel_pos, ctx.components_container, ctx.get_cached_blocked_positions(), selected_radius
	):
		return

	var chosen_scene := ctx.get_scene(COMPONENT_FLYWHEEL)
	if chosen_scene == null:
		return
	var flywheel := chosen_scene.instantiate() as Node2D
	if flywheel == null:
		return

	configure_instance(flywheel)
	flywheel.set_meta("shaft_connection_radius", flywheel_connection_radius)
	flywheel.set_meta("flywheel_block_radius", selected_radius)
	flywheel.set_meta("shaft_end_a_id", first_gear.get_instance_id())
	flywheel.set_meta("shaft_end_b_id", second_gear.get_instance_id())
	flywheel.global_position = flywheel_pos
	flywheel.rotation = flywheel_rotation

	var flywheel_visual := flywheel.get_node_or_null("Visual")
	if flywheel_visual:
		flywheel_visual.set("flywheel_shaft_half_length", flywheel_visual_half_length)

	ctx.components_container.add_child(flywheel)
	ctx.emit_gear_placed(flywheel)

# -- Geometry ------------------------------------------------------------------

func compute_data(first_gear: GearComponent, second_gear: GearComponent) -> Dictionary:
	if first_gear == null or second_gear == null:
		return {}
	var first_pos: Vector2 = first_gear.global_position
	var second_pos: Vector2 = second_gear.global_position
	var center_delta: Vector2 = second_pos - first_pos
	if center_delta.length_squared() <= 0.0001:
		return {}
	var dir: Vector2 = center_delta.normalized()
	var first_radius: float = ctx.get_node_connection_radius(first_gear)
	var second_radius: float = ctx.get_node_connection_radius(second_gear)
	var start_contact: Vector2 = first_pos + (dir * first_radius)
	var end_contact: Vector2 = second_pos - (dir * second_radius)
	var span: float = (end_contact - start_contact).length()
	var flywheel_connection_radius: float = span * 0.5
	if flywheel_connection_radius < PROJECT_PATHS_SCRIPT.SHAFT_MIN_CONNECTION_RADIUS:
		return {}
	return {
		"position": first_pos.lerp(second_pos, 0.5),
		"rotation": center_delta.angle(),
		"connection_radius": flywheel_connection_radius,
		"visual_half_length": first_pos.distance_to(second_pos) * 0.5
	}

# -- Radius helpers ------------------------------------------------------------

func get_outer_radius() -> float:
	return OUTER_RADIUS

func get_connection_radius() -> float:
	return maxf(2.0, OUTER_RADIUS - PROJECT_PATHS_SCRIPT.GEAR_MESH_CONTACT_MARGIN)

# -- Query helpers -------------------------------------------------------------

func _get_nearest_gear_at(world_pos: Vector2, max_distance: float) -> GearComponent:
	var nearest: GearComponent = null
	var nearest_distance := max_distance
	for child in ctx.components_container.get_children():
		var node := child as Node2D
		if not _is_gear_endpoint(node):
			continue
		var gear := node as GearComponent
		var distance := gear.global_position.distance_to(world_pos)
		if distance < nearest_distance:
			nearest = gear
			nearest_distance = distance
	return nearest

func _is_gear_endpoint(node: Node2D) -> bool:
	if node == null or not (node is GearComponent):
		return false
	var ctype := str(node.get_meta("component_type", ""))
	return ctype == COMPONENT_GEAR_SMALL or ctype == COMPONENT_GEAR_MEDIUM or ctype == COMPONENT_GEAR_LARGE

## Returns the current first gear (used by PlacementController._draw).
func get_first_gear() -> GearComponent:
	return _first_gear
