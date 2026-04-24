extends Camera2D
class_name GameCamera2D
const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")


@export var pan_speed: float = 500.0
@export var drag_button: MouseButton = MOUSE_BUTTON_MIDDLE
@export var min_zoom: float = 0.5
@export var max_zoom: float = 2.3
@export var zoom_step: float = 0.1

var _is_dragging: bool = false

var _camera_min_y: float = 0.0
var _camera_max_y: float = 0.0

@onready var _frontier_node: Node = get_node_or_null("../Blockade")


func _ready() -> void:
	_camera_min_y = PROJECT_PATHS_SCRIPT.CAMERA_MIN_Y
	_camera_max_y = PROJECT_PATHS_SCRIPT.CAMERA_MAX_Y

func _process(delta: float) -> void:
	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	input_dir.y = Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")

	if input_dir.length_squared() > 0.0:
		position += input_dir.normalized() * pan_speed * delta * zoom.x

	_constrain_camera_position()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == drag_button:
			_is_dragging = mouse_event.pressed
			return

		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_event.pressed:
			_apply_zoom(zoom.x + zoom_step)
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_event.pressed:
			_apply_zoom(zoom.x - zoom_step)
		return

	if event is InputEventMouseMotion and _is_dragging:
		var motion := event as InputEventMouseMotion
		var safe_zoom_x := maxf(zoom.x, 0.001)
		var safe_zoom_y := maxf(zoom.y, 0.001)
		var world_drag_delta := Vector2(motion.relative.x / safe_zoom_x, motion.relative.y / safe_zoom_y)
		position -= world_drag_delta
		_constrain_camera_position()


func _apply_zoom(next_zoom: float) -> void:
	var clamped_zoom := clampf(next_zoom, min_zoom, max_zoom)
	zoom = Vector2.ONE * clamped_zoom


func _constrain_camera_position() -> void:
	position.y = clampf(position.y, _camera_min_y, _camera_max_y)

	if _frontier_node != null and _frontier_node.has_method("constrain_world_position"):
		var constrained: Variant = _frontier_node.call("constrain_world_position", global_position, 0.0, false)
		if constrained is Vector2:
			global_position = constrained
