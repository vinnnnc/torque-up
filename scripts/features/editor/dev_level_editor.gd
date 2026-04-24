extends Node
class_name DevLevelEditor

const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")
const CHAIN_COMPONENT_SCRIPT_PATH := "res://scripts/components/chain.gd"
const GEAR_SCENE_PATH := "res://scenes/components/Gear.tscn"
const ANCHOR_ROTOR_SCRIPT_PATH := "res://scripts/components/anchor_rotor.gd"
const GEAR_VISUAL_SCRIPT_PATH := "res://scripts/components/gear_visual.gd"
const ZONE_EFFECT_SCRIPT_PATH := "res://scripts/features/zones/zone_effect.gd"
const BARRIER_ZONE_SCRIPT_PATH := "res://scripts/features/barriers/barrier_zone.gd"
const SAVE_DIR := "user://dev_levels"
const SAVE_PATH := "user://dev_levels/level_dev.json"

const TOOL_NONE := "none"
const TOOL_POWER_BALANCED := "power_balanced"
const TOOL_POWER_TORQUE := "power_torque"
const TOOL_POWER_SPEED := "power_speed"
const TOOL_ZONE_HEAT := "zone_heat"
const TOOL_ZONE_COLD := "zone_cold"
const TOOL_ZONE_DUST := "zone_dust"
const TOOL_BARRIER := "barrier"
const TOOL_DELETE_DEV := "delete_dev"

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
@export var shaft_scene: PackedScene
@export var flywheel_scene: PackedScene
@export var clutch_scene: PackedScene
@export var differential_scene: PackedScene
@export var chain_scene: PackedScene

var _active_tool: String = TOOL_NONE
var _menu_visible: bool = false
var _menu_layer: CanvasLayer = null
var _menu_root: Control = null
var _tool_status_label: Label = null

func _ready() -> void:
	_build_menu()
	_set_active_tool(TOOL_NONE)
	print("DevLevelEditor hotkeys: F5=menu F6=save F7=load F8=clear")


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
	print("DevLevelEditor: saved %s components and %s chains to %s" % [
		int(payload.get("component_count", 0)),
		int(payload.get("chain_count", 0)),
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


func generate_procedural_map(node_count: int = -1, zone_count: int = -1) -> void:
	# Clear existing dev-placed network nodes and world objects.
	_clear_dev_world_nodes()
	if _network_node != null:
		for child in _network_node.get_children():
			if child.has_meta("dev_created"):
				child.queue_free()

	# Wait one frame so queue_free'd nodes are removed before we place new ones.
	await get_tree().process_frame

	var rng := RandomNumberGenerator.new()
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

			_create_power_node(world_pos, _pick_procedural_power_type(rng))
			placed_positions.append(world_pos)
			placed_nodes += 1
		row_radius += row_spacing
    # Scatter environmental zones.
	var requested_zone_count := zone_count
	if requested_zone_count <= 0:
		requested_zone_count = PROJECT_PATHS_SCRIPT.DEV_MAP_DEFAULT_ZONE_COUNT
	var zone_types := ["heat", "cold", "dust"]
	var zones_placed := 0
	var zone_attempts := 0
	var zone_max_radius := minf(max_radius + PROJECT_PATHS_SCRIPT.DEV_MAP_ZONE_RADIUS_EXTRA, world_max_radius)
	while zones_placed < requested_zone_count and zone_attempts < requested_zone_count * 20:
		zone_attempts += 1
		var r := rng.randf_range(start_radius, zone_max_radius)
		var angle := rng.randf_range(-half_angle, half_angle)
		var world_pos := apex + Vector2(sin(angle), -cos(angle)) * r
		_create_zone(world_pos, zone_types[rng.randi() % zone_types.size()])
		zones_placed += 1

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


func _pick_procedural_power_type(rng: RandomNumberGenerator) -> String:
	# Weighted type: 50% balanced, 30% torque, 20% speed.
	var rand_val := rng.randf()
	if rand_val < 0.5:
		return PROJECT_PATHS_SCRIPT.POWER_NODE_BALANCED
	if rand_val < 0.8:
		return PROJECT_PATHS_SCRIPT.POWER_NODE_TORQUE
	return PROJECT_PATHS_SCRIPT.POWER_NODE_SPEED


func _serialize_components() -> Dictionary:
	var component_entries: Array = []
	var chain_entries: Array = []
	var id_by_instance: Dictionary = {}
	var next_id := 1

	for child in _components_container.get_children():
		var node := child as Node2D
		if node == null:
			continue
		var component_type := str(node.get_meta("component_type", ""))
		if component_type == PROJECT_PATHS_SCRIPT.COMPONENT_CHAIN:
			continue

		var entry := {
			"id": next_id,
			"component_type": component_type,
			"position": [node.global_position.x, node.global_position.y],
			"rotation": node.rotation
		}

		if node.has_meta("shaft_connection_radius"):
			entry["shaft_connection_radius"] = float(node.get_meta("shaft_connection_radius"))
		if node.has_meta("stack_parent_id"):
			entry["stack_parent_instance_id"] = int(node.get_meta("stack_parent_id"))
		if node.has_meta("stack_root_id"):
			entry["stack_root_instance_id"] = int(node.get_meta("stack_root_id"))

		component_entries.append(entry)
		id_by_instance[node.get_instance_id()] = next_id
		next_id += 1

	for entry_raw in component_entries:
		if not entry_raw is Dictionary:
			continue
		var entry := entry_raw as Dictionary
		if entry.has("stack_parent_instance_id"):
			var parent_instance_id := int(entry["stack_parent_instance_id"])
			entry.erase("stack_parent_instance_id")
			if id_by_instance.has(parent_instance_id):
				entry["stack_parent_id"] = int(id_by_instance[parent_instance_id])
		if entry.has("stack_root_instance_id"):
			var root_instance_id := int(entry["stack_root_instance_id"])
			entry.erase("stack_root_instance_id")
			if id_by_instance.has(root_instance_id):
				entry["stack_root_id"] = int(id_by_instance[root_instance_id])

	for child in _components_container.get_children():
		var node := child as Node2D
		if node == null:
			continue
		if str(node.get_meta("component_type", "")) != PROJECT_PATHS_SCRIPT.COMPONENT_CHAIN:
			continue

		var chain_component := _get_chain_component(node)
		if chain_component == null:
			continue

		var pulley_a := chain_component.get("pulley_a") as Node2D
		var pulley_b := chain_component.get("pulley_b") as Node2D
		if pulley_a == null or pulley_b == null:
			continue

		if not id_by_instance.has(pulley_a.get_instance_id()) or not id_by_instance.has(pulley_b.get_instance_id()):
			continue

		chain_entries.append({
			"pulley_a_id": int(id_by_instance[pulley_a.get_instance_id()]),
			"pulley_b_id": int(id_by_instance[pulley_b.get_instance_id()])
		})

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
				"power_node_type": str(power_node.get("power_node_type")),
				"rated_torque_output": float(power_node.get("rated_torque_output")),
				"base_spin_speed": float(power_node.get("base_spin_speed")),
				"torque_spin_factor": float(power_node.get("torque_spin_factor"))
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
		"version": 1,
		"components": component_entries,
		"chains": chain_entries,
		"dev_power_nodes": dev_power_nodes,
		"dev_zones": dev_zones,
		"dev_barriers": dev_barriers,
		"component_count": component_entries.size(),
		"chain_count": chain_entries.size()
	}


func _apply_serialized_level(payload: Dictionary) -> void:
	for child in _components_container.get_children():
		child.queue_free()
	_clear_dev_world_nodes()

	var default_gear_scene := load(GEAR_SCENE_PATH) as PackedScene
	var chain_script := load(CHAIN_COMPONENT_SCRIPT_PATH) as Script
	if default_gear_scene == null or chain_script == null:
		push_warning("DevLevelEditor: required resources are missing")
		return

	var saved_components := payload.get("components", []) as Array
	var saved_chains := payload.get("chains", payload.get("belts", [])) as Array
	var saved_power_nodes := payload.get("dev_power_nodes", []) as Array
	var saved_zones := payload.get("dev_zones", []) as Array
	var saved_barriers := payload.get("dev_barriers", []) as Array
	var node_by_id: Dictionary = {}
	var stack_meta_by_id: Dictionary = {}

	for component_raw in saved_components:
		if not component_raw is Dictionary:
			continue
		var component := component_raw as Dictionary
		var component_id := int(component.get("id", -1))
		if component_id < 0:
			continue

		var component_type := str(component.get("component_type", PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_MEDIUM))
		var chosen_scene := _get_scene_for_component(component_type)
		if chosen_scene == null:
			chosen_scene = default_gear_scene
		var node := chosen_scene.instantiate() as Node2D
		if node == null:
			continue

		node.set_meta("component_type", component_type)
		node.global_position = _array_to_vec2(component.get("position", [0.0, 0.0]))
		node.rotation = float(component.get("rotation", 0.0))
		if component.has("shaft_connection_radius"):
			node.set_meta("shaft_connection_radius", float(component.get("shaft_connection_radius", 0.0)))

		_configure_visual_for_component(node, component_type)
		_components_container.add_child(node)
		node_by_id[component_id] = node
		stack_meta_by_id[component_id] = {
			"stack_parent_id": int(component.get("stack_parent_id", -1)),
			"stack_root_id": int(component.get("stack_root_id", -1))
		}

	for id_key in node_by_id.keys():
		var node := node_by_id[id_key] as Node2D
		var stack_meta := stack_meta_by_id.get(id_key, {}) as Dictionary
		var saved_parent_id := int(stack_meta.get("stack_parent_id", -1))
		var saved_root_id := int(stack_meta.get("stack_root_id", -1))
		if saved_parent_id >= 0 and node_by_id.has(saved_parent_id):
			var parent_node := node_by_id[saved_parent_id] as Node2D
			node.set_meta("stack_parent_id", parent_node.get_instance_id())
			if node.has_method("set_stacked_top"):
				node.call("set_stacked_top", true)
		if saved_root_id >= 0 and node_by_id.has(saved_root_id):
			var root_node := node_by_id[saved_root_id] as Node2D
			node.set_meta("stack_root_id", root_node.get_instance_id())
		elif node.has_meta("stack_parent_id") and saved_parent_id >= 0 and node_by_id.has(saved_parent_id):
			node.set_meta("stack_root_id", (node_by_id[saved_parent_id] as Node2D).get_instance_id())

	for chain_raw in saved_chains:
		if not chain_raw is Dictionary:
			continue
		var chain_data := chain_raw as Dictionary
		var pulley_a_id := int(chain_data.get("pulley_a_id", -1))
		var pulley_b_id := int(chain_data.get("pulley_b_id", -1))
		if not node_by_id.has(pulley_a_id) or not node_by_id.has(pulley_b_id):
			continue

		var pulley_a := node_by_id[pulley_a_id] as Node2D
		var pulley_b := node_by_id[pulley_b_id] as Node2D
		if pulley_a == null or pulley_b == null:
			continue

		# Prefer exported chain scene when available
		if chain_scene != null:
			var chain_node := chain_scene.instantiate() as Node2D
			if chain_node == null:
				continue
			if chain_node.has_method("configure"):
				chain_node.call("configure", pulley_a, pulley_b, _get_node_connection_radius(pulley_a), _get_node_connection_radius(pulley_b))
			chain_node.set_meta("component_type", PROJECT_PATHS_SCRIPT.COMPONENT_CHAIN)
			_components_container.add_child(chain_node)
		else:
			var chain_node := Node2D.new()
			chain_node.set_meta("component_type", PROJECT_PATHS_SCRIPT.COMPONENT_CHAIN)
			var chain_component: Node = chain_script.new() as Node
			if chain_component == null:
				continue
			chain_node.add_child(chain_component)
			chain_component.configure(
				pulley_a,
				pulley_b,
				_get_node_connection_radius(pulley_a),
				_get_node_connection_radius(pulley_b)
			)
			_components_container.add_child(chain_node)

	for power_raw in saved_power_nodes:
		if not power_raw is Dictionary:
			continue
		var power_data := power_raw as Dictionary
		_create_power_node(
			_array_to_vec2(power_data.get("position", [0.0, 0.0])),
			str(power_data.get("power_node_type", PROJECT_PATHS_SCRIPT.POWER_NODE_BALANCED)),
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
	_add_tool_button(layout, "Power Node: Balanced", TOOL_POWER_BALANCED)
	_add_tool_button(layout, "Power Node: Torque", TOOL_POWER_TORQUE)
	_add_tool_button(layout, "Power Node: Speed", TOOL_POWER_SPEED)
	_add_tool_button(layout, "Zone: Heat", TOOL_ZONE_HEAT)
	_add_tool_button(layout, "Zone: Cold", TOOL_ZONE_COLD)
	_add_tool_button(layout, "Zone: Dust", TOOL_ZONE_DUST)
	_add_tool_button(layout, "Barrier", TOOL_BARRIER)
	_add_tool_button(layout, "Delete Dev Node", TOOL_DELETE_DEV)

	var sep2 := HSeparator.new()
	layout.add_child(sep2)

	var gen_btn := Button.new()
	gen_btn.text = "Generate Map"
	gen_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gen_btn.pressed.connect(func() -> void: generate_procedural_map())
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
		TOOL_POWER_BALANCED:
			return "Power Balanced"
		TOOL_POWER_TORQUE:
			return "Power Torque"
		TOOL_POWER_SPEED:
			return "Power Speed"
		TOOL_ZONE_HEAT:
			return "Zone Heat"
		TOOL_ZONE_COLD:
			return "Zone Cold"
		TOOL_ZONE_DUST:
			return "Zone Dust"
		TOOL_BARRIER:
			return "Barrier"
		TOOL_DELETE_DEV:
			return "Delete Dev Node"
		_:
			return "None"


func _place_with_active_tool(world_pos: Vector2) -> void:
	match _active_tool:
		TOOL_POWER_BALANCED:
			_create_power_node(world_pos, PROJECT_PATHS_SCRIPT.POWER_NODE_BALANCED)
		TOOL_POWER_TORQUE:
			_create_power_node(world_pos, PROJECT_PATHS_SCRIPT.POWER_NODE_TORQUE)
		TOOL_POWER_SPEED:
			_create_power_node(world_pos, PROJECT_PATHS_SCRIPT.POWER_NODE_SPEED)
		TOOL_ZONE_HEAT:
			_create_zone(world_pos, "heat")
		TOOL_ZONE_COLD:
			_create_zone(world_pos, "cold")
		TOOL_ZONE_DUST:
			_create_zone(world_pos, "dust")
		TOOL_BARRIER:
			_create_barrier(world_pos)
		TOOL_DELETE_DEV:
			_delete_nearest_dev_node(world_pos)
		_:
			return

	_notify_layout_changed()


func _create_power_node(world_pos: Vector2, power_type: String, overrides: Dictionary = {}) -> void:
	if _network_node == null:
		return

	var anchor_script := load(ANCHOR_ROTOR_SCRIPT_PATH) as Script
	var visual_script := load(GEAR_VISUAL_SCRIPT_PATH) as Script
	if anchor_script == null or visual_script == null:
		return

	var power_node := Node2D.new()
	power_node.set_script(anchor_script)
	power_node.name = _generate_unique_name("Power", _network_node)
	power_node.global_position = world_pos
	power_node.set_meta("dev_created", true)
	var always_active := bool(overrides.get("always_active", false))
	power_node.set("always_active", always_active)
	power_node.set("power_node_type", power_type)

	if overrides.has("rated_torque_output"):
		power_node.set("rated_torque_output", float(overrides.get("rated_torque_output", PROJECT_PATHS_SCRIPT.BASE_POWER_NODE_OUTPUT)))
	if overrides.has("base_spin_speed"):
		power_node.set("base_spin_speed", float(overrides.get("base_spin_speed", 1.45)))
	if overrides.has("torque_spin_factor"):
		power_node.set("torque_spin_factor", float(overrides.get("torque_spin_factor", 0.015)))

	var visual := Node2D.new()
	visual.name = "Visual"
	visual.set_script(visual_script)
	var visual_radius: float
	match power_type:
		PROJECT_PATHS_SCRIPT.POWER_NODE_TORQUE:
			visual_radius = PROJECT_PATHS_SCRIPT.POWER_NODE_RADIUS_TORQUE
		PROJECT_PATHS_SCRIPT.POWER_NODE_SPEED:
			visual_radius = PROJECT_PATHS_SCRIPT.POWER_NODE_RADIUS_SPEED
		_:
			visual_radius = PROJECT_PATHS_SCRIPT.POWER_NODE_RADIUS_BALANCED
	visual.set("outer_radius", visual_radius)
	visual.set("use_module_profile", true)
	_match_power_visual_style(visual, power_type)
	power_node.add_child(visual)

	_network_node.add_child(power_node)


func _match_power_visual_style(visual: Node2D, power_type: String) -> void:
	if visual == null:
		return

	match power_type:
		PROJECT_PATHS_SCRIPT.POWER_NODE_TORQUE:
			visual.set("body_color", Color(0.48, 0.62, 0.27, 1.0))
			visual.set("tooth_color", Color(0.7, 0.85, 0.4, 1.0))
			visual.set("outline_color", Color(0.14, 0.17, 0.08, 1.0))
		PROJECT_PATHS_SCRIPT.POWER_NODE_SPEED:
			visual.set("body_color", Color(0.76, 0.42, 0.25, 1.0))
			visual.set("tooth_color", Color(0.96, 0.62, 0.34, 1.0))
			visual.set("outline_color", Color(0.2, 0.11, 0.07, 1.0))
		_:
			visual.set("body_color", Color(0.26, 0.48, 0.78, 1.0))
			visual.set("tooth_color", Color(0.4, 0.68, 1.0, 1.0))
			visual.set("outline_color", Color(0.07, 0.14, 0.23, 1.0))


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
			zone.set("efficiency_multiplier", 0.99)
			zone.set("torque_load_add", 0.0)
			zone.set("power_output_multiplier", 1.03)
			zone.set("power_output_add", 0.5)
			zone.set("gizmo_color", Color(0.35, 0.6, 1.0, 0.2))
		"dust":
			zone.set("zone_type", "dust")
			zone.set("radius", 145.0)
			zone.set("friction_multiplier", 1.08)
			zone.set("efficiency_multiplier", 0.97)
			zone.set("torque_load_add", 0.1)
			zone.set("power_output_multiplier", 0.99)
			zone.set("power_output_add", -0.2)
			zone.set("gizmo_color", Color(0.84, 0.74, 0.48, 0.2))
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


func _get_chain_component(chain_node: Node2D) -> Node:
	if chain_node == null:
		return null

	# Support direct connector scripts as well as legacy wrapper-child setup.
	if chain_node.has_method("set_tension_state") or chain_node.has_method("set_jam_state"):
		return chain_node
	if chain_node.get("pulley_a") != null or chain_node.get("pulley_b") != null:
		return chain_node

	for child in chain_node.get_children():
		if child and (child.has_method("set_tension_state") or child.has_method("set_jam_state")):
			return child
	return null


func _configure_visual_for_component(node: Node2D, component_type: String) -> void:
	var visual := node.get_node_or_null("Visual")
	if visual == null:
		return

	visual.set("outer_radius", _get_component_outer_radius(component_type))
	if component_type == PROJECT_PATHS_SCRIPT.COMPONENT_SHAFT:
		visual.set("use_module_profile", false)
		visual.set("visual_mode", "shaft")
		visual.set("shaft_module_size", PROJECT_PATHS_SCRIPT.SHAFT_SHAPE_MODULE)
		visual.set("inner_radius", 4.8)
		visual.set("hub_radius", 3.8)
		visual.set("tooth_count", 0)
	elif component_type == PROJECT_PATHS_SCRIPT.COMPONENT_FLYWHEEL:
		visual.set("visual_mode", "flywheel")
		visual.set("use_module_profile", false)
		visual.set("inner_radius", _get_component_outer_radius(component_type) * 0.78)
		visual.set("hub_radius", _get_component_outer_radius(component_type) * 0.24)
		visual.set("body_color", Color(0.34, 0.37, 0.41, 1.0))
		visual.set("tooth_color", Color(0.52, 0.56, 0.60, 1.0))
	elif component_type == PROJECT_PATHS_SCRIPT.COMPONENT_CLUTCH:
		visual.set("visual_mode", "clutch")
		visual.set("use_module_profile", false)
		visual.set("inner_radius", _get_component_outer_radius(component_type) * 0.56)
		visual.set("hub_radius", _get_component_outer_radius(component_type) * 0.2)
		visual.set("body_color", Color(0.64, 0.55, 0.36, 1.0))
		visual.set("tooth_color", Color(0.86, 0.72, 0.46, 1.0))
	elif component_type == PROJECT_PATHS_SCRIPT.COMPONENT_DIFFERENTIAL:
		visual.set("visual_mode", "differential")
		visual.set("use_module_profile", false)
		visual.set("inner_radius", _get_component_outer_radius(component_type) * 0.62)
		visual.set("hub_radius", _get_component_outer_radius(component_type) * 0.22)
		visual.set("body_color", Color(0.41, 0.47, 0.55, 1.0))
		visual.set("tooth_color", Color(0.62, 0.7, 0.8, 1.0))
	else:
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
		PROJECT_PATHS_SCRIPT.COMPONENT_SHAFT:
			return shaft_scene if shaft_scene != null else null
		PROJECT_PATHS_SCRIPT.COMPONENT_FLYWHEEL:
			return flywheel_scene if flywheel_scene != null else null
		PROJECT_PATHS_SCRIPT.COMPONENT_CLUTCH:
			return clutch_scene if clutch_scene != null else null
		PROJECT_PATHS_SCRIPT.COMPONENT_DIFFERENTIAL:
			return differential_scene if differential_scene != null else null
		PROJECT_PATHS_SCRIPT.COMPONENT_CHAIN:
			return chain_scene if chain_scene != null else null
		_:
			return null


func _get_component_outer_radius(component_type: String) -> float:
	match component_type:
		PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_SMALL:
			return PROJECT_PATHS_SCRIPT.SMALL_GEAR_OUTER_RADIUS
		PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_LARGE:
			return PROJECT_PATHS_SCRIPT.LARGE_GEAR_OUTER_RADIUS
		PROJECT_PATHS_SCRIPT.COMPONENT_SHAFT:
			return PROJECT_PATHS_SCRIPT.SHAFT_OUTER_RADIUS
		PROJECT_PATHS_SCRIPT.COMPONENT_FLYWHEEL:
			return PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS * 1.45
		PROJECT_PATHS_SCRIPT.COMPONENT_CLUTCH:
			return PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS * 1.05
		PROJECT_PATHS_SCRIPT.COMPONENT_DIFFERENTIAL:
			return PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS * 1.25
		_:
			return PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS


func _get_node_connection_radius(node: Node2D) -> float:
	if node == null:
		return PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS

	if node.has_meta("shaft_connection_radius"):
		return maxf(0.0, float(node.get_meta("shaft_connection_radius")))

	var visual := node.get_node_or_null("Visual")
	if visual == null:
		return PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS

	var outer_radius := float(visual.get("outer_radius"))
	return maxf(2.0, outer_radius - PROJECT_PATHS_SCRIPT.GEAR_MESH_CONTACT_MARGIN)


func _array_to_vec2(raw: Variant) -> Vector2:
	if raw is Array:
		var arr := raw as Array
		if arr.size() >= 2:
			return Vector2(float(arr[0]), float(arr[1]))
	return Vector2.ZERO
