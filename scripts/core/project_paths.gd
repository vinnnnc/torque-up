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
const CONDITION_STRAIN_SECONDS_TO_JAM: float = 8.0
const CONDITION_JAM_RECOVER_SECONDS: float = 5.0
const CONDITION_WEAR_JAM_THRESHOLD: int = 3
const CONDITION_THRESHOLD_STRAINED: float = 0.35
const CONDITION_THRESHOLD_UNSTABLE: float = 0.65
const CONDITION_THRESHOLD_RISK: float = 0.85

# Torque and friction model
const TORQUE_COST_PER_GEAR: float = 0.08
const TORQUE_COST_RADIUS_EXPONENT: float = 1.0
const FRICTION_SMALL_GEAR: float = 0.05
const FRICTION_MEDIUM_GEAR: float = 0.08
const FRICTION_LARGE_GEAR: float = 0.16
const FRICTION_DEFAULT_COMPONENT: float = FRICTION_MEDIUM_GEAR
const BASE_POWER_NODE_OUTPUT: float = 1.0

# Power node: all nodes share the same angular velocity; torque and size are randomized
const POWER_NODE_NO_LOAD_RPM: float = 180.0
const POWER_NODE_BASE_SPIN_SPEED: float = 1.45
const POWER_NODE_TORQUE_SPIN_FACTOR: float = 0.02
const POWER_NODE_STALL_RATIO: float = 1.0
const POWER_NODE_BRAKE_CAP_RATIO: float = 0.10
const POWER_NODE_MIN_OUTPUT_RATIO: float = 1.0
const POWER_NODE_OUTPUT_DROOP: float = 0.0
const POWER_NODE_NEAR_LIMIT_RATIO: float = 0.90

# Simplified readable torque units by node tier.
# Weighted procedural mix targets about 100 torque from roughly 100-120 nodes.
const POWER_NODE_TIER_0_TORQUE: float = 0.5
const POWER_NODE_TIER_1_TORQUE: float = 1.0
const POWER_NODE_TIER_2_TORQUE: float = 1.5
const POWER_NODE_TIER_3_TORQUE: float = 2.25
const POWER_NODE_TIER_4_TORQUE: float = 3.0
const POWER_NODE_TARGET_ROUTE_TORQUE: float = 100.0
const POWER_NODE_TARGET_ROUTE_NODE_MIN: int = 100
const POWER_NODE_TARGET_ROUTE_NODE_MAX: int = 120

# 5 size tiers: 0 = smallest/most common → 4 = largest/rarest
const POWER_NODE_TIER_0_RADIUS: float = 9.0
const POWER_NODE_TIER_1_RADIUS: float = 11.5
const POWER_NODE_TIER_2_RADIUS: float = 14.5
const POWER_NODE_TIER_3_RADIUS: float = 18.0
const POWER_NODE_TIER_4_RADIUS: float = 22.0

# Kept as generic defaults for AnchorRotor inspector values and fallback paths
const POWER_NODE_STALL_TORQUE_BALANCED: float = POWER_NODE_TIER_1_TORQUE
const POWER_NODE_BRAKE_TORQUE_CAP_BALANCED: float = POWER_NODE_TIER_1_TORQUE * POWER_NODE_BRAKE_CAP_RATIO
const POWER_NODE_RADIUS_BALANCED: float = 11.5

# Engine (generator) sink response
const ENGINE_LOAD_STATIC_TORQUE: float = 42.0
const ENGINE_LOAD_LINEAR_COEFF: float = 0.28
const ENGINE_LOAD_QUADRATIC_COEFF: float = 0.05

# Generator output-shaft ramp (visible) and internal gearbox equivalent (scoring)
const GENERATOR_OUTPUT_MAX_RPM: float = 15.0
const GENERATOR_INTERNAL_MAX_RPM: float = 1500.0
const GENERATOR_OUTPUT_TORQUE_FOR_MAX_RPM: float = 100.0
const GENERATOR_BREAKAWAY_TORQUE: float = 0.25
const GENERATOR_RPM_RESPONSE: float = 5.5

# Decorative generator head visuals
const ENGINE_TOP_ASSEMBLY_Y_OFFSET: float = -54.0
const ENGINE_TOP_GEAR_A_RADIUS: float = 15.0
const ENGINE_TOP_GEAR_B_RADIUS: float = 11.0
const ENGINE_TOP_GEAR_CENTER_SPACING: float = 24.0
const ENGINE_TOP_GEAR_A_SPEED_MULTIPLIER: float = 2.8
const ENGINE_TOP_GEAR_B_SPEED_MULTIPLIER: float = -4.2

# Engine visual tuning (simple larger gear)
const ENGINE_VISUAL_OUTER_RADIUS: float = 100.0
const ENGINE_VISUAL_TOOTH_COUNT: int = 64
const ENGINE_VISUAL_INNER_RADIUS_RATIO: float = 0.92
const ENGINE_VISUAL_HUB_RADIUS_RATIO: float = 0.28
const ENGINE_VISUAL_TOOTH_DEPTH: float = 3.6

# World bounds and viewport
const VIEWPORT_WIDTH: float = 1152.0
const VIEWPORT_HEIGHT: float = 646.0
const VIEWPORT_CENTER_X: float = 576.0
const VIEWPORT_CENTER_Y: float = 323.0
const ENGINE_WORLD_Y: float = ENGINE_VISUAL_OUTER_RADIUS + 500.0
const BLOCKADE_HALF_HEIGHT: float = 323.0
const CAMERA_MIN_Y: float = WORLD_HALF_WIDTH * (-1.0) + VIEWPORT_HEIGHT
const CAMERA_MAX_Y: float = 400.0
const WORLD_HALF_WIDTH: float = 4000.0
const WORLD_VERTICAL_EXTENT: float = WORLD_HALF_WIDTH
const WORLD_BLOCKADE_Z_INDEX: int = -50
const WORLD_FRONTIER_OVERLAY_Z_INDEX: int = 100
const ENGINE_FOREGROUND_Z_INDEX: int = 350
const PLACEMENT_OVERLAY_Z_INDEX: int = 360

# Torque frontier (fog progression)
const FRONTIER_BASE_RADIUS: float = FRONTIER_CONE_APEX_Y_OFFSET + ENGINE_WORLD_Y
const FRONTIER_SMOOTHING_ALPHA: float = 0.85
const FRONTIER_RADIUS_SCALE_K: float = 650.0
const FRONTIER_MIN_EXPANSION_STEP: float = 196.0
# Set <= 0.0 to disable frontier radius clamping (endless progression mode).
const FRONTIER_MAX_RADIUS_CLAMP: float = WORLD_HALF_WIDTH
const FRONTIER_CONE_HALF_ANGLE_DEGREES: float = 15.0
const FRONTIER_CONE_APEX_Y_OFFSET: float = 0.0
const FRONTIER_VISUAL_RADIUS_SMOOTHING: float = 6.5
const FRONTIER_FOG_FEATHER_WIDTH: float = 44.0
const FRONTIER_FOG_FEATHER_STEPS: int = 4
const FRONTIER_REQUIRE_RPM_RAMP: bool = true
const FRONTIER_RPM_GATE_SOFT_MIN: float = 0.2
const FRONTIER_RPM_GATE_FULL: float = 15.0
const FRONTIER_RPM_GATE_CURVE_EXPONENT: float = 0.55
const FRONTIER_WIN_LEVER_TOP_MARGIN: float = 100.0

# Placement-time jam prevention: reject snap candidates with incompatible
# meshing phase requirements from multiple neighbors.
const PLACEMENT_MAX_ROTATION_MISMATCH_DEGREES: float = 20.0
const PLACEMENT_NEAR_SNAP_ASSIST_DISTANCE: float = 5.0

# Brand color palette (hex source: fff4e0 8fcccb 449489 285763 2f2b5c 4b3b9c 457cd6 f2b63d d46e33 e34262 94353d 57253b 9c656c d1b48c b4ba47 6d8c32 2c1b2e)
const PALETTE_CREAM: Color   = Color(1.00, 0.957, 0.878, 1.0)       # fff4e0
const PALETTE_TEAL: Color    = Color(0.561, 0.8, 0.796, 1.0)        # 8fcccb
const PALETTE_SAGE: Color    = Color(0.267, 0.576, 0.537, 1.0)      # 449489
const PALETTE_SLATE: Color   = Color(0.157, 0.341, 0.388, 1.0)      # 285763
const PALETTE_PURPLE: Color  = Color(0.184, 0.169, 0.361, 1.0)      # 2f2b5c
const PALETTE_INDIGO: Color  = Color(0.294, 0.231, 0.612, 1.0)      # 4b3b9c
const PALETTE_BLUE: Color    = Color(0.271, 0.486, 0.839, 1.0)      # 457cd6
const PALETTE_AMBER: Color   = Color(0.949, 0.714, 0.239, 1.0)      # f2b63d
const PALETTE_ORANGE: Color  = Color(0.831, 0.431, 0.2, 1.0)        # d46e33
const PALETTE_SALMON: Color  = Color(0.89, 0.259, 0.384, 1.0)       # e34262
const PALETTE_CRIMSON: Color = Color(0.58, 0.208, 0.239, 1.0)       # 94353d
const PALETTE_MAUVE: Color   = Color(0.341, 0.145, 0.231, 1.0)      # 57253b
const PALETTE_ROSE: Color    = Color(0.612, 0.396, 0.424, 1.0)      # 9c656c
const PALETTE_TAN: Color     = Color(0.82, 0.706, 0.549, 1.0)       # d1b48c
const PALETTE_OLIVE: Color   = Color(0.706, 0.729, 0.278, 1.0)      # b4ba47
const PALETTE_MOSS: Color    = Color(0.427, 0.549, 0.196, 1.0)      # 6d8c32
const PALETTE_VOID: Color    = Color(0.173, 0.106, 0.18, 1.0)       # 2c1b2e

# Frontier visuals
const FRONTIER_AREA_COLOR: Color = PALETTE_ROSE                      # 9c656c
const BLOCKADE_COLOR: Color      = PALETTE_VOID                      # 2c1b2e

# Dev procedural map generation (frontier-start, spacing-first)
const DEV_MAP_DEFAULT_NODE_COUNT: int = 300
const DEV_MAP_NODE_START_RADIUS: float = FRONTIER_CONE_APEX_Y_OFFSET
const DEV_MAP_NODE_RADIUS_BUDGET: float = WORLD_VERTICAL_EXTENT
const DEV_MAP_NODE_SPACING: float = 150.0
const DEV_MAP_NODE_ROW_SPACING: float = 96.0
const DEV_MAP_NODE_RADIAL_JITTER: float = 22.0
const DEV_MAP_NODE_ANGLE_JITTER_DEGREES: float = 5.0
const DEV_MAP_CONE_APEX_RAISE: float = 256.0
const DEV_MAP_NODE_MIN_SEPARATION_FACTOR: float = 1.8
const DEV_MAP_ZONE_RADIUS_EXTRA: float = 0.0
const DEV_MAP_DEFAULT_ZONE_COUNT: int = 5
const DEV_MAP_ZONE_INNER_FRONTIER_MIN_RATIO: float = 0.20
const DEV_MAP_ZONE_INNER_FRONTIER_MAX_RATIO: float = 0.40
const DEV_MAP_ZONE_INNER_TARGET_SHARE: float = 0.30
const DEV_MAP_GIANT_NODE_COUNT_DEFAULT: int = 7
const DEV_MAP_GIANT_NODE_COUNT_MIN: int = 5
const DEV_MAP_GIANT_NODE_COUNT_MAX: int = 10
const DEV_MAP_GIANT_NODE_RADIUS: float = 30.0
const DEV_MAP_GIANT_NODE_TORQUE: float = 4.5
const DEV_MAP_GIANT_NODE_VISUAL_SCALE: float = 1.15

# Map seed. Set to -1 to use a random seed on each run.
const DEFAULT_RUN_SEED: int = 111

# Early-game tuning targets (for balancing pass instrumentation)
const EARLY_ROUTE_HP_TARGET_MIN: float = 5.0
const EARLY_ROUTE_HP_TARGET_MAX: float = 10.0
const EARLY_OPTIMIZED_HP_TARGET_MIN: float = 10.0
const EARLY_OPTIMIZED_HP_TARGET_MAX: float = 20.0
const EFFICIENCY_LOSS_PER_CONNECTION: float = 0.005
const MIN_EFFICIENCY: float = 0.10
const EFFICIENCY_GEAR_SMALL: float = 0.998
const EFFICIENCY_GEAR_MEDIUM: float = 0.996
const EFFICIENCY_GEAR_LARGE: float = 0.994
const EFFICIENCY_DEFAULT_COMPONENT: float = 0.995
const EFFICIENCY_GEAR_VARIATION_BONUS_PER_TYPE: float = 0.006
const EFFICIENCY_GEAR_VARIATION_MAX_TYPES: int = 3
const EFFICIENCY_GEAR_VARIATION_MAX_BONUS: float = 0.015


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


static func get_power_node_tier_from_radius(radius: float) -> int:
	var tiers := [
		POWER_NODE_TIER_0_RADIUS,
		POWER_NODE_TIER_1_RADIUS,
		POWER_NODE_TIER_2_RADIUS,
		POWER_NODE_TIER_3_RADIUS,
		POWER_NODE_TIER_4_RADIUS
	]
	var best_tier := 0
	var best_distance := INF
	for tier in range(tiers.size()):
		var distance := absf(radius - float(tiers[tier]))
		if distance < best_distance:
			best_distance = distance
			best_tier = tier
	return best_tier


static func get_power_node_torque_for_tier(tier: int) -> float:
	match tier:
		0: return POWER_NODE_TIER_0_TORQUE
		1: return POWER_NODE_TIER_1_TORQUE
		2: return POWER_NODE_TIER_2_TORQUE
		3: return POWER_NODE_TIER_3_TORQUE
		_: return POWER_NODE_TIER_4_TORQUE


static func get_power_node_torque_from_radius(radius: float) -> float:
	return get_power_node_torque_for_tier(get_power_node_tier_from_radius(radius))
