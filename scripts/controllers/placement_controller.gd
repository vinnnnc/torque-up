extends Node2D
class_name PlacementController

const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")
const PLACEMENT_RULES_SCRIPT = preload("res://scripts/features/placement/placement_rules.gd")
const NETWORK_SERVICE_SCRIPT = preload("res://scripts/features/network/network_service.gd")
const CHAIN_COMPONENT_SCRIPT_PATH := "res://scripts/components/belt.gd"
const SHAFT_COMPONENT_SCRIPT_PATH := "res://scripts/components/shaft_link.gd"

@export var gear_scene: PackedScene
@export var components_container_path: NodePath = PROJECT_PATHS_SCRIPT.COMPONENTS_CONTAINER_PATH
@export var power_source_path: NodePath = PROJECT_PATHS_SCRIPT.POWER_SOURCE_PATH
@export var socket_count: int = PROJECT_PATHS_SCRIPT.DEFAULT_SOCKET_COUNT
@export var socket_radius: float = PROJECT_PATHS_SCRIPT.DEFAULT_SOCKET_RADIUS
@export var snap_max_distance: float = PROJECT_PATHS_SCRIPT.DEFAULT_SNAP_MAX_DISTANCE
@export var placement_clearance: float = PROJECT_PATHS_SCRIPT.DEFAULT_PLACEMENT_CLEARANCE

const VALID_PREVIEW_COLOR := Color(0.45, 1.0, 0.45, 0.65)
const INVALID_PREVIEW_COLOR := Color(1.0, 0.35, 0.35, 0.65)
const SOCKET_MARKER_COLOR := Color(0.34, 0.72, 1.0, 0.35)
const SOCKET_MARKER_OUTLINE := Color(0.48, 0.86, 1.0, 0.95)
const ACTIVE_SOCKET_COLOR := Color(0.95, 0.97, 1.0, 0.95)
const COMPONENT_GEAR_SMALL := PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_SMALL
const COMPONENT_GEAR_MEDIUM := PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_MEDIUM
const COMPONENT_GEAR_LARGE := PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_LARGE
const COMPONENT_SHAFT := PROJECT_PATHS_SCRIPT.COMPONENT_SHAFT
const COMPONENT_CHAIN := PROJECT_PATHS_SCRIPT.COMPONENT_CHAIN
const COMPONENT_DELETE := PROJECT_PATHS_SCRIPT.COMPONENT_DELETE
const COMPONENT_FLYWHEEL := PROJECT_PATHS_SCRIPT.COMPONENT_FLYWHEEL
const COMPONENT_CLUTCH := PROJECT_PATHS_SCRIPT.COMPONENT_CLUTCH
const COMPONENT_DIFFERENTIAL := PROJECT_PATHS_SCRIPT.COMPONENT_DIFFERENTIAL

var _placement_rules = PLACEMENT_RULES_SCRIPT.new()
var _preview_gear: Node2D
var _socket_markers: Array = []
var _active_socket_position := Vector2.ZERO
var _has_active_socket := false
var _active_socket_valid := false
var _network_service = NETWORK_SERVICE_SCRIPT.new()
var _selected_component: String = ""
var _belt_first_pulley: GearComponent = null
var _shaft_first_gear: GearComponent = null
var _is_left_mouse_down: bool = false
var _has_auto_place_anchor: bool = false
var _auto_place_anchor := Vector2.ZERO
var _last_auto_place_msec: int = 0
var _last_auto_delete_msec: int = 0
var _cached_seed_positions: Array = []
var _cached_blocked_positions: Array = []
var _placement_context_dirty: bool = true
var _last_preview_mouse_pos := Vector2.ZERO
var _has_last_preview_mouse: bool = false
var _last_preview_refresh_msec: int = 0
var _bulk_gear_place_pending_recalc: bool = false
@onready var _components_container: Node2D = get_node(components_container_path)
@onready var _power_source: Node2D = get_node_or_null(power_source_path)
@onready var _central_engine: Node2D = get_node_or_null("../Network/CentralEngine")
@onready var _network_node: Node2D = get_node_or_null("../Network")
@onready var _barriers_node: Node2D = get_node_or_null("../Barriers")
@onready var _signal_bus: Node = get_node_or_null("/root/SignalBus")

const AUTO_PLACE_INTERVAL_MSEC := 70
const AUTO_DELETE_INTERVAL_MSEC := 55
const PREVIEW_REFRESH_INTERVAL_MSEC := 33
const DRAG_RELEASE_DEADZONE := 14.0
const FLYWHEEL_OUTER_RADIUS := PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS * 1.45
const CLUTCH_OUTER_RADIUS := PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS * 1.05
const DIFFERENTIAL_OUTER_RADIUS := PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS * 1.25
const SHAFT_PLACEMENT_BLOCK_RADIUS := PROJECT_PATHS_SCRIPT.SHAFT_MIN_CONNECTION_RADIUS
## Pixels the mouse must travel before a gear drag direction locks to 8-way.
const GEAR_DRAG_DEADZONE: float = PROJECT_PATHS_SCRIPT.GEAR_DRAG_DEADZONE

var _belt_drag_start_mouse := Vector2.ZERO
var _shaft_drag_start_mouse := Vector2.ZERO
## 8-way lock state for gear drag auto-placement.
var _gear_drag_locked_dir := Vector2.ZERO
var _gear_drag_has_direction_lock: bool = false


func _ready() -> void:
	_placement_rules.socket_count = socket_count
	_placement_rules.socket_radius = socket_radius
	_placement_rules.snap_max_distance = snap_max_distance
	_placement_rules.placement_clearance = placement_clearance
	_create_preview_gear()
	if _signal_bus and not _signal_bus.component_selected.is_connected(_on_component_selected):
		_signal_bus.component_selected.connect(_on_component_selected)
	if _signal_bus and not _signal_bus.gear_placed.is_connected(_on_layout_changed):
		_signal_bus.gear_placed.connect(_on_layout_changed)
	if _signal_bus and not _signal_bus.component_removed.is_connected(_on_layout_changed):
		_signal_bus.component_removed.connect(_on_layout_changed)
	_update_preview_visibility()


func _process(_delta: float) -> void:
	if _preview_gear == null:
		return

	var mouse_world_pos := get_global_mouse_position()

	if not _is_selected_placeable_component():
		var had_preview_artifacts := (not _socket_markers.is_empty()) or _has_active_socket
		_socket_markers.clear()
		_has_active_socket = false
		_update_preview_visibility()
		_handle_delete_drag(mouse_world_pos)
		if had_preview_artifacts:
			queue_redraw()
		return

	var should_refresh_preview := _should_refresh_preview(mouse_world_pos)
	if _selected_component == COMPONENT_SHAFT:
		if should_refresh_preview:
			if _is_left_mouse_down and _shaft_first_gear != null:
				_update_shaft_drag_preview(mouse_world_pos)
			else:
				_update_shaft_preview(mouse_world_pos)
			_record_preview_refresh(mouse_world_pos)
			queue_redraw()
		_handle_delete_drag(mouse_world_pos)
		return

	if _selected_component == COMPONENT_CHAIN:
		if should_refresh_preview:
			_update_belt_preview(mouse_world_pos)
			_record_preview_refresh(mouse_world_pos)
			queue_redraw()
		_handle_gear_drag_auto_place(mouse_world_pos)
		_handle_delete_drag(mouse_world_pos)
		return

	if not should_refresh_preview:
		_handle_gear_drag_auto_place(mouse_world_pos)
		_handle_delete_drag(mouse_world_pos)
		return

	var stack_target := _get_stack_target(mouse_world_pos)
	if stack_target:
		_preview_gear.global_position = stack_target.global_position
		_preview_gear.rotation = stack_target.rotation
		_preview_gear.modulate = VALID_PREVIEW_COLOR
		_socket_markers = [stack_target.global_position]
		_active_socket_position = stack_target.global_position
		_has_active_socket = true
		_active_socket_valid = true
		_update_preview_visibility()
		_record_preview_refresh(mouse_world_pos)
		queue_redraw()
		return

	var seed_positions := _get_cached_seed_positions()
	var blocked_positions := _get_cached_blocked_positions()
	var selected_radius := _get_selected_component_connection_radius()
	var snap_result: Dictionary = _placement_rules.get_snap_result(
		mouse_world_pos,
		_components_container,
		seed_positions,
		blocked_positions,
		selected_radius
	)
	var snapped_pos: Vector2 = snap_result.get("position", mouse_world_pos)
	var use_snap := bool(snap_result.get("valid", false))
	var preview_pos := snapped_pos if use_snap else mouse_world_pos
	_preview_gear.global_position = preview_pos
	if use_snap and (_selected_component == COMPONENT_CLUTCH or _selected_component == COMPONENT_DIFFERENTIAL):
		_align_gear_with_origin(_preview_gear, snapped_pos, snap_result.get("origin", {}))
	var preview_is_clear := _placement_rules.can_place_at(
		preview_pos,
		_components_container,
		blocked_positions,
		selected_radius
	)
	_socket_markers = _placement_rules.get_nearest_available_socket_positions(
		mouse_world_pos,
		_components_container,
		seed_positions,
		blocked_positions,
		selected_radius
	)
	_active_socket_position = snapped_pos
	_has_active_socket = use_snap and bool(snap_result.get("origin", null) != null)
	_update_preview_visibility()

	if preview_is_clear:
		_preview_gear.modulate = VALID_PREVIEW_COLOR
		_active_socket_valid = use_snap
	else:
		_preview_gear.modulate = INVALID_PREVIEW_COLOR
		_active_socket_valid = false

	_record_preview_refresh(mouse_world_pos)
	queue_redraw()
	_handle_gear_drag_auto_place(mouse_world_pos)
	_handle_delete_drag(mouse_world_pos)


func _draw() -> void:
	for marker_world_pos in _socket_markers:
		if not marker_world_pos is Vector2:
			continue

		var marker_local := to_local(marker_world_pos)
		draw_circle(marker_local, 4.5, SOCKET_MARKER_COLOR)
		draw_arc(marker_local, 4.5, 0.0, TAU, 20, SOCKET_MARKER_OUTLINE, 1.6)

	if _has_active_socket:
		var active_local := to_local(_active_socket_position)
		var ring_color := ACTIVE_SOCKET_COLOR if _active_socket_valid else INVALID_PREVIEW_COLOR
		draw_arc(active_local, 8.0, 0.0, TAU, 28, ring_color, 2.0)

	if _selected_component == COMPONENT_SHAFT and _has_active_socket and _shaft_first_gear == null:
		var origin_local := to_local(_active_socket_position)
		var mouse_local := to_local(get_global_mouse_position())
		draw_line(origin_local, mouse_local, Color(0.8, 0.92, 1.0, 0.65), 1.8)

	# Shaft drag preview: lock one end on the first clicked gear.
	if _selected_component == COMPONENT_SHAFT and _shaft_first_gear:
		var first_shaft_local := to_local(_shaft_first_gear.global_position)
		var shaft_target := get_global_mouse_position()
		var second_gear := _get_nearest_gear_at(shaft_target, maxf(28.0, snap_max_distance))
		if second_gear and second_gear != _shaft_first_gear:
			shaft_target = second_gear.global_position
		var target_local := to_local(shaft_target)
		draw_line(first_shaft_local, target_local, Color(0.76, 0.9, 1.0, 0.55), 2.0)
		draw_circle(first_shaft_local, 26.0, Color(0.76, 0.9, 1.0, 0.22))

	if _selected_component == COMPONENT_CHAIN:
		_draw_belt_preview()

	# 8-way drag lock indicator: show direction line while dragging gears.
	if _gear_drag_has_direction_lock and _has_auto_place_anchor and _is_selected_gear_component():
		var anchor_local := to_local(_auto_place_anchor)
		var projected_local := to_local(_project_onto_axis(_auto_place_anchor, get_global_mouse_position(), _gear_drag_locked_dir))
		draw_line(anchor_local, projected_local, Color(0.85, 0.95, 1.0, 0.38), 1.4)
		draw_circle(anchor_local, 3.5, Color(0.85, 0.95, 1.0, 0.55))

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_cancel_active_drags()
		return

	if event is not InputEventMouseButton:
		return

	var mouse_event := event as InputEventMouseButton
	if mouse_event == null:
		return

	if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
		_cancel_active_drags()
		return

	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	_is_left_mouse_down = mouse_event.pressed
	if not mouse_event.pressed:
		if _selected_component == COMPONENT_CHAIN:
			_complete_belt_drag(get_global_mouse_position())
		if _selected_component == COMPONENT_SHAFT:
			_complete_shaft_drag(get_global_mouse_position())
		_belt_drag_start_mouse = Vector2.ZERO
		_shaft_drag_start_mouse = Vector2.ZERO
		_has_auto_place_anchor = false
		_gear_drag_has_direction_lock = false
		_gear_drag_locked_dir = Vector2.ZERO
		if _bulk_gear_place_pending_recalc and _signal_bus:
			_signal_bus.component_removed.emit()
		_bulk_gear_place_pending_recalc = false
		_placement_context_dirty = true
		return

	# Ignore world placement/deletion clicks when interacting with UI controls.
	if get_viewport().gui_get_hovered_control() != null:
		return

	if _selected_component == COMPONENT_DELETE:
		delete_component_at(get_global_mouse_position())
		_last_auto_delete_msec = Time.get_ticks_msec()
		return

	if not _is_selected_placeable_component():
		return

	if _selected_component == COMPONENT_SHAFT:
		_start_shaft_drag(get_global_mouse_position())
		return

	if _selected_component == COMPONENT_CHAIN:
		_start_belt_drag(get_global_mouse_position())
		return

	place_gear(get_global_mouse_position(), true)
	if _is_selected_gear_component():
		_has_auto_place_anchor = true
		_auto_place_anchor = get_global_mouse_position()
		_last_auto_place_msec = Time.get_ticks_msec()


func _handle_gear_drag_auto_place(mouse_world_pos: Vector2) -> void:
	if not _is_left_mouse_down or not _is_selected_gear_component():
		_has_auto_place_anchor = false
		_gear_drag_has_direction_lock = false
		_gear_drag_locked_dir = Vector2.ZERO
		return

	if get_viewport().gui_get_hovered_control() != null:
		return

	if not _has_auto_place_anchor:
		_has_auto_place_anchor = true
		_auto_place_anchor = mouse_world_pos
		_last_auto_place_msec = Time.get_ticks_msec()
		return

	# Wait for deadzone to clear before locking a direction.
	if not _gear_drag_has_direction_lock:
		if _auto_place_anchor.distance_to(mouse_world_pos) < GEAR_DRAG_DEADZONE:
			return
		# Snap to nearest 8-way axis and lock.
		_gear_drag_locked_dir = _snap_direction_to_8way((mouse_world_pos - _auto_place_anchor).normalized())
		_gear_drag_has_direction_lock = true
		# Reset anchor so the first gear after locking originates cleanly.
		_auto_place_anchor = mouse_world_pos
		return

	# Project mouse position onto the locked axis so the chain stays straight.
	var effective_pos := _project_onto_axis(_auto_place_anchor, mouse_world_pos, _gear_drag_locked_dir)

	var min_step := maxf(18.0, _get_selected_component_connection_radius() * 1.35)
	if _auto_place_anchor.distance_to(effective_pos) < min_step:
		return

	var now_msec := Time.get_ticks_msec()
	if now_msec - _last_auto_place_msec < AUTO_PLACE_INTERVAL_MSEC:
		return

	var count_before := _components_container.get_child_count()
	place_gear(effective_pos, false)
	if _components_container.get_child_count() > count_before:
		_auto_place_anchor = effective_pos
		_last_auto_place_msec = now_msec
		_bulk_gear_place_pending_recalc = true


func _handle_delete_drag(mouse_world_pos: Vector2) -> void:
	if _selected_component != COMPONENT_DELETE or not _is_left_mouse_down:
		return

	if get_viewport().gui_get_hovered_control() != null:
		return

	var now_msec := Time.get_ticks_msec()
	if now_msec - _last_auto_delete_msec < AUTO_DELETE_INTERVAL_MSEC:
		return

	delete_component_at(mouse_world_pos)
	_last_auto_delete_msec = now_msec


func _should_refresh_preview(mouse_world_pos: Vector2) -> bool:
	if _placement_context_dirty:
		return true

	if not _has_last_preview_mouse:
		return true

	if _last_preview_mouse_pos.distance_squared_to(mouse_world_pos) >= 1.0:
		return true

	if _selected_component == COMPONENT_CHAIN and _belt_first_pulley:
		return (Time.get_ticks_msec() - _last_preview_refresh_msec) >= PREVIEW_REFRESH_INTERVAL_MSEC

	return false


func _record_preview_refresh(mouse_world_pos: Vector2) -> void:
	_last_preview_mouse_pos = mouse_world_pos
	_has_last_preview_mouse = true
	_last_preview_refresh_msec = Time.get_ticks_msec()


func _get_cached_seed_positions() -> Array:
	if _placement_context_dirty:
		_cached_seed_positions = _get_seed_positions()
		_cached_blocked_positions = _get_blocked_positions()
		_placement_context_dirty = false
	return _cached_seed_positions


func _get_cached_blocked_positions() -> Array:
	if _placement_context_dirty:
		_cached_seed_positions = _get_seed_positions()
		_cached_blocked_positions = _get_blocked_positions()
		_placement_context_dirty = false
	return _cached_blocked_positions


func _create_preview_gear() -> void:
	if gear_scene == null:
		return

	_preview_gear = gear_scene.instantiate() as Node2D
	if _preview_gear == null:
		return

	_preview_gear.z_index = 100
	add_child(_preview_gear)
	_configure_gear_instance(_preview_gear)
	_update_preview_visibility()


func _on_component_selected(component_id: String) -> void:
	if (_selected_component == COMPONENT_CHAIN and component_id != COMPONENT_CHAIN) or (_selected_component == COMPONENT_SHAFT and component_id != COMPONENT_SHAFT):
		_cancel_active_drags()

	_selected_component = component_id
	_socket_markers.clear()
	_has_active_socket = false
	_active_socket_valid = false
	_has_last_preview_mouse = false
	_configure_gear_instance(_preview_gear)
	_update_preview_visibility()
	queue_redraw()


func _on_layout_changed(_component: Node2D = null) -> void:
	_placement_context_dirty = true
	_has_last_preview_mouse = false


func _update_preview_visibility() -> void:
	if _preview_gear:
		_preview_gear.visible = _is_selected_placeable_component() and _selected_component != COMPONENT_SHAFT

func place_gear(pos: Vector2, emit_network_update: bool = true) -> void:
	if gear_scene == null or not _is_selected_placeable_component():
		return

	var stack_target := _get_stack_target(pos)
	if stack_target:
		var stacked_gear := gear_scene.instantiate() as Node2D
		_configure_gear_instance(stacked_gear)
		stacked_gear.global_position = stack_target.global_position
		stacked_gear.rotation = stack_target.rotation
		stacked_gear.set_meta("stack_parent_id", stack_target.get_instance_id())
		stacked_gear.set_meta("stack_root_id", _get_stack_root_id(stack_target))
		_components_container.add_child(stacked_gear)
		if stacked_gear.has_method("set_stacked_top"):
			stacked_gear.call("set_stacked_top", true)

		var stack_signal_bus := get_node_or_null("/root/SignalBus")
		if emit_network_update and stack_signal_bus:
			stack_signal_bus.gear_placed.emit(stacked_gear)
		if emit_network_update:
			_placement_context_dirty = true
		return

	var selected_radius := _get_selected_component_connection_radius()
	var blocked_positions := _get_cached_blocked_positions()

	var snap_result: Dictionary = _placement_rules.get_snap_result(
		pos,
		_components_container,
		_get_cached_seed_positions(),
		blocked_positions,
		selected_radius
	)
	var use_snap := bool(snap_result.get("valid", false))
	var snapped_pos: Vector2 = snap_result.get("position", pos)
	var target_pos := snapped_pos if use_snap else pos
	if not _placement_rules.can_place_at(target_pos, _components_container, blocked_positions, selected_radius):
		return

	var gear := gear_scene.instantiate() as Node2D
	_configure_gear_instance(gear)
	if use_snap:
		_align_gear_with_origin(gear, target_pos, snap_result.get("origin", {}))
	gear.global_position = target_pos
	_components_container.add_child(gear)

	var signal_bus := get_node_or_null("/root/SignalBus")
	if emit_network_update and signal_bus:
		signal_bus.gear_placed.emit(gear)
	if emit_network_update:
		_placement_context_dirty = true


func delete_component_at(world_pos: Vector2) -> void:
	var nearest_component: Node2D = null
	var nearest_distance := INF
	var delete_radius := placement_clearance * 0.7

	for child in _components_container.get_children():
		var component := child as Node2D
		if component == null:
			continue

		var distance := _get_delete_distance_for_component(component, world_pos)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_component = component

	if nearest_component == null or nearest_distance > delete_radius:
		return

	var belts_to_remove := _collect_attached_belts(nearest_component)
	for belt_node in belts_to_remove:
		if belt_node and belt_node != nearest_component:
			belt_node.queue_free()

	if _signal_bus:
		nearest_component.tree_exited.connect(_on_deleted_component_exited, CONNECT_ONE_SHOT)
	nearest_component.queue_free()
	_placement_context_dirty = true


func _collect_attached_belts(component: Node2D) -> Array:
	var attached_belts: Array = []
	if component == null:
		return attached_belts

	var ctype := str(component.get_meta("component_type", ""))
	if ctype == COMPONENT_CHAIN or ctype == PROJECT_PATHS_SCRIPT.COMPONENT_BELT or ctype == COMPONENT_SHAFT:
		attached_belts.append(component)
		return attached_belts

	for child in _components_container.get_children():
		var candidate := child as Node2D
		if candidate == null:
			continue
		var candidate_type := str(candidate.get_meta("component_type", ""))
		if candidate_type == COMPONENT_SHAFT and candidate.has_meta("shaft_end_a_id"):
			var a := int(candidate.get_meta("shaft_end_a_id", -1))
			var b := int(candidate.get_meta("shaft_end_b_id", -1))
			var cid := component.get_instance_id()
			if a == cid or b == cid:
				attached_belts.append(candidate)
			continue
		if candidate_type != COMPONENT_CHAIN and candidate_type != PROJECT_PATHS_SCRIPT.COMPONENT_BELT:
			continue

		for connector_child in candidate.get_children():
			if connector_child == null:
				continue
			var pulley_a := connector_child.get("pulley_a") as Node2D
			var pulley_b := connector_child.get("pulley_b") as Node2D
			if pulley_a == component or pulley_b == component:
				attached_belts.append(candidate)
				break

	return attached_belts


func _get_delete_distance_for_component(component: Node2D, world_pos: Vector2) -> float:
	if component == null:
		return INF

	var component_type := str(component.get_meta("component_type", ""))
	if component_type == COMPONENT_CHAIN or component_type == PROJECT_PATHS_SCRIPT.COMPONENT_BELT or component_type == COMPONENT_SHAFT:
		for child in component.get_children():
			if child and child.has_method("get_distance_to_world_point"):
				return float(child.call("get_distance_to_world_point", world_pos))

	return component.global_position.distance_to(world_pos)


func _on_deleted_component_exited() -> void:
	if _signal_bus:
		_signal_bus.component_removed.emit()


func _get_stack_target(world_pos: Vector2) -> Node2D:
	if not _is_selected_gear_component():
		return null

	var selected_rank := _get_component_size_rank(_selected_component)
	if selected_rank <= 0:
		return null

	var nearest_target: Node2D = null
	var nearest_distance := PROJECT_PATHS_SCRIPT.STACK_PICK_DISTANCE
	for child in _components_container.get_children():
		var candidate := child as Node2D
		if candidate == null:
			continue
		if not _is_standard_gear_component(candidate):
			continue
		if candidate.has_meta("stack_parent_id"):
			continue

		var candidate_rank := _get_component_size_rank(str(candidate.get_meta("component_type", "")))
		if candidate_rank <= selected_rank:
			continue
		if _has_stacked_child(candidate):
			continue

		var distance := candidate.global_position.distance_to(world_pos)
		if distance <= nearest_distance:
			nearest_distance = distance
			nearest_target = candidate

	return nearest_target


func _has_stacked_child(base_gear: Node2D) -> bool:
	if base_gear == null:
		return false

	var base_id := base_gear.get_instance_id()
	for child in _components_container.get_children():
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


func _is_selected_gear_component() -> bool:
	return _selected_component == COMPONENT_GEAR_SMALL or _selected_component == COMPONENT_GEAR_MEDIUM or _selected_component == COMPONENT_GEAR_LARGE


## Snap a unit direction vector to the nearest 45-degree axis (8-way).
func _snap_direction_to_8way(dir: Vector2) -> Vector2:
	var angle := dir.angle()
	var snapped_angle: float = round(angle / (PI * 0.25)) * (PI * 0.25)
	return Vector2.RIGHT.rotated(snapped_angle)


## Project a world-space point onto a ray from origin along axis, returning
## the closest point on that infinite line.
func _project_onto_axis(origin: Vector2, point: Vector2, axis: Vector2) -> Vector2:
	var delta := point - origin
	var projected_length := delta.dot(axis)
	return origin + axis * projected_length


func _is_standard_gear_component(node: Node2D) -> bool:
	if node == null:
		return false

	var component_type := str(node.get_meta("component_type", ""))
	return component_type == COMPONENT_GEAR_SMALL or component_type == COMPONENT_GEAR_MEDIUM or component_type == COMPONENT_GEAR_LARGE


func _get_component_size_rank(component_type: String) -> int:
	match component_type:
		COMPONENT_GEAR_SMALL:
			return 0
		COMPONENT_GEAR_MEDIUM:
			return 1
		COMPONENT_GEAR_LARGE:
			return 2
		_:
			return -1


func _get_blocked_positions() -> Array:
	var positions: Array = []
	if _network_node == null:
		return positions
	var active_power_sources := _get_active_power_sources_for_placement()
	var active_source_ids: Dictionary = {}
	for source_raw in active_power_sources:
		var source := source_raw as Node2D
		if source:
			active_source_ids[source.get_instance_id()] = true

	for child in _network_node.get_children():
		var node := child as Node2D
		if node == null or node == _components_container:
			continue

		if node.name == "CentralEngine":
			positions.append({"position": node.global_position, "radius": _get_node_connection_radius(node)})
			continue

		if node.name.begins_with("Power"):
			if active_source_ids.has(node.get_instance_id()):
				continue
			var node_radius := _get_node_connection_radius(node)
			positions.append({"position": node.global_position, "radius": node_radius})

	if _barriers_node:
		for child in _barriers_node.get_children():
			var barrier := child as Node2D
			if barrier == null:
				continue

			if barrier.has_method("get_block_data"):
				var block_data: Variant = barrier.call("get_block_data")
				if block_data is Dictionary:
					positions.append(block_data)
				continue

			var radius_value: Variant = barrier.get("radius")
			if radius_value != null:
				positions.append({
					"position": barrier.global_position,
					"radius": maxf(1.0, float(radius_value))
				})

	return positions


func _get_seed_positions() -> Array:
	var positions: Array = []
	for anchor_raw in _get_network_anchor_nodes_for_placement():
		var anchor := anchor_raw as Node2D
		if anchor == null:
			continue
		positions.append({
			"position": anchor.global_position,
			"radius": _get_node_connection_radius(anchor),
			"node": anchor
		})

	return positions


func _get_network_anchor_nodes_for_placement() -> Array:
	var anchors: Array = []
	if _network_node == null:
		if _power_source:
			anchors.append(_power_source)
		return anchors

	for child in _network_node.get_children():
		var node := child as Node2D
		if node == null or node == _components_container:
			continue
		if node == _central_engine or node.name.begins_with("Power"):
			anchors.append(node)

	if anchors.is_empty() and _power_source:
		anchors.append(_power_source)

	return anchors


func _get_active_power_sources_for_placement() -> Array:
	var active_sources: Array = []
	if _network_node == null:
		return active_sources

	var all_power_sources: Array = []
	for child in _network_node.get_children():
		var node := child as Node2D
		if node == null or node == _components_container:
			continue
		if node.name.begins_with("Power"):
			all_power_sources.append(node)

	return all_power_sources


func _get_node_outer_radius(node: Node2D) -> float:
	if node == null:
		return PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS

	var visual := node.get_node_or_null("Visual")
	if visual == null:
		return PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS

	var radius_value: Variant = visual.get("outer_radius")
	if radius_value == null:
		return PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS

	return float(radius_value)


func _get_node_connection_radius(node: Node2D) -> float:
	if _is_shaft_component(node):
		if node and node.has_meta("shaft_end_a_id"):
			return 2.0
		return _get_shaft_block_radius(node)

	var outer_radius := _get_node_outer_radius(node)
	return maxf(2.0, outer_radius - PROJECT_PATHS_SCRIPT.GEAR_MESH_CONTACT_MARGIN)


func _get_shaft_block_radius(node: Node2D) -> float:
	if node and node.has_meta("shaft_block_radius"):
		return maxf(2.0, float(node.get_meta("shaft_block_radius")))

	if node and node.has_meta("shaft_connection_radius"):
		var legacy_radius := float(node.get_meta("shaft_connection_radius"))
		return maxf(2.0, minf(legacy_radius, SHAFT_PLACEMENT_BLOCK_RADIUS))

	return SHAFT_PLACEMENT_BLOCK_RADIUS


func _align_gear_with_origin(gear: Node2D, snapped_pos: Vector2, origin_data: Variant) -> void:
	if gear == null or not origin_data is Dictionary:
		return

	var origin_dict := origin_data as Dictionary
	var origin_node := origin_dict.get("node", null) as Node2D
	if origin_node == null:
		return

	var connection_angle := (snapped_pos - origin_node.global_position).angle()
	if _selected_component == COMPONENT_SHAFT:
		gear.rotation = connection_angle
		return
	if _selected_component == COMPONENT_CLUTCH:
		var toward_origin := wrapf(connection_angle + PI, -PI, PI)
		gear.rotation = toward_origin + (PI * 0.5)
		return
	if _selected_component == COMPONENT_DIFFERENTIAL:
		var toward_origin := wrapf(connection_angle + PI, -PI, PI)
		var input_ports := [-2.35, -0.79]
		gear.rotation = _rotation_from_best_port_alignment(toward_origin, input_ports, gear.rotation)
		return

	var origin_tooth_count := _get_node_tooth_count(origin_node)
	var gear_tooth_count := _get_node_tooth_count(gear)
	if origin_tooth_count <= 0 or gear_tooth_count <= 0:
		return

	var origin_pitch := TAU / float(origin_tooth_count)
	var gear_pitch := TAU / float(gear_tooth_count)
	var origin_phase_ratio := wrapf((connection_angle - origin_node.rotation) / origin_pitch, 0.0, 1.0)
	var gear_phase := wrapf((0.5 - origin_phase_ratio), 0.0, 1.0) * gear_pitch
	gear.rotation = (connection_angle + PI) - gear_phase


func _rotation_from_best_port_alignment(target_world_angle: float, local_port_angles: Array, current_rotation: float) -> float:
	if local_port_angles.is_empty():
		return target_world_angle

	var best_rotation := target_world_angle - float(local_port_angles[0])
	var best_delta := INF
	for port_raw in local_port_angles:
		var port_angle := float(port_raw)
		var candidate := target_world_angle - port_angle
		var delta := absf(wrapf(candidate - current_rotation, -PI, PI))
		if delta < best_delta:
			best_delta = delta
			best_rotation = candidate

	return wrapf(best_rotation, -PI, PI)


func _get_node_tooth_count(node: Node2D) -> int:
	if node == null:
		return 0

	var visual := node.get_node_or_null("Visual")
	if visual == null:
		return 0

	var tooth_value: Variant = visual.get("tooth_count")
	if tooth_value == null:
		return 0

	return int(tooth_value)


func _is_selected_placeable_component() -> bool:
	return _selected_component == COMPONENT_GEAR_SMALL or _selected_component == COMPONENT_GEAR_MEDIUM or _selected_component == COMPONENT_GEAR_LARGE or _selected_component == COMPONENT_SHAFT or _selected_component == COMPONENT_CHAIN or _selected_component == COMPONENT_FLYWHEEL or _selected_component == COMPONENT_CLUTCH or _selected_component == COMPONENT_DIFFERENTIAL


func _get_selected_gear_radius() -> float:
	match _selected_component:
		COMPONENT_GEAR_SMALL:
			return PROJECT_PATHS_SCRIPT.SMALL_GEAR_OUTER_RADIUS
		COMPONENT_GEAR_LARGE:
			return PROJECT_PATHS_SCRIPT.LARGE_GEAR_OUTER_RADIUS
		COMPONENT_GEAR_MEDIUM:
			return PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS
		COMPONENT_SHAFT:
			return PROJECT_PATHS_SCRIPT.SHAFT_OUTER_RADIUS
		COMPONENT_FLYWHEEL:
			return FLYWHEEL_OUTER_RADIUS
		COMPONENT_CLUTCH:
			return CLUTCH_OUTER_RADIUS
		COMPONENT_DIFFERENTIAL:
			return DIFFERENTIAL_OUTER_RADIUS
		_:
			return PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS


func _get_selected_component_connection_radius() -> float:
	var outer_radius := _get_selected_gear_radius()
	return maxf(2.0, outer_radius - PROJECT_PATHS_SCRIPT.GEAR_MESH_CONTACT_MARGIN)


func _configure_gear_instance(gear: Node2D) -> void:
	if gear == null:
		return

	gear.set_meta("component_type", _selected_component)

	var visual := gear.get_node_or_null("Visual")
	if visual == null:
		return

	visual.set("outer_radius", _get_selected_gear_radius())
	if _selected_component == COMPONENT_SHAFT:
		visual.set("use_module_profile", false)
		visual.set("visual_mode", "shaft")
		visual.set("shaft_module_size", PROJECT_PATHS_SCRIPT.SHAFT_SHAPE_MODULE)
		visual.set("inner_radius", 4.8)
		visual.set("hub_radius", 3.8)
		visual.set("tooth_count", 0)
	elif _selected_component == COMPONENT_FLYWHEEL:
		visual.set("visual_mode", "flywheel")
		visual.set("use_module_profile", false)
		visual.set("inner_radius", _get_selected_gear_radius() * 0.78)
		visual.set("hub_radius", _get_selected_gear_radius() * 0.24)
		visual.set("body_color", Color(0.34, 0.37, 0.41, 1.0))
		visual.set("tooth_color", Color(0.52, 0.56, 0.60, 1.0))
	elif _selected_component == COMPONENT_CLUTCH:
		visual.set("visual_mode", "clutch")
		visual.set("use_module_profile", false)
		visual.set("inner_radius", _get_selected_gear_radius() * 0.56)
		visual.set("hub_radius", _get_selected_gear_radius() * 0.2)
		visual.set("body_color", Color(0.64, 0.55, 0.36, 1.0))
		visual.set("tooth_color", Color(0.86, 0.72, 0.46, 1.0))
	elif _selected_component == COMPONENT_DIFFERENTIAL:
		visual.set("visual_mode", "differential")
		visual.set("use_module_profile", false)
		visual.set("inner_radius", _get_selected_gear_radius() * 0.62)
		visual.set("hub_radius", _get_selected_gear_radius() * 0.22)
		visual.set("body_color", Color(0.41, 0.47, 0.55, 1.0))
		visual.set("tooth_color", Color(0.62, 0.7, 0.8, 1.0))
	else:
		visual.set("visual_mode", "gear")
		visual.set("use_module_profile", true)
		# Explicitly set module_size so the constant in gear_visual is always honoured.
		visual.set("module_size", PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_MODULE)
	if visual.has_method("_sync_module_profile"):
		visual.call("_sync_module_profile")


func _update_shaft_preview(mouse_world_pos: Vector2) -> void:
	_socket_markers.clear()
	for child in _components_container.get_children():
		var gear := child as Node2D
		if _is_belt_pulley_candidate(gear):
			_socket_markers.append(gear.global_position)

	_has_active_socket = false
	_active_socket_valid = false


func _update_shaft_drag_preview(mouse_world_pos: Vector2) -> void:
	if _shaft_first_gear == null:
		_update_shaft_preview(mouse_world_pos)
		return

	var second_gear := _get_nearest_gear_at(mouse_world_pos, maxf(28.0, snap_max_distance))
	var valid := second_gear != null and second_gear != _shaft_first_gear and not _shaft_link_exists(_shaft_first_gear, second_gear)
	_has_active_socket = true
	_active_socket_position = _shaft_first_gear.global_position
	_active_socket_valid = valid
	_socket_markers = [_shaft_first_gear.global_position]
	if second_gear and second_gear != _shaft_first_gear:
		_socket_markers.append(second_gear.global_position)


func place_shaft(world_pos: Vector2) -> void:
	var start_origin := _get_nearest_origin(world_pos, PROJECT_PATHS_SCRIPT.SHAFT_PICK_DISTANCE)
	if start_origin.is_empty():
		return

	var shaft_data := _compute_shaft_data_from_origin(start_origin, world_pos)
	if shaft_data.is_empty():
		return

	var shaft_pos: Vector2 = shaft_data["position"]
	var shaft_rotation: float = shaft_data["rotation"]
	var shaft_outer_radius: float = shaft_data["outer_radius"]
	var shaft_connection_radius: float = shaft_data["connection_radius"]
	if not _is_shaft_candidate_clear(shaft_pos, shaft_connection_radius, [start_origin]):
		return

	var shaft := gear_scene.instantiate() as Node2D
	_configure_gear_instance(shaft)
	_configure_shaft_runtime_visual(shaft, shaft_outer_radius)
	shaft.set_meta("shaft_connection_radius", shaft_connection_radius)
	shaft.set_meta("shaft_block_radius", SHAFT_PLACEMENT_BLOCK_RADIUS)
	shaft.global_position = shaft_pos
	shaft.rotation = shaft_rotation
	_components_container.add_child(shaft)

	if _signal_bus:
		_signal_bus.gear_placed.emit(shaft)
	_placement_context_dirty = true


func _start_belt_drag(world_pos: Vector2) -> void:
	var nearest_gear := _get_nearest_gear_at(world_pos, maxf(28.0, snap_max_distance))
	if nearest_gear == null:
		return

	if _belt_first_pulley and _belt_first_pulley != nearest_gear:
		_belt_first_pulley.set_pulley_mode(false)

	_belt_first_pulley = nearest_gear
	_belt_first_pulley.set_pulley_mode(true)
	_belt_drag_start_mouse = world_pos
	queue_redraw()


func _complete_belt_drag(world_pos: Vector2) -> void:
	if _belt_first_pulley == null:
		return

	if _belt_drag_start_mouse.distance_to(world_pos) < DRAG_RELEASE_DEADZONE:
		_belt_first_pulley.set_pulley_mode(false)
		_belt_first_pulley = null
		queue_redraw()
		return

	var second_pulley := _get_nearest_gear_at(world_pos, maxf(28.0, snap_max_distance))
	if second_pulley == null or second_pulley == _belt_first_pulley:
		_belt_first_pulley.set_pulley_mode(false)
		_belt_first_pulley = null
		queue_redraw()
		return

	if _is_valid_belt_distance(_belt_first_pulley.global_position, second_pulley.global_position):
		second_pulley.set_pulley_mode(true)
		place_belt(_belt_first_pulley, second_pulley)

	_belt_first_pulley.set_pulley_mode(false)
	_belt_first_pulley = null
	queue_redraw()


func _start_shaft_drag(world_pos: Vector2) -> void:
	_shaft_first_gear = _get_nearest_gear_at(world_pos, maxf(28.0, snap_max_distance))
	_shaft_drag_start_mouse = world_pos
	queue_redraw()


func _complete_shaft_drag(world_pos: Vector2) -> void:
	if _shaft_first_gear == null:
		return

	if _shaft_drag_start_mouse.distance_to(world_pos) < DRAG_RELEASE_DEADZONE:
		_shaft_first_gear = null
		queue_redraw()
		return

	var second_gear := _get_nearest_gear_at(world_pos, maxf(28.0, snap_max_distance))
	if second_gear and second_gear != _shaft_first_gear:
		place_shaft_between_gears(_shaft_first_gear, second_gear)

	_shaft_first_gear = null
	queue_redraw()


func _cancel_active_drags() -> void:
	if _belt_first_pulley:
		_belt_first_pulley.set_pulley_mode(false)
	_belt_first_pulley = null
	_shaft_first_gear = null
	_belt_drag_start_mouse = Vector2.ZERO
	_shaft_drag_start_mouse = Vector2.ZERO
	_gear_drag_has_direction_lock = false
	_gear_drag_locked_dir = Vector2.ZERO
	queue_redraw()


func place_shaft_between_gears(first_gear: GearComponent, second_gear: GearComponent) -> void:
	if first_gear == null or second_gear == null:
		return
	if _shaft_link_exists(first_gear, second_gear):
		return

	var shaft_script := load(SHAFT_COMPONENT_SCRIPT_PATH)
	if shaft_script == null:
		return

	var shaft_data := _compute_shaft_data_between_gears(first_gear, second_gear)
	if shaft_data.is_empty():
		return

	var shaft_pos: Vector2 = shaft_data["position"]
	var shaft_rotation: float = shaft_data["rotation"]
	var shaft_connection_radius: float = shaft_data["connection_radius"]
	var shaft := Node2D.new()
	var shaft_component: Node = shaft_script.new()
	if shaft_component == null:
		return
	shaft.add_child(shaft_component)
	if shaft_component.has_method("configure"):
		shaft_component.configure(first_gear, second_gear)
	shaft.set_meta("component_type", PROJECT_PATHS_SCRIPT.COMPONENT_SHAFT)
	shaft.set_meta("shaft_connection_radius", shaft_connection_radius)
	shaft.set_meta("shaft_block_radius", 2.0)
	shaft.set_meta("shaft_end_a_id", first_gear.get_instance_id())
	shaft.set_meta("shaft_end_b_id", second_gear.get_instance_id())
	shaft.global_position = shaft_pos
	shaft.rotation = shaft_rotation
	_components_container.add_child(shaft)

	if _signal_bus:
		_signal_bus.gear_placed.emit(shaft)
	_placement_context_dirty = true


func _shaft_link_exists(first_gear: GearComponent, second_gear: GearComponent) -> bool:
	if first_gear == null or second_gear == null:
		return false

	var first_id := first_gear.get_instance_id()
	var second_id := second_gear.get_instance_id()
	for child in _components_container.get_children():
		var node := child as Node2D
		if node == null:
			continue
		if str(node.get_meta("component_type", "")) != COMPONENT_SHAFT:
			continue
		if not node.has_meta("shaft_end_a_id"):
			continue
		var a := int(node.get_meta("shaft_end_a_id", -1))
		var b := int(node.get_meta("shaft_end_b_id", -1))
		if (a == first_id and b == second_id) or (a == second_id and b == first_id):
			return true

	return false


func _compute_shaft_data_between_gears(first_gear: GearComponent, second_gear: GearComponent) -> Dictionary:
	if first_gear == null or second_gear == null:
		return {}

	var first_pos := first_gear.global_position
	var second_pos := second_gear.global_position
	var center_delta := second_pos - first_pos
	if center_delta.length_squared() <= 0.0001:
		return {}

	var dir := center_delta.normalized()
	var first_radius := _get_node_connection_radius(first_gear)
	var second_radius := _get_node_connection_radius(second_gear)
	var start_contact := first_pos + (dir * first_radius)
	var end_contact := second_pos - (dir * second_radius)
	var span := end_contact - start_contact
	var shaft_connection_radius := span.length() * 0.5
	if shaft_connection_radius < PROJECT_PATHS_SCRIPT.SHAFT_MIN_CONNECTION_RADIUS:
		return {}

	shaft_connection_radius = minf(shaft_connection_radius, PROJECT_PATHS_SCRIPT.SHAFT_MAX_CONNECTION_RADIUS)
	var shaft_pos := first_pos.lerp(second_pos, 0.5)
	var shaft_rotation := dir.angle()
	var visual_outer_radius := first_pos.distance_to(second_pos) * 0.5
	return {
		"position": shaft_pos,
		"rotation": shaft_rotation,
		"connection_radius": shaft_connection_radius,
		"outer_radius": shaft_connection_radius + PROJECT_PATHS_SCRIPT.GEAR_MESH_CONTACT_MARGIN,
		"visual_outer_radius": visual_outer_radius
	}


func place_belt_step(world_pos: Vector2) -> void:
	# Use click-pick distance so a specific gear can be chosen precisely.
	var nearest_gear := _get_nearest_gear_at(world_pos, maxf(28.0, snap_max_distance))
	
	if nearest_gear == null:
		return

	if _belt_first_pulley == null:
		# First click - select first pulley
		_belt_first_pulley = nearest_gear
		_belt_first_pulley.set_pulley_mode(true)
		queue_redraw()
		return

	if _belt_first_pulley == nearest_gear:
		# Clicked same pulley again - deselect
		_belt_first_pulley.set_pulley_mode(false)
		_belt_first_pulley = null
		queue_redraw()
		return

	# Second click - validate and place belt
	var second_pulley := nearest_gear
	
	if not _is_valid_belt_distance(_belt_first_pulley.global_position, second_pulley.global_position):
		# Keep first selected so the player can choose another target.
		queue_redraw()
		return

	# Distance valid - create belt and set pulley modes
	second_pulley.set_pulley_mode(true)
	place_belt(_belt_first_pulley, second_pulley)
	# Keep pulley mode ON since they're now connected
	_belt_first_pulley = null
	queue_redraw()


func _update_belt_preview(mouse_world_pos: Vector2) -> void:
	"""Update belt placement preview based on mouse position and selected pulleys."""
	_socket_markers.clear()
	_has_active_socket = false
	_active_socket_valid = false

	if _belt_first_pulley == null:
		# No first pulley selected - highlight available pulleys
		for child in _components_container.get_children():
			var gear := child as Node2D
			if not _is_belt_pulley_candidate(gear):
				continue
			_socket_markers.append(gear.global_position)
	else:
		# First pulley selected - show only valid second pulleys.
		for child in _components_container.get_children():
			var candidate := child as Node2D
			if not _is_belt_pulley_candidate(candidate):
				continue
			if candidate == _belt_first_pulley:
				continue
			if _is_valid_belt_distance(_belt_first_pulley.global_position, candidate.global_position):
				_socket_markers.append(candidate.global_position)

		var valid := _is_valid_belt_distance(_belt_first_pulley.global_position, mouse_world_pos)
		_active_socket_position = _belt_first_pulley.global_position
		_has_active_socket = true
		_active_socket_valid = valid


func _get_nearest_gear_at(world_pos: Vector2, max_distance: float) -> GearComponent:
	var nearest: GearComponent = null
	var nearest_distance := max_distance
	
	for child in _components_container.get_children():
		var node := child as Node2D
		if not _is_belt_pulley_candidate(node):
			continue

		var gear := node as GearComponent
		
		var distance := gear.global_position.distance_to(world_pos)
		if distance < nearest_distance:
			nearest = gear
			nearest_distance = distance
	
	return nearest


func _is_belt_pulley_candidate(node: Node2D) -> bool:
	if node == null:
		return false

	var gear := node as GearComponent
	if gear == null:
		return false

	var component_type := str(node.get_meta("component_type", ""))
	return component_type == COMPONENT_GEAR_SMALL or component_type == COMPONENT_GEAR_MEDIUM or component_type == COMPONENT_GEAR_LARGE


func _is_valid_belt_distance(pos_a: Vector2, pos_b: Vector2) -> bool:
	var distance := pos_a.distance_to(pos_b)
	return distance <= PROJECT_PATHS_SCRIPT.CHAIN_MAX_SPAN and distance > 20.0


func place_belt(pulley_a: GearComponent, pulley_b: GearComponent) -> void:
	var belt := Node2D.new()
	var belt_script := load(CHAIN_COMPONENT_SCRIPT_PATH)
	if belt_script == null:
		return

	var belt_component = belt_script.new()
	if belt_component == null:
		return
	belt.add_child(belt_component)
	belt_component.configure(
		pulley_a,
		pulley_b,
		_get_node_connection_radius(pulley_a),
		_get_node_connection_radius(pulley_b)
	)
	belt.set_meta("component_type", PROJECT_PATHS_SCRIPT.COMPONENT_CHAIN)
	_components_container.add_child(belt)

	if _signal_bus:
		_signal_bus.gear_placed.emit(belt)
	_placement_context_dirty = true

## Draw helper: belt preview in _draw().
func _draw_belt_preview() -> void:
	if _belt_first_pulley:
		var first_pulley_local := to_local(_belt_first_pulley.global_position)
		var mouse_local := to_local(get_global_mouse_position())
		draw_line(first_pulley_local, mouse_local, Color(0.52, 0.56, 0.60, 0.55), 2.5)
		var pulse := sin(get_tree().get_frame() * 0.05) * 0.5 + 0.5
		var highlight_radius := 35.0 + (pulse * 3.0)
		draw_circle(first_pulley_local, highlight_radius, Color(0.55, 0.60, 0.65, 0.28 + (pulse * 0.15)))

		for child in _components_container.get_children():
			var candidate := child as Node2D
			if not _is_belt_pulley_candidate(candidate) or candidate == _belt_first_pulley:
				continue
			if not _is_valid_belt_distance(_belt_first_pulley.global_position, candidate.global_position):
				continue
			var candidate_local := to_local(candidate.global_position)
			draw_circle(candidate_local, 22.0, Color(0.55, 0.95, 0.75, 0.28))
			draw_arc(candidate_local, 22.0, 0.0, TAU, 30, Color(0.65, 1.0, 0.82, 0.9), 1.8)
	else:
		for child in _components_container.get_children():
			var gear := child as Node2D
			if not _is_belt_pulley_candidate(gear):
				continue
			var gear_local := to_local(gear.global_position)
			draw_circle(gear_local, 28.0, Color(0.42, 0.55, 0.68, 0.22))



func _compute_shaft_data_from_origin(start_origin: Dictionary, world_pos: Vector2) -> Dictionary:
	var start_pos: Vector2 = start_origin.get("position", Vector2.ZERO)
	var start_radius: float = float(start_origin.get("radius", 0.0))
	var direction := world_pos - start_pos
	if direction.length_squared() <= 0.0001:
		direction = Vector2.RIGHT
	else:
		direction = direction.normalized()

	var raw_connection_radius := world_pos.distance_to(start_pos) - start_radius
	var shaft_connection_radius := clampf(
		raw_connection_radius,
		PROJECT_PATHS_SCRIPT.SHAFT_MIN_CONNECTION_RADIUS,
		PROJECT_PATHS_SCRIPT.SHAFT_MAX_CONNECTION_RADIUS
	)
	var shaft_center := start_pos + (direction * (start_radius + shaft_connection_radius))
	var shaft_rotation := direction.angle()
	return {
		"position": shaft_center,
		"rotation": shaft_rotation,
		"connection_radius": shaft_connection_radius,
		"outer_radius": shaft_connection_radius + PROJECT_PATHS_SCRIPT.GEAR_MESH_CONTACT_MARGIN,
		"visual_outer_radius": shaft_connection_radius + PROJECT_PATHS_SCRIPT.GEAR_MESH_CONTACT_MARGIN
	}


func _is_shaft_candidate_clear(candidate_pos: Vector2, candidate_radius: float, ignore_origins: Array) -> bool:
	var ignored_nodes: Dictionary = {}
	for origin_raw in ignore_origins:
		if not origin_raw is Dictionary:
			continue
		var origin := origin_raw as Dictionary
		var origin_node := origin.get("node", null) as Node2D
		if origin_node:
			ignored_nodes[origin_node.get_instance_id()] = true

	for child in _components_container.get_children():
		var placed_component := child as Node2D
		if not placed_component:
			continue
		if ignored_nodes.has(placed_component.get_instance_id()):
			continue
		var placed_radius := _get_node_connection_radius(placed_component)
		var min_distance := candidate_radius + placed_radius - 0.6
		if placed_component.global_position.distance_to(candidate_pos) < min_distance:
			return false

	for blocked_raw in _get_cached_blocked_positions():
		if not blocked_raw is Dictionary:
			continue
		var blocked_data := blocked_raw as Dictionary
		var blocked_pos: Vector2 = blocked_data.get("position", Vector2.ZERO)
		var blocked_radius: float = float(blocked_data.get("radius", PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS))
		var blocked_min_distance := candidate_radius + blocked_radius - 1.0
		if blocked_pos.distance_to(candidate_pos) < blocked_min_distance:
			return false

	return true


func _get_nearest_origin(world_pos: Vector2, max_pick_distance: float = snap_max_distance) -> Dictionary:
	var nearest_origin: Dictionary = {}
	var nearest_distance := INF
	for origin_raw in _get_all_snap_origins():
		if not origin_raw is Dictionary:
			continue
		var origin := origin_raw as Dictionary
		var origin_pos: Vector2 = origin.get("position", Vector2.ZERO)
		var distance := origin_pos.distance_to(world_pos)
		if distance > max_pick_distance:
			continue
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_origin = origin

	return nearest_origin


func _get_all_snap_origins() -> Array:
	var origins: Array = []
	for seed_raw in _get_cached_seed_positions():
		if seed_raw is Dictionary:
			origins.append(seed_raw)

	for child in _components_container.get_children():
		var node := child as Node2D
		if not node:
			continue
		if _is_shaft_component(node):
			var shaft_radius := _get_shaft_connection_radius(node)
			var shaft_dir := Vector2.RIGHT.rotated(node.rotation)
			origins.append({
				"position": node.global_position + (shaft_dir * shaft_radius),
				"radius": PROJECT_PATHS_SCRIPT.SHAFT_ENDPOINT_ORIGIN_RADIUS,
				"node": node
			})
			origins.append({
				"position": node.global_position - (shaft_dir * shaft_radius),
				"radius": PROJECT_PATHS_SCRIPT.SHAFT_ENDPOINT_ORIGIN_RADIUS,
				"node": node
			})
			continue
		origins.append({
			"position": node.global_position,
			"radius": _get_node_connection_radius(node),
			"node": node
		})

	return origins


func _configure_shaft_preview_visual(outer_radius: float) -> void:
	if _preview_gear == null:
		return

	var visual := _preview_gear.get_node_or_null("Visual")
	if visual == null:
		return

	visual.set("outer_radius", outer_radius)
	visual.set("inner_radius", 4.8)
	visual.set("hub_radius", 3.8)
	if visual.has_method("queue_redraw"):
		visual.call("queue_redraw")


func _configure_shaft_runtime_visual(shaft: Node2D, outer_radius: float) -> void:
	if shaft == null:
		return

	var visual := shaft.get_node_or_null("Visual")
	if visual == null:
		return

	visual.set("outer_radius", outer_radius)
	visual.set("shaft_module_size", PROJECT_PATHS_SCRIPT.SHAFT_SHAPE_MODULE)
	visual.set("inner_radius", 4.8)
	visual.set("hub_radius", 3.8)
	if visual.has_method("queue_redraw"):
		visual.call("queue_redraw")


func _is_shaft_component(node: Node2D) -> bool:
	if node == null or not node.has_meta("component_type"):
		return false

	return str(node.get_meta("component_type")) == PROJECT_PATHS_SCRIPT.COMPONENT_SHAFT


func _get_shaft_connection_radius(node: Node2D) -> float:
	if node and node.has_meta("shaft_connection_radius"):
		return maxf(0.0, float(node.get_meta("shaft_connection_radius")))

	return _get_node_connection_radius(node)


func get_perf_stats() -> Dictionary:
	return {
		"selected_component": _selected_component,
		"context_dirty": _placement_context_dirty,
		"socket_markers": _socket_markers.size(),
		"has_active_socket": _has_active_socket,
		"components": _components_container.get_child_count()
	}

