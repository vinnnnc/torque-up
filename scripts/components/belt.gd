extends Node2D
class_name BeltComponent

const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")

@export var pulley_a_path: NodePath
@export var pulley_b_path: NodePath
@export var belt_color: Color = Color(0.32, 0.34, 0.38, 1.0)
@export var tension_color: Color = Color(0.52, 0.55, 0.60, 1.0)
@export var line_width: float = 4.5

var pulley_a: GearComponent = null
var pulley_b: GearComponent = null
var connection_radius_a: float = 0.0
var connection_radius_b: float = 0.0
var is_crossed: bool = false
var tension_level: float = 0.0
var slip_amount: float = 0.0
var _belt_phase: float = 0.0

const BELT_TOOTH_MARGIN := 1.2
const BELT_MARK_SPEED := 70.0
const BELT_MARK_SPACING := 18.0
const BELT_MARK_ALPHA := 0.72


func configure(pulley_a_ref: GearComponent, pulley_b_ref: GearComponent, radius_a: float, radius_b: float) -> void:
	pulley_a = pulley_a_ref
	pulley_b = pulley_b_ref
	connection_radius_a = radius_a
	connection_radius_b = radius_b

	if pulley_a and pulley_a.has_method("set_pulley_mode"):
		pulley_a.set_pulley_mode(true)
	if pulley_b and pulley_b.has_method("set_pulley_mode"):
		pulley_b.set_pulley_mode(true)

	queue_redraw()


func _ready() -> void:
	if pulley_a == null and pulley_a_path != NodePath():
		pulley_a = get_node_or_null(pulley_a_path)
	if pulley_b == null and pulley_b_path != NodePath():
		pulley_b = get_node_or_null(pulley_b_path)

	# Set component type for network service recognition.
	set_meta("component_type", PROJECT_PATHS_SCRIPT.COMPONENT_CHAIN)

	if pulley_a == null or pulley_b == null:
		push_error("Belt failed to find pulleys: a=%s, b=%s" % [pulley_a, pulley_b])
		queue_free()
		return

	if pulley_a.has_method("set_pulley_mode"):
		pulley_a.set_pulley_mode(true)
	if pulley_b.has_method("set_pulley_mode"):
		pulley_b.set_pulley_mode(true)


func set_tension_state(tension: float, slip: float, crossed: bool) -> void:
	tension_level = clampf(tension, 0.0, 1.0)
	slip_amount = clampf(slip, 0.0, 1.0)
	is_crossed = crossed
	queue_redraw()


func _process(_delta: float) -> void:
	if pulley_a == null or pulley_b == null:
		return

	var belt_radius_a := maxf(3.0, connection_radius_a + PROJECT_PATHS_SCRIPT.GEAR_MESH_CONTACT_MARGIN + BELT_TOOTH_MARGIN)
	var belt_radius_b := maxf(3.0, connection_radius_b + PROJECT_PATHS_SCRIPT.GEAR_MESH_CONTACT_MARGIN + BELT_TOOTH_MARGIN)
	var angular_speed_a := _get_pulley_angular_speed(pulley_a)
	var angular_speed_b := _get_pulley_angular_speed(pulley_b)
	var linear_speed_a := angular_speed_a * belt_radius_a
	var linear_speed_b := angular_speed_b * belt_radius_b
	var driven_linear_speed := 0.0
	if absf(linear_speed_a) > 0.001 and absf(linear_speed_b) > 0.001:
		driven_linear_speed = (linear_speed_a + linear_speed_b) * 0.5
	elif absf(linear_speed_a) > 0.001:
		driven_linear_speed = linear_speed_a
	elif absf(linear_speed_b) > 0.001:
		driven_linear_speed = linear_speed_b

	if absf(driven_linear_speed) < 0.001:
		driven_linear_speed = signf(driven_linear_speed) * BELT_MARK_SPEED

	_belt_phase = wrapf(
		_belt_phase - (_delta * driven_linear_speed * (1.0 - (slip_amount * 0.45))),
		-10000.0,
		10000.0
	)
	global_position = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	if pulley_a == null or pulley_b == null:
		return

	var pos_a := to_local(pulley_a.global_position)
	var pos_b := to_local(pulley_b.global_position)
	var radius_a := maxf(3.0, connection_radius_a + PROJECT_PATHS_SCRIPT.GEAR_MESH_CONTACT_MARGIN + BELT_TOOTH_MARGIN)
	var radius_b := maxf(3.0, connection_radius_b + PROJECT_PATHS_SCRIPT.GEAR_MESH_CONTACT_MARGIN + BELT_TOOTH_MARGIN)
	var current_color := belt_color.lerp(tension_color, tension_level)
	var mark_color := Color(0.86, 0.9, 0.94, BELT_MARK_ALPHA)

	var geometry := _compute_open_belt_geometry(pos_a, radius_a, pos_b, radius_b)
	if geometry.is_empty():
		draw_line(pos_a, pos_b, current_color, line_width)
		_draw_moving_marks_on_line(pos_a, pos_b, mark_color)
		return

	var p1_up: Vector2 = geometry["p1_up"]
	var p1_dn: Vector2 = geometry["p1_dn"]
	var p2_up: Vector2 = geometry["p2_up"]
	var p2_dn: Vector2 = geometry["p2_dn"]
	var a_up: float = float(geometry["a_up"])
	var a_dn: float = float(geometry["a_dn"])

	# Wrapped belt: two tangent spans + arc contact around both pulleys.
	draw_line(p1_up, p2_up, current_color, line_width)
	draw_line(p1_dn, p2_dn, current_color, line_width)
	_draw_arc_segment(pos_a, radius_a, a_up, a_dn, true, current_color, line_width)
	_draw_arc_segment(pos_b, radius_b, a_dn, a_up, true, current_color, line_width)

	# Animated belt marks follow one continuous loop.
	_draw_moving_marks_on_line(p1_up, p2_up, mark_color)
	_draw_moving_marks_on_arc(pos_b, radius_b, a_up, a_dn, false, mark_color)
	_draw_moving_marks_on_line(p2_dn, p1_dn, mark_color)
	_draw_moving_marks_on_arc(pos_a, radius_a, a_dn, a_up, false, mark_color)

	# Draw slip indicator (dashed line overlay if slipping).
	if slip_amount > 0.01:
		var slip_color := Color(1.0, 0.6, 0.4, slip_amount * 0.6)
		_draw_line_dashes(p1_up, p2_up, slip_color)
		_draw_line_dashes(p1_dn, p2_dn, slip_color)

	# Draw crossed belt indicator (X mark in center).
	if is_crossed:
		var mid := pos_a.lerp(pos_b, 0.5)
		var cross_size := 7.0
		var cross_color := Color(0.95, 0.56, 0.56, 0.6)
		draw_line(mid + Vector2(-cross_size, -cross_size), mid + Vector2(cross_size, cross_size), cross_color, 2.0)
		draw_line(mid + Vector2(-cross_size, cross_size), mid + Vector2(cross_size, -cross_size), cross_color, 2.0)


func _compute_open_belt_geometry(c1: Vector2, r1: float, c2: Vector2, r2: float) -> Dictionary:
	var d := c2 - c1
	var dist := d.length()
	if dist <= 0.001:
		return {}

	var ratio := (r1 - r2) / dist
	if absf(ratio) >= 0.999:
		return {}

	var base := d.angle()
	var alpha := acos(clampf(ratio, -1.0, 1.0))
	var a_up := base + alpha
	var a_dn := base - alpha

	return {
		"a_up": a_up,
		"a_dn": a_dn,
		"p1_up": c1 + Vector2.RIGHT.rotated(a_up) * r1,
		"p1_dn": c1 + Vector2.RIGHT.rotated(a_dn) * r1,
		"p2_up": c2 + Vector2.RIGHT.rotated(a_up) * r2,
		"p2_dn": c2 + Vector2.RIGHT.rotated(a_dn) * r2
	}


func _draw_arc_segment(center: Vector2, radius: float, start_angle: float, end_angle: float, ccw: bool, color: Color, width: float) -> void:
	var delta := _signed_angle_delta(start_angle, end_angle, ccw)
	var steps := maxi(12, int(ceil(absf(delta) * radius / 7.0)))
	var points := PackedVector2Array()
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var angle := start_angle + (delta * t)
		points.append(center + Vector2.RIGHT.rotated(angle) * radius)

	draw_polyline(points, color, width)


func _draw_moving_marks_on_line(start_pos: Vector2, end_pos: Vector2, color: Color) -> void:
	var span := end_pos - start_pos
	var length := span.length()
	if length <= 0.001:
		return

	var dir := span / length
	var normal := dir.rotated(PI * 0.5)
	var count := int(ceil(length / BELT_MARK_SPACING)) + 1
	for i in range(count):
		var offset := fposmod(_belt_phase + (float(i) * BELT_MARK_SPACING), length)
		var p := start_pos + dir * offset
		draw_line(p - normal * (line_width * 0.42), p + normal * (line_width * 0.42), color, 1.4)


func _draw_moving_marks_on_arc(center: Vector2, radius: float, start_angle: float, end_angle: float, ccw: bool, color: Color) -> void:
	var delta := _signed_angle_delta(start_angle, end_angle, ccw)
	var arc_len := absf(delta) * radius
	if arc_len <= 0.001:
		return

	var travel_sign := 1.0 if delta >= 0.0 else -1.0
	var count := int(ceil(arc_len / BELT_MARK_SPACING)) + 1
	for i in range(count):
		var offset := fposmod(_belt_phase + (float(i) * BELT_MARK_SPACING), arc_len)
		var angle := start_angle + ((offset / radius) * travel_sign)
		var radial := Vector2.RIGHT.rotated(angle)
		var p := center + radial * radius
		draw_line(p - radial * (line_width * 0.42), p + radial * (line_width * 0.42), color, 1.4)


func _draw_line_dashes(start_pos: Vector2, end_pos: Vector2, color: Color) -> void:
	var span := end_pos - start_pos
	var length := span.length()
	if length <= 0.001:
		return

	var segment_len := 8.0
	var dash_len := 3.4
	var count := int(ceil(length / segment_len))
	for i in range(count):
		var t0 := minf((float(i) * segment_len) / length, 1.0)
		var t1 := minf(((float(i) * segment_len) + dash_len) / length, 1.0)
		draw_line(start_pos.lerp(end_pos, t0), start_pos.lerp(end_pos, t1), color, maxf(1.0, line_width - 1.1))


func _signed_angle_delta(start_angle: float, end_angle: float, ccw: bool) -> float:
	var delta := wrapf(end_angle - start_angle, -PI, PI)
	if ccw and delta < 0.0:
		delta += TAU
	elif not ccw and delta > 0.0:
		delta -= TAU
	return delta


func get_distance_to_world_point(world_pos: Vector2) -> float:
	if pulley_a == null or pulley_b == null:
		return INF

	var pos_a := pulley_a.global_position
	var pos_b := pulley_b.global_position
	var radius_a := maxf(3.0, connection_radius_a + PROJECT_PATHS_SCRIPT.GEAR_MESH_CONTACT_MARGIN + BELT_TOOTH_MARGIN)
	var radius_b := maxf(3.0, connection_radius_b + PROJECT_PATHS_SCRIPT.GEAR_MESH_CONTACT_MARGIN + BELT_TOOTH_MARGIN)

	var geometry := _compute_open_belt_geometry(pos_a, radius_a, pos_b, radius_b)
	if geometry.is_empty():
		return _point_segment_distance(world_pos, pos_a, pos_b)

	var p1_up: Vector2 = geometry["p1_up"]
	var p1_dn: Vector2 = geometry["p1_dn"]
	var p2_up: Vector2 = geometry["p2_up"]
	var p2_dn: Vector2 = geometry["p2_dn"]
	var a_up: float = float(geometry["a_up"])
	var a_dn: float = float(geometry["a_dn"])

	var min_dist := INF
	min_dist = minf(min_dist, _point_segment_distance(world_pos, p1_up, p2_up))
	min_dist = minf(min_dist, _point_segment_distance(world_pos, p1_dn, p2_dn))
	min_dist = minf(min_dist, _point_arc_distance(world_pos, pos_a, radius_a, a_up, a_dn, true))
	min_dist = minf(min_dist, _point_arc_distance(world_pos, pos_b, radius_b, a_dn, a_up, true))
	return min_dist


func _point_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var ab_len_sq := ab.length_squared()
	if ab_len_sq <= 0.000001:
		return p.distance_to(a)

	var t := clampf((p - a).dot(ab) / ab_len_sq, 0.0, 1.0)
	var closest := a + (ab * t)
	return p.distance_to(closest)


func _point_arc_distance(p: Vector2, center: Vector2, radius: float, start_angle: float, end_angle: float, ccw: bool) -> float:
	var point_vec := p - center
	if point_vec.length_squared() <= 0.000001:
		var near_start := center + Vector2.RIGHT.rotated(start_angle) * radius
		var near_end := center + Vector2.RIGHT.rotated(end_angle) * radius
		return minf(p.distance_to(near_start), p.distance_to(near_end))

	var point_angle := point_vec.angle()
	if _is_angle_on_arc(point_angle, start_angle, end_angle, ccw):
		return absf(point_vec.length() - radius)

	var arc_start := center + Vector2.RIGHT.rotated(start_angle) * radius
	var arc_end := center + Vector2.RIGHT.rotated(end_angle) * radius
	return minf(p.distance_to(arc_start), p.distance_to(arc_end))


func _is_angle_on_arc(angle: float, start_angle: float, end_angle: float, ccw: bool) -> bool:
	var total := _signed_angle_delta(start_angle, end_angle, ccw)
	var partial := _signed_angle_delta(start_angle, angle, ccw)
	if total >= 0.0:
		return partial >= -0.0001 and partial <= total + 0.0001
	return partial <= 0.0001 and partial >= total - 0.0001


func _get_pulley_angular_speed(pulley: GearComponent) -> float:
	if pulley == null:
		return 0.0
	if pulley.has_method("get_angular_velocity"):
		return float(pulley.call("get_angular_velocity"))
	return 0.0
