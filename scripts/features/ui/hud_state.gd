extends RefCounted
class_name HudState

var horsepower: float = 0.0
var available_torque: float = 0.0
var efficiency: float = 1.0
var rpm: float = 0.0
var used_torque: float = 0.0
var free_torque: float = 0.0

func set_values(
	new_horsepower: float,
	new_available_torque: float,
	new_efficiency: float,
	new_rpm: float = 0.0,
	new_used_torque: float = 0.0,
	new_free_torque: float = 0.0
) -> void:
	horsepower = max(new_horsepower, 0.0)
	available_torque = new_available_torque
	efficiency = clamp(new_efficiency, 0.0, 1.0)
	rpm = max(new_rpm, 0.0)
	used_torque = max(new_used_torque, 0.0)
	free_torque = new_free_torque
