extends RefCounted
class_name ComponentConditionService

## Standalone, modular condition tracker for individual network components.
##
## Each game tick, call update() with the current component list, a zone-effect
## getter callable, and the tick delta. The service accumulates heat, cold stress,
## and contamination per component; determines threshold states; triggers
## temporary jams under sustained overload; and drives wear progression over
## many jams.
##
## Results are applied back to components via set_condition_state().
## This service owns no Node refs — it only stores data keyed by instance ID.

const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")

## Internal condition record per component (keyed by instance ID).
## { heat, cold_stress, contamination, strain_timer, jam_timer, jam_count, wear }
var _conditions: Dictionary = {}

## Returns the number of components currently tracked.
func get_tracked_count() -> int:
	return _conditions.size()


## Main update call. components is the Array of reachable Node2D components.
## zone_getter is a Callable(world_pos: Vector2) -> Dictionary with keys:
##   "zone_type": String  ("heat" | "cold" | "dusty" | "")
##   "intensity": float   (0..1, zone falloff strength at that position)
## load_ratios is an optional Dictionary {instance_id: float} of local load ratios.
func update(
	components: Array,
	zone_getter: Callable,
	tick_delta: float,
	load_ratios: Dictionary = {}
) -> void:
	var alive_ids: Dictionary = {}

	for component_raw in components:
		var component := component_raw as Node2D
		if component == null:
			continue

		var cid := component.get_instance_id()
		alive_ids[cid] = true

		if not _conditions.has(cid):
			_conditions[cid] = _empty_condition()

		var cond: Dictionary = _conditions[cid]
		var load_ratio := clampf(float(load_ratios.get(cid, 0.0)), 0.0, 1.0)

		_accumulate_zone_effects(cond, component.global_position, zone_getter, tick_delta, load_ratio)
		_decay_conditions(cond, tick_delta)
		_update_jam_state(cond, tick_delta, load_ratio)
		_update_wear(cond)
		_determine_state(cond, load_ratio)

		_conditions[cid] = cond
		_apply_to_component(component, cond)

	# Prune stale entries (components removed from network).
	for stale_id in _conditions.keys():
		if not alive_ids.has(stale_id):
			_conditions.erase(stale_id)


## Returns a copy of the condition record for a specific component, or empty
## dict if not tracked. Useful for the debug overlay.
func get_condition(component_id: int) -> Dictionary:
	if _conditions.has(component_id):
		return (_conditions[component_id] as Dictionary).duplicate()
	return {}


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _empty_condition() -> Dictionary:
	return {
		"heat": 0.0,
		"cold_stress": 0.0,
		"strain_timer": 0.0,
		"jam_timer": 0.0,
		"jam_count": 0,
		"wear": 0.0,
		"state": 0  # ConditionState.NORMAL
	}


func _accumulate_zone_effects(
	cond: Dictionary,
	world_pos: Vector2,
	zone_getter: Callable,
	delta: float,
	load_ratio: float
) -> void:
	var zone := zone_getter.call(world_pos) as Dictionary

	var zone_type := str(zone.get("zone_type", ""))
	var intensity := clampf(float(zone.get("intensity", 0.0)), 0.0, 1.0)

	match zone_type:
		"heat":
			cond["heat"] = clampf(
				float(cond["heat"]) + PROJECT_PATHS_SCRIPT.CONDITION_HEAT_GAIN_HOT * intensity * delta,
				0.0, 1.0
			)
		"cold":
			cond["cold_stress"] = clampf(
				float(cond["cold_stress"]) + PROJECT_PATHS_SCRIPT.CONDITION_COLD_GAIN_COLD * intensity * delta,
				0.0, 1.0
			)

	# Load always contributes a small heat gain regardless of zone type.
	cond["heat"] = clampf(
		float(cond["heat"]) + PROJECT_PATHS_SCRIPT.CONDITION_HEAT_GAIN_LOAD * load_ratio * delta,
		0.0, 1.0
	)


func _decay_conditions(cond: Dictionary, delta: float) -> void:
	cond["heat"] = clampf(
		float(cond["heat"]) - PROJECT_PATHS_SCRIPT.CONDITION_HEAT_LOSS_BASE * delta,
		0.0, 1.0
	)
	cond["cold_stress"] = clampf(
		float(cond["cold_stress"]) - PROJECT_PATHS_SCRIPT.CONDITION_COLD_LOSS_BASE * delta,
		0.0, 1.0
	)


func _update_jam_state(cond: Dictionary, delta: float, _load_ratio: float) -> void:
	# Runtime jam triggering is disabled. Keep legacy counters decayed to zero
	# so stress diagnostics remain available without hard-stop states.
	cond["jam_timer"] = maxf(0.0, float(cond["jam_timer"]) - delta * 4.0)
	cond["strain_timer"] = maxf(0.0, float(cond["strain_timer"]) - delta * 2.0)


func _update_wear(cond: Dictionary) -> void:
	var jam_count := int(cond["jam_count"])
	if jam_count < PROJECT_PATHS_SCRIPT.CONDITION_WEAR_JAM_THRESHOLD:
		return
	# Each jam beyond the threshold adds a small amount of permanent wear.
	var extra_jams := jam_count - PROJECT_PATHS_SCRIPT.CONDITION_WEAR_JAM_THRESHOLD
	cond["wear"] = clampf(float(cond["wear"]) + extra_jams * 0.04, 0.0, 1.0)


func _determine_state(cond: Dictionary, load_ratio: float) -> void:
	# Composite stress score: max of heat, cold_stress, wear (weighted) + load.
	var heat := float(cond["heat"])
	var cold := float(cond["cold_stress"])
	var wear := float(cond["wear"]) * 0.6
	var composite := maxf(heat, maxf(cold, wear))
	composite = maxf(composite, load_ratio * 0.65)

	if composite >= PROJECT_PATHS_SCRIPT.CONDITION_THRESHOLD_RISK:
		cond["state"] = 3  # ConditionState.RISK
	elif composite >= PROJECT_PATHS_SCRIPT.CONDITION_THRESHOLD_UNSTABLE:
		cond["state"] = 2  # ConditionState.UNSTABLE
	elif composite >= PROJECT_PATHS_SCRIPT.CONDITION_THRESHOLD_STRAINED:
		cond["state"] = 1  # ConditionState.STRAINED
	else:
		cond["state"] = 0  # ConditionState.NORMAL


func _apply_to_component(component: Node2D, cond: Dictionary) -> void:
	if component.has_method("set_condition_state"):
		component.call(
			"set_condition_state",
			int(cond["state"]),
			float(cond["heat"]),
			0.0
		)
