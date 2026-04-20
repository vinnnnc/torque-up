extends Node2D
class_name AnchorRotor

const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")

@export var always_active: bool = false
@export_enum("balanced", "torque", "speed") var power_node_type: String = PROJECT_PATHS_SCRIPT.POWER_NODE_BALANCED
@export var rated_torque_output: float = PROJECT_PATHS_SCRIPT.BASE_POWER_NODE_OUTPUT
@export var min_output_ratio: float = 0.7
@export var output_droop_strength: float = 0.45
@export var base_spin_speed: float = 1.2
@export var torque_spin_factor: float = 0.02
@export var inactive_spin_multiplier: float = 0.0
@export var underpowered_tint: Color = Color(1.0, 0.58, 0.58, 1.0)
@export var connected_tint: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var disconnected_tint: Color = Color(0.72, 0.72, 0.78, 1.0)
@export var engine_route_tint: Color = Color(0.82, 0.94, 1.0, 1.0)
@export var tint_smoothing: float = 8.0
@export var jitter_amount: float = 0.3
@export var jitter_speed: float = 20.0

var _network_torque: float = 0.0
var _is_network_active: bool = false
var _angular_velocity: float = 0.0
var _is_underpowered: bool = false
var _is_connected_to_network: bool = false
var _is_on_engine_route: bool = false
var _spin_direction: float = 1.0
var _direct_drive_speed: float = 0.0
var _use_direct_drive: bool = false
var _base_position: Vector2 = Vector2.ZERO
var _jitter_phase: float = 0.0

const SPIN_SMOOTHING: float = 6.0

func _ready() -> void:
	_base_position = position
	_jitter_phase = randf() * TAU
	if is_equal_approx(rated_torque_output, PROJECT_PATHS_SCRIPT.BASE_POWER_NODE_OUTPUT):
		_apply_type_defaults()

func set_network_torque(torque_value: float, network_active: bool, spin_direction: float = 1.0) -> void:
	_network_torque = max(torque_value, 0.0)
	_is_network_active = network_active
	_spin_direction = -1.0 if spin_direction < 0.0 else 1.0
	_use_direct_drive = false


func set_target_angular_speed(target_speed: float, network_active: bool) -> void:
	_direct_drive_speed = target_speed
	_is_network_active = network_active
	_use_direct_drive = true


func set_underpowered_state(is_underpowered: bool) -> void:
	_is_underpowered = is_underpowered


func set_connection_state(connection_active: bool) -> void:
	_is_connected_to_network = connection_active
	_is_on_engine_route = connection_active


func set_engine_route_state(route_active: bool) -> void:
	_is_on_engine_route = route_active


func get_power_output(load_ratio: float = 0.0) -> float:
	var clamped_load := clampf(load_ratio, 0.0, 1.0)
	var droop := output_droop_strength * clamped_load
	var ratio := maxf(min_output_ratio, 1.0 - droop)
	return rated_torque_output * ratio


func _apply_type_defaults() -> void:
	match power_node_type:
		PROJECT_PATHS_SCRIPT.POWER_NODE_TORQUE:
			rated_torque_output = PROJECT_PATHS_SCRIPT.TORQUE_NODE_OUTPUT
			base_spin_speed = 0.85
			torque_spin_factor = 0.01
			min_output_ratio = 0.76
			output_droop_strength = 0.3
		PROJECT_PATHS_SCRIPT.POWER_NODE_SPEED:
			rated_torque_output = PROJECT_PATHS_SCRIPT.SPEED_NODE_OUTPUT
			base_spin_speed = 3.2
			torque_spin_factor = 0.045
			min_output_ratio = 0.66
			output_droop_strength = 0.5
		_:
			rated_torque_output = PROJECT_PATHS_SCRIPT.BASE_POWER_NODE_OUTPUT
			base_spin_speed = 1.45
			torque_spin_factor = 0.02
			min_output_ratio = 0.7
			output_droop_strength = 0.45


func get_angular_velocity() -> float:
	return _angular_velocity

func _process(delta: float) -> void:
	var target_speed := 0.0

	if not _is_underpowered:
		if _use_direct_drive:
			target_speed = _direct_drive_speed
		else:
			if always_active:
				if _is_network_active:
					target_speed += base_spin_speed * _spin_direction
				else:
					target_speed += base_spin_speed

			if _is_network_active:
				target_speed += _network_torque * torque_spin_factor * _spin_direction
			elif not always_active:
				target_speed += base_spin_speed * inactive_spin_multiplier

	_angular_velocity = lerpf(_angular_velocity, target_speed, min(delta * SPIN_SMOOTHING, 1.0))
	rotation += _angular_velocity * delta

	var target_tint := underpowered_tint
	if not _is_underpowered:
		target_tint = connected_tint if _is_connected_to_network else disconnected_tint
		if _is_on_engine_route:
			target_tint = target_tint.lerp(engine_route_tint, 0.45)
	modulate = modulate.lerp(target_tint, min(delta * tint_smoothing, 1.0))

	if _is_underpowered:
		var t := (float(Time.get_ticks_msec()) * 0.001 * jitter_speed) + _jitter_phase
		var jitter_offset := Vector2(sin(t), cos(t * 1.37)) * jitter_amount
		position = _base_position + jitter_offset
	else:
		position = position.lerp(_base_position, min(delta * 12.0, 1.0))
