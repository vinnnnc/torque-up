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

# World bounds and viewport
const VIEWPORT_WIDTH: float = 1152.0
const VIEWPORT_HEIGHT: float = 646.0
const VIEWPORT_CENTER_X: float = 576.0
const VIEWPORT_CENTER_Y: float = 323.0
const ENGINE_WORLD_Y: float = 520.0
const BLOCKADE_HALF_HEIGHT: float = 323.0
const CAMERA_MIN_Y: float = 280.0
const CAMERA_MAX_Y: float = 550.0
const EFFICIENCY_LOSS_PER_CONNECTION: float = 0.03
const MIN_EFFICIENCY: float = 0.10
const SHAFT_JOINT_FRICTION: float = 0.55
const MIXED_NETWORK_EFFICIENCY_BONUS: float = 0.035

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
