@tool
extends GearVisual

# VisualUtilsScript is provided by GearVisual base class; do not redeclare here.

func _ready() -> void:
	visual_mode = "shaft"
	# Slightly darker shaft color by default
	body_color = Color(0.48, 0.52, 0.56, 1.0)
	queue_redraw()

func _draw() -> void:
	_draw_shaft()


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
	VisualUtilsScript.draw_shaft_rotation_bands(self, rod_rect, half_thickness, _shaft_phase)

	VisualUtilsScript.draw_shaft_end_coupler(self, -half_length, -1.0, rod_half_length, half_thickness, coupler_radius, tooth_color, outline_color, _shaft_phase)
	VisualUtilsScript.draw_shaft_end_coupler(self, half_length, 1.0, rod_half_length, half_thickness, coupler_radius, tooth_color, outline_color, _shaft_phase)

	draw_circle(Vector2.ZERO, hub_radius, Color(0.2, 0.22, 0.24, 1.0))
	draw_arc(Vector2.ZERO, hub_radius, 0.0, TAU, 24, outline_color, 1.1)
