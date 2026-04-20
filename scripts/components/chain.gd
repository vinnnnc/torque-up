extends Node2D
class_name ChainComponent

## Chain drive component. Connects two gear sprockets with a chain link transfer.
## Preserves rotation direction (same as belt). Accumulates jam risk under
## sustained overload — unlike belt slip which was instantaneous.

const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")

@export var pulley_a_path: NodePath
@export var pulley_b_path: NodePath
@export var chain_color: Color = Color(0.32, 0.34, 0.38, 1.0)
@export var link_highlight_color: Color = Color(0.52, 0.55, 0.60, 1.0)
@export var jam_color: Color = Color(0.95, 0.42, 0.18, 1.0)
@export var line_width: float = 4.5

## pulley_a / pulley_b kept as property names so network_service can find them
## via the same _belt_links_node lookup (uses .get("pulley_a") / .get("pulley_b")).
var pulley_a: GearComponent = null
var pulley_b: GearComponent = null
var connection_radius_a: float = 0.0
var connection_radius_b: float = 0.0

var jam_amount: float = 0.0     # 0..1 — visual jam indicator intensity
var load_ratio: float = 0.0     # last known load ratio fed from condition system
var _chain_phase: float = 0.0

const CHAIN_TOOTH_MARGIN := 1.2
const CHAIN_SPEED_SCALE := 65.0
const CHAIN_MARK_SPACING := 11.0
const CHAIN_MARK_WIDTH := 1.4
const CHAIN_JAM_PULSE_SPEED := 3.0


func configure(
	pulley_a_ref: GearComponent,
	pulley_b_ref: GearComponent,
	radius_a: float,
	radius_b: float
) -> void:
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

	set_meta("component_type", PROJECT_PATHS_SCRIPT.COMPONENT_CHAIN)

	# Pulley references may not be set yet if this chain is a preview instance
	# or being loaded from a save. Validation happens in configure() or _process() will handle null pulleys.


func set_jam_state(jam: float) -> void:
	jam_amount = clampf(jam, 0.0, 1.0)
	queue_redraw()


## Called by condition service each tick with the network load ratio.
func set_load_ratio(ratio: float) -> void:
	load_ratio = clampf(ratio, 0.0, 1.0)


func _process(delta: float) -> void:
	if pulley_a == null or pulley_b == null:
		return

	var chain_radius_a := maxf(3.0, connection_radius_a + PROJECT_PATHS_SCRIPT.GEAR_MESH_CONTACT_MARGIN + CHAIN_TOOTH_MARGIN)
	var chain_radius_b := maxf(3.0, connection_radius_b + PROJECT_PATHS_SCRIPT.GEAR_MESH_CONTACT_MARGIN + CHAIN_TOOTH_MARGIN)
	var angular_a := _get_sprocket_angular_speed(pulley_a)
	var angular_b := _get_sprocket_angular_speed(pulley_b)
	var linear_a := angular_a * chain_radius_a
	var linear_b := angular_b * chain_radius_b
	var driven_speed := 0.0
	if absf(linear_a) > 0.001 and absf(linear_b) > 0.001:
		driven_speed = (linear_a + linear_b) * 0.5
	elif absf(linear_a) > 0.001:
		driven_speed = linear_a
	elif absf(linear_b) > 0.001:
		driven_speed = linear_b

	if absf(driven_speed) < 0.001:
		driven_speed = signf(driven_speed) * CHAIN_SPEED_SCALE

	# Jam slows the phase movement proportionally.
	var jam_drag := 1.0 - (jam_amount * 0.85)
	_chain_phase = wrapf(
		_chain_phase - (delta * driven_speed * jam_drag),
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
	var radius_a := maxf(3.0, connection_radius_a + PROJECT_PATHS_SCRIPT.GEAR_MESH_CONTACT_MARGIN + CHAIN_TOOTH_MARGIN)
	var radius_b := maxf(3.0, connection_radius_b + PROJECT_PATHS_SCRIPT.GEAR_MESH_CONTACT_MARGIN + CHAIN_TOOTH_MARGIN)

	var geometry := _compute_open_belt_geometry(pos_a, radius_a, pos_b, radius_b)
	if geometry.is_empty():
		_draw_chain_run(pos_a, pos_b, chain_color)
		_draw_moving_marks_on_line(pos_a, pos_b, link_highlight_color)
		return

	var p1_up: Vector2 = geometry["p1_up"]
	var p1_dn: Vector2 = geometry["p1_dn"]
	var p2_up: Vector2 = geometry["p2_up"]
	var p2_dn: Vector2 = geometry["p2_dn"]
	var a_up: float = float(geometry["a_up"])
	var a_dn: float = float(geometry["a_dn"])

	# Draw the two straight chain runs.
	_draw_chain_run(p1_up, p2_up, chain_color)
	_draw_chain_run(p1_dn, p2_dn, chain_color)

	# Draw the arc wrap on each sprocket (solid line).
	_draw_arc_segment(pos_a, radius_a, a_up, a_dn, true, chain_color, line_width)
	_draw_arc_segment(pos_b, radius_b, a_up, a_dn, false, chain_color, line_width)

	# Moving marks on both straight spans and wrapped arcs.
	_draw_moving_marks_on_line(p1_up, p2_up, link_highlight_color)
	_draw_moving_marks_on_arc(pos_a, radius_a, a_dn, a_up, false, link_highlight_color)
	_draw_moving_marks_on_line(p2_dn, p1_dn, link_highlight_color)
	_draw_moving_marks_on_arc(pos_b, radius_b, a_up, a_dn, false, link_highlight_color)

	# Draw jam glow overlay when accumulating jam.
	if jam_amount > 0.02:
		var pulse := sin(Time.get_ticks_msec() * 0.001 * CHAIN_JAM_PULSE_SPEED) * 0.5 + 0.5
		var glow_alpha := jam_amount * (0.55 + pulse * 0.3)
		var glow_col := Color(jam_color.r, jam_color.g, jam_color.b, glow_alpha)
		draw_line(p1_up, p2_up, glow_col, line_width + 2.5)
		draw_line(p1_dn, p2_dn, glow_col, line_width + 2.5)


func _draw_chain_run(start_pos: Vector2, end_pos: Vector2, run_color: Color) -> void:
	var span := end_pos - start_pos
	var length := span.length()
	if length <= 0.001:
		return

	# Base run line.
	draw_line(start_pos, end_pos, run_color, line_width)


func _draw_moving_marks_on_line(start_pos: Vector2, end_pos: Vector2, mark_color: Color) -> void:
	var span := end_pos - start_pos
	var length := span.length()
	if length <= 0.001:
		return

	var dir := span / length
	var normal := dir.rotated(PI * 0.5)
	var count := int(ceil(length / CHAIN_MARK_SPACING)) + 1
	for i in range(count):
		var offset := fposmod(_chain_phase + (float(i) * CHAIN_MARK_SPACING), length)
		var center := start_pos + dir * offset
		draw_line(
			center - normal * (line_width * 0.45),
			center + normal * (line_width * 0.45),
			mark_color,
			CHAIN_MARK_WIDTH
		)


func _draw_moving_marks_on_arc(
	center: Vector2,
	radius: float,
	start_angle: float,
	end_angle: float,
	ccw: bool,
	mark_color: Color
) -> void:
	var delta := _signed_angle_delta(start_angle, end_angle, ccw)
	var arc_len := absf(delta) * radius
	if arc_len <= 0.001:
		return

	var travel_sign := 1.0 if delta >= 0.0 else -1.0
	var count := int(ceil(arc_len / CHAIN_MARK_SPACING)) + 1
	for i in range(count):
		var offset := fposmod(_chain_phase + (float(i) * CHAIN_MARK_SPACING), arc_len)
		var angle := start_angle + ((offset / radius) * travel_sign)
		var radial := Vector2.RIGHT.rotated(angle)
		var p := center + radial * radius
		draw_line(
			p - radial * (line_width * 0.45),
			p + radial * (line_width * 0.45),
			mark_color,
			CHAIN_MARK_WIDTH
		)


func _get_sprocket_angular_speed(sprocket: GearComponent) -> float:
	if sprocket == null:
		return 0.0
	var angular_velocity: Variant = sprocket.get("angular_velocity")
	if angular_velocity == null:
		return 0.0
	return float(angular_velocity)


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


func _draw_arc_segment(
	center: Vector2,
	radius: float,
	start_angle: float,
	end_angle: float,
	ccw: bool,
	color: Color,
	width: float
) -> void:
	var delta := _signed_angle_delta(start_angle, end_angle, ccw)
	var steps := maxi(12, int(ceil(absf(delta) * radius / 7.0)))
	var points := PackedVector2Array()
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var angle := start_angle + (delta * t)
		points.append(center + Vector2.RIGHT.rotated(angle) * radius)
	draw_polyline(points, color, width)


func _signed_angle_delta(from_angle: float, to_angle: float, ccw: bool) -> float:
	var raw := wrapf(to_angle - from_angle, -PI, PI)
	if ccw and raw < 0.0:
		raw += TAU
	elif not ccw and raw > 0.0:
		raw -= TAU
	return raw


func get_distance_to_world_point(world_pos: Vector2) -> float:
	if pulley_a == null or pulley_b == null:
		return INF

	var pos_a := pulley_a.global_position
	var pos_b := pulley_b.global_position
	var radius_a := maxf(3.0, connection_radius_a + PROJECT_PATHS_SCRIPT.GEAR_MESH_CONTACT_MARGIN + CHAIN_TOOTH_MARGIN)
	var radius_b := maxf(3.0, connection_radius_b + PROJECT_PATHS_SCRIPT.GEAR_MESH_CONTACT_MARGIN + CHAIN_TOOTH_MARGIN)

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
	min_dist = minf(min_dist, _point_arc_distance(world_pos, pos_b, radius_b, a_up, a_dn, true))
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
