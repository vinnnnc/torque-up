@tool
extends GearVisual

# VisualUtilsScript is provided by GearVisual base class; do not redeclare here.

func _ready() -> void:
	visual_mode = "differential"
	queue_redraw()

func _draw() -> void:
	_draw_differential()


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
	# Shaft ports: input on top, outputs on left and right sides
	_draw_shaft_port_collar(0.0, core + 1.2, "input")
	_draw_shaft_port_collar(PI * 0.5, core + 1.2, "output")
	_draw_shaft_port_collar(-PI * 0.5, core + 1.2, "output")


func _draw_windowed_housing(
	outer: float,
	inner: float,
	shell_color: Color,
	window_count: int,
	window_width: float,
	phase_offset: float
) -> void:
	VisualUtilsScript.draw_windowed_housing(self, outer, inner, shell_color, window_count, window_width, phase_offset, outline_color)


func _draw_shell_window(center_angle: float, shell_inner_radius: float, outer_radius_value: float, half_width: float) -> void:
	VisualUtilsScript.draw_shell_window(self, center_angle, shell_inner_radius, outer_radius_value, half_width, outline_color)


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
	VisualUtilsScript.draw_hub_face(self, radius, outline_color)


func _draw_shaft_port_collar(port_angle: float, port_inner_radius: float, role: String) -> void:
	VisualUtilsScript.draw_shaft_port_collar(self, port_angle, port_inner_radius, role, outline_color)
