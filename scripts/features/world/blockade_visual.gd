extends Node2D
## World-space blockade + torque frontier progression.
## Playable space is an upward cone sector rooted at the engine.

const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")
const FRONTIER_GEOMETRY_SCRIPT = preload("res://scripts/features/world/frontier_geometry.gd")

@export var blockade_color: Color = Color(0.0, 0.0, 0.0, 0.85)
@export var fog_color: Color = Color(0.0, 0.0, 0.0, 0.28)
@export var ring_color: Color = Color(0.72, 0.84, 1.0, 0.72)
@export var world_half_width: float = PROJECT_PATHS_SCRIPT.WORLD_HALF_WIDTH
@export var world_height: float = PROJECT_PATHS_SCRIPT.WORLD_VERTICAL_EXTENT

@export var base_radius: float = PROJECT_PATHS_SCRIPT.FRONTIER_BASE_RADIUS
@export var alpha: float = PROJECT_PATHS_SCRIPT.FRONTIER_SMOOTHING_ALPHA
@export var radius_scale_k: float = PROJECT_PATHS_SCRIPT.FRONTIER_RADIUS_SCALE_K
@export var min_expansion_step: float = PROJECT_PATHS_SCRIPT.FRONTIER_MIN_EXPANSION_STEP
@export var max_radius_clamp: float = PROJECT_PATHS_SCRIPT.FRONTIER_MAX_RADIUS_CLAMP
@export var cone_half_angle_degrees: float = PROJECT_PATHS_SCRIPT.FRONTIER_CONE_HALF_ANGLE_DEGREES
@export var cone_apex_y_offset: float = PROJECT_PATHS_SCRIPT.FRONTIER_CONE_APEX_Y_OFFSET
@export var visual_radius_smoothing: float = PROJECT_PATHS_SCRIPT.FRONTIER_VISUAL_RADIUS_SMOOTHING
@export var fog_feather_width: float = PROJECT_PATHS_SCRIPT.FRONTIER_FOG_FEATHER_WIDTH
@export var fog_feather_steps: int = PROJECT_PATHS_SCRIPT.FRONTIER_FOG_FEATHER_STEPS
@export var require_rpm_ramp: bool = PROJECT_PATHS_SCRIPT.FRONTIER_REQUIRE_RPM_RAMP
@export var rpm_gate_soft_min: float = PROJECT_PATHS_SCRIPT.FRONTIER_RPM_GATE_SOFT_MIN
@export var rpm_gate_full: float = PROJECT_PATHS_SCRIPT.FRONTIER_RPM_GATE_FULL
@export var rpm_gate_min_factor: float = 0.1

@export var live_tuning_enabled: bool = false
@export var live_tuning_poll_interval: float = 0.25
@export var live_tuning_cfg_path: String = "user://frontier_tuning.cfg"

var _center: Vector2 = Vector2(PROJECT_PATHS_SCRIPT.VIEWPORT_CENTER_X, PROJECT_PATHS_SCRIPT.ENGINE_WORLD_Y)
var _cone_apex: Vector2 = Vector2(PROJECT_PATHS_SCRIPT.VIEWPORT_CENTER_X, PROJECT_PATHS_SCRIPT.ENGINE_WORLD_Y)
var _smoothed_torque: float = 0.0
var _unlocked_radius: float = PROJECT_PATHS_SCRIPT.FRONTIER_BASE_RADIUS
var _visual_unlocked_radius: float = PROJECT_PATHS_SCRIPT.FRONTIER_BASE_RADIUS
var _live_tuning_poll_accum: float = 0.0
var _live_tuning_last_modified_time: int = -1

@onready var _engine: Node2D = get_node_or_null("../Network/CentralEngine")
@onready var _game_state: Node = get_node_or_null("/root/GameState")


func _ready() -> void:
	z_as_relative = false
	z_index = PROJECT_PATHS_SCRIPT.WORLD_BLOCKADE_Z_INDEX
	if _engine != null:
		_center = Vector2(_engine.global_position.x, PROJECT_PATHS_SCRIPT.ENGINE_WORLD_Y)
	else:
		_center = Vector2(PROJECT_PATHS_SCRIPT.VIEWPORT_CENTER_X, PROJECT_PATHS_SCRIPT.ENGINE_WORLD_Y)
	_refresh_cone_apex()
	_setup_live_tuning()

	_unlocked_radius = _apply_frontier_cap(base_radius)
	_visual_unlocked_radius = _unlocked_radius

	if _game_state != null and _game_state.has_signal("state_changed"):
		if not _game_state.state_changed.is_connected(_on_state_changed):
			_game_state.state_changed.connect(_on_state_changed)
		_on_state_changed(_game_state.horsepower, _game_state.available_torque, _game_state.efficiency, _game_state.total_score, _game_state.lifetime_hp, _game_state.reliability_multiplier)

	queue_redraw()


func _process(delta: float) -> void:
	_poll_live_tuning(delta)
	var smoothing := maxf(visual_radius_smoothing, 0.1)
	var next_visual := lerpf(_visual_unlocked_radius, _unlocked_radius, min(delta * smoothing, 1.0))
	if absf(next_visual - _visual_unlocked_radius) > 0.01:
		_visual_unlocked_radius = next_visual
		queue_redraw()


func _on_state_changed(horsepower: float, available_torque: float, _efficiency: float, _total_score: float, _lifetime_hp: float, _reliability_multiplier: float) -> void:
	var delivered_torque := maxf(0.0, available_torque)
	if PROJECT_PATHS_SCRIPT.ENGINE_MECHANICAL_COUPLED_MODE:
		delivered_torque = (
			delivered_torque * PROJECT_PATHS_SCRIPT.FRONTIER_COUPLED_TORQUE_MULTIPLIER
		) + (
			maxf(0.0, horsepower) * PROJECT_PATHS_SCRIPT.FRONTIER_COUPLED_HP_TO_TORQUE
		)
	if require_rpm_ramp and _game_state != null:
		var current_rpm : Variant = _game_state.rpm
		delivered_torque *= _compute_rpm_gate_factor(current_rpm)
	_smoothed_torque = (alpha * delivered_torque) + ((1.0 - alpha) * _smoothed_torque)

	var candidate_radius := base_radius + (radius_scale_k * sqrt(_smoothed_torque))
	candidate_radius = _apply_frontier_cap(candidate_radius)
	if candidate_radius >= (_unlocked_radius + min_expansion_step):
		_unlocked_radius = candidate_radius

	queue_redraw()


func get_unlocked_radius() -> float:
	return _unlocked_radius


func get_visual_unlocked_radius() -> float:
	return _visual_unlocked_radius


func reset_frontier() -> void:
	_smoothed_torque = 0.0
	_unlocked_radius = _apply_frontier_cap(base_radius)
	_visual_unlocked_radius = _unlocked_radius
	queue_redraw()


func _apply_frontier_cap(radius_value: float) -> float:
	if max_radius_clamp <= 0.0:
		return maxf(radius_value, base_radius)
	return minf(max_radius_clamp, maxf(radius_value, base_radius))


func _compute_rpm_gate_factor(rpm: float) -> float:
	var soft_min := rpm_gate_soft_min
	var full_rpm := maxf(rpm_gate_full, soft_min + 0.001)
	var t := clampf(inverse_lerp(soft_min, full_rpm, maxf(rpm, 0.0)), 0.0, 1.0)
	# Smoothstep easing: near-idle contributes very little, progression ramps up as RPM rises.
	t = t * t * (3.0 - (2.0 * t))
	var floor_factor := clampf(rpm_gate_min_factor, 0.0, 1.0)
	return lerpf(floor_factor, 1.0, t)


func get_smoothed_torque() -> float:
	return _smoothed_torque


func get_cone_half_angle_radians() -> float:
	return deg_to_rad(clampf(cone_half_angle_degrees, 1.0, 89.0))


func get_cone_apex_world() -> Vector2:
	return _cone_apex


func _refresh_cone_apex() -> void:
	_cone_apex = _center + Vector2(0.0, cone_apex_y_offset)


func _setup_live_tuning() -> void:
	if not live_tuning_enabled:
		return

	if not FileAccess.file_exists(live_tuning_cfg_path):
		_write_live_tuning_config_defaults()

	if FileAccess.file_exists(live_tuning_cfg_path):
		_live_tuning_last_modified_time = int(FileAccess.get_modified_time(live_tuning_cfg_path))
		_load_live_tuning_config(false)


func _poll_live_tuning(delta: float) -> void:
	if not live_tuning_enabled:
		return

	_live_tuning_poll_accum += delta
	if _live_tuning_poll_accum < maxf(live_tuning_poll_interval, 0.05):
		return
	_live_tuning_poll_accum = 0.0

	if not FileAccess.file_exists(live_tuning_cfg_path):
		return

	var modified_time := int(FileAccess.get_modified_time(live_tuning_cfg_path))
	if modified_time <= 0 or modified_time == _live_tuning_last_modified_time:
		return

	_live_tuning_last_modified_time = modified_time
	_load_live_tuning_config(true)


func _write_live_tuning_config_defaults() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("frontier", "base_radius", base_radius)
	cfg.set_value("frontier", "alpha", alpha)
	cfg.set_value("frontier", "radius_scale_k", radius_scale_k)
	cfg.set_value("frontier", "min_expansion_step", min_expansion_step)
	cfg.set_value("frontier", "max_radius_clamp", max_radius_clamp)
	cfg.set_value("frontier", "cone_half_angle_degrees", cone_half_angle_degrees)
	cfg.set_value("frontier", "cone_apex_y_offset", cone_apex_y_offset)
	cfg.set_value("frontier", "visual_radius_smoothing", visual_radius_smoothing)
	cfg.set_value("frontier", "fog_feather_width", fog_feather_width)
	cfg.set_value("frontier", "fog_feather_steps", fog_feather_steps)
	cfg.set_value("frontier", "require_rpm_ramp", require_rpm_ramp)
	cfg.set_value("frontier", "rpm_gate_soft_min", rpm_gate_soft_min)
	cfg.set_value("frontier", "rpm_gate_full", rpm_gate_full)
	cfg.set_value("frontier", "rpm_gate_min_factor", rpm_gate_min_factor)
	var save_err := cfg.save(live_tuning_cfg_path)
	if save_err != OK:
		push_warning("Blockade: failed to write live tuning defaults (%s)" % [save_err])


func _load_live_tuning_config(log_reload: bool) -> void:
	var cfg := ConfigFile.new()
	var load_err := cfg.load(live_tuning_cfg_path)
	if load_err != OK:
		push_warning("Blockade: failed to load live tuning cfg (%s)" % [load_err])
		return

	base_radius = maxf(_cfg_float(cfg, "frontier", "base_radius", base_radius), 1.0)
	alpha = clampf(_cfg_float(cfg, "frontier", "alpha", alpha), 0.0, 1.0)
	radius_scale_k = maxf(_cfg_float(cfg, "frontier", "radius_scale_k", radius_scale_k), 0.0)
	min_expansion_step = maxf(_cfg_float(cfg, "frontier", "min_expansion_step", min_expansion_step), 0.0)
	max_radius_clamp = _cfg_float(cfg, "frontier", "max_radius_clamp", max_radius_clamp)
	cone_half_angle_degrees = clampf(_cfg_float(cfg, "frontier", "cone_half_angle_degrees", cone_half_angle_degrees), 1.0, 89.0)
	cone_apex_y_offset = _cfg_float(cfg, "frontier", "cone_apex_y_offset", cone_apex_y_offset)
	visual_radius_smoothing = maxf(_cfg_float(cfg, "frontier", "visual_radius_smoothing", visual_radius_smoothing), 0.1)
	fog_feather_width = maxf(_cfg_float(cfg, "frontier", "fog_feather_width", fog_feather_width), 1.0)
	fog_feather_steps = maxi(_cfg_int(cfg, "frontier", "fog_feather_steps", fog_feather_steps), 1)
	require_rpm_ramp = _cfg_bool(cfg, "frontier", "require_rpm_ramp", require_rpm_ramp)
	rpm_gate_soft_min = maxf(_cfg_float(cfg, "frontier", "rpm_gate_soft_min", rpm_gate_soft_min), 0.0)
	rpm_gate_full = maxf(_cfg_float(cfg, "frontier", "rpm_gate_full", rpm_gate_full), rpm_gate_soft_min + 0.001)
	rpm_gate_min_factor = clampf(_cfg_float(cfg, "frontier", "rpm_gate_min_factor", rpm_gate_min_factor), 0.0, 1.0)

	_refresh_cone_apex()
	_unlocked_radius = _apply_frontier_cap(_unlocked_radius)
	_visual_unlocked_radius = _apply_frontier_cap(_visual_unlocked_radius)
	queue_redraw()

	if log_reload:
		print("Blockade: reloaded live frontier tuning from %s" % [live_tuning_cfg_path])


func _cfg_float(cfg: ConfigFile, section: String, key: String, fallback: float) -> float:
	var value: Variant = cfg.get_value(section, key, fallback)
	return float(value)


func _cfg_int(cfg: ConfigFile, section: String, key: String, fallback: int) -> int:
	var value: Variant = cfg.get_value(section, key, fallback)
	return int(value)


func _cfg_bool(cfg: ConfigFile, section: String, key: String, fallback: bool) -> bool:
	var value: Variant = cfg.get_value(section, key, fallback)
	return bool(value)


func is_position_unlocked(world_pos: Vector2, clearance_radius: float = 0.0) -> bool:
	if not is_position_inside_cone(world_pos, clearance_radius):
		return false

	var distance := _cone_apex.distance_to(world_pos)
	return distance <= maxf(0.0, _unlocked_radius - clearance_radius)


func is_position_inside_cone(world_pos: Vector2, clearance_radius: float = 0.0) -> bool:
	var dy := _cone_apex.y - world_pos.y
	if dy <= clearance_radius:
		return false

	var half_angle := get_cone_half_angle_radians()
	var max_horizontal := maxf(0.0, (dy - clearance_radius) * tan(half_angle))
	return absf(world_pos.x - _cone_apex.x) <= max_horizontal


func constrain_world_position(world_pos: Vector2, clearance_radius: float = 0.0, use_unlocked_radius: bool = false) -> Vector2:
	var constrained := world_pos

	var max_y := _cone_apex.y - clearance_radius
	constrained.y = minf(constrained.y, max_y)

	var dy := _cone_apex.y - constrained.y
	var half_angle := get_cone_half_angle_radians()
	var max_horizontal := maxf(0.0, (dy - clearance_radius) * tan(half_angle))
	constrained.x = clampf(constrained.x, _cone_apex.x - max_horizontal, _cone_apex.x + max_horizontal)

	if use_unlocked_radius:
		var max_radius := maxf(0.0, _unlocked_radius - clearance_radius)
		var offset := constrained - _cone_apex
		if offset.length() > max_radius and max_radius > 0.0:
			constrained = _cone_apex + (offset.normalized() * max_radius)

	return constrained


func _draw() -> void:
	# Solid blockade covers the entire world outside the upward cone (all unplayable area).
	var half_angle := get_cone_half_angle_radians()
	var blockade_pts := FRONTIER_GEOMETRY_SCRIPT.build_full_outside_polygon(
		_cone_apex, half_angle,
		-world_half_width, world_half_width,
		_center.y - world_height, _center.y + world_height
	)
	draw_colored_polygon(blockade_pts, blockade_color)

	# Fog outside the frontier cone-sector in upper world.
	# Built as a single concave polygon: full upper-world rectangle with a
	# cone-sector bite taken from the lower-center.
	var fog_pts := FRONTIER_GEOMETRY_SCRIPT.build_upper_outside_polygon(
		_cone_apex,
		_visual_unlocked_radius,
		half_angle,
		world_half_width,
		_center.y - world_height,
		_center.y,
		72
	)

	draw_colored_polygon(fog_pts, fog_color)
	_draw_fog_feather(half_angle)

	# Frontier ring outline (cone sector arc + side rays).
	var up_angle := -PI * 0.5
	var right_angle := up_angle + half_angle
	var left_angle := up_angle - half_angle
	draw_arc(_cone_apex, _visual_unlocked_radius, left_angle, right_angle, 72, ring_color, 2.0, true)
	var left_edge := _cone_apex + (Vector2.RIGHT.rotated(left_angle) * _visual_unlocked_radius)
	var right_edge := _cone_apex + (Vector2.RIGHT.rotated(right_angle) * _visual_unlocked_radius)
	draw_line(_cone_apex, left_edge, ring_color, 2.0, true)
	draw_line(_cone_apex, right_edge, ring_color, 2.0, true)


func _draw_fog_feather(half_angle: float) -> void:
	var feather_steps := maxi(fog_feather_steps, 1)
	var feather_width := maxf(fog_feather_width, 1.0)
	var step_width := feather_width / float(feather_steps)
	var up_angle := -PI * 0.5
	var right_angle := up_angle + half_angle
	var left_angle := up_angle - half_angle
	for step in range(feather_steps):
		var radius := maxf(0.0, _visual_unlocked_radius - (float(step) * step_width))
		var t := float(step + 1) / float(feather_steps + 1)
		var alpha := fog_color.a * (1.0 - t) * 0.75
		var color := Color(fog_color.r, fog_color.g, fog_color.b, alpha)
		draw_arc(_cone_apex, radius, left_angle, right_angle, 72, color, step_width + 1.0, true)
