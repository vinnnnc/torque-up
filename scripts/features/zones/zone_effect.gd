@tool
extends Node2D
class_name ZoneEffect

@export var zone_type: String = "heat"
@export var radius: float = 140.0
@export var friction_multiplier: float = 1.2
@export var efficiency_multiplier: float = 0.92
@export var torque_load_add: float = 0.0
@export var power_output_multiplier: float = 1.0
@export var power_output_add: float = 0.0
@export var show_gizmo: bool = true
@export var gizmo_color: Color = Color(1.0, 0.42, 0.28, 0.2)
@export var follow_target_path: NodePath
@export var follow_offset: Vector2 = Vector2.ZERO

var _follow_target: Node2D

func _ready() -> void:
	_resolve_follow_target()
	_update_follow_position()
	queue_redraw()


func _process(_delta: float) -> void:
	if _follow_target == null and not follow_target_path.is_empty():
		_resolve_follow_target()
	_update_follow_position()
	if Engine.is_editor_hint() and show_gizmo:
		queue_redraw()


func _resolve_follow_target() -> void:
	if follow_target_path.is_empty():
		_follow_target = null
		return

	_follow_target = get_node_or_null(follow_target_path) as Node2D


func _update_follow_position() -> void:
	if _follow_target == null:
		return

	global_position = _follow_target.global_position + follow_offset


func get_effect_at(world_pos: Vector2) -> Dictionary:
	var distance := global_position.distance_to(world_pos)
	if distance > radius:
		return {
			"friction_multiplier": 1.0,
			"efficiency_multiplier": 1.0,
			"torque_load_add": 0.0,
			"power_output_multiplier": 1.0,
			"power_output_add": 0.0
		}

	var falloff := 1.0 - clampf(distance / maxf(radius, 1.0), 0.0, 1.0)
	var friction := lerpf(1.0, friction_multiplier, falloff)
	var efficiency := lerpf(1.0, efficiency_multiplier, falloff)
	var torque_add := torque_load_add * falloff
	var output_multiplier := lerpf(1.0, power_output_multiplier, falloff)
	var output_add := power_output_add * falloff
	return {
		"friction_multiplier": friction,
		"efficiency_multiplier": efficiency,
		"torque_load_add": torque_add,
		"power_output_multiplier": output_multiplier,
		"power_output_add": output_add
	}


func _draw() -> void:
	if not show_gizmo:
		return

	draw_circle(Vector2.ZERO, radius, gizmo_color)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(gizmo_color.r, gizmo_color.g, gizmo_color.b, 0.8), 1.8)
