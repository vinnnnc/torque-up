extends Camera2D
class_name GameCamera2D

@export var pan_speed: float = 500.0
@export var drag_button: MouseButton = MOUSE_BUTTON_MIDDLE
@export var min_zoom: float = 0.5
@export var max_zoom: float = 2.3
@export var zoom_step: float = 0.1

var _is_dragging: bool = false

func _process(delta: float) -> void:
	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	input_dir.y = Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")

	if input_dir.length_squared() > 0.0:
		position += input_dir.normalized() * pan_speed * delta * zoom.x


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
		position -= motion.relative * zoom.x


func _apply_zoom(next_zoom: float) -> void:
	var clamped_zoom := clampf(next_zoom, min_zoom, max_zoom)
	zoom = Vector2.ONE * clamped_zoom
