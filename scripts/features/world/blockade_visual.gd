extends Node2D
## World-space blockade veil. Anything below `cutoff_world_y` is darkened.

const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")

@export var cutoff_world_y: float = PROJECT_PATHS_SCRIPT.ENGINE_WORLD_Y
@export var veil_color: Color = Color(0.0, 0.0, 0.0, 0.85)
@export var world_half_width: float = 8000.0
@export var world_height: float = 8000.0


func _ready() -> void:
	z_as_relative = false
	z_index = 250
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(
		Vector2(-world_half_width, cutoff_world_y),
		Vector2(world_half_width * 2.0, world_height)
	)
	draw_rect(rect, veil_color, true)
