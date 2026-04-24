extends RefCounted
class_name ProjectPaths

const COMPONENTS_CONTAINER_PATH := NodePath("../Network/Components")
const POWER_SOURCE_PATH := NodePath("../Network/PowerSource")
const CENTRAL_ENGINE_PATH := NodePath("../Network/CentralEngine")

const COMPONENT_NONE := ""
const COMPONENT_GEAR_SMALL := "gear_small"
const COMPONENT_GEAR_MEDIUM := "gear_medium"
const COMPONENT_GEAR_LARGE := "gear_large"
const COMPONENT_DELETE := "delete"

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
const STACK_PICK_DISTANCE: float = 34.0

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
const FRICTION_DEFAULT_COMPONENT: float = FRICTION_MEDIUM_GEAR
const BASE_POWER_NODE_OUTPUT: float = 68.0

# Power node: all nodes share the same angular velocity; torque and size are randomized
const POWER_NODE_NO_LOAD_RPM: float = 180.0
const POWER_NODE_BASE_SPIN_SPEED: float = 1.45
const POWER_NODE_TORQUE_SPIN_FACTOR: float = 0.02
const POWER_NODE_STALL_RATIO: float = 1.35        # stall_torque = rated_torque * this
const POWER_NODE_BRAKE_CAP_RATIO: float = 0.22    # brake_torque_cap = rated_torque * this
const POWER_NODE_MIN_OUTPUT_RATIO: float = 0.72
const POWER_NODE_OUTPUT_DROOP: float = 0.40
const POWER_NODE_NEAR_LIMIT_RATIO: float = 0.90

# Random torque range — all sizes draw from the same flat range
const POWER_NODE_TORQUE_MIN: float = 25.0
const POWER_NODE_TORQUE_MAX: float = 115.0

# 5 size tiers: 0 = smallest/most common → 4 = largest/rarest
const POWER_NODE_TIER_0_RADIUS: float = 9.0
const POWER_NODE_TIER_1_RADIUS: float = 11.5
const POWER_NODE_TIER_2_RADIUS: float = 14.5
const POWER_NODE_TIER_3_RADIUS: float = 18.0
const POWER_NODE_TIER_4_RADIUS: float = 22.0

# Kept as generic defaults for AnchorRotor inspector values and fallback paths
const POWER_NODE_STALL_TORQUE_BALANCED: float = 68.0
const POWER_NODE_BRAKE_TORQUE_CAP_BALANCED: float = 18.0
const POWER_NODE_RADIUS_BALANCED: float = 11.5

# Engine (generator) sink response
const ENGINE_LOAD_STATIC_TORQUE: float = 42.0
const ENGINE_LOAD_LINEAR_COEFF: float = 0.28
const ENGINE_LOAD_QUADRATIC_COEFF: float = 0.05

# Generator output-shaft ramp (visible) and internal gearbox equivalent (scoring)
const GENERATOR_OUTPUT_MAX_RPM: float = 10.0
const GENERATOR_INTERNAL_MAX_RPM: float = 1500.0
const GENERATOR_OUTPUT_TORQUE_FOR_MAX_RPM: float = 95.0
const GENERATOR_BREAKAWAY_TORQUE: float = 1.5
const GENERATOR_RPM_RESPONSE: float = 7.0

# Engine visual tuning (simple larger gear)
const ENGINE_VISUAL_OUTER_RADIUS: float = 100.0
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
const ENGINE_WORLD_Y: float = ENGINE_VISUAL_OUTER_RADIUS + 300.0
const BLOCKADE_HALF_HEIGHT: float = 323.0
const CAMERA_MIN_Y: float = WORLD_HALF_WIDTH * (-1.0) + VIEWPORT_HEIGHT
const CAMERA_MAX_Y: float = 400.0
const WORLD_HALF_WIDTH: float = 8000.0
const WORLD_VERTICAL_EXTENT: float = WORLD_HALF_WIDTH
const WORLD_BLOCKADE_Z_INDEX: int = 250
const ENGINE_FOREGROUND_Z_INDEX: int = 350
const PLACEMENT_OVERLAY_Z_INDEX: int = 360

# Torque frontier (fog progression)
const FRONTIER_BASE_RADIUS: float = FRONTIER_CONE_APEX_Y_OFFSET + ENGINE_WORLD_Y + 300.0
const FRONTIER_SMOOTHING_ALPHA: float = 0.85
const FRONTIER_RADIUS_SCALE_K: float = 120.0
const FRONTIER_MIN_EXPANSION_STEP: float = 96.0
# Set <= 0.0 to disable frontier radius clamping (endless progression mode).
const FRONTIER_MAX_RADIUS_CLAMP: float = 0.0
const FRONTIER_CONE_HALF_ANGLE_DEGREES: float = 15.0
const FRONTIER_CONE_APEX_Y_OFFSET: float = 0.0
const FRONTIER_VISUAL_RADIUS_SMOOTHING: float = 6.5
const FRONTIER_FOG_FEATHER_WIDTH: float = 44.0
const FRONTIER_FOG_FEATHER_STEPS: int = 4
const FRONTIER_REQUIRE_RPM_RAMP: bool = true
const FRONTIER_RPM_GATE_SOFT_MIN: float = 0.8
const FRONTIER_RPM_GATE_FULL: float = 10.0

# Dev procedural map generation (frontier-start, spacing-first)
const DEV_MAP_DEFAULT_NODE_COUNT: int = 1000
const DEV_MAP_NODE_START_RADIUS: float = FRONTIER_CONE_APEX_Y_OFFSET
const DEV_MAP_NODE_RADIUS_BUDGET: float = WORLD_VERTICAL_EXTENT
const DEV_MAP_NODE_SPACING: float = 172.0
const DEV_MAP_NODE_ROW_SPACING: float = 156.0
const DEV_MAP_NODE_RADIAL_JITTER: float = 22.0
const DEV_MAP_NODE_ANGLE_JITTER_DEGREES: float = 5.0
const DEV_MAP_CONE_APEX_RAISE: float = 280.0
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


static func compute_tooth_count_from_outer_radius(outer_radius: float) -> int:
	var safe_outer := maxf(outer_radius, DEFAULT_GEAR_MODULE * 4.0)
	var scaled_module := maxf(DEFAULT_GEAR_MODULE / maxf(GEAR_TOOTH_DENSITY_SCALE, 0.1), 0.25)
	var pitch_radius := maxf(safe_outer - (scaled_module * 0.80), scaled_module * 3.0)
	var computed := int(round((pitch_radius * 2.0) / scaled_module))
	return maxi(MIN_GEAR_TOOTH_COUNT, computed)


static func get_power_node_tier_radius(tier: int) -> float:
	match tier:
		0: return POWER_NODE_TIER_0_RADIUS
		1: return POWER_NODE_TIER_1_RADIUS
		2: return POWER_NODE_TIER_2_RADIUS
		3: return POWER_NODE_TIER_3_RADIUS
		_: return POWER_NODE_TIER_4_RADIUS
