"""
VisualUtils

Shared math and drawing helpers for component visuals.

Stable API (public helpers):
- signed_angle_delta(from_angle, to_angle, ccw)
- draw_arc_segment(canvas, center, radius, start_angle, end_angle, ccw, color, width=1.0)
- draw_shaft_end_coupler(canvas, outer_x, direction, rod_half_length, _rod_half_thickness, coupler_radius, tooth_color, outline_color, shaft_phase)
- draw_shaft_rotation_bands(canvas, rod_rect, half_thickness, shaft_phase)
- draw_windowed_housing(canvas, outer, inner, shell_color, window_count, window_width, phase_offset, outline_color)
- draw_internal_rotor(canvas, outer, inner, teeth, phase, clockwise, tooth_color, outline_color)
- draw_clutch_disc_pack(canvas, outer, inner, mode_pulse)
- draw_hub_face(canvas, radius, outline_color)
- draw_shaft_port_collar(canvas, port_angle, inner_radius, role, outline_color)

Prefer calling via preload: `const VisualUtils = preload("res://scripts/components/visual_utils.gd")`.
"""

class_name VisualUtils

const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")

static func signed_angle_delta(from_angle: float, to_angle: float, ccw: bool) -> float:
    var delta: float = to_angle - from_angle
    if ccw:
        while delta < 0.0:
            delta += TAU
    else:
        while delta > 0.0:
            delta -= TAU
    return delta

static func draw_arc_segment(canvas: CanvasItem, center: Vector2, radius: float, start_angle: float, end_angle: float, ccw: bool, color: Color, width: float=1.0) -> void:
    var delta: float = signed_angle_delta(start_angle, end_angle, ccw)
    var steps := maxi(8, int(ceil(absf(delta) * radius / 7.0)))
    var pts: PackedVector2Array = PackedVector2Array()
    for i in range(steps + 1):
        var t := float(i) / float(steps)
        var ang := start_angle + (delta * t)
        pts.append(center + Vector2.RIGHT.rotated(ang) * radius)
    canvas.draw_polyline(pts, color, width)

static func draw_shaft_end_coupler(canvas: CanvasItem, outer_x: float, direction: float, rod_half_length: float, _rod_half_thickness: float, coupler_radius: float, tooth_color: Color, outline_color: Color, shaft_phase: float) -> void:
    var inner_x := direction * rod_half_length
    var safe_radius := maxf(coupler_radius, 2.0)
    var collar_rect := Rect2(
        Vector2(minf(inner_x, outer_x), -safe_radius * 0.58),
        Vector2(absf(outer_x - inner_x), safe_radius * 1.16)
    )
    canvas.draw_rect(collar_rect, tooth_color, true)
    canvas.draw_rect(collar_rect, outline_color, false, 1.0)

    var face_center := Vector2(outer_x, 0.0)
    canvas.draw_circle(face_center, safe_radius * 0.56, Color(0.24, 0.27, 0.31, 1.0))
    canvas.draw_arc(face_center, safe_radius * 0.56, 0.0, TAU, 24, outline_color, 1.1)
    canvas.draw_circle(face_center, safe_radius * 0.2, Color(0.78, 0.82, 0.88, 0.95))

    var key_angle := shaft_phase * 1.65
    var key_dir := Vector2.RIGHT.rotated(key_angle)
    canvas.draw_line(
        face_center + (key_dir * (safe_radius * 0.22)),
        face_center + (key_dir * (safe_radius * 0.48)),
        Color(0.86, 0.9, 0.96, 0.95),
        1.6
    )

static func draw_shaft_rotation_bands(canvas: CanvasItem, rod_rect: Rect2, half_thickness: float, shaft_phase: float) -> void:
    var spacing := maxf(6.0, rod_rect.size.x / 7.5)
    var travel := fposmod(shaft_phase * 22.0, spacing)
    var band_color := Color(0.9, 0.95, 1.0, 0.36)
    var shadow_color := Color(0.12, 0.14, 0.18, 0.25)
    var start_x := rod_rect.position.x - spacing
    var end_x := rod_rect.position.x + rod_rect.size.x + spacing
    var x := start_x + travel
    while x <= end_x:
        canvas.draw_line(Vector2(x, -half_thickness), Vector2(x, half_thickness), band_color, 1.2)
        canvas.draw_line(Vector2(x + 1.0, -half_thickness), Vector2(x + 1.0, half_thickness), shadow_color, 0.9)
        x += spacing

static func draw_shell_window(canvas: CanvasItem, center_angle: float, inner_radius: float, outer_radius_value: float, half_width: float, outline_color: Color) -> void:
    var points := PackedVector2Array()
    points.append(Vector2.RIGHT.rotated(center_angle - half_width) * inner_radius)
    points.append(Vector2.RIGHT.rotated(center_angle - half_width * 0.72) * outer_radius_value)
    points.append(Vector2.RIGHT.rotated(center_angle + half_width * 0.72) * outer_radius_value)
    points.append(Vector2.RIGHT.rotated(center_angle + half_width) * inner_radius)
    canvas.draw_colored_polygon(points, Color(0.09, 0.11, 0.14, 0.88))
    canvas.draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[3], points[0]]), outline_color, 1.0)

static func draw_windowed_housing(canvas: CanvasItem, outer: float, inner: float, shell_color: Color, window_count: int, window_width: float, phase_offset: float, outline_color: Color) -> void:
    canvas.draw_circle(Vector2.ZERO, outer, shell_color)
    canvas.draw_circle(Vector2.ZERO, inner, Color(0.14, 0.16, 0.19, 1.0))
    canvas.draw_arc(Vector2.ZERO, outer, 0.0, TAU, 96, outline_color, 1.3)
    canvas.draw_arc(Vector2.ZERO, inner, 0.0, TAU, 96, outline_color, 1.0)
    var stride := TAU / float(max(window_count, 1))
    for idx in range(window_count):
        var angle := phase_offset + (float(idx) * stride)
        draw_shell_window(canvas, angle, inner + 1.0, outer - 2.0, window_width, outline_color)

static func draw_internal_rotor(canvas: CanvasItem, outer: float, inner: float, teeth: int, phase: float, clockwise: bool, tooth_color: Color, outline_color: Color) -> void:
    var tooth_steps: int = maxi(teeth, 8)
    var step: float = TAU / float(tooth_steps)
    var tooth_half: float = step * 0.22
    var dir: float = -1.0 if clockwise else 1.0
    canvas.draw_circle(Vector2.ZERO, outer - 1.2, Color(0.27, 0.3, 0.35, 1.0))
    for idx in range(tooth_steps):
        var center_angle: float = phase * dir + (float(idx) * step)
        var a: Vector2 = Vector2.RIGHT.rotated(center_angle - tooth_half) * (outer - 2.2)
        var b: Vector2 = Vector2.RIGHT.rotated(center_angle - tooth_half * 0.78) * outer
        var c: Vector2 = Vector2.RIGHT.rotated(center_angle + tooth_half * 0.78) * outer
        var d: Vector2 = Vector2.RIGHT.rotated(center_angle + tooth_half) * (outer - 2.2)
        canvas.draw_colored_polygon(PackedVector2Array([a, b, c, d]), tooth_color)
    canvas.draw_circle(Vector2.ZERO, inner, Color(0.12, 0.14, 0.18, 1.0))
    canvas.draw_arc(Vector2.ZERO, outer, 0.0, TAU, 84, outline_color, 1.0)
    canvas.draw_arc(Vector2.ZERO, inner, 0.0, TAU, 64, outline_color, 1.0)

static func draw_clutch_disc_pack(canvas: CanvasItem, outer: float, inner: float, mode_pulse: float) -> void:
    for idx in range(3):
        var radius := lerpf(inner, outer, float(idx + 1) / 4.0)
        var flash := 0.66 + (0.22 * maxf(0.0, sin(mode_pulse + (float(idx) * 0.8))))
        canvas.draw_arc(Vector2.ZERO, radius, 0.0, TAU, 72, Color(0.9, 0.94, 0.98, flash), 2.0)

static func draw_hub_face(canvas: CanvasItem, radius: float, _outline_color: Color) -> void:
    canvas.draw_circle(Vector2.ZERO, radius, PROJECT_PATHS_SCRIPT.PALETTE_VOID)

static func draw_shaft_port_collar(canvas: CanvasItem, port_angle: float, inner_radius: float, role: String, outline_color: Color) -> void:
    var collar_pos: Vector2 = Vector2.RIGHT.rotated(port_angle) * inner_radius
    var collar_radius: float = 5.5
    var collar_inner: float = 3.2
    var port_color: Color = Color(0.48, 0.86, 1.0, 0.92) if role == "input" else Color(1.0, 0.8, 0.36, 0.92)

    canvas.draw_circle(collar_pos, collar_radius, outline_color)
    canvas.draw_arc(collar_pos, collar_radius, 0.0, TAU, 32, Color(0.3, 0.35, 0.38, 1.0), 2.2)

    canvas.draw_circle(collar_pos, collar_inner, Color(0.18, 0.20, 0.24, 1.0))
    for spline in range(6):
        var spline_angle: float = float(spline) * (TAU / 6.0)
        var inner_pt: Vector2 = collar_pos + Vector2.RIGHT.rotated(spline_angle) * (collar_inner * 0.5)
        var outer_pt: Vector2 = collar_pos + Vector2.RIGHT.rotated(spline_angle) * collar_inner
        canvas.draw_line(inner_pt, outer_pt, port_color, 1.1)

    canvas.draw_circle(collar_pos + Vector2(0.0, -collar_radius - 1.2), 1.4, port_color)

static func draw_arrow_shape(canvas: CanvasItem, a: Vector2, b: Vector2, color: Color) -> void:
    var dir := (b - a).normalized()
    var perp := Vector2(-dir.y, dir.x)
    canvas.draw_line(a, b, color, 2.2)
    var tip := b
    var left := tip - (dir * 8.0) + (perp * 4.0)
    var right := tip - (dir * 8.0) - (perp * 4.0)
    canvas.draw_colored_polygon(PackedVector2Array([tip, left, right]), color)
