@tool
extends Node2D
class_name BarrierZone

@export var radius: float = 52.0
@export var show_gizmo: bool = true
@export var gizmo_fill_color: Color = Color(0.22, 0.22, 0.24, 0.26)
@export var gizmo_outline_color: Color = Color(0.8, 0.28, 0.28, 0.88)

func _ready() -> void:
	queue_redraw()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and show_gizmo:
		queue_redraw()


func get_block_data() -> Dictionary:
	return {
		"position": global_position,
		"radius": maxf(radius, 1.0)
	}


func _draw() -> void:
	if not show_gizmo:
		return

	draw_circle(Vector2.ZERO, radius, gizmo_fill_color)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, gizmo_outline_color, 2.2)
