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
var _is_flywheel_component: bool = false
var _base_rotation: float = 0.0
var _visual: Node = null
var _presentation_visible: bool = true
var _pulley_mode: bool = false
var _flywheel_energy: float = 0.0
var _flywheel_peak_speed: float = 0.0
var _flywheel_last_sign: float = 1.0
## Direction conflict state — gear receives two incompatible spin requirements.
var _has_direction_conflict: bool = false
## Condition system state.
var _condition_state: int = ConditionState.NORMAL
var _condition_heat: float = 0.0
var _condition_contamination: float = 0.0

const TORQUE_TO_SPEED := 0.06
const SMOOTHING := 8.0
const FLYWHEEL_SPEED_TO_ENERGY := 10.0
const FLYWHEEL_PEAK_TRACKING := 3.0
# Removed constants kept as fallback literals.
const _FLYWHEEL_CAPACITY := 100.0
const _FLYWHEEL_DISCHARGE_RATE := 0.5
const _FLYWHEEL_CHARGE_RATE := 0.3

func _ready() -> void:
	_pulse_phase = randf() * TAU
	var component_type: String = str(get_meta("component_type", ""))
	_is_shaft_component = component_type == "shaft"
	_is_shell_component = component_type == "clutch" or component_type == "differential"
	_is_flywheel_component = component_type == "flywheel"
	_base_rotation = rotation
	_visual = get_node_or_null("Visual")
	_ensure_art_node()
	_ensure_visibility_notifier()


func _ensure_art_node() -> void:
	var art_node := get_node_or_null("Art") as Sprite2D
	if art_node == null:
		art_node = Sprite2D.new()
		art_node.name = "Art"
		add_child(art_node)

	art_node.centered = true
	art_node.z_as_relative = true
	art_node.z_index = 1


func _ensure_visibility_notifier() -> void:
	if Engine.is_editor_hint():
		return
	var notifier := get_node_or_null("PresentationVisibility") as VisibleOnScreenNotifier2D
	if notifier == null:
		notifier = VisibleOnScreenNotifier2D.new()
		notifier.name = "PresentationVisibility"
		add_child(notifier)
	var bounds_radius := 32.0
	if _visual != null:
		var outer_radius_value: Variant = _visual.get("outer_radius")
		if outer_radius_value != null:
			bounds_radius = maxf(bounds_radius, float(outer_radius_value) + 24.0)
	notifier.rect = Rect2(Vector2(-bounds_radius, -bounds_radius), Vector2(bounds_radius * 2.0, bounds_radius * 2.0))
	if not notifier.screen_entered.is_connected(_on_screen_entered):
		notifier.screen_entered.connect(_on_screen_entered)
	if not notifier.screen_exited.is_connected(_on_screen_exited):
		notifier.screen_exited.connect(_on_screen_exited)
	_presentation_visible = notifier.is_on_screen()


func _on_screen_entered() -> void:
	_presentation_visible = true


func _on_screen_exited() -> void:
	_presentation_visible = false

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


func is_sprocket_mode() -> bool:
	return _pulley_mode


## Returns how much temporary torque energy can be released this tick.
func draw_discharge(deficit: float, tick_delta: float) -> float:
	if not _is_flywheel_component:
		return 0.0
	if deficit <= 0.0 or tick_delta <= 0.0:
		return 0.0

	var capacity: float = maxf(_FLYWHEEL_CAPACITY, 0.001)
	var discharge_rate: float = maxf(_FLYWHEEL_DISCHARGE_RATE, 0.0)
	var available: float = minf(_flywheel_energy, capacity * discharge_rate * tick_delta)
	var drawn: float = minf(available, deficit)
	_flywheel_energy = maxf(_flywheel_energy - drawn, 0.0)
	return drawn


## Absorbs part of available surplus into flywheel energy storage.
func absorb_surplus(surplus: float, tick_delta: float) -> void:
	if not _is_flywheel_component:
		return
	if surplus <= 0.0 or tick_delta <= 0.0:
		return

	var capacity: float = maxf(_FLYWHEEL_CAPACITY, 0.001)
	var charge_rate: float = maxf(_FLYWHEEL_CHARGE_RATE, 0.0)
	var absorbed: float = surplus * charge_rate * tick_delta
	_flywheel_energy = minf(_flywheel_energy + absorbed, capacity)


func get_charge_ratio() -> float:
	if not _is_flywheel_component:
		return 0.0
	var capacity: float = maxf(_FLYWHEEL_CAPACITY, 0.001)
	return clampf(_flywheel_energy / capacity, 0.0, 1.0)

func _process(delta: float) -> void:
	var target_velocity := _direct_target_velocity if _use_direct_drive else torque * TORQUE_TO_SPEED
	var has_drive_target: bool = absf(target_velocity) > 0.001
	if has_drive_target:
		_flywheel_last_sign = signf(target_velocity)
		if _flywheel_last_sign == 0.0:
			_flywheel_last_sign = 1.0

	if _is_flywheel_component and has_drive_target:
		var tracked_peak: float = maxf(_flywheel_peak_speed, absf(target_velocity))
		_flywheel_peak_speed = lerpf(_flywheel_peak_speed, tracked_peak, min(delta * FLYWHEEL_PEAK_TRACKING, 1.0))
		absorb_surplus(absf(target_velocity) * FLYWHEEL_SPEED_TO_ENERGY, delta)
	elif _is_flywheel_component:
		var capacity: float = maxf(_FLYWHEEL_CAPACITY, 0.001)
		var discharge_rate: float = maxf(_FLYWHEEL_DISCHARGE_RATE, 0.0)
		_flywheel_energy = maxf(_flywheel_energy - (capacity * discharge_rate * delta), 0.0)
		var retained_speed: float = _flywheel_last_sign * (_flywheel_peak_speed * get_charge_ratio())
		target_velocity = retained_speed
	# Jam, stall, or direction conflict are hard-stop states for readability.
	if _condition_state == ConditionState.JAMMED or _is_stalled or _has_direction_conflict:
		target_velocity = 0.0
		angular_velocity = 0.0
		if _is_flywheel_component:
			_flywheel_energy = 0.0
			_flywheel_peak_speed = 0.0
	else:
		angular_velocity = lerpf(angular_velocity, target_velocity, min(delta * SMOOTHING, 1.0))

	if not Engine.is_editor_hint() and not _presentation_visible:
		if _is_shaft_component or _is_shell_component:
			rotation = _base_rotation
		return

	if _visual and _visual.has_method("set_visual_spin_speed"):
		_visual.call("set_visual_spin_speed", angular_velocity)
	if _is_shaft_component or _is_shell_component:
		rotation = _base_rotation
		if _visual and _visual.has_method("set_shaft_spin_speed"):
			_visual.call("set_shaft_spin_speed", angular_velocity)
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
