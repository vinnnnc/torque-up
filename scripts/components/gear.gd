extends Node2D
class_name GearComponent

const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")

@export var connected_tint: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var disconnected_tint: Color = Color(0.6, 0.6, 0.64, 1.0)
@export var engine_route_tint: Color = Color(0.82, 0.94, 1.0, 1.0)
@export var strained_tint: Color = Color(1.0, 0.88, 0.64, 1.0)
@export var stalled_tint: Color = Color(0.95, 0.56, 0.56, 1.0)
@export var stress_pulse_tint: Color = Color(1.0, 0.74, 0.5, 1.0)
@export var conflict_tint: Color = Color(1.0, 0.32, 0.32, 1.0)
@export var condition_heat_tint: Color = Color(1.0, 0.48, 0.22, 1.0)
@export var tint_smoothing: float = 8.0
@export var stress_pulse_strength: float = 0.28
@export var stress_pulse_speed: float = 10.0

## Condition threshold states. Kept in sync with project_paths constants.
enum ConditionState { NORMAL = 0, STRAINED = 1, UNSTABLE = 2, RISK = 3, JAMMED = 4 }

var torque := 0.0
var angular_velocity: float = 0.0
var _direct_target_velocity := 0.0
var _use_direct_drive := false
var _is_connected_to_main: bool = true
var _is_on_engine_route: bool = false
var _has_connection_state: bool = false
var _stress_level: float = 0.0
var _is_stalled: bool = false
var _pulse_phase: float = 0.0
var _is_shaft_component: bool = false
var _is_shell_component: bool = false
var _base_rotation: float = 0.0
var _visual: Node = null
var _pulley_mode: bool = false
## Direction conflict state — gear receives two incompatible spin requirements.
var _has_direction_conflict: bool = false
## Condition system state.
var _condition_state: int = ConditionState.NORMAL
var _condition_heat: float = 0.0
var _condition_contamination: float = 0.0

const TORQUE_TO_SPEED := 0.06
const SMOOTHING := 8.0

func _ready() -> void:
	_pulse_phase = randf() * TAU
	var component_type: String = str(get_meta("component_type", ""))
	_is_shaft_component = component_type == PROJECT_PATHS_SCRIPT.COMPONENT_SHAFT
	_is_shell_component = component_type == PROJECT_PATHS_SCRIPT.COMPONENT_CLUTCH or component_type == PROJECT_PATHS_SCRIPT.COMPONENT_DIFFERENTIAL
	_base_rotation = rotation
	_visual = get_node_or_null("Visual")

func set_torque(value: float) -> void:
	torque = value
	_use_direct_drive = false


func set_target_angular_speed(value: float) -> void:
	_direct_target_velocity = value
	_use_direct_drive = true


func get_angular_velocity() -> float:
	return angular_velocity


func set_connection_state(connection_active: bool) -> void:
	_is_connected_to_main = connection_active
	_is_on_engine_route = connection_active
	_has_connection_state = true


func set_engine_route_state(route_active: bool) -> void:
	_is_on_engine_route = route_active
	_has_connection_state = true


func set_stress_state(stress_level: float, stalled: bool) -> void:
	_stress_level = clampf(stress_level, 0.0, 1.0)
	_is_stalled = stalled


## Called each tick by the conflict detection pass in GameManager.
func set_conflict_state(in_conflict: bool) -> void:
	_has_direction_conflict = in_conflict


## Called each tick by ComponentConditionService.
func set_condition_state(state: int, heat: float, contamination: float) -> void:
	_condition_state = state
	_condition_heat = clampf(heat, 0.0, 1.0)
	_condition_contamination = clampf(contamination, 0.0, 1.0)


func is_jammed() -> bool:
	return _condition_state == ConditionState.JAMMED

func set_pulley_mode(enabled: bool) -> void:
	_pulley_mode = enabled
	if _visual and _visual.has_method("set"):
		_visual.pulley_mode = enabled
	queue_redraw()

func set_stacked_top(enabled: bool) -> void:
	if _visual and _visual.has_method("set"):
		_visual.is_stacked_top = enabled
		_visual.queue_redraw()

func _process(delta: float) -> void:
	var target_velocity := _direct_target_velocity if _use_direct_drive else torque * TORQUE_TO_SPEED
	# Jam, stall, or direction conflict are hard-stop states for readability.
	if _condition_state == ConditionState.JAMMED or _is_stalled or _has_direction_conflict:
		target_velocity = 0.0
		angular_velocity = 0.0
	else:
		angular_velocity = lerpf(angular_velocity, target_velocity, min(delta * SMOOTHING, 1.0))
	if _is_shaft_component or _is_shell_component:
		rotation = _base_rotation
		if _visual and _visual.has_method("set_shaft_spin_speed"):
			_visual.call("set_shaft_spin_speed", angular_velocity)
		if _visual and _visual.has_method("set_visual_spin_speed"):
			_visual.call("set_visual_spin_speed", angular_velocity)
	else:
		rotation += angular_velocity * delta

	if _has_connection_state:
		var target_tint := disconnected_tint
		if _is_connected_to_main:
			if _has_direction_conflict:
				# Conflict takes priority: red flicker.
				_pulse_phase += delta * 14.0
				var cf := ((sin(_pulse_phase) + 1.0) * 0.5) * 0.55 + 0.45
				target_tint = stalled_tint.lerp(conflict_tint, cf)
			elif _condition_state == ConditionState.JAMMED:
				target_tint = conflict_tint
			elif _condition_state >= ConditionState.RISK:
				_pulse_phase += delta * stress_pulse_speed * 1.5
				var pulse := ((sin(_pulse_phase) + 1.0) * 0.5) * 0.5
				target_tint = condition_heat_tint.lerp(stalled_tint, pulse)
			elif _condition_state >= ConditionState.UNSTABLE:
				target_tint = strained_tint.lerp(condition_heat_tint, 0.55)
			elif _is_stalled:
				target_tint = stalled_tint
			elif _stress_level > 0.0:
				target_tint = connected_tint.lerp(strained_tint, _stress_level)
				if _stress_level > 0.2:
					_pulse_phase += delta * stress_pulse_speed * (0.6 + _stress_level)
					var pulse := ((sin(_pulse_phase) + 1.0) * 0.5) * stress_pulse_strength * _stress_level
					target_tint = target_tint.lerp(stress_pulse_tint, pulse)
			else:
				target_tint = connected_tint
			if _is_on_engine_route:
				target_tint = target_tint.lerp(engine_route_tint, 0.45)
		modulate = modulate.lerp(target_tint, min(delta * tint_smoothing, 1.0))
