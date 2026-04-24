extends CanvasLayer
class_name MainMenuController

@export var camera_path: NodePath = NodePath("../Camera2D")
@export var engine_path: NodePath = NodePath("../Network/CentralEngine")
@export var placement_controller_path: NodePath = NodePath("../PlacementController")
@export var hud_path: NodePath = NodePath("../UI")
@export var dev_level_editor_path: NodePath = NodePath("../DevLevelEditor")
@export var menu_camera_offset: Vector2 = Vector2(260.0, -140.0)
@export var menu_camera_zoom: float = 1.0

@onready var _panel: PanelContainer = $Root/Panel
@onready var _tutorial_checkbox: CheckBox = $Root/Panel/Margin/VBox/TutorialCheckbox
@onready var _start_button: Button = $Root/Panel/Margin/VBox/StartButton
@onready var _panel_vbox: VBoxContainer = $Root/Panel/Margin/VBox
@onready var _camera: Camera2D = get_node_or_null(camera_path)
@onready var _engine: Node2D = get_node_or_null(engine_path)
@onready var _placement_controller: Node = get_node_or_null(placement_controller_path)
@onready var _hud: CanvasLayer = get_node_or_null(hud_path) as CanvasLayer
@onready var _dev_level_editor: Node = get_node_or_null(dev_level_editor_path)
@onready var _game_state: Node = get_node_or_null("/root/GameState")

var _initial_camera_position: Vector2 = Vector2.ZERO
var _initial_camera_zoom: Vector2 = Vector2.ONE
var _has_initial_camera_state: bool = false
var _menu_active: bool = true
var _menu_mode: String = "startup"
var _restart_button: Button = null

const MENU_MODE_STARTUP := "startup"
const MENU_MODE_PAUSE := "pause"


func _ready() -> void:
	if _camera != null:
		_initial_camera_position = _camera.position
		_initial_camera_zoom = _camera.zoom
		_has_initial_camera_state = true

	set_process_unhandled_input(true)
	_ensure_restart_button()

	if _start_button != null and not _start_button.pressed.is_connected(_on_start_pressed):
		_start_button.pressed.connect(_on_start_pressed)

	_open_startup_menu()



func _ensure_restart_button() -> void:
	if _panel_vbox == null or _restart_button != null:
		return
	_restart_button = Button.new()
	_restart_button.custom_minimum_size = Vector2(0, 32)
	_restart_button.text = "Restart Run"
	_restart_button.visible = false
	_restart_button.pressed.connect(_on_restart_pressed)
	_panel_vbox.add_child(_restart_button)


func _open_startup_menu() -> void:
	_menu_mode = MENU_MODE_STARTUP
	_show_menu_state(true)
	_apply_menu_camera_pose()


func _open_pause_menu() -> void:
	_menu_mode = MENU_MODE_PAUSE
	_show_menu_state(false)


func _show_menu_state(startup_mode: bool) -> void:
	_menu_active = true
	visible = true
	if _panel != null:
		_panel.visible = true
	if _tutorial_checkbox != null:
		_tutorial_checkbox.visible = startup_mode
	if _start_button != null:
		_start_button.text = "Start Game" if startup_mode else "Resume"
	if _restart_button != null:
		_restart_button.visible = not startup_mode

	if _hud != null:
		_hud.visible = false

	_set_gameplay_input_enabled(false)


func _on_start_pressed() -> void:
	if _menu_mode == MENU_MODE_STARTUP:
		var tutorial_enabled := _tutorial_checkbox != null and _tutorial_checkbox.button_pressed
		if _game_state != null:
			if _game_state.has_method("set_tutorial_enabled"):
				_game_state.call("set_tutorial_enabled", tutorial_enabled)
			elif _game_state.has_meta("tutorial_enabled"):
				_game_state.set_meta("tutorial_enabled", tutorial_enabled)
		await _generate_new_run()
		await _resume_gameplay(true)
		return

	await _resume_gameplay(false)


func _on_restart_pressed() -> void:
	await _generate_new_run()
	if _camera != null and _has_initial_camera_state:
		_camera.position = _initial_camera_position
		_camera.zoom = _initial_camera_zoom
	await _resume_gameplay(false)


func _resume_gameplay(restore_start_camera: bool) -> void:
	_menu_active = false
	visible = false
	if _panel != null:
		_panel.visible = false
	if _hud != null:
		_hud.visible = true

	if restore_start_camera:
		# Keep gameplay input disabled during startup camera tween.
		await _restore_gameplay_camera_pose()

	_set_gameplay_input_enabled(true)


func _generate_new_run() -> void:
	if _game_state != null and _game_state.has_method("reset_run_state"):
		_game_state.call("reset_run_state")

	if _dev_level_editor == null:
		return
	if _dev_level_editor.has_method("start_new_run"):
		await _dev_level_editor.call("start_new_run", -1)
	elif _dev_level_editor.has_method("generate_procedural_map"):
		await _dev_level_editor.call("generate_procedural_map", -1, -1, -1)


func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventKey:
		return
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode != KEY_ESCAPE:
		return
	if key_event.ctrl_pressed or key_event.alt_pressed or key_event.meta_pressed:
		return
	if _is_text_input_focused():
		return

	if _menu_active:
		if _menu_mode == MENU_MODE_PAUSE:
			await _resume_gameplay(false)
			get_viewport().set_input_as_handled()
		return

	_open_pause_menu()
	get_viewport().set_input_as_handled()


func _is_text_input_focused() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner == null:
		return false
	return focus_owner is LineEdit or focus_owner is TextEdit


func _set_gameplay_input_enabled(enabled: bool) -> void:
	if _camera != null:
		_camera.set_process(enabled)
		_camera.set_process_input(enabled)

	if _placement_controller != null:
		_placement_controller.set_process(enabled)
		_placement_controller.set_process_input(enabled)

	if _hud != null:
		_hud.set_process(enabled)
		_hud.set_process_unhandled_input(enabled)


func _apply_menu_camera_pose() -> void:
	if _camera == null:
		return

	var focus_position := _camera.position
	if _engine != null:
		focus_position = _engine.position + menu_camera_offset

	_camera.position = focus_position
	_camera.zoom = Vector2.ONE * maxf(menu_camera_zoom, 0.05)


func _restore_gameplay_camera_pose() -> void:
	if _camera == null or not _has_initial_camera_state:
		return

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_parallel(true)
	
	# Smoothly animate camera position to gameplay start position
	tween.tween_property(_camera, "position", _initial_camera_position, 0.6)
	# Smoothly animate camera zoom to gameplay start zoom
	tween.tween_property(_camera, "zoom", _initial_camera_zoom, 0.6)
	
	# Wait for tween to complete before returning
	await tween.finished


func is_menu_active() -> bool:
	return _menu_active
