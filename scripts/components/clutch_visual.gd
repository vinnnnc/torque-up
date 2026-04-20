@tool
extends GearVisual

# VisualUtilsScript is provided by GearVisual base class; do not redeclare here.

func _ready() -> void:
	visual_mode = "clutch"
	queue_redraw()

func _draw() -> void:
	_draw_clutch()


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
	# Shaft ports: top port visible, rear port hidden by construction
	_draw_shaft_port_collar(0.0, hub_radius + 0.5, "input")
	_draw_shaft_port_collar(PI, hub_radius + 0.5, "output")


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


func _draw_internal_rotor(outer: float, inner: float, teeth: int, phase: float, clockwise: bool) -> void:
	VisualUtilsScript.draw_internal_rotor(self, outer, inner, teeth, phase, clockwise, tooth_color, outline_color)


func _draw_clutch_disc_pack(outer: float, inner: float) -> void:
	VisualUtilsScript.draw_clutch_disc_pack(self, outer, inner, _mode_pulse)


func _draw_hub_face(radius: float) -> void:
	VisualUtilsScript.draw_hub_face(self, radius, outline_color)


func _draw_shaft_port_collar(port_angle: float, port_inner_radius: float, role: String) -> void:
	VisualUtilsScript.draw_shaft_port_collar(self, port_angle, port_inner_radius, role, outline_color)
