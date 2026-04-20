## PlacementHandlerContext
## Shared context passed to every placement handler.
## PlacementController creates one instance and binds all callables in _ready().
class_name PlacementHandlerContext
extends RefCounted

const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")

# -- Shared nodes --------------------------------------------------------------
var components_container: Node2D = null
var signal_bus: Node = null

# -- Placement rules object (PLACEMENT_RULES_SCRIPT instance) ------------------
var placement_rules: RefCounted = null

# -- Per-component scenes, keyed by component-id string -----------------------
var scenes: Dictionary = {}

# -- Runtime config ------------------------------------------------------------
var snap_max_distance: float = PROJECT_PATHS_SCRIPT.DEFAULT_SNAP_MAX_DISTANCE
var drag_release_deadzone: float = 14.0

# -- Preview state (handlers write; PlacementController reads for _draw) -------
var socket_markers: Array = []
var active_socket_position: Vector2 = Vector2.ZERO
var has_active_socket: bool = false
var active_socket_valid: bool = false

# -- Callables (PlacementController binds these after _ready) -----------------
## func(node: Node2D) -> float
var fn_get_node_connection_radius: Callable = Callable()
## func(node: Node2D) -> float
var fn_get_node_outer_radius: Callable = Callable()
## func(node: Node2D) -> int
var fn_get_node_tooth_count: Callable = Callable()
## func() -> Array
var fn_get_cached_seed_positions: Callable = Callable()
## func() -> Array
var fn_get_cached_blocked_positions: Callable = Callable()
## func() -> void  -- marks layout cache dirty
var fn_mark_dirty: Callable = Callable()
## func() -> Array  -- returns all current snap origins
var fn_get_all_snap_origins: Callable = Callable()

# -- Convenience forwarders ----------------------------------------------------
func get_scene(component_id: String) -> PackedScene:
	return scenes.get(component_id, null) as PackedScene

func get_node_connection_radius(node: Node2D) -> float:
	if fn_get_node_connection_radius.is_valid():
		return float(fn_get_node_connection_radius.call(node))
	return PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS - PROJECT_PATHS_SCRIPT.GEAR_MESH_CONTACT_MARGIN

func get_node_outer_radius(node: Node2D) -> float:
	if fn_get_node_outer_radius.is_valid():
		return float(fn_get_node_outer_radius.call(node))
	return PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS

func get_node_tooth_count(node: Node2D) -> int:
	if fn_get_node_tooth_count.is_valid():
		return int(fn_get_node_tooth_count.call(node))
	return 0

func get_cached_seed_positions() -> Array:
	if fn_get_cached_seed_positions.is_valid():
		return fn_get_cached_seed_positions.call() as Array
	return []

func get_cached_blocked_positions() -> Array:
	if fn_get_cached_blocked_positions.is_valid():
		return fn_get_cached_blocked_positions.call() as Array
	return []

func mark_dirty() -> void:
	if fn_mark_dirty.is_valid():
		fn_mark_dirty.call()

func get_all_snap_origins() -> Array:
	if fn_get_all_snap_origins.is_valid():
		return fn_get_all_snap_origins.call() as Array
	return []

func emit_gear_placed(node: Node2D) -> void:
	if signal_bus:
		signal_bus.gear_placed.emit(node)

func emit_component_removed() -> void:
	if signal_bus:
		signal_bus.component_removed.emit()

func emit_feedback(message: String) -> void:
	if signal_bus and signal_bus.has_signal("placement_feedback"):
		signal_bus.placement_feedback.emit(message)
