@tool
extends Node2D
class_name GearVisual

const DEFAULT_GEAR_MODULE: float = 2.0
const DEFAULT_GEAR_ADDENDUM: float = DEFAULT_GEAR_MODULE * 0.80
const DEFAULT_GEAR_DEDENDUM: float = DEFAULT_GEAR_MODULE * 0.70
const DEFAULT_GEAR_HUB_RADIUS_RATIO: float = 0.32
const MIN_GEAR_TOOTH_COUNT: int = 8
const DEFAULT_GEAR_TOOTH_WIDTH_RATIO: float = 0.45

@export var use_module_profile: bool = true
@export_enum("gear", "shaft", "flywheel", "clutch", "differential") var visual_mode: String = "gear"
@export var pulley_mode: bool = false
@export var module_size: float = DEFAULT_GEAR_MODULE
@export var tooth_count: int = 12
@export var outer_radius: float = 17.0
@export var inner_radius: float = 12.56
@export var hub_radius: float = 4.02
@export var tooth_depth: float = 4.44
@export var tooth_width_ratio: float = DEFAULT_GEAR_TOOTH_WIDTH_RATIO
@export var body_color: Color = Color(0.68, 0.72, 0.76, 1.0)
@export var tooth_color: Color = Color(0.79, 0.83, 0.88, 1.0)
@export var outline_color: Color = Color(0.16, 0.18, 0.2, 1.0)
@export var outline_strength: float = 0.0
@export var shaft_module_size: float = 2.2
@export var shaft_body_thickness: float = 8.0
@export var shaft_coupler_radius: float = 8.2
@export var shaft_bevel_length: float = 7.0
@export var belt_module_size: float = 1.8
@export var is_stacked_top: bool = false

var _shaft_spin_speed: float = 0.0
var _shaft_phase: float = 0.0
var _mode_phase: float = 0.0
var _mode_pulse: float = 0.0
var _mode_spin_speed: float = 0.0

func _ready() -> void:
	_sync_module_profile()
	queue_redraw()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_sync_module_profile(false)
		return

	if visual_mode == "shaft":
		_shaft_phase = wrapf(_shaft_phase + (_shaft_spin_speed * delta), 0.0, TAU)
		queue_redraw()
	elif visual_mode == "flywheel" or visual_mode == "clutch" or visual_mode == "differential":
		var phase_speed: float = _mode_spin_speed if absf(_mode_spin_speed) > 0.001 else 1.6
		_mode_phase = wrapf(_mode_phase + (phase_speed * delta), 0.0, TAU)
		_mode_pulse = wrapf(_mode_pulse + (delta * 2.2), 0.0, TAU)
		queue_redraw()


func _sync_module_profile(redraw: bool = true) -> void:
	if visual_mode != "gear":
		if redraw:
			queue_redraw()
		return

	if not use_module_profile:
		if redraw:
			queue_redraw()
		return

	var safe_module := maxf(module_size, 0.5)
	var safe_outer := maxf(outer_radius, safe_module * 4.0)
	if not is_equal_approx(safe_outer, outer_radius):
		outer_radius = safe_outer

	var pitch_radius := maxf(safe_outer - DEFAULT_GEAR_ADDENDUM, safe_module * 3.0)
	var computed_tooth_count := maxi(
		MIN_GEAR_TOOTH_COUNT,
		int(round((pitch_radius * 2.0) / safe_module))
	)
	var computed_inner := maxf(2.0, pitch_radius - DEFAULT_GEAR_DEDENDUM)
	var computed_depth := safe_outer - computed_inner
	var computed_hub := maxf(safe_module * 1.4, computed_inner * DEFAULT_GEAR_HUB_RADIUS_RATIO)

	tooth_count = computed_tooth_count
	inner_radius = computed_inner
	hub_radius = computed_hub
	tooth_depth = computed_depth
	tooth_width_ratio = DEFAULT_GEAR_TOOTH_WIDTH_RATIO

	if redraw:
		queue_redraw()

func _draw() -> void:
	if visual_mode == "shaft":
		_draw_shaft()
		return
	if visual_mode == "flywheel":
		_draw_flywheel()
		return
	if visual_mode == "clutch":
		_draw_clutch()
		return
	if visual_mode == "differential":
		_draw_differential()
		return

	var pitch: float = TAU / float(max(tooth_count, 1))
	var root_radius: float = maxf(inner_radius, outer_radius - tooth_depth)
	var half_top: float = pitch * tooth_width_ratio * 0.5
	var half_base: float = minf(pitch * 0.5, half_top * 1.28)

	# Base wheel body below the teeth ring.
	draw_circle(Vector2.ZERO, root_radius, body_color)

	# Draw each tooth as a slightly tapered quad with a flat top.
	for tooth_index in range(tooth_count):
		var center_angle: float = pitch * float(tooth_index)
		var base_left: Vector2 = Vector2.RIGHT.rotated(center_angle - half_base) * root_radius
		var top_left: Vector2 = Vector2.RIGHT.rotated(center_angle - half_top) * outer_radius
		var top_right: Vector2 = Vector2.RIGHT.rotated(center_angle + half_top) * outer_radius
		var base_right: Vector2 = Vector2.RIGHT.rotated(center_angle + half_base) * root_radius
		var tooth_poly := PackedVector2Array([base_left, top_left, top_right, base_right])
		draw_colored_polygon(tooth_poly, tooth_color)

	# Subtle contour strokes that do not cut through the tooth faces.
	var contour_color := Color(outline_color.r, outline_color.g, outline_color.b, clampf(outline_color.a * outline_strength, 0.0, 1.0))
	draw_arc(Vector2.ZERO, root_radius, 0.0, TAU, 72, contour_color, 1.1)
	draw_arc(Vector2.ZERO, outer_radius, 0.0, TAU, 72, contour_color, 1.0)

	draw_circle(Vector2.ZERO, hub_radius, Color(0.2, 0.22, 0.24, 1.0))
	draw_arc(Vector2.ZERO, hub_radius, 0.0, TAU, 36, outline_color, 1.2)

	if pulley_mode:
		_draw_pulley_ring()

	if is_stacked_top:
		_draw_stacked_ring()


func _draw_flywheel() -> void:
	var ring_outer := maxf(outer_radius, 10.0)
	var ring_inner := maxf(hub_radius + 4.0, ring_outer * 0.72)
	var core_radius := maxf(hub_radius, ring_outer * 0.24)

	# Dense outer mass ring conveys inertia.
	draw_arc(Vector2.ZERO, ring_outer, 0.0, TAU, 96, tooth_color, 7.5)
	draw_arc(Vector2.ZERO, ring_inner, 0.0, TAU, 96, body_color, 3.2)
	var sweep_angle := _mode_phase * 1.35
	_draw_arc_segment(
		Vector2.ZERO,
		ring_outer + 0.2,
		sweep_angle - 0.32,
		sweep_angle + 0.32,
		true,
		Color(0.9, 0.95, 1.0, 0.32),
		2.2
	)

	# Spokes from core to ring.
	for spoke in range(8):
		var angle := float(spoke) * (TAU / 8.0)
		var inner := Vector2.RIGHT.rotated(angle) * (core_radius + 1.0)
		var outer := Vector2.RIGHT.rotated(angle) * (ring_inner - 1.4)
		draw_line(inner, outer, outline_color, 2.2)

	draw_circle(Vector2.ZERO, core_radius, Color(0.2, 0.22, 0.24, 1.0))
	draw_arc(Vector2.ZERO, core_radius, 0.0, TAU, 48, outline_color, 1.3)
	_draw_port_gears([
		-PI * 0.5,
		PI * 0.5
	], ["input", "output"], ring_outer + 5.8, 3.8)


func _draw_clutch() -> void:
	var clutch_outer := maxf(outer_radius, 10.0)
	var shell_inner := maxf(hub_radius + 4.2, clutch_outer * 0.68)
	var rotor_outer := shell_inner - 2.8
	var rotor_inner := maxf(hub_radius + 2.6, rotor_outer * 0.56)
	var shell_color := body_color.darkened(0.08)

	_draw_windowed_housing(clutch_outer, shell_inner, shell_color, 2, 0.34, 0.18)
	_draw_internal_rotor(rotor_outer, rotor_inner, 18, _mode_phase, true)
	_draw_clutch_disc_pack(rotor_outer * 0.92, rotor_inner + 1.6)
	_draw_hub_face(hub_radius)
	_draw_shell_port_gear(-PI * 0.5, clutch_outer, 6.3, 10, "input")
	_draw_shell_port_gear(PI * 0.5, clutch_outer, 6.3, 10, "output")
	_draw_port_arrow(-PI * 0.5, clutch_outer + 9.6, "input")
	_draw_port_arrow(PI * 0.5, clutch_outer + 9.6, "output")


func _draw_differential() -> void:
	var diff_outer := maxf(outer_radius, 10.0)
	var shell_inner := maxf(hub_radius + 4.0, diff_outer * 0.7)
	var carrier_radius := shell_inner - 3.4
	var core := maxf(hub_radius, diff_outer * 0.22)
	var carrier_phase := _mode_phase * 0.65
	var shell_color := body_color.darkened(0.1)

	_draw_windowed_housing(diff_outer, shell_inner, shell_color, 3, 0.28, 0.04)
	_draw_differential_carrier(carrier_radius, core, carrier_phase)
	_draw_hub_face(core)
	var diff_ports: Array = [-2.35, -0.79, PI * 0.5]
	for port_angle in diff_ports:
		_draw_shell_port_gear(port_angle, diff_outer, 5.8, 9, "io")
		_draw_dual_port_arrows(port_angle, diff_outer + 9.2)


func _draw_stacked_ring() -> void:
	var ring_radius := outer_radius + 3.5
	var ring_color := Color(0.42, 0.85, 1.0, 0.72)
	var ring_shadow := Color(0.12, 0.35, 0.55, 0.40)
	draw_arc(Vector2.ZERO, ring_radius + 1.2, 0.0, TAU, 72, ring_shadow, 3.6)
	draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 72, ring_color, 2.0)


func _draw_pulley_ring() -> void:
	var pulley_outer := outer_radius + 8.0
	var pulley_inner := outer_radius + 2.0
	var pulley_color := Color(0.52, 0.58, 0.64, 1.0)
	var pulley_outline := Color(0.16, 0.18, 0.2, 1.0)
	
	# Draw pulley rim as two concentric circles
	draw_arc(Vector2.ZERO, pulley_outer, 0.0, TAU, 72, pulley_color, 3.2)
	draw_arc(Vector2.ZERO, pulley_inner, 0.0, TAU, 72, pulley_color, 2.8)
	draw_arc(Vector2.ZERO, pulley_outer, 0.0, TAU, 72, pulley_outline, 1.0)
	draw_arc(Vector2.ZERO, pulley_inner, 0.0, TAU, 72, pulley_outline, 1.0)


func _draw_shaft() -> void:
	var shaft_module := maxf(0.8, shaft_module_size)
	var half_length := maxf(outer_radius, 8.0)
	var shaft_thickness := maxf(maxf(3.0, shaft_body_thickness), shaft_module * 3.2)
	var half_thickness := shaft_thickness * 0.5
	var coupler_radius := maxf(maxf(shaft_coupler_radius, shaft_module * 3.5), shaft_thickness * 0.72)
	var coupler_inset := clampf(maxf(shaft_bevel_length, shaft_module * 2.8), 2.0, half_length * 0.55)
	var rod_half_length := maxf(2.0, half_length - coupler_inset)
	var rod_rect := Rect2(
		Vector2(-rod_half_length, -half_thickness),
		Vector2(rod_half_length * 2.0, shaft_thickness)
	)

	draw_rect(rod_rect, body_color, true)
	draw_rect(rod_rect, outline_color, false, 1.4)
	_draw_shaft_rotation_bands(rod_rect, half_thickness)

	_draw_shaft_end_coupler(-half_length, -1.0, rod_half_length, half_thickness, coupler_radius)
	_draw_shaft_end_coupler(half_length, 1.0, rod_half_length, half_thickness, coupler_radius)

	draw_circle(Vector2.ZERO, hub_radius, Color(0.2, 0.22, 0.24, 1.0))
	draw_arc(Vector2.ZERO, hub_radius, 0.0, TAU, 24, outline_color, 1.1)


func set_shaft_spin_speed(speed: float) -> void:
	_shaft_spin_speed = speed


func set_visual_spin_speed(speed: float) -> void:
	_mode_spin_speed = speed


func _draw_shaft_end_coupler(
	outer_x: float,
	direction: float,
	rod_half_length: float,
	rod_half_thickness: float,
	coupler_radius: float
) -> void:
	var inner_x := direction * rod_half_length
	var safe_radius := maxf(coupler_radius, 2.0)
	var collar_rect := Rect2(
		Vector2(minf(inner_x, outer_x), -safe_radius * 0.58),
		Vector2(absf(outer_x - inner_x), safe_radius * 1.16)
	)
	draw_rect(collar_rect, tooth_color, true)
	draw_rect(collar_rect, outline_color, false, 1.0)

	# End hub face where shaft meets gear axle zone.
	var face_center := Vector2(outer_x, 0.0)
	draw_circle(face_center, safe_radius * 0.56, Color(0.24, 0.27, 0.31, 1.0))
	draw_arc(face_center, safe_radius * 0.56, 0.0, TAU, 24, outline_color, 1.1)
	draw_circle(face_center, safe_radius * 0.2, Color(0.78, 0.82, 0.88, 0.95))

	# Keyway indicator rotates with shaft speed to show motion.
	var key_angle := _shaft_phase * 1.65
	var key_dir := Vector2.RIGHT.rotated(key_angle)
	draw_line(
		face_center + (key_dir * (safe_radius * 0.22)),
		face_center + (key_dir * (safe_radius * 0.48)),
		Color(0.86, 0.9, 0.96, 0.95),
		1.6
	)


func _draw_shaft_rotation_bands(rod_rect: Rect2, half_thickness: float) -> void:
	var spacing := maxf(6.0, rod_rect.size.x / 7.5)
	var travel := fposmod(_shaft_phase * 22.0, spacing)
	var band_color := Color(0.9, 0.95, 1.0, 0.36)
	var shadow_color := Color(0.12, 0.14, 0.18, 0.25)
	var start_x := rod_rect.position.x - spacing
	var end_x := rod_rect.position.x + rod_rect.size.x + spacing
	var x := start_x + travel
	while x <= end_x:
		draw_line(Vector2(x, -half_thickness), Vector2(x, half_thickness), band_color, 1.2)
		draw_line(Vector2(x + 1.0, -half_thickness), Vector2(x + 1.0, half_thickness), shadow_color, 0.9)
		x += spacing


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
	var steps := maxi(8, int(ceil(absf(delta) * radius / 7.0)))
	var points := PackedVector2Array()
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var angle := start_angle + (delta * t)
		points.append(center + Vector2.RIGHT.rotated(angle) * radius)
	draw_polyline(points, color, width)


func _signed_angle_delta(from_angle: float, to_angle: float, ccw: bool) -> float:
	var delta := wrapf(to_angle - from_angle, -PI, PI)
	if ccw and delta < 0.0:
		delta += TAU
	elif not ccw and delta > 0.0:
		delta -= TAU
	return delta


func _draw_port_gears(port_angles: Array, port_roles: Array, orbit_radius: float, gear_radius: float) -> void:
	for i in range(port_angles.size()):
		var port_angle := float(port_angles[i])
		var role := str(port_roles[i]) if i < port_roles.size() else "input"
		var center := Vector2.RIGHT.rotated(port_angle) * orbit_radius
		_draw_mini_gear(center, gear_radius, role)


func _draw_mini_gear(center: Vector2, radius: float, role: String) -> void:
	var ring_color: Color = Color(0.42, 0.78, 1.0, 0.95) if role == "input" else Color(0.98, 0.72, 0.3, 0.95)
	if role == "io":
		ring_color = Color(0.9, 0.9, 0.95, 0.95)
	var fill_color := Color(0.21, 0.24, 0.28, 1.0)
	var tooth_count := 8
	var tooth_len := radius * 0.42
	var phase := _mode_phase if role == "input" else -_mode_phase

	draw_circle(center, radius, fill_color)
	draw_arc(center, radius, 0.0, TAU, 24, outline_color, 1.0)

	for tooth in range(tooth_count):
		var angle := phase + (float(tooth) * (TAU / float(tooth_count)))
		var inner := center + (Vector2.RIGHT.rotated(angle) * radius)
		var outer := center + (Vector2.RIGHT.rotated(angle) * (radius + tooth_len))
		draw_line(inner, outer, ring_color, 1.4)

	# Role dot to make IO role readable at a glance.
	var role_dot: Color = Color(0.48, 0.86, 1.0, 1.0) if role == "input" else Color(1.0, 0.8, 0.36, 1.0)
	if role == "io":
		role_dot = Color(0.9, 0.92, 0.98, 1.0)
	draw_circle(center + Vector2(0.0, -radius * 0.2), maxf(1.3, radius * 0.24), role_dot)


func _draw_windowed_housing(
	outer: float,
	inner: float,
	shell_color: Color,
	window_count: int,
	window_width: float,
	phase_offset: float
) -> void:
	draw_circle(Vector2.ZERO, outer, shell_color)
	draw_circle(Vector2.ZERO, inner, Color(0.14, 0.16, 0.19, 1.0))
	draw_arc(Vector2.ZERO, outer, 0.0, TAU, 96, outline_color, 1.3)
	draw_arc(Vector2.ZERO, inner, 0.0, TAU, 96, outline_color, 1.0)
	var stride := TAU / float(max(window_count, 1))
	for idx in range(window_count):
		var angle := phase_offset + (float(idx) * stride)
		_draw_shell_window(angle, inner + 1.0, outer - 2.0, window_width)


func _draw_shell_window(center_angle: float, inner_radius: float, outer_radius_value: float, half_width: float) -> void:
	var points := PackedVector2Array()
	points.append(Vector2.RIGHT.rotated(center_angle - half_width) * inner_radius)
	points.append(Vector2.RIGHT.rotated(center_angle - half_width * 0.72) * outer_radius_value)
	points.append(Vector2.RIGHT.rotated(center_angle + half_width * 0.72) * outer_radius_value)
	points.append(Vector2.RIGHT.rotated(center_angle + half_width) * inner_radius)
	draw_colored_polygon(points, Color(0.09, 0.11, 0.14, 0.88))
	draw_polyline(PackedVector2Array([
		points[0], points[1], points[2], points[3], points[0]
	]), outline_color, 1.0)


func _draw_internal_rotor(outer: float, inner: float, teeth: int, phase: float, clockwise: bool) -> void:
	var tooth_steps: int = maxi(teeth, 8)
	var step: float = TAU / float(tooth_steps)
	var tooth_half: float = step * 0.22
	var dir: float = -1.0 if clockwise else 1.0
	draw_circle(Vector2.ZERO, outer - 1.2, Color(0.27, 0.3, 0.35, 1.0))
	for idx in range(tooth_steps):
		var center_angle: float = phase * dir + (float(idx) * step)
		var a: Vector2 = Vector2.RIGHT.rotated(center_angle - tooth_half) * (outer - 2.2)
		var b: Vector2 = Vector2.RIGHT.rotated(center_angle - tooth_half * 0.78) * outer
		var c: Vector2 = Vector2.RIGHT.rotated(center_angle + tooth_half * 0.78) * outer
		var d: Vector2 = Vector2.RIGHT.rotated(center_angle + tooth_half) * (outer - 2.2)
		draw_colored_polygon(PackedVector2Array([a, b, c, d]), tooth_color)
	draw_circle(Vector2.ZERO, inner, Color(0.12, 0.14, 0.18, 1.0))
	draw_arc(Vector2.ZERO, outer, 0.0, TAU, 84, outline_color, 1.0)
	draw_arc(Vector2.ZERO, inner, 0.0, TAU, 64, outline_color, 1.0)


func _draw_clutch_disc_pack(outer: float, inner: float) -> void:
	for idx in range(3):
		var radius := lerpf(inner, outer, float(idx + 1) / 4.0)
		var flash := 0.66 + (0.22 * maxf(0.0, sin(_mode_pulse + (float(idx) * 0.8))))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 72, Color(0.9, 0.94, 0.98, flash), 2.0)


func _draw_differential_carrier(carrier_radius: float, core: float, phase: float) -> void:
	draw_circle(Vector2.ZERO, carrier_radius, Color(0.25, 0.28, 0.33, 1.0))
	for arm in range(4):
		var angle := phase + (float(arm) * (TAU / 4.0))
		var start := Vector2.RIGHT.rotated(angle) * (core + 1.2)
		var finish := Vector2.RIGHT.rotated(angle) * (carrier_radius - 2.0)
		draw_line(start, finish, tooth_color, 2.3)
	for pinion in range(4):
		var angle := -phase * 1.3 + (float(pinion) * (TAU / 4.0)) + (TAU / 8.0)
		var pos := Vector2.RIGHT.rotated(angle) * (carrier_radius * 0.68)
		_draw_internal_pinion(pos, carrier_radius * 0.16, angle)
	draw_arc(Vector2.ZERO, carrier_radius, 0.0, TAU, 84, outline_color, 1.0)


func _draw_internal_pinion(center: Vector2, radius: float, phase: float) -> void:
	draw_circle(center, radius, tooth_color)
	for idx in range(6):
		var angle := phase + (float(idx) * (TAU / 6.0))
		var inner := center + (Vector2.RIGHT.rotated(angle) * (radius * 0.7))
		var outer := center + (Vector2.RIGHT.rotated(angle) * (radius * 1.18))
		draw_line(inner, outer, outline_color, 0.9)


func _draw_hub_face(radius: float) -> void:
	draw_circle(Vector2.ZERO, radius, Color(0.18, 0.2, 0.24, 1.0))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 36, outline_color, 1.1)
	draw_circle(Vector2.ZERO, maxf(1.2, radius * 0.28), Color(0.84, 0.88, 0.93, 0.94))


func _draw_shell_port_gear(angle: float, shell_radius: float, gear_radius: float, exposed_teeth: int, role: String) -> void:
	var center := Vector2.RIGHT.rotated(angle) * (shell_radius - gear_radius * 0.36)
	var base_color := Color(0.24, 0.27, 0.31, 1.0)
	var tooth_tint: Color = Color(0.48, 0.86, 1.0, 1.0) if role == "input" else Color(1.0, 0.78, 0.34, 1.0)
	if role == "io":
		tooth_tint = Color(0.88, 0.9, 0.96, 1.0)
	draw_circle(center, gear_radius, base_color)
	draw_arc(center, gear_radius, 0.0, TAU, 24, outline_color, 1.0)
	var step := PI / float(max(exposed_teeth - 1, 1))
	for idx in range(exposed_teeth):
		var tooth_angle := angle - (PI * 0.5) + (float(idx) * step)
		var inner := center + (Vector2.RIGHT.rotated(tooth_angle) * (gear_radius * 0.82))
		var outer := center + (Vector2.RIGHT.rotated(tooth_angle) * (gear_radius * 1.28))
		draw_line(inner, outer, tooth_tint, 1.35)


func _draw_port_arrow(angle: float, radius: float, role: String) -> void:
	var color: Color = Color(0.48, 0.86, 1.0, 0.95) if role == "input" else Color(1.0, 0.78, 0.34, 0.95)
	var dir: Vector2 = Vector2.RIGHT.rotated(angle)
	var tip: Vector2 = dir * radius
	var stem: Vector2 = tip + (dir * (4.2 if role == "input" else -4.2))
	_draw_arrow_shape(stem, tip, color)


func _draw_dual_port_arrows(angle: float, radius: float) -> void:
	var dir: Vector2 = Vector2.RIGHT.rotated(angle)
	var tip_out: Vector2 = dir * radius
	var stem_out: Vector2 = tip_out - (dir * 4.0)
	var tip_in: Vector2 = dir * (radius - 8.0)
	var stem_in: Vector2 = tip_in + (dir * 4.0)
	_draw_arrow_shape(stem_in, tip_in, Color(0.48, 0.86, 1.0, 0.9))
	_draw_arrow_shape(stem_out, tip_out, Color(1.0, 0.78, 0.34, 0.9))


func _draw_arrow_shape(from: Vector2, to: Vector2, color: Color) -> void:
	draw_line(from, to, color, 1.6)
	var dir: Vector2 = (to - from).normalized()
	if dir == Vector2.ZERO:
		return
	var normal: Vector2 = Vector2(-dir.y, dir.x)
	var head_len: float = 3.0
	var left: Vector2 = to - (dir * head_len) + (normal * 2.0)
	var right: Vector2 = to - (dir * head_len) - (normal * 2.0)
	draw_colored_polygon(PackedVector2Array([to, left, right]), color)
