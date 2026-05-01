extends Node2D
class_name WinController

const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")
const HUD_FONT = preload("res://assets/fonts/MotionControl-Bold.otf")

@export var blockade_path: NodePath = NodePath("../Blockade")
@export var dev_level_editor_path: NodePath = NodePath("../DevLevelEditor")
@export var camera_path: NodePath = NodePath("../Camera2D")
@export var placement_controller_path: NodePath = NodePath("../PlacementController")
@export var hud_path: NodePath = NodePath("../UI")
@export var game_manager_path: NodePath = NodePath("../GameManager")
@export var main_menu_path: NodePath = NodePath("../MainMenu")
@export var lever_pick_radius: float = 28.0
@export var lever_stem_height: float = 28.0
@export var lever_tip_radius: float = 9.0
@export var lever_rest_angle_degrees: float = -32.0
@export var lever_tip_color: Color = Color(1.0, 0.78, 0.28, 1.0)
@export var lever_base_color: Color = Color(0.42, 0.32, 0.2, 1.0)

@onready var _blockade: Node = get_node_or_null(blockade_path)
@onready var _dev_level_editor: Node = get_node_or_null(dev_level_editor_path)
@onready var _camera: Camera2D = get_node_or_null(camera_path)
@onready var _placement_controller: Node = get_node_or_null(placement_controller_path)
@onready var _hud: CanvasLayer = get_node_or_null(hud_path) as CanvasLayer
@onready var _game_manager: Node = get_node_or_null(game_manager_path)
@onready var _main_menu: Node = get_node_or_null(main_menu_path)
@onready var _signal_bus: Node = get_node_or_null("/root/SignalBus")
@onready var _game_state: Node = get_node_or_null("/root/GameState")

var _lever_world_pos: Vector2 = Vector2.ZERO
var _lever_angle: float = 0.0
var _lever_animating: bool = false
var _won: bool = false

var _score_layer: CanvasLayer = null
var _score_panel: PanelContainer = null
var _score_label: Label = null
var _play_again_button: Button = null

# Confetti system
var _confetti_layer: CanvasLayer = null
var _confetti_particles: Array = []
var _confetti_colors: Array = []
const CONFETTI_COUNT: int = 80


func _ready() -> void:
	z_as_relative = false
	z_index = PROJECT_PATHS_SCRIPT.PLACEMENT_OVERLAY_Z_INDEX + 1
	set_process_unhandled_input(true)
	_reset_lever_pose()
	_compute_lever_position()
	_build_score_screen()
	_build_confetti_layer()
	queue_redraw()


func _process(_delta: float) -> void:
	if _lever_animating:
		queue_redraw()
	_update_confetti(_delta)


func _reset_lever_pose() -> void:
	_lever_angle = deg_to_rad(lever_rest_angle_degrees)


func _compute_lever_position() -> void:
	var apex := Vector2(PROJECT_PATHS_SCRIPT.VIEWPORT_CENTER_X, PROJECT_PATHS_SCRIPT.ENGINE_WORLD_Y)
	if _blockade != null and _blockade.has_method("get_cone_apex_world"):
		apex = _blockade.call("get_cone_apex_world") as Vector2

	var raw_radius := PROJECT_PATHS_SCRIPT.FRONTIER_MAX_RADIUS_CLAMP
	if _blockade != null:
		var radius_variant: Variant = _blockade.get("max_radius_clamp")
		if radius_variant != null:
			raw_radius = float(radius_variant)
	if raw_radius <= 0.0:
		raw_radius = PROJECT_PATHS_SCRIPT.WORLD_VERTICAL_EXTENT - 220.0

	var safe_radius := maxf(120.0, raw_radius - PROJECT_PATHS_SCRIPT.FRONTIER_WIN_LEVER_TOP_MARGIN)
	var target := apex + Vector2(0.0, -safe_radius)
	if _blockade != null and _blockade.has_method("constrain_world_position"):
		target = _blockade.call("constrain_world_position", target, 0.0, false) as Vector2
	_lever_world_pos = target


func _build_score_screen() -> void:
	_score_layer = CanvasLayer.new()
	add_child(_score_layer)

	_score_panel = PanelContainer.new()
	_score_panel.visible = false
	_score_panel.custom_minimum_size = Vector2(420.0, 250.0)
	_score_panel.anchor_left = 0.5
	_score_panel.anchor_top = 0.5
	_score_panel.anchor_right = 0.5
	_score_panel.anchor_bottom = 0.5
	_score_panel.offset_left = -210.0
	_score_panel.offset_top = -125.0
	_score_panel.offset_right = 210.0
	_score_panel.offset_bottom = 125.0
	_score_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_score_layer.add_child(_score_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	_score_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	_score_label = Label.new()
	_score_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.add_theme_font_override("font", HUD_FONT)
	_score_label.add_theme_font_size_override("font_size", 20)
	_score_label.text = ""
	vbox.add_child(_score_label)

	_play_again_button = Button.new()
	_play_again_button.text = "Play Again"
	_play_again_button.custom_minimum_size = Vector2(0.0, 34.0)
	_play_again_button.add_theme_font_override("font", HUD_FONT)
	_play_again_button.add_theme_font_size_override("font_size", 18)
	_play_again_button.pressed.connect(_on_play_again_pressed)
	vbox.add_child(_play_again_button)


func _draw() -> void:
	var base := _lever_world_pos
	var tip := base + Vector2(sin(_lever_angle), -cos(_lever_angle)) * lever_stem_height
	draw_circle(base, 12.0, lever_base_color)
	draw_line(base, tip, lever_base_color, 5.0, true)
	draw_circle(tip, lever_tip_radius, lever_tip_color)


func _unhandled_input(event: InputEvent) -> void:
	if _won:
		return
	if event is not InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	if get_viewport().gui_get_hovered_control() != null:
		return
	if _main_menu != null and _main_menu.has_method("is_menu_active") and bool(_main_menu.call("is_menu_active")):
		return

	var world_pos := get_global_mouse_position()
	if world_pos.distance_to(_lever_world_pos) > lever_pick_radius:
		return

	if _blockade != null and _blockade.has_method("is_position_unlocked"):
		var unlocked := bool(_blockade.call("is_position_unlocked", _lever_world_pos, 0.0))
		if not unlocked:
			_emit_feedback("The frontier has not reached the lever yet.")
			return

	_trigger_win()
	get_viewport().set_input_as_handled()


func _trigger_win() -> void:
	_won = true
	var signal_bus := get_node_or_null("/root/SignalBus")
	if signal_bus != null:
		signal_bus.component_selected.emit("")
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager != null and audio_manager.has_method("play_win"):
		audio_manager.call("play_win")
	_set_gameplay_input_enabled(false)
	_animate_lever_flick()
	_update_score_text()
	if _score_panel != null:
		_score_panel.visible = true
	_spawn_confetti()


func _animate_lever_flick() -> void:
	_lever_animating = true
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "_lever_angle", PI * 0.42, 0.35)
	tween.tween_callback(func() -> void: _lever_animating = false; queue_redraw())


func _update_score_text() -> void:
	if _score_label == null:
		return
	var run_time := 0.0
	var torque := 0.0
	if _game_state != null:
		run_time = float(_game_state.get("run_time"))
		torque = float(_game_state.get("available_torque"))

	var total_seconds := maxi(int(run_time), 0)
	var minutes := int(total_seconds / 60)
	var seconds := total_seconds % 60
	_score_label.text = "Time: %d:%02d\nTorque: %.1f" % [minutes, seconds, torque]


func _on_play_again_pressed() -> void:
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager != null and audio_manager.has_method("play_menu_click"):
		audio_manager.call("play_menu_click")
	await _restart_run()


func _restart_run() -> void:
	_animate_camera_to_start()
	_clear_confetti()
	if _score_panel != null:
		_score_panel.visible = false
	if _game_state != null and _game_state.has_method("reset_run_state"):
		_game_state.call("reset_run_state")
	if _dev_level_editor != null:
		if _dev_level_editor.has_method("start_new_run"):
			await _dev_level_editor.call("start_new_run", -1)
		elif _dev_level_editor.has_method("generate_procedural_map"):
			await _dev_level_editor.call("generate_procedural_map", -1, -1, -1)
	_won = false
	_reset_lever_pose()
	_lever_animating = false
	_compute_lever_position()
	_set_gameplay_input_enabled(true)
	queue_redraw()


func _animate_camera_to_start() -> void:
	if _camera == null:
		return
	var start_pos := Vector2(PROJECT_PATHS_SCRIPT.VIEWPORT_CENTER_X, PROJECT_PATHS_SCRIPT.VIEWPORT_CENTER_Y)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_camera, "global_position", start_pos, 0.8)


func _set_gameplay_input_enabled(enabled: bool) -> void:
	if _camera != null:
		_camera.set_process_input(enabled)
	if _placement_controller != null:
		_placement_controller.set_process_input(enabled)
	if _hud != null:
		_hud.set_process_unhandled_input(enabled)


func _emit_feedback(message: String) -> void:
	if _signal_bus != null and _signal_bus.has_signal("placement_feedback"):
		_signal_bus.placement_feedback.emit(message)


# Confetti system
func _build_confetti_layer() -> void:
	_confetti_layer = CanvasLayer.new()
	_confetti_layer.name = "ConfettiLayer"
	add_child(_confetti_layer)
	_confetti_layer.visible = false
	
	# Define confetti colors from palette
	_confetti_colors = [
		PROJECT_PATHS_SCRIPT.PALETTE_TEAL,
		PROJECT_PATHS_SCRIPT.PALETTE_AMBER,
		PROJECT_PATHS_SCRIPT.PALETTE_SALMON,
		PROJECT_PATHS_SCRIPT.PALETTE_OLIVE,
		PROJECT_PATHS_SCRIPT.PALETTE_PURPLE,
		PROJECT_PATHS_SCRIPT.PALETTE_ORANGE,
		PROJECT_PATHS_SCRIPT.PALETTE_TEAL.lightened(0.2),
		PROJECT_PATHS_SCRIPT.PALETTE_AMBER.lightened(0.2)
	]


func _spawn_confetti() -> void:
	if _confetti_layer == null:
		return
	
	# Clear existing confetti
	for particle in _confetti_particles:
		if is_instance_valid(particle["node"]):
			particle["node"].queue_free()
	_confetti_particles.clear()
	
	_confetti_layer.visible = true
	
	var viewport_size := get_viewport().get_visible_rect().size
	var center := viewport_size * 0.5
	
	for i in range(CONFETTI_COUNT):
		var confetti := Control.new()
		confetti.set_anchors_preset(Control.PRESET_TOP_LEFT)
		confetti.position = center
		confetti.custom_minimum_size = Vector2(8.0, 8.0)
		_confetti_layer.add_child(confetti)
		
		# Random burst direction
		var angle := randf() * TAU
		var speed := 200.0 + randf() * 400.0
		var upward_bias := -300.0 - randf() * 200.0  # Initial upward burst
		
		var particle := {
			"node": confetti,
			"pos": center,
			"vel": Vector2(cos(angle) * speed, sin(angle) * speed + upward_bias),
			"rot": randf() * TAU,
			"rot_speed": (randf() - 0.5) * 10.0,
			"color": _confetti_colors.pick_random(),
			"scale": 0.6 + randf() * 0.6,
			"life": 3.0 + randf() * 2.0
		}
		_confetti_particles.append(particle)
		_draw_confetti_piece(confetti, particle)


func _draw_confetti_piece(node: Control, particle: Dictionary) -> void:
	# Create a simple colored rect for each confetti piece
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(8.0, 8.0) * particle["scale"]
	panel.modulate = particle["color"]
	
	# Add a colored stylebox
	var style := StyleBoxFlat.new()
	style.bg_color = particle["color"]
	style.corner_radius_top_left = 1.0
	style.corner_radius_top_right = 1.0
	style.corner_radius_bottom_left = 1.0
	style.corner_radius_bottom_right = 1.0
	panel.add_theme_stylebox_override("panel", style)
	node.add_child(panel)


func _update_confetti(delta: float) -> void:
	if _confetti_particles.is_empty():
		return
	
	var gravity := 400.0
	var viewport_size := get_viewport().get_visible_rect().size
	
	for particle in _confetti_particles:
		if not is_instance_valid(particle["node"]):
			continue
		
		# Apply gravity
		particle["vel"].y += gravity * delta
		
		# Update position
		particle["pos"] += particle["vel"] * delta
		
		# Update rotation
		particle["rot"] += particle["rot_speed"] * delta
		
		# Fade out over time
		particle["life"] -= delta
		if particle["life"] < 1.0:
			particle["node"].modulate.a = particle["life"]
		
		# Wrap horizontally (optional - keeps confetti on screen)
		if particle["pos"].x < -20.0:
			particle["pos"].x = viewport_size.x + 20.0
		elif particle["pos"].x > viewport_size.x + 20.0:
			particle["pos"].x = -20.0
		
		# Update node position and rotation
		particle["node"].position = particle["pos"]
		particle["node"].rotation = particle["rot"]
	
	# Hide confetti layer when all particles are done
	var any_alive := false
	for particle in _confetti_particles:
		if particle["life"] > 0.0:
			any_alive = true
			break
	if not any_alive:
		_confetti_layer.visible = false


func _clear_confetti() -> void:
	for particle in _confetti_particles:
		if is_instance_valid(particle["node"]):
			particle["node"].queue_free()
	_confetti_particles.clear()
	_confetti_layer.visible = false
