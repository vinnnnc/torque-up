## GearPlacementHandler
## Handles placement preview, drag auto-place, and stacking for all three gear
## sizes (small, medium, large). Extracted from PlacementController.
extends "res://scripts/features/placement/handlers/placement_handler_base.gd"

const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")

const AUTO_PLACE_INTERVAL_MSEC := 70
const GEAR_DRAG_DEADZONE: float = PROJECT_PATHS_SCRIPT.GEAR_DRAG_DEADZONE

const VALID_PREVIEW_COLOR := Color(0.45, 1.0, 0.45, 0.65)
const INVALID_PREVIEW_COLOR := Color(1.0, 0.35, 0.35, 0.65)

const COMPONENT_GEAR_SMALL := PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_SMALL
const COMPONENT_GEAR_MEDIUM := PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_MEDIUM
const COMPONENT_GEAR_LARGE := PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_LARGE
const MODE_MESH := "mesh"
const MODE_COMPOUND := "compound"
const DENSE_MESH_FASTPATH_COMPONENT_THRESHOLD := 240
const DENSE_MESH_ULTRA_FASTPATH_COMPONENT_THRESHOLD := 420

## Set by PlacementController when this handler is activated (e.g. "gear_small").
var component_id: String = ""

# -- Drag state ----------------------------------------------------------------
var _is_mouse_down: bool = false
var _gear_drag_locked_dir: Vector2 = Vector2.ZERO
var _gear_drag_has_direction_lock: bool = false
var _has_auto_place_anchor: bool = false
var _auto_place_anchor: Vector2 = Vector2.ZERO
var _last_auto_place_msec: int = 0
var _bulk_gear_place_pending_recalc: bool = false
var _focused_mesh_origin_id: int = -1
var _focused_mesh_root_id: int = -1
## Nearest snap-origin node detected during the current preview frame.
## Used by _should_block_mesh_collision to pass through layer-2 gears that
## belong only to the stack being approached, not to other stacks.
var _active_snap_origin_node: Node2D = null

# -- Lifecycle -----------------------------------------------------------------

func activate() -> void:
	_reset_drag()

func deactivate() -> void:
	_reset_drag()

func _reset_drag() -> void:
	_is_mouse_down = false
	_gear_drag_locked_dir = Vector2.ZERO
	_gear_drag_has_direction_lock = false
	_has_auto_place_anchor = false
	_bulk_gear_place_pending_recalc = false
	_active_snap_origin_node = null
	_clear_mesh_focus()

# -- Per-frame -----------------------------------------------------------------

## Update preview node position and socket marker state.
## Called by PlacementController only when the preview needs a refresh.
func update_preview(mouse_pos: Vector2, preview_node: Node2D) -> void:
	if preview_node == null:
		return
	if ctx.active_mode == MODE_COMPOUND:
		_update_compound_preview(mouse_pos, preview_node)
		return
	_update_mesh_preview(mouse_pos, preview_node)


func _update_mesh_preview(mouse_pos: Vector2, preview_node: Node2D) -> void:
	_ensure_mesh_focus_is_valid(mouse_pos)
	var component_count := ctx.components_container.get_child_count() if ctx.components_container != null else 0
	var dense_fastpath := component_count >= DENSE_MESH_FASTPATH_COMPONENT_THRESHOLD
	if component_count >= DENSE_MESH_ULTRA_FASTPATH_COMPONENT_THRESHOLD:
		_active_snap_origin_node = null
		preview_node.global_position = mouse_pos
		preview_node.modulate = VALID_PREVIEW_COLOR
		ctx.socket_markers = []
		ctx.has_active_socket = false
		ctx.active_socket_valid = false
		return
	var selected_radius := get_connection_radius()
	var blocked_positions := ctx.get_cached_blocked_positions()
	var origin_filter := Callable(self, "_is_mesh_origin_compatible")
	var collision_filter := Callable(self, "_should_block_mesh_collision")
	# Pre-resolve the nearest snap origin so the collision filter knows which
	# compound stack is being approached this frame.
	if dense_fastpath:
		_active_snap_origin_node = null
	else:
		var nearest_origin_raw = ctx.placement_rules.get_nearest_snap_origin(
			mouse_pos, ctx.components_container, ctx.get_cached_seed_positions(),
			blocked_positions, selected_radius, origin_filter, collision_filter
		)
		if nearest_origin_raw is Dictionary:
			_active_snap_origin_node = (nearest_origin_raw as Dictionary).get("node", null) as Node2D
		else:
			_active_snap_origin_node = null
	var snap_result: Dictionary = ctx.placement_rules.get_snap_result(
		mouse_pos,
		ctx.components_container,
		ctx.get_cached_seed_positions(),
		blocked_positions,
		selected_radius,
		origin_filter,
		collision_filter
	)
	var snapped_pos: Vector2 = snap_result.get("position", mouse_pos)
	var use_snap := bool(snap_result.get("valid", false))
	preview_node.global_position = snapped_pos if use_snap else mouse_pos

	var preview_is_clear: bool = ctx.placement_rules.can_place_at(
		preview_node.global_position,
		ctx.components_container,
		blocked_positions,
		selected_radius,
		collision_filter
	)
	ctx.socket_markers = [] if dense_fastpath else _build_mesh_arc_markers(mouse_pos, blocked_positions, selected_radius)
	ctx.active_socket_position = snapped_pos
	ctx.has_active_socket = use_snap and snap_result.get("origin", null) != null

	if preview_is_clear:
		preview_node.modulate = VALID_PREVIEW_COLOR
		ctx.active_socket_valid = use_snap
	else:
		preview_node.modulate = INVALID_PREVIEW_COLOR
		ctx.active_socket_valid = false


func _update_compound_preview(mouse_pos: Vector2, preview_node: Node2D) -> void:
	var stack_eval := _evaluate_stack_candidate(mouse_pos)
	var stack_target := stack_eval.get("target", null) as Node2D
	ctx.socket_markers = _build_compound_markers()
	if stack_target:
		preview_node.global_position = stack_target.global_position
		preview_node.rotation = stack_target.rotation
		var stack_valid := bool(stack_eval.get("valid", false))
		preview_node.modulate = VALID_PREVIEW_COLOR if stack_valid else INVALID_PREVIEW_COLOR
		ctx.active_socket_position = stack_target.global_position
		ctx.has_active_socket = true
		ctx.active_socket_valid = stack_valid
		return
	preview_node.global_position = mouse_pos
	preview_node.modulate = INVALID_PREVIEW_COLOR
	ctx.has_active_socket = false
	ctx.active_socket_valid = false

## Called every frame (un-throttled) to drive drag auto-place logic.
## PlacementController must NOT call this when gui_get_hovered_control() != null.
func process(mouse_pos: Vector2) -> void:
	_handle_drag_auto_place(mouse_pos)

## Draw the 8-way direction-lock indicator line.
func draw_overlay(draw_node: Node2D) -> void:
	if not _gear_drag_has_direction_lock or not _has_auto_place_anchor:
		return
	var anchor_local := draw_node.to_local(_auto_place_anchor)
	var projected_local := draw_node.to_local(
		_project_onto_axis(_auto_place_anchor, draw_node.get_global_mouse_position(), _gear_drag_locked_dir)
	)
	draw_node.draw_line(anchor_local, projected_local, Color(0.85, 0.95, 1.0, 0.38), 1.4)
	draw_node.draw_circle(anchor_local, 3.5, Color(0.85, 0.95, 1.0, 0.55))

# -- Input ---------------------------------------------------------------------

func on_mouse_down(world_pos: Vector2) -> void:
	_is_mouse_down = true
	place_gear(world_pos, true)
	_has_auto_place_anchor = true
	_auto_place_anchor = world_pos
	_last_auto_place_msec = Time.get_ticks_msec()

func on_mouse_up(_world_pos: Vector2) -> void:
	_is_mouse_down = false
	if _bulk_gear_place_pending_recalc:
		ctx.emit_component_removed()
	_bulk_gear_place_pending_recalc = false
	_gear_drag_has_direction_lock = false
	_gear_drag_locked_dir = Vector2.ZERO
	_has_auto_place_anchor = false
	ctx.mark_dirty()

func cancel() -> void:
	_reset_drag()

# -- Instance configuration ---------------------------------------------------

func configure_instance(instance: Node2D) -> void:
	if instance == null:
		return
	instance.set_meta("component_type", component_id)
	var visual := instance.get_node_or_null("Visual")
	if visual == null:
		return
	visual.set("outer_radius", get_outer_radius())
	visual.set("visual_mode", "gear")
	visual.set("use_module_profile", true)
	visual.set("module_size", PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_MODULE)
	if visual.has_method("_sync_module_profile"):
		visual.call("_sync_module_profile")

# -- Placement -----------------------------------------------------------------

func place_gear(pos: Vector2, emit_network_update: bool = true) -> void:
	if ctx.active_mode == MODE_COMPOUND:
		_place_compound_gear(pos, emit_network_update)
		return
	_place_meshed_gear(pos, emit_network_update)


func _place_compound_gear(pos: Vector2, emit_network_update: bool = true) -> void:
	var stack_eval := _evaluate_stack_candidate(pos)
	var stack_target := stack_eval.get("target", null) as Node2D
	if stack_target:
		if not bool(stack_eval.get("valid", false)):
			if emit_network_update:
				var reason := str(stack_eval.get("reason", "Cannot place compound stack."))
				ctx.emit_feedback(reason)
			return
		var stack_scene := ctx.get_scene(component_id)
		if stack_scene == null:
			return
		var stacked_gear := stack_scene.instantiate() as Node2D
		configure_instance(stacked_gear)
		stacked_gear.global_position = stack_target.global_position
		stacked_gear.rotation = stack_target.rotation
		stacked_gear.set_meta("stack_parent_id", stack_target.get_instance_id())
		stacked_gear.set_meta("stack_root_id", _get_stack_root_id(stack_target))
		stacked_gear.set_meta("compound_layer", 2)
		stacked_gear.set_meta("compound_added_layers", 1)
		stack_target.set_meta("compound_layer", 1)
		stack_target.set_meta("compound_added_layers", 1)
		if bool(stack_eval.get("behind", false)):
			stacked_gear.z_index = stack_target.z_index - 1
		ctx.components_container.add_child(stacked_gear)
		if stacked_gear.has_method("set_stacked_top") and not bool(stack_eval.get("behind", false)):
			stacked_gear.call("set_stacked_top", true)
		if emit_network_update:
			ctx.emit_gear_placed(stacked_gear)
			ctx.mark_dirty()
		# Return to mesh mode after a successful compound placement.
		if ctx.signal_bus and ctx.signal_bus.has_signal("placement_mode_changed"):
			ctx.signal_bus.placement_mode_changed.emit(MODE_MESH)
		return


func _place_meshed_gear(pos: Vector2, emit_network_update: bool = true) -> void:

	var selected_radius := get_connection_radius()
	var blocked_positions := ctx.get_cached_blocked_positions()
	var origin_filter := Callable(self, "_is_mesh_origin_compatible")
	var collision_filter := Callable(self, "_should_block_mesh_collision")
	var snap_result: Dictionary = ctx.placement_rules.get_snap_result(
		pos,
		ctx.components_container,
		ctx.get_cached_seed_positions(),
		blocked_positions,
		selected_radius,
		origin_filter,
		collision_filter
	)
	var use_snap := bool(snap_result.get("valid", false))
	var snapped_pos: Vector2 = snap_result.get("position", pos)
	var target_pos := snapped_pos if use_snap else pos
	if not ctx.placement_rules.can_place_at(target_pos, ctx.components_container, blocked_positions, selected_radius, collision_filter):
		return

	var chosen_scene := ctx.get_scene(component_id)
	if chosen_scene == null:
		return
	var gear := chosen_scene.instantiate() as Node2D
	configure_instance(gear)
	gear.set_meta("compound_layer", 1)
	if use_snap:
		align_instance_with_origin(gear, target_pos, snap_result.get("origin", {}))
	gear.global_position = target_pos
	ctx.components_container.add_child(gear)
	_clear_mesh_focus()

	if emit_network_update:
		ctx.emit_gear_placed(gear)
		ctx.mark_dirty()

## Rotate gear to mesh with the origin gear's tooth phase.
func align_instance_with_origin(gear: Node2D, snapped_pos: Vector2, origin_data: Variant) -> void:
	if gear == null or not origin_data is Dictionary:
		return
	var origin_dict := origin_data as Dictionary
	var origin_node := origin_dict.get("node", null) as Node2D
	if origin_node == null:
		return
	var connection_angle := (snapped_pos - origin_node.global_position).angle()
	var origin_tooth_count := ctx.get_node_tooth_count(origin_node)
	var gear_tooth_count := ctx.get_node_tooth_count(gear)
	if origin_tooth_count <= 0 or gear_tooth_count <= 0:
		return
	var origin_pitch := TAU / float(origin_tooth_count)
	var gear_pitch := TAU / float(gear_tooth_count)
	var origin_phase_ratio := wrapf((connection_angle - origin_node.rotation) / origin_pitch, 0.0, 1.0)
	var gear_phase := wrapf((0.5 - origin_phase_ratio), 0.0, 1.0) * gear_pitch
	gear.rotation = (connection_angle + PI) - gear_phase

# -- Drag helpers --------------------------------------------------------------

func _handle_drag_auto_place(mouse_world_pos: Vector2) -> void:
	if not _is_mouse_down:
		_has_auto_place_anchor = false
		_gear_drag_has_direction_lock = false
		_gear_drag_locked_dir = Vector2.ZERO
		return

	if not _has_auto_place_anchor:
		_has_auto_place_anchor = true
		_auto_place_anchor = mouse_world_pos
		_last_auto_place_msec = Time.get_ticks_msec()
		return

	if not _gear_drag_has_direction_lock:
		if _auto_place_anchor.distance_to(mouse_world_pos) < GEAR_DRAG_DEADZONE:
			return
		_gear_drag_locked_dir = _snap_direction_to_8way((mouse_world_pos - _auto_place_anchor).normalized())
		_gear_drag_has_direction_lock = true
		_auto_place_anchor = mouse_world_pos
		return

	var effective_pos := _project_onto_axis(_auto_place_anchor, mouse_world_pos, _gear_drag_locked_dir)
	var min_step := maxf(18.0, get_connection_radius() * 1.35)
	if _auto_place_anchor.distance_to(effective_pos) < min_step:
		return

	var now_msec := Time.get_ticks_msec()
	if now_msec - _last_auto_place_msec < AUTO_PLACE_INTERVAL_MSEC:
		return

	var count_before := ctx.components_container.get_child_count()
	place_gear(effective_pos, false)
	if ctx.components_container.get_child_count() > count_before:
		_auto_place_anchor = effective_pos
		_last_auto_place_msec = now_msec
		_bulk_gear_place_pending_recalc = true

# -- Stack helpers -------------------------------------------------------------

func _evaluate_stack_candidate(world_pos: Vector2) -> Dictionary:
	if ctx.active_mode != MODE_COMPOUND:
		return {}
	var selected_rank := _get_size_rank(component_id)
	if selected_rank < 0:
		return {}

	var nearest_target: Node2D = null
	var nearest_distance := PROJECT_PATHS_SCRIPT.STACK_PICK_DISTANCE
	for child in ctx.components_container.get_children():
		var candidate := child as Node2D
		if candidate == null or not _is_standard_gear(candidate):
			continue
		if _get_node_layer(candidate) != 1:
			continue
		var distance := candidate.global_position.distance_to(world_pos)
		if distance > nearest_distance:
			continue
		nearest_distance = distance
		nearest_target = candidate

	if nearest_target == null:
		return {}

	if nearest_target.has_meta("stack_parent_id"):
		return {
			"target": nearest_target,
			"valid": false,
			"reason": "Compound stack limit reached (max 2 layers)."
		}

	if _has_stacked_child(nearest_target):
		return {
			"target": nearest_target,
			"valid": false,
			"reason": "Compound stack limit reached (max 2 layers)."
		}

	var candidate_rank := _get_size_rank(str(nearest_target.get_meta("component_type", "")))
	if candidate_rank < 0:
		return {}

	if selected_rank > candidate_rank:
		# Any larger gear may go behind any smaller gear.
		return {
			"target": nearest_target,
			"valid": true,
			"behind": true
		}

	if selected_rank < candidate_rank:
		return {
			"target": nearest_target,
			"valid": true
		}

	# Same-size stack: allowed only when interface types differ (gear+sprocket).
	var candidate_is_sprocket := _is_sprocket_mode(nearest_target)
	if candidate_is_sprocket:
		return {
			"target": nearest_target,
			"valid": true
		}

	return {
		"target": nearest_target,
		"valid": false,
		"reason": "Same-size gear stack blocked unless one layer is sprocket mode."
	}

func _has_stacked_child(base_gear: Node2D) -> bool:
	if base_gear == null:
		return false
	var base_id := base_gear.get_instance_id()
	for child in ctx.components_container.get_children():
		var component := child as Node2D
		if component == null or component == base_gear:
			continue
		if int(component.get_meta("stack_parent_id", -1)) == base_id:
			return true
	return false

func _get_stack_root_id(node: Node2D) -> int:
	if node == null:
		return -1
	return int(node.get_meta("stack_root_id", node.get_instance_id()))

func _is_standard_gear(node: Node2D) -> bool:
	if node == null:
		return false
	var ctype := str(node.get_meta("component_type", ""))
	return ctype == COMPONENT_GEAR_SMALL or ctype == COMPONENT_GEAR_MEDIUM or ctype == COMPONENT_GEAR_LARGE


func _get_node_layer(node: Node2D) -> int:
	if node == null:
		return 1
	if node.has_meta("compound_layer"):
		return clampi(int(node.get_meta("compound_layer")), 1, 2)
	if int(node.get_meta("stack_parent_id", -1)) >= 0:
		return 2
	return 1


func _is_mesh_origin_compatible(origin: Dictionary) -> bool:
	var origin_node := origin.get("node", null) as Node2D
	if origin_node == null:
		return _focused_mesh_origin_id < 0
	if not _is_standard_gear(origin_node):
		return _focused_mesh_origin_id < 0
	if _focused_mesh_origin_id < 0:
		# Only layer-1 gears are default snap origins; layer-2 (compound behind) are skipped.
		return _get_node_layer(origin_node) == 1
	return origin_node.get_instance_id() == _focused_mesh_origin_id


func _build_mesh_arc_markers(mouse_pos: Vector2, blocked_positions: Array, selected_radius: float) -> Array:
	var origin_filter := Callable(self, "_is_mesh_origin_compatible")
	var collision_filter := Callable(self, "_should_block_mesh_collision")
	var nearest_origin = ctx.placement_rules.get_nearest_snap_origin(
		mouse_pos,
		ctx.components_container,
		ctx.get_cached_seed_positions(),
		blocked_positions,
		selected_radius,
		origin_filter,
		collision_filter
	)
	if nearest_origin == null:
		return []
	var origin := nearest_origin as Dictionary
	if origin.is_empty():
		return []
	return _build_origin_arc_markers(origin, blocked_positions, selected_radius)


func _build_origin_arc_markers(origin: Dictionary, blocked_positions: Array, selected_radius: float) -> Array:
	var markers: Array = []
	if origin.has("fixed_direction"):
		var fixed_direction := origin.get("fixed_direction", Vector2.RIGHT) as Vector2
		if fixed_direction.length_squared() <= 0.0001:
			fixed_direction = Vector2.RIGHT
		else:
			fixed_direction = fixed_direction.normalized()
		var base_angle := fixed_direction.angle()
		markers.append({
			"kind": "arc_segment",
			"center": origin.get("position", Vector2.ZERO),
			"radius": float(origin.get("radius", 0.0)) + selected_radius,
			"start_angle": base_angle - 0.26,
			"end_angle": base_angle + 0.26
		})
		return markers

	var origin_pos: Vector2 = origin.get("position", Vector2.ZERO)
	var origin_radius: float = float(origin.get("radius", 0.0))
	var marker_radius := origin_radius + selected_radius
	var sample_count: int = maxi(12, int(ctx.placement_rules.marker_samples))
	var open_start := -INF
	var previous_open := false
	for sample_index in range(sample_count + 1):
		var angle := TAU * (float(sample_index) / float(sample_count))
		var candidate := origin_pos + Vector2.RIGHT.rotated(angle) * marker_radius
		var is_open: bool = not bool(ctx.placement_rules._is_too_close(candidate, ctx.components_container, blocked_positions, selected_radius, Callable(self, "_should_block_mesh_collision")))
		if is_open and not previous_open:
			open_start = angle
		elif previous_open and not is_open:
			markers.append({
				"kind": "arc_segment",
				"center": origin_pos,
				"radius": marker_radius,
				"start_angle": open_start,
				"end_angle": angle - (TAU / float(sample_count)) * 0.2
			})
			open_start = -INF
		previous_open = is_open
	if previous_open and open_start > -INF:
		markers.append({
			"kind": "arc_segment",
			"center": origin_pos,
			"radius": marker_radius,
			"start_angle": open_start,
			"end_angle": TAU
		})
	return markers


func _build_compound_markers() -> Array:
	var markers: Array = []
	for child in ctx.components_container.get_children():
		var candidate := child as Node2D
		if candidate == null or not _is_standard_gear(candidate):
			continue
		if _get_node_layer(candidate) != 1:
			continue
		var eval := _evaluate_stack_candidate(candidate.global_position)
		if not bool(eval.get("valid", false)):
			continue
		markers.append({
			"kind": "ring",
			"center": candidate.global_position,
			"radius": maxf(ctx.get_node_outer_radius(candidate), get_outer_radius()) + 4.0
		})
	return markers


func _should_block_mesh_collision(node: Node2D) -> bool:
	if node == null:
		return true
	if not _is_standard_gear(node):
		return true

	var origin_node: Node2D = null
	if _focused_mesh_origin_id >= 0:
		origin_node = _find_standard_gear_by_id(_focused_mesh_origin_id)
	elif _active_snap_origin_node != null:
		origin_node = _active_snap_origin_node

	if origin_node != null:
		# The origin itself always blocks to prevent placing directly on top of it.
		if node.get_instance_id() == origin_node.get_instance_id():
			return true
		# Same-stack partners are transparent regardless of layer.
		# This covers both the normal case (layer-2 behind-gear transparent while
		# layer-1 is the origin) and the Z-focus case (layer-1 front-gear transparent
		# while layer-2 is the Z-focused origin, so its orbit is not blocked).
		if _get_stack_root_id(node) == _get_stack_root_id(origin_node):
			return false
		# Different compound stacks are always solid.
		return true

	# No active snap origin: layer-1 foreground gears block, layer-2 behind-gears
	# are transparent (they are always physically inside their layer-1 partner).
	return _get_node_layer(node) == 1


func cycle_mesh_origin_focus(mouse_pos: Vector2) -> String:
	if ctx.active_mode != MODE_MESH:
		return "Origin cycling is only available in Mesh mode."
	var cycle_data := _get_cycle_candidates(mouse_pos)
	var candidates := cycle_data.get("candidates", []) as Array
	if candidates.is_empty():
		_clear_mesh_focus()
		return "No compound gear under cursor to cycle."
	var root_id := int(cycle_data.get("root_id", -1))
	var next_index := 1
	if _focused_mesh_root_id == root_id and _focused_mesh_origin_id >= 0:
		for idx in range(candidates.size()):
			var node := candidates[idx] as Node2D
			if node == null:
				continue
			if node.get_instance_id() == _focused_mesh_origin_id:
				next_index = (idx + 1) % candidates.size()
				break
	elif candidates.size() <= 1:
		next_index = 0
	if next_index < 0 or next_index >= candidates.size():
		next_index = 0
	var next_node := candidates[next_index] as Node2D
	if next_node == null:
		_clear_mesh_focus()
		return "No valid cycle target."
	_focused_mesh_origin_id = next_node.get_instance_id()
	_focused_mesh_root_id = root_id
	var ctype := str(next_node.get_meta("component_type", ""))
	var label := "Gear"
	if ctype == COMPONENT_GEAR_SMALL:
		label = "Small Gear"
	elif ctype == COMPONENT_GEAR_MEDIUM:
		label = "Medium Gear"
	elif ctype == COMPONENT_GEAR_LARGE:
		label = "Large Gear"
	return "Mesh focus: %s (%d/%d)" % [label, next_index + 1, candidates.size()]


func _get_cycle_candidates(mouse_pos: Vector2) -> Dictionary:
	var best_root_id := -1
	var best_root_distance := INF
	var grouped: Dictionary = {}
	for child in ctx.components_container.get_children():
		var node := child as Node2D
		if node == null or not _is_standard_gear(node):
			continue
		var root_id := _get_stack_root_id(node)
		if root_id < 0:
			continue
		if not grouped.has(root_id):
			grouped[root_id] = []
		(grouped[root_id] as Array).append(node)
		var d := node.global_position.distance_to(mouse_pos)
		if d < best_root_distance:
			best_root_distance = d
			best_root_id = root_id
	if best_root_id < 0 or not grouped.has(best_root_id):
		return {"root_id": -1, "candidates": []}
	var candidates := grouped[best_root_id] as Array
	if candidates.size() <= 1:
		return {"root_id": -1, "candidates": []}
	candidates.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		if a == null:
			return false
		if b == null:
			return true
		var la := _get_node_layer(a)
		var lb := _get_node_layer(b)
		if la != lb:
			return la < lb
		return ctx.get_node_outer_radius(a) > ctx.get_node_outer_radius(b)
	)
	return {"root_id": best_root_id, "candidates": candidates}


func _find_standard_gear_by_id(instance_id: int) -> Node2D:
	if instance_id < 0:
		return null
	for child in ctx.components_container.get_children():
		var node := child as Node2D
		if node == null or not _is_standard_gear(node):
			continue
		if node.get_instance_id() == instance_id:
			return node
	return null


func _ensure_mesh_focus_is_valid(mouse_pos: Vector2 = Vector2.ZERO) -> void:
	if _focused_mesh_origin_id < 0:
		return
	var node := _find_standard_gear_by_id(_focused_mesh_origin_id)
	if node == null:
		_clear_mesh_focus()
		return
	# Auto-clear when the cursor has moved away from the focused compound stack.
	if mouse_pos != Vector2.ZERO and node.global_position.distance_to(mouse_pos) > PROJECT_PATHS_SCRIPT.STACK_PICK_DISTANCE * 2.0:
		_clear_mesh_focus()


func _clear_mesh_focus() -> void:
	_focused_mesh_origin_id = -1
	_focused_mesh_root_id = -1

func _is_sprocket_mode(node: Node2D) -> bool:
	if node == null:
		return false
	if node.has_method("is_sprocket_mode"):
		return bool(node.call("is_sprocket_mode"))
	var pulley_flag: Variant = node.get("_pulley_mode")
	if pulley_flag != null:
		return bool(pulley_flag)
	return false

func _get_size_rank(ctype: String) -> int:
	match ctype:
		COMPONENT_GEAR_SMALL:
			return 0
		COMPONENT_GEAR_MEDIUM:
			return 1
		COMPONENT_GEAR_LARGE:
			return 2
		_:
			return -1

# -- Geometry helpers ----------------------------------------------------------

func _snap_direction_to_8way(dir: Vector2) -> Vector2:
	var angle := dir.angle()
	var snapped_angle: float = round(angle / (PI * 0.25)) * (PI * 0.25)
	return Vector2.RIGHT.rotated(snapped_angle)

func _project_onto_axis(origin: Vector2, point: Vector2, axis: Vector2) -> Vector2:
	var delta := point - origin
	return origin + axis * delta.dot(axis)

# -- Radius helpers ------------------------------------------------------------

func get_outer_radius() -> float:
	match component_id:
		COMPONENT_GEAR_SMALL:
			return PROJECT_PATHS_SCRIPT.SMALL_GEAR_OUTER_RADIUS
		COMPONENT_GEAR_LARGE:
			return PROJECT_PATHS_SCRIPT.LARGE_GEAR_OUTER_RADIUS
		_:
			return PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS

func get_connection_radius() -> float:
	return maxf(2.0, get_outer_radius() - PROJECT_PATHS_SCRIPT.GEAR_MESH_CONTACT_MARGIN)
