extends CanvasLayer
class_name MainMenuController

const STARTUP_SNAPSHOT_PATH := "res://data/menu_startup_snapshot.json"

@export var camera_path: NodePath = NodePath("../Camera2D")
@export var engine_path: NodePath = NodePath("../Network/CentralEngine")
@export var placement_controller_path: NodePath = NodePath("../PlacementController")
@export var hud_path: NodePath = NodePath("../UI")
@export var dev_level_editor_path: NodePath = NodePath("../DevLevelEditor")
@export var menu_camera_offset: Vector2 = Vector2(50.0, -70.0)
@export var menu_camera_zoom: float = 3.0

@onready var _panel: Control = $Root/MenuCard
@onready var _tutorial_checkbox: CheckBox = $Root/MenuCard/VBox/TutorialCheckbox
@onready var _start_button: Button = $Root/MenuCard/VBox/StartButton
@onready var _panel_vbox: VBoxContainer = $Root/MenuCard/VBox
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
var _main_menu_button: Button = null
var _show_controls_button: Button = null
var _how_to_play_button: Button = null
var _info_overlay: Control = null
var _info_panel: PanelContainer = null
var _info_title: Label = null
var _info_content: VBoxContainer = null
var _audio_toggle_row: HBoxContainer = null
var _music_toggle_button: Button = null
var _sfx_toggle_button: Button = null
var _seed_row: HBoxContainer = null
var _seed_checkbox: CheckBox = null
var _seed_input: LineEdit = null

const MENU_MODE_STARTUP := "startup"
const MENU_MODE_PAUSE := "pause"


func _ready() -> void:
	if _camera != null:
		_initial_camera_position = _camera.position
		_initial_camera_zoom = _camera.zoom
		_has_initial_camera_state = true

	set_process_unhandled_input(true)
	_ensure_help_buttons()
	_ensure_restart_button()
	_build_info_overlay()

	const MOTION_CONTROL := preload("res://assets/fonts/MotionControl-Bold.otf")
	for node in [$Root/MenuCard/VBox/Subtitle, _start_button, _tutorial_checkbox, _show_controls_button, _how_to_play_button]:
		if node != null:
			node.add_theme_font_override("font", MOTION_CONTROL)

	if _start_button != null and not _start_button.pressed.is_connected(_on_start_pressed):
		_start_button.pressed.connect(_on_start_pressed)

	_open_startup_menu()
	_build_audio_toggle_buttons()
	call_deferred("_load_startup_snapshot_background")



func _ensure_restart_button() -> void:
	if _panel_vbox == null or _restart_button != null:
		return
	_restart_button = Button.new()
	_restart_button.custom_minimum_size = Vector2(0, 32)
	_restart_button.text = "Restart Run"
	_restart_button.visible = false
	_restart_button.pressed.connect(_on_restart_pressed)
	_restart_button.add_theme_font_override("font", load("res://assets/fonts/MotionControl-Bold.otf"))
	_panel_vbox.call_deferred("add_child", _restart_button)
	_main_menu_button = Button.new()
	_main_menu_button.custom_minimum_size = Vector2(0, 32)
	_main_menu_button.text = "Main Menu"
	_main_menu_button.visible = false
	_main_menu_button.pressed.connect(_on_main_menu_pressed)
	_main_menu_button.add_theme_font_override("font", load("res://assets/fonts/MotionControl-Bold.otf"))
	_panel_vbox.call_deferred("add_child", _main_menu_button)


func _ensure_help_buttons() -> void:
	if _panel_vbox == null:
		return
	if _show_controls_button == null:
		_show_controls_button = Button.new()
		_show_controls_button.custom_minimum_size = Vector2(0, 32)
		_show_controls_button.text = "Show Controls"
		_show_controls_button.pressed.connect(_on_show_controls_pressed)
		_panel_vbox.call_deferred("add_child", _show_controls_button)
	if _how_to_play_button == null:
		_how_to_play_button = Button.new()
		_how_to_play_button.custom_minimum_size = Vector2(0, 32)
		_how_to_play_button.text = "How To Play"
		_how_to_play_button.pressed.connect(_on_how_to_play_pressed)
		_panel_vbox.call_deferred("add_child", _how_to_play_button)
	if _seed_row == null:
		_seed_row = HBoxContainer.new()
		_seed_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_seed_checkbox = CheckBox.new()
		const MOTION_FONT_PATH := "res://assets/fonts/MotionControl-Bold.otf"
		_seed_checkbox.text = "Seed"
		_seed_checkbox.add_theme_font_override("font", load(MOTION_FONT_PATH))
		_seed_checkbox.add_theme_font_size_override("font_size", 11)
		_seed_checkbox.toggled.connect(func(on: bool) -> void: _seed_input.visible = on)
		_seed_input = LineEdit.new()
		_seed_input.placeholder_text = "0"
		_seed_input.max_length = 10
		_seed_input.custom_minimum_size = Vector2(80, 0)
		_seed_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_seed_input.add_theme_font_override("font", load(MOTION_FONT_PATH))
		_seed_input.add_theme_font_size_override("font_size", 11)
		_seed_input.visible = false
		_seed_row.add_child(_seed_checkbox)
		_seed_row.add_child(_seed_input)
		_panel_vbox.call_deferred("add_child", _seed_row)


func _build_info_overlay() -> void:
	var root := get_node_or_null("Root") as Control
	if root == null or _info_overlay != null:
		return

	_info_overlay = Control.new()
	_info_overlay.name = "InfoOverlay"
	_info_overlay.visible = false
	_info_overlay.anchor_left = 0.0
	_info_overlay.anchor_top = 0.0
	_info_overlay.anchor_right = 1.0
	_info_overlay.anchor_bottom = 1.0
	_info_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_info_overlay)

	var shade := ColorRect.new()
	shade.anchor_right = 1.0
	shade.anchor_bottom = 1.0
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.color = Color(0.05, 0.03, 0.07, 0.72)
	_info_overlay.add_child(shade)

	_info_panel = PanelContainer.new()
	_info_panel.custom_minimum_size = Vector2(500, 320)
	_info_panel.anchor_left = 0.5
	_info_panel.anchor_top = 0.5
	_info_panel.anchor_right = 0.5
	_info_panel.anchor_bottom = 0.5
	_info_panel.offset_left = -250
	_info_panel.offset_top = -160
	_info_panel.offset_right = 250
	_info_panel.offset_bottom = 160
	_info_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.11, 0.08, 0.13, 0.96)
	panel_style.border_color = Color(0.92, 0.76, 0.45, 0.55)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(14)
	_info_panel.add_theme_stylebox_override("panel", panel_style)
	_info_overlay.add_child(_info_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	_info_panel.add_child(margin)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	margin.add_child(stack)

	_info_title = Label.new()
	_info_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_title.add_theme_font_override("font", load("res://assets/fonts/MotionControl-Bold.otf"))
	_info_title.add_theme_font_size_override("font_size", 24)
	stack.add_child(_info_title)

	_info_content = VBoxContainer.new()
	_info_content.add_theme_constant_override("separation", 8)
	_info_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(_info_content)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(0, 34)
	close_button.add_theme_font_override("font", load("res://assets/fonts/MotionControl-Bold.otf"))
	close_button.pressed.connect(_hide_info_overlay)
	stack.add_child(close_button)


func _open_startup_menu() -> void:
	_menu_mode = MENU_MODE_STARTUP
	_show_menu_state(true)
	_apply_menu_camera_pose()


func _open_pause_menu() -> void:
	_menu_mode = MENU_MODE_PAUSE
	var signal_bus := get_node_or_null("/root/SignalBus")
	if signal_bus != null:
		signal_bus.component_selected.emit("")
	_show_menu_state(false)
	var gm := get_node_or_null("../GameManager")
	if gm != null:
		gm.set("_gameplay_paused", true)


func _show_menu_state(startup_mode: bool) -> void:
	_menu_active = true
	visible = true
	if _panel != null:
		_panel.visible = true
	if _tutorial_checkbox != null:
		_tutorial_checkbox.visible = false
	if _show_controls_button != null:
		_show_controls_button.visible = true
	if _how_to_play_button != null:
		_how_to_play_button.visible = true
	if _seed_row != null:
		_seed_row.visible = startup_mode
	if _start_button != null:
		_start_button.text = "Start Game" if startup_mode else "Resume"
	if _restart_button != null:
		_restart_button.visible = not startup_mode
	if _main_menu_button != null:
		_main_menu_button.visible = not startup_mode
	if not startup_mode:
		_hide_info_overlay()

	if _hud != null:
		_hud.visible = false

	_set_gameplay_input_enabled(false)


func _on_start_pressed() -> void:
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager != null and audio_manager.has_method("play_menu_click"):
		audio_manager.call("play_menu_click")

	if _menu_mode == MENU_MODE_STARTUP:
		var tutorial_enabled := false
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
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager != null and audio_manager.has_method("play_menu_click"):
		audio_manager.call("play_menu_click")

	await _generate_new_run()
	if _camera != null and _has_initial_camera_state:
		_camera.position = _initial_camera_position
		_camera.zoom = _initial_camera_zoom
	await _resume_gameplay(false)


func _on_main_menu_pressed() -> void:
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager != null and audio_manager.has_method("play_menu_click"):
		audio_manager.call("play_menu_click")
	var gm := get_node_or_null("../GameManager")
	if gm != null:
		gm.set("_gameplay_paused", false)
	_open_startup_menu()



func _on_show_controls_pressed() -> void:
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager != null and audio_manager.has_method("play_menu_click"):
		audio_manager.call("play_menu_click")
	_show_controls_overlay()


func _on_how_to_play_pressed() -> void:
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager != null and audio_manager.has_method("play_menu_click"):
		audio_manager.call("play_menu_click")
	_show_how_to_play_overlay()


func _show_controls_overlay() -> void:
	if _info_overlay == null or _info_title == null or _info_content == null:
		return
	_info_title.text = "Controls"
	for child in _info_content.get_children():
		child.queue_free()

	var rows := [
		{"keys": ["W", "A", "S", "D"], "action": "Pan camera"},
		{"keys": ["Mouse Wheel"], "action": "Zoom in / out"},
		{"keys": ["Middle Mouse"], "action": "Drag camera"},
		{"keys": ["1", "2", "3"], "action": "Select gear size"},
		{"keys": ["X"], "action": "Delete mode"},
		{"keys": ["Esc"], "action": "Pause menu"}
	]

	for row_raw in rows:
		var row := row_raw as Dictionary
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		_info_content.add_child(line)

		var key_box := HBoxContainer.new()
		key_box.add_theme_constant_override("separation", 5)
		line.add_child(key_box)

		for key_text_raw in (row.get("keys", []) as Array):
			key_box.add_child(_create_keycap(str(key_text_raw)))

		var action_label := Label.new()
		action_label.text = "  " + str(row.get("action", ""))
		action_label.add_theme_font_override("font", load("res://assets/fonts/MotionControl-Bold.otf"))
		action_label.add_theme_font_size_override("font_size", 16)
		action_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(action_label)

	_info_overlay.visible = true


func _show_how_to_play_overlay() -> void:
	if _info_overlay == null or _info_title == null or _info_content == null:
		return
	_info_title.text = "How To Play"
	for child in _info_content.get_children():
		child.queue_free()

	var lines := [
		"1. Place gears and connect power nodes to the central generator.",
		"2. Watch Torque in the HUD. Connected routes feed the generator.",
		"3. Avoid jams/conflicts and improve routing to sustain output.",
		"4. Expand outward and keep the network stable as load grows.",
		"5. Hot zones reduce gear efficiency, causing torque loss. Cold zones increase efficiency for a torque bonus. Route through cold zones for maximum output.",
		"6. When your network is ready, click the lever to complete the run."
	]
	for text in lines:
		var line := Label.new()
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.text = text
		line.add_theme_font_override("font", load("res://assets/fonts/MotionControl-Bold.otf"))
		line.add_theme_font_size_override("font_size", 16)
		_info_content.add_child(line)

	_info_overlay.visible = true


func _hide_info_overlay() -> void:
	if _info_overlay == null:
		return
	_info_overlay.visible = false


func _create_keycap(text: String) -> PanelContainer:
	var cap := PanelContainer.new()
	cap.custom_minimum_size = Vector2(0, 30)
	var cap_style := StyleBoxFlat.new()
	cap_style.bg_color = Color(0.19, 0.15, 0.23, 1.0)
	cap_style.border_color = Color(1.0, 0.92, 0.78, 0.55)
	cap_style.set_border_width_all(1)
	cap_style.set_corner_radius_all(8)
	cap_style.content_margin_left = 10
	cap_style.content_margin_right = 10
	cap_style.content_margin_top = 4
	cap_style.content_margin_bottom = 4
	cap.add_theme_stylebox_override("panel", cap_style)

	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", load("res://assets/fonts/MotionControl-Bold.otf"))
	label.add_theme_font_size_override("font_size", 14)
	cap.add_child(label)
	return cap


func _build_audio_toggle_buttons() -> void:
	var root := get_node_or_null("Root") as Control
	if root == null or _audio_toggle_row != null:
		return

	_audio_toggle_row = HBoxContainer.new()
	_audio_toggle_row.name = "AudioToggleRow"
	_audio_toggle_row.anchor_left = 1.0
	_audio_toggle_row.anchor_right = 1.0
	_audio_toggle_row.anchor_top = 0.0
	_audio_toggle_row.anchor_bottom = 0.0
	_audio_toggle_row.offset_left = -188.0
	_audio_toggle_row.offset_right = -16.0
	_audio_toggle_row.offset_top = 14.0
	_audio_toggle_row.offset_bottom = 46.0
	_audio_toggle_row.alignment = BoxContainer.ALIGNMENT_END
	_audio_toggle_row.add_theme_constant_override("separation", 6)
	root.add_child(_audio_toggle_row)

	_music_toggle_button = Button.new()
	_music_toggle_button.custom_minimum_size = Vector2(84.0, 28.0)
	_music_toggle_button.pressed.connect(_on_music_toggle_pressed)
	_audio_toggle_row.add_child(_music_toggle_button)

	_sfx_toggle_button = Button.new()
	_sfx_toggle_button.custom_minimum_size = Vector2(84.0, 28.0)
	_sfx_toggle_button.pressed.connect(_on_sfx_toggle_pressed)
	_audio_toggle_row.add_child(_sfx_toggle_button)

	var motion_control := load("res://assets/fonts/MotionControl-Bold.otf")
	if motion_control != null:
		_music_toggle_button.add_theme_font_override("font", motion_control)
		_sfx_toggle_button.add_theme_font_override("font", motion_control)

	_update_audio_toggle_labels()


func _on_music_toggle_pressed() -> void:
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager == null:
		return
	if audio_manager.has_method("toggle_music_enabled"):
		audio_manager.call("toggle_music_enabled")
	if audio_manager.has_method("play_menu_click"):
		audio_manager.call("play_menu_click")
	_update_audio_toggle_labels()


func _on_sfx_toggle_pressed() -> void:
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager == null:
		return
	if audio_manager.has_method("is_sfx_enabled") and bool(audio_manager.call("is_sfx_enabled")):
		if audio_manager.has_method("play_menu_click"):
			audio_manager.call("play_menu_click")
	if audio_manager.has_method("toggle_sfx_enabled"):
		audio_manager.call("toggle_sfx_enabled")
	_update_audio_toggle_labels()


func _update_audio_toggle_labels() -> void:
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager == null:
		if _music_toggle_button != null:
			_music_toggle_button.text = "MUSIC"
		if _sfx_toggle_button != null:
			_sfx_toggle_button.text = "SFX"
		return

	var music_on := true
	var sfx_on := true
	if audio_manager.has_method("is_music_enabled"):
		music_on = bool(audio_manager.call("is_music_enabled"))
	if audio_manager.has_method("is_sfx_enabled"):
		sfx_on = bool(audio_manager.call("is_sfx_enabled"))

	if _music_toggle_button != null:
		_music_toggle_button.text = "MUSIC ON" if music_on else "MUSIC OFF"
	if _sfx_toggle_button != null:
		_sfx_toggle_button.text = "SFX ON" if sfx_on else "SFX OFF"


func _resume_gameplay(restore_start_camera: bool) -> void:
	_menu_active = false
	visible = false
	if _panel != null:
		_panel.visible = false
	if _hud != null:
		_hud.visible = true

	var gm := get_node_or_null("../GameManager")
	if gm != null:
		gm.set("_gameplay_paused", false)

	if restore_start_camera:
		# Keep gameplay input disabled during startup camera tween.
		await _restore_gameplay_camera_pose()

	_set_gameplay_input_enabled(true)


func _generate_new_run() -> void:
	if _game_state != null and _game_state.has_method("reset_run_state"):
		_game_state.call("reset_run_state")

	var chosen_seed: int = -1
	if _seed_checkbox != null and _seed_checkbox.button_pressed:
		if _seed_input != null and _seed_input.text.is_valid_int():
			chosen_seed = _seed_input.text.to_int()

	if _dev_level_editor == null:
		return
	if _dev_level_editor.has_method("start_new_run"):
		await _dev_level_editor.call("start_new_run", chosen_seed)
	elif _dev_level_editor.has_method("generate_procedural_map"):
		await _dev_level_editor.call("generate_procedural_map", -1, -1, chosen_seed)


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

	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager != null and audio_manager.has_method("play_menu_click"):
		audio_manager.call("play_menu_click")
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

	await get_tree().process_frame

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


func _load_startup_snapshot_background() -> void:
	if _menu_mode != MENU_MODE_STARTUP:
		push_warning("MainMenu: startup snapshot skipped (not in startup mode)")
		return
	if _dev_level_editor == null:
		push_warning("MainMenu: startup snapshot skipped (DevLevelEditor missing)")
		return
	if not _dev_level_editor.has_method("load_level_from_path"):
		push_warning("MainMenu: startup snapshot skipped (load_level_from_path missing)")
		return
	if not FileAccess.file_exists(STARTUP_SNAPSHOT_PATH):
		push_warning("MainMenu: startup snapshot file not found at %s" % [STARTUP_SNAPSHOT_PATH])
		return

	# Wait one frame so main-scene startup nodes settle before mutating world state.
	await get_tree().process_frame
	if _menu_mode != MENU_MODE_STARTUP:
		push_warning("MainMenu: startup snapshot aborted (menu mode changed)")
		return
	_dev_level_editor.call("load_level_from_path", STARTUP_SNAPSHOT_PATH)
	await get_tree().process_frame
	_focus_camera_on_snapshot(STARTUP_SNAPSHOT_PATH)


func _focus_camera_on_snapshot(path: String) -> void:
	if _camera == null:
		return

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return

	var json_text := file.get_as_text()
	var json := JSON.new()
	if json.parse(json_text) != OK:
		return

	var payload := json.data as Dictionary
	if payload.is_empty():
		return

	var points: Array[Vector2] = []
	for component_raw in (payload.get("components", []) as Array):
		if component_raw is Dictionary:
			var component := component_raw as Dictionary
			var p := component.get("position", []) as Array
			if p.size() >= 2:
				points.append(Vector2(float(p[0]), float(p[1])))

	for power_raw in (payload.get("dev_power_nodes", []) as Array):
		if power_raw is Dictionary:
			var power := power_raw as Dictionary
			var p := power.get("position", []) as Array
			if p.size() >= 2:
				points.append(Vector2(float(p[0]), float(p[1])))

	if points.is_empty():
		return

	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for p in points:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)

	var center := Vector2((min_x + max_x) * 0.5, (min_y + max_y) * 0.5)
	var span_x := maxf(120.0, max_x - min_x)
	var span_y := maxf(120.0, max_y - min_y)
	var viewport_size := get_viewport().get_visible_rect().size
	var fit_x := span_x / maxf(1.0, viewport_size.x * 0.80)
	var fit_y := span_y / maxf(1.0, viewport_size.y * 0.80)
	var fit_zoom := maxf(0.8, maxf(fit_x, fit_y))

	_camera.position = center
	_camera.zoom = Vector2.ONE * maxf(menu_camera_zoom, fit_zoom)
