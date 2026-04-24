extends RefCounted
class_name NetworkService

const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")
const COMPONENT_RADIUS: float = PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS


## Build a thread-safe graph snapshot from the current scene graph.
## Returned data contains plain Dictionaries/Arrays only (no Node refs).
func build_graph_snapshot(
	components_container: Node,
	relay_nodes: Array = [],
	connection_tolerance: float = 8.0
) -> Dictionary:
	if components_container == null:
		return {}

	var runtime_nodes: Array = []
	var component_ids: Array = []

	for child in components_container.get_children():
		var gear := child as Node2D
		if not gear:
			continue
		var gear_id := gear.get_instance_id()
		component_ids.append(gear_id)
		runtime_nodes.append({
			"key": gear_id,
			"node": gear,
			"position": gear.global_position,
			"radius": _get_node_connection_radius(gear),
			"drive_radius": _get_node_outer_radius(gear),
			"drive_teeth": _get_node_tooth_count(gear),
			"component_type": _get_component_type(gear)
		})

	for relay_raw in relay_nodes:
		var relay := relay_raw as Node2D
		if relay == null:
			continue
		var relay_id := relay.get_instance_id()
		var duplicate := false
		for existing_raw in runtime_nodes:
			var existing := existing_raw as Dictionary
			if int(existing.get("key", -1)) == relay_id:
				duplicate = true
				break
		if duplicate:
			continue
		runtime_nodes.append({
			"key": relay_id,
			"node": relay,
			"position": relay.global_position,
			"radius": _get_node_connection_radius(relay),
			"drive_radius": _get_node_outer_radius(relay),
			"drive_teeth": _get_node_tooth_count(relay),
			"component_type": _get_component_type(relay)
		})

	var nodes_by_id: Dictionary = {}
	var adjacency: Dictionary = {}
	var max_node_radius := 0.0
	for node_raw in runtime_nodes:
		var node_data := node_raw as Dictionary
		var node_id := int(node_data.get("key", -1))
		if node_id < 0:
			continue
		var node_radius := float(node_data.get("radius", COMPONENT_RADIUS))
		max_node_radius = maxf(max_node_radius, node_radius)
		nodes_by_id[node_id] = {
			"key": node_id,
			"position": node_data.get("position", Vector2.ZERO),
			"radius": node_radius,
			"drive_radius": float(node_data.get("drive_radius", COMPONENT_RADIUS)),
			"drive_teeth": int(node_data.get("drive_teeth", 0)),
			"component_type": str(node_data.get("component_type", ""))
		}
		adjacency[node_id] = []

	var snapshot_cell_size := maxf(64.0, (max_node_radius * 2.0) + connection_tolerance + 4.0)
	var spatial_grid: Dictionary = {}
	for node_index in range(runtime_nodes.size()):
		var indexed_node := runtime_nodes[node_index] as Dictionary
		_snapshot_grid_insert(
			spatial_grid,
			indexed_node.get("position", Vector2.ZERO) as Vector2,
			node_index,
			snapshot_cell_size
		)

	for i in range(runtime_nodes.size()):
		var node_a := runtime_nodes[i] as Dictionary
		var node_a_pos := node_a.get("position", Vector2.ZERO) as Vector2
		var node_a_radius := float(node_a.get("radius", COMPONENT_RADIUS))
		var query_radius := node_a_radius + max_node_radius + connection_tolerance + 2.0
		var nearby_indices := _snapshot_grid_query(spatial_grid, node_a_pos, query_radius, snapshot_cell_size)
		for j_raw in nearby_indices:
			var j := int(j_raw)
			if j <= i:
				continue
			var node_b := runtime_nodes[j] as Dictionary
			if not _nodes_are_connected(node_a, node_b, connection_tolerance):
				continue

			var a_id := int(node_a.get("key", -1))
			var b_id := int(node_b.get("key", -1))
			if a_id < 0 or b_id < 0:
				continue

			var sign_ab := _get_connection_sign_multiplier(node_a, node_b)
			var ratio_ab := _compute_edge_ratio(node_a, node_b)
			var sign_ba := _get_connection_sign_multiplier(node_b, node_a)
			var ratio_ba := _compute_edge_ratio(node_b, node_a)

			(adjacency[a_id] as Array).append({
				"to": b_id,
				"sign": sign_ab,
				"ratio": ratio_ab
			})
			(adjacency[b_id] as Array).append({
				"to": a_id,
				"sign": sign_ba,
				"ratio": ratio_ba
			})

	return {
		"nodes_by_id": nodes_by_id,
		"adjacency": adjacency,
		"component_ids": component_ids,
		"connection_tolerance": connection_tolerance
	}


func get_reachable_component_ids_from_snapshot(snapshot: Dictionary, source_id: int) -> Array:
	var reachable: Array = []
	if snapshot.is_empty() or source_id < 0:
		return reachable

	var adjacency := snapshot.get("adjacency", {}) as Dictionary
	if not adjacency.has(source_id):
		return reachable

	var component_set := _build_id_set(snapshot.get("component_ids", []) as Array)
	var queue: Array = [source_id]
	var visited: Dictionary = {source_id: true}

	while not queue.is_empty():
		var current_id := int(queue.pop_front())
		var neighbors := adjacency.get(current_id, []) as Array
		for edge_raw in neighbors:
			if not edge_raw is Dictionary:
				continue
			var edge := edge_raw as Dictionary
			var neighbor_id := int(edge.get("to", -1))
			if neighbor_id < 0 or visited.has(neighbor_id):
				continue
			visited[neighbor_id] = true
			queue.push_back(neighbor_id)
			if component_set.has(neighbor_id):
				reachable.append(neighbor_id)

	return reachable


func get_drive_multipliers_from_snapshot(snapshot: Dictionary, source_id: int) -> Dictionary:
	var multipliers: Dictionary = {}
	if snapshot.is_empty() or source_id < 0:
		return multipliers

	var adjacency := snapshot.get("adjacency", {}) as Dictionary
	if not adjacency.has(source_id):
		return multipliers

	var queue: Array = [source_id]
	var visited: Dictionary = {source_id: true}
	multipliers[source_id] = 1.0

	while not queue.is_empty():
		var current_id := int(queue.pop_front())
		var current_multiplier := float(multipliers.get(current_id, 1.0))
		var neighbors := adjacency.get(current_id, []) as Array
		for edge_raw in neighbors:
			if not edge_raw is Dictionary:
				continue
			var edge := edge_raw as Dictionary
			var neighbor_id := int(edge.get("to", -1))
			if neighbor_id < 0 or visited.has(neighbor_id):
				continue
			var sign_mult := float(edge.get("sign", 1.0))
			var ratio := float(edge.get("ratio", 1.0))
			multipliers[neighbor_id] = current_multiplier * sign_mult * ratio
			visited[neighbor_id] = true
			queue.push_back(neighbor_id)

	multipliers.erase(source_id)
	return multipliers


func get_spin_signs_from_snapshot(snapshot: Dictionary, source_id: int) -> Dictionary:
	var signs: Dictionary = {}
	if snapshot.is_empty() or source_id < 0:
		return signs

	var adjacency := snapshot.get("adjacency", {}) as Dictionary
	if not adjacency.has(source_id):
		return signs

	var queue: Array = []
	var seed_edges := adjacency.get(source_id, []) as Array
	for edge_raw in seed_edges:
		if not edge_raw is Dictionary:
			continue
		var edge := edge_raw as Dictionary
		var seed_id := int(edge.get("to", -1))
		if seed_id < 0 or signs.has(seed_id):
			continue
		signs[seed_id] = -1.0
		queue.push_back(seed_id)

	while not queue.is_empty():
		var current_id := int(queue.pop_front())
		var current_sign := float(signs.get(current_id, 1.0))
		var neighbors := adjacency.get(current_id, []) as Array
		for edge_raw in neighbors:
			if not edge_raw is Dictionary:
				continue
			var edge := edge_raw as Dictionary
			var neighbor_id := int(edge.get("to", -1))
			if neighbor_id < 0 or neighbor_id == source_id or signs.has(neighbor_id):
				continue
			var sign_multiplier := float(edge.get("sign", 1.0))
			signs[neighbor_id] = current_sign * sign_multiplier
			queue.push_back(neighbor_id)

	return signs


func get_direction_conflicts_from_snapshot(snapshot: Dictionary, source_id: int) -> Array:
	if snapshot.is_empty() or source_id < 0:
		return []

	var adjacency := snapshot.get("adjacency", {}) as Dictionary
	if not adjacency.has(source_id):
		return []

	var assigned: Dictionary = {}
	var conflict_ids: Dictionary = {}
	var queue: Array = []

	var seed_edges := adjacency.get(source_id, []) as Array
	for edge_raw in seed_edges:
		if not edge_raw is Dictionary:
			continue
		var edge := edge_raw as Dictionary
		var seed_id := int(edge.get("to", -1))
		if seed_id < 0:
			continue
		assigned[seed_id] = -1.0
		queue.push_back(seed_id)

	while not queue.is_empty():
		var current_id := int(queue.pop_front())
		var current_sign := float(assigned.get(current_id, 1.0))
		var neighbors := adjacency.get(current_id, []) as Array
		for edge_raw in neighbors:
			if not edge_raw is Dictionary:
				continue
			var edge := edge_raw as Dictionary
			var neighbor_id := int(edge.get("to", -1))
			if neighbor_id < 0 or neighbor_id == source_id:
				continue

			var sign_mult := float(edge.get("sign", 1.0))
			var expected := current_sign * sign_mult
			if assigned.has(neighbor_id):
				var existing := float(assigned.get(neighbor_id, expected))
				if not is_equal_approx(existing, expected):
					conflict_ids[neighbor_id] = true
					conflict_ids[current_id] = true
			else:
				assigned[neighbor_id] = expected
				queue.push_back(neighbor_id)

	return conflict_ids.keys()


func propagate_speeds_from_snapshot(snapshot: Dictionary, drive_targets: Dictionary) -> Dictionary:
	if snapshot.is_empty() or drive_targets.is_empty():
		return drive_targets.duplicate()

	var adjacency := snapshot.get("adjacency", {}) as Dictionary
	if adjacency.is_empty():
		return drive_targets.duplicate()

	var resolved: Dictionary = drive_targets.duplicate()
	var visited: Dictionary = {}

	var seed_ids: Array = resolved.keys()
	seed_ids.sort_custom(func(a: Variant, b: Variant) -> bool:
		return absf(float(resolved.get(a, 0.0))) > absf(float(resolved.get(b, 0.0)))
	)

	for seed_raw in seed_ids:
		var seed_id := int(seed_raw)
		if visited.has(seed_id):
			continue
		var seed_speed := float(resolved.get(seed_id, 0.0))
		if absf(seed_speed) < 0.001:
			continue
		if not adjacency.has(seed_id):
			continue

		visited[seed_id] = true
		var queue: Array = [seed_id]
		while not queue.is_empty():
			var current_id := int(queue.pop_front())
			var current_speed := float(resolved.get(current_id, 0.0))
			var neighbors := adjacency.get(current_id, []) as Array
			for edge_raw in neighbors:
				if not edge_raw is Dictionary:
					continue
				var edge := edge_raw as Dictionary
				var neighbor_id := int(edge.get("to", -1))
				if neighbor_id < 0 or visited.has(neighbor_id):
					continue

				var sign_mult := float(edge.get("sign", 1.0))
				var ratio := float(edge.get("ratio", 1.0))
				resolved[neighbor_id] = current_speed * sign_mult * ratio
				visited[neighbor_id] = true
				queue.push_back(neighbor_id)

	return resolved


func compute_threaded_graph_cache(
	component_snapshot: Dictionary,
	source_nodes: Array,
	engine_data: Dictionary = {}
) -> Dictionary:
	if component_snapshot.is_empty():
		return {}

	var reachable_by_source: Dictionary = {}
	var multipliers_by_source: Dictionary = {}
	var spin_signs_by_source: Dictionary = {}
	var conflicts_by_source: Dictionary = {}
	var connected_source_ids: Array = []
	var engine_reachable_component_ids: Array = []
	var anchor_multipliers_by_id: Dictionary = {}
	var engine_reachable_set: Dictionary = {}

	if not engine_data.is_empty():
		var engine_seed_components := _get_seed_component_ids(component_snapshot, engine_data)
		engine_reachable_component_ids = _get_reachable_component_ids_from_seed(component_snapshot, engine_seed_components)
		engine_reachable_set = _build_id_set(engine_reachable_component_ids)

		var engine_id := int(engine_data.get("id", -1))
		if engine_id >= 0:
			anchor_multipliers_by_id[engine_id] = _get_drive_multipliers_from_seed(
				component_snapshot,
				engine_data,
				engine_seed_components
			)

	for source_raw in source_nodes:
		if not source_raw is Dictionary:
			continue
		var source_node := source_raw as Dictionary
		var source_id := int(source_node.get("id", 0))
		if source_id == 0:
			continue

		var source_seed_components := _get_seed_component_ids(component_snapshot, source_node)
		reachable_by_source[source_id] = _get_reachable_component_ids_from_seed(component_snapshot, source_seed_components)

		var source_multipliers := _get_drive_multipliers_from_seed(
			component_snapshot,
			source_node,
			source_seed_components
		)
		multipliers_by_source[source_id] = source_multipliers
		anchor_multipliers_by_id[source_id] = source_multipliers

		spin_signs_by_source[source_id] = _get_spin_signs_from_seed(component_snapshot, source_seed_components)
		var source_direction_conflicts := _get_direction_conflicts_from_seed(component_snapshot, source_seed_components)
		var source_ratio_conflicts := _get_ratio_conflicts_from_seed(component_snapshot, source_node, source_seed_components)
		var merged_conflicts: Dictionary = {}
		for conflict_raw in source_direction_conflicts:
			merged_conflicts[int(conflict_raw)] = true
		for conflict_raw in source_ratio_conflicts:
			merged_conflicts[int(conflict_raw)] = true
		conflicts_by_source[source_id] = merged_conflicts.keys()

		if not engine_reachable_set.is_empty() and _source_touches_component_set(component_snapshot, source_node, engine_reachable_set):
			connected_source_ids.append(source_id)

	# Tier-N: expand connected sources to include nodes adjacent to already-connected
	# sources OR to any component reachable from them (handles node-to-node through gear trains).
	if not connected_source_ids.is_empty() and source_nodes.size() > 1:
		var connected_source_set := _build_id_set(connected_source_ids)
		var snap_tolerance := float(component_snapshot.get("connection_tolerance", 8.0))
		# Accumulate all reachable component ids across connected sources for tier-N checks.
		var tier_n_reachable: Dictionary = engine_reachable_set.duplicate()
		for src_raw in source_nodes:
			if not src_raw is Dictionary:
				continue
			var src_d := src_raw as Dictionary
			var src_id_check := int(src_d.get("id", 0))
			if src_id_check == 0 or not connected_source_set.has(src_id_check):
				continue
			for cid_raw in (reachable_by_source.get(src_id_check, []) as Array):
				tier_n_reachable[int(cid_raw)] = true
		var frontier_changed := true
		while frontier_changed:
			frontier_changed = false
			for candidate_raw in source_nodes:
				if not candidate_raw is Dictionary:
					continue
				var candidate := candidate_raw as Dictionary
				var candidate_id := int(candidate.get("id", 0))
				if candidate_id == 0 or connected_source_set.has(candidate_id):
					continue
				var candidate_pos := candidate.get("position", Vector2.ZERO) as Vector2
				var candidate_radius := float(candidate.get("radius", COMPONENT_RADIUS))
				var is_newly_connected := false
				# Check source-to-source direct contact.
				for peer_raw in source_nodes:
					if not peer_raw is Dictionary:
						continue
					var peer := peer_raw as Dictionary
					var peer_id := int(peer.get("id", 0))
					if peer_id == 0 or not connected_source_set.has(peer_id):
						continue
					var peer_pos := peer.get("position", Vector2.ZERO) as Vector2
					var peer_radius := float(peer.get("radius", COMPONENT_RADIUS))
					if absf(candidate_pos.distance_to(peer_pos) - (candidate_radius + peer_radius)) <= snap_tolerance:
						is_newly_connected = true
						break
				# Check source-to-reachable-component contact.
				if not is_newly_connected:
					is_newly_connected = _source_touches_component_set(component_snapshot, candidate, tier_n_reachable)
				if not is_newly_connected:
					continue
				connected_source_ids.append(candidate_id)
				connected_source_set[candidate_id] = true
				frontier_changed = true
				# Add this source's reachable components for subsequent tier checks.
				for cid_raw in (reachable_by_source.get(candidate_id, []) as Array):
					tier_n_reachable[int(cid_raw)] = true

	# Expand engine_reachable_component_ids to include components reachable from
	# all connected sources (their own gear trains join the scoring network).
	if not connected_source_ids.is_empty():
		var expanded_reachable_set := engine_reachable_set.duplicate()
		for source_raw in source_nodes:
			if not source_raw is Dictionary:
				continue
			var source_node2 := source_raw as Dictionary
			var source_id2 := int(source_node2.get("id", 0))
			if source_id2 == 0:
				continue
			var is_connected_source := false
			for cid_raw in connected_source_ids:
				if int(cid_raw) == source_id2:
					is_connected_source = true
					break
			if not is_connected_source:
				continue
			var source_seeds := _get_seed_component_ids(component_snapshot, source_node2)
			var source_reachable := _get_reachable_component_ids_from_seed(component_snapshot, source_seeds)
			for comp_id_raw in source_reachable:
				var comp_id := int(comp_id_raw)
				if not expanded_reachable_set.has(comp_id):
					expanded_reachable_set[comp_id] = true
					engine_reachable_component_ids.append(comp_id)
		engine_reachable_set = expanded_reachable_set

	return {
		"connected_source_ids": connected_source_ids,
		"engine_reachable_component_ids": engine_reachable_component_ids,
		"reachable_component_ids_by_source": reachable_by_source,
		"source_drive_multipliers_by_id": multipliers_by_source,
		"source_spin_signs_by_id": spin_signs_by_source,
		"source_conflicts_by_id": conflicts_by_source,
		"anchor_multipliers_by_id": anchor_multipliers_by_id
	}


func _get_seed_component_ids(snapshot: Dictionary, seed_node: Dictionary) -> Array:
	var seed_position := seed_node.get("position", Vector2.ZERO) as Vector2
	var seed_radius := maxf(0.0, float(seed_node.get("radius", COMPONENT_RADIUS)))
	var nodes_by_id := snapshot.get("nodes_by_id", {}) as Dictionary
	var component_ids := snapshot.get("component_ids", []) as Array
	var tolerance := float(snapshot.get("connection_tolerance", 8.0))

	var seeds: Array = []
	for component_id_raw in component_ids:
		var component_id := int(component_id_raw)
		var component_data := nodes_by_id.get(component_id, {}) as Dictionary
		if component_data.is_empty():
			continue
		var component_pos := component_data.get("position", Vector2.ZERO) as Vector2
		var component_radius := float(component_data.get("radius", COMPONENT_RADIUS))
		if absf(component_pos.distance_to(seed_position) - (seed_radius + component_radius)) <= tolerance:
			seeds.append(component_id)

	return seeds


func _get_reachable_component_ids_from_seed(snapshot: Dictionary, seed_component_ids: Array) -> Array:
	if seed_component_ids.is_empty():
		return []

	var adjacency := snapshot.get("adjacency", {}) as Dictionary
	var component_set := _build_id_set(snapshot.get("component_ids", []) as Array)
	if adjacency.is_empty():
		return []

	var visited: Dictionary = {}
	var queue: Array = []
	var reachable: Array = []

	for seed_raw in seed_component_ids:
		var seed_id := int(seed_raw)
		if visited.has(seed_id):
			continue
		visited[seed_id] = true
		if component_set.has(seed_id):
			reachable.append(seed_id)
		queue.push_back(seed_id)

	while not queue.is_empty():
		var current_id := int(queue.pop_front())
		var neighbors := adjacency.get(current_id, []) as Array
		for edge_raw in neighbors:
			if not edge_raw is Dictionary:
				continue
			var edge := edge_raw as Dictionary
			var neighbor_id := int(edge.get("to", -1))
			if neighbor_id < 0 or visited.has(neighbor_id):
				continue
			visited[neighbor_id] = true
			if component_set.has(neighbor_id):
				reachable.append(neighbor_id)
			queue.push_back(neighbor_id)

	return reachable


func _get_drive_multipliers_from_seed(snapshot: Dictionary, seed_node: Dictionary, seed_component_ids: Array) -> Dictionary:
	if seed_component_ids.is_empty():
		return {}

	var adjacency := snapshot.get("adjacency", {}) as Dictionary
	var nodes_by_id := snapshot.get("nodes_by_id", {}) as Dictionary
	if adjacency.is_empty() or nodes_by_id.is_empty():
		return {}

	var source_data := {
		"position": seed_node.get("position", Vector2.ZERO),
		"radius": float(seed_node.get("radius", COMPONENT_RADIUS)),
		"drive_radius": float(seed_node.get("drive_radius", seed_node.get("radius", COMPONENT_RADIUS))),
		"drive_teeth": int(seed_node.get("drive_teeth", 0)),
		"component_type": str(seed_node.get("component_type", ""))
	}

	var multipliers: Dictionary = {}
	var visited: Dictionary = {}
	var queue: Array = []

	for seed_raw in seed_component_ids:
		var seed_id := int(seed_raw)
		if visited.has(seed_id):
			continue
		var seed_component := nodes_by_id.get(seed_id, {}) as Dictionary
		if seed_component.is_empty():
			continue

		var seed_sign := _get_connection_sign_multiplier(source_data, seed_component)
		var seed_ratio := _compute_edge_ratio(source_data, seed_component)
		multipliers[seed_id] = seed_sign * seed_ratio
		visited[seed_id] = true
		queue.push_back(seed_id)

	while not queue.is_empty():
		var current_id := int(queue.pop_front())
		var current_multiplier := float(multipliers.get(current_id, 1.0))
		var neighbors := adjacency.get(current_id, []) as Array
		for edge_raw in neighbors:
			if not edge_raw is Dictionary:
				continue
			var edge := edge_raw as Dictionary
			var neighbor_id := int(edge.get("to", -1))
			if neighbor_id < 0 or visited.has(neighbor_id):
				continue
			var sign_mult := float(edge.get("sign", 1.0))
			var ratio := float(edge.get("ratio", 1.0))
			multipliers[neighbor_id] = current_multiplier * sign_mult * ratio
			visited[neighbor_id] = true
			queue.push_back(neighbor_id)

	return multipliers


func _get_spin_signs_from_seed(snapshot: Dictionary, seed_component_ids: Array) -> Dictionary:
	if seed_component_ids.is_empty():
		return {}

	var adjacency := snapshot.get("adjacency", {}) as Dictionary
	if adjacency.is_empty():
		return {}

	var signs: Dictionary = {}
	var queue: Array = []

	for seed_raw in seed_component_ids:
		var seed_id := int(seed_raw)
		if signs.has(seed_id):
			continue
		signs[seed_id] = -1.0
		queue.push_back(seed_id)

	while not queue.is_empty():
		var current_id := int(queue.pop_front())
		var current_sign := float(signs.get(current_id, 1.0))
		var neighbors := adjacency.get(current_id, []) as Array
		for edge_raw in neighbors:
			if not edge_raw is Dictionary:
				continue
			var edge := edge_raw as Dictionary
			var neighbor_id := int(edge.get("to", -1))
			if neighbor_id < 0 or signs.has(neighbor_id):
				continue
			var sign_multiplier := float(edge.get("sign", 1.0))
			signs[neighbor_id] = current_sign * sign_multiplier
			queue.push_back(neighbor_id)

	return signs


func _get_direction_conflicts_from_seed(snapshot: Dictionary, seed_component_ids: Array) -> Array:
	if seed_component_ids.is_empty():
		return []

	var adjacency := snapshot.get("adjacency", {}) as Dictionary
	var component_set := _build_id_set(snapshot.get("component_ids", []) as Array)
	if adjacency.is_empty() or component_set.is_empty():
		return []

	var assigned: Dictionary = {}
	var conflicts: Dictionary = {}
	var queue: Array = []

	for seed_raw in seed_component_ids:
		var seed_id := int(seed_raw)
		if assigned.has(seed_id):
			continue
		assigned[seed_id] = -1.0
		queue.push_back(seed_id)

	while not queue.is_empty():
		var current_id := int(queue.pop_front())
		var current_sign := float(assigned.get(current_id, 1.0))
		var neighbors := adjacency.get(current_id, []) as Array
		for edge_raw in neighbors:
			if not edge_raw is Dictionary:
				continue
			var edge := edge_raw as Dictionary
			var neighbor_id := int(edge.get("to", -1))
			if neighbor_id < 0:
				continue

			var expected := current_sign * float(edge.get("sign", 1.0))
			if assigned.has(neighbor_id):
				var existing := float(assigned.get(neighbor_id, expected))
				if not is_equal_approx(existing, expected):
					if component_set.has(neighbor_id):
						conflicts[neighbor_id] = true
					if component_set.has(current_id):
						conflicts[current_id] = true
			else:
				assigned[neighbor_id] = expected
				queue.push_back(neighbor_id)

	return conflicts.keys()


func _get_ratio_conflicts_from_seed(snapshot: Dictionary, seed_node: Dictionary, seed_component_ids: Array) -> Array:
	if seed_component_ids.is_empty():
		return []

	var adjacency := snapshot.get("adjacency", {}) as Dictionary
	var nodes_by_id := snapshot.get("nodes_by_id", {}) as Dictionary
	if adjacency.is_empty() or nodes_by_id.is_empty():
		return []

	var component_set := _build_id_set(snapshot.get("component_ids", []) as Array)
	var source_data := {
		"position": seed_node.get("position", Vector2.ZERO),
		"radius": float(seed_node.get("radius", COMPONENT_RADIUS)),
		"drive_radius": float(seed_node.get("drive_radius", seed_node.get("radius", COMPONENT_RADIUS))),
		"drive_teeth": int(seed_node.get("drive_teeth", 0)),
		"component_type": str(seed_node.get("component_type", ""))
	}

	var assigned: Dictionary = {}
	var conflicts: Dictionary = {}
	var queue: Array = []

	for seed_raw in seed_component_ids:
		var seed_id := int(seed_raw)
		var seed_component := nodes_by_id.get(seed_id, {}) as Dictionary
		if seed_component.is_empty():
			continue
		var seed_sign := _get_connection_sign_multiplier(source_data, seed_component)
		var seed_ratio := _compute_edge_ratio(source_data, seed_component)
		assigned[seed_id] = seed_sign * seed_ratio
		queue.push_back(seed_id)

	while not queue.is_empty():
		var current_id := int(queue.pop_front())
		var current_multiplier := float(assigned.get(current_id, 0.0))
		var neighbors := adjacency.get(current_id, []) as Array
		for edge_raw in neighbors:
			if not edge_raw is Dictionary:
				continue
			var edge := edge_raw as Dictionary
			var neighbor_id := int(edge.get("to", -1))
			if neighbor_id < 0:
				continue

			var expected := current_multiplier * float(edge.get("sign", 1.0)) * float(edge.get("ratio", 1.0))
			if assigned.has(neighbor_id):
				var existing := float(assigned.get(neighbor_id, expected))
				var tolerance := maxf(0.03, absf(expected) * 0.08)
				if absf(existing - expected) > tolerance:
					if component_set.has(current_id):
						conflicts[current_id] = true
					if component_set.has(neighbor_id):
						conflicts[neighbor_id] = true
					# If a relay node (source/engine) carries the inconsistency,
					# project the conflict to adjacent components for stable jam handling.
					if not component_set.has(current_id):
						for relay_edge_raw in neighbors:
							if not relay_edge_raw is Dictionary:
								continue
							var relay_edge := relay_edge_raw as Dictionary
							var relay_neighbor := int(relay_edge.get("to", -1))
							if component_set.has(relay_neighbor):
								conflicts[relay_neighbor] = true
			else:
				assigned[neighbor_id] = expected
				queue.push_back(neighbor_id)

	return conflicts.keys()


func _source_touches_component_set(snapshot: Dictionary, source_node: Dictionary, component_set: Dictionary) -> bool:
	if component_set.is_empty():
		return false

	var source_position := source_node.get("position", Vector2.ZERO) as Vector2
	var source_radius := maxf(0.0, float(source_node.get("radius", COMPONENT_RADIUS)))
	var nodes_by_id := snapshot.get("nodes_by_id", {}) as Dictionary
	var tolerance := float(snapshot.get("connection_tolerance", 8.0))

	for component_id_raw in component_set.keys():
		var component_id := int(component_id_raw)
		var component_data := nodes_by_id.get(component_id, {}) as Dictionary
		if component_data.is_empty():
			continue
		var component_pos := component_data.get("position", Vector2.ZERO) as Vector2
		var component_radius := float(component_data.get("radius", COMPONENT_RADIUS))
		if absf(component_pos.distance_to(source_position) - (source_radius + component_radius)) <= tolerance:
			return true

	return false


func _build_id_set(ids: Array) -> Dictionary:
	var result: Dictionary = {}
	for id_raw in ids:
		var id := int(id_raw)
		if id < 0:
			continue
		result[id] = true
	return result


func _snapshot_grid_key(cell_x: int, cell_y: int) -> String:
	return "%d:%d" % [cell_x, cell_y]


func _snapshot_grid_insert(grid: Dictionary, world_pos: Vector2, node_index: int, cell_size: float) -> void:
	var safe_cell_size := maxf(cell_size, 1.0)
	var cell_x := int(floor(world_pos.x / safe_cell_size))
	var cell_y := int(floor(world_pos.y / safe_cell_size))
	var key := _snapshot_grid_key(cell_x, cell_y)
	if not grid.has(key):
		grid[key] = []
	(grid[key] as Array).append(node_index)


func _snapshot_grid_query(grid: Dictionary, world_pos: Vector2, radius: float, cell_size: float) -> Array:
	if grid.is_empty():
		return []
	var safe_cell_size := maxf(cell_size, 1.0)
	var safe_radius := maxf(radius, 0.0)
	var center_x := int(floor(world_pos.x / safe_cell_size))
	var center_y := int(floor(world_pos.y / safe_cell_size))
	var cell_radius := int(ceil(safe_radius / safe_cell_size))
	var result: Array = []
	var seen: Dictionary = {}
	for y in range(center_y - cell_radius, center_y + cell_radius + 1):
		for x in range(center_x - cell_radius, center_x + cell_radius + 1):
			var key := _snapshot_grid_key(x, y)
			if not grid.has(key):
				continue
			for idx_raw in (grid[key] as Array):
				var idx := int(idx_raw)
				if seen.has(idx):
					continue
				seen[idx] = true
				result.append(idx)
	return result


func _build_runtime_graph_nodes(components_container: Node, extra_nodes: Array = []) -> Dictionary:
	var graph_nodes: Array = []
	var max_radius := 0.0

	if components_container != null:
		for child in components_container.get_children():
			var gear := child as Node2D
			if not gear:
				continue
			var radius := _get_node_connection_radius(gear)
			max_radius = maxf(max_radius, radius)
			graph_nodes.append({
				"key": gear.get_instance_id(),
				"node": gear,
				"position": gear.global_position,
				"radius": radius,
				"drive_radius": _get_node_outer_radius(gear),
				"drive_teeth": _get_node_tooth_count(gear),
				"component_type": _get_component_type(gear)
			})

	for extra_raw in extra_nodes:
		if not extra_raw is Dictionary:
			continue
		var extra_node := extra_raw as Dictionary
		var extra_radius := float(extra_node.get("radius", COMPONENT_RADIUS))
		max_radius = maxf(max_radius, extra_radius)
		graph_nodes.append(extra_node)

	var cell_size := maxf(64.0, (max_radius * 2.0) + 12.0)
	var spatial_grid: Dictionary = {}
	for node_index in range(graph_nodes.size()):
		var node_data := graph_nodes[node_index] as Dictionary
		_snapshot_grid_insert(
			spatial_grid,
			node_data.get("position", Vector2.ZERO) as Vector2,
			node_index,
			cell_size
		)

	return {
		"nodes": graph_nodes,
		"grid": spatial_grid,
		"cell_size": cell_size,
		"max_radius": max_radius,
	}


func _query_runtime_neighbor_indices(
	spatial_grid: Dictionary,
	world_pos: Vector2,
	node_radius: float,
	max_radius: float,
	connection_tolerance: float,
	cell_size: float
) -> Array:
	var query_radius := maxf(node_radius, 0.0) + maxf(max_radius, 0.0) + connection_tolerance + 2.0
	return _snapshot_grid_query(spatial_grid, world_pos, query_radius, cell_size)

func get_component_count_from_container(components_container: Node) -> int:
	if components_container == null:
		return 0
	return components_container.get_child_count()

func get_available_torque_from_sources(power_sources: Array, load_ratio: float = 0.0) -> float:
	var total_torque: float = 0.0
	for source_raw in power_sources:
		var power_source := source_raw as Node2D
		if power_source == null:
			continue

		if power_source.has_method("get_power_output"):
			total_torque += float(power_source.call("get_power_output", load_ratio))
			continue

		var rated_value: Variant = power_source.get("rated_torque_output")
		if rated_value != null:
			total_torque += float(rated_value)
		else:
			total_torque += PROJECT_PATHS_SCRIPT.BASE_POWER_NODE_OUTPUT
	return total_torque

func get_used_torque(component_count: int) -> float:
	"""Returns torque spent on placed gears."""
	return float(component_count) * PROJECT_PATHS_SCRIPT.FRICTION_DEFAULT_COMPONENT


func get_used_torque_from_components(components_container: Node) -> float:
	return get_friction_load_from_components(components_container)


func get_friction_load_from_components(components_container: Node) -> float:
	if components_container == null:
		return 0.0

	var profiles := get_component_profiles_from_container(components_container)
	return get_friction_load_for_profiles(profiles)


func get_used_torque_for_components(components: Array) -> float:
	return get_friction_load_for_components(components)


func get_friction_load_for_components(components: Array) -> float:
	var profiles := get_component_profiles_from_list(components)
	return get_friction_load_for_profiles(profiles)


func get_component_profiles_from_container(components_container: Node) -> Array:
	if components_container == null:
		return []

	var profiles: Array = []
	for child in components_container.get_children():
		var node := child as Node2D
		if not node:
			continue
		profiles.append(get_component_profile(node))

	return profiles


func get_component_profiles_from_list(components: Array) -> Array:
	var profiles: Array = []
	for component_raw in components:
		var node := component_raw as Node2D
		if not node:
			continue
		profiles.append(get_component_profile(node))

	return profiles


func get_friction_load_for_profiles(profiles: Array) -> float:
	var friction_load := 0.0
	for profile_raw in profiles:
		if not profile_raw is Dictionary:
			continue
		var profile := profile_raw as Dictionary
		friction_load += float(profile.get("friction", PROJECT_PATHS_SCRIPT.FRICTION_DEFAULT_COMPONENT))

	return friction_load


func get_component_profile(node: Node2D) -> Dictionary:
	if node == null:
		return {}

	var component_type: String = ""
	if node.has_meta("component_type"):
		component_type = str(node.get_meta("component_type"))

	var outer_radius := _get_node_outer_radius(node)
	var profile := {
		"id": node.get_instance_id(),
		"node": node,
		"type": component_type,
		"outer_radius": outer_radius,
		"connection_radius": _get_node_connection_radius(node),
		"tooth_count": _get_node_tooth_count(node),
		"friction": _get_component_friction_load(node),
		"inertia": _get_component_inertia(node),
		"max_torque": _get_component_max_torque(node)
	}

	return profile

func compute_efficiency(connection_count: int) -> float:
	var loss := float(connection_count) * PROJECT_PATHS_SCRIPT.EFFICIENCY_LOSS_PER_CONNECTION
	return clamp(1.0 - loss, PROJECT_PATHS_SCRIPT.MIN_EFFICIENCY, 1.0)


func is_path_connected(
	components_container: Node,
	source_world_pos: Vector2,
	engine_world_pos: Vector2,
	_connection_distance: float,
	connection_tolerance: float = 8.0,
	source_radius: float = COMPONENT_RADIUS,
	engine_radius: float = COMPONENT_RADIUS,
	relay_nodes: Array = []
) -> bool:
	if components_container == null:
		return false

	var nodes := _build_network_nodes(
		components_container,
		source_world_pos,
		engine_world_pos,
		source_radius,
		engine_radius,
		relay_nodes
	)
	if nodes.size() < 2:
		return false

	var source_index := 0
	var engine_index := 1
	var queue: Array = [source_index]
	var visited: Dictionary = {}
	visited[source_index] = true

	while not queue.is_empty():
		var current_index: int = queue.pop_front()
		if current_index == engine_index:
			return true

		for neighbor_index in range(nodes.size()):
			if neighbor_index == current_index or visited.has(neighbor_index):
				continue

			var current_node: Dictionary = nodes[current_index]
			var neighbor_node: Dictionary = nodes[neighbor_index]
			if not _nodes_are_connected(current_node, neighbor_node, connection_tolerance):
				continue

			visited[neighbor_index] = true
			queue.push_back(neighbor_index)

	return false


func get_component_spin_signs(
	components_container: Node,
	source_world_pos: Vector2,
	_connection_distance: float,
	connection_tolerance: float = 8.0,
	source_radius: float = COMPONENT_RADIUS
) -> Dictionary:
	return get_network_spin_signs(
		components_container,
		source_world_pos,
		source_radius,
		[],
		connection_tolerance
	)


func get_network_spin_signs(
	components_container: Node,
	source_world_pos: Vector2,
	source_radius: float = COMPONENT_RADIUS,
	extra_nodes: Array = [],
	connection_tolerance: float = 8.0
) -> Dictionary:
	var signs: Dictionary = {}
	if components_container == null:
		return signs

	var runtime_graph := _build_runtime_graph_nodes(components_container, extra_nodes)
	var graph_nodes := runtime_graph.get("nodes", []) as Array
	var spatial_grid := runtime_graph.get("grid", {}) as Dictionary
	var cell_size := float(runtime_graph.get("cell_size", 64.0))
	var max_radius := float(runtime_graph.get("max_radius", COMPONENT_RADIUS))

	var queue: Array = []
	for node_index in _query_runtime_neighbor_indices(spatial_grid, source_world_pos, source_radius, max_radius, connection_tolerance, cell_size):
		var node_data := graph_nodes[int(node_index)] as Dictionary
		var node_key: Variant = node_data.get("key", null)
		if node_key == null:
			continue
		var node_pos: Vector2 = node_data.get("position", Vector2.ZERO)
		var node_radius: float = float(node_data.get("radius", COMPONENT_RADIUS))
		var source_distance := node_pos.distance_to(source_world_pos)
		if absf(source_distance - (source_radius + node_radius)) <= connection_tolerance:
			signs[node_key] = -1.0
			queue.push_back(node_data)

	while not queue.is_empty():
		var current: Dictionary = queue.pop_front()
		var current_key: Variant = current.get("key", null)
		var current_sign := float(signs.get(current_key, 1.0))

		for neighbor_index in _query_runtime_neighbor_indices(
			spatial_grid,
			current.get("position", Vector2.ZERO) as Vector2,
			float(current.get("radius", COMPONENT_RADIUS)),
			max_radius,
			connection_tolerance,
			cell_size
		):
			var neighbor: Dictionary = graph_nodes[int(neighbor_index)] as Dictionary
			var neighbor_key: Variant = neighbor.get("key", null)
			if neighbor_key == null or neighbor_key == current_key or signs.has(neighbor_key):
				continue

			if not _nodes_are_connected(current, neighbor, connection_tolerance):
				continue

			var sign_multiplier := _get_connection_sign_multiplier(current, neighbor)
			signs[neighbor_key] = current_sign * sign_multiplier
			queue.push_back(neighbor)

	return signs


func get_direction_conflicts(
	components_container: Node,
	source_world_pos: Vector2,
	source_radius: float = COMPONENT_RADIUS,
	extra_nodes: Array = [],
	connection_tolerance: float = 8.0
) -> Array:
	"""BFS spin-sign pass that detects contradictions. Returns Array of instance IDs
	where two different required signs meet — these components are in conflict."""
	if components_container == null:
		return []

	var runtime_graph := _build_runtime_graph_nodes(components_container, extra_nodes)
	var graph_nodes := runtime_graph.get("nodes", []) as Array
	var spatial_grid := runtime_graph.get("grid", {}) as Dictionary
	var cell_size := float(runtime_graph.get("cell_size", 64.0))
	var max_radius := float(runtime_graph.get("max_radius", COMPONENT_RADIUS))

	var assigned: Dictionary = {}
	var conflict_ids: Dictionary = {}
	var queue: Array = []

	# Seed directly from source.
	for node_index in _query_runtime_neighbor_indices(spatial_grid, source_world_pos, source_radius, max_radius, connection_tolerance, cell_size):
		var node_data := graph_nodes[int(node_index)] as Dictionary
		var node_key: Variant = node_data.get("key", null)
		if node_key == null:
			continue
		var node_pos: Vector2 = node_data.get("position", Vector2.ZERO)
		var node_radius: float = float(node_data.get("radius", COMPONENT_RADIUS))
		if absf(node_pos.distance_to(source_world_pos) - (source_radius + node_radius)) <= connection_tolerance:
			assigned[node_key] = -1.0
			queue.push_back(node_data)

	while not queue.is_empty():
		var current: Dictionary = queue.pop_front()
		var current_key: Variant = current.get("key", null)
		var current_sign := float(assigned.get(current_key, 1.0))

		for neighbor_index in _query_runtime_neighbor_indices(
			spatial_grid,
			current.get("position", Vector2.ZERO) as Vector2,
			float(current.get("radius", COMPONENT_RADIUS)),
			max_radius,
			connection_tolerance,
			cell_size
		):
			var neighbor: Dictionary = graph_nodes[int(neighbor_index)] as Dictionary
			var neighbor_key: Variant = neighbor.get("key", null)
			if neighbor_key == null or neighbor_key == current_key:
				continue

			if not _nodes_are_connected(current, neighbor, connection_tolerance):
				continue

			var sign_mult := _get_connection_sign_multiplier(current, neighbor)
			var expected := current_sign * sign_mult

			if assigned.has(neighbor_key):
				var existing := float(assigned[neighbor_key])
				if not is_equal_approx(existing, expected):
					conflict_ids[neighbor_key] = true
					conflict_ids[current_key] = true
			else:
				assigned[neighbor_key] = expected
				queue.push_back(neighbor)

	return conflict_ids.keys()


func get_network_drive_multipliers(
	components_container: Node,
	source_world_pos: Vector2,
	source_radius: float = COMPONENT_RADIUS,
	source_drive_radius: float = COMPONENT_RADIUS,
	source_drive_teeth: int = 0,
	extra_nodes: Array = [],
	connection_tolerance: float = 8.0
) -> Dictionary:
	var multipliers: Dictionary = {}
	if components_container == null:
		return multipliers

	var runtime_graph := _build_runtime_graph_nodes(components_container, extra_nodes)
	var graph_nodes := runtime_graph.get("nodes", []) as Array
	var spatial_grid := runtime_graph.get("grid", {}) as Dictionary
	var cell_size := float(runtime_graph.get("cell_size", 64.0))
	var max_radius := float(runtime_graph.get("max_radius", COMPONENT_RADIUS))

	var queue: Array = []
	var source_key: int = -1
	var source_node := {
		"key": source_key,
		"position": source_world_pos,
		"radius": source_radius,
		"drive_radius": source_drive_radius,
		"drive_teeth": source_drive_teeth
	}
	queue.push_back(source_node)
	var visited: Dictionary = {source_key: true}

	while not queue.is_empty():
		var current: Dictionary = queue.pop_front()
		var current_key: Variant = current.get("key", null)
		var current_multiplier := 1.0 if current_key == source_key else float(multipliers.get(current_key, 1.0))
		var current_radius: float = float(current.get("radius", COMPONENT_RADIUS))
		var current_drive_radius: float = float(current.get("drive_radius", current_radius))
		var current_drive_teeth: int = int(current.get("drive_teeth", 0))

		for neighbor_index in _query_runtime_neighbor_indices(
			spatial_grid,
			current.get("position", Vector2.ZERO) as Vector2,
			float(current.get("radius", COMPONENT_RADIUS)),
			max_radius,
			connection_tolerance,
			cell_size
		):
			var neighbor: Dictionary = graph_nodes[int(neighbor_index)] as Dictionary
			var neighbor_key: Variant = neighbor.get("key", null)
			if neighbor_key == null or visited.has(neighbor_key):
				continue

			if not _nodes_are_connected(current, neighbor, connection_tolerance):
				continue

			var neighbor_drive_teeth: int = int(neighbor.get("drive_teeth", 0))
			var neighbor_drive_radius: float = float(neighbor.get("drive_radius", neighbor.get("radius", COMPONENT_RADIUS)))
			var ratio := 1.0
			if current_drive_teeth > 0 and neighbor_drive_teeth > 0:
				ratio = float(current_drive_teeth) / float(neighbor_drive_teeth)
			elif neighbor_drive_radius > 0.0001:
				ratio = current_drive_radius / neighbor_drive_radius

			var sign_multiplier := _get_connection_sign_multiplier(current, neighbor)
			multipliers[neighbor_key] = current_multiplier * sign_multiplier * ratio
			visited[neighbor_key] = true
			queue.push_back(neighbor)

	return multipliers


## Extract the speed ratio for one directed edge (current → neighbor).
## Returns the scalar by which current's angular speed maps to neighbor's
## angular speed (sign handled separately by _get_connection_sign_multiplier).
func _compute_edge_ratio(current: Dictionary, neighbor: Dictionary) -> float:
	var current_drive_teeth := int(current.get("drive_teeth", 0))
	var neighbor_drive_teeth := int(neighbor.get("drive_teeth", 0))
	if current_drive_teeth > 0 and neighbor_drive_teeth > 0:
		return float(current_drive_teeth) / float(neighbor_drive_teeth)
	var current_drive_radius := float(current.get("drive_radius", current.get("radius", COMPONENT_RADIUS)))
	var neighbor_drive_radius := float(neighbor.get("drive_radius", neighbor.get("radius", COMPONENT_RADIUS)))
	if neighbor_drive_radius > 0.0001:
		return current_drive_radius / neighbor_drive_radius
	return 1.0


## After a multi-source fastest-wins merge, individual components in the same
## connected gear subgraph may have geometrically inconsistent speeds (one
## source won component X, a different source won adjacent component Y, but
## X_speed * ratio ≠ Y_speed).  This re-propagates speeds from the
## highest-speed seed in each subgraph so the entire graph is consistent.
## Conflict/stall entries (speed == 0) are treated as passthrough; the caller
## should re-apply conflict overrides afterward.
func propagate_speeds_from_settled(
	components_container: Node,
	drive_targets: Dictionary,
	connection_tolerance: float,
	relay_nodes: Array = []
) -> Dictionary:
	if components_container == null or drive_targets.is_empty():
		return drive_targets.duplicate()

	var all_nodes: Array = []
	for child in components_container.get_children():
		var gear := child as Node2D
		if not gear:
			continue
		all_nodes.append({
			"key": gear.get_instance_id(),
			"node": gear,
			"position": gear.global_position,
			"radius": _get_node_connection_radius(gear),
			"drive_radius": _get_node_outer_radius(gear),
			"drive_teeth": _get_node_tooth_count(gear),
			"component_type": _get_component_type(gear)
		})

	# Include relay nodes (power sources, engine) so BFS can bridge segments
	# whose only path passes through a node outside components_container.
	# Their computed speeds land in resolved but are harmless — _apply_component_drive_targets
	# only iterates components_container children, so relay IDs are never acted on.
	for relay_raw in relay_nodes:
		var relay := relay_raw as Node2D
		if relay == null:
			continue
		all_nodes.append({
			"key": relay.get_instance_id(),
			"node": relay,
			"position": relay.global_position,
			"radius": _get_node_connection_radius(relay),
			"drive_radius": _get_node_outer_radius(relay),
			"drive_teeth": _get_node_tooth_count(relay),
			"component_type": _get_component_type(relay)
		})

	var resolved: Dictionary = drive_targets.duplicate()
	var visited: Dictionary = {}

	# Sort seeds fastest-first so the highest-speed component wins each subgraph.
	var seed_ids: Array = resolved.keys()
	seed_ids.sort_custom(func(a: Variant, b: Variant) -> bool:
		return absf(float(resolved.get(a, 0.0))) > absf(float(resolved.get(b, 0.0)))
	)

	for seed_id_raw in seed_ids:
		var seed_id := int(seed_id_raw)
		if visited.has(seed_id):
			continue
		var seed_speed := float(resolved.get(seed_id, 0.0))
		if absf(seed_speed) < 0.001:
			continue

		var seed_data: Dictionary = {}
		for node_raw in all_nodes:
			if int(node_raw.get("key", -1)) == seed_id:
				seed_data = node_raw as Dictionary
				break
		if seed_data.is_empty():
			continue

		visited[seed_id] = true
		var queue: Array = [seed_data]
		while not queue.is_empty():
			var current: Dictionary = queue.pop_front() as Dictionary
			var current_id := int(current.get("key", -1))
			var current_speed := float(resolved.get(current_id, 0.0))

			for neighbor_raw in all_nodes:
				var neighbor: Dictionary = neighbor_raw as Dictionary
				var neighbor_id := int(neighbor.get("key", -1))
				if visited.has(neighbor_id):
					continue
				if not _nodes_are_connected(current, neighbor, connection_tolerance):
					continue

				var sign_mult := _get_connection_sign_multiplier(current, neighbor)
				var ratio := _compute_edge_ratio(current, neighbor)
				resolved[neighbor_id] = current_speed * sign_mult * ratio
				visited[neighbor_id] = true
				queue.push_back(neighbor)

	return resolved


func get_reachable_components_from_source(
	components_container: Node,
	source_world_pos: Vector2,
	_connection_distance: float,
	connection_tolerance: float = 8.0,
	source_radius: float = COMPONENT_RADIUS
) -> Array:
	"""Returns all components reachable from the power source via BFS."""
	var reachable: Array = []
	if components_container == null:
		return reachable

	var runtime_graph := _build_runtime_graph_nodes(components_container)
	var graph_nodes := runtime_graph.get("nodes", []) as Array
	var spatial_grid := runtime_graph.get("grid", {}) as Dictionary
	var cell_size := float(runtime_graph.get("cell_size", 64.0))
	var max_radius := float(runtime_graph.get("max_radius", COMPONENT_RADIUS))

	# Find all components directly adjacent to source
	var queue: Array = []
	var visited: Dictionary = {}
	for node_index in _query_runtime_neighbor_indices(spatial_grid, source_world_pos, source_radius, max_radius, connection_tolerance, cell_size):
		var gear_data := graph_nodes[int(node_index)] as Dictionary
		var gear_node := gear_data.get("node", null) as Node2D
		if gear_node == null:
			continue
		var gear_radius := _get_node_connection_radius(gear_node)
		var source_distance: float = gear_node.global_position.distance_to(source_world_pos)
		if absf(source_distance - (source_radius + gear_radius)) <= connection_tolerance:
			var gear_id: int = gear_node.get_instance_id()
			visited[gear_id] = true
			queue.push_back(gear_node)
			reachable.append(gear_node)

	# BFS to find all transitively reachable components
	while not queue.is_empty():
		var current := queue.pop_front() as Node2D
		if not current:
			continue

		for node_index in _query_runtime_neighbor_indices(spatial_grid, current.global_position, _get_node_connection_radius(current), max_radius, connection_tolerance, cell_size):
			var neighbor_data := graph_nodes[int(node_index)] as Dictionary
			var neighbor := neighbor_data.get("node", null) as Node2D
			if neighbor == null:
				continue
			var neighbor_id: int = neighbor.get_instance_id()
			if visited.has(neighbor_id):
				continue

			var current_data := {
				"node": current,
				"position": current.global_position,
				"radius": _get_node_connection_radius(current)
			}
			var neighbor_connection_data := {
				"node": neighbor,
				"position": neighbor.global_position,
				"radius": _get_node_connection_radius(neighbor)
			}
			if not _nodes_are_connected(current_data, neighbor_connection_data, connection_tolerance):
				continue

			visited[neighbor_id] = true
			queue.push_back(neighbor)
			reachable.append(neighbor)

	return reachable


func _build_network_nodes(
	components_container: Node,
	source_world_pos: Vector2,
	engine_world_pos: Vector2,
	source_radius: float,
	engine_radius: float,
	relay_nodes: Array = []
) -> Array:
	var nodes: Array = [
		{"position": source_world_pos, "radius": source_radius},
		{"position": engine_world_pos, "radius": engine_radius}
	]

	for child in components_container.get_children():
		var placed_component := child as Node2D
		if not placed_component:
			continue
		nodes.append({
			"node": placed_component,
			"position": placed_component.global_position,
			"radius": _get_node_connection_radius(placed_component)
		})

	# Other power sources and scene nodes (not in components_container) can
	# relay torque flow between gear segments they are meshed with. Include
	# them as passthrough nodes so the path BFS can traverse through them.
	for relay_raw in relay_nodes:
		var relay := relay_raw as Node2D
		if relay == null:
			continue
		# Skip the source itself — it is already index 0.
		if relay.global_position.is_equal_approx(source_world_pos):
			continue
		nodes.append({
			"node": relay,
			"position": relay.global_position,
			"radius": _get_node_connection_radius(relay)
		})

	return nodes


func _nodes_are_connected(node_a: Dictionary, node_b: Dictionary, tolerance: float) -> bool:
	var node_a_ref := node_a.get("node", null) as Node2D
	var node_b_ref := node_b.get("node", null) as Node2D
	var type_a := str(node_a.get("component_type", _get_component_type(node_a_ref)))
	var type_b := str(node_b.get("component_type", _get_component_type(node_b_ref)))

	var pos_a: Vector2 = node_a.get("position", Vector2.ZERO)
	var pos_b: Vector2 = node_b.get("position", Vector2.ZERO)
	var radius_a: float = float(node_a.get("radius", COMPONENT_RADIUS))
	var radius_b: float = float(node_b.get("radius", COMPONENT_RADIUS))
	var edge_distance := pos_a.distance_to(pos_b)
	if absf(edge_distance - (radius_a + radius_b)) > tolerance:
		return false

	if _mesh_blocked_by_sprocket_mode(node_a_ref, node_b_ref, type_a, type_b):
		return false

	return true


func _get_connection_sign_multiplier(node_a: Dictionary, node_b: Dictionary) -> float:
	var _node_a_ref := node_a.get("node", null) as Node2D
	var _node_b_ref := node_b.get("node", null) as Node2D
	return -1.0


func _get_node_outer_radius(node: Node2D) -> float:
	if node == null:
		return COMPONENT_RADIUS

	var visual := node.get_node_or_null("Visual")
	if visual == null:
		return COMPONENT_RADIUS

	var radius_value: Variant = visual.get("outer_radius")
	if radius_value == null:
		return COMPONENT_RADIUS

	return float(radius_value)


func _get_node_connection_radius(node: Node2D) -> float:
	var outer_radius := _get_node_outer_radius(node)
	return maxf(2.0, outer_radius - PROJECT_PATHS_SCRIPT.GEAR_MESH_CONTACT_MARGIN)


func _get_component_torque_cost(node: Node2D) -> float:
	return _get_component_friction_load(node)


func _get_component_friction_load(node: Node2D) -> float:
	var component_type: String = ""
	if node and node.has_meta("component_type"):
		component_type = str(node.get_meta("component_type"))

	match component_type:
		PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_SMALL:
			return PROJECT_PATHS_SCRIPT.FRICTION_SMALL_GEAR
		PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_LARGE:
			return PROJECT_PATHS_SCRIPT.FRICTION_LARGE_GEAR
		PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_MEDIUM:
			return PROJECT_PATHS_SCRIPT.FRICTION_MEDIUM_GEAR

	var radius := _get_node_outer_radius(node)
	var radius_ratio := radius / PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS
	var multiplier := pow(maxf(radius_ratio, 0.1), PROJECT_PATHS_SCRIPT.TORQUE_COST_RADIUS_EXPONENT)
	return PROJECT_PATHS_SCRIPT.FRICTION_DEFAULT_COMPONENT * multiplier


func _get_component_inertia(node: Node2D) -> float:
	var radius := _get_node_outer_radius(node)
	var radius_ratio := radius / PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS
	return maxf(0.05, radius_ratio * radius_ratio)


func _get_component_max_torque(node: Node2D) -> float:
	var radius := _get_node_outer_radius(node)
	var radius_ratio := radius / PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS
	return PROJECT_PATHS_SCRIPT.BASE_POWER_NODE_OUTPUT * maxf(0.4, radius_ratio)


func _get_component_type(node: Node2D) -> String:
	if node == null or not node.has_meta("component_type"):
		return ""

	return str(node.get_meta("component_type"))


func _mesh_blocked_by_sprocket_mode(_node_a: Node2D, _node_b: Node2D, _type_a: String, _type_b: String) -> bool:
	# Allow sprocket-mode gears to continue meshing so chain-connected islands
	# can still relay through existing gear trains.
	return false


func _is_standard_gear_component_type(component_type: String) -> bool:
	return component_type == PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_SMALL or component_type == PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_MEDIUM or component_type == PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_LARGE


func _is_sprocket_mode(node: Node2D) -> bool:
	if node == null:
		return false
	if node.has_method("is_sprocket_mode"):
		return bool(node.call("is_sprocket_mode"))
	var pulley_flag: Variant = node.get("_pulley_mode")
	if pulley_flag != null:
		return bool(pulley_flag)
	return false


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
