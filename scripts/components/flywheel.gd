extends Node2D
class_name FlywheelComponent

const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")

@export var connected_tint: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var disconnected_tint: Color = Color(0.6, 0.6, 0.64, 1.0)
@export var strained_tint: Color = Color(1.0, 0.88, 0.64, 1.0)
@export var stalled_tint: Color = Color(0.95, 0.56, 0.56, 1.0)
@export var tint_smoothing: float = 8.0

## Maximum stored torque energy the flywheel can hold.
@export var capacity: float = PROJECT_PATHS_SCRIPT.FLYWHEEL_CAPACITY
## Fraction of surplus torque absorbed per second when charging.
@export var charge_rate: float = PROJECT_PATHS_SCRIPT.FLYWHEEL_CHARGE_RATE
## Fraction of stored energy released per second when discharging to cover a deficit.
@export var discharge_rate: float = PROJECT_PATHS_SCRIPT.FLYWHEEL_DISCHARGE_RATE

var torque: float = 0.0
var angular_velocity: float = 0.0
var stored_energy: float = 0.0
# var _is_connected_to_main: bool = true

func _ready() -> void:
	set_meta("component_type", PROJECT_PATHS_SCRIPT.COMPONENT_FLYWHEEL)

## Returns how much torque the flywheel can contribute to cover a deficit this tick.
func draw_discharge(deficit: float, tick_delta: float) -> float:
	var available := stored_energy * discharge_rate * tick_delta
	var drawn := minf(available, deficit)
	stored_energy -= drawn
	return drawn

## Absorbs surplus torque into the flywheel this tick.
func absorb_surplus(surplus: float, tick_delta: float) -> void:
	var absorbed := surplus * charge_rate * tick_delta
	stored_energy = minf(stored_energy + absorbed, capacity)

## Charge ratio 0.0–1.0 for visual feedback.
func get_charge_ratio() -> float:
	return stored_energy / capacity if capacity > 0.0 else 0.0

func set_target_angular_speed(speed: float) -> void:
	angular_velocity = move_toward(angular_velocity, speed, 8.0 * get_process_delta_time())
	if _visual_node:
		_visual_node.rotation += angular_velocity * get_process_delta_time()

var _visual_node: Node = null

func _process(_delta: float) -> void:
	_visual_node = get_node_or_null("Visual")
