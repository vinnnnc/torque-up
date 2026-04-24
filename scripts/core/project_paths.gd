extends RefCounted
class_name ProjectPaths

const COMPONENTS_CONTAINER_PATH := NodePath("../Network/Components")
const POWER_SOURCE_PATH := NodePath("../Network/PowerSource")
const CENTRAL_ENGINE_PATH := NodePath("../Network/CentralEngine")

const COMPONENT_NONE := ""
const COMPONENT_GEAR_SMALL := "gear_small"
const COMPONENT_GEAR_MEDIUM := "gear_medium"
const COMPONENT_GEAR_LARGE := "gear_large"
const COMPONENT_SHAFT := "shaft"
const COMPONENT_CHAIN := "chain"
const COMPONENT_BELT := COMPONENT_CHAIN # legacy alias
const COMPONENT_DELETE := "delete"
const COMPONENT_FLYWHEEL := "flywheel"
const COMPONENT_CLUTCH := "clutch"
const COMPONENT_DIFFERENTIAL := "differential"

const POWER_NODE_BALANCED := "balanced"
const POWER_NODE_TORQUE := "torque"
const POWER_NODE_SPEED := "speed"

const SMALL_GEAR_OUTER_RADIUS: float = 12.0
const DEFAULT_GEAR_OUTER_RADIUS: float = 18.0
const LARGE_GEAR_OUTER_RADIUS: float = 44.0
const SHAFT_OUTER_RADIUS: float = 5.0
const DEFAULT_GEAR_MODULE: float = 2.0
const DEFAULT_GEAR_ADDENDUM: float = DEFAULT_GEAR_MODULE * 0.80
const DEFAULT_GEAR_DEDENDUM: float = DEFAULT_GEAR_MODULE * 0.70
const DEFAULT_GEAR_HUB_RADIUS_RATIO: float = 0.32
const MIN_GEAR_TOOTH_COUNT: int = 8
const DEFAULT_GEAR_TOOTH_WIDTH_RATIO: float = 0.45
const GEAR_TOOTH_DENSITY_SCALE: float = 1.0
const GEAR_MESH_CONTACT_MARGIN: float = 1.5
const DEFAULT_SOCKET_RADIUS: float = DEFAULT_GEAR_OUTER_RADIUS
const DEFAULT_SOCKET_COUNT: int = 8
const DEFAULT_SNAP_MAX_DISTANCE: float = 24.0
const DEFAULT_PLACEMENT_CLEARANCE: float = DEFAULT_SOCKET_RADIUS - 1.0
const DEFAULT_CONNECTION_TOLERANCE: float = 3.0
const SHAFT_PICK_DISTANCE: float = 160.0
const STACK_PICK_DISTANCE: float = 34.0
const COMPOUND_MAX_LAYERS_PHASE1: int = 2
const COMPOUND_LAYER_EFFICIENCY_PENALTY: float = 0.03
const COMPOUND_LAYER_INERTIA_RESPONSE_PENALTY: float = 0.35
const SHAFT_MIN_CONNECTION_RADIUS: float = SHAFT_OUTER_RADIUS - GEAR_MESH_CONTACT_MARGIN
const SHAFT_MAX_CONNECTION_RADIUS: float = 96.0
const SHAFT_SHAPE_MODULE: float = 2.2
const SHAFT_ENDPOINT_ORIGIN_RADIUS: float = 0.0

# Chain system
const CHAIN_MAX_SPAN: float = 480.0
const CHAIN_FRICTION_BASE: float = 2.5
const CHAIN_FRICTION_PER_RADIUS: float = 0.12
const CHAIN_JAM_LOAD_THRESHOLD: float = 140.0
const CHAIN_JAM_PENALTY: float = 0.15
const CHAIN_SPAN_WEIGHT: float = 0.05
const CHAIN_MODULE_SIZE: float = 1.8

# Belt legacy aliases (use chain values)
const BELT_OUTER_RADIUS: float = 8.0
const BELT_INNER_RADIUS: float = 4.0
const BELT_MAX_SPAN: float = CHAIN_MAX_SPAN
const BELT_FRICTION_BASE: float = CHAIN_FRICTION_BASE
const BELT_FRICTION_PER_RADIUS: float = CHAIN_FRICTION_PER_RADIUS
const BELT_SLIP_LOAD_THRESHOLD: float = CHAIN_JAM_LOAD_THRESHOLD
const BELT_SLIP_PENALTY: float = CHAIN_JAM_PENALTY
const BELT_SPAN_WEIGHT: float = CHAIN_SPAN_WEIGHT
const BELT_MODULE_SIZE: float = CHAIN_MODULE_SIZE

# Gear drag 8-way directional lock
const GEAR_DRAG_DEADZONE: float = 22.0

# Per-component condition system
const CONDITION_HEAT_GAIN_HOT: float = 0.010
const CONDITION_HEAT_GAIN_LOAD: float = 0.004
const CONDITION_HEAT_LOSS_BASE: float = 0.008
const CONDITION_COLD_GAIN_COLD: float = 0.010
const CONDITION_COLD_LOSS_BASE: float = 0.008
const CONDITION_DUST_GAIN_DUSTY: float = 0.006
const CONDITION_DUST_LOSS_BASE: float = 0.002
const CONDITION_STRAIN_SECONDS_TO_JAM: float = 8.0
const CONDITION_JAM_RECOVER_SECONDS: float = 5.0
const CONDITION_WEAR_JAM_THRESHOLD: int = 3
const CONDITION_THRESHOLD_STRAINED: float = 0.35
const CONDITION_THRESHOLD_UNSTABLE: float = 0.65
const CONDITION_THRESHOLD_RISK: float = 0.85

# Torque and friction model
const TORQUE_COST_PER_GEAR: float = 5.0
const TORQUE_COST_RADIUS_EXPONENT: float = 1.15
const FRICTION_SMALL_GEAR: float = 3.2
const FRICTION_MEDIUM_GEAR: float = 5.0
const FRICTION_LARGE_GEAR: float = 12.0
const FRICTION_SHAFT: float = 1.8
const FRICTION_SHAFT_BASE: float = 1.3
const FRICTION_SHAFT_PER_RADIUS: float = 0.085
const FRICTION_DEFAULT_COMPONENT: float = FRICTION_MEDIUM_GEAR
const BASE_POWER_NODE_OUTPUT: float = 50.0
const TORQUE_NODE_OUTPUT: float = 85.0
const SPEED_NODE_OUTPUT: float = 45.0

# Power node profile (Phase 1 tunables)
const POWER_NODE_RADIUS_SPEED: float = 8.0
const POWER_NODE_RADIUS_BALANCED: float = 9.5
const POWER_NODE_RADIUS_TORQUE: float = 11.5

const POWER_NODE_NO_LOAD_RPM_SPEED: float = 235.0
const POWER_NODE_NO_LOAD_RPM_BALANCED: float = 180.0
const POWER_NODE_NO_LOAD_RPM_TORQUE: float = 140.0

const POWER_NODE_STALL_TORQUE_SPEED: float = 56.0
const POWER_NODE_STALL_TORQUE_BALANCED: float = 68.0
const POWER_NODE_STALL_TORQUE_TORQUE: float = 110.0

const POWER_NODE_BRAKE_TORQUE_CAP_SPEED: float = 14.0
const POWER_NODE_BRAKE_TORQUE_CAP_BALANCED: float = 18.0
const POWER_NODE_BRAKE_TORQUE_CAP_TORQUE: float = 24.0

const POWER_NODE_NEAR_LIMIT_RATIO: float = 0.90

# Engine sink response (Phase 1 tunables)
const ENGINE_LOAD_STATIC_TORQUE: float = 42.0
const ENGINE_LOAD_LINEAR_COEFF: float = 0.28
const ENGINE_LOAD_QUADRATIC_COEFF: float = 0.05

const ENGINE_OPERATING_BAND_SOFT_MIN_RPM: float = 8.0
const ENGINE_OPERATING_BAND_MIN_RPM: float = 10.0
const ENGINE_OPERATING_BAND_MAX_RPM: float = 52.0
const ENGINE_OPERATING_BAND_SOFT_MAX_RPM: float = 70.0

# Engine visual tuning (simple larger gear)
const ENGINE_VISUAL_OUTER_RADIUS: float = 800.0
const ENGINE_VISUAL_TOOTH_COUNT: int = 64
const ENGINE_VISUAL_INNER_RADIUS_RATIO: float = 0.92
const ENGINE_VISUAL_HUB_RADIUS_RATIO: float = 0.28
const ENGINE_VISUAL_TOOTH_DEPTH: float = 3.6

# Coupled engine mode: central engine visual radius also drives mechanical ratio.
# Auto-retune helps keep HP/frontier progression playable while preserving low early RPM.
const ENGINE_MECHANICAL_COUPLED_MODE: bool = true
const ENGINE_COUPLED_BASELINE_RADIUS: float = 17.0
const ENGINE_COUPLED_HP_RETUNE_EXPONENT: float = 0.32
const ENGINE_COUPLED_HP_RETUNE_MAX: float = 6.0
const ENGINE_COUPLED_LOAD_EXPONENT: float = 0.80
const ENGINE_COUPLED_LOAD_MAX: float = 40.0
const FRONTIER_COUPLED_TORQUE_MULTIPLIER: float = 0.85
const FRONTIER_COUPLED_HP_TO_TORQUE: float = 0.9

# Drivetrain readability
const DRIVETRAIN_HIGH_SPEED_VISUAL_RPM: float = 120.0
const DRIVETRAIN_HIGH_SPEED_VISUAL_ANGULAR_SPEED: float = 12.57

# World bounds and viewport
const VIEWPORT_WIDTH: float = 1152.0
const VIEWPORT_HEIGHT: float = 646.0
const VIEWPORT_CENTER_X: float = 576.0
const VIEWPORT_CENTER_Y: float = 323.0
const ENGINE_WORLD_Y: float = 800.0
const BLOCKADE_HALF_HEIGHT: float = 323.0
const CAMERA_MIN_Y: float = WORLD_HALF_WIDTH * (-1.0) + VIEWPORT_HEIGHT
const CAMERA_MAX_Y: float = 400.0
const WORLD_HALF_WIDTH: float = 5000.0
const WORLD_VERTICAL_EXTENT: float = WORLD_HALF_WIDTH
const WORLD_BLOCKADE_Z_INDEX: int = 250
const ENGINE_FOREGROUND_Z_INDEX: int = 350
const PLACEMENT_OVERLAY_Z_INDEX: int = 360

# Torque frontier (fog progression)
const FRONTIER_BASE_RADIUS: float = FRONTIER_CONE_APEX_Y_OFFSET + ENGINE_WORLD_Y - 128.0
const FRONTIER_SMOOTHING_ALPHA: float = 0.85
const FRONTIER_RADIUS_SCALE_K: float = 120.0
const FRONTIER_MIN_EXPANSION_STEP: float = 96.0
# Set <= 0.0 to disable frontier radius clamping (endless progression mode).
const FRONTIER_MAX_RADIUS_CLAMP: float = 0.0
const FRONTIER_CONE_HALF_ANGLE_DEGREES: float = 15.0
const FRONTIER_CONE_APEX_Y_OFFSET: float = ENGINE_WORLD_Y - 330.0
const FRONTIER_VISUAL_RADIUS_SMOOTHING: float = 6.5
const FRONTIER_FOG_FEATHER_WIDTH: float = 44.0
const FRONTIER_FOG_FEATHER_STEPS: int = 4
const FRONTIER_REQUIRE_RPM_RAMP: bool = true
const FRONTIER_RPM_GATE_SOFT_MIN: float = 1.0
const FRONTIER_RPM_GATE_FULL: float = 5.0
const FRONTIER_RPM_GATE_MIN_FACTOR: float = 0.6

# Dev procedural map generation (frontier-start, spacing-first)
const DEV_MAP_DEFAULT_NODE_COUNT: int = 1000
const DEV_MAP_NODE_START_RADIUS: float = FRONTIER_CONE_APEX_Y_OFFSET
const DEV_MAP_NODE_RADIUS_BUDGET: float = WORLD_VERTICAL_EXTENT
const DEV_MAP_NODE_SPACING: float = 172.0
const DEV_MAP_NODE_ROW_SPACING: float = 184.0
const DEV_MAP_NODE_RADIAL_JITTER: float = 22.0
const DEV_MAP_NODE_ANGLE_JITTER_DEGREES: float = 5.0
const DEV_MAP_CONE_APEX_RAISE: float = 512.0
const DEV_MAP_NODE_MIN_SEPARATION_FACTOR: float = 1.8
const DEV_MAP_ZONE_RADIUS_EXTRA: float = 0.0
const DEV_MAP_DEFAULT_ZONE_COUNT: int = 5

# Early-game tuning targets (for balancing pass instrumentation)
const EARLY_ROUTE_HP_TARGET_MIN: float = 5.0
const EARLY_ROUTE_HP_TARGET_MAX: float = 10.0
const EARLY_OPTIMIZED_HP_TARGET_MIN: float = 10.0
const EARLY_OPTIMIZED_HP_TARGET_MAX: float = 20.0
const HP_DISPLAY_SCALE: float = 1.0

const EFFICIENCY_LOSS_PER_CONNECTION: float = 0.005
const MIN_EFFICIENCY: float = 0.10
const SHAFT_JOINT_FRICTION: float = 0.55
const MIXED_NETWORK_EFFICIENCY_BONUS: float = 0.035
const GEAR_VARIATION_BONUS_PER_TYPE: float = 0.02
const GEAR_VARIATION_BONUS_MAX_TYPES: int = 3
const GEAR_VARIATION_INCLUDE_CHAIN: bool = true
const GEAR_VARIATION_CHAIN_BONUS: float = 0.015
const GEAR_VARIATION_INCLUDE_COMPOUND: bool = true
const GEAR_VARIATION_COMPOUND_BONUS_PER_STACK: float = 0.01
const GEAR_VARIATION_COMPOUND_BONUS_MAX_STACKS: int = 8

# Flywheel
const FRICTION_FLYWHEEL: float = 8.0
const FLYWHEEL_CAPACITY: float = 200.0
const FLYWHEEL_CHARGE_RATE: float = 0.25
const FLYWHEEL_DISCHARGE_RATE: float = 0.40

# Clutch
const FRICTION_CLUTCH: float = 3.5
const CLUTCH_ENGAGEMENT_THRESHOLD: float = 0.05

# Differential
const FRICTION_DIFFERENTIAL: float = 7.0
const DIFFERENTIAL_MERGE_EFFICIENCY: float = 0.92


static func compute_tooth_count_from_outer_radius(outer_radius: float) -> int:
	var safe_outer := maxf(outer_radius, DEFAULT_GEAR_MODULE * 4.0)
	var scaled_module := maxf(DEFAULT_GEAR_MODULE / maxf(GEAR_TOOTH_DENSITY_SCALE, 0.1), 0.25)
	var pitch_radius := maxf(safe_outer - (scaled_module * 0.80), scaled_module * 3.0)
	var computed := int(round((pitch_radius * 2.0) / scaled_module))
	return maxi(MIN_GEAR_TOOTH_COUNT, computed)
