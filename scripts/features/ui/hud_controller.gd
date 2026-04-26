extends CanvasLayer

const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")
const MINIMAP_VIEW_SCRIPT = preload("res://scripts/features/ui/minimap_view.gd")
const HOVER_PICK_RADIUS := 30.0
const TOOLTIP_OFFSET := Vector2(18.0, 18.0)
const OVERLAY_REFRESH_INTERVAL := 0.12
const FEEDBACK_DURATION := 2.4

@onready var _energy_value: Label = $PanelContainer/MarginContainer/Stats/EnergyRow/Value
@onready var _horsepower_value: Label = $PanelContainer/MarginContainer/Stats/HorsepowerRow/Value
@onready var _timer_value: Label = $PanelContainer/MarginContainer/Stats/TimerRow/Value
@onready var _none_button: Button = $HotbarPanel/MarginContainer/Hotbar/NoneButton
@onready var _small_gear_button: Button = $HotbarPanel/MarginContainer/Hotbar/SmallGearButton
@onready var _medium_gear_button: Button = $HotbarPanel/MarginContainer/Hotbar/MediumGearButton
@onready var _large_gear_button: Button = $HotbarPanel/MarginContainer/Hotbar/LargeGearButton
@onready var _shaft_button: Button = $HotbarPanel/MarginContainer/Hotbar/ShaftButton
@onready var _chain_button: Button = $HotbarPanel/MarginContainer/Hotbar/BeltButton
@onready var _delete_button: Button = $HotbarPanel/MarginContainer/Hotbar/DeleteButton
@onready var _flywheel_button: Button = $HotbarPanel/MarginContainer/Hotbar/FlywheelButton
@onready var _clutch_button: Button = $HotbarPanel/MarginContainer/Hotbar/ClutchButton
@onready var _differential_button: Button = $HotbarPanel/MarginContainer/Hotbar/DifferentialButton
@onready var _game_manager: Node = get_node_or_null("../GameManager")
@onready var _placement_controller: Node2D = get_node_or_null("../PlacementController")
@onready var _network_node: Node2D = get_node_or_null("../Network")
@onready var _camera_node: Camera2D = get_node_or_null("../Camera2D")
@onready var _frontier_node: Node = get_node_or_null("../Blockade")
@onready var _components_container: Node2D = get_node_or_null("../Network/Components")
@onready var _engine_node: Node2D = get_node_or_null("../Network/CentralEngine")

const COMPONENT_NONE := PROJECT_PATHS_SCRIPT.COMPONENT_NONE
const COMPONENT_GEAR_SMALL := PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_SMALL
const COMPONENT_GEAR_MEDIUM := PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_MEDIUM
const COMPONENT_GEAR_LARGE := PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_LARGE
const COMPONENT_DELETE := PROJECT_PATHS_SCRIPT.COMPONENT_DELETE
# Removed component types — kept as constants so legacy code branches compile.
const COMPONENT_SHAFT := "shaft"
const COMPONENT_CHAIN := "chain"
const COMPONENT_FLYWHEEL := "flywheel"
const COMPONENT_CLUTCH := "clutch"
const COMPONENT_DIFFERENTIAL := "differential"

@export var overlay_toggle_key: Key = KEY_Q

var _selected_component: String = COMPONENT_NONE
var _tooltip_panel: PanelContainer = null
var _tooltip_title: Label = null
var _tooltip_body: Label = null
var _overlay_panel: PanelContainer = null
var _overlay_label: Label = null
var _hovered_component: Node2D = null
var _overlay_visible: bool = false
var _overlay_refresh_accum: float = 0.0
var _feedback_label: Label = null
var _feedback_timer: float = 0.0
var _layer_indicator_label: Label = null
var _minimap_panel: PanelContainer = null
var _minimap_view: Control = null


func _ready() -> void:
	var game_state := get_node_or_null("/root/GameState")
	if game_state:
		if not game_state.state_changed.is_connected(_on_state_changed):
			game_state.state_changed.connect(_on_state_changed)
		_on_state_changed(game_state.horsepower, game_state.available_torque, game_state.efficiency, game_state.total_score, game_state.lifetime_hp, game_state.reliability_multiplier)

	_none_button.pressed.connect(_on_none_button_pressed)
	_small_gear_button.pressed.connect(_on_small_gear_button_pressed)
	_medium_gear_button.pressed.connect(_on_medium_gear_button_pressed)
	_large_gear_button.pressed.connect(_on_large_gear_button_pressed)
	if _shaft_button:
		_shaft_button.visible = false
		_shaft_button.disabled = true
	if _chain_button:
		_chain_button.visible = false
		_chain_button.disabled = true
	if _flywheel_button:
		_flywheel_button.visible = false
		_flywheel_button.disabled = true
	if _clutch_button:
		_clutch_button.visible = false
		_clutch_button.disabled = true
	if _differential_button:
		_differential_button.visible = false
		_differential_button.disabled = true
	_delete_button.pressed.connect(_on_delete_button_pressed)
	_configure_hotbar_tooltips()
	_build_hover_tooltip()
	_build_network_overlay()
	_build_feedback_toast()
	_build_layer_indicator()
	_build_minimap()

	var signal_bus := get_node_or_null("/root/SignalBus")
	if signal_bus and not signal_bus.network_changed.is_connected(_on_network_changed):
		signal_bus.network_changed.connect(_on_network_changed)
	if signal_bus and signal_bus.has_signal("placement_feedback") and not signal_bus.placement_feedback.is_connected(_on_placement_feedback):
		signal_bus.placement_feedback.connect(_on_placement_feedback)

	_select_component(COMPONENT_NONE)
	_update_network_overlay()


func _process(delta: float) -> void:
	_update_hover_tooltip()
	if _feedback_label != null and _feedback_timer > 0.0:
		_feedback_timer = maxf(0.0, _feedback_timer - delta)
		_feedback_label.visible = _feedback_timer > 0.0

	if not _overlay_visible:
		return

	_overlay_refresh_accum += delta
	if _overlay_refresh_accum < OVERLAY_REFRESH_INTERVAL:
		return
	_overlay_refresh_accum = 0.0
	_update_network_overlay()


func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventKey:
		return
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.ctrl_pressed or key_event.alt_pressed or key_event.meta_pressed:
		return
	if _is_text_input_focused():
		return

	if key_event.keycode == overlay_toggle_key:
		_overlay_visible = not _overlay_visible
		if _overlay_panel:
			_overlay_panel.visible = _overlay_visible
		if _overlay_visible:
			_update_network_overlay()
		return

	if _apply_hotbar_keybind(key_event.keycode):
		get_viewport().set_input_as_handled()


func _on_state_changed(horsepower: float, available_torque: float, efficiency: float, total_score: float, lifetime_hp: float, reliability_multiplier: float) -> void:
	_energy_value.text = "%.1f" % total_score
	_horsepower_value.text = "%.1f" % horsepower
	
	# Format run_time as MM:SS
	var game_state := get_node_or_null("/root/GameState")
	if game_state:
		var seconds := int(game_state.run_time)
		var minutes := seconds / 60
		var secs := seconds % 60
		_timer_value.text = "%d:%02d" % [minutes, secs]
	
	if _overlay_visible:
		_update_network_overlay()


func _on_network_changed() -> void:
	if _overlay_visible:
		_update_network_overlay()


func _on_placement_feedback(message: String) -> void:
	_show_feedback(message)


func _on_none_button_pressed() -> void:
	_select_component(COMPONENT_NONE)


func _on_small_gear_button_pressed() -> void:
	_toggle_component_selection(COMPONENT_GEAR_SMALL)


func _on_medium_gear_button_pressed() -> void:
	_toggle_component_selection(COMPONENT_GEAR_MEDIUM)


func _on_large_gear_button_pressed() -> void:
	_toggle_component_selection(COMPONENT_GEAR_LARGE)


func _on_shaft_button_pressed() -> void:
	_toggle_component_selection(COMPONENT_SHAFT)


func _on_chain_button_pressed() -> void:
	_toggle_component_selection(COMPONENT_CHAIN)


func _on_delete_button_pressed() -> void:
	_toggle_component_selection(COMPONENT_DELETE)


func _on_flywheel_button_pressed() -> void:
	_toggle_component_selection(COMPONENT_FLYWHEEL)


func _on_clutch_button_pressed() -> void:
	_toggle_component_selection(COMPONENT_CLUTCH)


func _on_differential_button_pressed() -> void:
	_toggle_component_selection(COMPONENT_DIFFERENTIAL)


func _configure_hotbar_tooltips() -> void:
	_set_button_tooltip(
		_none_button,
		"Select / Inspect",
		[
			"Mode: No placement",
			"Use: Hover parts to inspect live torque, RPM, friction, and state",
			"Efficiency: Aggregate drivetrain quality (component + zone weighted)"
		]
	)
	_set_button_tooltip(
		_small_gear_button,
		"Small Gear",
		[
			"Role: Ratio stage (compact)",
			"Torque / RPM: Increases RPM when driving larger gears; trades torque",
			"Efficiency: High component efficiency; boosts mixed-gear bonus when diversified",
			"Best for: Speed-focused branches and fine ratio tuning"
		]
	)
	_set_button_tooltip(
		_medium_gear_button,
		"Medium Gear",
		[
			"Role: Ratio stage (balanced)",
			"Torque / RPM: Moderate conversion between torque and speed",
			"Efficiency: Balanced component efficiency; stable core drivetrain element",
			"Best for: General routing and stable mixed trains"
		]
	)
	_set_button_tooltip(
		_large_gear_button,
		"Large Gear",
		[
			"Role: Ratio stage (high leverage)",
			"Torque / RPM: Increases torque when driven by smaller gears; lowers RPM",
			"Efficiency: Slightly lower component efficiency; optimized for torque-heavy paths",
			"Best for: Heavy-load segments and low-speed torque delivery"
		]
	)
	if _shaft_button:
		_shaft_button.tooltip_text = ""
	if _chain_button:
		_set_button_tooltip(
			_chain_button,
			"Chain",
			[
				"Role: Flexible bridge between endpoints",
				"Torque / RPM: Ratio follows connected sprocket/gear sizes",
				"Efficiency: Higher loss and jam pressure under load/zones",
				"Best for: Crossing gaps and obstacle routing"
			]
		)
	_set_button_tooltip(
		_flywheel_button,
		"Flywheel",
		[
			"Role: Inertia buffer",
			"Torque / RPM: Stores rotational energy to smooth short torque drops",
			"Efficiency: Indirectly improves sustained output by reducing jam cascades",
			"Best for: Unstable branches and zone-driven interruption recovery"
		]
	)
	_set_button_tooltip(
		_clutch_button,
		"Clutch",
		[
			"Role: On/off drivetrain gate",
			"Torque / RPM: Engaged passes flow; disengaged isolates branch",
			"Efficiency: Avoids bad-path losses when branch is intentionally cut",
			"Best for: Bypass control and selective source contribution"
		]
	)
	_set_button_tooltip(
		_differential_button,
		"Differential",
		[
			"Role: Merge/split drivetrain branches",
			"Torque / RPM: Combines multiple inputs into shared output path",
			"Efficiency: Applies merge efficiency before downstream losses",
			"Best for: Multi-source routing near engine trunk"
		]
	)
	_set_button_tooltip(
		_delete_button,
		"Delete",
		[
			"Mode: Remove nearest component",
			"Use: Trim friction-heavy or jam-prone segments quickly",
			"Efficiency: Can improve total output by shortening bad paths"
		]
	)


func _set_button_tooltip(button: Button, title: String, lines: Array) -> void:
	if button == null:
		return
	var text_lines: Array = [title]
	text_lines.append_array(lines)
	button.tooltip_text = _join_parts(text_lines, "\n")


func _toggle_component_selection(component_id: String) -> void:
	if component_id == COMPONENT_NONE:
		_select_component(COMPONENT_NONE)
		return

	if _selected_component == component_id:
		_select_component(COMPONENT_NONE)
		return

	if component_id == COMPONENT_CHAIN:
		print("CHAIN MODE ACTIVATED: Click to select first gear, then click to select second gear (max 480 units apart)")
	_select_component(component_id)


func _apply_hotbar_keybind(keycode: Key) -> bool:
	match keycode:
		KEY_1:
			_toggle_component_selection(COMPONENT_GEAR_SMALL)
			return true
		KEY_2:
			_toggle_component_selection(COMPONENT_GEAR_MEDIUM)
			return true
		KEY_3:
			_toggle_component_selection(COMPONENT_GEAR_LARGE)
			return true
		KEY_4:
			_toggle_component_selection(COMPONENT_CHAIN)
			return true
		KEY_5:
			_toggle_component_selection(COMPONENT_FLYWHEEL)
			return true
		KEY_6:
			_toggle_component_selection(COMPONENT_CLUTCH)
			return true
		KEY_7:
			_toggle_component_selection(COMPONENT_DIFFERENTIAL)
			return true
		KEY_X:
			_toggle_component_selection(COMPONENT_DELETE)
			return true
		_:
			return false


func _is_text_input_focused() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner == null:
		return false
	return focus_owner is LineEdit or focus_owner is TextEdit


func _select_component(component_id: String) -> void:
	_selected_component = component_id
	_none_button.button_pressed = component_id == COMPONENT_NONE
	_small_gear_button.button_pressed = component_id == COMPONENT_GEAR_SMALL
	_medium_gear_button.button_pressed = component_id == COMPONENT_GEAR_MEDIUM
	_large_gear_button.button_pressed = component_id == COMPONENT_GEAR_LARGE
	_shaft_button.button_pressed = component_id == COMPONENT_SHAFT
	if _chain_button:
		_chain_button.button_pressed = component_id == COMPONENT_CHAIN
	_delete_button.button_pressed = component_id == COMPONENT_DELETE
	if _flywheel_button:
		_flywheel_button.button_pressed = component_id == COMPONENT_FLYWHEEL
	if _clutch_button:
		_clutch_button.button_pressed = component_id == COMPONENT_CLUTCH
	if _differential_button:
		_differential_button.button_pressed = component_id == COMPONENT_DIFFERENTIAL

	var signal_bus := get_node_or_null("/root/SignalBus")
	if signal_bus:
		signal_bus.component_selected.emit(component_id)


func _build_hover_tooltip() -> void:
	_tooltip_panel = PanelContainer.new()
	_tooltip_panel.visible = false
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.custom_minimum_size = Vector2(230.0, 0.0)
	add_child(_tooltip_panel)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	_tooltip_panel.add_child(margin)

	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 4)
	margin.add_child(stack)

	_tooltip_title = Label.new()
	_tooltip_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	stack.add_child(_tooltip_title)

	_tooltip_body = Label.new()
	_tooltip_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tooltip_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_tooltip_body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	stack.add_child(_tooltip_body)


func _build_network_overlay() -> void:
	_overlay_panel = PanelContainer.new()
	_overlay_panel.visible = false
	_overlay_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_panel.anchor_left = 0.0
	_overlay_panel.anchor_top = 0.0
	_overlay_panel.anchor_right = 0.0
	_overlay_panel.anchor_bottom = 0.0
	_overlay_panel.offset_left = 16.0
	_overlay_panel.offset_top = 16.0
	_overlay_panel.custom_minimum_size = Vector2(280.0, 0.0)
	add_child(_overlay_panel)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	_overlay_panel.add_child(margin)

	_overlay_label = Label.new()
	_overlay_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_overlay_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	margin.add_child(_overlay_label)


func _build_feedback_toast() -> void:
	_feedback_label = Label.new()
	_feedback_label.visible = false
	_feedback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback_label.anchor_left = 0.5
	_feedback_label.anchor_right = 0.5
	_feedback_label.anchor_top = 0.0
	_feedback_label.anchor_bottom = 0.0
	_feedback_label.offset_left = -220.0
	_feedback_label.offset_right = 220.0
	_feedback_label.offset_top = 18.0
	_feedback_label.offset_bottom = 74.0
	_feedback_label.modulate = Color(1.0, 0.86, 0.62, 1.0)
	add_child(_feedback_label)


func _build_layer_indicator() -> void:
	_layer_indicator_label = Label.new()
	_layer_indicator_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer_indicator_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_layer_indicator_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_layer_indicator_label.anchor_left = 0.0
	_layer_indicator_label.anchor_right = 0.0
	_layer_indicator_label.anchor_top = 0.0
	_layer_indicator_label.anchor_bottom = 0.0
	_layer_indicator_label.offset_left = 20.0
	_layer_indicator_label.offset_top = 18.0
	_layer_indicator_label.offset_right = 220.0
	_layer_indicator_label.offset_bottom = 42.0
	_layer_indicator_label.modulate = Color(0.86, 0.92, 1.0, 0.92)
	add_child(_layer_indicator_label)
	_update_layer_indicator()


func _build_minimap() -> void:
	_minimap_panel = PanelContainer.new()
	_minimap_panel.anchor_left = 1.0
	_minimap_panel.anchor_right = 1.0
	_minimap_panel.anchor_top = 1.0
	_minimap_panel.anchor_bottom = 1.0
	_minimap_panel.offset_left = -272.0
	_minimap_panel.offset_top = -262.0
	_minimap_panel.offset_right = -18.0
	_minimap_panel.offset_bottom = -84.0
	_minimap_panel.custom_minimum_size = Vector2(240.0, 160.0)
	add_child(_minimap_panel)

	var margin := MarginContainer.new()
	margin.layout_mode = 2
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_minimap_panel.add_child(margin)

	var minimap_title := Label.new()
	minimap_title.text = "Minimap"
	minimap_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	minimap_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	minimap_title.modulate = Color(0.9, 0.94, 1.0, 0.95)

	var stack := VBoxContainer.new()
	stack.layout_mode = 2
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 6)
	margin.add_child(stack)
	stack.add_child(minimap_title)

	_minimap_view = MINIMAP_VIEW_SCRIPT.new()
	_minimap_view.custom_minimum_size = Vector2(220.0, 130.0)
	_minimap_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_minimap_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(_minimap_view)

	if _minimap_view.has_method("set_context"):
		_minimap_view.call(
			"set_context",
			_camera_node,
			_frontier_node,
			_network_node,
			_components_container,
			_engine_node
		)


func _update_layer_indicator() -> void:
	if _layer_indicator_label == null:
		return
	_layer_indicator_label.text = "Mesh"


func _show_feedback(message: String) -> void:
	if _feedback_label == null:
		return
	if message.is_empty():
		_feedback_label.visible = false
		_feedback_timer = 0.0
		return
	_feedback_label.text = message
	_feedback_label.visible = true
	_feedback_timer = FEEDBACK_DURATION


func _update_hover_tooltip() -> void:
	if _tooltip_panel == null:
		return

	var hovered_control := get_viewport().gui_get_hovered_control()
	if hovered_control != null:
		_set_tooltip_visible(false)
		return

	var world_pos := _get_world_mouse_position()
	var hovered := _find_hover_component(world_pos)
	_hovered_component = hovered
	if hovered == null:
		_set_tooltip_visible(false)
		return

	var snapshot := _get_component_snapshot(hovered)
	_tooltip_title.text = _get_component_display_name(hovered, snapshot)
	_tooltip_body.text = _build_tooltip_text(hovered, snapshot)
	var panel_size := _tooltip_panel.get_combined_minimum_size()
	var mouse_pos := get_viewport().get_mouse_position()
	var visible_rect := get_viewport().get_visible_rect()
	var pos := mouse_pos + TOOLTIP_OFFSET
	pos.x = minf(pos.x, visible_rect.size.x - panel_size.x - 12.0)
	pos.y = minf(pos.y, visible_rect.size.y - panel_size.y - 12.0)
	_tooltip_panel.position = pos
	_set_tooltip_visible(true)


func _update_network_overlay() -> void:
	if _overlay_label == null:
		return

	var snapshot := _get_overlay_snapshot()
	var lines: Array = []
	lines.append("Network Overlay [%s]" % OS.get_keycode_string(overlay_toggle_key))
	if snapshot.is_empty() or not bool(snapshot.get("connected", false)):
		lines.append("No engine-connected route")
		lines.append("Hover any part for local stats")
		_overlay_label.text = _join_parts(lines, "\n")
		return

	lines.append("HP: %.1f" % float(snapshot.get("horsepower", 0.0)))
	var hp_target_hint := _get_hp_target_hint(
		float(snapshot.get("horsepower", 0.0)),
		int(snapshot.get("connected_source_count", 0))
	)
	if not hp_target_hint.is_empty():
		lines.append("Target Band: %s" % hp_target_hint)
	lines.append("Net Torque (HUD): %.1f" % maxf(float(snapshot.get("net_torque", 0.0)), 0.0))
	lines.append("Engine Input Torque: %.1f" % float(snapshot.get("delivered_torque", 0.0)))
	lines.append("Efficiency: %.1f%%" % (float(snapshot.get("efficiency", 0.0)) * 100.0))
	lines.append("Friction Load: %.1f" % float(snapshot.get("friction_load", 0.0)))
	lines.append(
		"Sources: %d/%d  Reachable: %d" % [
			int(snapshot.get("connected_source_count", 0)),
			int(snapshot.get("total_source_count", 0)),
			int(snapshot.get("reachable_count", 0))
		]
	)
	lines.append("Underpowered: %s" % ("Yes" if bool(snapshot.get("underpowered", false)) else "No"))
	var bottleneck_name := str(snapshot.get("bottleneck_name", ""))
	if not bottleneck_name.is_empty():
		lines.append("Bottleneck: %s (%.1f loss)" % [bottleneck_name, float(snapshot.get("bottleneck_loss", 0.0))])
	lines.append("Hold Shift while hovering for raw values")
	_overlay_label.text = _join_parts(lines, "\n")


func _get_hp_target_hint(horsepower: float, connected_source_count: int) -> String:
	if connected_source_count <= 0:
		return ""

	if connected_source_count <= 1:
		if horsepower < PROJECT_PATHS_SCRIPT.EARLY_ROUTE_HP_TARGET_MIN:
			return "Below first-route target"
		if horsepower > PROJECT_PATHS_SCRIPT.EARLY_ROUTE_HP_TARGET_MAX:
			return "Above first-route target"
		return "Within first-route target"

	if connected_source_count <= 2:
		if horsepower < PROJECT_PATHS_SCRIPT.EARLY_OPTIMIZED_HP_TARGET_MIN:
			return "Below early-optimized target"
		if horsepower > PROJECT_PATHS_SCRIPT.EARLY_OPTIMIZED_HP_TARGET_MAX:
			return "Above early-optimized target"
		return "Within early-optimized target"

	return ""


func _find_hover_component(world_pos: Vector2) -> Node2D:
	if _placement_controller and _placement_controller.has_method("find_component_at"):
		var hovered_component := _placement_controller.call("find_component_at", world_pos, HOVER_PICK_RADIUS) as Node2D
		if hovered_component != null:
			return hovered_component

	if _network_node == null:
		return null

	var nearest: Node2D = null
	var nearest_distance := HOVER_PICK_RADIUS
	for child in _network_node.get_children():
		var node := child as Node2D
		if node == null:
			continue
		if node.name == "Components" or node.name == "Connections":
			continue
		if not (node.name == "CentralEngine" or node.name.begins_with("Power")):
			continue
		var pick_radius := maxf(20.0, _get_node_radius(node) + 8.0)
		var distance := node.global_position.distance_to(world_pos)
		if distance <= pick_radius and distance <= nearest_distance:
			nearest = node
			nearest_distance = distance

	return nearest


func _get_component_snapshot(component: Node2D) -> Dictionary:
	if component == null:
		return {}
	if _game_manager and _game_manager.has_method("get_component_ui_snapshot"):
		var snapshot := _game_manager.call("get_component_ui_snapshot", component) as Dictionary
		if snapshot != null:
			return snapshot
	return {}


func _get_overlay_snapshot() -> Dictionary:
	if _game_manager and _game_manager.has_method("get_ui_overlay_snapshot"):
		var snapshot := _game_manager.call("get_ui_overlay_snapshot") as Dictionary
		if snapshot != null:
			return snapshot
	return {}


func _build_tooltip_text(component: Node2D, snapshot: Dictionary) -> String:
	var lines: Array = []
	var badges := _get_component_badges(component, snapshot)
	if not badges.is_empty():
		lines.append("State: %s" % _join_parts(badges, " | "))

	var rpm := _get_component_rpm(component)
	var is_node := component.name == "CentralEngine" or component.name.begins_with("Power")
	if rpm > 0.01 or is_node:
		lines.append("RPM: %.0f" % rpm)

	var torque := _get_component_torque(component, snapshot)
	if torque >= 0.0:
		lines.append("Torque: %.1f" % torque)

	var friction := float(snapshot.get("friction", 0.0))
	if friction > 0.0:
		lines.append("Friction: %.1f" % friction)

	var load_ratio := float(snapshot.get("load_ratio", 0.0))
	if load_ratio > 0.0:
		lines.append("Load: %.0f%%" % (load_ratio * 100.0))

	_append_type_specific_lines(lines, component, snapshot)

	var zone_type := str(snapshot.get("zone_type", ""))
	if not zone_type.is_empty():
		lines.append("Zone: %s (%.0f%%)" % [_format_zone_type(zone_type), float(snapshot.get("zone_intensity", 0.0)) * 100.0])

	if Input.is_key_pressed(KEY_SHIFT):
		_append_raw_detail_lines(lines, component, snapshot)

	return _join_parts(lines, "\n")


func _append_type_specific_lines(lines: Array, component: Node2D, snapshot: Dictionary) -> void:
	var component_type := _get_component_type(component, snapshot)
	match component_type:
		COMPONENT_GEAR_SMALL, COMPONENT_GEAR_MEDIUM, COMPONENT_GEAR_LARGE:
			var tooth_count := int(snapshot.get("tooth_count", 0))
			if tooth_count > 0:
				lines.append("Teeth: %d" % tooth_count)
			var pulley_mode_value: Variant = component.get("_pulley_mode")
			if pulley_mode_value != null and bool(pulley_mode_value):
				lines.append("Interface: Sprocket")
		COMPONENT_SHAFT:
			lines.append("Span Length: %.0f" % _get_connector_length(component))
		COMPONENT_CHAIN:
			lines.append("Span Length: %.0f" % _get_connector_length(component))
			lines.append("Jam: %.0f%%" % (float(component.get("jam_amount")) * 100.0))
		COMPONENT_FLYWHEEL:
			if component.has_method("get_charge_ratio"):
				lines.append("Charge: %.0f%%" % (float(component.call("get_charge_ratio")) * 100.0))
		COMPONENT_CLUTCH:
			lines.append("Clutch: %s" % ("Engaged" if bool(component.get("is_engaged")) else "Freewheel"))
		COMPONENT_DIFFERENTIAL:
			lines.append("Merge Eff.: %.0f%%" % (float(component.get("merge_efficiency")) * 100.0))
		_:
			if component.name == "CentralEngine":
				lines.append("Role: Scoring sink")
				var operating_state := str(snapshot.get("engine_operating_state", ""))
				if not operating_state.is_empty():
					lines.append("Operating State: %s" % _format_source_state_label(operating_state))
				var input_hp := float(snapshot.get("engine_input_horsepower", -1.0))
				if input_hp >= 0.0:
					lines.append("Input HP: %.1f" % input_hp)
			elif component.name.begins_with("Power"):
				var rated_output: Variant = component.get("rated_torque_output")
				if rated_output != null:
					lines.append("Rated Torque: %.1f" % float(rated_output))
				var source_status := str(snapshot.get("source_status", ""))
				if not source_status.is_empty():
					lines.append("Source State: %s" % _format_source_state_label(source_status))
				var source_rpm := float(snapshot.get("source_rpm", -1.0))
				var source_no_load := float(snapshot.get("source_no_load_rpm", -1.0))
				if source_rpm >= 0.0 and source_no_load > 0.0:
					lines.append("Source RPM: %.0f / %.0f" % [source_rpm, source_no_load])
				var remaining_budget := float(snapshot.get("source_remaining_budget", -1.0))
				if remaining_budget >= 0.0:
					lines.append("Remaining Budget: %.1f" % remaining_budget)


func _append_raw_detail_lines(lines: Array, component: Node2D, snapshot: Dictionary) -> void:
	var angular_velocity: Variant = component.get("angular_velocity")
	if angular_velocity != null:
		lines.append("Angular: %.3f" % float(angular_velocity))
	var outer_radius := float(snapshot.get("outer_radius", 0.0))
	if outer_radius > 0.0:
		lines.append("Outer Radius: %.1f" % outer_radius)
	if component.has_method("get_charge_ratio"):
		lines.append("Buffer Ratio: %.3f" % float(component.call("get_charge_ratio")))
	var condition_state: Variant = component.get("_condition_state")
	if condition_state != null:
		lines.append("Condition: %s" % _format_condition_state(int(condition_state)))
	var heat: Variant = component.get("_condition_heat")
	if heat != null:
		lines.append("Heat: %.0f%%" % (float(heat) * 100.0))
	var contamination: Variant = component.get("_condition_contamination")
	if contamination != null:
		lines.append("Dust: %.0f%%" % (float(contamination) * 100.0))


func _get_component_badges(component: Node2D, snapshot: Dictionary) -> Array:
	var badges: Array = []
	var connected := bool(snapshot.get("connected", false))
	if component.name == "CentralEngine" or component.name.begins_with("Power"):
		var anchor_connected: Variant = component.get("_is_connected_to_network")
		if anchor_connected != null:
			connected = bool(anchor_connected)
	badges.append("Connected" if connected else "Disconnected")

	var route_active: Variant = component.get("_is_on_engine_route")
	if route_active != null and bool(route_active):
		badges.append("Engine Route")
	if component.name.begins_with("Power"):
		var source_status := str(snapshot.get("source_status", ""))
		if not source_status.is_empty():
			badges.append(_format_source_state_label(source_status))
	if component.name == "CentralEngine":
		var engine_state := str(snapshot.get("engine_operating_state", ""))
		if not engine_state.is_empty():
			badges.append(_format_source_state_label(engine_state))
	if bool(snapshot.get("bottleneck", false)):
		badges.append("Bottleneck")
	var stalled: Variant = component.get("_is_stalled")
	if stalled != null and bool(stalled):
		badges.append("Underpowered")
	var underpowered: Variant = component.get("_is_underpowered")
	if underpowered != null and bool(underpowered):
		badges.append("Underpowered")
	var conflict: Variant = component.get("_has_direction_conflict")
	if conflict == null:
		conflict = component.get("_is_direction_conflict")
	if conflict != null and bool(conflict):
		badges.append("Conflict")
	var condition_state: Variant = component.get("_condition_state")
	if condition_state != null:
		match int(condition_state):
			3:
				badges.append("Jam Risk")
			4:
				badges.append("Jammed")
	var pulley_mode_value: Variant = component.get("_pulley_mode")
	if pulley_mode_value != null and bool(pulley_mode_value):
		badges.append("Sprocket")
	return badges


func _get_component_display_name(component: Node2D, snapshot: Dictionary) -> String:
	var component_type := _get_component_type(component, snapshot)
	match component_type:
		COMPONENT_GEAR_SMALL:
			return "Small Gear"
		COMPONENT_GEAR_MEDIUM:
			return "Medium Gear"
		COMPONENT_GEAR_LARGE:
			return "Large Gear"
		COMPONENT_SHAFT:
			return "Shaft"
		COMPONENT_CHAIN:
			return "Chain"
		COMPONENT_FLYWHEEL:
			return "Flywheel"
		COMPONENT_CLUTCH:
			return "Clutch"
		COMPONENT_DIFFERENTIAL:
			return "Differential"
		_:
			if component.name == "CentralEngine":
				return "Central Engine"
			if component.name.begins_with("Power"):
				return component.name
			return component.name


func _get_component_type(component: Node2D, snapshot: Dictionary) -> String:
	var snapshot_type := str(snapshot.get("component_type", ""))
	if not snapshot_type.is_empty():
		return snapshot_type
	return str(component.get_meta("component_type", ""))


func _format_source_state_label(state: String) -> String:
	match state:
		"in_band":
			return "In Band"
		"near_limit":
			return "Near Limit"
		"braking":
			return "Braking"
		"bogging":
			return "Bogging"
		"overspeed":
			return "Overspeed"
		_:
			return state.capitalize()


func _get_component_rpm(component: Node2D) -> float:
	if component == null:
		return 0.0
	var component_type := str(component.get_meta("component_type", ""))
	if component_type == COMPONENT_CHAIN:
		return _get_average_endpoint_rpm(component.get("pulley_a") as Node2D, component.get("pulley_b") as Node2D)
	if component_type == COMPONENT_SHAFT:
		return _get_average_endpoint_rpm(component.get("gear_a") as Node2D, component.get("gear_b") as Node2D)
	if component.has_method("get_angular_velocity"):
		return _to_rpm(float(component.call("get_angular_velocity")))
	var angular_velocity: Variant = component.get("angular_velocity")
	if angular_velocity == null:
		return 0.0
	return _to_rpm(float(angular_velocity))


func _get_component_torque(component: Node2D, snapshot: Dictionary = {}) -> float:
	if component == null:
		return -1.0
	if not snapshot.is_empty() and snapshot.has("torque"):
		return float(snapshot.get("torque", 0.0))
	var torque: Variant = component.get("torque")
	if torque == null:
		return -1.0
	return float(torque)


func _get_average_endpoint_rpm(a: Node2D, b: Node2D) -> float:
	var values: Array = []
	if a != null:
		var angular_a: Variant = a.get("angular_velocity")
		if angular_a != null:
			values.append(_to_rpm(float(angular_a)))
	if b != null:
		var angular_b: Variant = b.get("angular_velocity")
		if angular_b != null:
			values.append(_to_rpm(float(angular_b)))
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value_raw in values:
		total += float(value_raw)
	return total / float(values.size())


func _get_connector_length(component: Node2D) -> float:
	if component == null:
		return 0.0
	var component_type := str(component.get_meta("component_type", ""))
	if component_type == COMPONENT_CHAIN:
		var pulley_a := component.get("pulley_a") as Node2D
		var pulley_b := component.get("pulley_b") as Node2D
		if pulley_a != null and pulley_b != null:
			return pulley_a.global_position.distance_to(pulley_b.global_position)
	elif component_type == COMPONENT_SHAFT:
		var gear_a := component.get("gear_a") as Node2D
		var gear_b := component.get("gear_b") as Node2D
		if gear_a != null and gear_b != null:
			return gear_a.global_position.distance_to(gear_b.global_position)
	return 0.0


func _get_node_radius(node: Node2D) -> float:
	if node == null:
		return PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS
	var visual: Node = node.get_node_or_null("Visual")
	if visual == null:
		return PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS
	var outer_radius: Variant = visual.get("outer_radius")
	if outer_radius == null:
		return PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS
	return float(outer_radius)


func _get_world_mouse_position() -> Vector2:
	if _placement_controller != null:
		return _placement_controller.get_global_mouse_position()
	return Vector2.ZERO


func _to_rpm(angular_speed: float) -> float:
	return absf(angular_speed) * (60.0 / TAU)


func _join_parts(parts: Array, separator: String) -> String:
	var text := ""
	for i in range(parts.size()):
		text += str(parts[i])
		if i < parts.size() - 1:
			text += separator
	return text


func _format_condition_state(state: int) -> String:
	match state:
		0:
			return "Normal"
		1:
			return "Strained"
		2:
			return "Unstable"
		3:
			return "Risk"
		4:
			return "Jammed"
		_:
			return "Unknown"


func _format_zone_type(zone_type: String) -> String:
	match zone_type:
		"heat":
			return "Heat"
		"cold":
			return "Cold"
		"dusty":
			return "Dusty"
		_:
			return zone_type.capitalize()


func _set_tooltip_visible(visible: bool) -> void:
	if _tooltip_panel != null:
		_tooltip_panel.visible = visible
