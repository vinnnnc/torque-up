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
	# Pre-resolve the nearest snap origin for collision filtering in dense layouts.
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
	_place_meshed_gear(pos, emit_network_update)


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

func _is_standard_gear(node: Node2D) -> bool:
	if node == null:
		return false
	var ctype := str(node.get_meta("component_type", ""))
	return ctype == COMPONENT_GEAR_SMALL or ctype == COMPONENT_GEAR_MEDIUM or ctype == COMPONENT_GEAR_LARGE


func _is_mesh_origin_compatible(origin: Dictionary) -> bool:
	var origin_node := origin.get("node", null) as Node2D
	if origin_node == null:
		return true
	if _is_standard_gear(origin_node):
		return true
	# Keep network anchors (power nodes / engine) valid snap origins.
	if ctx != null and ctx.components_container != null and origin_node.get_parent() != ctx.components_container:
		return true
	return false


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


func _should_block_mesh_collision(node: Node2D) -> bool:
	return true


func cycle_mesh_origin_focus(mouse_pos: Vector2) -> String:
	return "Origin cycling is disabled in mesh-only mode."


func _ensure_mesh_focus_is_valid(_mouse_pos: Vector2 = Vector2.ZERO) -> void:
	return


func _clear_mesh_focus() -> void:
	return

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
