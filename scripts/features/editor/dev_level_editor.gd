extends Node
class_name DevLevelEditor

const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")
const GEAR_SCENE_PATH := "res://scenes/components/Gear.tscn"
const ANCHOR_ROTOR_SCRIPT_PATH := "res://scripts/components/anchor_rotor.gd"
const GEAR_VISUAL_SCRIPT_PATH := "res://scripts/components/gear_visual.gd"
const ZONE_EFFECT_SCRIPT_PATH := "res://scripts/features/zones/zone_effect.gd"
const BARRIER_ZONE_SCRIPT_PATH := "res://scripts/features/barriers/barrier_zone.gd"
const SAVE_DIR := "user://dev_levels"
const SAVE_PATH := "user://dev_levels/level_dev.json"

const TOOL_NONE := "none"
const TOOL_POWER_NODE := "power_node"
const TOOL_ZONE_HEAT := "zone_heat"
const TOOL_ZONE_COLD := "zone_cold"
const TOOL_BARRIER := "barrier"
const TOOL_DELETE_DEV := "delete_dev"

const SAVE_VERSION := 2

@export var components_container_path: NodePath = NodePath("../Network/Components")
@export var network_node_path: NodePath = NodePath("../Network")
@export var zones_node_path: NodePath = NodePath("../Zones")
@export var barriers_node_path: NodePath = NodePath("../Barriers")
@export var blockade_node_path: NodePath = NodePath("../Blockade")
@export var menu_toggle_hotkey: Key = KEY_F5
@export var save_hotkey: Key = KEY_F6
@export var load_hotkey: Key = KEY_F7
@export var clear_hotkey: Key = KEY_F8

@onready var _components_container: Node2D = get_node_or_null(components_container_path)
@onready var _network_node: Node2D = get_node_or_null(network_node_path)
@onready var _zones_node: Node2D = get_node_or_null(zones_node_path)
@onready var _barriers_node: Node2D = get_node_or_null(barriers_node_path)
@onready var _blockade_node: Node = get_node_or_null(blockade_node_path)
@onready var _signal_bus: Node = get_node_or_null("/root/SignalBus")

@export var small_gear_scene: PackedScene
@export var medium_gear_scene: PackedScene
@export var large_gear_scene: PackedScene

var _active_tool: String = TOOL_NONE
var _menu_visible: bool = false
var _menu_layer: CanvasLayer = null
var _menu_root: Control = null
var _tool_status_label: Label = null

func _ready() -> void:
	_build_menu()
	_set_active_tool(TOOL_NONE)
	if _menu_root:
		_menu_root.visible = _menu_visible
	print("DevLevelEditor hotkeys: F5=menu F6=save F7=load F8=clear")


func start_new_run(seed: int = -1) -> void:
	if _blockade_node != null and _blockade_node.has_method("reset_frontier"):
		_blockade_node.call("reset_frontier")
	await generate_procedural_map(-1, -1, seed)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event and mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if _active_tool != TOOL_NONE and not _is_pointer_over_ui():
				_place_with_active_tool(_get_mouse_world_position())
				get_viewport().set_input_as_handled()
			return

	if not event is InputEventKey:
		return

	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return

	if key_event.keycode == menu_toggle_hotkey:
		_menu_visible = not _menu_visible
		if _menu_root:
			_menu_root.visible = _menu_visible
		return

	if key_event.keycode == save_hotkey:
		save_level()
		return
	if key_event.keycode == load_hotkey:
		load_level()
		return
	if key_event.keycode == clear_hotkey:
		clear_level()
		return

	if key_event.keycode == KEY_ESCAPE:
		_set_active_tool(TOOL_NONE)
		return


func save_level() -> void:
	if _components_container == null:
		push_warning("DevLevelEditor: components container not found")
		return

	var payload := _serialize_components()
	var dir_result := DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	if dir_result != OK and dir_result != ERR_ALREADY_EXISTS:
		push_warning("DevLevelEditor: failed to create save dir (%s)" % [dir_result])
		return

	var json_text := JSON.stringify(payload, "\t")
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("DevLevelEditor: failed to open save file")
		return

	file.store_string(json_text)
	print("DevLevelEditor: saved %s components and %s power nodes to %s" % [
		int(payload.get("component_count", 0)),
		int((payload.get("dev_power_nodes", []) as Array).size()),
		SAVE_PATH
	])


func load_level() -> void:
	if _components_container == null:
		push_warning("DevLevelEditor: components container not found")
		return

	if not FileAccess.file_exists(SAVE_PATH):
		push_warning("DevLevelEditor: no saved level found at %s" % [SAVE_PATH])
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("DevLevelEditor: failed to read save file")
		return

	var json_text := file.get_as_text()
	var json := JSON.new()
	var parse_result := json.parse(json_text)
	if parse_result != OK:
		push_warning("DevLevelEditor: invalid save JSON")
		return

	var payload := json.data as Dictionary
	if payload.is_empty():
		push_warning("DevLevelEditor: save payload is empty")
		return

	_apply_serialized_level(payload)
	print("DevLevelEditor: loaded level from %s" % [SAVE_PATH])


func clear_level() -> void:
	if _components_container == null:
		return

	for child in _components_container.get_children():
		child.queue_free()
	_clear_dev_world_nodes()
	if _blockade_node != null and _blockade_node.has_method("reset_frontier"):
		_blockade_node.call("reset_frontier")
	await get_tree().process_frame
	_notify_layout_changed()
	print("DevLevelEditor: cleared placed components")


func generate_procedural_map(node_count: int = -1, zone_count: int = -1, seed: int = -1) -> void:
	# Clear existing dev-placed network nodes and world objects.
	_clear_dev_world_nodes()
	if _components_container != null:
		for child in _components_container.get_children():
			child.queue_free()
	if _network_node != null:
		for child in _network_node.get_children():
			if child.has_meta("dev_created"):
				child.queue_free()

	# Wait one frame so queue_free'd nodes are removed before we place new ones.
	await get_tree().process_frame

	var rng := RandomNumberGenerator.new()
	var actual_seed := seed if seed >= 0 else PROJECT_PATHS_SCRIPT.DEFAULT_RUN_SEED
	if actual_seed >= 0:
		rng.seed = actual_seed
	else:
		rng.randomize()

	var dev_apex_raise := maxf(PROJECT_PATHS_SCRIPT.DEV_MAP_CONE_APEX_RAISE, 0.0)
	var apex := Vector2(
		PROJECT_PATHS_SCRIPT.VIEWPORT_CENTER_X,
		PROJECT_PATHS_SCRIPT.ENGINE_WORLD_Y + PROJECT_PATHS_SCRIPT.FRONTIER_CONE_APEX_Y_OFFSET - dev_apex_raise
	)
	var half_angle := deg_to_rad(PROJECT_PATHS_SCRIPT.FRONTIER_CONE_HALF_ANGLE_DEGREES)
	var requested_node_count := node_count
	if requested_node_count <= 0:
		requested_node_count = PROJECT_PATHS_SCRIPT.DEV_MAP_DEFAULT_NODE_COUNT
	var total_nodes := maxi(requested_node_count, 1)
	var start_radius := maxf(PROJECT_PATHS_SCRIPT.DEV_MAP_NODE_START_RADIUS, 24.0)
	var radius_budget := maxf(PROJECT_PATHS_SCRIPT.DEV_MAP_NODE_RADIUS_BUDGET, 200.0)
	var max_radius := start_radius + radius_budget
	var node_spacing := maxf(PROJECT_PATHS_SCRIPT.DEV_MAP_NODE_SPACING, 24.0)
	var row_spacing := maxf(PROJECT_PATHS_SCRIPT.DEV_MAP_NODE_ROW_SPACING, 24.0)
	var radial_jitter := clampf(PROJECT_PATHS_SCRIPT.DEV_MAP_NODE_RADIAL_JITTER, 0.0, row_spacing * 0.45)
	var angle_jitter := deg_to_rad(clampf(PROJECT_PATHS_SCRIPT.DEV_MAP_NODE_ANGLE_JITTER_DEGREES, 0.0, 12.0))
	var min_separation := node_spacing * clampf(PROJECT_PATHS_SCRIPT.DEV_MAP_NODE_MIN_SEPARATION_FACTOR, 0.4, 1.0)
	var world_max_radius := maxf(1200.0, PROJECT_PATHS_SCRIPT.WORLD_VERTICAL_EXTENT - 220.0)
	max_radius = minf(max_radius, world_max_radius)

	var placed_positions: Array[Vector2] = []
	var placed_power_nodes: Array[Node2D] = []
	var placed_nodes := 0
	var row_radius := start_radius
	while placed_nodes < total_nodes and row_radius <= max_radius:
		var arc_length := maxf((half_angle * 2.0) * row_radius, node_spacing)
		var slot_count := maxi(1, int(floor(arc_length / node_spacing)) + 1)
		var angle_step := 0.0
		if slot_count > 1:
			angle_step = (half_angle * 2.0) / float(slot_count - 1)

		for slot_index in range(slot_count):
			if placed_nodes >= total_nodes:
				break

			var slot_angle := 0.0
			if slot_count > 1:
				slot_angle = -half_angle + (angle_step * float(slot_index))
			slot_angle += rng.randf_range(-angle_jitter, angle_jitter)
			slot_angle = clampf(slot_angle, -half_angle, half_angle)

			var slot_radius := row_radius + rng.randf_range(-radial_jitter, radial_jitter)
			slot_radius = clampf(slot_radius, start_radius, max_radius)
			var world_pos := apex + Vector2(sin(slot_angle), -cos(slot_angle)) * slot_radius

			if _is_too_close_to_positions(world_pos, placed_positions, min_separation):
				continue

			var overrides := _pick_procedural_power_overrides(rng)
			if placed_nodes == 0:
				overrides = _build_power_overrides_from_radius(PROJECT_PATHS_SCRIPT.POWER_NODE_TIER_4_RADIUS)
			var created_node := _create_power_node(world_pos, overrides)
			if created_node != null:
				placed_power_nodes.append(created_node)
			placed_positions.append(world_pos)
			placed_nodes += 1
		row_radius += row_spacing

	_upgrade_some_nodes_to_giant(placed_power_nodes, rng)

	# Scatter environmental zones in two bands: a few in 20-40%, then the rest above 40%.
	var requested_zone_count := zone_count
	if requested_zone_count <= 0:
		requested_zone_count = PROJECT_PATHS_SCRIPT.DEV_MAP_DEFAULT_ZONE_COUNT
	var zone_types := ["heat", "cold"]
	var zone_max_radius := minf(max_radius + PROJECT_PATHS_SCRIPT.DEV_MAP_ZONE_RADIUS_EXTRA, world_max_radius)
	var zone_span := maxf(zone_max_radius - start_radius, 1.0)
	var inner_min_radius := start_radius + (zone_span * PROJECT_PATHS_SCRIPT.DEV_MAP_ZONE_INNER_FRONTIER_MIN_RATIO)
	var inner_max_radius := start_radius + (zone_span * PROJECT_PATHS_SCRIPT.DEV_MAP_ZONE_INNER_FRONTIER_MAX_RATIO)
	inner_min_radius = clampf(inner_min_radius, start_radius, zone_max_radius)
	inner_max_radius = clampf(inner_max_radius, inner_min_radius, zone_max_radius)

	var inner_target := int(round(float(requested_zone_count) * PROJECT_PATHS_SCRIPT.DEV_MAP_ZONE_INNER_TARGET_SHARE))
	if requested_zone_count > 0:
		inner_target = clampi(inner_target, 1, requested_zone_count)
	var outer_target : Variant = max(requested_zone_count - inner_target, 0)

	var zones_placed := 0
	zones_placed += _scatter_zones_in_band(rng, apex, half_angle, inner_min_radius, inner_max_radius, inner_target, zone_types)
	zones_placed += _scatter_zones_in_band(rng, apex, half_angle, inner_max_radius, zone_max_radius, outer_target, zone_types)
	if zones_placed < requested_zone_count:
		zones_placed += _scatter_zones_in_band(
			rng,
			apex,
			half_angle,
			inner_min_radius,
			zone_max_radius,
			requested_zone_count - zones_placed,
			zone_types
		)

	_notify_layout_changed()
	print("DevLevelEditor: generated %d/%d power nodes, %d zones" % [
		placed_positions.size(), total_nodes, zones_placed
	])


func _is_too_close_to_positions(world_pos: Vector2, placed_positions: Array, min_separation: float) -> bool:
	for p_raw in placed_positions:
		var p := p_raw as Vector2
		if world_pos.distance_to(p) < min_separation:
			return true
	return false


func _pick_procedural_power_overrides(rng: RandomNumberGenerator) -> Dictionary:
	var radius := _random_power_node_radius(rng)
	var rated := PROJECT_PATHS_SCRIPT.get_power_node_torque_from_radius(radius)
	return { "source_outer_radius": radius, "rated_torque_output": rated }


func _build_power_overrides_from_radius(radius: float, torque_override: float = -1.0) -> Dictionary:
	var rated := torque_override if torque_override > 0.0 else PROJECT_PATHS_SCRIPT.get_power_node_torque_from_radius(radius)
	return {
		"source_outer_radius": radius,
		"rated_torque_output": rated,
	}


func _scatter_zones_in_band(
	rng: RandomNumberGenerator,
	apex: Vector2,
	half_angle: float,
	min_radius: float,
	max_radius: float,
	target_count: int,
	zone_types: Array
) -> int:
	if target_count <= 0 or zone_types.is_empty():
		return 0

	var safe_min := minf(min_radius, max_radius)
	var safe_max := maxf(min_radius, max_radius)
	var placed := 0
	var attempts := 0
	var max_attempts := maxi(target_count * 25, 25)
	while placed < target_count and attempts < max_attempts:
		attempts += 1
		var r := rng.randf_range(safe_min, safe_max)
		var angle := rng.randf_range(-half_angle, half_angle)
		var world_pos := apex + Vector2(sin(angle), -cos(angle)) * r
		_create_zone(world_pos, zone_types[rng.randi() % zone_types.size()])
		placed += 1

	return placed


func _upgrade_some_nodes_to_giant(power_nodes: Array, rng: RandomNumberGenerator) -> void:
	if power_nodes.size() <= 1:
		return

	var min_count := PROJECT_PATHS_SCRIPT.DEV_MAP_GIANT_NODE_COUNT_MIN
	var max_count := PROJECT_PATHS_SCRIPT.DEV_MAP_GIANT_NODE_COUNT_MAX
	var desired_count := clampi(PROJECT_PATHS_SCRIPT.DEV_MAP_GIANT_NODE_COUNT_DEFAULT, min_count, max_count)
	var giant_count := clampi(desired_count, 0, power_nodes.size() - 1)
	if giant_count <= 0:
		return

	var candidate_indices: Array = []
	for idx in range(1, power_nodes.size()):
		candidate_indices.append(idx)

	for _pick in range(giant_count):
		if candidate_indices.is_empty():
			break
		var pick_i := rng.randi() % candidate_indices.size()
		var node_index := int(candidate_indices[pick_i])
		candidate_indices.remove_at(pick_i)
		var node := power_nodes[node_index] as Node2D
		if node == null:
			continue
		_apply_power_node_size(
			node,
			PROJECT_PATHS_SCRIPT.DEV_MAP_GIANT_NODE_RADIUS,
			PROJECT_PATHS_SCRIPT.DEV_MAP_GIANT_NODE_TORQUE
		)


func _apply_power_node_size(node: Node2D, radius: float, rated_torque: float = -1.0) -> void:
	if node == null:
		return
	var rated := rated_torque if rated_torque > 0.0 else PROJECT_PATHS_SCRIPT.get_power_node_torque_from_radius(radius)
	node.set("source_outer_radius", radius)
	node.set("rated_torque_output", rated)
	node.set("stall_torque_output", rated * PROJECT_PATHS_SCRIPT.POWER_NODE_STALL_RATIO)
	node.set("brake_torque_cap", rated * PROJECT_PATHS_SCRIPT.POWER_NODE_BRAKE_CAP_RATIO)

	var visual := node.get_node_or_null("Visual")
	if visual != null:
		var is_giant := radius >= (PROJECT_PATHS_SCRIPT.DEV_MAP_GIANT_NODE_RADIUS - 0.01)
		var visual_outer := radius * PROJECT_PATHS_SCRIPT.DEV_MAP_GIANT_NODE_VISUAL_SCALE if is_giant else radius
		var safe_outer := maxf(visual_outer, 2.0)
		var module_variant: Variant = visual.get("module_size")
		var module_size := PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_MODULE
		if module_variant != null:
			module_size = maxf(float(module_variant), 0.5)
		var safe_module := maxf(module_size / maxf(PROJECT_PATHS_SCRIPT.GEAR_TOOTH_DENSITY_SCALE, 0.1), 0.5)
		var pitch_radius := maxf(safe_outer - PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_ADDENDUM, safe_module * 3.0)
		var inner_radius := maxf(2.0, pitch_radius - PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_DEDENDUM)
		var tooth_depth := safe_outer - inner_radius
		var hub_radius := maxf(safe_module * 1.4, inner_radius * PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_HUB_RADIUS_RATIO)

		visual.set("outer_radius", safe_outer)
		visual.set("tooth_count", PROJECT_PATHS_SCRIPT.compute_tooth_count_from_outer_radius(safe_outer))
		visual.set("inner_radius", inner_radius)
		visual.set("hub_radius", hub_radius)
		visual.set("tooth_depth", tooth_depth)
		visual.set("tooth_width_ratio", PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_TOOTH_WIDTH_RATIO)
		visual.set("spokes_enabled", false)
		visual.set("cutout_windows_enabled", false)

		if is_giant:
			visual.set("body_color", Color(0.26, 0.3, 0.22, 1.0))
			visual.set("tooth_color", Color(0.53, 0.62, 0.34, 1.0))
			visual.set("outline_color", Color(0.12, 0.15, 0.09, 1.0))
		elif radius >= PROJECT_PATHS_SCRIPT.POWER_NODE_TIER_4_RADIUS:
			visual.set("body_color", Color(0.27, 0.4, 0.72, 1.0))
			visual.set("tooth_color", Color(0.52, 0.74, 1.0, 1.0))
			visual.set("outline_color", Color(0.09, 0.14, 0.27, 1.0))
		elif radius >= PROJECT_PATHS_SCRIPT.POWER_NODE_TIER_3_RADIUS:
			visual.set("body_color", Color(0.28, 0.47, 0.68, 1.0))
			visual.set("tooth_color", Color(0.46, 0.74, 0.94, 1.0))
			visual.set("outline_color", Color(0.09, 0.18, 0.24, 1.0))
		else:
			visual.set("body_color", Color(0.31, 0.52, 0.82, 1.0))
			visual.set("tooth_color", Color(0.48, 0.76, 1.0, 1.0))
			visual.set("outline_color", Color(0.09, 0.18, 0.3, 1.0))
		if visual.has_method("queue_redraw"):
			visual.call("queue_redraw")


func _serialize_components() -> Dictionary:
	var component_entries: Array = []

	for child in _components_container.get_children():
		var node := child as Node2D
		if node == null:
			continue
		var component_type := str(node.get_meta("component_type", ""))
		if not _is_supported_component_type(component_type):
			continue

		var entry := {
			"component_type": component_type,
			"position": [node.global_position.x, node.global_position.y],
			"rotation": node.rotation
		}

		component_entries.append(entry)

	var dev_power_nodes: Array = []
	if _network_node:
		for child in _network_node.get_children():
			var power_node := child as Node2D
			if power_node == null:
				continue
			if not str(power_node.name).begins_with("Power"):
				continue
			if not bool(power_node.get_meta("dev_created", false)):
				continue

			dev_power_nodes.append({
				"position": [power_node.global_position.x, power_node.global_position.y],
				"rated_torque_output": float(power_node.get("rated_torque_output")),
				"stall_torque_output": float(power_node.get("stall_torque_output")),
				"brake_torque_cap": float(power_node.get("brake_torque_cap")),
				"source_outer_radius": float(power_node.get("source_outer_radius"))
			})

	var dev_zones: Array = []
	if _zones_node:
		for child in _zones_node.get_children():
			var zone := child as Node2D
			if zone == null:
				continue
			if not bool(zone.get_meta("dev_created", false)):
				continue
			if not zone.has_method("get_effect_at"):
				continue

			dev_zones.append({
				"position": [zone.global_position.x, zone.global_position.y],
				"zone_type": str(zone.get("zone_type")),
				"radius": float(zone.get("radius")),
				"friction_multiplier": float(zone.get("friction_multiplier")),
				"efficiency_multiplier": float(zone.get("efficiency_multiplier")),
				"torque_load_add": float(zone.get("torque_load_add")),
				"power_output_multiplier": float(zone.get("power_output_multiplier")),
				"power_output_add": float(zone.get("power_output_add"))
			})

	var dev_barriers: Array = []
	if _barriers_node:
		for child in _barriers_node.get_children():
			var barrier := child as Node2D
			if barrier == null:
				continue
			if not bool(barrier.get_meta("dev_created", false)):
				continue

			dev_barriers.append({
				"position": [barrier.global_position.x, barrier.global_position.y],
				"radius": float(barrier.get("radius"))
			})

	return {
		"version": SAVE_VERSION,
		"components": component_entries,
		"dev_power_nodes": dev_power_nodes,
		"dev_zones": dev_zones,
		"dev_barriers": dev_barriers,
		"component_count": component_entries.size()
	}


func _apply_serialized_level(payload: Dictionary) -> void:
	for child in _components_container.get_children():
		child.queue_free()
	_clear_dev_world_nodes()

	var default_gear_scene := load(GEAR_SCENE_PATH) as PackedScene

	var saved_components := payload.get("components", []) as Array
	var saved_power_nodes := payload.get("dev_power_nodes", []) as Array
	var saved_zones := payload.get("dev_zones", []) as Array
	var saved_barriers := payload.get("dev_barriers", []) as Array

	for component_raw in saved_components:
		if not component_raw is Dictionary:
			continue
		var component := component_raw as Dictionary

		var component_type := _normalize_loaded_component_type(
			str(component.get("component_type", PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_MEDIUM))
		)
		if component_type.is_empty():
			continue
		var chosen_scene := _get_scene_for_component(component_type)
		if chosen_scene == null:
			chosen_scene = default_gear_scene
		var node := chosen_scene.instantiate() as Node2D
		if node == null:
			continue

		node.set_meta("component_type", component_type)
		node.global_position = _array_to_vec2(component.get("position", [0.0, 0.0]))
		node.rotation = float(component.get("rotation", 0.0))

		_configure_visual_for_component(node, component_type)
		_components_container.add_child(node)

	for power_raw in saved_power_nodes:
		if not power_raw is Dictionary:
			continue
		var power_data := power_raw as Dictionary
		_create_power_node(
			_array_to_vec2(power_data.get("position", [0.0, 0.0])),
			power_data
		)

	for zone_raw in saved_zones:
		if not zone_raw is Dictionary:
			continue
		var zone_data := zone_raw as Dictionary
		_create_zone(
			_array_to_vec2(zone_data.get("position", [0.0, 0.0])),
			str(zone_data.get("zone_type", "heat")),
			zone_data
		)

	for barrier_raw in saved_barriers:
		if not barrier_raw is Dictionary:
			continue
		var barrier_data := barrier_raw as Dictionary
		_create_barrier(
			_array_to_vec2(barrier_data.get("position", [0.0, 0.0])),
			barrier_data
		)

	_notify_layout_changed()


func _notify_layout_changed() -> void:
	if _signal_bus:
		_signal_bus.component_removed.emit()


func _build_menu() -> void:
	_menu_layer = CanvasLayer.new()
	add_child(_menu_layer)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = 12.0
	panel.offset_top = 12.0
	panel.offset_right = 264.0
	panel.offset_bottom = 408.0
	_menu_layer.add_child(panel)
	_menu_root = panel
	_menu_root.visible = _menu_visible

	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(layout)

	var title := Label.new()
	title.text = "Dev Mode"
	layout.add_child(title)

	_tool_status_label = Label.new()
	_tool_status_label.text = "Tool: None"
	layout.add_child(_tool_status_label)

	var controls := Label.new()
	controls.text = "F5 Menu  F6 Save  F7 Load  F8 Clear"
	layout.add_child(controls)

	var sep1 := HSeparator.new()
	layout.add_child(sep1)

	_add_tool_button(layout, "Select/None", TOOL_NONE)
	_add_tool_button(layout, "Power Node", TOOL_POWER_NODE)
	_add_tool_button(layout, "Zone: Heat", TOOL_ZONE_HEAT)
	_add_tool_button(layout, "Zone: Cold", TOOL_ZONE_COLD)
	_add_tool_button(layout, "Barrier", TOOL_BARRIER)
	_add_tool_button(layout, "Delete Dev Node", TOOL_DELETE_DEV)

	var sep2 := HSeparator.new()
	layout.add_child(sep2)

	var seed_label := Label.new()
	seed_label.text = "Seed (empty = random)"
	layout.add_child(seed_label)

	var seed_input := LineEdit.new()
	seed_input.placeholder_text = "-1 for random"
	seed_input.text = "-1"
	layout.add_child(seed_input)

	var gen_btn := Button.new()
	gen_btn.text = "Generate Map"
	gen_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gen_btn.pressed.connect(func() -> void:
		var seed_value: int = -1
		if not seed_input.text.is_empty():
			seed_value = int(seed_input.text) if seed_input.text.is_valid_int() else -1
		generate_procedural_map(-1, -1, seed_value)
	)
	layout.add_child(gen_btn)

	var row := HBoxContainer.new()
	layout.add_child(row)

	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.pressed.connect(save_level)
	row.add_child(save_btn)

	var load_btn := Button.new()
	load_btn.text = "Load"
	load_btn.pressed.connect(load_level)
	row.add_child(load_btn)

	var clear_btn := Button.new()
	clear_btn.text = "Clear"
	clear_btn.pressed.connect(clear_level)
	row.add_child(clear_btn)


func _add_tool_button(parent: Control, label: String, tool_id: String) -> void:
	var btn := Button.new()
	btn.text = label
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(func() -> void:
		_set_active_tool(tool_id)
	)
	parent.add_child(btn)


func _set_active_tool(tool_id: String) -> void:
	_active_tool = tool_id
	if _tool_status_label:
		_tool_status_label.text = "Tool: %s" % [_describe_tool(tool_id)]

	# Disable normal component placement while dev placement tool is active.
	if _signal_bus:
		_signal_bus.component_selected.emit(PROJECT_PATHS_SCRIPT.COMPONENT_NONE)


func _describe_tool(tool_id: String) -> String:
	match tool_id:
		TOOL_POWER_NODE:
			return "Power Node"
		TOOL_ZONE_HEAT:
			return "Zone Heat"
		TOOL_ZONE_COLD:
			return "Zone Cold"
		TOOL_BARRIER:
			return "Barrier"
		TOOL_DELETE_DEV:
			return "Delete Dev Node"
		_:
			return "None"


func _place_with_active_tool(world_pos: Vector2) -> void:
	match _active_tool:
		TOOL_POWER_NODE:
			_create_power_node(world_pos)
		TOOL_ZONE_HEAT:
			_create_zone(world_pos, "heat")
		TOOL_ZONE_COLD:
			_create_zone(world_pos, "cold")
		TOOL_BARRIER:
			_create_barrier(world_pos)
		TOOL_DELETE_DEV:
			_delete_nearest_dev_node(world_pos)
		_:
			return

	_notify_layout_changed()


func _create_power_node(world_pos: Vector2, overrides: Dictionary = {}) -> Node2D:
	if _network_node == null:
		return null

	var anchor_script := load(ANCHOR_ROTOR_SCRIPT_PATH) as Script
	var visual_script := load(GEAR_VISUAL_SCRIPT_PATH) as Script
	if anchor_script == null or visual_script == null:
		return null

	# Generate random defaults; overrides win so loading saved nodes restores exact values.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var radius := float(overrides.get("source_outer_radius", _random_power_node_radius(rng)))
	var rated := float(overrides.get("rated_torque_output", PROJECT_PATHS_SCRIPT.get_power_node_torque_from_radius(radius)))

	var power_node := Node2D.new()
	power_node.set_script(anchor_script)
	power_node.name = _generate_unique_name("Power", _network_node)
	power_node.global_position = world_pos
	power_node.set_meta("dev_created", true)
	power_node.set("always_active", bool(overrides.get("always_active", false)))
	power_node.set("no_load_rpm", PROJECT_PATHS_SCRIPT.POWER_NODE_NO_LOAD_RPM)
	power_node.set("base_spin_speed", PROJECT_PATHS_SCRIPT.POWER_NODE_BASE_SPIN_SPEED)
	power_node.set("torque_spin_factor", PROJECT_PATHS_SCRIPT.POWER_NODE_TORQUE_SPIN_FACTOR)
	power_node.set("min_output_ratio", PROJECT_PATHS_SCRIPT.POWER_NODE_MIN_OUTPUT_RATIO)
	power_node.set("output_droop_strength", PROJECT_PATHS_SCRIPT.POWER_NODE_OUTPUT_DROOP)

	var visual := Node2D.new()
	visual.name = "Visual"
	visual.set_script(visual_script)
	visual.set("use_module_profile", true)
	visual.set("body_color", Color(0.26, 0.48, 0.78, 1.0))
	visual.set("tooth_color", Color(0.4, 0.68, 1.0, 1.0))
	visual.set("outline_color", Color(0.07, 0.14, 0.23, 1.0))
	power_node.add_child(visual)
	_apply_power_node_size(power_node, radius, rated)

	_network_node.add_child(power_node)
	return power_node


func _random_power_node_radius(rng: RandomNumberGenerator) -> float:
	var roll := rng.randf()
	if roll < 0.40:
		return PROJECT_PATHS_SCRIPT.POWER_NODE_TIER_0_RADIUS
	if roll < 0.68:
		return PROJECT_PATHS_SCRIPT.POWER_NODE_TIER_1_RADIUS
	if roll < 0.86:
		return PROJECT_PATHS_SCRIPT.POWER_NODE_TIER_2_RADIUS
	if roll < 0.96:
		return PROJECT_PATHS_SCRIPT.POWER_NODE_TIER_3_RADIUS
	return PROJECT_PATHS_SCRIPT.POWER_NODE_TIER_4_RADIUS


func _create_zone(world_pos: Vector2, zone_type: String, overrides: Dictionary = {}) -> void:
	if _zones_node == null:
		return

	var zone_script := load(ZONE_EFFECT_SCRIPT_PATH) as Script
	if zone_script == null:
		return

	var zone := Node2D.new()
	zone.set_script(zone_script)
	zone.name = _generate_unique_name("Zone", _zones_node)
	zone.global_position = world_pos
	zone.set_meta("dev_created", true)
	zone.set("show_gizmo", true)
	zone.set("follow_target_path", NodePath(""))
	_apply_zone_defaults(zone, zone_type)

	for key in overrides.keys():
		var prop := str(key)
		if prop == "position":
			continue
		zone.set(prop, overrides[key])

	_zones_node.add_child(zone)


func _apply_zone_defaults(zone: Node2D, zone_type: String) -> void:
	if zone == null:
		return

	match zone_type:
		"cold":
			zone.set("zone_type", "cold")
			zone.set("radius", 165.0)
			zone.set("friction_multiplier", 0.92)
			zone.set("efficiency_multiplier", 1.10)
			zone.set("torque_load_add", 0.0)
			zone.set("power_output_multiplier", 1.03)
			zone.set("power_output_add", 0.5)
			zone.set("gizmo_color", Color(0.35, 0.6, 1.0, 0.2))
		_:
			zone.set("zone_type", "heat")
			zone.set("radius", 180.0)
			zone.set("friction_multiplier", 1.1)
			zone.set("efficiency_multiplier", 0.96)
			zone.set("torque_load_add", 0.15)
			zone.set("power_output_multiplier", 0.98)
			zone.set("power_output_add", 0.0)
			zone.set("gizmo_color", Color(1.0, 0.4, 0.25, 0.2))


func _create_barrier(world_pos: Vector2, overrides: Dictionary = {}) -> void:
	if _barriers_node == null:
		return

	var barrier_script := load(BARRIER_ZONE_SCRIPT_PATH) as Script
	if barrier_script == null:
		return

	var barrier := Node2D.new()
	barrier.set_script(barrier_script)
	barrier.name = _generate_unique_name("Barrier", _barriers_node)
	barrier.global_position = world_pos
	barrier.set_meta("dev_created", true)
	barrier.set("show_gizmo", true)
	barrier.set("radius", float(overrides.get("radius", 56.0)))
	_barriers_node.add_child(barrier)


func _delete_nearest_dev_node(world_pos: Vector2) -> void:
	var nearest: Node2D = null
	var nearest_distance := INF

	for node in _get_all_deletable_dev_nodes():
		var candidate := node as Node2D
		if candidate == null:
			continue
		var distance := candidate.global_position.distance_to(world_pos)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = candidate

	if nearest and nearest_distance <= 56.0:
		nearest.queue_free()


func _get_all_deletable_dev_nodes() -> Array:
	var nodes: Array = []
	if _network_node:
		for child in _network_node.get_children():
			if child is Node2D and str(child.name).begins_with("Power") and bool(child.get_meta("dev_created", false)):
				nodes.append(child)
	if _zones_node:
		for child in _zones_node.get_children():
			if child is Node2D and bool(child.get_meta("dev_created", false)):
				nodes.append(child)
	if _barriers_node:
		for child in _barriers_node.get_children():
			if child is Node2D and bool(child.get_meta("dev_created", false)):
				nodes.append(child)
	return nodes


func _clear_dev_world_nodes() -> void:
	for node in _get_all_deletable_dev_nodes():
		(node as Node2D).queue_free()


func _generate_unique_name(prefix: String, parent: Node) -> String:
	if parent == null:
		return prefix
	if parent.get_node_or_null(prefix) == null:
		return prefix

	var index := 2
	while parent.get_node_or_null("%s%s" % [prefix, index]) != null:
		index += 1
	return "%s%s" % [prefix, index]


func _is_pointer_over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null


func _get_mouse_world_position() -> Vector2:
	var parent_2d := get_parent() as Node2D
	if parent_2d:
		return parent_2d.get_global_mouse_position()

	var canvas_xform := get_viewport().get_canvas_transform()
	return canvas_xform.affine_inverse() * get_viewport().get_mouse_position()


func _configure_visual_for_component(node: Node2D, component_type: String) -> void:
	var visual := node.get_node_or_null("Visual")
	if visual == null:
		return

	visual.set("outer_radius", _get_component_outer_radius(component_type))
	visual.set("visual_mode", "gear")
	visual.set("use_module_profile", true)
	if visual.has_method("_sync_module_profile"):
		visual.call("_sync_module_profile")


func _get_scene_for_component(component_type: String) -> PackedScene:
	match component_type:
		PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_SMALL:
			return small_gear_scene if small_gear_scene != null else null
		PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_MEDIUM:
			return medium_gear_scene if medium_gear_scene != null else null
		PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_LARGE:
			return large_gear_scene if large_gear_scene != null else null
		_:
			return null


func _get_component_outer_radius(component_type: String) -> float:
	match component_type:
		PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_SMALL:
			return PROJECT_PATHS_SCRIPT.SMALL_GEAR_OUTER_RADIUS
		PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_LARGE:
			return PROJECT_PATHS_SCRIPT.LARGE_GEAR_OUTER_RADIUS
		_:
			return PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS


func _is_supported_component_type(component_type: String) -> bool:
	return component_type == PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_SMALL \
		or component_type == PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_MEDIUM \
		or component_type == PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_LARGE


func _normalize_loaded_component_type(component_type: String) -> String:
	if _is_supported_component_type(component_type):
		return component_type
	return ""


func _array_to_vec2(raw: Variant) -> Vector2:
	if raw is Array:
		var arr := raw as Array
		if arr.size() >= 2:
			return Vector2(float(arr[0]), float(arr[1]))
	return Vector2.ZERO
