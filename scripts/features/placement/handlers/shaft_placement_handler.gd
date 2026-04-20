## ShaftPlacementHandler
## Handles shaft preview, drag, and placement between two gear endpoints.
## Extracted from PlacementController.
extends "res://scripts/features/placement/handlers/placement_handler_base.gd"

const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")
const SHAFT_COMPONENT_SCRIPT_PATH := "res://scripts/components/shaft_link.gd"

const COMPONENT_SHAFT := PROJECT_PATHS_SCRIPT.COMPONENT_SHAFT
const COMPONENT_GEAR_SMALL := PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_SMALL
const COMPONENT_GEAR_MEDIUM := PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_MEDIUM
const COMPONENT_GEAR_LARGE := PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_LARGE
const COMPONENT_FLYWHEEL := PROJECT_PATHS_SCRIPT.COMPONENT_FLYWHEEL
const COMPONENT_CLUTCH := PROJECT_PATHS_SCRIPT.COMPONENT_CLUTCH
const COMPONENT_DIFFERENTIAL := PROJECT_PATHS_SCRIPT.COMPONENT_DIFFERENTIAL
const SHAFT_PLACEMENT_BLOCK_RADIUS := PROJECT_PATHS_SCRIPT.SHAFT_MIN_CONNECTION_RADIUS

# -- Drag state ----------------------------------------------------------------
var _first_gear: GearComponent = null
var _drag_start_mouse: Vector2 = Vector2.ZERO

# -- Lifecycle -----------------------------------------------------------------

func deactivate() -> void:
	_first_gear = null
	_drag_start_mouse = Vector2.ZERO

func cancel() -> void:
	_first_gear = null
	_drag_start_mouse = Vector2.ZERO

# -- Per-frame -----------------------------------------------------------------

## Show socket markers on valid endpoint candidates.
## When dragging, highlight the first gear and nearest second candidate.
func update_preview(mouse_pos: Vector2, _preview_node: Node2D) -> void:
	if _first_gear == null:
		ctx.socket_markers = _get_all_endpoint_positions()
		ctx.has_active_socket = false
		ctx.active_socket_valid = false
		return

	var second_gear := get_nearest_candidate_at(mouse_pos, maxf(28.0, ctx.snap_max_distance))
	var valid := second_gear != null and second_gear != _first_gear and not _link_exists(_first_gear, second_gear)
	ctx.has_active_socket = true
	ctx.active_socket_position = _first_gear.global_position
	ctx.active_socket_valid = valid
	ctx.socket_markers = [_first_gear.global_position]
	if second_gear != null and second_gear != _first_gear:
		ctx.socket_markers.append(second_gear.global_position)

## Draw the drag line and anchor circle from the first selected gear.
func draw_overlay(draw_node: Node2D) -> void:
	if _first_gear == null:
		return
	var first_local := draw_node.to_local(_first_gear.global_position)
	var shaft_target := draw_node.get_global_mouse_position()
	var second_gear := get_nearest_candidate_at(shaft_target, maxf(28.0, ctx.snap_max_distance))
	if second_gear != null and second_gear != _first_gear:
		shaft_target = second_gear.global_position
	var target_local := draw_node.to_local(shaft_target)
	draw_node.draw_line(first_local, target_local, Color(0.76, 0.9, 1.0, 0.55), 2.0)
	draw_node.draw_circle(first_local, 26.0, Color(0.76, 0.9, 1.0, 0.22))

# -- Input ---------------------------------------------------------------------

func on_mouse_down(world_pos: Vector2) -> void:
	_first_gear = get_nearest_candidate_at(world_pos, maxf(28.0, ctx.snap_max_distance))
	_drag_start_mouse = world_pos

func on_mouse_up(world_pos: Vector2) -> void:
	if _first_gear == null:
		return
	if _drag_start_mouse.distance_to(world_pos) < ctx.drag_release_deadzone:
		_first_gear = null
		return
	var second_gear := get_nearest_candidate_at(world_pos, maxf(28.0, ctx.snap_max_distance))
	if second_gear != null and second_gear != _first_gear:
		place_between_gears(_first_gear, second_gear)
	_first_gear = null

# -- Instance configuration ---------------------------------------------------

func configure_instance(instance: Node2D) -> void:
	if instance == null:
		return
	instance.set_meta("component_type", COMPONENT_SHAFT)
	var visual := instance.get_node_or_null("Visual")
	if visual == null:
		return
	visual.set("use_module_profile", false)
	visual.set("visual_mode", "shaft")
	visual.set("shaft_module_size", PROJECT_PATHS_SCRIPT.SHAFT_SHAPE_MODULE)
	visual.set("inner_radius", 4.8)
	visual.set("hub_radius", 3.8)
	visual.set("tooth_count", 0)
	if visual.has_method("_sync_module_profile"):
		visual.call("_sync_module_profile")

# -- Placement -----------------------------------------------------------------

## Gear-to-gear shaft: the primary placement path (drag to connect two gears).
func place_between_gears(first_gear: GearComponent, second_gear: GearComponent) -> void:
	if first_gear == null or second_gear == null:
		return
	if _link_exists(first_gear, second_gear):
		return

	var shaft_script := load(SHAFT_COMPONENT_SCRIPT_PATH)
	if shaft_script == null:
		return

	var shaft_data := compute_data_between_gears(first_gear, second_gear)
	if shaft_data.is_empty():
		return

	var shaft_pos: Vector2 = shaft_data["position"]
	var shaft_rotation: float = shaft_data["rotation"]
	var shaft_connection_radius: float = shaft_data["connection_radius"]

	var shaft := Node2D.new()
	var shaft_component: Node = shaft_script.new()
	if shaft_component == null:
		return
	shaft.add_child(shaft_component)
	if shaft_component.has_method("configure"):
		shaft_component.configure(first_gear, second_gear)
	shaft.set_meta("component_type", COMPONENT_SHAFT)
	shaft.set_meta("shaft_connection_radius", shaft_connection_radius)
	shaft.set_meta("shaft_block_radius", 2.0)
	shaft.set_meta("shaft_end_a_id", first_gear.get_instance_id())
	shaft.set_meta("shaft_end_b_id", second_gear.get_instance_id())
	shaft.global_position = shaft_pos
	shaft.rotation = shaft_rotation
	ctx.components_container.add_child(shaft)
	ctx.emit_gear_placed(shaft)
	ctx.mark_dirty()

## Legacy origin-point shaft placement (single click from a snap origin).
func place_from_origin(world_pos: Vector2) -> void:
	var start_origin := _get_nearest_origin(world_pos, PROJECT_PATHS_SCRIPT.SHAFT_PICK_DISTANCE)
	if start_origin.is_empty():
		return
	var shaft_data := compute_data_from_origin(start_origin, world_pos)
	if shaft_data.is_empty():
		return

	var shaft_pos: Vector2 = shaft_data["position"]
	var shaft_rotation: float = shaft_data["rotation"]
	var shaft_outer_radius: float = shaft_data["outer_radius"]
	var shaft_connection_radius: float = shaft_data["connection_radius"]
	if not _is_candidate_clear(shaft_pos, shaft_connection_radius, [start_origin]):
		return

	var chosen_scene := ctx.get_scene(COMPONENT_SHAFT)
	if chosen_scene == null:
		return
	var shaft := chosen_scene.instantiate() as Node2D
	configure_instance(shaft)
	_configure_runtime_visual(shaft, shaft_outer_radius)
	shaft.set_meta("shaft_connection_radius", shaft_connection_radius)
	shaft.set_meta("shaft_block_radius", SHAFT_PLACEMENT_BLOCK_RADIUS)
	shaft.global_position = shaft_pos
	shaft.rotation = shaft_rotation
	ctx.components_container.add_child(shaft)
	ctx.emit_gear_placed(shaft)
	ctx.mark_dirty()

# -- Geometry ------------------------------------------------------------------

func compute_data_between_gears(first_gear: GearComponent, second_gear: GearComponent) -> Dictionary:
	if first_gear == null or second_gear == null:
		return {}
	var first_pos := first_gear.global_position
	var second_pos := second_gear.global_position
	var center_delta := second_pos - first_pos
	if center_delta.length_squared() <= 0.0001:
		return {}
	var dir := center_delta.normalized()
	var first_radius := ctx.get_node_connection_radius(first_gear)
	var second_radius := ctx.get_node_connection_radius(second_gear)
	var start_contact := first_pos + (dir * first_radius)
	var end_contact := second_pos - (dir * second_radius)
	var span := end_contact - start_contact
	var shaft_connection_radius := span.length() * 0.5
	if shaft_connection_radius < PROJECT_PATHS_SCRIPT.SHAFT_MIN_CONNECTION_RADIUS:
		return {}
	shaft_connection_radius = minf(shaft_connection_radius, PROJECT_PATHS_SCRIPT.SHAFT_MAX_CONNECTION_RADIUS)
	return {
		"position": first_pos.lerp(second_pos, 0.5),
		"rotation": dir.angle(),
		"connection_radius": shaft_connection_radius,
		"outer_radius": shaft_connection_radius + PROJECT_PATHS_SCRIPT.GEAR_MESH_CONTACT_MARGIN,
		"visual_outer_radius": first_pos.distance_to(second_pos) * 0.5
	}

func compute_data_from_origin(start_origin: Dictionary, world_pos: Vector2) -> Dictionary:
	var start_pos: Vector2 = start_origin.get("position", Vector2.ZERO)
	var start_radius: float = float(start_origin.get("radius", 0.0))
	var direction := world_pos - start_pos
	if direction.length_squared() <= 0.0001:
		direction = Vector2.RIGHT
	else:
		direction = direction.normalized()
	var raw_connection_radius := world_pos.distance_to(start_pos) - start_radius
	var shaft_connection_radius := clampf(
		raw_connection_radius,
		PROJECT_PATHS_SCRIPT.SHAFT_MIN_CONNECTION_RADIUS,
		PROJECT_PATHS_SCRIPT.SHAFT_MAX_CONNECTION_RADIUS
	)
	var shaft_center := start_pos + (direction * (start_radius + shaft_connection_radius))
	return {
		"position": shaft_center,
		"rotation": direction.angle(),
		"connection_radius": shaft_connection_radius,
		"outer_radius": shaft_connection_radius + PROJECT_PATHS_SCRIPT.GEAR_MESH_CONTACT_MARGIN,
		"visual_outer_radius": shaft_connection_radius + PROJECT_PATHS_SCRIPT.GEAR_MESH_CONTACT_MARGIN
	}

# -- Query helpers -------------------------------------------------------------

## Return all GearComponents that can be a shaft endpoint.
func get_nearest_candidate_at(world_pos: Vector2, max_distance: float) -> GearComponent:
	var nearest: GearComponent = null
	var nearest_distance := max_distance
	for child in ctx.components_container.get_children():
		var node := child as Node2D
		if not is_endpoint_candidate(node):
			continue
		var gear := node as GearComponent
		var distance := gear.global_position.distance_to(world_pos)
		if distance < nearest_distance:
			nearest = gear
			nearest_distance = distance
	return nearest

func is_endpoint_candidate(node: Node2D) -> bool:
	if node == null or not (node is GearComponent):
		return false
	var ctype := str(node.get_meta("component_type", ""))
	return (
		ctype == COMPONENT_GEAR_SMALL
		or ctype == COMPONENT_GEAR_MEDIUM
		or ctype == COMPONENT_GEAR_LARGE
		or ctype == COMPONENT_FLYWHEEL
		or ctype == COMPONENT_CLUTCH
		or ctype == COMPONENT_DIFFERENTIAL
	)

func _link_exists(first_gear: GearComponent, second_gear: GearComponent) -> bool:
	if first_gear == null or second_gear == null:
		return false
	var first_id := first_gear.get_instance_id()
	var second_id := second_gear.get_instance_id()
	for child in ctx.components_container.get_children():
		var node := child as Node2D
		if node == null:
			continue
		if str(node.get_meta("component_type", "")) != COMPONENT_SHAFT:
			continue
		if not node.has_meta("shaft_end_a_id"):
			continue
		var a := int(node.get_meta("shaft_end_a_id", -1))
		var b := int(node.get_meta("shaft_end_b_id", -1))
		if (a == first_id and b == second_id) or (a == second_id and b == first_id):
			return true
	return false

func _get_all_endpoint_positions() -> Array:
	var positions: Array = []
	for child in ctx.components_container.get_children():
		var node := child as Node2D
		if is_endpoint_candidate(node):
			positions.append(node.global_position)
	return positions

func _get_nearest_origin(world_pos: Vector2, max_pick_distance: float) -> Dictionary:
	var nearest_origin: Dictionary = {}
	var nearest_distance := INF
	for origin_raw in ctx.get_all_snap_origins():
		if not origin_raw is Dictionary:
			continue
		var origin := origin_raw as Dictionary
		var origin_pos: Vector2 = origin.get("position", Vector2.ZERO)
		var distance := origin_pos.distance_to(world_pos)
		if distance > max_pick_distance:
			continue
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_origin = origin
	return nearest_origin

func _is_candidate_clear(candidate_pos: Vector2, candidate_radius: float, ignore_origins: Array) -> bool:
	var ignored_nodes: Dictionary = {}
	for origin_raw in ignore_origins:
		if not origin_raw is Dictionary:
			continue
		var origin_node := (origin_raw as Dictionary).get("node", null) as Node2D
		if origin_node:
			ignored_nodes[origin_node.get_instance_id()] = true

	for child in ctx.components_container.get_children():
		var placed := child as Node2D
		if placed == null or ignored_nodes.has(placed.get_instance_id()):
			continue
		var placed_radius := ctx.get_node_connection_radius(placed)
		if placed.global_position.distance_to(candidate_pos) < (candidate_radius + placed_radius - 0.6):
			return false

	for blocked_raw in ctx.get_cached_blocked_positions():
		if not blocked_raw is Dictionary:
			continue
		var blocked := blocked_raw as Dictionary
		var blocked_pos: Vector2 = blocked.get("position", Vector2.ZERO)
		var blocked_radius: float = float(blocked.get("radius", PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS))
		if blocked_pos.distance_to(candidate_pos) < (candidate_radius + blocked_radius - 1.0):
			return false

	return true

# -- Visual config helpers -----------------------------------------------------

func _configure_runtime_visual(shaft: Node2D, outer_radius: float) -> void:
	if shaft == null:
		return
	var visual := shaft.get_node_or_null("Visual")
	if visual == null:
		return
	visual.set("outer_radius", outer_radius)
	visual.set("shaft_module_size", PROJECT_PATHS_SCRIPT.SHAFT_SHAPE_MODULE)
	visual.set("inner_radius", 4.8)
	visual.set("hub_radius", 3.8)
	if visual.has_method("queue_redraw"):
		visual.call("queue_redraw")

## Returns the current in-progress first gear (used by PlacementController._draw).
func get_first_gear() -> GearComponent:
	return _first_gear
