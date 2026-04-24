extends RefCounted
class_name PlacementRules

const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")

var socket_count: int = 8
var socket_radius: float = PROJECT_PATHS_SCRIPT.DEFAULT_SOCKET_RADIUS
var snap_max_distance: float = PROJECT_PATHS_SCRIPT.DEFAULT_SNAP_MAX_DISTANCE
var placement_clearance: float = PROJECT_PATHS_SCRIPT.DEFAULT_PLACEMENT_CLEARANCE
var marker_samples: int = 24
var component_radius: float = PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS
## Optional callback signature: func(world_pos: Vector2, clearance_radius: float) -> bool
var world_position_validator: Callable = Callable()

const MAX_ORIGIN_CLEARANCE_TESTS := 6
const DENSE_LAYOUT_COMPONENT_THRESHOLD := 180
const DENSE_LAYOUT_MARKER_SAMPLES := 10
const MAX_DUAL_SNAP_ORIGINS := 10
const DENSE_LAYOUT_DISABLE_DUAL_SNAP_THRESHOLD := 240
const MESH_CACHE_CELL_SIZE := 96.0
const MESH_CACHE_LARGE_RADIUS_THRESHOLD := 180.0

var _mesh_cache_valid: bool = false
var _mesh_cache_components_container: Node = null
var _mesh_cache_origins: Array = []
var _mesh_cache_components: Array = []
var _mesh_cache_components_grid: Dictionary = {}
var _mesh_cache_max_component_radius: float = 0.0
var _mesh_cache_blocked_small: Array = []
var _mesh_cache_blocked_small_grid: Dictionary = {}
var _mesh_cache_blocked_large: Array = []
var _mesh_cache_max_blocked_small_radius: float = 0.0
var _mesh_cache_blocked_count: int = 0


func invalidate_mesh_cache() -> void:
	_mesh_cache_valid = false
	_mesh_cache_components_container = null
	_mesh_cache_origins = []
	_mesh_cache_components = []
	_mesh_cache_components_grid = {}
	_mesh_cache_max_component_radius = 0.0
	_mesh_cache_blocked_small = []
	_mesh_cache_blocked_small_grid = {}
	_mesh_cache_blocked_large = []
	_mesh_cache_max_blocked_small_radius = 0.0
	_mesh_cache_blocked_count = 0


func rebuild_mesh_cache(components_container: Node, seed_positions: Array = [], blocked_positions: Array = []) -> void:
	invalidate_mesh_cache()
	_mesh_cache_components_container = components_container
	if components_container == null:
		return

	for child in components_container.get_children():
		var placed_component := child as Node2D
		if not placed_component:
			continue
		var component_entry := {
			"node": placed_component,
			"position": placed_component.global_position,
			"radius": _get_node_block_radius(placed_component)
		}
		var component_index := _mesh_cache_components.size()
		_mesh_cache_components.append(component_entry)
		_mesh_cache_max_component_radius = maxf(_mesh_cache_max_component_radius, float(component_entry.get("radius", 0.0)))
		_grid_insert(_mesh_cache_components_grid, component_entry.get("position", Vector2.ZERO) as Vector2, component_index)

	for blocked_raw in blocked_positions:
		var blocked_data := _to_origin_data(blocked_raw)
		if blocked_data.is_empty():
			continue
		var blocked_entry := {
			"position": blocked_data.get("position", Vector2.ZERO),
			"radius": float(blocked_data.get("radius", 0.0))
		}
		_mesh_cache_blocked_count += 1
		if float(blocked_entry.get("radius", 0.0)) >= MESH_CACHE_LARGE_RADIUS_THRESHOLD:
			_mesh_cache_blocked_large.append(blocked_entry)
			continue
		var blocked_small_index := _mesh_cache_blocked_small.size()
		_mesh_cache_blocked_small.append(blocked_entry)
		_mesh_cache_max_blocked_small_radius = maxf(_mesh_cache_max_blocked_small_radius, float(blocked_entry.get("radius", 0.0)))
		_grid_insert(_mesh_cache_blocked_small_grid, blocked_entry.get("position", Vector2.ZERO) as Vector2, blocked_small_index)

	_mesh_cache_origins = _get_snap_origins_uncached(components_container, seed_positions)
	_mesh_cache_valid = true


func is_mesh_cache_valid() -> bool:
	return _mesh_cache_valid


## Incrementally add a single newly-placed component to an existing cache.
## Returns false if the cache is not currently valid (caller should fall back to full rebuild).
func add_component_to_mesh_cache(component: Node2D) -> bool:
	if not _mesh_cache_valid or _mesh_cache_components_container == null or component == null:
		return false

	var component_entry := {
		"node": component,
		"position": component.global_position,
		"radius": _get_node_block_radius(component)
	}
	var component_index := _mesh_cache_components.size()
	_mesh_cache_components.append(component_entry)
	_mesh_cache_max_component_radius = maxf(_mesh_cache_max_component_radius, float(component_entry.get("radius", 0.0)))
	_grid_insert(_mesh_cache_components_grid, component_entry.get("position", Vector2.ZERO) as Vector2, component_index)

	# Append snap origins contributed by this component.
	var port_origins := _get_component_port_snap_origins(component)
	if not port_origins.is_empty():
		for port_origin_raw in port_origins:
			var port_origin := port_origin_raw as Dictionary
			if port_origin.is_empty():
				continue
			var port_pos: Vector2 = port_origin.get("position", Vector2.ZERO)
			if _is_world_position_valid(port_pos, 0.0):
				_mesh_cache_origins.append(port_origin)
		return true

	if _is_world_position_valid(component.global_position, 0.0):
		_mesh_cache_origins.append({
			"position": component.global_position,
			"radius": _get_node_connection_radius(component),
			"node": component
		})
	return true


func get_snap_origins(components_container: Node, seed_positions: Array = []) -> Array:
	if _has_valid_mesh_cache_for(components_container):
		return _mesh_cache_origins.duplicate(true)
	return _get_snap_origins_uncached(components_container, seed_positions)


func _has_valid_mesh_cache_for(components_container: Node) -> bool:
	return _mesh_cache_valid and _mesh_cache_components_container == components_container


func _get_query_origins(components_container: Node, seed_positions: Array) -> Array:
	if _has_valid_mesh_cache_for(components_container):
		return _mesh_cache_origins
	return _get_snap_origins_uncached(components_container, seed_positions)


func _is_world_position_valid(world_pos: Vector2, clearance_radius: float = 0.0) -> bool:
	if not world_position_validator.is_valid():
		return true
	return bool(world_position_validator.call(world_pos, clearance_radius))


func get_available_socket_positions(
	components_container: Node,
	seed_positions: Array = [],
	blocked_positions: Array = [],
	component_outer_radius: float = component_radius,
	origin_filter: Callable = Callable(),
	collision_filter: Callable = Callable()
) -> Array:
	if components_container == null:
		return []

	var positions: Array = []
	var origins := _get_query_origins(components_container, seed_positions)
	for origin_raw in origins:
		var origin_data := _to_origin_data(origin_raw)
		if origin_data.is_empty():
			continue
		if origin_filter.is_valid() and not bool(origin_filter.call(origin_data)):
			continue

		if origin_data.has("fixed_direction"):
			var fixed_candidate := _get_snap_candidate_for_origin(Vector2.ZERO, origin_data, component_outer_radius)
			if not _is_world_position_valid(fixed_candidate, component_outer_radius):
				continue
			if not _is_too_close(fixed_candidate, components_container, blocked_positions, component_outer_radius, collision_filter):
				positions.append(fixed_candidate)
			continue

		var origin: Vector2 = origin_data["position"]
		var origin_radius: float = origin_data["radius"]
		for sample_index in range(marker_samples):
			var angle := TAU * (float(sample_index) / float(marker_samples))
			var candidate := origin + Vector2.RIGHT.rotated(angle) * (origin_radius + component_outer_radius)
			if not _is_world_position_valid(candidate, component_outer_radius):
				continue
			if _is_too_close(candidate, components_container, blocked_positions, component_outer_radius, collision_filter):
				continue
			positions.append(candidate)

	return positions


func get_nearest_available_socket_positions(
	world_pos: Vector2,
	components_container: Node,
	seed_positions: Array = [],
	blocked_positions: Array = [],
	component_outer_radius: float = component_radius,
	origin_filter: Callable = Callable(),
	collision_filter: Callable = Callable()
) -> Array:
	if components_container == null:
		return []

	if components_container.get_child_count() >= DENSE_LAYOUT_COMPONENT_THRESHOLD:
		# In dense layouts this marker pass is expensive and not needed for usability.
		return []

	var origin: Variant = get_nearest_snap_origin(
		world_pos,
		components_container,
		seed_positions,
		blocked_positions,
		component_outer_radius,
		origin_filter
	)
	if origin == null:
		return []

	var positions: Array = []
	if origin.has("fixed_direction"):
		var fixed_candidate := _get_snap_candidate_for_origin(world_pos, origin, component_outer_radius)
		if not _is_world_position_valid(fixed_candidate, component_outer_radius):
			return positions
		if not _is_too_close(fixed_candidate, components_container, blocked_positions, component_outer_radius, collision_filter):
			positions.append(fixed_candidate)
		return positions

	var origin_pos: Vector2 = origin["position"]
	var origin_radius: float = origin["radius"]
	var local_marker_samples := marker_samples
	if components_container.get_child_count() >= DENSE_LAYOUT_COMPONENT_THRESHOLD:
		local_marker_samples = DENSE_LAYOUT_MARKER_SAMPLES

	for sample_index in range(local_marker_samples):
		var angle := TAU * (float(sample_index) / float(local_marker_samples))
		var candidate := origin_pos + Vector2.RIGHT.rotated(angle) * (origin_radius + component_outer_radius)
		if not _is_world_position_valid(candidate, component_outer_radius):
			continue
		if _is_too_close(candidate, components_container, blocked_positions, component_outer_radius, collision_filter):
			continue
		positions.append(candidate)

	return positions


func get_nearest_snap_origin(
	world_pos: Vector2,
	components_container: Node,
	seed_positions: Array = [],
	blocked_positions: Array = [],
	component_outer_radius: float = component_radius,
	origin_filter: Callable = Callable(),
	collision_filter: Callable = Callable()
):
	if components_container == null:
		return null

	var origins := _get_query_origins(components_container, seed_positions)
	if origins.is_empty():
		return null

	var nearest_candidates: Array = []
	for origin_raw in origins:
		var origin_data := _to_origin_data(origin_raw)
		if origin_data.is_empty():
			continue
		if origin_filter.is_valid() and not bool(origin_filter.call(origin_data)):
			continue

		var origin_pos: Vector2 = origin_data["position"]
		if not _is_world_position_valid(origin_pos, 0.0):
			continue
		var edge_candidate := _get_snap_candidate_for_origin(world_pos, origin_data, component_outer_radius)
		var distance_to_mouse := edge_candidate.distance_to(world_pos)
		_push_nearest_origin_candidate(nearest_candidates, origin_data, distance_to_mouse)

	for candidate_entry_raw in nearest_candidates:
		if not candidate_entry_raw is Dictionary:
			continue
		var candidate_entry := candidate_entry_raw as Dictionary
		var candidate_origin := candidate_entry.get("origin", {}) as Dictionary
		if candidate_origin.is_empty():
			continue

		var _candidate_origin_pos: Vector2 = candidate_origin["position"]
		var _candidate_origin_radius: float = candidate_origin["radius"]
		var edge_candidate := _get_snap_candidate_for_origin(world_pos, candidate_origin, component_outer_radius)
		if not _is_world_position_valid(edge_candidate, component_outer_radius):
			continue
		if not _is_too_close(edge_candidate, components_container, blocked_positions, component_outer_radius, collision_filter):
			return candidate_origin

	return null

func get_snap_result(
	world_pos: Vector2,
	components_container: Node,
	seed_positions: Array = [],
	blocked_positions: Array = [],
	component_outer_radius: float = component_radius,
	origin_filter: Callable = Callable(),
	collision_filter: Callable = Callable()
) -> Dictionary:
	if components_container == null:
		return {"valid": false, "position": world_pos}

	var dual_candidate := {"valid": false, "position": world_pos}
	if components_container.get_child_count() < DENSE_LAYOUT_DISABLE_DUAL_SNAP_THRESHOLD:
		dual_candidate = _get_dual_snap_result(
			world_pos,
			components_container,
			seed_positions,
			blocked_positions,
			component_outer_radius,
			origin_filter,
			collision_filter
		)

	var nearest_origin_raw = get_nearest_snap_origin(
		world_pos,
		components_container,
		seed_positions,
		blocked_positions,
		component_outer_radius,
		origin_filter,
		collision_filter
	)
	if nearest_origin_raw == null:
		if bool(dual_candidate.get("valid", false)):
			return dual_candidate
		return {"valid": false, "position": world_pos}

	var nearest_origin := nearest_origin_raw as Dictionary
	if nearest_origin.is_empty():
		if bool(dual_candidate.get("valid", false)):
			return dual_candidate
		return {"valid": false, "position": world_pos}

	var _origin_pos: Vector2 = nearest_origin["position"]
	var _origin_radius: float = nearest_origin["radius"]
	var candidate := _get_snap_candidate_for_origin(world_pos, nearest_origin, component_outer_radius)
	if not _is_world_position_valid(candidate, component_outer_radius):
		return {
			"valid": false,
			"position": candidate,
			"origin": nearest_origin
		}
	var is_close_enough := candidate.distance_to(world_pos) <= snap_max_distance
	var is_clear := not _is_too_close(candidate, components_container, blocked_positions, component_outer_radius, collision_filter)
	var single_candidate := {
		"valid": is_close_enough and is_clear,
		"position": candidate,
		"origin": nearest_origin
	}

	if bool(dual_candidate.get("valid", false)):
		var dual_pos := dual_candidate.get("position", world_pos) as Vector2
		if not bool(single_candidate.get("valid", false)):
			return dual_candidate
		if dual_pos.distance_to(world_pos) <= candidate.distance_to(world_pos):
			return dual_candidate

	return single_candidate


func can_place_at(
	world_pos: Vector2,
	components_container: Node,
	blocked_positions: Array = [],
	component_outer_radius: float = component_radius,
	collision_filter: Callable = Callable()
) -> bool:
	if components_container == null:
		return false
	if not _is_world_position_valid(world_pos, component_outer_radius):
		return false

	return not _is_too_close(world_pos, components_container, blocked_positions, component_outer_radius, collision_filter)


func _get_snap_origins_uncached(components_container: Node, seed_positions: Array) -> Array:
	var origins: Array = []

	for seed_pos in seed_positions:
		var seed_data := _to_origin_data(seed_pos)
		if not seed_data.is_empty():
			var seed_world_pos: Vector2 = seed_data["position"]
			if _is_world_position_valid(seed_world_pos, 0.0):
				origins.append(seed_data)

	for child in components_container.get_children():
		var placed_component := child as Node2D
		if not placed_component:
			continue

		var port_origins := _get_component_port_snap_origins(placed_component)
		if not port_origins.is_empty():
			for port_origin_raw in port_origins:
				var port_origin := port_origin_raw as Dictionary
				if port_origin.is_empty():
					continue
				var port_pos: Vector2 = port_origin.get("position", Vector2.ZERO)
				if _is_world_position_valid(port_pos, 0.0):
					origins.append(port_origin)
			continue

		if _is_world_position_valid(placed_component.global_position, 0.0):
			origins.append({
				"position": placed_component.global_position,
				"radius": _get_node_connection_radius(placed_component),
				"node": placed_component
			})

	return origins


func _push_nearest_origin_candidate(candidates: Array, origin: Dictionary, distance_to_mouse: float) -> void:
	var insert_at := candidates.size()
	for index in range(candidates.size()):
		var current := candidates[index] as Dictionary
		if current.is_empty():
			continue
		if distance_to_mouse < float(current.get("distance", INF)):
			insert_at = index
			break

	candidates.insert(insert_at, {
		"origin": origin,
		"distance": distance_to_mouse
	})

	if candidates.size() > MAX_ORIGIN_CLEARANCE_TESTS:
		candidates.resize(MAX_ORIGIN_CLEARANCE_TESTS)


func _get_edge_snap_candidate(world_pos: Vector2, origin: Vector2, origin_radius: float, component_outer_radius: float) -> Vector2:
	var direction := world_pos - origin
	if direction.length_squared() < 0.0001:
		direction = Vector2.RIGHT
	else:
		direction = direction.normalized()
	return origin + (direction * (origin_radius + component_outer_radius))


func _get_snap_candidate_for_origin(world_pos: Vector2, origin_data: Dictionary, component_outer_radius: float) -> Vector2:
	var origin_pos: Vector2 = origin_data.get("position", Vector2.ZERO) as Vector2
	var origin_radius: float = float(origin_data.get("radius", 0.0))
	if origin_data.has("fixed_direction"):
		var fixed_direction: Vector2 = origin_data.get("fixed_direction", Vector2.RIGHT) as Vector2
		if fixed_direction.length_squared() < 0.0001:
			fixed_direction = Vector2.RIGHT
		else:
			fixed_direction = fixed_direction.normalized()
		return origin_pos + (fixed_direction * (origin_radius + component_outer_radius))

	return _get_edge_snap_candidate(world_pos, origin_pos, origin_radius, component_outer_radius)


func _get_dual_snap_result(
	world_pos: Vector2,
	components_container: Node,
	seed_positions: Array,
	blocked_positions: Array,
	component_outer_radius: float,
	origin_filter: Callable = Callable(),
	collision_filter: Callable = Callable()
) -> Dictionary:
	var origins := _get_query_origins(components_container, seed_positions)
	if origins.size() < 2:
		return {"valid": false, "position": world_pos}

	var nearest_origins: Array = []
	for origin_raw in origins:
		var origin_data := _to_origin_data(origin_raw)
		if origin_data.is_empty():
			continue
		if origin_filter.is_valid() and not bool(origin_filter.call(origin_data)):
			continue
		var distance_to_mouse := (origin_data.get("position", Vector2.ZERO) as Vector2).distance_to(world_pos)
		_push_dual_origin_candidate(nearest_origins, origin_data, distance_to_mouse)

	var best_pos := Vector2.ZERO
	var best_distance := INF
	for i in range(nearest_origins.size()):
		var a_entry := nearest_origins[i] as Dictionary
		var origin_a := a_entry.get("origin", {}) as Dictionary
		if origin_a.is_empty():
			continue
		var center_a: Vector2 = origin_a["position"]
		var snap_radius_a: float = float(origin_a["radius"]) + component_outer_radius

		for j in range(i + 1, nearest_origins.size()):
			var b_entry := nearest_origins[j] as Dictionary
			var origin_b := b_entry.get("origin", {}) as Dictionary
			if origin_b.is_empty():
				continue

			var center_b: Vector2 = origin_b["position"]
			var snap_radius_b: float = float(origin_b["radius"]) + component_outer_radius
			for intersection in _circle_intersections(center_a, snap_radius_a, center_b, snap_radius_b):
				var point := intersection as Vector2
				var distance_to_mouse := point.distance_to(world_pos)
				if distance_to_mouse > snap_max_distance:
					continue
				if _is_too_close(point, components_container, blocked_positions, component_outer_radius, collision_filter):
					continue
				if distance_to_mouse < best_distance:
					best_distance = distance_to_mouse
					best_pos = point

	if best_distance == INF:
		return {"valid": false, "position": world_pos}

	return {
		"valid": true,
		"position": best_pos,
		"origin": {}
	}


func _push_dual_origin_candidate(candidates: Array, origin: Dictionary, distance_to_mouse: float) -> void:
	var insert_at := candidates.size()
	for index in range(candidates.size()):
		var current := candidates[index] as Dictionary
		if current.is_empty():
			continue
		if distance_to_mouse < float(current.get("distance", INF)):
			insert_at = index
			break

	candidates.insert(insert_at, {
		"origin": origin,
		"distance": distance_to_mouse
	})

	if candidates.size() > MAX_DUAL_SNAP_ORIGINS:
		candidates.resize(MAX_DUAL_SNAP_ORIGINS)


func _circle_intersections(c1: Vector2, r1: float, c2: Vector2, r2: float) -> Array:
	var delta := c2 - c1
	var d := delta.length()
	if d <= 0.0001:
		return []
	if d > r1 + r2 + 0.0001:
		return []
	if d < absf(r1 - r2) - 0.0001:
		return []

	var a := ((r1 * r1) - (r2 * r2) + (d * d)) / (2.0 * d)
	var h_sq := (r1 * r1) - (a * a)
	if h_sq < 0.0:
		if h_sq > -0.0001:
			h_sq = 0.0
		else:
			return []
	var h := sqrt(h_sq)
	var dir := delta / d
	var midpoint := c1 + (dir * a)
	var perp := Vector2(-dir.y, dir.x)

	if h <= 0.0001:
		return [midpoint]

	return [
		midpoint + (perp * h),
		midpoint - (perp * h)
	]


func _is_too_close(candidate: Vector2, components_container: Node, blocked_positions: Array = [], component_outer_radius: float = component_radius, collision_filter: Callable = Callable()) -> bool:
	if _has_valid_mesh_cache_for(components_container):
		var component_query_radius := component_outer_radius + _mesh_cache_max_component_radius + 2.0
		var nearby_component_indices := _query_grid_indices(_mesh_cache_components_grid, candidate, component_query_radius)
		for component_index_raw in nearby_component_indices:
			var component_index := int(component_index_raw)
			if component_index < 0 or component_index >= _mesh_cache_components.size():
				continue
			var component_entry := _mesh_cache_components[component_index] as Dictionary
			if component_entry.is_empty():
				continue
			var placed_component := component_entry.get("node", null) as Node2D
			if placed_component == null:
				continue
			if collision_filter.is_valid() and not bool(collision_filter.call(placed_component)):
				continue
			var placed_pos := component_entry.get("position", Vector2.ZERO) as Vector2
			var placed_radius := float(component_entry.get("radius", component_radius))
			var component_min_distance := placed_radius + component_outer_radius - 0.6
			if placed_pos.distance_to(candidate) < component_min_distance:
				return true

		var use_cached_blocked := not blocked_positions.is_empty() and blocked_positions.size() == _mesh_cache_blocked_count
		if use_cached_blocked:
			var blocked_small_query_radius := component_outer_radius + _mesh_cache_max_blocked_small_radius + 2.0
			var nearby_blocked_indices := _query_grid_indices(_mesh_cache_blocked_small_grid, candidate, blocked_small_query_radius)
			for blocked_index_raw in nearby_blocked_indices:
				var blocked_index := int(blocked_index_raw)
				if blocked_index < 0 or blocked_index >= _mesh_cache_blocked_small.size():
					continue
				var blocked_entry := _mesh_cache_blocked_small[blocked_index] as Dictionary
				if blocked_entry.is_empty():
					continue
				var blocked_pos := blocked_entry.get("position", Vector2.ZERO) as Vector2
				var blocked_radius := float(blocked_entry.get("radius", 0.0))
				var blocked_min_distance := blocked_radius + component_outer_radius - 1.0
				if blocked_pos.distance_to(candidate) < blocked_min_distance:
					return true

			for blocked_entry_raw in _mesh_cache_blocked_large:
				var blocked_large := blocked_entry_raw as Dictionary
				if blocked_large.is_empty():
					continue
				var blocked_large_pos := blocked_large.get("position", Vector2.ZERO) as Vector2
				var blocked_large_radius := float(blocked_large.get("radius", 0.0))
				var blocked_large_min_distance := blocked_large_radius + component_outer_radius - 1.0
				if blocked_large_pos.distance_to(candidate) < blocked_large_min_distance:
					return true
		else:
			for blocked_raw in blocked_positions:
				var blocked_data := _to_origin_data(blocked_raw)
				if blocked_data.is_empty():
					continue
				var blocked_pos: Vector2 = blocked_data["position"]
				var blocked_radius: float = blocked_data["radius"]
				var blocked_min_distance := blocked_radius + component_outer_radius - 1.0
				if blocked_pos.distance_to(candidate) < blocked_min_distance:
					return true
		return false

	for child in components_container.get_children():
		var placed_component := child as Node2D
		if not placed_component:
			continue
		if collision_filter.is_valid() and not bool(collision_filter.call(placed_component)):
			continue
		var placed_radius := _get_node_block_radius(placed_component)
		# Use pairwise radius tangency for variable-size gears; a global clearance floor
		# would incorrectly block valid placements after applying contact-radius meshing.
		var component_min_distance := placed_radius + component_outer_radius - 0.6
		if placed_component.global_position.distance_to(candidate) < component_min_distance:
			return true

	for blocked_raw in blocked_positions:
		var blocked_data := _to_origin_data(blocked_raw)
		if blocked_data.is_empty():
			continue
		var blocked_pos: Vector2 = blocked_data["position"]
		var blocked_radius: float = blocked_data["radius"]
		var blocked_min_distance := blocked_radius + component_outer_radius - 1.0
		if blocked_pos.distance_to(candidate) < blocked_min_distance:
			return true

	return false


func _grid_key(cell_x: int, cell_y: int) -> String:
	return "%d:%d" % [cell_x, cell_y]


func _grid_insert(grid: Dictionary, world_pos: Vector2, index: int) -> void:
	var cell_x := int(floor(world_pos.x / MESH_CACHE_CELL_SIZE))
	var cell_y := int(floor(world_pos.y / MESH_CACHE_CELL_SIZE))
	var key := _grid_key(cell_x, cell_y)
	if not grid.has(key):
		grid[key] = []
	(grid[key] as Array).append(index)


func _query_grid_indices(grid: Dictionary, world_pos: Vector2, radius: float) -> Array:
	if grid.is_empty():
		return []
	var safe_radius := maxf(radius, 0.0)
	var center_x := int(floor(world_pos.x / MESH_CACHE_CELL_SIZE))
	var center_y := int(floor(world_pos.y / MESH_CACHE_CELL_SIZE))
	var cell_radius := int(ceil(safe_radius / MESH_CACHE_CELL_SIZE))
	var indices: Array = []
	var seen: Dictionary = {}
	for cy in range(center_y - cell_radius, center_y + cell_radius + 1):
		for cx in range(center_x - cell_radius, center_x + cell_radius + 1):
			var key := _grid_key(cx, cy)
			if not grid.has(key):
				continue
			for idx_raw in (grid[key] as Array):
				var idx := int(idx_raw)
				if seen.has(idx):
					continue
				seen[idx] = true
				indices.append(idx)
	return indices


func get_mesh_cache_stats() -> Dictionary:
	return {
		"valid": _mesh_cache_valid,
		"origins": _mesh_cache_origins.size(),
		"components": _mesh_cache_components.size(),
		"blocked_small": _mesh_cache_blocked_small.size(),
		"blocked_large": _mesh_cache_blocked_large.size(),
		"blocked_total": _mesh_cache_blocked_count,
		"max_component_radius": _mesh_cache_max_component_radius,
		"max_blocked_small_radius": _mesh_cache_max_blocked_small_radius,
	}


func _get_node_outer_radius(node: Node2D) -> float:
	if node == null:
		return component_radius

	var visual := node.get_node_or_null("Visual")
	if visual == null:
		return component_radius

	var mesh_radius := 0.0
	var anchor_mesh_radius: Variant = node.get("source_outer_radius")
	if anchor_mesh_radius != null:
		mesh_radius = maxf(float(anchor_mesh_radius), 0.0)

	var radius_value: Variant = visual.get("outer_radius")
	if radius_value == null:
		if mesh_radius > 0.0:
			return mesh_radius
		return component_radius

	var visual_radius := maxf(float(radius_value), 0.0)
	if mesh_radius <= 0.0:
		return visual_radius
	# Keep mesh contact radius aligned with the rendered shell size.
	return maxf(mesh_radius, visual_radius)


func _get_node_connection_radius(node: Node2D) -> float:
	var outer_radius := _get_node_outer_radius(node)
	return maxf(2.0, outer_radius - PROJECT_PATHS_SCRIPT.GEAR_MESH_CONTACT_MARGIN)


func _get_node_block_radius(node: Node2D) -> float:
	if node and node.has_meta("flywheel_block_radius"):
		return maxf(2.0, float(node.get_meta("flywheel_block_radius")))
	return _get_node_connection_radius(node)


func _to_origin_data(entry: Variant) -> Dictionary:
	if entry is Dictionary:
		var pos_value: Variant = entry.get("position", null)
		if pos_value is Vector2:
			var data := {
				"position": pos_value,
				"radius": float(entry.get("radius", component_radius))
			}
			if entry.has("node"):
				data["node"] = entry.get("node")
			if entry.has("fixed_direction"):
				data["fixed_direction"] = entry.get("fixed_direction")
			return data
		return {}

	if entry is Vector2:
		return {
			"position": entry,
			"radius": component_radius
		}

	return {}


func _get_component_port_snap_origins(_node: Node2D) -> Array:
	return []
