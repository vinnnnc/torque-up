extends CanvasLayer
class_name PerfOverlay

@export var visible_on_start: bool = false
@export var toggle_key: Key = KEY_F9
@export var update_interval_sec: float = 0.2

var _root_panel: PanelContainer = null
var _label: Label = null
var _time_accum: float = 0.0

@onready var _game_manager: Node = get_node_or_null("../GameManager")
@onready var _placement_controller: Node = get_node_or_null("../PlacementController")

func _ready() -> void:
	_build_ui()
	if _root_panel:
		_root_panel.visible = visible_on_start


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode != toggle_key:
		return
	if _root_panel:
		_root_panel.visible = not _root_panel.visible


func _process(delta: float) -> void:
	if _root_panel == null or not _root_panel.visible:
		return

	_time_accum += delta
	if _time_accum < update_interval_sec:
		return
	_time_accum = 0.0

	var gm_stats := _game_manager.call("get_perf_stats") as Dictionary if _game_manager and _game_manager.has_method("get_perf_stats") else {}
	var placement_stats := _placement_controller.call("get_perf_stats") as Dictionary if _placement_controller and _placement_controller.has_method("get_perf_stats") else {}
	
	var game_state := get_node_or_null("/root/GameState")
	var score_stats := {}
	if game_state:
		score_stats = {
			"total_score": game_state.total_score,
			"lifetime_hp": game_state.lifetime_hp,
			"reliability_multiplier": game_state.reliability_multiplier,
			"total_jams": game_state.total_jams
		}
	
	_update_text(gm_stats, placement_stats, score_stats)


func _build_ui() -> void:
	_root_panel = PanelContainer.new()
	_root_panel.anchor_left = 0.0
	_root_panel.anchor_top = 0.0
	_root_panel.anchor_right = 0.0
	_root_panel.anchor_bottom = 0.0
	_root_panel.offset_left = 12.0
	_root_panel.offset_top = 12.0
	_root_panel.offset_right = 344.0
	_root_panel.offset_bottom = 212.0
	add_child(_root_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_root_panel.add_child(margin)

	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_label.text = "perf overlay"
	margin.add_child(_label)


func _update_text(gm_stats: Dictionary, placement_stats: Dictionary, score_stats: Dictionary = {}) -> void:
	if _label == null:
		return

	var fps := Engine.get_frames_per_second()
	var last_ms := float(gm_stats.get("last_recalc_ms", 0.0))
	var avg_ms := float(gm_stats.get("avg_recalc_ms", 0.0))
	var peak_ms := float(gm_stats.get("peak_recalc_ms", 0.0))
	var solver_mode := str(gm_stats.get("solver_mode", "unknown"))
	var dirty := bool(gm_stats.get("network_dirty", false))
	var dirty_wait := float(gm_stats.get("dirty_wait_ms", 0.0))
	var tick_hz := float(gm_stats.get("sim_tick_hz", 0.0))
	var reachable := int(gm_stats.get("reachable_count", 0))
	var profiles := int(gm_stats.get("profile_count", 0))
	var underpowered := bool(gm_stats.get("underpowered", false))
	var components := int(gm_stats.get("component_count", 0))
	var threaded_enabled := bool(gm_stats.get("threaded_solver_enabled", false))
	var threaded_running := bool(gm_stats.get("threaded_solver_running", false))
	var threaded_eligible := bool(gm_stats.get("threaded_solver_eligible", false))
	var threaded_threshold := int(gm_stats.get("threaded_solver_threshold", 0))

	var thread_req_ms := float(gm_stats.get("thread_request_ms", 0.0))
	var thread_work_ms := float(gm_stats.get("thread_worker_ms", 0.0))
	var thread_apply_ms := float(gm_stats.get("thread_apply_ms", 0.0))

	var selected := str(placement_stats.get("selected_component", ""))
	var placement_dirty := bool(placement_stats.get("context_dirty", false))
	var marker_count := int(placement_stats.get("socket_markers", 0))
	var has_socket := bool(placement_stats.get("has_active_socket", false))
	
	var total_score := float(score_stats.get("total_score", 0.0))
	var reliability := float(score_stats.get("reliability_multiplier", 1.0))
	var total_jams := int(score_stats.get("total_jams", 0))
	var kilowatts := float(gm_stats.get("kilowatts", 0.0))
	var generator_output_rpm := float(gm_stats.get("generator_output_rpm", 0.0))
	var generator_internal_rpm := float(gm_stats.get("generator_internal_rpm", 0.0))
	var generator_load_torque := float(gm_stats.get("generator_load_torque", 0.0))
	var generator_ramp := float(gm_stats.get("generator_ramp_factor", 0.0))

	_label.text = "Perf Overlay (F9)\n" \
		+ "FPS: %d\n" % fps \
		+ "Recalc ms  last/avg/peak: %.2f / %.2f / %.2f\n" % [last_ms, avg_ms, peak_ms] \
		+ "Solver: %s  enabled: %s  eligible: %s  running: %s  threshold: %d\n" % [solver_mode, str(threaded_enabled), str(threaded_eligible), str(threaded_running), threaded_threshold] \
		+ "Thread req/work/apply ms: %.1f / %.1f / %.1f\n" % [thread_req_ms, thread_work_ms, thread_apply_ms] \
		+ "Network tick Hz: %.1f  dirty: %s  wait: %.1fms\n" % [tick_hz, str(dirty), dirty_wait] \
		+ "Reachable: %d  profiles: %d  components: %d\n" % [reachable, profiles, components] \
		+ "Underpowered: %s\n" % str(underpowered) \
		+ "Generator: %.1f kW  Energy Delivered: %.1f kJ  Reliability: %.0f%%  Jams: %d\n" % [kilowatts, total_score, reliability * 100.0, total_jams] \
		+ "Generator RPM out/int: %.2f / %.0f  Load: %.1f Nm  Ramp: %.0f%%\n" % [generator_output_rpm, generator_internal_rpm, generator_load_torque, generator_ramp * 100.0] \
		+ "Placement selected: %s\n" % selected \
		+ "Placement dirty: %s  markers: %d  active_socket: %s" % [str(placement_dirty), marker_count, str(has_socket)]
