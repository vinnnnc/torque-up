extends Node2D
class_name PlacementController

const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")
const PLACEMENT_RULES_SCRIPT = preload("res://scripts/features/placement/placement_rules.gd")
const NETWORK_SERVICE_SCRIPT = preload("res://scripts/features/network/network_service.gd")
# Handler type preloads
const GearPlacementHandler = preload("res://scripts/features/placement/handlers/gear_placement_handler.gd")

@export var gear_scene: PackedScene
@export var small_gear_scene: PackedScene
@export var medium_gear_scene: PackedScene
@export var large_gear_scene: PackedScene
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
const OVERLAY_ARC_PIXELS_PER_SEGMENT := 8.0
const OVERLAY_ARC_MIN_POINTS := 18
const OVERLAY_ARC_MAX_POINTS := 220
const COMPONENT_GEAR_SMALL := PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_SMALL
const COMPONENT_GEAR_MEDIUM := PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_MEDIUM
const COMPONENT_GEAR_LARGE := PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_LARGE
const COMPONENT_DELETE := PROJECT_PATHS_SCRIPT.COMPONENT_DELETE

var _placement_rules = PLACEMENT_RULES_SCRIPT.new()
var _preview_gear: Node2D
var _selected_component: String = ""
var _is_left_mouse_down: bool = false
var _last_auto_delete_msec: int = 0
var _cached_seed_positions: Array = []
var _cached_blocked_positions: Array = []
var _placement_context_dirty: bool = true
var _last_preview_mouse_pos := Vector2.ZERO
var _has_last_preview_mouse: bool = false
var _last_preview_refresh_msec: int = 0
var _skip_next_dirty_flag: bool = false
# -- Per-component handlers ---------------------------------------------------
var _handler_ctx: PlacementHandlerContext
var _handlers: Dictionary = {}
@onready var _components_container: Node2D = get_node(components_container_path)
@onready var _power_source: Node2D = get_node_or_null(power_source_path)
@onready var _central_engine: Node2D = get_node_or_null("../Network/CentralEngine")
@onready var _network_node: Node2D = get_node_or_null("../Network")
@onready var _barriers_node: Node2D = get_node_or_null("../Barriers")
@onready var _frontier_node: Node = get_node_or_null("../Blockade")
@onready var _signal_bus: Node = get_node_or_null("/root/SignalBus")

const AUTO_DELETE_INTERVAL_MSEC := 55
const PREVIEW_REFRESH_INTERVAL_MSEC := 33
const DENSE_MESH_PREVIEW_COMPONENT_THRESHOLD := 240
const DENSE_MESH_PREVIEW_REFRESH_INTERVAL_MSEC := 90
const DENSE_MESH_PREVIEW_MIN_MOUSE_DELTA_SQ := 9.0
const DRAG_RELEASE_DEADZONE := 14.0


func _ready() -> void:
	z_as_relative = false
	z_index = PROJECT_PATHS_SCRIPT.PLACEMENT_OVERLAY_Z_INDEX
	_placement_rules.socket_count = socket_count
	_placement_rules.socket_radius = socket_radius
	_placement_rules.snap_max_distance = snap_max_distance
	_placement_rules.placement_clearance = placement_clearance
	_placement_rules.world_position_validator = func(world_pos: Vector2, clearance_radius: float) -> bool:
		return _is_inside_frontier(world_pos, clearance_radius)
	_setup_handler_context()
	_setup_handlers()
	_create_preview_gear()
	if _signal_bus and not _signal_bus.component_selected.is_connected(_on_component_selected):
		_signal_bus.component_selected.connect(_on_component_selected)
	if _signal_bus and not _signal_bus.gear_placed.is_connected(_on_layout_changed):
		_signal_bus.gear_placed.connect(_on_layout_changed)
	if _signal_bus and not _signal_bus.component_removed.is_connected(_on_layout_changed):
		_signal_bus.component_removed.connect(_on_layout_changed)
	if _signal_bus and _signal_bus.has_signal("placement_mode_changed") and not _signal_bus.placement_mode_changed.is_connected(_on_placement_mode_changed):
		_signal_bus.placement_mode_changed.connect(_on_placement_mode_changed)
	_update_preview_visibility()


func _setup_handler_context() -> void:
	_handler_ctx = PlacementHandlerContext.new()
	_handler_ctx.components_container = _components_container
	_handler_ctx.signal_bus = _signal_bus
	_handler_ctx.placement_rules = _placement_rules
	_handler_ctx.snap_max_distance = snap_max_distance
	_handler_ctx.drag_release_deadzone = DRAG_RELEASE_DEADZONE
	_handler_ctx.scenes = {
		COMPONENT_GEAR_SMALL: small_gear_scene if small_gear_scene != null else gear_scene,
		COMPONENT_GEAR_MEDIUM: medium_gear_scene if medium_gear_scene != null else gear_scene,
		COMPONENT_GEAR_LARGE: large_gear_scene if large_gear_scene != null else gear_scene,
	}
	_handler_ctx.fn_get_node_connection_radius = _get_node_connection_radius
	_handler_ctx.fn_get_node_outer_radius = _get_node_outer_radius
	_handler_ctx.fn_get_node_tooth_count = _get_node_tooth_count
	_handler_ctx.fn_get_cached_seed_positions = _get_cached_seed_positions
	_handler_ctx.fn_get_cached_blocked_positions = _get_cached_blocked_positions
	_handler_ctx.fn_mark_dirty = func():
		if _skip_next_dirty_flag:
			_skip_next_dirty_flag = false
		else:
			_placement_context_dirty = true
	_handler_ctx.fn_get_all_snap_origins = _get_all_snap_origins


func _setup_handlers() -> void:
	var gear_small_handler := GearPlacementHandler.new()
	gear_small_handler.init(_handler_ctx)
	gear_small_handler.component_id = COMPONENT_GEAR_SMALL

	var gear_medium_handler := GearPlacementHandler.new()
	gear_medium_handler.init(_handler_ctx)
	gear_medium_handler.component_id = COMPONENT_GEAR_MEDIUM

	var gear_large_handler := GearPlacementHandler.new()
	gear_large_handler.init(_handler_ctx)
	gear_large_handler.component_id = COMPONENT_GEAR_LARGE

	_handlers = {
		COMPONENT_GEAR_SMALL: gear_small_handler,
		COMPONENT_GEAR_MEDIUM: gear_medium_handler,
		COMPONENT_GEAR_LARGE: gear_large_handler,
	}


func _get_active_handler() -> PlacementHandlerBase:
	return _handlers.get(_selected_component, null) as PlacementHandlerBase


func _process(_delta: float) -> void:
	if _preview_gear == null or _handler_ctx == null:
		return

	var mouse_world_pos := get_global_mouse_position()

	if not _is_selected_placeable_component():
		var had_preview_artifacts := (not _handler_ctx.socket_markers.is_empty()) or _handler_ctx.has_active_socket
		_handler_ctx.socket_markers.clear()
		_handler_ctx.has_active_socket = false
		_update_preview_visibility()
		_handle_delete_drag(mouse_world_pos)
		if had_preview_artifacts:
			queue_redraw()
		return

	var handler := _get_active_handler()
	# Unthrottled per-frame hook (e.g., gear drag auto-place).
	if get_viewport().gui_get_hovered_control() == null and handler != null:
		handler.process(mouse_world_pos)

	var should_refresh_preview := _should_refresh_preview(mouse_world_pos)
	if should_refresh_preview and handler != null:
		handler.update_preview(mouse_world_pos, _preview_gear)
		_update_preview_visibility()
		_record_preview_refresh(mouse_world_pos)
		queue_redraw()

	_handle_delete_drag(mouse_world_pos)


func _draw() -> void:
	if _handler_ctx == null:
		return
	for marker_world_pos in _handler_ctx.socket_markers:
		if marker_world_pos is Dictionary:
			var marker := marker_world_pos as Dictionary
			var kind := str(marker.get("kind", ""))
			var center_world := marker.get("center", Vector2.ZERO) as Vector2
			var center_local := to_local(center_world)
			var radius := float(marker.get("radius", 0.0))
			if kind == "arc_segment":
				var start_angle := float(marker.get("start_angle", 0.0))
				var end_angle := float(marker.get("end_angle", 0.0))
				var segment_points := _get_overlay_arc_point_count(radius, absf(end_angle - start_angle))
				draw_arc(center_local, radius, start_angle, end_angle, segment_points, SOCKET_MARKER_COLOR, 3.0)
				draw_arc(center_local, radius, start_angle, end_angle, segment_points, SOCKET_MARKER_OUTLINE, 1.6)
			elif kind == "ring":
				var ring_points := _get_overlay_arc_point_count(radius, TAU)
				draw_arc(center_local, radius, 0.0, TAU, ring_points, SOCKET_MARKER_COLOR, 3.0)
				draw_arc(center_local, radius, 0.0, TAU, ring_points, SOCKET_MARKER_OUTLINE, 1.6)
			continue
		if not marker_world_pos is Vector2:
			continue
		var marker_world: Vector2 = marker_world_pos
		var marker_local: Vector2 = to_local(marker_world)
		var p0: Vector2 = marker_local + Vector2(-5.2, 0.0)
		var p1: Vector2 = marker_local + Vector2(5.2, 0.0)
		draw_line(p0, p1, SOCKET_MARKER_COLOR, 3.0)
		draw_line(p0, p1, SOCKET_MARKER_OUTLINE, 1.6)

	if _handler_ctx.has_active_socket:
		var active_local := to_local(_handler_ctx.active_socket_position)
		var ring_color := ACTIVE_SOCKET_COLOR if _handler_ctx.active_socket_valid else INVALID_PREVIEW_COLOR
		draw_arc(active_local, 8.0, 0.0, TAU, _get_overlay_arc_point_count(8.0, TAU), ring_color, 2.0)

	var handler := _get_active_handler()
	if handler != null:
		handler.draw_overlay(self)


func _get_overlay_arc_point_count(radius: float, sweep_angle: float) -> int:
	var safe_radius := maxf(radius, 1.0)
	var safe_sweep := clampf(absf(sweep_angle), 0.001, TAU)
	var arc_length := safe_radius * safe_sweep
	var estimated_points := int(ceil(arc_length / OVERLAY_ARC_PIXELS_PER_SEGMENT))
	return clampi(estimated_points, OVERLAY_ARC_MIN_POINTS, OVERLAY_ARC_MAX_POINTS)

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
	var world_pos := get_global_mouse_position()
	if not mouse_event.pressed:
		var release_handler := _get_active_handler()
		if release_handler != null:
			release_handler.on_mouse_up(world_pos)
		_has_last_preview_mouse = false
		queue_redraw()
		return

	# Ignore world placement/deletion clicks when interacting with UI controls.
	if get_viewport().gui_get_hovered_control() != null:
		return

	if _selected_component == COMPONENT_DELETE:
		delete_component_at(world_pos)
		_last_auto_delete_msec = Time.get_ticks_msec()
		return

	if not _is_selected_placeable_component():
		return
	if not _is_inside_frontier(world_pos):
		if _signal_bus and _signal_bus.has_signal("placement_feedback"):
			_signal_bus.placement_feedback.emit("Fog blocks placement outside the unlocked frontier.")
		return

	var active_handler := _get_active_handler()
	if active_handler == null:
		return

	active_handler.on_mouse_down(world_pos)
	_has_last_preview_mouse = false
	queue_redraw()


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

	# In very dense layouts mesh preview calculations are expensive. Throttle
	# refreshes to a fixed interval to keep cursor movement smooth.
	if _handler_ctx != null and _handler_ctx.active_mode == "mesh" and _components_container != null:
		if _components_container.get_child_count() >= DENSE_MESH_PREVIEW_COMPONENT_THRESHOLD:
			if not _has_last_preview_mouse:
				return true
			if _last_preview_mouse_pos.distance_squared_to(mouse_world_pos) < DENSE_MESH_PREVIEW_MIN_MOUSE_DELTA_SQ:
				return false
			return (Time.get_ticks_msec() - _last_preview_refresh_msec) >= DENSE_MESH_PREVIEW_REFRESH_INTERVAL_MSEC

	if not _has_last_preview_mouse:
		return true

	if _last_preview_mouse_pos.distance_squared_to(mouse_world_pos) >= 1.0:
		return true

	return false


func _record_preview_refresh(mouse_world_pos: Vector2) -> void:
	_last_preview_mouse_pos = mouse_world_pos
	_has_last_preview_mouse = true
	_last_preview_refresh_msec = Time.get_ticks_msec()


func _get_cached_seed_positions() -> Array:
	if _placement_context_dirty:
		_rebuild_placement_context_cache()
	return _cached_seed_positions


func _get_cached_blocked_positions() -> Array:
	if _placement_context_dirty:
		_rebuild_placement_context_cache()
	return _cached_blocked_positions


func _rebuild_placement_context_cache() -> void:
	_cached_seed_positions = _get_seed_positions()
	_cached_blocked_positions = _get_blocked_positions()
	if _placement_rules != null and _placement_rules.has_method("rebuild_mesh_cache"):
		_placement_rules.call("rebuild_mesh_cache", _components_container, _cached_seed_positions, _cached_blocked_positions)
	_placement_context_dirty = false


func _create_preview_gear() -> void:
	var chosen_scene: PackedScene = _handler_ctx.get_scene(_selected_component) if _handler_ctx != null else null
	if chosen_scene == null:
		chosen_scene = gear_scene
	if chosen_scene == null:
		return

	_preview_gear = chosen_scene.instantiate() as Node2D
	if _preview_gear == null:
		return

	_preview_gear.z_index = 100
	add_child(_preview_gear)
	var handler := _get_active_handler()
	if handler != null:
		handler.configure_instance(_preview_gear)
	_update_preview_visibility()


func _on_component_selected(component_id: String) -> void:
	var old_handler := _get_active_handler()
	if old_handler != null:
		old_handler.deactivate()

	_selected_component = component_id
	_handler_ctx.socket_markers.clear()
	_handler_ctx.has_active_socket = false
	_handler_ctx.active_socket_valid = false
	_has_last_preview_mouse = false

	if _preview_gear != null:
		_preview_gear.queue_free()
		_preview_gear = null
	_create_preview_gear()
	_update_preview_visibility()

	var new_handler := _get_active_handler()
	if new_handler != null:
		new_handler.activate()
	queue_redraw()


func get_handler_context() -> PlacementHandlerContext:
	return _handler_ctx


func cycle_mesh_origin_focus() -> String:
	var handler := _get_active_handler()
	if handler == null:
		return "Select a gear first."
	if not handler.has_method("cycle_mesh_origin_focus"):
		return "Origin cycling is only supported for gear placement."
	var message := str(handler.call("cycle_mesh_origin_focus", get_global_mouse_position()))
	_has_last_preview_mouse = false
	queue_redraw()
	return message


func _on_placement_mode_changed(mode: String) -> void:
	if _handler_ctx == null:
		return
	_handler_ctx.set_active_mode(mode)
	_has_last_preview_mouse = false
	queue_redraw()


func _on_layout_changed(_component: Node2D = null) -> void:
	if _component != null and _placement_rules != null and _placement_rules.has_method("add_component_to_mesh_cache"):
		var incremental_ok := bool(_placement_rules.call("add_component_to_mesh_cache", _component))
		if incremental_ok:
			_skip_next_dirty_flag = true
			_has_last_preview_mouse = false
			return
	_placement_context_dirty = true
	if _placement_rules != null and _placement_rules.has_method("invalidate_mesh_cache"):
		_placement_rules.call("invalidate_mesh_cache")
	_has_last_preview_mouse = false


func _update_preview_visibility() -> void:
	if _preview_gear:
		_preview_gear.visible = _is_selected_placeable_component()

func place_gear(pos: Vector2, emit_network_update: bool = true) -> void:
	if not _is_inside_frontier(pos):
		return
	var handler := _handlers.get(_selected_component, null) as GearPlacementHandler
	if handler == null:
		return
	handler.place_gear(pos, emit_network_update)


func delete_component_at(world_pos: Vector2) -> void:
	var nearest_component := find_component_at(world_pos, placement_clearance * 0.7)
	if nearest_component == null:
		return

	var attached_connectors := _collect_attached_connectors(nearest_component)
	for connector_node in attached_connectors:
		if connector_node and connector_node != nearest_component:
			connector_node.queue_free()

	if _signal_bus:
		nearest_component.tree_exited.connect(_on_deleted_component_exited, CONNECT_ONE_SHOT)
	nearest_component.queue_free()
	_placement_context_dirty = true


func find_component_at(world_pos: Vector2, max_distance: float = -1.0) -> Node2D:
	if _components_container == null:
		return null

	var pick_radius := max_distance
	if pick_radius < 0.0:
		pick_radius = placement_clearance * 0.7

	var nearest_component: Node2D = null
	var nearest_distance := INF
	for child in _components_container.get_children():
		var component := child as Node2D
		if component == null:
			continue

		var distance := _get_delete_distance_for_component(component, world_pos)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_component = component

	if nearest_component == null or nearest_distance > pick_radius:
		return null

	return nearest_component


func _collect_attached_connectors(component: Node2D) -> Array:
	if component == null:
		return []
	return [component]


func _get_delete_distance_for_component(component: Node2D, world_pos: Vector2) -> float:
	if component == null:
		return INF
	return component.global_position.distance_to(world_pos)


func _on_deleted_component_exited() -> void:
	if _signal_bus:
		_signal_bus.component_removed.emit()


func _get_blocked_positions() -> Array:
	var positions: Array = []
	if _network_node == null:
		return positions

	for child in _network_node.get_children():
		var node := child as Node2D
		if node == null or node == _components_container:
			continue

		if node.name == "CentralEngine":
			positions.append({"position": node.global_position, "radius": _get_node_connection_radius(node)})
			continue

		if node.name.begins_with("Power"):
			# Include all power nodes (both active and inactive) in blocking validation
			# The snap calculation via circle intersection ensures proper spacing around them
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

	var mesh_radius := 0.0
	var anchor_mesh_radius: Variant = node.get("source_outer_radius")
	if anchor_mesh_radius != null:
		mesh_radius = maxf(float(anchor_mesh_radius), 0.0)

	var radius_value: Variant = visual.get("outer_radius")
	if radius_value == null:
		if mesh_radius > 0.0:
			return mesh_radius
		return PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS

	var visual_radius := maxf(float(radius_value), 0.0)
	if mesh_radius <= 0.0:
		return visual_radius
	# Keep mechanics from becoming smaller than the rendered shell.
	return maxf(mesh_radius, visual_radius)


func _get_node_connection_radius(node: Node2D) -> float:
	var outer_radius := _get_node_outer_radius(node)
	return maxf(2.0, outer_radius - PROJECT_PATHS_SCRIPT.GEAR_MESH_CONTACT_MARGIN)


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
	return _selected_component == COMPONENT_GEAR_SMALL or _selected_component == COMPONENT_GEAR_MEDIUM or _selected_component == COMPONENT_GEAR_LARGE


func _cancel_active_drags() -> void:
	for handler_raw in _handlers.values():
		var handler := handler_raw as PlacementHandlerBase
		if handler != null:
			handler.cancel()
	queue_redraw()



func _get_all_snap_origins() -> Array:
	var origins = _placement_rules.get_snap_origins(_components_container, _get_cached_seed_positions())
	
	# Ensure power nodes and engine are explicitly included in snap origins for dual snap support
	var network_anchors := _get_network_anchor_nodes_for_placement()
	var origin_nodes_set := {}
	for origin_raw in origins:
		if origin_raw is Dictionary and origin_raw.has("node"):
			var node = origin_raw["node"]
			if node:
				origin_nodes_set[node.get_instance_id()] = true
	
	# Add power nodes that might not be in origins yet
	for anchor in network_anchors:
		if anchor == null:
			continue
		if not _is_inside_frontier(anchor.global_position, 0.0):
			continue
		if not origin_nodes_set.has(anchor.get_instance_id()):
			origins.append({
				"position": anchor.global_position,
				"radius": _get_node_connection_radius(anchor),
				"node": anchor
			})
	
	return origins


func _is_inside_frontier(world_pos: Vector2, clearance_radius: float = 0.0) -> bool:
	if _frontier_node != null and _frontier_node.has_method("is_position_unlocked"):
		return bool(_frontier_node.call("is_position_unlocked", world_pos, clearance_radius))
	return true


func get_perf_stats() -> Dictionary:
	var mesh_cache_stats: Dictionary = {}
	if _placement_rules != null and _placement_rules.has_method("get_mesh_cache_stats"):
		mesh_cache_stats = _placement_rules.call("get_mesh_cache_stats") as Dictionary
	return {
		"selected_component": _selected_component,
		"context_dirty": _placement_context_dirty,
		"socket_markers": _handler_ctx.socket_markers.size() if _handler_ctx != null else 0,
		"has_active_socket": _handler_ctx.has_active_socket if _handler_ctx != null else false,
		"components": _components_container.get_child_count(),
		"mesh_cache": mesh_cache_stats,
	}

