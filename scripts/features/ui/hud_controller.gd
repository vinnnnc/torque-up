extends CanvasLayer

const PROJECT_PATHS_SCRIPT = preload("res://scripts/core/project_paths.gd")

@onready var _horsepower_value: Label = $PanelContainer/MarginContainer/Stats/HorsepowerRow/Value
@onready var _torque_value: Label = $PanelContainer/MarginContainer/Stats/TorqueRow/Value
@onready var _efficiency_value: Label = $PanelContainer/MarginContainer/Stats/EfficiencyRow/Value
@onready var _rpm_value: Label = $PanelContainer/MarginContainer/Stats/RpmRow/Value
@onready var _none_button: Button = $HotbarPanel/MarginContainer/Hotbar/NoneButton
@onready var _small_gear_button: Button = $HotbarPanel/MarginContainer/Hotbar/SmallGearButton
@onready var _medium_gear_button: Button = $HotbarPanel/MarginContainer/Hotbar/MediumGearButton
@onready var _large_gear_button: Button = $HotbarPanel/MarginContainer/Hotbar/LargeGearButton
@onready var _shaft_button: Button = $HotbarPanel/MarginContainer/Hotbar/ShaftButton
@onready var _chain_button: Button = $HotbarPanel/MarginContainer/Hotbar/BeltButton
@onready var _delete_button: Button = $HotbarPanel/MarginContainer/Hotbar/DeleteButton
@onready var _flywheel_button: Button = $HotbarPanel/MarginContainer/Hotbar/FlywheelButton
@onready var _clutch_button: Button = $HotbarPanel/MarginContainer/Hotbar/ClutchButton
@onready var _differential_button: Button = $HotbarPanel/MarginContainer/Hotbar/DifferentialButton

const COMPONENT_NONE := PROJECT_PATHS_SCRIPT.COMPONENT_NONE
const COMPONENT_GEAR_SMALL := PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_SMALL
const COMPONENT_GEAR_MEDIUM := PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_MEDIUM
const COMPONENT_GEAR_LARGE := PROJECT_PATHS_SCRIPT.COMPONENT_GEAR_LARGE
const COMPONENT_SHAFT := PROJECT_PATHS_SCRIPT.COMPONENT_SHAFT
const COMPONENT_DELETE := PROJECT_PATHS_SCRIPT.COMPONENT_DELETE
const COMPONENT_CHAIN := PROJECT_PATHS_SCRIPT.COMPONENT_CHAIN
const COMPONENT_FLYWHEEL := PROJECT_PATHS_SCRIPT.COMPONENT_FLYWHEEL
const COMPONENT_CLUTCH := PROJECT_PATHS_SCRIPT.COMPONENT_CLUTCH
const COMPONENT_DIFFERENTIAL := PROJECT_PATHS_SCRIPT.COMPONENT_DIFFERENTIAL

var _selected_component: String = COMPONENT_NONE

func _ready() -> void:
	var game_state := get_node_or_null("/root/GameState")
	if game_state:
		if not game_state.state_changed.is_connected(_on_state_changed):
			game_state.state_changed.connect(_on_state_changed)
		_on_state_changed(game_state.horsepower, game_state.available_torque, game_state.efficiency, game_state.rpm)

	_none_button.pressed.connect(_on_none_button_pressed)
	_small_gear_button.pressed.connect(_on_small_gear_button_pressed)
	_medium_gear_button.pressed.connect(_on_medium_gear_button_pressed)
	_large_gear_button.pressed.connect(_on_large_gear_button_pressed)
	_shaft_button.pressed.connect(_on_shaft_button_pressed)
	if _chain_button:
		_chain_button.pressed.connect(_on_chain_button_pressed)
	_delete_button.pressed.connect(_on_delete_button_pressed)
	if _flywheel_button:
		_flywheel_button.pressed.connect(_on_flywheel_button_pressed)
	if _clutch_button:
		_clutch_button.pressed.connect(_on_clutch_button_pressed)
	if _differential_button:
		_differential_button.pressed.connect(_on_differential_button_pressed)
	_select_component(COMPONENT_NONE)

func _on_state_changed(horsepower: float, available_torque: float, efficiency: float, rpm: float) -> void:
	_horsepower_value.text = "%.1f" % horsepower
	_torque_value.text = "%.1f" % available_torque
	_efficiency_value.text = "%.1f%%" % (efficiency * 100.0)
	_rpm_value.text = "%.0f" % rpm


func _on_none_button_pressed() -> void:
	_select_component(COMPONENT_NONE)


func _on_small_gear_button_pressed() -> void:
	_select_component(COMPONENT_GEAR_SMALL)


func _on_medium_gear_button_pressed() -> void:
	_select_component(COMPONENT_GEAR_MEDIUM)


func _on_large_gear_button_pressed() -> void:
	_select_component(COMPONENT_GEAR_LARGE)


func _on_shaft_button_pressed() -> void:
	_select_component(COMPONENT_SHAFT)


func _on_chain_button_pressed() -> void:
	print("CHAIN MODE ACTIVATED: Click to select first gear, then click to select second gear (max 480 units apart)")
	_select_component(COMPONENT_CHAIN)


func _on_delete_button_pressed() -> void:
	_select_component(COMPONENT_DELETE)


func _on_flywheel_button_pressed() -> void:
	_select_component(COMPONENT_FLYWHEEL)


func _on_clutch_button_pressed() -> void:
	_select_component(COMPONENT_CLUTCH)


func _on_differential_button_pressed() -> void:
	_select_component(COMPONENT_DIFFERENTIAL)



func _select_component(component_id: String) -> void:
	_selected_component = component_id
	_none_button.button_pressed = component_id == COMPONENT_NONE
	_small_gear_button.button_pressed = component_id == COMPONENT_GEAR_SMALL
	_medium_gear_button.button_pressed = component_id == COMPONENT_GEAR_MEDIUM
	_large_gear_button.button_pressed = component_id == COMPONENT_GEAR_LARGE
	_shaft_button.button_pressed = component_id == COMPONENT_SHAFT
	if _chain_button:
		_chain_button.button_pressed = component_id == COMPONENT_CHAIN
	_delete_button.button_pressed = component_id == COMPONENT_DELETE
	if _flywheel_button:
		_flywheel_button.button_pressed = component_id == COMPONENT_FLYWHEEL
	if _clutch_button:
		_clutch_button.button_pressed = component_id == COMPONENT_CLUTCH
	if _differential_button:
		_differential_button.button_pressed = component_id == COMPONENT_DIFFERENTIAL

	var signal_bus := get_node_or_null("/root/SignalBus")
	if signal_bus:
		signal_bus.component_selected.emit(component_id)
