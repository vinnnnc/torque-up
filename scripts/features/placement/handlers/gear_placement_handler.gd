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
const DENSE_MESH_FASTPATH_COMPONENT_THRESHOLD := 240
const DENSE_MESH_ULTRA_FASTPATH_COMPONENT_THRESHOLD := 420
const MESH_CONTACT_EPSILON := 1.4
const SNAP_CONTACT_EPSILON: float = PROJECT_PATHS_SCRIPT.DEFAULT_CONNECTION_TOLERANCE

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
## World position of the preview gear this frame — used by draw_overlay.
var _preview_world_pos: Vector2 = Vector2.ZERO
var _preview_is_snapped: bool = false

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
	_preview_is_snapped = false
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
	if preview_is_clear and _would_trigger_snap_jam(preview_node.global_position, selected_radius):
		preview_is_clear = false
	ctx.socket_markers = [] if dense_fastpath else _build_mesh_arc_markers(mouse_pos, blocked_positions, selected_radius)
	ctx.active_socket_position = snapped_pos
	ctx.has_active_socket = use_snap and snap_result.get("origin", null) != null

	_preview_world_pos = preview_node.global_position
	_preview_is_snapped = use_snap

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

## Draw direction-lock line (drag) and gear rotation arc-arrows (snap preview).
func draw_overlay(draw_node: Node2D) -> void:
	# -- Drag direction-lock line --
	if _gear_drag_has_direction_lock and _has_auto_place_anchor:
		var anchor_local := draw_node.to_local(_auto_place_anchor)
		var projected_local := draw_node.to_local(
			_project_onto_axis(_auto_place_anchor, draw_node.get_global_mouse_position(), _gear_drag_locked_dir)
		)
		draw_node.draw_line(anchor_local, projected_local, Color(0.85, 0.95, 1.0, 0.38), 1.4)
		draw_node.draw_circle(anchor_local, 3.5, Color(0.85, 0.95, 1.0, 0.55))

	# -- Gear rotation arc-arrows (only when snapped near an existing mesh origin) --
	if not _preview_is_snapped or ctx == null or ctx.components_container == null:
		return

	var pulse_alpha := 0.55 + 0.45 * sin(Time.get_ticks_msec() / 300.0)
	var selected_radius := get_connection_radius()
	var candidate_required_sign: float = 0.0
	var has_conflict := false

	# Gather meshing neighbors (gears + network anchors) and determine candidate spin.
	var meshing_neighbors := _collect_meshing_spin_neighbors(_preview_world_pos, selected_radius)
	for neighbor_data_raw in meshing_neighbors:
		var neighbor_data := neighbor_data_raw as Dictionary
		var nspin := float(neighbor_data.get("spin", 0.0))
		var required := -nspin
		if candidate_required_sign == 0.0:
			candidate_required_sign = required
		elif signf(required) != signf(candidate_required_sign):
			has_conflict = true

	if meshing_neighbors.is_empty():
		return

	var color_ok := Color(0.3, 1.0, 0.4, pulse_alpha)
	var color_bad := Color(1.0, 0.25, 0.25, pulse_alpha)

	# Draw arc-arrow on each meshing neighbor showing its spin direction.
	for neighbor_data_raw in meshing_neighbors:
		var neighbor_data := neighbor_data_raw as Dictionary
		var neighbor := neighbor_data.get("node", null) as Node2D
		if neighbor == null:
			continue
		var nspin := float(neighbor_data.get("spin", 0.0))
		var n_radius := float(neighbor_data.get("radius", selected_radius))
		var arrow_color := color_bad if has_conflict else color_ok
		_draw_spin_arc_arrow(draw_node, neighbor.global_position, n_radius * 0.80, nspin, arrow_color)

	# Draw arc-arrow on the preview position showing expected candidate spin.
	if absf(candidate_required_sign) >= 0.5:
		var preview_color := color_bad if has_conflict else color_ok
		_draw_spin_arc_arrow(draw_node, _preview_world_pos, selected_radius * 0.80, candidate_required_sign, preview_color)


## Draw a pulsing arc with an arrowhead indicating spin direction (sign > 0 = CCW, sign < 0 = CW).
func _draw_spin_arc_arrow(draw_node: Node2D, world_center: Vector2, radius: float, spin_sign: float, color: Color) -> void:
	var center := draw_node.to_local(world_center)
	var arc_span := PI * 1.1  # slightly more than half-circle
	# Choose start angle so the arc sits in the top half of the gear for readability.
	var start_angle := -PI * 0.55 if spin_sign >= 0.0 else PI * 0.55 - arc_span
	var end_angle := start_angle + arc_span * signf(spin_sign)
	var steps := clampi(int(ceil(radius * absf(end_angle - start_angle) / 6.0)), 8, 32)
	draw_node.draw_arc(center, radius, start_angle, end_angle, steps, color, 2.0)

	# Arrowhead: small triangle at the arc endpoint.
	var tip_angle := end_angle
	var tip := center + Vector2(cos(tip_angle), sin(tip_angle)) * radius
	var tangent_dir := Vector2(-sin(tip_angle), cos(tip_angle)) * signf(spin_sign)
	var head_len := clampf(radius * 0.28, 5.0, 14.0)
	var left := tip - tangent_dir * head_len + Vector2(-tangent_dir.y, tangent_dir.x) * head_len * 0.4
	var right := tip - tangent_dir * head_len - Vector2(-tangent_dir.y, tangent_dir.x) * head_len * 0.4
	draw_node.draw_colored_polygon(PackedVector2Array([tip, left, right]), color)

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
	if not use_snap and _should_promote_near_snap(pos, snap_result, blocked_positions, selected_radius, collision_filter):
		use_snap = true
		snapped_pos = snap_result.get("position", pos)
	var target_pos := snapped_pos if use_snap else pos
	if not ctx.placement_rules.can_place_at(target_pos, ctx.components_container, blocked_positions, selected_radius, collision_filter):
		return
	if _would_trigger_snap_jam(target_pos, selected_radius):
		ctx.emit_feedback("Unable to place here: snap point would jam this gear.")
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


func _would_trigger_snap_jam(target_pos: Vector2, selected_radius: float) -> bool:
	if ctx == null or ctx.components_container == null:
		return false

	# Collect spin requirements from all meshing neighbors (gears + anchors).
	# Meshing gears reverse direction, so required_sign = -neighbor_spin_sign.
	# If two neighbors require opposite signs, placement creates an irresolvable conflict.
	var required_sign: float = 0.0  # 0 = undecided
	for neighbor_data_raw in _collect_meshing_spin_neighbors(target_pos, selected_radius):
		var neighbor_data := neighbor_data_raw as Dictionary
		var this_required := -float(neighbor_data.get("spin", 0.0))

		if required_sign == 0.0:
			required_sign = this_required
		elif signf(this_required) != signf(required_sign):
			return true  # two neighbors require opposite directions → jam

	return false


func _should_promote_near_snap(
	mouse_pos: Vector2,
	snap_result: Dictionary,
	blocked_positions: Array,
	selected_radius: float,
	collision_filter: Callable
) -> bool:
	if ctx == null or ctx.placement_rules == null or snap_result.is_empty():
		return false
	if snap_result.get("origin", null) == null:
		return false

	var candidate_pos := snap_result.get("position", mouse_pos) as Vector2
	var base_snap_distance := PROJECT_PATHS_SCRIPT.DEFAULT_SNAP_MAX_DISTANCE
	if ctx.snap_max_distance > 0.0:
		base_snap_distance = ctx.snap_max_distance
	var assist_distance := PROJECT_PATHS_SCRIPT.PLACEMENT_NEAR_SNAP_ASSIST_DISTANCE
	if candidate_pos.distance_to(mouse_pos) > (base_snap_distance + assist_distance):
		return false

	return ctx.placement_rules.can_place_at(
		candidate_pos,
		ctx.components_container,
		blocked_positions,
		selected_radius,
		collision_filter
	)


func _collect_meshing_spin_neighbors(target_pos: Vector2, selected_radius: float) -> Array:
	var neighbors: Array = []
	if ctx == null or ctx.components_container == null:
		return neighbors

	var seen_ids: Dictionary = {}
	for child in ctx.components_container.get_children():
		_collect_single_neighbor_spin(child as Node2D, target_pos, selected_radius, neighbors, seen_ids)

	for seed_raw in ctx.get_cached_seed_positions():
		if not seed_raw is Dictionary:
			continue
		var seed_node := (seed_raw as Dictionary).get("node", null) as Node2D
		_collect_single_neighbor_spin(seed_node, target_pos, selected_radius, neighbors, seen_ids)

	return neighbors


func _collect_single_neighbor_spin(
	neighbor: Node2D,
	target_pos: Vector2,
	selected_radius: float,
	neighbors: Array,
	seen_ids: Dictionary
) -> void:
	if neighbor == null or not neighbor.has_method("get_spin_direction"):
		return
	if not _is_standard_gear(neighbor) and not _is_network_anchor(neighbor):
		return

	var neighbor_id := neighbor.get_instance_id()
	if seen_ids.has(neighbor_id):
		return

	var neighbor_radius := ctx.get_node_connection_radius(neighbor)
	var tangent_distance := neighbor_radius + selected_radius
	var distance_to_target := neighbor.global_position.distance_to(target_pos)
	if absf(distance_to_target - tangent_distance) > SNAP_CONTACT_EPSILON:
		return

	var neighbor_spin := float(neighbor.call("get_spin_direction"))
	if absf(neighbor_spin) < 0.5:
		return

	seen_ids[neighbor_id] = true
	neighbors.append({
		"node": neighbor,
		"radius": neighbor_radius,
		"spin": neighbor_spin,
	})


func _is_network_anchor(node: Node2D) -> bool:
	if node == null or ctx == null or ctx.components_container == null:
		return false
	if node.get_parent() == ctx.components_container:
		return false
	return node.name == "CentralEngine" or node.name.begins_with("Power")


func _required_candidate_rotation_for_neighbor(
	target_pos: Vector2,
	neighbor: Node2D,
	candidate_tooth_count: int
) -> float:
	var connection_angle := (target_pos - neighbor.global_position).angle()
	var origin_tooth_count := ctx.get_node_tooth_count(neighbor)
	if origin_tooth_count <= 0:
		return connection_angle + PI

	var origin_pitch := TAU / float(origin_tooth_count)
	var candidate_pitch := TAU / float(candidate_tooth_count)
	var origin_phase_ratio := wrapf((connection_angle - neighbor.rotation) / origin_pitch, 0.0, 1.0)
	var candidate_phase := wrapf((0.5 - origin_phase_ratio), 0.0, 1.0) * candidate_pitch
	return (connection_angle + PI) - candidate_phase

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
