extends Node
class_name GameManager

const NETWORK_SERVICE_SCRIPT = preload("res://scripts/features/network/network_service.gd")
const TORQUE_SYSTEM_SCRIPT = preload("res://scripts/features/torque/torque_system.gd")
const HUD_STATE_SCRIPT = preload("res://scripts/features/ui/hud_state.gd")
const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")
const CONDITION_SERVICE_SCRIPT = preload("res://scripts/features/condition/component_condition_service.gd")

@export var components_container_path: NodePath = NodePath("../Network/Components")
@export var power_source_path: NodePath = PROJECT_PATHS_SCRIPT.POWER_SOURCE_PATH
@export var central_engine_path: NodePath = PROJECT_PATHS_SCRIPT.CENTRAL_ENGINE_PATH
@export var connection_distance: float = PROJECT_PATHS_SCRIPT.DEFAULT_SOCKET_RADIUS
@export var connection_tolerance: float = PROJECT_PATHS_SCRIPT.DEFAULT_CONNECTION_TOLERANCE
@export var simulation_tick_hz: float = 14.0
@export var underpowered_tick_hz: float = 8.0
@export var underpowered_tick_component_threshold: int = 180

var network_service = NETWORK_SERVICE_SCRIPT.new()
var torque_system = TORQUE_SYSTEM_SCRIPT.new()
var hud_state = HUD_STATE_SCRIPT.new()
var condition_service = CONDITION_SERVICE_SCRIPT.new()

var _network_dirty: bool = true
var _recalc_timer: float = 0.0
var _perf_last_recalc_ms: float = 0.0
var _perf_avg_recalc_ms: float = 0.0
var _perf_peak_recalc_ms: float = 0.0
var _perf_recalc_samples: int = 0
var _perf_last_reachable_count: int = 0
var _perf_last_profile_count: int = 0
var _perf_last_underpowered: bool = false
var _perf_last_component_count: int = 0

@onready var _components_container: Node = get_node(components_container_path)
@onready var _power_source: Node2D = get_node_or_null(power_source_path)
@onready var _central_engine: Node2D = get_node_or_null(central_engine_path)
@onready var _game_state: Node = get_node_or_null("/root/GameState")
@onready var _signal_bus: Node = get_node_or_null("/root/SignalBus")
@onready var _network_node: Node2D = get_node_or_null("../Network")
@onready var _zones_node: Node2D = get_node_or_null("../Zones")


func _ready() -> void:
	if _signal_bus and not _signal_bus.gear_placed.is_connected(_on_gear_placed):
		_signal_bus.gear_placed.connect(_on_gear_placed)
	if _signal_bus and not _signal_bus.component_removed.is_connected(_on_component_removed):
		_signal_bus.component_removed.connect(_on_component_removed)

	_mark_network_dirty(true)


func _get_all_power_sources() -> Array:
	var power_sources: Array = []
	if _network_node == null:
		return power_sources

	for child in _network_node.get_children():
		var node := child as Node2D
		if node == null or node == _central_engine or node == _components_container:
			continue

		if node.name.begins_with("Power"):
			power_sources.append(node)

	return power_sources


func _get_active_power_sources() -> Array:
	return _get_power_sources_connected_to_engine()


func _get_power_sources_connected_to_engine() -> Array:
	var all_power_sources: Array = _get_all_power_sources()
	if _central_engine == null:
		return all_power_sources

	var connected_sources: Array = []
	var engine_radius := _get_node_connection_radius(_central_engine)
	for power_source_raw in all_power_sources:
		var power_source := power_source_raw as Node2D
		if power_source == null:
			continue
		var source_radius := _get_node_connection_radius(power_source)
		if not network_service.is_path_connected(
			_components_container,
			power_source.global_position,
			_central_engine.global_position,
			connection_distance,
			connection_tolerance,
			source_radius,
			engine_radius
		):
			continue
		connected_sources.append(power_source)

	return connected_sources


func _on_gear_placed(_gear: Node2D) -> void:
	_mark_network_dirty(false)


func _on_component_removed() -> void:
	_mark_network_dirty(false)


func _mark_network_dirty(immediate: bool) -> void:
	_network_dirty = true
	if immediate:
		_recalc_timer = 0.0
		_recalculate_and_publish_state()
		_network_dirty = false


func _recalculate_and_publish_state() -> void:
	var perf_start_usec := Time.get_ticks_usec()
	_perf_last_component_count = _components_container.get_child_count()

	var all_power_sources: Array = _get_all_power_sources()
	var power_sources: Array = _get_active_power_sources()
	var local_power_sources: Array = all_power_sources

	var available_torque := 0.0
	if not power_sources.is_empty():
		available_torque = _compute_available_torque_from_sources(power_sources, 0.0)

	var reachable_components: Array = _get_reachable_components_from_sources(power_sources)

	var reachable_profiles := network_service.get_component_profiles_from_list(reachable_components)
	_perf_last_reachable_count = reachable_components.size()
	_perf_last_profile_count = reachable_profiles.size()
	var zone_result := _apply_zone_effects_to_profiles(reachable_profiles)
	reachable_profiles = zone_result.get("profiles", reachable_profiles)
	var zone_efficiency_multiplier := float(zone_result.get("efficiency_multiplier", 1.0))

	var friction_load := network_service.get_friction_load_for_profiles(reachable_profiles)
	friction_load += _compute_shaft_joint_penalty(reachable_profiles)
	if not power_sources.is_empty():
		var preliminary_load_ratio := 0.0
		if available_torque > 0.001:
			preliminary_load_ratio = clampf(friction_load / available_torque, 0.0, 1.0)
		available_torque = _compute_available_torque_from_sources(power_sources, preliminary_load_ratio)

	var free_torque := available_torque - friction_load
	var is_underpowered := free_torque < 0.0
	_perf_last_underpowered = is_underpowered

	var reachable_count: int = reachable_components.size()
	var reachable_connection_count: int = max(reachable_count - 1, 0)
	# Stage power flow: friction load consumes available drive budget before delivery.
	var effective_drive_torque := maxf(available_torque - friction_load, 0.0)
	var efficiency_for_engine := network_service.compute_efficiency(reachable_connection_count) * zone_efficiency_multiplier
	efficiency_for_engine *= _compute_network_mix_efficiency_bonus(reachable_profiles)
	efficiency_for_engine = clampf(efficiency_for_engine, PROJECT_PATHS_SCRIPT.MIN_EFFICIENCY, 1.0)

	var connected := false
	var delivered_torque := 0.0
	var horsepower := 0.0
	var network_spin_signs: Dictionary = {}
	var network_drive_multipliers: Dictionary = {}

	if _central_engine and not power_sources.is_empty():
		connected = true

		if connected:
			delivered_torque = effective_drive_torque
			horsepower = torque_system.compute_output_horsepower(delivered_torque, efficiency_for_engine)

	var drive_utilization := _get_drive_utilization(available_torque, friction_load)
	var source_drive_speed := _get_source_drive_speed(power_sources, is_underpowered)
	var local_source_drive_speeds: Dictionary = {}
	var local_source_underpowered: Dictionary = {}
	var component_drive_targets: Dictionary = {}
	var local_conflict_set: Dictionary = {}
	for local_source_raw in local_power_sources:
		var local_source := local_source_raw as Node2D
		if local_source == null:
			continue

		var local_source_radius := _get_node_connection_radius(local_source)
		var local_reachable := network_service.get_reachable_components_from_source(
			_components_container,
			local_source.global_position,
			connection_distance,
			connection_tolerance,
			local_source_radius
		)
		var local_profiles := network_service.get_component_profiles_from_list(local_reachable)
		var local_zone_result := _apply_zone_effects_to_profiles(local_profiles)
		local_profiles = local_zone_result.get("profiles", local_profiles)
		var local_friction_load := network_service.get_friction_load_for_profiles(local_profiles)
		local_friction_load += _compute_shaft_joint_penalty(local_profiles)

		var local_available_torque := _get_power_source_output(local_source, 0.0)
		if local_available_torque > 0.001:
			var local_load_ratio := clampf(local_friction_load / local_available_torque, 0.0, 1.0)
			local_available_torque = _get_power_source_output(local_source, local_load_ratio)

		var local_is_underpowered := local_available_torque <= local_friction_load
		local_source_underpowered[local_source.get_instance_id()] = local_is_underpowered

		var local_source_speed := 0.0
		if not local_is_underpowered:
			var local_utilization := _get_drive_utilization(local_available_torque, local_friction_load)
			local_source_speed = _get_source_drive_speed([local_source], false) * local_utilization
		local_source_drive_speeds[local_source.get_instance_id()] = local_source_speed

		var local_source_drive_radius := _get_node_outer_radius(local_source)
		var local_source_drive_teeth := _get_node_tooth_count(local_source)
		var local_multipliers := network_service.get_network_drive_multipliers(
			_components_container,
			local_source.global_position,
			local_source_radius,
			local_source_drive_radius,
			local_source_drive_teeth,
			[],
			connection_tolerance
		)
		var local_conflicts := network_service.get_direction_conflicts(
			_components_container,
			local_source.global_position,
			local_source_radius,
			[],
			connection_tolerance
		)
		for local_conflict_id_raw in local_conflicts:
			local_conflict_set[int(local_conflict_id_raw)] = true

		for key in local_multipliers.keys():
			var target_speed := local_source_speed * float(local_multipliers[key])
			var key_id := int(key)
			if local_conflict_set.has(key_id):
				component_drive_targets[key_id] = 0.0
				continue

			var prev_speed := float(component_drive_targets.get(key_id, 0.0))
			if absf(prev_speed) > 0.001 and absf(target_speed) > 0.001 and signf(prev_speed) != signf(target_speed):
				local_conflict_set[key_id] = true
				component_drive_targets[key_id] = 0.0
				continue

			if absf(target_speed) > absf(prev_speed):
				component_drive_targets[key_id] = target_speed
	var should_compute_drive_graph := source_drive_speed != 0.0

	if should_compute_drive_graph and not power_sources.is_empty():
		var first_power_source := power_sources[0] as Node2D
		if first_power_source:
			var source_radius := _get_node_connection_radius(first_power_source)
			var source_drive_radius := _get_node_outer_radius(first_power_source)
			var source_drive_teeth := _get_node_tooth_count(first_power_source)
			var extra_spin_nodes: Array = []
			for source_raw in power_sources:
				var source := source_raw as Node2D
				if source == null or source == first_power_source:
					continue
				extra_spin_nodes.append({
					"key": source.get_instance_id(),
					"position": source.global_position,
					"radius": _get_node_connection_radius(source),
					"drive_radius": _get_node_outer_radius(source),
					"drive_teeth": _get_node_tooth_count(source)
				})

			network_spin_signs = network_service.get_network_spin_signs(
				_components_container,
				first_power_source.global_position,
				source_radius,
				extra_spin_nodes,
				connection_tolerance
			)
			network_drive_multipliers = network_service.get_network_drive_multipliers(
				_components_container,
				first_power_source.global_position,
				source_radius,
				source_drive_radius,
				source_drive_teeth,
				extra_spin_nodes,
				connection_tolerance
			)

	_apply_component_drive_targets(component_drive_targets)
	_update_component_connection_state(reachable_components)
	_update_component_stress_state(reachable_components, reachable_profiles, drive_utilization, is_underpowered)

	# Direction conflict detection: components where two gear paths require opposite rotation.
	var direction_conflict_ids: Array = local_conflict_set.keys()
	if not power_sources.is_empty() and network_spin_signs.size() > 0:
		var first_source := power_sources[0] as Node2D
		if first_source:
			var engine_conflicts := network_service.get_direction_conflicts(
				_components_container,
				first_source.global_position,
				_get_node_connection_radius(first_source),
				[],
				connection_tolerance
			)
			for engine_conflict_id_raw in engine_conflicts:
				local_conflict_set[int(engine_conflict_id_raw)] = true
			direction_conflict_ids = local_conflict_set.keys()
	_apply_direction_conflicts(direction_conflict_ids)

	# Condition system: accumulate per-component heat/cold/dust stress each tick.
	var condition_tick_delta := 1.0 / maxf(1.0, simulation_tick_hz)
	var per_component_load_ratios := _build_component_load_ratios(reachable_profiles, available_torque)
	condition_service.update(
		reachable_components,
		_get_zone_condition_at,
		condition_tick_delta,
		per_component_load_ratios
	)

	# Derive engine drive speed from its actual mechanical driver in the gear chain.
	var engine_drive_multiplier := _compute_engine_drive_multiplier(
		reachable_components, network_drive_multipliers, network_spin_signs, connected
	)

	_update_anchor_rotors(
		all_power_sources,
		power_sources,
		local_power_sources,
		local_source_underpowered,
		available_torque,
		delivered_torque,
		connected,
		is_underpowered,
		network_spin_signs,
		network_drive_multipliers,
		source_drive_speed,
		local_source_drive_speeds,
		engine_drive_multiplier
	)
	var engine_rpm := _to_rpm(source_drive_speed * engine_drive_multiplier if connected else 0.0)
	hud_state.set_values(horsepower, free_torque, efficiency_for_engine, engine_rpm, friction_load, free_torque)

	if _game_state:
		var tick_delta := 1.0 / maxf(1.0, simulation_tick_hz)
		_game_state.set_state(horsepower, free_torque, efficiency_for_engine, engine_rpm, tick_delta)

	if _signal_bus:
		_signal_bus.network_changed.emit()

	var perf_elapsed_ms := float(Time.get_ticks_usec() - perf_start_usec) * 0.001
	_perf_last_recalc_ms = perf_elapsed_ms
	_perf_recalc_samples += 1
	if _perf_recalc_samples <= 1:
		_perf_avg_recalc_ms = perf_elapsed_ms
	else:
		_perf_avg_recalc_ms = lerpf(_perf_avg_recalc_ms, perf_elapsed_ms, 0.18)
	_perf_peak_recalc_ms = maxf(_perf_peak_recalc_ms * 0.96, perf_elapsed_ms)


func _apply_zone_effects_to_profiles(profiles: Array) -> Dictionary:
	if _zones_node == null or profiles.is_empty():
		return {
			"profiles": profiles,
			"efficiency_multiplier": 1.0
		}

	var adjusted_profiles: Array = []
	var efficiency_sum := 0.0
	var efficiency_count := 0

	for profile_raw in profiles:
		if not profile_raw is Dictionary:
			continue
		var profile := (profile_raw as Dictionary).duplicate()
		var profile_node := profile.get("node", null) as Node2D
		if profile_node == null:
			adjusted_profiles.append(profile)
			continue

		var zone_effect := _get_zone_effect_at(profile_node.global_position)
		var base_friction := float(profile.get("friction", 0.0))
		var friction_multiplier := float(zone_effect.get("friction_multiplier", 1.0))
		var torque_load_add := float(zone_effect.get("torque_load_add", 0.0))
		var local_efficiency := float(zone_effect.get("efficiency_multiplier", 1.0))

		profile["friction"] = maxf(0.0, (base_friction * friction_multiplier) + torque_load_add)
		profile["local_efficiency"] = local_efficiency
		adjusted_profiles.append(profile)

		efficiency_sum += local_efficiency
		efficiency_count += 1

	var avg_efficiency := 1.0
	if efficiency_count > 0:
		avg_efficiency = clampf(efficiency_sum / float(efficiency_count), 0.5, 1.0)

	return {
		"profiles": adjusted_profiles,
		"efficiency_multiplier": avg_efficiency
	}


func _get_zone_effect_at(world_pos: Vector2) -> Dictionary:
	var combined := {
		"friction_multiplier": 1.0,
		"efficiency_multiplier": 1.0,
		"torque_load_add": 0.0,
		"power_output_multiplier": 1.0,
		"power_output_add": 0.0
	}

	if _zones_node == null:
		return combined

	for zone_raw in _zones_node.get_children():
		var zone := zone_raw as Node2D
		if zone == null or not zone.has_method("get_effect_at"):
			continue

		var effect: Variant = zone.call("get_effect_at", world_pos)
		if not effect is Dictionary:
			continue
		var effect_dict := effect as Dictionary

		combined["friction_multiplier"] = float(combined["friction_multiplier"]) * float(effect_dict.get("friction_multiplier", 1.0))
		combined["efficiency_multiplier"] = float(combined["efficiency_multiplier"]) * float(effect_dict.get("efficiency_multiplier", 1.0))
		combined["torque_load_add"] = float(combined["torque_load_add"]) + float(effect_dict.get("torque_load_add", 0.0))
		combined["power_output_multiplier"] = float(combined["power_output_multiplier"]) * float(effect_dict.get("power_output_multiplier", 1.0))
		combined["power_output_add"] = float(combined["power_output_add"]) + float(effect_dict.get("power_output_add", 0.0))

	combined["friction_multiplier"] = clampf(float(combined["friction_multiplier"]), 0.5, 2.5)
	combined["efficiency_multiplier"] = clampf(float(combined["efficiency_multiplier"]), 0.5, 1.0)
	combined["power_output_multiplier"] = clampf(float(combined["power_output_multiplier"]), 0.4, 1.8)
	return combined


func _compute_available_torque_from_sources(power_sources: Array, load_ratio: float) -> float:
	var available_torque := 0.0
	for source_raw in power_sources:
		var source := source_raw as Node2D
		if source == null:
			continue
		available_torque += _get_power_source_output(source, load_ratio)

	return available_torque


func _get_power_source_output(source: Node2D, load_ratio: float) -> float:
	if source == null:
		return 0.0

	var source_output := 0.0
	if source.has_method("get_power_output"):
		source_output = float(source.call("get_power_output", load_ratio))
	else:
		var rated_value: Variant = source.get("rated_torque_output")
		if rated_value != null:
			source_output = float(rated_value)
		else:
			source_output = PROJECT_PATHS_SCRIPT.BASE_POWER_NODE_OUTPUT

	var zone_effect := _get_zone_effect_at(source.global_position)
	var output_multiplier := float(zone_effect.get("power_output_multiplier", 1.0))
	var output_add := float(zone_effect.get("power_output_add", 0.0))
	return maxf(0.0, (source_output * output_multiplier) + output_add)


func _get_reachable_components_from_sources(power_sources: Array) -> Array:
	var reachable_components: Array = []
	if power_sources.is_empty():
		return reachable_components

	var reachable_ids: Dictionary = {}
	for power_source_raw in power_sources:
		var power_source := power_source_raw as Node2D
		if power_source == null:
			continue
		var source_radius := _get_node_connection_radius(power_source)
		var from_source := network_service.get_reachable_components_from_source(
			_components_container,
			power_source.global_position,
			connection_distance,
			connection_tolerance,
			source_radius
		)
		for component_raw in from_source:
			var component := component_raw as Node2D
			if component == null:
				continue
			var component_id := component.get_instance_id()
			if reachable_ids.has(component_id):
				continue
			reachable_ids[component_id] = true
			reachable_components.append(component)

	return reachable_components


func _update_component_connection_state(reachable_components: Array) -> void:
	var reachable_ids: Dictionary = {}
	for component_raw in reachable_components:
		var component := component_raw as Node2D
		if not component:
			continue
		reachable_ids[component.get_instance_id()] = true

	for child in _components_container.get_children():
		var is_engine_route := reachable_ids.has(child.get_instance_id())
		if child.has_method("set_connection_state"):
			child.set_connection_state(is_engine_route)
		if child.has_method("set_engine_route_state"):
			child.set_engine_route_state(is_engine_route)


func _update_component_stress_state(reachable_components: Array, reachable_profiles: Array, drive_utilization: float, is_underpowered: bool) -> void:
	var reachable_ids: Dictionary = {}
	for component_raw in reachable_components:
		var component := component_raw as Node2D
		if not component:
			continue
		reachable_ids[component.get_instance_id()] = true

	if is_underpowered:
		for child in _components_container.get_children():
			if not child.has_method("set_stress_state"):
				continue
			var stalled_connected := reachable_ids.has(child.get_instance_id())
			child.set_stress_state(1.0 if stalled_connected else 0.0, stalled_connected)
		return

	var stress_level := clampf(1.0 - drive_utilization, 0.0, 1.0)
	var profile_by_id: Dictionary = {}
	for profile_raw in reachable_profiles:
		if not profile_raw is Dictionary:
			continue
		var profile := profile_raw as Dictionary
		var profile_id: int = int(profile.get("id", 0))
		if profile_id == 0:
			continue
		profile_by_id[profile_id] = profile

	for child in _components_container.get_children():
		if not child.has_method("set_stress_state"):
			continue

		var component_connected := reachable_ids.has(child.get_instance_id())
		var stalled := component_connected and is_underpowered
		var child_stress := 0.0
		if component_connected:
			child_stress = stress_level
			var profile: Dictionary = profile_by_id.get(child.get_instance_id(), {}) as Dictionary
			if not profile.is_empty():
				var friction := float(profile.get("friction", 0.0))
				var max_torque := float(profile.get("max_torque", 1.0))
				var local_load_ratio := clampf(friction / maxf(max_torque, 0.001), 0.0, 1.0)
				# Blend global strain with local bottleneck strain so overloaded pieces stand out.
				child_stress = clampf(maxf(stress_level, local_load_ratio * 0.85), 0.0, 1.0)
		child.set_stress_state(child_stress, stalled)


func _apply_component_torque(per_component_torque: float, spin_signs: Dictionary) -> void:
	for child in _components_container.get_children():
		if child.has_method("set_torque"):
			var spin_direction := float(spin_signs.get(child.get_instance_id(), 1.0))
			child.set_torque(per_component_torque * spin_direction)


func _apply_component_drive(source_drive_speed: float, drive_multipliers: Dictionary) -> void:
	for child in _components_container.get_children():
		if child.has_method("set_target_angular_speed"):
			var multiplier := float(drive_multipliers.get(child.get_instance_id(), 0.0))
			child.set_target_angular_speed(source_drive_speed * multiplier)


func _apply_component_drive_targets(drive_targets: Dictionary) -> void:
	for child in _components_container.get_children():
		if child.has_method("set_target_angular_speed"):
			child.set_target_angular_speed(float(drive_targets.get(child.get_instance_id(), 0.0)))


func _update_anchor_rotors(
	all_power_sources: Array,
	power_sources: Array,
	local_power_sources: Array,
	local_source_underpowered: Dictionary,
	available_torque: float,
	delivered_torque: float,
	connected: bool,
	is_underpowered: bool,
	network_spin_signs: Dictionary,
	network_drive_multipliers: Dictionary,
	source_drive_speed: float,
	local_source_drive_speeds: Dictionary,
	engine_drive_multiplier: float
) -> void:
	for power_source_raw in all_power_sources:
		var source := power_source_raw as Node2D
		if not source:
			continue

		var is_source_connected := power_sources.has(source)
		var is_source_local := local_power_sources.has(source)
		var source_sign := 1.0
		source_sign = float(network_spin_signs.get(source.get_instance_id(), 1.0))
		var source_drive := 0.0
		if is_source_connected:
			if network_drive_multipliers.has(source.get_instance_id()):
				var multiplier := float(network_drive_multipliers.get(source.get_instance_id(), 0.0))
				source_drive = source_drive_speed * multiplier
			else:
				source_drive = source_drive_speed
		elif is_source_local:
			source_drive = float(local_source_drive_speeds.get(source.get_instance_id(), 0.0))

		if is_source_local and source.has_method("set_target_angular_speed"):
			source.set_target_angular_speed(source_drive, is_source_local)
		elif source.has_method("set_network_torque"):
			# Important: disconnected AnchorRotor instances should remain in torque-mode
			# so `always_active` can keep their idle spin visible in dev mode.
			source.set_network_torque(available_torque if is_source_connected else 0.0, is_source_connected, source_sign)
		if source.has_method("set_underpowered_state"):
			var source_underpowered := bool(local_source_underpowered.get(source.get_instance_id(), false))
			source.set_underpowered_state((is_underpowered and is_source_connected) or source_underpowered)
		if source.has_method("set_connection_state"):
			source.set_connection_state(is_source_connected)
		if source.has_method("set_engine_route_state"):
			source.set_engine_route_state(is_source_connected)

	# Engine speed is now derived from the actual drive chain ratio, not hardcoded from source.
	if _central_engine and _central_engine.has_method("set_target_angular_speed"):
		var engine_drive := source_drive_speed * engine_drive_multiplier if connected else 0.0
		_central_engine.set_target_angular_speed(engine_drive, connected)
	elif _central_engine and _central_engine.has_method("set_network_torque"):
		_central_engine.set_network_torque(delivered_torque, connected)
	if _central_engine and _central_engine.has_method("set_underpowered_state"):
		_central_engine.set_underpowered_state(false)
	if _central_engine and _central_engine.has_method("set_connection_state"):
		_central_engine.set_connection_state(connected)


## Compute the effective drive multiplier for the central engine by finding the
## gear directly meshing with it and reading that gear's drive multiplier + sign.
func _compute_engine_drive_multiplier(
	reachable_components: Array,
	drive_multipliers: Dictionary,
	_spin_signs: Dictionary,
	connected: bool
) -> float:
	if not connected or _central_engine == null:
		return 0.0

	var engine_radius := _get_node_connection_radius(_central_engine)
	var engine_outer := _get_node_outer_radius(_central_engine)

	for component_raw in reachable_components:
		var component := component_raw as Node2D
		if component == null:
			continue
		var comp_radius := _get_node_connection_radius(component)
		var dist := component.global_position.distance_to(_central_engine.global_position)
		if absf(dist - (comp_radius + engine_radius)) > connection_tolerance:
			continue
		# Found a gear directly driving the engine.
		var comp_mult := float(drive_multipliers.get(component.get_instance_id(), 0.0))
		var comp_outer := _get_node_outer_radius(component)
		# Meshing gears reverse direction; chain preserves it (handled by sign).
		return comp_mult * (comp_outer / maxf(engine_outer, 0.001)) * -1.0

	# Fallback: use the simple source-to-engine ratio if no direct driver found.
	return 0.0


## Mark components with conflicting rotation requirements so they can show
## a visual indicator and stall their motion.
func _apply_direction_conflicts(conflict_ids: Array) -> void:
	var conflict_set: Dictionary = {}
	for id_raw in conflict_ids:
		conflict_set[int(id_raw)] = true

	for child in _components_container.get_children():
		if child.has_method("set_conflict_state"):
			child.call("set_conflict_state", conflict_set.has(child.get_instance_id()))


## Build a Dictionary {instance_id: load_ratio} from the current profiles.
func _build_component_load_ratios(reachable_profiles: Array, total_available_torque: float) -> Dictionary:
	var result: Dictionary = {}
	var denom := maxf(total_available_torque, 0.001)
	for profile_raw in reachable_profiles:
		if not profile_raw is Dictionary:
			continue
		var profile := profile_raw as Dictionary
		var cid := int(profile.get("id", 0))
		if cid == 0:
			continue
		var friction := float(profile.get("friction", 0.0))
		result[cid] = clampf(friction / denom, 0.0, 1.0)
	return result


## Zone getter callable for condition service — returns zone type and intensity
## at a world position. This queries the same _zones_node used by zone effects.
func _get_zone_condition_at(world_pos: Vector2) -> Dictionary:
	if _zones_node == null:
		return {"zone_type": "", "intensity": 0.0}

	var best_type := ""
	var best_intensity := 0.0

	for zone_raw in _zones_node.get_children():
		var zone := zone_raw as Node2D
		if zone == null:
			continue
		var zone_type_val: Variant = zone.get("zone_type")
		if zone_type_val == null:
			continue
		var zone_type := str(zone_type_val)
		if zone_type.is_empty():
			continue
		if not zone.has_method("get_effect_at"):
			continue
		var effect: Variant = zone.call("get_effect_at", world_pos)
		if not effect is Dictionary:
			continue
		# Use friction_multiplier deviation from 1.0 as an intensity proxy.
		var effect_dict := effect as Dictionary
		var friction_mult := 1.0
		if effect_dict.has("friction_multiplier"):
			friction_mult = float(effect_dict["friction_multiplier"])
		var intensity := clampf(absf(friction_mult - 1.0), 0.0, 1.0)
		if intensity > best_intensity:
			best_intensity = intensity
			best_type = zone_type

	return {"zone_type": best_type, "intensity": best_intensity}


func _process(_delta: float) -> void:
	if not _network_dirty:
		return

	var safe_hz := maxf(1.0, simulation_tick_hz)
	if _perf_last_underpowered and _perf_last_component_count >= underpowered_tick_component_threshold:
		safe_hz = minf(safe_hz, maxf(1.0, underpowered_tick_hz))
	var tick_interval := 1.0 / safe_hz
	_recalc_timer += _delta
	if _recalc_timer < tick_interval:
		return

	_recalc_timer = 0.0
	_recalculate_and_publish_state()
	_network_dirty = false


func get_perf_stats() -> Dictionary:
	return {
		"last_recalc_ms": _perf_last_recalc_ms,
		"avg_recalc_ms": _perf_avg_recalc_ms,
		"peak_recalc_ms": _perf_peak_recalc_ms,
		"recalc_samples": _perf_recalc_samples,
		"network_dirty": _network_dirty,
		"dirty_wait_ms": _recalc_timer * 1000.0,
		"sim_tick_hz": simulation_tick_hz,
		"reachable_count": _perf_last_reachable_count,
		"profile_count": _perf_last_profile_count,
		"underpowered": _perf_last_underpowered,
		"component_count": _perf_last_component_count
	}


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


func _get_source_drive_speed(power_sources: Array, is_underpowered: bool) -> float:
	if is_underpowered or power_sources.is_empty():
		return 0.0

	var weighted_speed_sum := 0.0
	var total_weight := 0.0
	for source_raw in power_sources:
		var source := source_raw as Node2D
		if source == null:
			continue

		var base_speed_value: Variant = source.get("base_spin_speed")
		var torque_factor_value: Variant = source.get("torque_spin_factor")
		var base_speed := float(base_speed_value) if base_speed_value != null else 0.0
		var torque_factor := float(torque_factor_value) if torque_factor_value != null else 0.0
		var source_output := maxf(_get_power_source_output(source, 0.0), 0.001)
		var source_speed := base_speed + (source_output * torque_factor)
		weighted_speed_sum += source_speed * source_output
		total_weight += source_output

	if total_weight <= 0.001:
		return 0.0

	return weighted_speed_sum / total_weight


func _get_drive_utilization(available_torque: float, friction_load: float) -> float:
	if available_torque <= 0.001:
		return 0.0

	return clampf((available_torque - friction_load) / available_torque, 0.0, 1.0)


func _to_rpm(angular_speed: float) -> float:
	return absf(angular_speed) * (60.0 / TAU)


func _compute_network_mix_efficiency_bonus(reachable_profiles: Array) -> float:
	var has_shaft := false
	var has_gear := false
	for profile_raw in reachable_profiles:
		if not profile_raw is Dictionary:
			continue
		var profile := profile_raw as Dictionary
		var component_type := str(profile.get("type", ""))
		if component_type == PROJECT_PATHS_SCRIPT.COMPONENT_SHAFT:
			has_shaft = true
		elif component_type == PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_SMALL or component_type == PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_MEDIUM or component_type == PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_LARGE:
			has_gear = true

	if has_shaft and has_gear:
		return 1.0 + PROJECT_PATHS_SCRIPT.MIXED_NETWORK_EFFICIENCY_BONUS

	return 1.0


func _compute_shaft_joint_penalty(reachable_profiles: Array) -> float:
	if reachable_profiles.is_empty():
		return 0.0

	var profiles_by_id: Dictionary = {}
	for profile_raw in reachable_profiles:
		if not profile_raw is Dictionary:
			continue
		var profile := profile_raw as Dictionary
		var id := int(profile.get("id", 0))
		if id == 0:
			continue
		profiles_by_id[id] = profile

	var shafts: Array = []
	for profile_raw in reachable_profiles:
		if not profile_raw is Dictionary:
			continue
		var profile := profile_raw as Dictionary
		if str(profile.get("type", "")) != PROJECT_PATHS_SCRIPT.COMPONENT_SHAFT:
			continue
		shafts.append(profile)

	if shafts.size() <= 1:
		return 0.0

	var shaft_joints := 0
	for i in range(shafts.size()):
		var a := shafts[i] as Dictionary
		var a_node := a.get("node", null) as Node2D
		if a_node == null:
			continue
		var a_id := int(a.get("id", 0))
		if a_id == 0:
			continue
		var a_radius := float(a.get("connection_radius", _get_node_connection_radius(a_node)))

		for j in range(i + 1, shafts.size()):
			var b := shafts[j] as Dictionary
			var b_node := b.get("node", null) as Node2D
			if b_node == null:
				continue
			var b_id := int(b.get("id", 0))
			if b_id == 0:
				continue
			var b_radius := float(b.get("connection_radius", _get_node_connection_radius(b_node)))
			var edge_distance := a_node.global_position.distance_to(b_node.global_position)
			if absf(edge_distance - (a_radius + b_radius)) <= connection_tolerance:
				shaft_joints += 1

	if shaft_joints <= 0:
		return 0.0

	return float(shaft_joints) * PROJECT_PATHS_SCRIPT.SHAFT_JOINT_FRICTION
