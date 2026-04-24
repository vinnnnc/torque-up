extends Node2D
class_name AnchorRotor

const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")

@export var always_active: bool = false
@export var rated_torque_output: float = PROJECT_PATHS_SCRIPT.BASE_POWER_NODE_OUTPUT
@export var stall_torque_output: float = PROJECT_PATHS_SCRIPT.POWER_NODE_STALL_TORQUE_BALANCED
@export var no_load_rpm: float = PROJECT_PATHS_SCRIPT.POWER_NODE_NO_LOAD_RPM
@export var brake_torque_cap: float = PROJECT_PATHS_SCRIPT.POWER_NODE_BRAKE_TORQUE_CAP_BALANCED
@export var source_outer_radius: float = PROJECT_PATHS_SCRIPT.POWER_NODE_RADIUS_BALANCED
@export var min_output_ratio: float = 0.7
@export var output_droop_strength: float = 0.45
@export var near_limit_ratio: float = PROJECT_PATHS_SCRIPT.POWER_NODE_NEAR_LIMIT_RATIO
@export var base_spin_speed: float = 1.2
@export var torque_spin_factor: float = 0.02
@export var inactive_spin_multiplier: float = 0.0
@export var underpowered_tint: Color = Color(1.0, 0.58, 0.58, 1.0)
@export var connected_tint: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var disconnected_tint: Color = Color(0.72, 0.72, 0.78, 1.0)
@export var engine_route_tint: Color = Color(0.82, 0.94, 1.0, 1.0)
@export var conflict_tint: Color = Color(1.0, 0.18, 0.18, 1.0)
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
var _last_source_rpm: float = 0.0
var _last_source_torque: float = 0.0
var _source_status: String = "in_band"
var _presentation_visible: bool = true
var _is_direction_conflict: bool = false

const SPIN_SMOOTHING: float = 6.0

func _ready() -> void:
	_apply_power_node_torque_profile()
	_apply_engine_presentation_tunables()
	_base_position = position
	_jitter_phase = randf() * TAU
	_ensure_visibility_notifier()


func _ensure_visibility_notifier() -> void:
	if Engine.is_editor_hint():
		return
	var notifier := get_node_or_null("PresentationVisibility") as VisibleOnScreenNotifier2D
	if notifier == null:
		notifier = VisibleOnScreenNotifier2D.new()
		notifier.name = "PresentationVisibility"
		add_child(notifier)
	var bounds_radius := maxf(source_outer_radius + 32.0, 48.0)
	var visual_node := get_node_or_null("Visual")
	if visual_node != null:
		var visual_outer_radius: Variant = visual_node.get("outer_radius")
		if visual_outer_radius != null:
			bounds_radius = maxf(bounds_radius, float(visual_outer_radius) + 32.0)
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


func set_direction_conflict(state: bool) -> void:
	_is_direction_conflict = state


func get_power_output(load_ratio: float = 0.0) -> float:
	var source_rpm := _to_rpm(_angular_velocity)
	return get_source_torque_at_speed_rpm(source_rpm, load_ratio)


func get_source_torque_at_speed_rpm(source_rpm: float, _load_ratio: float = 0.0) -> float:
	_last_source_rpm = maxf(source_rpm, 0.0)
	var torque_value := maxf(rated_torque_output, 0.0)
	_last_source_torque = torque_value
	_update_source_status()
	return torque_value


func get_source_status() -> String:
	return _source_status


func is_source_braking() -> bool:
	return _source_status == "braking"


func get_source_no_load_rpm() -> float:
	return no_load_rpm


func get_source_last_rpm() -> float:
	return _last_source_rpm


func get_source_torque_estimate() -> float:
	return _last_source_torque


func get_angular_velocity() -> float:
	return _angular_velocity

func _process(delta: float) -> void:
	if not _is_underpowered and not _is_connected_to_network and not _is_on_engine_route and not always_active:
		if absf(_angular_velocity) <= 0.0005 and absf(_direct_drive_speed) <= 0.0005 and _network_torque <= 0.001:
			return

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
	if not Engine.is_editor_hint() and not _presentation_visible:
		return
	rotation += _angular_velocity * delta

	var target_tint := underpowered_tint
	if not _is_underpowered:
		target_tint = connected_tint if _is_connected_to_network else disconnected_tint
		if _is_on_engine_route:
			target_tint = target_tint.lerp(engine_route_tint, 0.45)
	if _is_direction_conflict:
		target_tint = conflict_tint
	modulate = modulate.lerp(target_tint, min(delta * tint_smoothing, 1.0))

	if _is_underpowered:
		var t := (float(Time.get_ticks_msec()) * 0.001 * jitter_speed) + _jitter_phase
		var jitter_offset := Vector2(sin(t), cos(t * 1.37)) * jitter_amount
		position = _base_position + jitter_offset
	else:
		position = position.lerp(_base_position, min(delta * 12.0, 1.0))


func _update_source_status() -> void:
	if _last_source_torque < -0.001:
		_source_status = "braking"
		return

	var safe_no_load := maxf(no_load_rpm, 1.0)
	if _last_source_rpm >= (safe_no_load * near_limit_ratio):
		_source_status = "near_limit"
		return

	_source_status = "in_band"


func _to_rpm(angular_speed: float) -> float:
	return absf(angular_speed) * (60.0 / TAU)


func _apply_engine_presentation_tunables() -> void:
	if name != "CentralEngine":
		return

	z_as_relative = false
	z_index = PROJECT_PATHS_SCRIPT.ENGINE_FOREGROUND_Z_INDEX

	var visual := get_node_or_null("Visual")
	if visual == null:
		return
	visual.z_as_relative = false
	visual.z_index = PROJECT_PATHS_SCRIPT.ENGINE_FOREGROUND_Z_INDEX
	_ensure_engine_art_node()

	var configured_outer: Variant = visual.get("outer_radius")
	var outer_radius := maxf(PROJECT_PATHS_SCRIPT.ENGINE_VISUAL_OUTER_RADIUS, 8.0)
	if configured_outer != null and float(configured_outer) > 0.0:
		outer_radius = maxf(float(configured_outer), 8.0)
	var inner_radius := maxf(outer_radius * PROJECT_PATHS_SCRIPT.ENGINE_VISUAL_INNER_RADIUS_RATIO, 2.0)
	var hub_radius := maxf(outer_radius * PROJECT_PATHS_SCRIPT.ENGINE_VISUAL_HUB_RADIUS_RATIO, 2.0)
	var auto_tooth_count := PROJECT_PATHS_SCRIPT.compute_tooth_count_from_outer_radius(outer_radius)

	visual.set("outer_radius", outer_radius)
	visual.set("inner_radius", inner_radius)
	visual.set("hub_radius", hub_radius)
	visual.set("tooth_depth", PROJECT_PATHS_SCRIPT.ENGINE_VISUAL_TOOTH_DEPTH)
	visual.set("tooth_count", auto_tooth_count)
	visual.set("engine_shell_mode", false)

	if visual.has_method("queue_redraw"):
		visual.call("queue_redraw")


func _apply_power_node_torque_profile() -> void:
	if name == "CentralEngine":
		return
	var rated := PROJECT_PATHS_SCRIPT.get_power_node_torque_from_radius(source_outer_radius)
	rated_torque_output = rated
	stall_torque_output = rated * PROJECT_PATHS_SCRIPT.POWER_NODE_STALL_RATIO
	brake_torque_cap = rated * PROJECT_PATHS_SCRIPT.POWER_NODE_BRAKE_CAP_RATIO


func _ensure_engine_art_node() -> void:
	var art_node := get_node_or_null("Art") as Sprite2D
	if art_node == null:
		art_node = Sprite2D.new()
		art_node.name = "Art"
		add_child(art_node)

	art_node.centered = true
	art_node.z_as_relative = false
	art_node.z_index = PROJECT_PATHS_SCRIPT.ENGINE_FOREGROUND_Z_INDEX + 1
