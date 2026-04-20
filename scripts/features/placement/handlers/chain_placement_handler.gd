## ChainPlacementHandler
## Handles chain preview, drag, and placement between two gear pulleys.
## Extracted from PlacementController.
extends "res://scripts/features/placement/handlers/placement_handler_base.gd"

const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")
const CHAIN_COMPONENT_SCRIPT_PATH := "res://scripts/components/chain.gd"

const COMPONENT_CHAIN := PROJECT_PATHS_SCRIPT.COMPONENT_CHAIN
const COMPONENT_GEAR_SMALL := PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_SMALL
const COMPONENT_GEAR_MEDIUM := PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_MEDIUM
const COMPONENT_GEAR_LARGE := PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_LARGE
const CONVERSION_REJECT_MESHED := "Cannot convert to sprocket: gear is meshed to another gear."
const CONVERSION_REJECT_MESHED_HINT := "Disconnect meshed neighbours first."

# -- Drag state ----------------------------------------------------------------
var _first_pulley: GearComponent = null
var _drag_start_mouse: Vector2 = Vector2.ZERO

# -- Lifecycle -----------------------------------------------------------------

func deactivate() -> void:
	_first_pulley = null
	_drag_start_mouse = Vector2.ZERO

func cancel() -> void:
	_first_pulley = null
	_drag_start_mouse = Vector2.ZERO

# -- Per-frame -----------------------------------------------------------------

func update_preview(mouse_pos: Vector2, _preview_node: Node2D) -> void:
	if _first_pulley == null:
		ctx.socket_markers = []
		for child in ctx.components_container.get_children():
			var candidate := child as GearComponent
			if candidate == null or not is_pulley_candidate(candidate):
				continue
			if not _can_convert_to_sprocket(candidate):
				continue
			ctx.socket_markers.append(candidate.global_position)
		ctx.has_active_socket = false
		ctx.active_socket_valid = false
		return

	var second_pulley := get_nearest_pulley_at(mouse_pos, maxf(28.0, ctx.snap_max_distance))
	var valid := second_pulley != null and second_pulley != _first_pulley and is_valid_distance(_first_pulley.global_position, second_pulley.global_position)
	ctx.has_active_socket = true
	ctx.active_socket_position = _first_pulley.global_position
	ctx.active_socket_valid = valid
	ctx.socket_markers = [_first_pulley.global_position]
	if second_pulley != null and second_pulley != _first_pulley:
		ctx.socket_markers.append(second_pulley.global_position)

func process(_mouse_pos: Vector2) -> void:
	pass

## Draw the drag line and anchor circle from the first selected pulley.
func draw_overlay(draw_node: Node2D) -> void:
	if _first_pulley == null:
		return
	var first_local := draw_node.to_local(_first_pulley.global_position)
	var chain_target := draw_node.get_global_mouse_position()
	var second_pulley := get_nearest_pulley_at(chain_target, maxf(28.0, ctx.snap_max_distance))
	if second_pulley != null and second_pulley != _first_pulley:
		chain_target = second_pulley.global_position
	var target_local := draw_node.to_local(chain_target)
	draw_node.draw_line(first_local, target_local, Color(0.76, 0.9, 1.0, 0.55), 2.0)
	draw_node.draw_circle(first_local, 26.0, Color(0.76, 0.9, 1.0, 0.22))

# -- Input ---------------------------------------------------------------------

func on_mouse_down(world_pos: Vector2) -> void:
	var picked := get_nearest_pulley_at(world_pos, maxf(28.0, ctx.snap_max_distance))
	if picked == null:
		_first_pulley = null
		return
	if not _ensure_sprocket_mode_for_chain_endpoint(picked, true):
		_first_pulley = null
		return
	_first_pulley = picked
	_drag_start_mouse = world_pos


func on_mouse_up(world_pos: Vector2) -> void:
	if _first_pulley == null:
		return
	if _drag_start_mouse.distance_to(world_pos) < ctx.drag_release_deadzone:
		_first_pulley = null
		return
	var second_pulley := get_nearest_pulley_at(world_pos, maxf(28.0, ctx.snap_max_distance))
	if second_pulley != null and second_pulley != _first_pulley and is_valid_distance(_first_pulley.global_position, second_pulley.global_position):
		if not _ensure_sprocket_mode_for_chain_endpoint(second_pulley, true):
			_first_pulley = null
			return
		place(_first_pulley, second_pulley)
	_first_pulley = null


func on_click(_world_pos: Vector2) -> void:
	pass

# -- Instance configuration ---------------------------------------------------

## Chain has no Visual node to configure — meta only.
func configure_instance(instance: Node2D) -> void:
	if instance != null:
		instance.set_meta("component_type", COMPONENT_CHAIN)

# -- Placement -----------------------------------------------------------------

func place(pulley_a: GearComponent, pulley_b: GearComponent) -> void:
	if pulley_a == null or pulley_b == null:
		return
	if not _ensure_sprocket_mode_for_chain_endpoint(pulley_a, true):
		return
	if not _ensure_sprocket_mode_for_chain_endpoint(pulley_b, true):
		return

	var chain_scene := ctx.get_scene(COMPONENT_CHAIN)
	if chain_scene != null:
		var chain_node := chain_scene.instantiate() as Node2D
		if chain_node == null:
			return
		if chain_node.has_method("configure"):
			chain_node.call(
				"configure",
				pulley_a,
				pulley_b,
				ctx.get_node_connection_radius(pulley_a),
				ctx.get_node_connection_radius(pulley_b)
			)
		chain_node.set_meta("component_type", COMPONENT_CHAIN)
		ctx.components_container.add_child(chain_node)
		ctx.emit_gear_placed(chain_node)
		ctx.mark_dirty()
		return

	# Fallback: dynamic script instantiation (no chain scene assigned in editor).
	var chain_script := load(CHAIN_COMPONENT_SCRIPT_PATH)
	if chain_script == null:
		return
	var chain_component = chain_script.new()
	if chain_component == null:
		return
	var chain_wrapper := Node2D.new()
	chain_wrapper.add_child(chain_component)
	chain_component.configure(
		pulley_a,
		pulley_b,
		ctx.get_node_connection_radius(pulley_a),
		ctx.get_node_connection_radius(pulley_b)
	)
	chain_wrapper.set_meta("component_type", COMPONENT_CHAIN)
	ctx.components_container.add_child(chain_wrapper)
	ctx.emit_gear_placed(chain_wrapper)
	ctx.mark_dirty()


func _ensure_sprocket_mode_for_chain_endpoint(gear: GearComponent, emit_feedback: bool) -> bool:
	if gear == null:
		return false
	if _is_sprocket_mode(gear):
		return true

	if _is_conversion_blocked_for_stack(gear):
		if emit_feedback:
			ctx.emit_feedback("%s\n%s" % [CONVERSION_REJECT_MESHED, CONVERSION_REJECT_MESHED_HINT])
		return false

	if gear.has_method("set_pulley_mode"):
		gear.call("set_pulley_mode", true)
	return true


func _can_convert_to_sprocket(gear: GearComponent) -> bool:
	if gear == null:
		return false
	if _is_sprocket_mode(gear):
		return true
	return not _is_conversion_blocked_for_stack(gear)


func _is_conversion_blocked_for_stack(gear: GearComponent) -> bool:
	var stack_nodes := _get_compound_stack_nodes(gear)
	for stack_node_raw in stack_nodes:
		var stack_node := stack_node_raw as GearComponent
		if stack_node == null:
			continue
		if _has_active_mesh_neighbor(stack_node):
			return true
	return false


func _get_compound_stack_nodes(gear: GearComponent) -> Array:
	if gear == null:
		return []

	var root := _get_stack_root_node(gear)
	var stack_nodes: Array = [root]
	var root_id := root.get_instance_id()
	for child in ctx.components_container.get_children():
		var candidate := child as GearComponent
		if candidate == null:
			continue
		if int(candidate.get_meta("stack_parent_id", -1)) == root_id:
			stack_nodes.append(candidate)
	return stack_nodes


func _get_stack_root_node(gear: GearComponent) -> GearComponent:
	var root_id := int(gear.get_meta("stack_root_id", gear.get_instance_id()))
	if root_id == gear.get_instance_id():
		return gear
	for child in ctx.components_container.get_children():
		var candidate := child as GearComponent
		if candidate == null:
			continue
		if candidate.get_instance_id() == root_id:
			return candidate
	return gear


func _has_active_mesh_neighbor(gear: GearComponent) -> bool:
	if gear == null or _is_sprocket_mode(gear):
		return false

	var gear_pos := gear.global_position
	var gear_radius := ctx.get_node_connection_radius(gear)
	for child in ctx.components_container.get_children():
		var neighbor := child as GearComponent
		if neighbor == null or neighbor == gear:
			continue
		if not _is_standard_gear(neighbor):
			continue
		if _is_sprocket_mode(neighbor):
			continue
		if _shares_compound_root(gear, neighbor):
			continue

		var neighbor_radius := ctx.get_node_connection_radius(neighbor)
		var dist := gear_pos.distance_to(neighbor.global_position)
		if absf(dist - (gear_radius + neighbor_radius)) <= PROJECT_PATHS_SCRIPT.DEFAULT_CONNECTION_TOLERANCE:
			return true
	return false


func _shares_compound_root(a: GearComponent, b: GearComponent) -> bool:
	var root_a := int(a.get_meta("stack_root_id", a.get_instance_id()))
	var root_b := int(b.get_meta("stack_root_id", b.get_instance_id()))
	return root_a == root_b


func _is_standard_gear(node: GearComponent) -> bool:
	var ctype := str(node.get_meta("component_type", ""))
	return ctype == COMPONENT_GEAR_SMALL or ctype == COMPONENT_GEAR_MEDIUM or ctype == COMPONENT_GEAR_LARGE


func _is_sprocket_mode(node: GearComponent) -> bool:
	if node == null:
		return false
	if node.has_method("is_sprocket_mode"):
		return bool(node.call("is_sprocket_mode"))
	var pulley_flag: Variant = node.get("_pulley_mode")
	if pulley_flag != null:
		return bool(pulley_flag)
	return false

# -- Query helpers -------------------------------------------------------------

func get_nearest_pulley_at(world_pos: Vector2, max_distance: float) -> GearComponent:
	var nearest: GearComponent = null
	var nearest_distance := max_distance
	for child in ctx.components_container.get_children():
		var node := child as Node2D
		if not is_pulley_candidate(node):
			continue
		var gear := node as GearComponent
		var distance := gear.global_position.distance_to(world_pos)
		if distance < nearest_distance:
			nearest = gear
			nearest_distance = distance
	return nearest

func is_pulley_candidate(node: Node2D) -> bool:
	if node == null or not (node is GearComponent):
		return false
	var ctype := str(node.get_meta("component_type", ""))
	return ctype == COMPONENT_GEAR_SMALL or ctype == COMPONENT_GEAR_MEDIUM or ctype == COMPONENT_GEAR_LARGE

func is_valid_distance(pos_a: Vector2, pos_b: Vector2) -> bool:
	var dist := pos_a.distance_to(pos_b)
	return dist <= PROJECT_PATHS_SCRIPT.CHAIN_MAX_SPAN and dist > 20.0

## Returns the current first pulley (used by PlacementController._draw).
func get_first_pulley() -> GearComponent:
	return _first_pulley
