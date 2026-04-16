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
const CHAIN_LINK_SPACING := 10.0
const CHAIN_LINK_WIDTH := 5.5
const CHAIN_LINK_HEIGHT := 3.5
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

	if pulley_a == null or pulley_b == null:
		push_error("ChainComponent: failed to find sprockets: a=%s  b=%s" % [pulley_a, pulley_b])
		queue_free()
		return

	if pulley_a.has_method("set_pulley_mode"):
		pulley_a.set_pulley_mode(true)
	if pulley_b.has_method("set_pulley_mode"):
		pulley_b.set_pulley_mode(true)


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
	_draw_arc_segment(pos_b, radius_b, a_dn, a_up, true, chain_color, line_width)

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

	var dir := span / length
	var normal := dir.rotated(PI * 0.5)

	# Base run line.
	draw_line(start_pos, end_pos, run_color, line_width)

	# Chain links: alternating outer-plate and pin-plate rects.
	var count := int(ceil(length / CHAIN_LINK_SPACING)) + 1
	for i in range(count):
		var offset := fposmod(_chain_phase + (float(i) * CHAIN_LINK_SPACING), length)
		var center := start_pos + dir * offset
		var is_outer_plate := (i % 2 == 0)
		var lw := CHAIN_LINK_WIDTH if is_outer_plate else (CHAIN_LINK_WIDTH * 0.65)
		var lh := CHAIN_LINK_HEIGHT if is_outer_plate else (CHAIN_LINK_HEIGHT * 0.75)
		var link_col := link_highlight_color if is_outer_plate else run_color
		# Draw link as 4 corner verts (axis-aligned parallelogram along run).
		var corners := PackedVector2Array([
			center + dir * (lw * 0.5) + normal * (lh * 0.5),
			center + dir * (lw * 0.5) - normal * (lh * 0.5),
			center - dir * (lw * 0.5) - normal * (lh * 0.5),
			center - dir * (lw * 0.5) + normal * (lh * 0.5),
			center + dir * (lw * 0.5) + normal * (lh * 0.5),
		])
		draw_polyline(corners, link_col, 1.2)


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
	if ccw and raw > 0.0:
		raw -= TAU
	elif not ccw and raw < 0.0:
		raw += TAU
	return raw
