extends RefCounted
class_name TorqueSystem

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
