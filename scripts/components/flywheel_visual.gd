@tool
extends GearVisual

# VisualUtilsScript is provided by GearVisual base class; do not redeclare here.

func _ready() -> void:
	visual_mode = "flywheel"
	# Default flywheel tint for quick differentiation
	flywheel_color = Color(0.35, 0.65, 0.92, 1.0)
	queue_redraw()

func _draw() -> void:
	_draw_flywheel()


func _draw_flywheel() -> void:
	var shaft_module := maxf(0.8, shaft_module_size)
	var half_length := maxf(flywheel_shaft_half_length, outer_radius + 10.0)
	var shaft_thickness := maxf(maxf(3.0, shaft_body_thickness), shaft_module * 3.2)
	var half_thickness := shaft_thickness * 0.5
	var coupler_radius := maxf(maxf(shaft_coupler_radius, shaft_module * 3.5), shaft_thickness * 0.72)
	var coupler_inset := clampf(maxf(shaft_bevel_length, shaft_module * 2.8), 2.0, half_length * 0.35)
	var rod_half_length := maxf(6.0, half_length - coupler_inset)
	var rod_rect := Rect2(
		Vector2(-rod_half_length, -half_thickness),
		Vector2(rod_half_length * 2.0, shaft_thickness)
	)
	var ring_outer := maxf(outer_radius, shaft_thickness + 6.0)
	var _ring_inner := maxf(hub_radius + 4.0, ring_outer * 0.72)
	var _core_radius := maxf(hub_radius, ring_outer * 0.24)

	# Simplified flywheel: just a shaft visual using the exported color
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	draw_rect(rod_rect, flywheel_color, true)
	draw_rect(rod_rect, outline_color, false, 1.4)
	VisualUtilsScript.draw_shaft_rotation_bands(self, rod_rect, half_thickness, _shaft_phase)
	VisualUtilsScript.draw_shaft_end_coupler(self, -half_length, -1.0, rod_half_length, half_thickness, coupler_radius, tooth_color, outline_color, _shaft_phase)
	VisualUtilsScript.draw_shaft_end_coupler(self, half_length, 1.0, rod_half_length, half_thickness, coupler_radius, tooth_color, outline_color, _shaft_phase)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE) # Reset transform
