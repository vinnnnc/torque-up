extends RefCounted
class_name TorqueSystem

const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")
const HP_CONVERSION_FACTOR := 5252.0

func apply_connection_loss(input_torque: float, connection_loss: float) -> float:
	return max(input_torque - connection_loss, 0.0)

func compute_delivered_torque(raw_torque: float, connection_count: int, loss_per_connection: float) -> float:
	var total_loss := float(connection_count) * loss_per_connection
	return apply_connection_loss(raw_torque, total_loss)

func compute_output_horsepower(torque_value: float, engine_rpm: float, efficiency: float) -> float:
	var clamped_efficiency: float = clampf(efficiency, 0.0, 1.0)
	var clamped_rpm: float = maxf(engine_rpm, 0.0)
	return (torque_value * clamped_rpm / HP_CONVERSION_FACTOR) * clamped_efficiency


func compute_engine_load_torque(engine_angular_speed: float) -> float:
	var omega := absf(engine_angular_speed)
	var static_load := PROJECT_PATHS_SCRIPT.ENGINE_LOAD_STATIC_TORQUE
	var linear := PROJECT_PATHS_SCRIPT.ENGINE_LOAD_LINEAR_COEFF * omega
	var quadratic := PROJECT_PATHS_SCRIPT.ENGINE_LOAD_QUADRATIC_COEFF * omega * omega
	return maxf(0.0, static_load + linear + quadratic)
