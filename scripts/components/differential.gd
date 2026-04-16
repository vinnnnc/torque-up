extends Node2D
class_name DifferentialComponent

const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")

@export var connected_tint: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var disconnected_tint: Color = Color(0.6, 0.6, 0.64, 1.0)
@export var strained_tint: Color = Color(1.0, 0.88, 0.64, 1.0)
@export var tint_smoothing: float = 8.0

## Torque lost during the merge of two inputs (efficiency of the differential).
@export var merge_efficiency: float = PROJECT_PATHS_SCRIPT.DIFFERENTIAL_MERGE_EFFICIENCY

var torque: float = 0.0
var angular_velocity: float = 0.0
# var _is_connected_to_main: bool = true

## Slot references — assigned by placement system when connected.
var input_a: Node = null
var input_b: Node = null

func _ready() -> void:
	set_meta("component_type", PROJECT_PATHS_SCRIPT.COMPONENT_DIFFERENTIAL)

## Blends two source RPMs into a single output RPM weighted by their torque contributions.
func compute_output_rpm(rpm_a: float, torque_a: float, rpm_b: float, torque_b: float) -> float:
	var total := torque_a + torque_b
	if total <= 0.0:
		return 0.0
	return (rpm_a * torque_a + rpm_b * torque_b) / total

## Sums both input torques minus merge losses.
func compute_output_torque(torque_a: float, torque_b: float) -> float:
	return (torque_a + torque_b) * merge_efficiency

func set_target_angular_speed(speed: float) -> void:
	angular_velocity = move_toward(angular_velocity, speed, 8.0 * get_process_delta_time())
