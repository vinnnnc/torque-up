extends Node2D
class_name ClutchComponent

const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")

@export var connected_tint: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var disconnected_tint: Color = Color(0.6, 0.6, 0.64, 1.0)
@export var engaged_tint: Color = Color(0.64, 1.0, 0.72, 1.0)
@export var disengaged_tint: Color = Color(0.95, 0.88, 0.56, 1.0)
@export var tint_smoothing: float = 8.0

## RPM delta below which the clutch disengages (input speed < network speed by this margin).
@export var engagement_threshold: float = PROJECT_PATHS_SCRIPT.CLUTCH_ENGAGEMENT_THRESHOLD

var torque: float = 0.0
var angular_velocity: float = 0.0
var is_engaged: bool = true
# var _is_connected_to_main: bool = true

func _ready() -> void:
	set_meta("component_type", PROJECT_PATHS_SCRIPT.COMPONENT_CLUTCH)

## Evaluates engagement state given source RPM and current network RPM.
## Returns true when the clutch is passing torque through.
func evaluate_engagement(source_rpm: float, network_rpm: float) -> bool:
	is_engaged = source_rpm >= (network_rpm - engagement_threshold)
	return is_engaged

## Returns transmitted torque — zero when disengaged (freewheeling).
func get_transmitted_torque(input_torque: float) -> float:
	return input_torque if is_engaged else 0.0

func set_target_angular_speed(speed: float) -> void:
	angular_velocity = move_toward(angular_velocity, speed, 8.0 * get_process_delta_time())
