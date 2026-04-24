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
@export var threaded_solver_enabled: bool = true
@export var threaded_solver_component_threshold: int = 1

var network_service = NETWORK_SERVICE_SCRIPT.new()
var torque_system = TORQUE_SYSTEM_SCRIPT.new()
var hud_state = HUD_STATE_SCRIPT.new()
var condition_service = CONDITION_SERVICE_SCRIPT.new()

var _network_dirty: bool = true
var _recalc_timer: float = 0.0
var _perf_last_recalc_ms: float = 0.0
var _perf_avg_recalc_ms: float = 0.0
var _perf_peak_recalc_ms: float = 0.0
var _perf_last_thread_request_ms: float = 0.0
var _perf_last_thread_worker_ms: float = 0.0
var _perf_last_thread_apply_ms: float = 0.0
var _perf_last_solver_mode: String = "sync"
var _perf_recalc_samples: int = 0
var _perf_last_reachable_count: int = 0
var _perf_last_profile_count: int = 0
var _perf_last_underpowered: bool = false
var _perf_last_component_count: int = 0
var _ui_overlay_snapshot: Dictionary = {}
var _ui_component_profiles: Dictionary = {}
var _ui_component_load_ratios: Dictionary = {}
var _ui_connected_component_ids: Dictionary = {}
var _ui_component_torque_by_id: Dictionary = {}
var _ui_source_budget_by_id: Dictionary = {}
var _ui_source_available_by_id: Dictionary = {}
var _source_rpm_feedback_by_id: Dictionary = {}
var _last_engine_operating_state: String = "bogging"
var _last_engine_band_multiplier: float = 1.0
var _last_engine_input_horsepower: float = 0.0
var _last_local_source_drive_speeds_by_id: Dictionary = {}
var _last_component_drive_targets: Dictionary = {}
var _isolated_detail_offset: int = 0
var _condition_update_accum: float = 0.0
var _topology_revision: int = 0
var _threaded_solver_thread: Thread = Thread.new()
var _threaded_solver_running: bool = false
var _threaded_solver_revision: int = -1
var _threaded_solver_snapshot: Dictionary = {}

const DETAILED_LOCAL_SOURCE_THRESHOLD := 220
const DETAILED_ISOLATED_SOURCE_BUDGET_BASE := 96
const DETAILED_ISOLATED_SOURCE_BUDGET_MEDIUM := 56
const DETAILED_ISOLATED_SOURCE_BUDGET_LARGE := 32
const DETAILED_ISOLATED_SOURCE_BUDGET_HUGE := 16
const DETAILED_ISOLATED_COMPONENT_MEDIUM := 260
const DETAILED_ISOLATED_COMPONENT_LARGE := 420
const DETAILED_ISOLATED_COMPONENT_HUGE := 700
const CONDITION_UPDATE_DENSE_COMPONENT_THRESHOLD := 300
const CONDITION_UPDATE_DENSE_INTERVAL := 0.22

@onready var _components_container: Node = get_node(components_container_path)

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


func _exit_tree() -> void:
	if _threaded_solver_running and _threaded_solver_thread.is_started():
		_threaded_solver_thread.wait_to_finish()
		_threaded_solver_running = false


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
	if _components_container == null:
		return []

	# Connectivity is component-only: node actors do not relay power between islands.
	var engine_connection_radius := _get_node_connection_radius(_central_engine)
	var engine_reachable_components := network_service.get_reachable_components_from_source(
		_components_container,
		_central_engine.global_position,
		connection_distance,
		connection_tolerance,
		engine_connection_radius
	)
	if engine_reachable_components.is_empty():
		return []

	# Tier-1: sources directly adjacent to an engine-reachable component.
	var connected_sources: Array = []
	var connected_source_ids: Dictionary = {}
	for power_source_raw in all_power_sources:
		var power_source := power_source_raw as Node2D
		if power_source == null:
			continue
		var source_pos := power_source.global_position
		var source_radius := _get_node_connection_radius(power_source)
		for component_raw in engine_reachable_components:
			var component := component_raw as Node2D
			if component == null:
				continue
			var component_radius := _get_node_connection_radius(component)
			if absf(component.global_position.distance_to(source_pos) - (source_radius + component_radius)) <= connection_tolerance:
				connected_sources.append(power_source)
				connected_source_ids[power_source.get_instance_id()] = true
				break

	# Tier-N: expand connected sources by checking if an unconnected source touches
	# any component reachable from an already-connected source (or another connected
	# source directly). This handles node-to-node coupling through shared gear trains.
	var tier_n_reachable_components: Array = engine_reachable_components.duplicate()
	var tier_n_reachable_ids: Dictionary = {}
	for c_raw in tier_n_reachable_components:
		var c := c_raw as Node2D
		if c:
			tier_n_reachable_ids[c.get_instance_id()] = true

	# Critical: also include ALL components reachable from each Tier-1 connected source.
	# The engine BFS cannot cross through power nodes, so gears on a source's far side
	# are absent from engine_reachable_components. Without this, a source connected to
	# node1's back gear train can never be detected in Tier-N.
	for cs_raw in connected_sources:
		var cs := cs_raw as Node2D
		if cs == null:
			continue
		var cs_r := _get_node_connection_radius(cs)
		var cs_reach := network_service.get_reachable_components_from_source(
			_components_container, cs.global_position, connection_distance, connection_tolerance, cs_r
		)
		for cr_raw in cs_reach:
			var cr := cr_raw as Node2D
			if cr == null:
				continue
			var crid := cr.get_instance_id()
			if not tier_n_reachable_ids.has(crid):
				tier_n_reachable_ids[crid] = true
				tier_n_reachable_components.append(cr)

	var frontier_changed := true
	while frontier_changed:
		frontier_changed = false
		for candidate_raw in all_power_sources:
			var candidate := candidate_raw as Node2D
			if candidate == null:
				continue
			var candidate_id := candidate.get_instance_id()
			if connected_source_ids.has(candidate_id):
				continue
			var candidate_pos := candidate.global_position
			var candidate_radius := _get_node_connection_radius(candidate)
			# Check against source-to-source direct contact.
			var is_newly_connected := false
			for peer_raw in connected_sources:
				var peer := peer_raw as Node2D
				if peer == null:
					continue
				var peer_radius := _get_node_connection_radius(peer)
				if absf(candidate_pos.distance_to(peer.global_position) - (candidate_radius + peer_radius)) <= connection_tolerance:
					is_newly_connected = true
					break
			# Check against components reachable from connected sources.
			if not is_newly_connected:
				for comp_raw in tier_n_reachable_components:
					var comp := comp_raw as Node2D
					if comp == null:
						continue
					var comp_radius := _get_node_connection_radius(comp)
					if absf(candidate_pos.distance_to(comp.global_position) - (candidate_radius + comp_radius)) <= connection_tolerance:
						is_newly_connected = true
						break
			if not is_newly_connected:
				continue
			connected_sources.append(candidate)
			connected_source_ids[candidate_id] = true
			frontier_changed = true
			# Pull in this newly-connected source's reachable components for subsequent tiers.
			var cand_radius := _get_node_connection_radius(candidate)
			var cand_reachable := network_service.get_reachable_components_from_source(
				_components_container, candidate_pos, connection_distance,
				connection_tolerance, cand_radius
			)
			for cr_raw in cand_reachable:
				var cr := cr_raw as Node2D
				if cr == null:
					continue
				var crid := cr.get_instance_id()
				if not tier_n_reachable_ids.has(crid):
					tier_n_reachable_ids[crid] = true
					tier_n_reachable_components.append(cr)

	return connected_sources


func _on_gear_placed(_gear: Node2D) -> void:
	_mark_network_dirty(false)


func _on_component_removed() -> void:
	_mark_network_dirty(false)


func _mark_network_dirty(immediate: bool) -> void:
	_topology_revision += 1
	_network_dirty = true
	# Topology changes invalidate previous target carry-over assumptions.
	_last_component_drive_targets.clear()
	_last_local_source_drive_speeds_by_id.clear()
	if immediate:
		_recalc_timer = 0.0
		var completed := _recalculate_and_publish_state()
		_network_dirty = not completed


func _recalculate_and_publish_state() -> bool:
	if _should_run_threaded_solver():
		return _recalculate_and_publish_state_threaded()

	_perf_last_solver_mode = "sync"
	_perf_last_thread_request_ms = 0.0
	_perf_last_thread_worker_ms = 0.0
	_perf_last_thread_apply_ms = 0.0
	_recalculate_and_publish_state_sync({}, {})
	return true


func _should_run_threaded_solver() -> bool:
	if _threaded_solver_running:
		return true
	if not threaded_solver_enabled:
		return false
	return _components_container.get_child_count() >= threaded_solver_component_threshold


func _recalculate_and_publish_state_threaded() -> bool:
	if _threaded_solver_running:
		if _threaded_solver_thread.is_alive():
			_perf_last_solver_mode = "thread-pending"
			return false
		var cache_variant: Variant = _threaded_solver_thread.wait_to_finish()
		_threaded_solver_running = false
		if _threaded_solver_revision != _topology_revision:
			_perf_last_solver_mode = "thread-stale"
			_threaded_solver_snapshot = {}
			return false
		var graph_cache := cache_variant as Dictionary
		_perf_last_thread_worker_ms = float(graph_cache.get("_worker_ms", 0.0))
		graph_cache.erase("_worker_ms")
		var apply_start_usec := Time.get_ticks_usec()
		_perf_last_solver_mode = "thread-apply"
		_recalculate_and_publish_state_sync(_threaded_solver_snapshot, graph_cache)
		_perf_last_thread_apply_ms = float(Time.get_ticks_usec() - apply_start_usec) / 1000.0
		return true

	var request_start_usec := Time.get_ticks_usec()
	var request := _build_threaded_solver_request()
	_perf_last_thread_request_ms = float(Time.get_ticks_usec() - request_start_usec) / 1000.0
	if request.is_empty():
		_perf_last_solver_mode = "sync-no-request"
		_perf_last_thread_worker_ms = 0.0
		_perf_last_thread_apply_ms = 0.0
		_recalculate_and_publish_state_sync({}, {})
		return true

	_threaded_solver_snapshot = request.get("snapshot", {}) as Dictionary
	_threaded_solver_thread = Thread.new()
	var start_error := _threaded_solver_thread.start(Callable(self, "_run_threaded_solver_job").bind(request))
	if start_error != OK:
		_perf_last_solver_mode = "thread-fallback-sync"
		var component_snapshot := request.get("snapshot", {}) as Dictionary
		var source_nodes := request.get("source_nodes", []) as Array
		var engine_data := request.get("engine_data", {}) as Dictionary
		var worker_start_usec := Time.get_ticks_usec()
		var fallback_cache := network_service.compute_threaded_graph_cache(
			component_snapshot,
			source_nodes,
			engine_data
		)
		_perf_last_thread_worker_ms = float(Time.get_ticks_usec() - worker_start_usec) / 1000.0
		var apply_start_usec := Time.get_ticks_usec()
		_recalculate_and_publish_state_sync(_threaded_solver_snapshot, fallback_cache)
		_perf_last_thread_apply_ms = float(Time.get_ticks_usec() - apply_start_usec) / 1000.0
		return true

	_threaded_solver_running = true
	_threaded_solver_revision = _topology_revision
	_perf_last_solver_mode = "thread-pending"
	_perf_last_thread_apply_ms = 0.0
	return false


func _run_threaded_solver_job(request: Dictionary) -> Dictionary:
	var worker_start_usec := Time.get_ticks_usec()
	var component_snapshot := request.get("snapshot", {}) as Dictionary
	var source_nodes := request.get("source_nodes", []) as Array
	var engine_data := request.get("engine_data", {}) as Dictionary
	var graph_cache := network_service.compute_threaded_graph_cache(component_snapshot, source_nodes, engine_data)
	graph_cache["_worker_ms"] = float(Time.get_ticks_usec() - worker_start_usec) / 1000.0
	return graph_cache


func _build_threaded_solver_request() -> Dictionary:
	if _components_container == null:
		return {}

	var all_power_sources: Array = _get_all_power_sources()
	var relay_nodes: Array = []
	for source_raw in all_power_sources:
		var source := source_raw as Node2D
		if source == null:
			continue
		relay_nodes.append(source)
	if _central_engine != null:
		relay_nodes.append(_central_engine)

	var component_snapshot := network_service.build_graph_snapshot(_components_container, relay_nodes, connection_tolerance)
	if component_snapshot.is_empty():
		return {}

	var source_nodes: Array = []
	for source_raw in all_power_sources:
		var source := source_raw as Node2D
		if source == null:
			continue
		source_nodes.append({
			"id": source.get_instance_id(),
			"position": source.global_position,
			"radius": _get_node_connection_radius(source),
			"drive_radius": _get_node_outer_radius(source),
			"drive_teeth": _get_node_tooth_count(source),
			"component_type": ""
		})

	var engine_data: Dictionary = {}
	if _central_engine != null:
		engine_data = {
			"id": _central_engine.get_instance_id(),
			"position": _central_engine.global_position,
			"radius": _get_node_connection_radius(_central_engine),
			"drive_radius": _get_node_outer_radius(_central_engine),
			"drive_teeth": _get_node_tooth_count(_central_engine),
			"component_type": ""
		}

	return {
		"snapshot": component_snapshot,
		"source_nodes": source_nodes,
		"engine_data": engine_data
	}


func _recalculate_and_publish_state_sync(graph_snapshot: Dictionary = {}, graph_cache: Dictionary = {}) -> void:
	var perf_start_usec := Time.get_ticks_usec()
	_perf_last_component_count = _components_container.get_child_count()

	var all_power_sources: Array = _get_all_power_sources()
	var component_lookup := _build_component_node_lookup()
	var zone_effects_by_component_id := _build_zone_effect_cache(component_lookup)
	var reachable_component_ids_by_source := graph_cache.get("reachable_component_ids_by_source", {}) as Dictionary
	var source_drive_multipliers_by_id := graph_cache.get("source_drive_multipliers_by_id", {}) as Dictionary
	var source_spin_signs_by_id := graph_cache.get("source_spin_signs_by_id", {}) as Dictionary
	var source_conflicts_by_id := graph_cache.get("source_conflicts_by_id", {}) as Dictionary
	var anchor_multipliers_by_id := graph_cache.get("anchor_multipliers_by_id", {}) as Dictionary
	var connected_source_ids: Array = graph_cache.get("connected_source_ids", []) as Array
	var has_connected_source_cache := graph_cache.has("connected_source_ids")
	var connected_source_set := _build_id_set(connected_source_ids)

	var power_sources: Array = []
	if has_connected_source_cache:
		for source_raw in all_power_sources:
			var source := source_raw as Node2D
			if source == null:
				continue
			if connected_source_set.has(source.get_instance_id()):
				power_sources.append(source)
	else:
		power_sources = _get_active_power_sources()

	var local_power_sources: Array = all_power_sources
	var tick_delta := 1.0 / maxf(1.0, simulation_tick_hz)

	var available_torque := 0.0
	if not power_sources.is_empty():
		available_torque = _compute_available_torque_from_sources(power_sources, 0.0)

	var reachable_components: Array = []
	if graph_cache.has("engine_reachable_component_ids"):
		reachable_components = _components_from_ids(
			graph_cache.get("engine_reachable_component_ids", []) as Array,
			component_lookup
		)
	else:
		reachable_components = _get_reachable_components_from_sources(power_sources)
	var engine_route_component_ids := _build_component_id_lookup(reachable_components)

	var reachable_profiles := network_service.get_component_profiles_from_list(reachable_components)
	_perf_last_reachable_count = reachable_components.size()
	_perf_last_profile_count = reachable_profiles.size()
	var reflected_load_factor := _compute_network_reflected_load_factor(
		power_sources,
		reachable_components,
		source_drive_multipliers_by_id
	)
	var zone_result := _apply_zone_effects_to_profiles(reachable_profiles, zone_effects_by_component_id)
	reachable_profiles = zone_result.get("profiles", reachable_profiles)
	var zone_efficiency_multiplier := float(zone_result.get("efficiency_multiplier", 1.0))

	var friction_load := network_service.get_friction_load_for_profiles(reachable_profiles)
	friction_load += _compute_shaft_joint_penalty(reachable_profiles, graph_snapshot)
	var estimated_source_drive_speed := _get_source_drive_speed(power_sources, false)
	var reflected_engine_load := _compute_reflected_engine_load(
		power_sources,
		reachable_components,
		estimated_source_drive_speed,
		source_drive_multipliers_by_id
	)
	var reflected_friction_load := (friction_load * reflected_load_factor) + reflected_engine_load
	if not power_sources.is_empty():
		var preliminary_load_ratio := 0.0
		if available_torque > 0.001:
			preliminary_load_ratio = clampf(reflected_friction_load / available_torque, 0.0, 1.0)
		available_torque = _compute_available_torque_from_sources(power_sources, preliminary_load_ratio)
	available_torque = _apply_flywheel_buffer(available_torque, reflected_friction_load, reachable_profiles, tick_delta)

	var free_torque := available_torque - reflected_friction_load
	var is_underpowered := free_torque < 0.0
	_perf_last_underpowered = is_underpowered

	var reachable_count: int = reachable_components.size()
	var reachable_connection_count: int = max(reachable_count - 1, 0)
	# Stage power flow: friction load consumes available drive budget before delivery.
	var effective_drive_torque := maxf(available_torque - reflected_friction_load, 0.0)
	var efficiency_for_engine := network_service.compute_efficiency(reachable_connection_count) * zone_efficiency_multiplier
	efficiency_for_engine *= _compute_network_mix_efficiency_bonus(reachable_profiles)
	efficiency_for_engine *= _compute_gear_variation_bonus_multiplier(reachable_profiles)
	efficiency_for_engine *= _compute_compound_stack_efficiency_multiplier(reachable_profiles)
	efficiency_for_engine = clampf(efficiency_for_engine, PROJECT_PATHS_SCRIPT.MIN_EFFICIENCY, 1.0)

	var connected := false
	var delivered_torque := 0.0
	var horsepower := 0.0
	var input_horsepower := 0.0
	var network_spin_signs: Dictionary = {}
	var network_drive_multipliers: Dictionary = {}

	if _central_engine and not power_sources.is_empty():
		connected = true

		if connected:
			delivered_torque = effective_drive_torque

	var drive_utilization := _get_drive_utilization(available_torque, reflected_friction_load)
	var source_drive_speed := _get_source_drive_speed(power_sources, is_underpowered)
	var bottleneck_profile := _get_bottleneck_profile(reachable_profiles)
	var iso_collect: Array = []
	var local_source_drive_speeds: Dictionary = {}
	var local_source_underpowered: Dictionary = {}
	var source_remaining_budget_by_id: Dictionary = {}
	var source_available_torque_by_id: Dictionary = {}
	var component_drive_targets: Dictionary = _last_component_drive_targets.duplicate()
	var isolated_component_targets: Dictionary = {}
	var isolated_stalled_components: Dictionary = {}
	var isolated_conflict_set: Dictionary = {}
	var visual_conflict_set: Dictionary = {}
	var connected_conflict_set: Dictionary = {}
	var connected_route_conflict_set: Dictionary = {}
	var source_conflict_votes: Dictionary = {}
	var allow_detailed_isolated := local_power_sources.size() <= DETAILED_LOCAL_SOURCE_THRESHOLD
	var isolated_total_estimate := maxi(local_power_sources.size() - power_sources.size(), 0)
	var isolated_detail_budget := _get_isolated_detail_budget(_perf_last_component_count, isolated_total_estimate)
	if isolated_total_estimate > 0:
		_isolated_detail_offset = posmod(_isolated_detail_offset, isolated_total_estimate)
	var isolated_seen := 0
	for local_source_raw in local_power_sources:
		var local_source := local_source_raw as Node2D
		if local_source == null:
			continue
		var local_source_id := local_source.get_instance_id()
		var is_engine_connected_source := power_sources.has(local_source)
		if not is_engine_connected_source:
			var should_detail := true
			if not allow_detailed_isolated and isolated_total_estimate > isolated_detail_budget:
				var slice_start := _isolated_detail_offset
				var slice_end := slice_start + isolated_detail_budget
				if slice_end <= isolated_total_estimate:
					should_detail = isolated_seen >= slice_start and isolated_seen < slice_end
				else:
					var wrapped_end := slice_end % isolated_total_estimate
					should_detail = isolated_seen >= slice_start or isolated_seen < wrapped_end
			isolated_seen += 1
			if not should_detail:
				var fallback_torque := _get_power_source_output(local_source, 0.0)
				source_available_torque_by_id[local_source_id] = fallback_torque
				local_source_underpowered[local_source_id] = false
				source_remaining_budget_by_id[local_source_id] = fallback_torque
				var cached_speed := float(_last_local_source_drive_speeds_by_id.get(local_source_id, 0.0))
				if absf(cached_speed) <= 0.001:
					cached_speed = _get_source_drive_speed([local_source], false)
				local_source_drive_speeds[local_source_id] = cached_speed

				# Cheap fallback for budget-skipped isolated sources: keep their reachable
				# components spinning from cached graph multipliers/conflicts so islands do
				# not randomly freeze when topology changes trigger a global recalc.
				var fallback_reachable_ids := reachable_component_ids_by_source.get(local_source_id, []) as Array
				var fallback_multipliers := source_drive_multipliers_by_id.get(local_source_id, {}) as Dictionary
				var fallback_conflicts_arr := source_conflicts_by_id.get(local_source_id, []) as Array
				var fallback_conflicts: Dictionary = {}
				for fallback_conflict_raw in fallback_conflicts_arr:
					fallback_conflicts[int(fallback_conflict_raw)] = true

				for comp_id_raw in fallback_reachable_ids:
					var comp_id := int(comp_id_raw)
					if fallback_conflicts.has(comp_id):
						isolated_conflict_set[comp_id] = true
						isolated_component_targets[comp_id] = 0.0
						continue
					var mult := float(fallback_multipliers.get(comp_id, 0.0))
					if absf(mult) <= 0.0001:
						continue
					var target := cached_speed * mult
					var prev := float(isolated_component_targets.get(comp_id, 0.0))
					if absf(prev) > 0.001 and absf(target) > 0.001 and signf(prev) != signf(target):
						isolated_conflict_set[comp_id] = true
						isolated_component_targets[comp_id] = 0.0
						continue
					if absf(target) > absf(prev):
						isolated_component_targets[comp_id] = target
				continue

		var local_source_radius := _get_node_connection_radius(local_source)
		var local_reachable: Array = []
		if reachable_component_ids_by_source.has(local_source_id):
			local_reachable = _components_from_ids(
				reachable_component_ids_by_source.get(local_source_id, []) as Array,
				component_lookup
			)
		else:
			local_reachable = network_service.get_reachable_components_from_source(
				_components_container,
				local_source.global_position,
				connection_distance,
				connection_tolerance,
				local_source_radius
			)
		var local_profiles := network_service.get_component_profiles_from_list(local_reachable)
		var local_zone_result := _apply_zone_effects_to_profiles(local_profiles, zone_effects_by_component_id)
		local_profiles = local_zone_result.get("profiles", local_profiles)
		var local_friction_load := network_service.get_friction_load_for_profiles(local_profiles)
		local_friction_load += _compute_shaft_joint_penalty(local_profiles, graph_snapshot)

		if not is_engine_connected_source:
			# Isolated source: defer underpowered/budget/speed/target decisions to
			# the group pass below so torques from co-connected sources pool together.
			var raw_torque := _get_power_source_output(local_source, 0.0)
			source_available_torque_by_id[local_source_id] = raw_torque
			iso_collect.append({
				"node": local_source,
				"id": local_source_id,
				"friction": local_friction_load,
				"reachable": local_reachable,
				"profiles": local_profiles,
				"available_torque_raw": raw_torque,
			})
			continue

		var local_engine_multiplier := _compute_source_engine_drive_multiplier(
			local_source,
			reachable_components,
			source_drive_multipliers_by_id.get(local_source_id, {}) as Dictionary,
			source_drive_multipliers_by_id.has(local_source_id)
		)
		var local_reflected_friction_load := local_friction_load * _compute_reflected_load_factor_from_multiplier(
			local_engine_multiplier)
		var local_estimated_drive_speed := _get_source_drive_speed([local_source], false)
		local_reflected_friction_load += _compute_reflected_engine_load_for_multiplier(
			local_engine_multiplier,
			local_estimated_drive_speed
		)
		var local_available_torque := _get_power_source_output(local_source, 0.0)
		if local_available_torque > 0.001:
			var local_load_ratio := clampf(local_reflected_friction_load / local_available_torque, 0.0, 1.0)
			local_available_torque = _get_power_source_output(local_source, local_load_ratio)
		local_available_torque = _apply_flywheel_buffer(local_available_torque, local_reflected_friction_load, local_profiles, tick_delta)
		source_available_torque_by_id[local_source_id] = local_available_torque

		# Engine-connected sources pool their torques; the global is_underpowered
		# flag already reflects the combined output of all connected sources vs
		# total friction. Never mark a connected source as stalled individually —
		# a weak source stays spinning as long as the pool is sufficient.
		local_source_underpowered[local_source_id] = is_underpowered
		source_remaining_budget_by_id[local_source_id] = maxf(local_available_torque - local_reflected_friction_load, 0.0)

		var local_source_speed := 0.0
		if not is_underpowered:
			var local_utilization := _get_drive_utilization(available_torque, reflected_friction_load)
			# Engine-connected sources are mechanically coupled via the active
			# network, including node-relay paths. Use a pooled source-frame speed
			# so speed conflict propagates across branches instead of remaining local.
			var speed_utilization := lerpf(0.35, 1.0, local_utilization)
			local_source_speed = source_drive_speed * speed_utilization
		local_source_drive_speeds[local_source_id] = local_source_speed

	# ── Isolated source group processing ────────────────────────────────────
	# Group isolated (non-engine) sources by connected subgraph so their
	# torques pool together. Two motors on the same gear train add torques;
	# neither stalls as long as combined output covers the shared friction load.
	var iso_groups: Array = _group_isolated_sources(iso_collect)
	for iso_group_raw in iso_groups:
		var iso_group: Array = iso_group_raw as Array

		# Step 1: sum raw (no-load) torques and compute group friction from the
		# union of reachable components so node-coupled islands share load.
		var group_raw_torque := 0.0
		var group_reachable_components: Array = []
		var group_reachable_ids: Dictionary = {}
		for src_raw in iso_group:
			var src: Dictionary = src_raw as Dictionary
			group_raw_torque += float(src.get("available_torque_raw", 0.0))
			for comp_raw in (src.get("reachable", []) as Array):
				var comp := comp_raw as Node2D
				if comp == null:
					continue
				var comp_id := comp.get_instance_id()
				if group_reachable_ids.has(comp_id):
					continue
				group_reachable_ids[comp_id] = true
				group_reachable_components.append(comp)

		var group_profiles := network_service.get_component_profiles_from_list(group_reachable_components)
		var group_zone_result := _apply_zone_effects_to_profiles(group_profiles, zone_effects_by_component_id)
		group_profiles = group_zone_result.get("profiles", group_profiles)
		var group_friction := network_service.get_friction_load_for_profiles(group_profiles)
		group_friction += _compute_shaft_joint_penalty(group_profiles, graph_snapshot)

		# Step 2: recompute drooped torques using group-level load ratio, then
		# apply flywheel buffer once for the whole group (shared components).
		var group_load_ratio := clampf(group_friction / group_raw_torque, 0.0, 1.0) if group_raw_torque > 0.001 else 1.0
		var group_torque := 0.0
		for src_raw in iso_group:
			var src: Dictionary = src_raw as Dictionary
			var src_node := src.get("node") as Node2D
			if src_node == null:
				continue
			var src_torque := _get_power_source_output(src_node, group_load_ratio)
			group_torque += src_torque
			source_available_torque_by_id[int(src.get("id", 0))] = src_torque
		group_torque = _apply_flywheel_buffer(group_torque, group_friction, group_profiles, tick_delta)

		var group_underpowered := group_torque <= group_friction
		var group_budget := maxf(group_torque - group_friction, 0.0)

		for src_raw in iso_group:
			var src: Dictionary = src_raw as Dictionary
			var src_id := int(src.get("id", 0))
			local_source_underpowered[src_id] = group_underpowered
			source_remaining_budget_by_id[src_id] = group_budget

		var group_source_nodes: Array = []
		for src_raw in iso_group:
			var src_node := (src_raw as Dictionary).get("node") as Node2D
			if src_node != null:
				group_source_nodes.append(src_node)

		var group_source_speed := 0.0
		if not group_underpowered and not group_source_nodes.is_empty():
			var utilization := _get_drive_utilization(group_torque, group_friction)
			var speed_utilization := lerpf(0.35, 1.0, utilization)
			group_source_speed = _get_source_drive_speed(group_source_nodes, false) * speed_utilization

		for src_raw in iso_group:
			var src_id := int((src_raw as Dictionary).get("id", 0))
			local_source_drive_speeds[src_id] = group_source_speed

		if group_underpowered:
			for src_raw in iso_group:
				var src: Dictionary = src_raw as Dictionary
				for comp_raw in (src.get("reachable", []) as Array):
					var comp := comp_raw as Node2D
					if comp == null:
						continue
					var comp_id := comp.get_instance_id()
					isolated_stalled_components[comp_id] = true
					isolated_component_targets[comp_id] = 0.0
			continue

		for src_raw in iso_group:
			var src: Dictionary = src_raw as Dictionary
			var src_node := src.get("node") as Node2D
			if src_node == null:
				continue
			var src_id := int(src.get("id", 0))
			var src_radius := _get_node_connection_radius(src_node)
			var src_drive_radius := _get_node_outer_radius(src_node)
			var src_drive_teeth := _get_node_tooth_count(src_node)
			var src_multipliers := source_drive_multipliers_by_id.get(src_id, {}) as Dictionary
			if src_multipliers.is_empty() and not source_drive_multipliers_by_id.has(src_id):
				src_multipliers = network_service.get_network_drive_multipliers(
					_components_container,
					src_node.global_position,
					src_radius,
					src_drive_radius,
					src_drive_teeth,
					[],
					connection_tolerance
				)
			var src_conflicts_arr := source_conflicts_by_id.get(src_id, []) as Array
			if src_conflicts_arr.is_empty() and not source_conflicts_by_id.has(src_id):
				src_conflicts_arr = network_service.get_direction_conflicts(
					_components_container,
					src_node.global_position,
					src_radius,
					[],
					connection_tolerance
				)
			var src_conflicts: Dictionary = {}
			for c in src_conflicts_arr:
				src_conflicts[int(c)] = true

			var src_speed := float(local_source_drive_speeds.get(src_id, 0.0))

			for comp_raw in (src.get("reachable", []) as Array):
				var comp := comp_raw as Node2D
				if comp == null:
					continue
				var comp_id := comp.get_instance_id()
				if isolated_stalled_components.has(comp_id):
					continue
				if src_conflicts.has(comp_id):
					isolated_conflict_set[comp_id] = true
					isolated_component_targets[comp_id] = 0.0
					continue
				var mult := float(src_multipliers.get(comp_id, 0.0))
				var target := src_speed * mult
				var prev := float(isolated_component_targets.get(comp_id, 0.0))
				if absf(prev) > 0.001 and absf(target) > 0.001 and signf(prev) != signf(target):
					isolated_conflict_set[comp_id] = true
					isolated_component_targets[comp_id] = 0.0
					continue
				if absf(target) > absf(prev):
					isolated_component_targets[comp_id] = target
	if not power_sources.is_empty():
		for source_raw in power_sources:
			var source := source_raw as Node2D
			if source == null:
				continue
			var source_id := source.get_instance_id()

			var source_radius := _get_node_connection_radius(source)
			var source_drive_radius := _get_node_outer_radius(source)
			var source_drive_teeth := _get_node_tooth_count(source)
			var source_speed := float(local_source_drive_speeds.get(source_id, source_drive_speed))

			var source_spin_signs := source_spin_signs_by_id.get(source_id, {}) as Dictionary
			if source_spin_signs.is_empty() and not source_spin_signs_by_id.has(source_id):
				source_spin_signs = network_service.get_network_spin_signs(
					_components_container,
					source.global_position,
					source_radius,
					[],
					connection_tolerance
				)
			for sign_key_raw in source_spin_signs.keys():
				if not network_spin_signs.has(sign_key_raw):
					network_spin_signs[sign_key_raw] = source_spin_signs[sign_key_raw]

			var source_multipliers := source_drive_multipliers_by_id.get(source_id, {}) as Dictionary
			if source_multipliers.is_empty() and not source_drive_multipliers_by_id.has(source_id):
				source_multipliers = network_service.get_network_drive_multipliers(
					_components_container,
					source.global_position,
					source_radius,
					source_drive_radius,
					source_drive_teeth,
					[],
					connection_tolerance
				)

			if network_drive_multipliers.is_empty():
				network_drive_multipliers = source_multipliers

			for key_raw in source_multipliers.keys():
				var key_id := int(key_raw)
				if not engine_route_component_ids.has(key_id):
					continue
				var target_speed := source_speed * float(source_multipliers[key_raw])
				var prev_speed := float(component_drive_targets.get(key_id, 0.0))
				if absf(prev_speed) > 0.001 and absf(target_speed) > 0.001 and signf(prev_speed) != signf(target_speed):
					connected_conflict_set[key_id] = true
					connected_route_conflict_set[key_id] = true
					component_drive_targets[key_id] = 0.0
					continue
				if absf(target_speed) > absf(prev_speed):
					component_drive_targets[key_id] = target_speed

			var source_conflicts := source_conflicts_by_id.get(source_id, []) as Array
			if source_conflicts.is_empty() and not source_conflicts_by_id.has(source_id):
				source_conflicts = network_service.get_direction_conflicts(
					_components_container,
					source.global_position,
					source_radius,
					[],
					connection_tolerance
				)
			for conflict_id_raw in source_conflicts:
				var conflict_id := int(conflict_id_raw)
				if not engine_route_component_ids.has(conflict_id):
					continue
				source_conflict_votes[conflict_id] = int(source_conflict_votes.get(conflict_id, 0)) + 1

	if not allow_detailed_isolated and isolated_total_estimate > 0:
		_isolated_detail_offset = (_isolated_detail_offset + isolated_detail_budget) % isolated_total_estimate
	_last_local_source_drive_speeds_by_id = local_source_drive_speeds.duplicate()

	for stalled_id_raw in isolated_stalled_components.keys():
		var stalled_id := int(stalled_id_raw)
		if component_drive_targets.has(stalled_id):
			continue
		component_drive_targets[stalled_id] = 0.0

	for isolated_id_raw in isolated_component_targets.keys():
		var isolated_id := int(isolated_id_raw)
		if component_drive_targets.has(isolated_id):
			continue
		component_drive_targets[isolated_id] = float(isolated_component_targets[isolated_id_raw])

	# Re-propagate speeds so the whole connected gear graph is geometrically
	# consistent. Without this pass, two sources with different base speeds can
	# each win different components via the fastest-wins merge but leave adjacent
	# components at mutually inconsistent angular velocities (visible as one side
	# spinning fast while the other side spins slow despite being meshed).
	if not graph_snapshot.is_empty():
		component_drive_targets = network_service.propagate_speeds_from_snapshot(graph_snapshot, component_drive_targets)
	else:
		# Fallback path remains component-only: node actors do not bridge islands.
		component_drive_targets = network_service.propagate_speeds_from_settled(
			_components_container, component_drive_targets, connection_tolerance, []
		)
	_last_component_drive_targets = component_drive_targets.duplicate()

	# Conflict overrides run after propagation so conflicted nodes end up at 0.
	for conflict_id_raw in connected_conflict_set.keys():
		var conflict_id := int(conflict_id_raw)
		component_drive_targets[conflict_id] = 0.0

	for isolated_conflict_raw in isolated_conflict_set.keys():
		var isolated_conflict_id := int(isolated_conflict_raw)
		connected_conflict_set[isolated_conflict_id] = true
		visual_conflict_set[isolated_conflict_id] = true
		if not component_drive_targets.has(isolated_conflict_id):
			component_drive_targets[isolated_conflict_id] = 0.0

	# Apply cached source-conflict detection conservatively:
	# - single connected source: keep all detected conflicts (odd-cycle jam case)
	# - multi-source network: only keep conflicts agreed by all connected sources
	#   to avoid painting large swaths red from per-source parity frames.
	if not source_conflict_votes.is_empty() and not power_sources.is_empty():
		var connected_source_count := maxi(power_sources.size(), 1)
		for voted_id_raw in source_conflict_votes.keys():
			var voted_id := int(voted_id_raw)
			var vote_count := int(source_conflict_votes.get(voted_id_raw, 0))
			var keep_conflict := connected_source_count == 1 or vote_count >= connected_source_count
			if not keep_conflict:
				continue
			connected_conflict_set[voted_id] = true
			visual_conflict_set[voted_id] = true
			connected_route_conflict_set[voted_id] = true
			component_drive_targets[voted_id] = 0.0

	# Conflict visuals stay local (direct contradiction gears only), but jam
	# policy for the connected network is strict: stall the full engine route.
	var direct_conflict_ids: Array = visual_conflict_set.keys()
	var jam_stalled_components: Dictionary = {}
	var jam_stalls_connected_network := connected and not connected_route_conflict_set.is_empty()
	if jam_stalls_connected_network:
		for route_id_raw in engine_route_component_ids.keys():
			jam_stalled_components[int(route_id_raw)] = true
	else:
		for conflict_id_raw in direct_conflict_ids:
			jam_stalled_components[int(conflict_id_raw)] = true
	for jam_id_raw in jam_stalled_components.keys():
		var jam_id := int(jam_id_raw)
		component_drive_targets[jam_id] = 0.0

	# Feed engine resistance back into the connected drivetrain so insufficient
	# torque damps the whole engine path, not just scoring or the engine node.
	var engine_drive_multiplier := _compute_engine_drive_multiplier(
		reachable_components, network_drive_multipliers, network_spin_signs, connected
	)
	var raw_engine_angular_velocity := 0.0
	var engine_acceptance_ratio := 0.0
	if connected:
		var engine_load_response := _compute_engine_load_response(
			delivered_torque,
			source_drive_speed,
			engine_drive_multiplier,
			component_drive_targets,
			anchor_multipliers_by_id
		)
		raw_engine_angular_velocity = float(engine_load_response.get("raw_engine_speed", 0.0))
		engine_acceptance_ratio = float(engine_load_response.get("acceptance_ratio", 0.0))
		_scale_connected_drive_targets(reachable_components, component_drive_targets, engine_acceptance_ratio)

	var per_component_torque := 0.0
	if connected and not reachable_components.is_empty():
		per_component_torque = delivered_torque / float(reachable_components.size())
	var component_torque_by_id: Dictionary = {}
	for reachable_raw in reachable_components:
		var reachable_component := reachable_raw as Node2D
		if reachable_component == null:
			continue
		var reachable_id := reachable_component.get_instance_id()
		var drive_target := float(component_drive_targets.get(reachable_id, 0.0))
		var sign_source := signf(drive_target)
		if absf(sign_source) <= 0.001:
			sign_source = float(network_spin_signs.get(reachable_id, 1.0))
		component_torque_by_id[reachable_id] = per_component_torque * sign_source
	_apply_component_torque(per_component_torque, network_spin_signs)
	_apply_component_drive_targets(component_drive_targets)
	_update_component_connection_state(reachable_components)
	_update_component_stress_state(
		reachable_components,
		reachable_profiles,
		drive_utilization,
		is_underpowered,
		isolated_stalled_components,
		jam_stalled_components
	)

	# Direction conflict detection: components where two gear paths require opposite rotation.
	var direction_conflict_ids: Array = direct_conflict_ids
	_apply_direction_conflicts(direction_conflict_ids)

	# Condition system: accumulate per-component heat/cold/dust stress each tick.
	var per_component_load_ratios := _build_component_load_ratios(reachable_profiles, available_torque)
	var run_condition_update := true
	if _perf_last_component_count >= CONDITION_UPDATE_DENSE_COMPONENT_THRESHOLD:
		_condition_update_accum += tick_delta
		if _condition_update_accum < CONDITION_UPDATE_DENSE_INTERVAL:
			run_condition_update = false
		else:
			_condition_update_accum = 0.0
	else:
		_condition_update_accum = 0.0
	if run_condition_update:
		condition_service.update(
			reachable_components,
			_get_zone_condition_at,
			tick_delta,
			per_component_load_ratios
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
		component_drive_targets,
		source_drive_speed,
		local_source_drive_speeds,
		engine_drive_multiplier,
		anchor_multipliers_by_id,
		jam_stalls_connected_network
	)
	_refresh_source_rpm_feedback(all_power_sources, component_drive_targets, anchor_multipliers_by_id)
	# Derive engine speed from the already load-damped drive targets.
	var engine_angular_velocity := 0.0
	if connected and _central_engine != null:
		engine_angular_velocity = _derive_anchor_drive_speed(_central_engine, component_drive_targets, anchor_multipliers_by_id)
	# Torque scales inverse to speed (power conservation). Use the resolved
	# engine angular speed vs source speed to get the true effective ratio.
	var ratio_magnitude := 1.0
	if connected and absf(source_drive_speed) > 0.001:
		ratio_magnitude = maxf(absf(raw_engine_angular_velocity) / absf(source_drive_speed), 0.001)
	elif connected:
		ratio_magnitude = maxf(absf(engine_drive_multiplier), 0.001)
	var engine_torque := delivered_torque / ratio_magnitude
	var engine_load_torque := _compute_engine_load_torque_scaled(engine_angular_velocity)
	var load_acceptance_ratio := 0.0
	if connected and engine_torque > 0.001:
		load_acceptance_ratio = clampf((engine_torque - engine_load_torque) / engine_torque, 0.0, 1.0)
	var net_engine_torque := maxf(engine_torque - engine_load_torque, 0.0)
	var engine_rpm := _to_rpm(engine_angular_velocity)
	var band_multiplier := torque_system.compute_engine_operating_band_multiplier(engine_rpm)
	var engine_operating_state := torque_system.get_engine_operating_state(engine_rpm)
	if _central_engine and _central_engine.has_method("set_target_angular_speed"):
		_central_engine.set_target_angular_speed(engine_angular_velocity, connected and load_acceptance_ratio > 0.001)
	if connected:
		input_horsepower = torque_system.compute_output_horsepower(engine_torque, engine_rpm, efficiency_for_engine)
		if engine_torque > 0.001:
			horsepower = input_horsepower * load_acceptance_ratio * band_multiplier
		else:
			horsepower = 0.0
		var coupled_hp_multiplier := _get_engine_coupled_hp_multiplier()
		input_horsepower *= coupled_hp_multiplier
		horsepower *= coupled_hp_multiplier
	_last_engine_operating_state = engine_operating_state
	_last_engine_band_multiplier = band_multiplier
	_last_engine_input_horsepower = input_horsepower
	_ui_component_profiles = _build_component_profile_lookup(reachable_profiles)
	_ui_component_load_ratios = per_component_load_ratios.duplicate()
	_ui_connected_component_ids = _build_component_id_lookup(reachable_components)
	_ui_component_torque_by_id = component_torque_by_id.duplicate()
	_ui_source_budget_by_id = source_remaining_budget_by_id.duplicate()
	_ui_source_available_by_id = source_available_torque_by_id.duplicate()
	_ui_overlay_snapshot = {
		"connected": connected,
		"horsepower": horsepower,
		"input_horsepower": input_horsepower,
		"delivered_torque": engine_torque,
		"net_torque": free_torque,
		"engine_load_torque": engine_load_torque,
		"free_torque": free_torque,
		"engine_rpm": engine_rpm,
		"efficiency": efficiency_for_engine,
		"engine_operating_state": engine_operating_state,
		"engine_band_multiplier": band_multiplier,
		"friction_load": friction_load,
		"reachable_count": reachable_components.size(),
		"connection_count": reachable_connection_count,
		"connected_source_count": power_sources.size(),
		"total_source_count": all_power_sources.size(),
		"underpowered": is_underpowered,
		"bottleneck_name": _get_profile_display_name(bottleneck_profile),
		"bottleneck_loss": float(bottleneck_profile.get("friction", 0.0)),
		"bottleneck_id": int((bottleneck_profile.get("node", null) as Node2D).get_instance_id()) if bottleneck_profile.get("node", null) is Node2D else -1
	}
	hud_state.set_values(horsepower, free_torque, efficiency_for_engine, engine_rpm, friction_load, free_torque)

	if _game_state:
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


func _apply_flywheel_buffer(
	available_torque: float,
	friction_load: float,
	profiles: Array,
	tick_delta: float
) -> float:
	if profiles.is_empty() or tick_delta <= 0.0:
		return available_torque

	var flywheels: Array = []
	for profile_raw in profiles:
		if not profile_raw is Dictionary:
			continue
		var profile := profile_raw as Dictionary
		if str(profile.get("type", "")) != PROJECT_PATHS_SCRIPT.COMPONENT_FLYWHEEL:
			continue
		var node := profile.get("node", null) as Node
		if node == null:
			continue
		if not node.has_method("draw_discharge") or not node.has_method("absorb_surplus"):
			continue
		flywheels.append(node)

	if flywheels.is_empty():
		return available_torque

	var adjusted_torque: float = available_torque
	var deficit: float = maxf(friction_load - adjusted_torque, 0.0)
	if deficit > 0.0:
		for flywheel_raw in flywheels:
			var flywheel := flywheel_raw as Node
			if flywheel == null:
				continue
			var released: float = float(flywheel.call("draw_discharge", deficit, tick_delta))
			if released <= 0.0:
				continue
			adjusted_torque += released
			deficit = maxf(deficit - released, 0.0)
			if deficit <= 0.0:
				break
	else:
		var surplus: float = maxf(adjusted_torque - friction_load, 0.0)
		if surplus > 0.0:
			var per_flywheel: float = surplus / float(flywheels.size())
			for flywheel_raw in flywheels:
				var flywheel := flywheel_raw as Node
				if flywheel == null:
					continue
				flywheel.call("absorb_surplus", per_flywheel, tick_delta)

	return adjusted_torque


func _apply_zone_effects_to_profiles(profiles: Array, zone_effect_cache: Dictionary = {}) -> Dictionary:
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

		var profile_id := int(profile.get("id", 0))
		var zone_effect: Dictionary = {}
		if profile_id != 0 and zone_effect_cache.has(profile_id):
			zone_effect = zone_effect_cache.get(profile_id, {}) as Dictionary
		else:
			zone_effect = _get_zone_effect_at(profile_node.global_position)
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


func _build_zone_effect_cache(component_lookup: Dictionary) -> Dictionary:
	var cache: Dictionary = {}
	if _zones_node == null:
		return cache

	for component_id_raw in component_lookup.keys():
		var component_id := int(component_id_raw)
		if component_id == 0:
			continue
		var component := component_lookup.get(component_id_raw, null) as Node2D
		if component == null:
			continue
		cache[component_id] = _get_zone_effect_at(component.global_position)

	return cache


func _compute_available_torque_from_sources(power_sources: Array, load_ratio: float, source_rpm_hints: Dictionary = {}) -> float:
	var available_torque := 0.0
	for source_raw in power_sources:
		var source := source_raw as Node2D
		if source == null:
			continue
		available_torque += _get_power_source_output(source, load_ratio, source_rpm_hints)

	return available_torque


func _get_power_source_output(source: Node2D, load_ratio: float, source_rpm_hints: Dictionary = {}) -> float:
	if source == null:
		return 0.0

	var source_output := 0.0
	if source.has_method("get_source_torque_at_speed_rpm"):
		var source_rpm := 0.0
		var source_id := source.get_instance_id()
		if source_rpm_hints.has(source_id):
			source_rpm = float(source_rpm_hints.get(source_id, 0.0))
		elif _source_rpm_feedback_by_id.has(source_id):
			source_rpm = float(_source_rpm_feedback_by_id.get(source_id, 0.0))
		elif source.has_method("get_angular_velocity"):
			source_rpm = _to_rpm(float(source.call("get_angular_velocity")))
		elif source.has_method("get_source_last_rpm"):
			source_rpm = float(source.call("get_source_last_rpm"))
		source_output = float(source.call("get_source_torque_at_speed_rpm", source_rpm, load_ratio))
	elif source.has_method("get_power_output"):
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
	return (source_output * output_multiplier) + output_add


func _get_reachable_components_from_sources(power_sources: Array) -> Array:
	var reachable_components: Array = []
	if power_sources.is_empty():
		return reachable_components

	var reachable_ids: Dictionary = {}

	# Seed from engine position so the core engine-connected train is always included.
	if _central_engine != null:
		var engine_radius := _get_node_connection_radius(_central_engine)
		var engine_reachable := network_service.get_reachable_components_from_source(
			_components_container,
			_central_engine.global_position,
			connection_distance,
			connection_tolerance,
			engine_radius
		)
		for component_raw in engine_reachable:
			var component := component_raw as Node2D
			if component == null:
				continue
			var cid := component.get_instance_id()
			if not reachable_ids.has(cid):
				reachable_ids[cid] = true
				reachable_components.append(component)

	# Also union in components reachable from each connected source so that
	# node-to-node coupled sources contribute their own gear trains to the network.
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
			if not reachable_ids.has(component_id):
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


func _update_component_stress_state(
	reachable_components: Array,
	reachable_profiles: Array,
	drive_utilization: float,
	is_underpowered: bool,
	isolated_stalled_components: Dictionary = {},
	jam_stalled_components: Dictionary = {}
) -> void:
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
			var child_id := child.get_instance_id()
			var stalled_connected := reachable_ids.has(child_id)
			var stalled_isolated := isolated_stalled_components.has(child_id)
			var stalled_jam := jam_stalled_components.has(child_id)
			var stalled_any := stalled_connected or stalled_isolated or stalled_jam
			child.set_stress_state(1.0 if stalled_any else 0.0, stalled_any)
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

		var child_id := child.get_instance_id()
		var component_connected := reachable_ids.has(child_id)
		var stalled := isolated_stalled_components.has(child_id) or jam_stalled_components.has(child_id)
		var child_stress := 0.0
		if component_connected:
			child_stress = stress_level
			var profile: Dictionary = profile_by_id.get(child_id, {}) as Dictionary
			if not profile.is_empty():
				var friction := float(profile.get("friction", 0.0))
				var max_torque := float(profile.get("max_torque", 1.0))
				var local_load_ratio := clampf(friction / maxf(max_torque, 0.001), 0.0, 1.0)
				# Blend global strain with local bottleneck strain so overloaded pieces stand out.
				child_stress = clampf(maxf(stress_level, local_load_ratio * 0.85), 0.0, 1.0)
		elif stalled:
			child_stress = 1.0
		child.set_stress_state(child_stress, stalled)


func _expand_component_conflict_set_from_snapshot(conflict_ids: Array, graph_snapshot: Dictionary) -> Dictionary:
	var expanded: Dictionary = {}
	if conflict_ids.is_empty():
		return expanded

	for id_raw in conflict_ids:
		expanded[int(id_raw)] = true

	if graph_snapshot.is_empty():
		return expanded

	var adjacency := graph_snapshot.get("adjacency", {}) as Dictionary
	var component_ids := graph_snapshot.get("component_ids", []) as Array
	if adjacency.is_empty() or component_ids.is_empty():
		return expanded
	var component_set := _build_id_set(component_ids)

	var queue: Array = []
	for id_raw in conflict_ids:
		var seed_id := int(id_raw)
		if component_set.has(seed_id):
			queue.append(seed_id)

	while not queue.is_empty():
		var current_id := int(queue.pop_front())
		var neighbors := adjacency.get(current_id, []) as Array
		for edge_raw in neighbors:
			if not edge_raw is Dictionary:
				continue
			var edge := edge_raw as Dictionary
			var neighbor_id := int(edge.get("to", -1))
			if neighbor_id < 0 or not component_set.has(neighbor_id) or expanded.has(neighbor_id):
				continue
			expanded[neighbor_id] = true
			queue.append(neighbor_id)

	return expanded


func _apply_component_torque(per_component_torque: float, spin_signs: Dictionary) -> void:
	for child in _components_container.get_children():
		if child.has_method("set_torque"):
			var child_id := child.get_instance_id()
			if not spin_signs.has(child_id):
				child.set_torque(0.0)
				continue
			var spin_direction := float(spin_signs.get(child_id, 1.0))
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
	component_drive_targets: Dictionary,
	source_drive_speed: float,
	local_source_drive_speeds: Dictionary,
	engine_drive_multiplier: float,
	anchor_multipliers_by_id: Dictionary = {},
	jam_stalls_connected_network: bool = false
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

		if is_source_local:
			var synced_source_drive := _derive_anchor_drive_speed(source, component_drive_targets, anchor_multipliers_by_id)
			if absf(synced_source_drive) > 0.001:
				source_drive = synced_source_drive

		if jam_stalls_connected_network and is_source_connected:
			source_drive = 0.0

		if is_source_local and source.has_method("set_target_angular_speed"):
			source.set_target_angular_speed(source_drive, is_source_local)
		elif source.has_method("set_network_torque"):
			# Important: disconnected AnchorRotor instances should remain in torque-mode
			# so `always_active` can keep their idle spin visible in dev mode.
			source.set_network_torque(available_torque if is_source_connected else 0.0, is_source_connected, source_sign)
		if source.has_method("set_underpowered_state"):
			var source_underpowered := bool(local_source_underpowered.get(source.get_instance_id(), false))
			source.set_underpowered_state((is_underpowered and is_source_connected) or source_underpowered or (jam_stalls_connected_network and is_source_connected))
		if source.has_method("set_connection_state"):
			source.set_connection_state(is_source_connected)
		if source.has_method("set_engine_route_state"):
			source.set_engine_route_state(is_source_connected)

	# Engine speed is now derived from the actual drive chain ratio, not hardcoded from source.
	if _central_engine and _central_engine.has_method("set_target_angular_speed"):
		var engine_drive := source_drive_speed * engine_drive_multiplier if connected else 0.0
		if connected:
			var synced_engine_drive := _derive_anchor_drive_speed(_central_engine, component_drive_targets, anchor_multipliers_by_id)
			if absf(synced_engine_drive) > 0.001:
				engine_drive = synced_engine_drive
		if jam_stalls_connected_network:
			engine_drive = 0.0
		_central_engine.set_target_angular_speed(engine_drive, connected)
	elif _central_engine and _central_engine.has_method("set_network_torque"):
		_central_engine.set_network_torque(delivered_torque, connected)
	if _central_engine and _central_engine.has_method("set_underpowered_state"):
		_central_engine.set_underpowered_state(false)
	if _central_engine and _central_engine.has_method("set_connection_state"):
		_central_engine.set_connection_state(connected)


func _refresh_source_rpm_feedback(
	all_power_sources: Array,
	drive_targets: Dictionary,
	anchor_multipliers_by_id: Dictionary = {}
) -> void:
	var next_feedback: Dictionary = {}
	for source_raw in all_power_sources:
		var source := source_raw as Node2D
		if source == null:
			continue

		var source_speed := _derive_anchor_drive_speed(source, drive_targets, anchor_multipliers_by_id)
		if absf(source_speed) <= 0.001 and source.has_method("get_angular_velocity"):
			source_speed = float(source.call("get_angular_velocity"))

		next_feedback[source.get_instance_id()] = _to_rpm(source_speed)

	_source_rpm_feedback_by_id = next_feedback


func _compute_engine_load_response(
	delivered_torque: float,
	source_drive_speed: float,
	engine_drive_multiplier: float,
	component_drive_targets: Dictionary,
	anchor_multipliers_by_id: Dictionary = {}
) -> Dictionary:
	var raw_engine_speed := 0.0
	if _central_engine != null:
		raw_engine_speed = _derive_anchor_drive_speed(_central_engine, component_drive_targets, anchor_multipliers_by_id)

	var ratio_magnitude := 1.0
	if absf(source_drive_speed) > 0.001:
		ratio_magnitude = maxf(absf(raw_engine_speed) / absf(source_drive_speed), 0.001)
	else:
		ratio_magnitude = maxf(absf(engine_drive_multiplier), 0.001)

	var engine_torque := delivered_torque / ratio_magnitude
	var acceptance_ratio := 0.0
	if engine_torque > 0.001:
		var simulated_speed := raw_engine_speed
		for _i in range(4):
			var load_torque := _compute_engine_load_torque_scaled(simulated_speed)
			acceptance_ratio = clampf((engine_torque - load_torque) / engine_torque, 0.0, 1.0)
			simulated_speed = raw_engine_speed * acceptance_ratio

	return {
		"raw_engine_speed": raw_engine_speed,
		"acceptance_ratio": acceptance_ratio,
		"engine_torque": engine_torque,
	}


func _scale_connected_drive_targets(reachable_components: Array, drive_targets: Dictionary, speed_factor: float) -> void:
	var clamped_factor := clampf(speed_factor, 0.0, 1.0)
	if clamped_factor >= 0.999:
		return

	for component_raw in reachable_components:
		var component := component_raw as Node2D
		if component == null:
			continue
		var component_id := component.get_instance_id()
		if not drive_targets.has(component_id):
			continue
		drive_targets[component_id] = float(drive_targets.get(component_id, 0.0)) * clamped_factor


func _derive_anchor_drive_speed(
	anchor_node: Node2D,
	drive_targets: Dictionary,
	anchor_multipliers_by_id: Dictionary = {}
) -> float:
	if anchor_node == null or drive_targets.is_empty():
		return 0.0

	var anchor_id := anchor_node.get_instance_id()
	var anchor_multipliers := anchor_multipliers_by_id.get(anchor_id, {}) as Dictionary
	if anchor_multipliers.is_empty() and not anchor_multipliers_by_id.has(anchor_id):
		var anchor_radius := _get_node_connection_radius(anchor_node)
		var anchor_drive_radius := _get_node_outer_radius(anchor_node)
		var anchor_drive_teeth := _get_node_tooth_count(anchor_node)
		anchor_multipliers = network_service.get_network_drive_multipliers(
			_components_container,
			anchor_node.global_position,
			anchor_radius,
			anchor_drive_radius,
			anchor_drive_teeth,
			[],
			connection_tolerance
		)

	var weighted_speed_sum := 0.0
	var total_weight := 0.0
	var fallback_anchor_speed := 0.0
	var fallback_component_speed := 0.0
	for component_id_raw in anchor_multipliers.keys():
		var component_id := int(component_id_raw)
		if not drive_targets.has(component_id):
			continue

		var component_speed := float(drive_targets.get(component_id, 0.0))
		var multiplier := float(anchor_multipliers.get(component_id_raw, 0.0))
		if absf(component_speed) <= 0.001 or absf(multiplier) <= 0.0001:
			continue

		var anchor_speed := component_speed / multiplier
		var sample_weight := absf(component_speed)
		weighted_speed_sum += anchor_speed * sample_weight
		total_weight += sample_weight

		if sample_weight > absf(fallback_component_speed):
			fallback_component_speed = component_speed
			fallback_anchor_speed = anchor_speed

	if total_weight > 0.001:
		return weighted_speed_sum / total_weight

	return fallback_anchor_speed


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
		var comp_teeth := _get_node_tooth_count(component)
		var engine_teeth := _get_node_tooth_count(_central_engine)
		var edge_ratio := 1.0
		if comp_teeth > 0 and engine_teeth > 0:
			edge_ratio = float(comp_teeth) / float(engine_teeth)
		else:
			var comp_outer := _get_node_outer_radius(component)
			edge_ratio = comp_outer / maxf(engine_outer, 0.001)
		# Meshing gears reverse direction; chain preserves it (handled by sign).
		return comp_mult * edge_ratio * -1.0

	# Fallback: use the simple source-to-engine ratio if no direct driver found.
	return 0.0


## Group isolated sources by connected subgraph using union-find on their
## reachable component sets and direct source coupling. Sources that share
## components or directly touch node-to-node are in the same group so their
## torques and speed conflicts can pool for the underpowered decision.
func _group_isolated_sources(iso_data: Array) -> Array:
	var n := iso_data.size()
	if n == 0:
		return []
	var parent: Array = []
	for i in range(n):
		parent.append(i)
	var source_nodes: Array = []
	var reachable_id_sets: Array = []
	for i in range(n):
		var source_node := iso_data[i].get("node") as Node2D
		source_nodes.append(source_node)
		var reachable_i: Array = iso_data[i].get("reachable", []) as Array
		var ids_i: Dictionary = {}
		for c in reachable_i:
			if c is Node2D:
				ids_i[(c as Node2D).get_instance_id()] = true
		reachable_id_sets.append(ids_i)
	for i in range(n):
		var source_i := source_nodes[i] as Node2D
		var ids_i := reachable_id_sets[i] as Dictionary
		for j in range(i + 1, n):
			var coupled := false
			var ids_j := reachable_id_sets[j] as Dictionary
			for id_raw in ids_j.keys():
				if ids_i.has(id_raw):
					coupled = true
					break
			if not coupled and source_i != null:
				var source_j := source_nodes[j] as Node2D
				if source_j != null:
					var radius_i := _get_node_connection_radius(source_i)
					var radius_j := _get_node_connection_radius(source_j)
					var contact := source_i.global_position.distance_to(source_j.global_position)
					coupled = absf(contact - (radius_i + radius_j)) <= connection_tolerance
			if coupled:
				var ri := _uf_find(parent, i)
				var rj := _uf_find(parent, j)
				if ri != rj:
					parent[ri] = rj
	var groups: Dictionary = {}
	for i in range(n):
		var root := _uf_find(parent, i)
		if not groups.has(root):
			groups[root] = []
		groups[root].append(iso_data[i])
	return groups.values()


func _uf_find(parent: Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


func _compute_source_engine_drive_multiplier(
	source: Node2D,
	reachable_components: Array,
	source_multipliers_cache: Dictionary = {},
	has_cached_multipliers: bool = false
) -> float:
	if source == null or reachable_components.is_empty():
		return 1.0
	var source_multipliers := source_multipliers_cache
	if source_multipliers.is_empty() and not has_cached_multipliers:
		var source_radius := _get_node_connection_radius(source)
		var source_drive_radius := _get_node_outer_radius(source)
		var source_drive_teeth := _get_node_tooth_count(source)
		source_multipliers = network_service.get_network_drive_multipliers(
			_components_container,
			source.global_position,
			source_radius,
			source_drive_radius,
			source_drive_teeth,
			[],
			connection_tolerance
		)
	var multiplier := _compute_engine_drive_multiplier(reachable_components, source_multipliers, {}, true)
	if absf(multiplier) <= 0.0001:
		return 1.0
	return multiplier


func _compute_reflected_load_factor_from_multiplier(engine_drive_multiplier: float) -> float:
	var ratio_magnitude := maxf(absf(engine_drive_multiplier), 0.001)
	# ratio < 1.0 (reduction) lowers reflected source-side load,
	# ratio > 1.0 (overdrive) raises reflected source-side load.
	return clampf(ratio_magnitude, 0.25, 4.0)


func _compute_network_reflected_load_factor(
	power_sources: Array,
	reachable_components: Array,
	source_multipliers_by_id: Dictionary = {}
) -> float:
	if power_sources.is_empty() or reachable_components.is_empty() or _central_engine == null:
		return 1.0
	var weighted_factor_sum := 0.0
	var total_weight := 0.0
	for source_raw in power_sources:
		var source := source_raw as Node2D
		if source == null:
			continue
		var source_output := maxf(_get_power_source_output(source, 0.0), 0.001)
		var source_engine_multiplier := _compute_source_engine_drive_multiplier(
			source,
			reachable_components,
			source_multipliers_by_id.get(source.get_instance_id(), {}) as Dictionary,
			source_multipliers_by_id.has(source.get_instance_id())
		)
		var source_factor := _compute_reflected_load_factor_from_multiplier(source_engine_multiplier)
		weighted_factor_sum += source_factor * source_output
		total_weight += source_output
	if total_weight <= 0.001:
		return 1.0
	return weighted_factor_sum / total_weight


func _compute_reflected_engine_load(
	power_sources: Array,
	reachable_components: Array,
	source_drive_speed: float,
	source_multipliers_by_id: Dictionary = {}
) -> float:
	if power_sources.is_empty() or reachable_components.is_empty() or _central_engine == null:
		return 0.0

	var weighted_load_sum := 0.0
	var total_weight := 0.0
	for source_raw in power_sources:
		var source := source_raw as Node2D
		if source == null:
			continue
		var source_id := source.get_instance_id()
		var source_output := maxf(_get_power_source_output(source, 0.0), 0.001)

		# Resolve the raw drive multipliers for this source (from cache or live BFS).
		var source_multipliers := source_multipliers_by_id.get(source_id, {}) as Dictionary
		if source_multipliers.is_empty() and not source_multipliers_by_id.has(source_id):
			var source_radius := _get_node_connection_radius(source)
			var source_drive_radius := _get_node_outer_radius(source)
			var source_drive_teeth := _get_node_tooth_count(source)
			source_multipliers = network_service.get_network_drive_multipliers(
				_components_container,
				source.global_position,
				source_radius,
				source_drive_radius,
				source_drive_teeth,
				[],
				connection_tolerance
			)

		# Use the raw (no-fallback) engine drive multiplier.  If a source has no
		# direct BFS path to the engine (e.g. it is an upstream relay in a chained
		# node→comp→node→comp→engine topology), _compute_engine_drive_multiplier
		# returns 0.0.  Skip it: applying the 1.0 fallback here would cause the
		# engine to be estimated as spinning at full source speed, producing a
		# massively inflated reflected load that incorrectly stalls the network.
		var engine_multiplier := _compute_engine_drive_multiplier(reachable_components, source_multipliers, {}, true)
		if absf(engine_multiplier) <= 0.0001:
			continue

		var local_source_speed := source_drive_speed
		if absf(local_source_speed) <= 0.001:
			local_source_speed = _get_source_drive_speed([source], false)
		var reflected_engine_load := _compute_reflected_engine_load_for_multiplier(engine_multiplier, local_source_speed)
		weighted_load_sum += reflected_engine_load * source_output
		total_weight += source_output

	if total_weight <= 0.001:
		return 0.0
	return weighted_load_sum / total_weight


func _compute_reflected_engine_load_for_multiplier(engine_drive_multiplier: float, source_drive_speed: float) -> float:
	if _central_engine == null:
		return 0.0

	var estimated_engine_speed := source_drive_speed * engine_drive_multiplier
	var engine_load_torque := _compute_engine_load_torque_scaled(estimated_engine_speed)
	# Reflect central-engine torque back to source side using the actual speed
	# ratio magnitude. Do not enforce the generic 0.25 floor here, or high
	# reduction paths get over-penalized and can stall immediately at startup.
	# Keep overdrive reflection bounded so stacked compounds do not create
	# disproportionate startup deficits from the giant engine load curve.
	var reflected_factor := clampf(absf(engine_drive_multiplier), 0.001, 2.5)
	return engine_load_torque * reflected_factor


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
	var completed := _recalculate_and_publish_state()
	_network_dirty = not completed


func get_perf_stats() -> Dictionary:
	var component_count := _components_container.get_child_count() if _components_container != null else _perf_last_component_count
	var thread_eligible := false
	if threaded_solver_enabled and _components_container != null:
		thread_eligible = component_count >= threaded_solver_component_threshold
	return {
		"last_recalc_ms": _perf_last_recalc_ms,
		"avg_recalc_ms": _perf_avg_recalc_ms,
		"peak_recalc_ms": _perf_peak_recalc_ms,
		"solver_mode": _perf_last_solver_mode,
		"thread_request_ms": _perf_last_thread_request_ms,
		"thread_worker_ms": _perf_last_thread_worker_ms,
		"thread_apply_ms": _perf_last_thread_apply_ms,
		"recalc_samples": _perf_recalc_samples,
		"network_dirty": _network_dirty,
		"dirty_wait_ms": _recalc_timer * 1000.0,
		"sim_tick_hz": simulation_tick_hz,
		"reachable_count": _perf_last_reachable_count,
		"profile_count": _perf_last_profile_count,
		"underpowered": _perf_last_underpowered,
		"component_count": component_count,
		"threaded_solver_enabled": threaded_solver_enabled,
		"threaded_solver_running": _threaded_solver_running,
		"threaded_solver_eligible": thread_eligible,
		"threaded_solver_threshold": threaded_solver_component_threshold
	}


func get_ui_overlay_snapshot() -> Dictionary:
	return _ui_overlay_snapshot.duplicate()


func get_component_ui_snapshot(component: Node2D) -> Dictionary:
	if component == null:
		return {}

	var cid := component.get_instance_id()
	var profile := _ui_component_profiles.get(cid, {}) as Dictionary
	var zone := _get_zone_condition_at(component.global_position)
	var snapshot := {
		"connected": _ui_connected_component_ids.has(cid),
		"friction": float(profile.get("friction", 0.0)),
		"load_ratio": float(_ui_component_load_ratios.get(cid, 0.0)),
		"torque": float(_ui_component_torque_by_id.get(cid, 0.0)),
		"component_type": str(profile.get("type", str(component.get_meta("component_type", "")))),
		"tooth_count": int(profile.get("tooth_count", 0)),
		"outer_radius": float(profile.get("outer_radius", _get_node_outer_radius(component))),
		"bottleneck": cid == int(_ui_overlay_snapshot.get("bottleneck_id", -1)),
		"zone_type": str(zone.get("zone_type", "")),
		"zone_intensity": float(zone.get("intensity", 0.0))
	}
	if component.name.begins_with("Power"):
		snapshot["source_remaining_budget"] = float(_ui_source_budget_by_id.get(cid, 0.0))
		snapshot["source_available_torque"] = float(_ui_source_available_by_id.get(cid, 0.0))
		if component.has_method("get_source_status"):
			snapshot["source_status"] = str(component.call("get_source_status"))
		if component.has_method("get_source_no_load_rpm"):
			snapshot["source_no_load_rpm"] = float(component.call("get_source_no_load_rpm"))
		if component.has_method("get_source_last_rpm"):
			snapshot["source_rpm"] = float(component.call("get_source_last_rpm"))
	elif component.name == "CentralEngine":
		snapshot["engine_operating_state"] = _last_engine_operating_state
		snapshot["engine_band_multiplier"] = _last_engine_band_multiplier
		snapshot["engine_input_horsepower"] = _last_engine_input_horsepower
	return snapshot


func _build_component_profile_lookup(reachable_profiles: Array) -> Dictionary:
	var lookup: Dictionary = {}
	for profile_raw in reachable_profiles:
		if not profile_raw is Dictionary:
			continue
		var profile := profile_raw as Dictionary
		var cid := int(profile.get("id", 0))
		if cid == 0:
			continue
		lookup[cid] = profile.duplicate()
	return lookup


func _build_component_id_lookup(components: Array) -> Dictionary:
	var lookup: Dictionary = {}
	for component_raw in components:
		var component := component_raw as Node2D
		if component == null:
			continue
		lookup[component.get_instance_id()] = true
	return lookup


func _build_component_node_lookup() -> Dictionary:
	var lookup: Dictionary = {}
	if _components_container == null:
		return lookup

	for child in _components_container.get_children():
		var component := child as Node2D
		if component == null:
			continue
		lookup[component.get_instance_id()] = component
	return lookup


func _components_from_ids(component_ids: Array, component_lookup: Dictionary) -> Array:
	var components: Array = []
	for id_raw in component_ids:
		var component_id := int(id_raw)
		var component := component_lookup.get(component_id, null) as Node2D
		if component == null:
			continue
		components.append(component)
	return components


func _build_id_set(ids: Array) -> Dictionary:
	var id_set: Dictionary = {}
	for id_raw in ids:
		id_set[int(id_raw)] = true
	return id_set


func _get_bottleneck_profile(reachable_profiles: Array) -> Dictionary:
	var bottleneck: Dictionary = {}
	var highest_friction := -INF
	for profile_raw in reachable_profiles:
		if not profile_raw is Dictionary:
			continue
		var profile := profile_raw as Dictionary
		var friction := float(profile.get("friction", 0.0))
		if friction <= highest_friction:
			continue
		highest_friction = friction
		bottleneck = profile
	return bottleneck


func _get_profile_display_name(profile: Dictionary) -> String:
	match str(profile.get("type", "")):
		PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_SMALL:
			return "Small Gear"
		PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_MEDIUM:
			return "Medium Gear"
		PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_LARGE:
			return "Large Gear"
		PROJECT_PATHS_SCRIPT.COMPONENT_SHAFT:
			return "Shaft"
		PROJECT_PATHS_SCRIPT.COMPONENT_CHAIN:
			return "Chain"
		PROJECT_PATHS_SCRIPT.COMPONENT_FLYWHEEL:
			return "Flywheel"
		PROJECT_PATHS_SCRIPT.COMPONENT_CLUTCH:
			return "Clutch"
		PROJECT_PATHS_SCRIPT.COMPONENT_DIFFERENTIAL:
			return "Differential"
		_:
			return ""


func _get_node_outer_radius(node: Node2D) -> float:
	if node == null:
		return PROJECT_PATHS_SCRIPT.DEFAULT_GEAR_OUTER_RADIUS

	if node.name == "CentralEngine" and PROJECT_PATHS_SCRIPT.ENGINE_MECHANICAL_COUPLED_MODE:
		var engine_visual := node.get_node_or_null("Visual")
		if engine_visual != null:
			var engine_radius_value: Variant = engine_visual.get("outer_radius")
			if engine_radius_value != null:
				return maxf(2.0, float(engine_radius_value))

	# Anchor nodes expose a mechanical mesh radius that should stay independent
	# from visual shell size (especially the macro central engine presentation).
	var anchor_mesh_radius: Variant = node.get("source_outer_radius")
	if anchor_mesh_radius != null:
		var mesh_radius := float(anchor_mesh_radius)
		if mesh_radius > 0.0:
			return mesh_radius

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

	if node.name == "CentralEngine" and PROJECT_PATHS_SCRIPT.ENGINE_MECHANICAL_COUPLED_MODE:
		var engine_outer := _get_node_outer_radius(node)
		return PROJECT_PATHS_SCRIPT.compute_tooth_count_from_outer_radius(engine_outer)

	# Keep drivetrain ratio math anchored to mechanical radius on anchor nodes.
	var anchor_mesh_radius: Variant = node.get("source_outer_radius")
	if anchor_mesh_radius != null:
		var mesh_radius := float(anchor_mesh_radius)
		if mesh_radius > 0.0:
			return PROJECT_PATHS_SCRIPT.compute_tooth_count_from_outer_radius(mesh_radius)

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


func _get_isolated_detail_budget(component_count: int, isolated_source_count: int) -> int:
	var budget := DETAILED_ISOLATED_SOURCE_BUDGET_BASE
	if component_count >= DETAILED_ISOLATED_COMPONENT_HUGE or isolated_source_count >= 900:
		budget = DETAILED_ISOLATED_SOURCE_BUDGET_HUGE
	elif component_count >= DETAILED_ISOLATED_COMPONENT_LARGE or isolated_source_count >= 600:
		budget = DETAILED_ISOLATED_SOURCE_BUDGET_LARGE
	elif component_count >= DETAILED_ISOLATED_COMPONENT_MEDIUM or isolated_source_count >= 350:
		budget = DETAILED_ISOLATED_SOURCE_BUDGET_MEDIUM
	return clampi(budget, 8, DETAILED_ISOLATED_SOURCE_BUDGET_BASE)


func _to_rpm(angular_speed: float) -> float:
	return absf(angular_speed) * (60.0 / TAU)


func _get_engine_coupled_hp_multiplier() -> float:
	if not PROJECT_PATHS_SCRIPT.ENGINE_MECHANICAL_COUPLED_MODE or _central_engine == null:
		return 1.0
	var baseline_radius := maxf(PROJECT_PATHS_SCRIPT.ENGINE_COUPLED_BASELINE_RADIUS, 1.0)
	var current_radius := _get_node_outer_radius(_central_engine)
	var coupled_ratio := maxf(current_radius / baseline_radius, 1.0)
	var exponent := clampf(PROJECT_PATHS_SCRIPT.ENGINE_COUPLED_HP_RETUNE_EXPONENT, 0.0, 1.0)
	var multiplier := pow(coupled_ratio, exponent)
	return clampf(multiplier, 1.0, PROJECT_PATHS_SCRIPT.ENGINE_COUPLED_HP_RETUNE_MAX)


func _get_engine_coupled_load_multiplier() -> float:
	if not PROJECT_PATHS_SCRIPT.ENGINE_MECHANICAL_COUPLED_MODE or _central_engine == null:
		return 1.0
	var baseline_radius := maxf(PROJECT_PATHS_SCRIPT.ENGINE_COUPLED_BASELINE_RADIUS, 1.0)
	var current_radius := _get_node_outer_radius(_central_engine)
	var coupled_ratio := maxf(current_radius / baseline_radius, 1.0)
	var exponent := maxf(PROJECT_PATHS_SCRIPT.ENGINE_COUPLED_LOAD_EXPONENT, 0.0)
	var multiplier := pow(coupled_ratio, exponent)
	return clampf(multiplier, 1.0, PROJECT_PATHS_SCRIPT.ENGINE_COUPLED_LOAD_MAX)


func _compute_engine_load_torque_scaled(engine_angular_speed: float) -> float:
	return torque_system.compute_engine_load_torque(engine_angular_speed) * _get_engine_coupled_load_multiplier()


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


func _compute_gear_variation_bonus_multiplier(reachable_profiles: Array) -> float:
	if reachable_profiles.is_empty():
		return 1.0

	var gear_types_seen: Dictionary = {}
	var has_chain := false
	var compound_stack_count := 0
	var counted_compound_roots: Dictionary = {}

	for profile_raw in reachable_profiles:
		if not profile_raw is Dictionary:
			continue
		var profile := profile_raw as Dictionary
		var component_type := str(profile.get("type", ""))

		if component_type == PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_SMALL or component_type == PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_MEDIUM or component_type == PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_LARGE:
			gear_types_seen[component_type] = true
		elif component_type == PROJECT_PATHS_SCRIPT.COMPONENT_CHAIN:
			has_chain = true

		if not PROJECT_PATHS_SCRIPT.GEAR_VARIATION_INCLUDE_COMPOUND:
			continue
		var added_layers := int(profile.get("compound_added_layers", 0))
		if added_layers <= 0:
			continue
		var node := profile.get("node", null) as Node2D
		if node == null:
			continue
		var root_id := int(node.get_meta("stack_root_id", node.get_instance_id()))
		if counted_compound_roots.has(root_id):
			continue
		counted_compound_roots[root_id] = true
		compound_stack_count += 1

	var bonus := 0.0
	var distinct_gear_types := mini(gear_types_seen.size(), PROJECT_PATHS_SCRIPT.GEAR_VARIATION_BONUS_MAX_TYPES)
	bonus += float(distinct_gear_types) * PROJECT_PATHS_SCRIPT.GEAR_VARIATION_BONUS_PER_TYPE

	if PROJECT_PATHS_SCRIPT.GEAR_VARIATION_INCLUDE_CHAIN and has_chain:
		bonus += PROJECT_PATHS_SCRIPT.GEAR_VARIATION_CHAIN_BONUS

	if PROJECT_PATHS_SCRIPT.GEAR_VARIATION_INCLUDE_COMPOUND:
		var counted_stacks := mini(compound_stack_count, PROJECT_PATHS_SCRIPT.GEAR_VARIATION_COMPOUND_BONUS_MAX_STACKS)
		bonus += float(counted_stacks) * PROJECT_PATHS_SCRIPT.GEAR_VARIATION_COMPOUND_BONUS_PER_STACK

	return 1.0 + maxf(bonus, 0.0)


func _compute_compound_stack_efficiency_multiplier(reachable_profiles: Array) -> float:
	if reachable_profiles.is_empty():
		return 1.0

	var added_layer_total := 0
	var counted_roots: Dictionary = {}
	for profile_raw in reachable_profiles:
		if not profile_raw is Dictionary:
			continue
		var profile := profile_raw as Dictionary
		var node := profile.get("node", null) as Node2D
		if node == null:
			continue

		var root_id := int(node.get_meta("stack_root_id", node.get_instance_id()))
		if counted_roots.has(root_id):
			continue
		counted_roots[root_id] = true

		var added_layers := int(profile.get("compound_added_layers", 0))
		if added_layers <= 0:
			continue
		added_layer_total += added_layers

	if added_layer_total <= 0:
		return 1.0

	var per_layer_loss := clampf(PROJECT_PATHS_SCRIPT.COMPOUND_LAYER_EFFICIENCY_PENALTY, 0.0, 0.95)
	return pow(1.0 - per_layer_loss, float(added_layer_total))


func _compute_shaft_joint_penalty(reachable_profiles: Array, graph_snapshot: Dictionary = {}) -> float:
	if reachable_profiles.is_empty():
		return 0.0

	var adjacency := graph_snapshot.get("adjacency", {}) as Dictionary
	if not adjacency.is_empty():
		var shaft_ids: Dictionary = {}
		for profile_raw in reachable_profiles:
			if not profile_raw is Dictionary:
				continue
			var profile := profile_raw as Dictionary
			if str(profile.get("type", "")) != PROJECT_PATHS_SCRIPT.COMPONENT_SHAFT:
				continue
			var shaft_id := int(profile.get("id", 0))
			if shaft_id == 0:
				continue
			shaft_ids[shaft_id] = true

		if shaft_ids.size() <= 1:
			return 0.0

		var shaft_joints := 0
		for shaft_id_raw in shaft_ids.keys():
			var shaft_id := int(shaft_id_raw)
			var neighbors := adjacency.get(shaft_id, []) as Array
			for edge_raw in neighbors:
				if not edge_raw is Dictionary:
					continue
				var edge := edge_raw as Dictionary
				var neighbor_id := int(edge.get("to", -1))
				if neighbor_id <= shaft_id:
					continue
				if shaft_ids.has(neighbor_id):
					shaft_joints += 1

		if shaft_joints <= 0:
			return 0.0
		return float(shaft_joints) * PROJECT_PATHS_SCRIPT.SHAFT_JOINT_FRICTION

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
