extends Node

const MUSIC_LOOP_STREAM = preload("res://assets/sounds/loop.mp3")
const GEAR_PLACE_STREAM = preload("res://assets/sounds/gear_place.mp3")
const MENU_CLICK_STREAM = preload("res://assets/sounds/menu.mp3")
const WIN_STREAM = preload("res://assets/sounds/game_win.mp3")
const ERROR_STREAM = preload("res://assets/sounds/error.mp3")
const GENERATOR_STREAM = preload("res://assets/sounds/generator.mp3")

const GENERATOR_ACTIVE_HP_THRESHOLD := 0.01
const GENERATOR_ACTIVE_DB := -9.0
const GENERATOR_SILENT_DB := -72.0
const GENERATOR_FADE_DB_PER_SEC := 28.0

var _rng := RandomNumberGenerator.new()
var _music_player: AudioStreamPlayer = null
var _generator_player: AudioStreamPlayer = null
var _sfx_root: Node = null
var _music_enabled: bool = true
var _sfx_enabled: bool = true
@onready var _signal_bus: Node = get_node_or_null("/root/SignalBus")
@onready var _game_state: Node = get_node_or_null("/root/GameState")

var _generator_should_play: bool = false


func _ready() -> void:
	_rng.randomize()
	_setup_players()
	_connect_signals()
	start_music_loop()



func _setup_players() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicLoopPlayer"
	_music_player.bus = "Master"
	_music_player.volume_db = -12.0
	_music_player.stream = MUSIC_LOOP_STREAM
	_music_player.finished.connect(_on_music_finished)
	add_child(_music_player)

	_generator_player = AudioStreamPlayer.new()
	_generator_player.name = "GeneratorLoopPlayer"
	_generator_player.bus = "Master"
	_generator_player.volume_db = GENERATOR_SILENT_DB
	_generator_player.stream = GENERATOR_STREAM
	_generator_player.finished.connect(_on_generator_finished)
	add_child(_generator_player)

	_sfx_root = Node.new()
	_sfx_root.name = "SfxPlayers"
	add_child(_sfx_root)


func _connect_signals() -> void:
	if _signal_bus != null and _signal_bus.has_signal("gear_placed"):
		if not _signal_bus.gear_placed.is_connected(_on_gear_placed):
			_signal_bus.gear_placed.connect(_on_gear_placed)
	if _signal_bus != null and _signal_bus.has_signal("placement_feedback"):
		if not _signal_bus.placement_feedback.is_connected(_on_placement_feedback):
			_signal_bus.placement_feedback.connect(_on_placement_feedback)
	if _game_state != null and _game_state.has_signal("state_changed"):
		if not _game_state.state_changed.is_connected(_on_game_state_changed):
			_game_state.state_changed.connect(_on_game_state_changed)


func _on_music_finished() -> void:
	if _music_player != null and _music_enabled:
		_music_player.play()


func _on_generator_finished() -> void:
	if _generator_player != null and _generator_should_play and _music_enabled:
		_generator_player.play()


func _on_gear_placed(_gear: Node2D) -> void:
	play_gear_place()


func _on_placement_feedback(message: String) -> void:
	if _is_error_feedback(message):
		play_error()


func _on_game_state_changed(horsepower: float, _available_torque: float, _efficiency: float, _total_score: float, _lifetime_hp: float, _reliability_multiplier: float) -> void:
	_generator_should_play = _music_enabled and horsepower > GENERATOR_ACTIVE_HP_THRESHOLD
	if _generator_should_play and _generator_player != null and not _generator_player.playing:
		_generator_player.volume_db = GENERATOR_SILENT_DB
		_generator_player.play()


func _is_error_feedback(message: String) -> bool:
	var m := message.to_lower()
	return m.contains("error") or m.contains("invalid") or m.contains("jam") or m.contains("block") or m.contains("conflict")


func start_music_loop() -> void:
	if _music_player == null:
		return
	if not _music_enabled:
		return
	if _music_player.playing:
		return
	_music_player.play()


func stop_music_loop() -> void:
	if _music_player == null:
		return
	_music_player.stop()
	if _generator_player != null:
		_generator_player.stop()
		_generator_player.volume_db = GENERATOR_SILENT_DB
	_generator_should_play = false


func play_menu_click() -> void:
	_play_sfx(MENU_CLICK_STREAM, -8.0, 1.0)


func play_win() -> void:
	_play_sfx(WIN_STREAM, -5.0, 1.0)


func play_error() -> void:
	_play_sfx(ERROR_STREAM, -5.5, 1.0)


func play_gear_place() -> void:
	var pitch := _rng.randf_range(0.94, 1.08)
	_play_sfx(GEAR_PLACE_STREAM, -6.5, pitch)


func play_gear_delete() -> void:
	var pitch := _rng.randf_range(0.82, 0.92)
	_play_sfx(GEAR_PLACE_STREAM, -7.0, pitch)


func is_music_enabled() -> bool:
	return _music_enabled


func is_sfx_enabled() -> bool:
	return _sfx_enabled


func toggle_music_enabled() -> bool:
	set_music_enabled(not _music_enabled)
	return _music_enabled


func toggle_sfx_enabled() -> bool:
	set_sfx_enabled(not _sfx_enabled)
	return _sfx_enabled


func set_music_enabled(enabled: bool) -> void:
	_music_enabled = enabled
	if _music_player == null:
		return
	if _music_enabled:
		if not _music_player.playing:
			_music_player.play()
		if _game_state != null:
			var hp := float(_game_state.get("horsepower"))
			_generator_should_play = hp > GENERATOR_ACTIVE_HP_THRESHOLD
			if _generator_should_play and _generator_player != null and not _generator_player.playing:
				_generator_player.volume_db = GENERATOR_SILENT_DB
				_generator_player.play()
	else:
		_music_player.stop()
		if _generator_player != null:
			_generator_player.stop()
			_generator_player.volume_db = GENERATOR_SILENT_DB
		_generator_should_play = false


func set_sfx_enabled(enabled: bool) -> void:
	_sfx_enabled = enabled


func _play_sfx(stream: AudioStream, volume_db: float, pitch_scale: float) -> void:
	if not _sfx_enabled:
		return
	if stream == null or _sfx_root == null:
		return
	var player := AudioStreamPlayer.new()
	player.bus = "Master"
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	_sfx_root.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _process(delta: float) -> void:
	if _generator_player == null:
		return

	var target_db := GENERATOR_ACTIVE_DB if _generator_should_play else GENERATOR_SILENT_DB
	_generator_player.volume_db = move_toward(_generator_player.volume_db, target_db, GENERATOR_FADE_DB_PER_SEC * delta)

	if not _generator_should_play and _generator_player.playing and _generator_player.volume_db <= GENERATOR_SILENT_DB + 0.1:
		_generator_player.stop()
