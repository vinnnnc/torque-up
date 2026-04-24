extends Node

signal state_changed(horsepower: float, available_torque: float, efficiency: float, total_score: float, lifetime_hp: float, reliability_multiplier: float)
signal lifetime_hp_changed(lifetime_hp: float, reliability_multiplier: float)
signal jam_registered(total_jams: int)

## Current-tick snapshot values.
var horsepower: float = 0.0
var available_torque: float = 0.0
var efficiency: float = 1.0

## Internal RPM tracking (not exposed in signal; used by frontier logic).
var rpm: float = 0.0

## Stored menu preference. Tutorial flow can read this later.
var tutorial_enabled: bool = false

## Sandbox / endless scoring — never decrements.
var lifetime_hp: float = 0.0
## Modulates how quickly lifetime_hp accumulates based on network reliability.
var reliability_multiplier: float = 1.0

## Score accumulation.
var total_score: float = 0.0
var last_score_delta: float = 0.0

## Jam tracking for reliability calculation.
var total_jams: int = 0
## Jams in a rolling 60-second window.
var _recent_jams: Array = []
const JAM_WINDOW_SECONDS: float = 60.0
const JAM_PENALTY_PER_JAM: float = 0.08
const MIN_RELIABILITY: float = 0.35

## Called once per simulation tick to update the current snapshot and
## accumulate lifetime HP based on the current output and reliability.
func set_state(
	new_horsepower: float,
	new_available_torque: float,
	new_efficiency: float,
	new_score_delta: float,
	tick_delta: float = 0.0,
	new_rpm: float = 0.0
) -> void:
	horsepower = maxf(new_horsepower, 0.0)
	available_torque = new_available_torque
	efficiency = clampf(new_efficiency, 0.0, 1.0)
	rpm = maxf(new_rpm, 0.0)
	last_score_delta = maxf(new_score_delta, 0.0)

	if tick_delta > 0.0:
		_purge_old_jams()
		lifetime_hp += horsepower * tick_delta * reliability_multiplier
		total_score += last_score_delta
		lifetime_hp_changed.emit(lifetime_hp, reliability_multiplier)

	state_changed.emit(horsepower, available_torque, efficiency, total_score, lifetime_hp, reliability_multiplier)


## Record a jam event at the current time. Reliability multiplier updates
## based on how many jams occurred within the rolling window.
func register_jam() -> void:
	total_jams += 1
	_recent_jams.append(Time.get_ticks_msec() * 0.001)
	_purge_old_jams()
	_recalculate_reliability()
	jam_registered.emit(total_jams)


func set_tutorial_enabled(enabled: bool) -> void:
	tutorial_enabled = enabled


func reset_run_state() -> void:
	horsepower = 0.0
	available_torque = 0.0
	efficiency = 1.0
	rpm = 0.0
	lifetime_hp = 0.0
	total_score = 0.0
	last_score_delta = 0.0
	total_jams = 0
	_recent_jams.clear()
	reliability_multiplier = 1.0
	state_changed.emit(horsepower, available_torque, efficiency, total_score, lifetime_hp, reliability_multiplier)


func _purge_old_jams() -> void:
	var now := Time.get_ticks_msec() * 0.001
	var cutoff := now - JAM_WINDOW_SECONDS
	var keep: Array = []
	for t in _recent_jams:
		if float(t) >= cutoff:
			keep.append(t)
	_recent_jams = keep


func _recalculate_reliability() -> void:
	var recent_count := _recent_jams.size()
	var penalty := recent_count * JAM_PENALTY_PER_JAM
	reliability_multiplier = clampf(1.0 - penalty, MIN_RELIABILITY, 1.0)
