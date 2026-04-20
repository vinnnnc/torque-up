extends RefCounted
class_name PlacementRules

const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")

var socket_count: int = 8
var socket_radius: float = PROJECT_PATHS_SCRIPT.DEFAULT_SOCKET_RADIUS
var snap_max_distance: float = PROJECT_PATHS_SCRIPT.DEFAULT_SNAP_MAX_DISTANCE
var placement_clearance: float = PROJECT_PATHS_SCRIPT.DEFAULT_PLACEMENT_CLEARANCE
var marker_samples: int = 24
var component_radius: float = PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS

const MAX_ORIGIN_CLEARANCE_TESTS := 6
const DENSE_LAYOUT_COMPONENT_THRESHOLD := 180
const DENSE_LAYOUT_MARKER_SAMPLES := 10
const MAX_DUAL_SNAP_ORIGINS := 10


func get_snap_origins(components_container: Node, seed_positions: Array = []) -> Array:
	return _get_snap_origins(components_container, seed_positions)


func get_available_socket_positions(
	components_container: Node,
	seed_positions: Array = [],
	blocked_positions: Array = [],
	component_outer_radius: float = component_radius
) -> Array:
	if components_container == null:
		return []

	var positions: Array = []
	var origins := _get_snap_origins(components_container, seed_positions)
	for origin_raw in origins:
		var origin_data := _to_origin_data(origin_raw)
		if origin_data.is_empty():
			continue

		if origin_data.has("fixed_direction"):
			var fixed_candidate := _get_snap_candidate_for_origin(Vector2.ZERO, origin_data, component_outer_radius)
			if not _is_too_close(fixed_candidate, components_container, blocked_positions, component_outer_radius):
				positions.append(fixed_candidate)
			continue

		var origin: Vector2 = origin_data["position"]
		var origin_radius: float = origin_data["radius"]
		for sample_index in range(marker_samples):
			var angle := TAU * (float(sample_index) / float(marker_samples))
			var candidate := origin + Vector2.RIGHT.rotated(angle) * (origin_radius + component_outer_radius)
			if _is_too_close(candidate, components_container, blocked_positions, component_outer_radius):
				continue
			positions.append(candidate)

	return positions


func get_nearest_available_socket_positions(
	world_pos: Vector2,
	components_container: Node,
	seed_positions: Array = [],
	blocked_positions: Array = [],
	component_outer_radius: float = component_radius
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
		component_outer_radius
	)
	if origin == null:
		return []

	var positions: Array = []
	if origin.has("fixed_direction"):
		var fixed_candidate := _get_snap_candidate_for_origin(world_pos, origin, component_outer_radius)
		if not _is_too_close(fixed_candidate, components_container, blocked_positions, component_outer_radius):
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
		if _is_too_close(candidate, components_container, blocked_positions, component_outer_radius):
			continue
		positions.append(candidate)

	return positions


func get_nearest_snap_origin(
	world_pos: Vector2,
	components_container: Node,
	seed_positions: Array = [],
	blocked_positions: Array = [],
	component_outer_radius: float = component_radius
):
	if components_container == null:
		return null

	var origins := _get_snap_origins(components_container, seed_positions)
	if origins.is_empty():
		return null

	var nearest_candidates: Array = []
	for origin_raw in origins:
		var origin_data := _to_origin_data(origin_raw)
		if origin_data.is_empty():
			continue

		var origin_pos: Vector2 = origin_data["position"]
		var distance_to_mouse := origin_pos.distance_to(world_pos)
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
		if not _is_too_close(edge_candidate, components_container, blocked_positions, component_outer_radius):
			return candidate_origin

	return null

func get_snap_result(
	world_pos: Vector2,
	components_container: Node,
	seed_positions: Array = [],
	blocked_positions: Array = [],
	component_outer_radius: float = component_radius
) -> Dictionary:
	if components_container == null:
		return {"valid": false, "position": world_pos}

	var dual_candidate := _get_dual_snap_result(
		world_pos,
		components_container,
		seed_positions,
		blocked_positions,
		component_outer_radius
	)

	var nearest_origin_raw = get_nearest_snap_origin(
		world_pos,
		components_container,
		seed_positions,
		blocked_positions,
		component_outer_radius
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
	var is_close_enough := candidate.distance_to(world_pos) <= snap_max_distance
	var is_clear := not _is_too_close(candidate, components_container, blocked_positions, component_outer_radius)
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
	component_outer_radius: float = component_radius
) -> bool:
	if components_container == null:
		return false

	return not _is_too_close(world_pos, components_container, blocked_positions, component_outer_radius)


func _get_snap_origins(components_container: Node, seed_positions: Array) -> Array:
	var origins: Array = []
	var stacked_parent_ids: Dictionary = {}

	for child in components_container.get_children():
		var stacked_node := child as Node2D
		if stacked_node == null:
			continue
		if stacked_node.has_meta("stack_parent_id"):
			var parent_id := int(stacked_node.get_meta("stack_parent_id", -1))
			if parent_id >= 0:
				stacked_parent_ids[parent_id] = true

	for seed_pos in seed_positions:
		var seed_data := _to_origin_data(seed_pos)
		if not seed_data.is_empty():
			origins.append(seed_data)

	for child in components_container.get_children():
		var placed_component := child as Node2D
		if not placed_component:
			continue

		if stacked_parent_ids.has(placed_component.get_instance_id()):
			# When a compound gear exists, snap to the top gear rather than the base gear.
			continue

		if _is_shaft_component(placed_component):
			var shaft_radius := _get_shaft_connection_radius(placed_component)
			var shaft_dir := Vector2.RIGHT.rotated(placed_component.rotation)
			origins.append({
				"position": placed_component.global_position + (shaft_dir * shaft_radius),
				"radius": PROJECT_PATHS_SCRIPT.SHAFT_ENDPOINT_ORIGIN_RADIUS,
				"node": placed_component
			})
			origins.append({
				"position": placed_component.global_position - (shaft_dir * shaft_radius),
				"radius": PROJECT_PATHS_SCRIPT.SHAFT_ENDPOINT_ORIGIN_RADIUS,
				"node": placed_component
			})
			continue

		var port_origins := _get_component_port_snap_origins(placed_component)
		if not port_origins.is_empty():
			for port_origin_raw in port_origins:
				var port_origin := port_origin_raw as Dictionary
				if port_origin.is_empty():
					continue
				origins.append(port_origin)
			continue

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
	component_outer_radius: float
) -> Dictionary:
	var origins := _get_snap_origins(components_container, seed_positions)
	if origins.size() < 2:
		return {"valid": false, "position": world_pos}

	var nearest_origins: Array = []
	for origin_raw in origins:
		var origin_data := _to_origin_data(origin_raw)
		if origin_data.is_empty():
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
				if _is_too_close(point, components_container, blocked_positions, component_outer_radius):
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


func _is_too_close(candidate: Vector2, components_container: Node, blocked_positions: Array = [], component_outer_radius: float = component_radius) -> bool:
	for child in components_container.get_children():
		var placed_component := child as Node2D
		if not placed_component:
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


func _get_node_outer_radius(node: Node2D) -> float:
	if node == null:
		return component_radius

	var visual := node.get_node_or_null("Visual")
	if visual == null:
		return component_radius

	var radius_value: Variant = visual.get("outer_radius")
	if radius_value == null:
		return component_radius

	return float(radius_value)


func _get_node_connection_radius(node: Node2D) -> float:
	if node and str(node.get_meta("component_type", "")) == PROJECT_PATHS_SCRIPT.COMPONENT_FLYWHEEL and node.has_meta("shaft_connection_radius"):
		return maxf(2.0, float(node.get_meta("shaft_connection_radius")))
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


func _is_shaft_component(node: Node2D) -> bool:
	if node == null or not node.has_meta("component_type"):
		return false

	return str(node.get_meta("component_type")) == PROJECT_PATHS_SCRIPT.COMPONENT_SHAFT


func _has_stacked_child(components_container: Node, base_node: Node2D) -> bool:
	if components_container == null or base_node == null:
		return false

	var base_id := base_node.get_instance_id()
	for child in components_container.get_children():
		var node := child as Node2D
		if node == null or node == base_node:
			continue
		if int(node.get_meta("stack_parent_id", -1)) == base_id:
			return true

	return false


func _get_shaft_connection_radius(node: Node2D) -> float:
	if node and node.has_meta("shaft_connection_radius"):
		return maxf(0.0, float(node.get_meta("shaft_connection_radius")))

	return _get_node_connection_radius(node)


func _get_component_port_snap_origins(node: Node2D) -> Array:
	if node == null or not node.has_meta("component_type"):
		return []

	var component_type := str(node.get_meta("component_type"))
	if component_type == PROJECT_PATHS_SCRIPT.COMPONENT_FLYWHEEL:
		var shaft_radius := _get_shaft_connection_radius(node)
		var shaft_dir := Vector2.RIGHT.rotated(node.global_rotation)
		return [
			{
				"position": node.global_position + (shaft_dir * shaft_radius),
				"radius": PROJECT_PATHS_SCRIPT.SHAFT_ENDPOINT_ORIGIN_RADIUS,
				"node": node
			},
			{
				"position": node.global_position - (shaft_dir * shaft_radius),
				"radius": PROJECT_PATHS_SCRIPT.SHAFT_ENDPOINT_ORIGIN_RADIUS,
				"node": node
			}
		]

	var local_ports: Array = []
	match component_type:
		PROJECT_PATHS_SCRIPT.COMPONENT_CLUTCH:
			# Center-based shaft ports: visible on top, hidden on back
			local_ports = [0.0, PI]
		PROJECT_PATHS_SCRIPT.COMPONENT_DIFFERENTIAL:
			# Center-based shaft ports: input on top, outputs on sides
			local_ports = [0.0, PI * 0.5, -PI * 0.5]
		_:
			return []

	var snap_origins: Array = []
	for port_angle_raw in local_ports:
		var port_angle: float = float(port_angle_raw) + node.global_rotation
		var outward: Vector2 = Vector2.RIGHT.rotated(port_angle)
		# Shaft ports snap at component center, not on perimeter
		snap_origins.append({
			"position": node.global_position,
			"radius": 0.0,
			"fixed_direction": outward,
			"node": node
		})

	return snap_origins
