extends Control
class_name MinimapView

const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")
const FRONTIER_GEOMETRY_SCRIPT = preload("res://scripts/features/world/frontier_geometry.gd")

@export var background_color: Color = Color(0.05, 0.07, 0.09, 0.9)
@export var blocked_color: Color = Color(0.02, 0.03, 0.04, 0.92)
@export var unlocked_fill_color: Color = Color(0.17, 0.25, 0.31, 0.72)
@export var frontier_color: Color = Color(0.76, 0.9, 1.0, 0.95)
@export var camera_rect_color: Color = Color(0.98, 0.96, 0.74, 0.95)
@export var engine_color: Color = Color(0.96, 0.76, 0.42, 1.0)
@export var power_color: Color = Color(0.48, 0.78, 1.0, 1.0)
@export var component_color: Color = Color(0.88, 0.9, 0.95, 0.75)
@export var high_speed_component_color: Color = Color(1.0, 0.86, 0.44, 0.95)
@export var high_speed_ring_color: Color = Color(1.0, 0.9, 0.6, 0.7)

var _camera: Camera2D = null
var _frontier: Node = null
var _network: Node2D = null
var _components: Node2D = null
var _engine: Node2D = null

var _dragging: bool = false
var _refresh_accum: float = 0.0
var _pulse_phase: float = 0.0


func set_context(camera_node: Camera2D, frontier_node: Node, network_node: Node2D, components_node: Node2D, engine_node: Node2D) -> void:
	_camera = camera_node
	_frontier = frontier_node
	_network = network_node
	_components = components_node
	_engine = engine_node
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	queue_redraw()


func _process(delta: float) -> void:
	_pulse_phase = wrapf(_pulse_phase + (delta * 3.2), 0.0, TAU)
	_refresh_accum += delta
	if _dragging or _refresh_accum >= 0.08:
		_refresh_accum = 0.0
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button_event := event as InputEventMouseButton
		if button_event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button_event.pressed
			if button_event.pressed:
				_move_camera_from_local(button_event.position)
			accept_event()
			return

	if event is InputEventMouseMotion and _dragging:
		var motion_event := event as InputEventMouseMotion
		_move_camera_from_local(motion_event.position)
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), background_color, true)
	if _camera == null or _engine == null:
		return

	var center_world := _get_frontier_apex_world()
	var frontier_radius := _get_frontier_radius()
	var map_radius_world := _compute_map_radius_world(center_world, frontier_radius)
	var radius_px := _get_map_radius_px()
	var scale_map := radius_px / map_radius_world
	var center_px := _get_map_center_px()
 
	var half_angle := _get_cone_half_angle_radians()
	var frustum_inner_world := minf(_get_frontier_frustum_inner_radius_world(), maxf(frontier_radius - 1.0, 0.0))
	var frustum_inner_px := frustum_inner_world * scale_map

	# Blocked region covers entire minimap area outside the upward cone.
	var blocked_pts := FRONTIER_GEOMETRY_SCRIPT.build_full_outside_polygon(
		center_px, half_angle, 0.0, size.x, 0.0, size.y
	)
	draw_colored_polygon(blocked_pts, blocked_color)

	# Unlocked cone-sector fill.
	var fill_pts := FRONTIER_GEOMETRY_SCRIPT.build_upward_cone_sector(center_px, frontier_radius * scale_map, half_angle, 56)
	fill_pts = FRONTIER_GEOMETRY_SCRIPT.clamp_polygon_points(fill_pts, 0.0, size.x, 0.0, size.y)
	draw_colored_polygon(fill_pts, unlocked_fill_color)
	if frustum_inner_px > 0.5:
		var bottom_mask := FRONTIER_GEOMETRY_SCRIPT.build_upward_cone_sector(center_px, frustum_inner_px, half_angle, 48)
		bottom_mask = FRONTIER_GEOMETRY_SCRIPT.clamp_polygon_points(bottom_mask, 0.0, size.x, 0.0, size.y)
		draw_colored_polygon(bottom_mask, blocked_color)

	# Frontier ring arc + side rays.
	var up_angle := -PI * 0.5
	var right_angle := up_angle + half_angle
	var left_angle := up_angle - half_angle
	draw_arc(center_px, frontier_radius * scale_map, left_angle, right_angle, 72, frontier_color, 1.8, true)
	if frustum_inner_px > 0.5:
		draw_arc(center_px, frustum_inner_px, left_angle, right_angle, 48, frontier_color, 1.2, true)
	var left_edge := center_px + (Vector2.RIGHT.rotated(left_angle) * frontier_radius * scale_map)
	var right_edge := center_px + (Vector2.RIGHT.rotated(right_angle) * frontier_radius * scale_map)
	var left_inner := center_px + (Vector2.RIGHT.rotated(left_angle) * frustum_inner_px)
	var right_inner := center_px + (Vector2.RIGHT.rotated(right_angle) * frustum_inner_px)
	draw_line(left_inner if frustum_inner_px > 0.5 else center_px, left_edge, frontier_color, 1.4, true)
	draw_line(right_inner if frustum_inner_px > 0.5 else center_px, right_edge, frontier_color, 1.4, true)

	# Nodes.
	var engine_px := _world_to_map(_engine.global_position, center_world, center_px, scale_map)
	var engine_radius_px := maxf(_get_engine_radius_world() * scale_map, 3.8)
	draw_circle(engine_px, engine_radius_px, engine_color)
	draw_arc(engine_px, engine_radius_px, 0.0, TAU, 40, Color(1.0, 0.94, 0.72, 0.9), 1.1, true)
	_draw_power_nodes(center_world, map_radius_world, center_px, scale_map)
	_draw_components(center_world, map_radius_world, center_px, scale_map)

	# Camera viewport marker.
	var camera_center_px := _world_to_map(_camera.global_position, center_world, center_px, scale_map)
	var viewport_world_size := get_viewport().get_visible_rect().size / _camera.zoom.x
	var viewport_px_size := viewport_world_size * scale_map
	var cam_rect := Rect2(camera_center_px - (viewport_px_size * 0.5), viewport_px_size)
	draw_rect(cam_rect, camera_rect_color, false, 1.6)


func _draw_power_nodes(center_world: Vector2, map_radius_world: float, center_px: Vector2, scale: float) -> void:
	if _network == null:
		return
	for child in _network.get_children():
		var node := child as Node2D
		if node == null:
			continue
		if not node.name.begins_with("Power"):
			continue
		if center_world.distance_to(node.global_position) > map_radius_world:
			continue
		draw_circle(_world_to_map(node.global_position, center_world, center_px, scale), 2.8, power_color)


func _draw_components(center_world: Vector2, map_radius_world: float, center_px: Vector2, scale: float) -> void:
	if _components == null:
		return
	for child in _components.get_children():
		var node := child as Node2D
		if node == null:
			continue
		if center_world.distance_to(node.global_position) > map_radius_world:
			continue
		var node_px := _world_to_map(node.global_position, center_world, center_px, scale)
		var rpm := _get_component_rpm(node)
		if rpm >= PROJECT_PATHS_SCRIPT.DRIVETRAIN_HIGH_SPEED_VISUAL_RPM:
			draw_circle(node_px, 2.1, high_speed_component_color)
			var pulse := 0.7 + (0.5 * (sin(_pulse_phase + (node_px.x * 0.02)) * 0.5 + 0.5))
			draw_arc(node_px, 3.4 + pulse, 0.0, TAU, 20, high_speed_ring_color, 1.2, true)
		else:
			draw_circle(node_px, 1.6, component_color)


func _get_component_rpm(component: Node2D) -> float:
	if component == null:
		return 0.0
	var component_type := str(component.get_meta("component_type", ""))
	if component_type == PROJECT_PATHS_SCRIPT.COMPONENT_CHAIN:
		return _get_average_endpoint_rpm(component.get("pulley_a") as Node2D, component.get("pulley_b") as Node2D)
	if component_type == PROJECT_PATHS_SCRIPT.COMPONENT_SHAFT:
		return _get_average_endpoint_rpm(component.get("gear_a") as Node2D, component.get("gear_b") as Node2D)
	if component.has_method("get_angular_velocity"):
		return _to_rpm(float(component.call("get_angular_velocity")))
	var angular_velocity: Variant = component.get("angular_velocity")
	if angular_velocity == null:
		return 0.0
	return _to_rpm(float(angular_velocity))


func _get_average_endpoint_rpm(a: Node2D, b: Node2D) -> float:
	var values: Array = []
	if a != null:
		var angular_a: Variant = a.get("angular_velocity")
		if angular_a != null:
			values.append(_to_rpm(float(angular_a)))
	if b != null:
		var angular_b: Variant = b.get("angular_velocity")
		if angular_b != null:
			values.append(_to_rpm(float(angular_b)))
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value_raw in values:
		total += float(value_raw)
	return total / float(values.size())


func _to_rpm(angular_speed: float) -> float:
	return absf(angular_speed) * (60.0 / TAU)


func _get_frontier_radius() -> float:
	if _frontier != null and _frontier.has_method("get_visual_unlocked_radius"):
		return float(_frontier.call("get_visual_unlocked_radius"))
	if _frontier != null and _frontier.has_method("get_unlocked_radius"):
		return float(_frontier.call("get_unlocked_radius"))
	return PROJECT_PATHS_SCRIPT.FRONTIER_BASE_RADIUS


func _compute_map_radius_world(center_world: Vector2, frontier_radius: float) -> float:
	var camera_dist := center_world.distance_to(_camera.global_position)
	var zoom_factor := maxf(_camera.zoom.x, 0.001)
	var viewport_half_diag := get_viewport().get_visible_rect().size.length() * 0.5 / zoom_factor
	var base := maxf(900.0, frontier_radius * 1.35)
	return maxf(base, camera_dist + viewport_half_diag + 140.0)


func _get_frontier_frustum_inner_radius_world() -> float:
	# Draw the minimap frontier as a truncated cone using engine footprint as
	# the bottom cap reference so the cone reads as a frustum near the engine.
	return _get_engine_radius_world()


func _get_engine_radius_world() -> float:
	if _engine == null:
		return PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS

	var resolved_radius := PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS

	var visual := _engine.get_node_or_null("Visual")
	if visual != null:
		var visual_outer_radius: Variant = visual.get("outer_radius")
		if visual_outer_radius != null:
			resolved_radius = maxf(resolved_radius, maxf(2.0, float(visual_outer_radius)))

	var source_outer_radius: Variant = _engine.get("source_outer_radius")
	if source_outer_radius != null:
		var source_radius := float(source_outer_radius)
		if source_radius > 0.0:
			resolved_radius = maxf(resolved_radius, source_radius)

	return resolved_radius


func _get_map_center_px() -> Vector2:
	# Engine/frontier origin sits near the minimap bottom edge because world below
	# the engine is not playable.
	return Vector2(size.x * 0.5, size.y - 8.0)


func _get_map_radius_px() -> float:
	# Radius is width-limited and also clamped to the available space above center.
	var center_y := _get_map_center_px().y
	var max_vertical := maxf(24.0, center_y - 6.0)
	var max_horizontal := maxf(24.0, size.x * 0.5 - 6.0)
	return minf(max_horizontal, max_vertical)


func _world_to_map(world_pos: Vector2, center_world: Vector2, center_px: Vector2, scale: float) -> Vector2:
	return center_px + ((world_pos - center_world) * scale)


func _move_camera_from_local(local_pos: Vector2) -> void:
	if _camera == null or _engine == null:
		return

	var center_world := _get_frontier_apex_world()
	var frontier_radius := _get_frontier_radius()
	var map_radius_world := _compute_map_radius_world(center_world, frontier_radius)
	var center_px := _get_map_center_px()
	var radius_px := _get_map_radius_px()
	var scale := radius_px / map_radius_world

	var delta_px := local_pos - center_px
	if delta_px.length() > radius_px:
		delta_px = delta_px.normalized() * radius_px

	var delta_world := delta_px / scale
	var target_world := center_world + delta_world
	target_world = _constrain_world_to_cone(target_world, center_world)

	if _frontier != null and _frontier.has_method("constrain_world_position"):
		var constrained: Variant = _frontier.call("constrain_world_position", target_world, 0.0, false)
		if constrained is Vector2:
			target_world = constrained

	_camera.global_position = target_world
	queue_redraw()


func _get_frontier_apex_world() -> Vector2:
	if _frontier != null and _frontier.has_method("get_cone_apex_world"):
		var apex: Variant = _frontier.call("get_cone_apex_world")
		if apex is Vector2:
			return apex
	return _engine.global_position


func _get_cone_half_angle_radians() -> float:
	if _frontier != null and _frontier.has_method("get_cone_half_angle_radians"):
		return float(_frontier.call("get_cone_half_angle_radians"))
	return deg_to_rad(PROJECT_PATHS_SCRIPT.FRONTIER_CONE_HALF_ANGLE_DEGREES)


func _constrain_world_to_cone(world_pos: Vector2, apex: Vector2) -> Vector2:
	var constrained := world_pos
	constrained.y = minf(constrained.y, apex.y)

	var dy := apex.y - constrained.y
	var max_horizontal := maxf(0.0, dy * tan(_get_cone_half_angle_radians()))
	constrained.x = clampf(constrained.x, apex.x - max_horizontal, apex.x + max_horizontal)
	return constrained
