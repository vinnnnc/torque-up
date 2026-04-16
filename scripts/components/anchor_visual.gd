extends Node2D
class_name AnchorVisual

const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")

@export var fill_color: Color = Color(0.18, 0.56, 1.0, 0.35)
@export var ring_color: Color = Color(0.4, 0.8, 1.0, 1.0)
@export var radius: float = 20.0
@export var ring_thickness: float = 3.0
@export var show_neighbor_slots: bool = false
@export var socket_count: int = 8
@export var socket_radius: float = PROJECT_PATHS_SCRIPT.DEFAULT_SOCKET_RADIUS

func _ready() -> void:
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, fill_color)
	draw_arc(Vector2.ZERO, radius + 4.0, 0.0, TAU, 48, ring_color, ring_thickness)

	# Draw a simple crosshair to make anchors legible when zoomed out.
	draw_line(Vector2(-radius * 0.35, 0), Vector2(radius * 0.35, 0), ring_color, 2.0)
	draw_line(Vector2(0, -radius * 0.35), Vector2(0, radius * 0.35), ring_color, 2.0)

	if show_neighbor_slots:
		for socket_index in range(socket_count):
			var angle := TAU * (float(socket_index) / float(socket_count))
			var slot_pos := Vector2.RIGHT.rotated(angle) * socket_radius
			draw_circle(slot_pos, 5.0, Color(ring_color.r, ring_color.g, ring_color.b, 0.22))
			draw_arc(slot_pos, 5.0, 0.0, TAU, 24, Color(ring_color.r, ring_color.g, ring_color.b, 0.9), 1.5)
