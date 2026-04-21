extends RefCounted
class_name NetworkService

const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")
const COMPONENT_RADIUS: float = PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS

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
		"max_torque": _get_component_max_torque(node),
		"compound_added_layers": _get_compound_added_layers(node)
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

	var graph_nodes: Array = []
	for child in components_container.get_children():
		var gear := child as Node2D
		if not gear:
			continue
		graph_nodes.append({
			"key": gear.get_instance_id(),
			"node": gear,
			"component_type": _get_component_type(gear),
			"position": gear.global_position,
			"radius": _get_node_connection_radius(gear)
		})

	for extra_raw in extra_nodes:
		if extra_raw is Dictionary:
			graph_nodes.append(extra_raw)

	var queue: Array = []
	for node_raw in graph_nodes:
		var node_data := node_raw as Dictionary
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

		for neighbor_raw in graph_nodes:
			var neighbor: Dictionary = neighbor_raw as Dictionary
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

	var graph_nodes: Array = []
	for child in components_container.get_children():
		var gear := child as Node2D
		if not gear:
			continue
		graph_nodes.append({
			"key": gear.get_instance_id(),
			"node": gear,
			"component_type": _get_component_type(gear),
			"position": gear.global_position,
			"radius": _get_node_connection_radius(gear)
		})

	for extra_raw in extra_nodes:
		if extra_raw is Dictionary:
			graph_nodes.append(extra_raw)

	var assigned: Dictionary = {}
	var conflict_ids: Dictionary = {}
	var queue: Array = []

	# Seed directly from source.
	for node_raw in graph_nodes:
		var node_data := node_raw as Dictionary
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

		for neighbor_raw in graph_nodes:
			var neighbor: Dictionary = neighbor_raw as Dictionary
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

	var graph_nodes: Array = []
	for child in components_container.get_children():
		var gear := child as Node2D
		if not gear:
			continue
		graph_nodes.append({
			"key": gear.get_instance_id(),
			"node": gear,
			"position": gear.global_position,
			"radius": _get_node_connection_radius(gear),
			"drive_radius": _get_node_outer_radius(gear),
			"drive_teeth": _get_node_tooth_count(gear),
			"component_type": _get_component_type(gear)
		})

	for extra_raw in extra_nodes:
		if extra_raw is Dictionary:
			graph_nodes.append(extra_raw)

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
		var current_component_type: String = str(current.get("component_type", ""))

		for neighbor_raw in graph_nodes:
			var neighbor: Dictionary = neighbor_raw as Dictionary
			var neighbor_key: Variant = neighbor.get("key", null)
			if neighbor_key == null or visited.has(neighbor_key):
				continue

			if not _nodes_are_connected(current, neighbor, connection_tolerance):
				continue

			var neighbor_drive_teeth: int = int(neighbor.get("drive_teeth", 0))
			var neighbor_drive_radius: float = float(neighbor.get("drive_radius", neighbor.get("radius", COMPONENT_RADIUS)))
			var neighbor_component_type: String = str(neighbor.get("component_type", ""))
			var current_node_ref := current.get("node", null) as Node2D
			var neighbor_node_ref := neighbor.get("node", null) as Node2D
			var current_is_connector := current_component_type == PROJECT_PATHS_SCRIPT.COMPONENT_BELT or current_component_type == PROJECT_PATHS_SCRIPT.COMPONENT_CHAIN
			var neighbor_is_connector := neighbor_component_type == PROJECT_PATHS_SCRIPT.COMPONENT_BELT or neighbor_component_type == PROJECT_PATHS_SCRIPT.COMPONENT_CHAIN
			var ratio := 1.0
			if current_node_ref and neighbor_node_ref and _stack_links_nodes(current_node_ref, neighbor_node_ref):
				ratio = 1.0
			elif current_is_connector and not neighbor_is_connector:
				ratio = _get_connector_to_pulley_ratio(current_node_ref, neighbor_node_ref)
			elif neighbor_is_connector and not current_is_connector:
				ratio = 1.0
			elif current_is_connector and neighbor_is_connector:
				ratio = 1.0
			elif current_component_type == PROJECT_PATHS_SCRIPT.COMPONENT_CLUTCH or neighbor_component_type == PROJECT_PATHS_SCRIPT.COMPONENT_CLUTCH:
				ratio = 1.0
			elif current_component_type == PROJECT_PATHS_SCRIPT.COMPONENT_DIFFERENTIAL or neighbor_component_type == PROJECT_PATHS_SCRIPT.COMPONENT_DIFFERENTIAL:
				ratio = 1.0
			elif current_component_type == PROJECT_PATHS_SCRIPT.COMPONENT_SHAFT or neighbor_component_type == PROJECT_PATHS_SCRIPT.COMPONENT_SHAFT:
				ratio = 1.0
			elif current_drive_teeth > 0 and neighbor_drive_teeth > 0:
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
	var current_node_ref := current.get("node", null) as Node2D
	var neighbor_node_ref := neighbor.get("node", null) as Node2D
	var current_component_type := str(current.get("component_type", _get_component_type(current_node_ref)))
	var neighbor_component_type := str(neighbor.get("component_type", _get_component_type(neighbor_node_ref)))
	var current_is_connector := current_component_type == PROJECT_PATHS_SCRIPT.COMPONENT_BELT or current_component_type == PROJECT_PATHS_SCRIPT.COMPONENT_CHAIN
	var neighbor_is_connector := neighbor_component_type == PROJECT_PATHS_SCRIPT.COMPONENT_BELT or neighbor_component_type == PROJECT_PATHS_SCRIPT.COMPONENT_CHAIN
	if current_node_ref and neighbor_node_ref and _stack_links_nodes(current_node_ref, neighbor_node_ref):
		return 1.0
	if current_is_connector and not neighbor_is_connector:
		return _get_connector_to_pulley_ratio(current_node_ref, neighbor_node_ref)
	if neighbor_is_connector or current_is_connector:
		return 1.0
	if current_component_type == PROJECT_PATHS_SCRIPT.COMPONENT_CLUTCH or neighbor_component_type == PROJECT_PATHS_SCRIPT.COMPONENT_CLUTCH:
		return 1.0
	if current_component_type == PROJECT_PATHS_SCRIPT.COMPONENT_DIFFERENTIAL or neighbor_component_type == PROJECT_PATHS_SCRIPT.COMPONENT_DIFFERENTIAL:
		return 1.0
	if current_component_type == PROJECT_PATHS_SCRIPT.COMPONENT_SHAFT or neighbor_component_type == PROJECT_PATHS_SCRIPT.COMPONENT_SHAFT:
		return 1.0
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


func _get_connector_to_pulley_ratio(connector_node: Node2D, target_pulley: Node2D) -> float:
	if connector_node == null or target_pulley == null:
		return 1.0

	var connector := _get_connector_component_node(connector_node)
	if connector == null:
		return 1.0

	var pulley_a := connector.get("pulley_a") as Node2D
	var pulley_b := connector.get("pulley_b") as Node2D
	if pulley_a == null or pulley_b == null:
		return 1.0

	var other_pulley: Node2D = null
	if target_pulley == pulley_a:
		other_pulley = pulley_b
	elif target_pulley == pulley_b:
		other_pulley = pulley_a
	else:
		return 1.0

	var other_teeth := _get_node_tooth_count(other_pulley)
	var target_teeth := _get_node_tooth_count(target_pulley)
	if other_teeth > 0 and target_teeth > 0:
		return float(other_teeth) / float(target_teeth)

	var other_radius := _get_node_outer_radius(other_pulley)
	var target_radius := _get_node_outer_radius(target_pulley)
	if target_radius > 0.0001:
		return other_radius / target_radius

	return 1.0


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

	var all_components: Array = []
	for child in components_container.get_children():
		var gear := child as Node2D
		if gear:
			all_components.append(gear)

	# Find all components directly adjacent to source
	var queue: Array = []
	var visited: Dictionary = {}
	for gear_node in all_components:
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

		for neighbor in all_components:
			var neighbor_id: int = neighbor.get_instance_id()
			if visited.has(neighbor_id):
				continue

			var current_data := {
				"node": current,
				"position": current.global_position,
				"radius": _get_node_connection_radius(current)
			}
			var neighbor_data := {
				"node": neighbor,
				"position": neighbor.global_position,
				"radius": _get_node_connection_radius(neighbor)
			}
			if not _nodes_are_connected(current_data, neighbor_data, connection_tolerance):
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

	var is_connector_a := type_a == PROJECT_PATHS_SCRIPT.COMPONENT_BELT or type_a == PROJECT_PATHS_SCRIPT.COMPONENT_CHAIN
	var is_connector_b := type_b == PROJECT_PATHS_SCRIPT.COMPONENT_BELT or type_b == PROJECT_PATHS_SCRIPT.COMPONENT_CHAIN
	if is_connector_a or is_connector_b:
		if node_a_ref and node_b_ref:
			return _connector_links_node(node_a_ref, node_b_ref) or _connector_links_node(node_b_ref, node_a_ref)
		return false

	if node_a_ref and node_b_ref:
		if _shaft_links_node(node_a_ref, node_b_ref) or _shaft_links_node(node_b_ref, node_a_ref):
			return true

	if node_a_ref and node_b_ref:
		if _stack_links_nodes(node_a_ref, node_b_ref):
			return true

	var pos_a: Vector2 = node_a.get("position", Vector2.ZERO)
	var pos_b: Vector2 = node_b.get("position", Vector2.ZERO)
	var radius_a: float = float(node_a.get("radius", COMPONENT_RADIUS))
	var radius_b: float = float(node_b.get("radius", COMPONENT_RADIUS))
	var edge_distance := pos_a.distance_to(pos_b)
	if absf(edge_distance - (radius_a + radius_b)) > tolerance:
		return false

	# Cross-compound compound-layer conflict check.
	# When two compound stacks are placed such that (L1-A + L2-B) and (L2-A + L1-B)
	# satisfy the same tangent-distance condition simultaneously (same physical tangent
	# point, symmetric radii), both pairs fire and produce contradictory speed ratios.
	# Rule: keep the L2→L1 direction (the foreground gear of each compound connects to
	# the base gear of the other). Block the mirrored L1→L2 connection.
	if node_a_ref != null and node_b_ref != null:
		var layer_a := _get_node_compound_layer(node_a_ref)
		var layer_b := _get_node_compound_layer(node_b_ref)
		var root_a := int(node_a_ref.get_meta("stack_root_id", node_a_ref.get_instance_id()))
		var root_b := int(node_b_ref.get_meta("stack_root_id", node_b_ref.get_instance_id()))
		if root_a != root_b:
			if layer_a == 2 and layer_b == 2:
				return false
			if layer_a != layer_b:
				# Mixed L1+L2 cross-compound: check for symmetric phantom.
				var partner_a := _find_compound_partner_node(node_a_ref)
				var partner_b := _find_compound_partner_node(node_b_ref)
				if partner_a != null and partner_b != null:
					var r_pa := _get_node_connection_radius(partner_a)
					var r_pb := _get_node_connection_radius(partner_b)
					var dist_partners := partner_a.global_position.distance_to(partner_b.global_position)
					if absf(dist_partners - (r_pa + r_pb)) <= tolerance:
						# Symmetric phantom: both L1+L2 and L2+L1 satisfy the distance.
						# Block the L1-A→L2-B direction; keep L2-A→L1-B.
						if layer_a == 1:
							return false

	if node_a_ref and _is_port_limited_component(type_a):
		if not _neighbor_matches_component_ports(node_a_ref, node_b_ref, type_a):
			return false

	if node_b_ref and _is_port_limited_component(type_b):
		if not _neighbor_matches_component_ports(node_b_ref, node_a_ref, type_b):
			return false

	if _mesh_blocked_by_sprocket_mode(node_a_ref, node_b_ref, type_a, type_b):
		return false

	return true


func _get_connection_sign_multiplier(node_a: Dictionary, node_b: Dictionary) -> float:
	var node_a_ref := node_a.get("node", null) as Node2D
	var node_b_ref := node_b.get("node", null) as Node2D
	if node_a_ref and node_b_ref and _stack_links_nodes(node_a_ref, node_b_ref):
		return 1.0

	var type_a := str(node_a.get("component_type", ""))
	var type_b := str(node_b.get("component_type", ""))
	var is_connector_a := type_a == PROJECT_PATHS_SCRIPT.COMPONENT_BELT or type_a == PROJECT_PATHS_SCRIPT.COMPONENT_CHAIN
	var is_connector_b := type_b == PROJECT_PATHS_SCRIPT.COMPONENT_BELT or type_b == PROJECT_PATHS_SCRIPT.COMPONENT_CHAIN
	if is_connector_a or is_connector_b:
		return 1.0
	if type_a == PROJECT_PATHS_SCRIPT.COMPONENT_SHAFT or type_b == PROJECT_PATHS_SCRIPT.COMPONENT_SHAFT:
		return 1.0
	if type_a == PROJECT_PATHS_SCRIPT.COMPONENT_CLUTCH or type_b == PROJECT_PATHS_SCRIPT.COMPONENT_CLUTCH:
		return 1.0
	if type_a == PROJECT_PATHS_SCRIPT.COMPONENT_DIFFERENTIAL or type_b == PROJECT_PATHS_SCRIPT.COMPONENT_DIFFERENTIAL:
		return 1.0
	return -1.0


func _is_port_limited_component(component_type: String) -> bool:
	return component_type == PROJECT_PATHS_SCRIPT.COMPONENT_CLUTCH or component_type == PROJECT_PATHS_SCRIPT.COMPONENT_DIFFERENTIAL


func _neighbor_matches_component_ports(component_node: Node2D, neighbor_node: Node2D, component_type: String) -> bool:
	if component_node == null or neighbor_node == null:
		return false

	var local_ports := _get_component_local_ports(component_type)
	if local_ports.is_empty():
		return true

	var local_angle := (neighbor_node.global_position - component_node.global_position).angle() - component_node.global_rotation
	local_angle = wrapf(local_angle, -PI, PI)
	var tolerance := 0.34

	for port_raw in local_ports:
		var port_angle := wrapf(float(port_raw), -PI, PI)
		var delta := absf(wrapf(local_angle - port_angle, -PI, PI))
		if delta <= tolerance:
			return true

	return false


func _get_node_compound_layer(node: Node2D) -> int:
	if node == null:
		return 1
	if node.has_meta("compound_layer"):
		return clampi(int(node.get_meta("compound_layer")), 1, 2)
	if int(node.get_meta("stack_parent_id", -1)) >= 0:
		return 2
	return 1


## Returns the other gear node in the same compound stack, or null if none.
func _find_compound_partner_node(node: Node2D) -> Node2D:
	if node == null:
		return null
	var parent := node.get_parent()
	if parent == null:
		return null
	var layer := _get_node_compound_layer(node)
	if layer == 2:
		# Layer-2 gear knows its layer-1 partner via stack_parent_id.
		var parent_id := int(node.get_meta("stack_parent_id", -1))
		if parent_id < 0:
			return null
		for sibling in parent.get_children():
			var s := sibling as Node2D
			if s != null and s.get_instance_id() == parent_id:
				return s
	else:
		# Layer-1 gear: find the sibling that has this node as its stack_parent.
		var node_id := node.get_instance_id()
		for sibling in parent.get_children():
			var s := sibling as Node2D
			if s != null and s != node:
				if int(s.get_meta("stack_parent_id", -1)) == node_id:
					return s
	return null


func _get_component_local_ports(component_type: String) -> Array:
	match component_type:
		PROJECT_PATHS_SCRIPT.COMPONENT_CLUTCH:
			return [-PI * 0.5, PI * 0.5]
		PROJECT_PATHS_SCRIPT.COMPONENT_DIFFERENTIAL:
			return [-2.35, -0.79, PI * 0.5]
		_:
			return []


func _stack_links_nodes(node_a: Node2D, node_b: Node2D) -> bool:
	if node_a == null or node_b == null:
		return false

	var a_parent := int(node_a.get_meta("stack_parent_id", -1))
	var b_parent := int(node_b.get_meta("stack_parent_id", -1))
	if a_parent == node_b.get_instance_id() or b_parent == node_a.get_instance_id():
		return true

	var a_root := int(node_a.get_meta("stack_root_id", -1))
	var b_root := int(node_b.get_meta("stack_root_id", -1))
	if a_root == -1 or b_root == -1:
		return false

	if a_root != b_root:
		return false

	return node_a.global_position.distance_to(node_b.global_position) <= 0.001


func _connector_links_node(connector_node: Node2D, other_node: Node2D) -> bool:
	if connector_node == null or other_node == null:
		return false
	var ctype := _get_component_type(connector_node)
	if ctype != PROJECT_PATHS_SCRIPT.COMPONENT_BELT and ctype != PROJECT_PATHS_SCRIPT.COMPONENT_CHAIN:
		return false

	var connector := _get_connector_component_node(connector_node)
	if connector == null:
		return false

	var pulley_a := connector.get("pulley_a") as Node2D
	var pulley_b := connector.get("pulley_b") as Node2D
	return pulley_a == other_node or pulley_b == other_node


func _shaft_links_node(shaft_node: Node2D, other_node: Node2D) -> bool:
	if shaft_node == null or other_node == null:
		return false
	if _get_component_type(shaft_node) != PROJECT_PATHS_SCRIPT.COMPONENT_SHAFT:
		return false

	if shaft_node.has_meta("shaft_end_a_id"):
		var end_a := int(shaft_node.get_meta("shaft_end_a_id"))
		var end_b := int(shaft_node.get_meta("shaft_end_b_id", -1))
		var other_id := other_node.get_instance_id()
		return other_id == end_a or other_id == end_b

	return false


func _get_connector_component_node(connector_node: Node2D) -> Node:
	"""Finds the connector component node on direct chain nodes or wrapper children."""
	if connector_node == null:
		return null

	# Support direct scripted connector nodes (no wrapper child).
	if connector_node.has_method("set_tension_state") or connector_node.has_method("set_jam_state"):
		return connector_node
	if connector_node.get("pulley_a") != null or connector_node.get("pulley_b") != null:
		return connector_node

	for child in connector_node.get_children():
		if child and (child.has_method("set_tension_state") or child.has_method("set_jam_state")):
			return child

	return null


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
	var ctype := _get_component_type(node)
	if ctype == PROJECT_PATHS_SCRIPT.COMPONENT_BELT or ctype == PROJECT_PATHS_SCRIPT.COMPONENT_CHAIN:
		return 0.01
	if ctype == PROJECT_PATHS_SCRIPT.COMPONENT_SHAFT and node and node.has_meta("shaft_end_a_id"):
		return 0.01
	if ctype == PROJECT_PATHS_SCRIPT.COMPONENT_FLYWHEEL and node and node.has_meta("shaft_connection_radius"):
		return maxf(2.0, float(node.get_meta("shaft_connection_radius")))

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
		PROJECT_PATHS_SCRIPT.COMPONENT_SHAFT:
			var shaft_radius := _get_shaft_connection_radius(node)
			var shaft_min_radius := PROJECT_PATHS_SCRIPT.SHAFT_OUTER_RADIUS - PROJECT_PATHS_SCRIPT.GEAR_MESH_CONTACT_MARGIN
			var extra_radius := maxf(0.0, shaft_radius - shaft_min_radius)
			return PROJECT_PATHS_SCRIPT.FRICTION_SHAFT + (extra_radius * 0.085)
		PROJECT_PATHS_SCRIPT.COMPONENT_BELT:
			return PROJECT_PATHS_SCRIPT.BELT_FRICTION_BASE
		PROJECT_PATHS_SCRIPT.COMPONENT_CHAIN:
			return PROJECT_PATHS_SCRIPT.CHAIN_FRICTION_BASE

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


func _get_shaft_connection_radius(node: Node2D) -> float:
	if node == null:
		return PROJECT_PATHS_SCRIPT.SHAFT_MIN_CONNECTION_RADIUS

	if node.has_meta("shaft_connection_radius"):
		return maxf(0.0, float(node.get_meta("shaft_connection_radius")))

	return _get_node_connection_radius(node)


func _get_compound_added_layers(node: Node2D) -> int:
	if node == null:
		return 0
	if node.has_meta("compound_added_layers"):
		return max(0, int(node.get_meta("compound_added_layers")))
	if node.has_meta("stack_parent_id"):
		return 1
	var container := node.get_parent()
	if container == null:
		return 0
	var node_id := node.get_instance_id()
	for child in container.get_children():
		var child_node := child as Node2D
		if child_node == null:
			continue
		if int(child_node.get_meta("stack_parent_id", -1)) == node_id:
			return 1
	return 0


func _mesh_blocked_by_sprocket_mode(node_a: Node2D, node_b: Node2D, type_a: String, type_b: String) -> bool:
	if node_a == null or node_b == null:
		return false
	if not _is_standard_gear_component_type(type_a) or not _is_standard_gear_component_type(type_b):
		return false
	if _stack_links_nodes(node_a, node_b):
		return false
	return _is_sprocket_mode(node_a) or _is_sprocket_mode(node_b)


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
