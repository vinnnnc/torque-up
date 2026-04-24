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


func compute_engine_operating_band_multiplier(engine_rpm: float) -> float:
	var rpm := maxf(engine_rpm, 0.0)
	var soft_min := PROJECT_PATHS_SCRIPT.ENGINE_OPERATING_BAND_SOFT_MIN_RPM
	var min_rpm := PROJECT_PATHS_SCRIPT.ENGINE_OPERATING_BAND_MIN_RPM
	var max_rpm := PROJECT_PATHS_SCRIPT.ENGINE_OPERATING_BAND_MAX_RPM
	var soft_max := PROJECT_PATHS_SCRIPT.ENGINE_OPERATING_BAND_SOFT_MAX_RPM

	if rpm < soft_min:
		return 0.35
	if rpm < min_rpm:
		var min_span := maxf(min_rpm - soft_min, 0.001)
		return lerpf(0.35, 1.0, (rpm - soft_min) / min_span)
	if rpm <= max_rpm:
		return 1.0
	if rpm <= soft_max:
		var max_span := maxf(soft_max - max_rpm, 0.001)
		return lerpf(1.0, 0.65, (rpm - max_rpm) / max_span)
	return 0.65


func get_engine_operating_state(engine_rpm: float) -> String:
	var rpm := maxf(engine_rpm, 0.0)
	if rpm < PROJECT_PATHS_SCRIPT.ENGINE_OPERATING_BAND_MIN_RPM:
		return "bogging"
	if rpm > PROJECT_PATHS_SCRIPT.ENGINE_OPERATING_BAND_MAX_RPM:
		return "overspeed"
	return "in_band"
