extends Node2D
class_name ShaftLinkComponent

@export var rod_color: Color = Color(0.62, 0.67, 0.74, 1.0)
@export var accent_color: Color = Color(0.82, 0.86, 0.92, 0.9)
@export var rod_width: float = 9.0
@export var cap_radius: float = 6.0

var gear_a: Node2D = null
var gear_b: Node2D = null


func configure(first_gear: Node2D, second_gear: Node2D) -> void:
	gear_a = first_gear
	gear_b = second_gear
	queue_redraw()


func _process(_delta: float) -> void:
	if gear_a == null or gear_b == null:
		return
	global_position = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	if gear_a == null or gear_b == null:
		return

	var a := to_local(gear_a.global_position)
	var b := to_local(gear_b.global_position)
	var axis := b - a
	var len := axis.length()
	if len <= 0.001:
		return

	var dir := axis / len
	var n := dir.rotated(PI * 0.5)
	var half_w := rod_width * 0.5

	var p1 := a + n * half_w
	var p2 := b + n * half_w
	var p3 := b - n * half_w
	var p4 := a - n * half_w

	draw_colored_polygon(PackedVector2Array([p1, p2, p3, p4]), rod_color)
	draw_line(a, b, accent_color, maxf(1.5, rod_width * 0.22))
	draw_circle(a, cap_radius, accent_color)
	draw_circle(b, cap_radius, accent_color)


func get_distance_to_world_point(world_pos: Vector2) -> float:
	if gear_a == null or gear_b == null:
		return INF
	return _point_segment_distance(world_pos, gear_a.global_position, gear_b.global_position)


func _point_segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var segment := b - a
	var segment_length_sq := segment.length_squared()
	if segment_length_sq <= 0.001:
		return point.distance_to(a)

	var t := clampf((point - a).dot(segment) / segment_length_sq, 0.0, 1.0)
	var closest := a + segment * t
	return point.distance_to(closest)
