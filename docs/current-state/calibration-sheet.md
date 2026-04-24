# Calibration Sheet

Use this sheet to tune progression and drivetrain balance from one playtest run.

## Targets

| Phase   |       Node Count |         Target Engine RPM | Target Settled HP | Notes                        |
| ------- | ---------------: | ------------------------: | ----------------: | ---------------------------- |
| Midgame | 1000 map spawned |                        10 |            [fill] | Stable, not stalled          |
| Endgame | 1000 map spawned | 50 (or 40-45 for clarity) |            [fill] | Sustained on optimized route |

## Recorded Run Metrics

Fill from HUD/perf overlay after network settles for 5-10 seconds.

| Metric                         | Midgame Run | Endgame Run |
| ------------------------------ | ----------: | ----------: |
| Engine RPM                     |      [fill] |      [fill] |
| Horsepower (final)             |      [fill] |      [fill] |
| Input Horsepower               |      [fill] |      [fill] |
| Efficiency                     |      [fill] |      [fill] |
| Engine Load Torque             |      [fill] |      [fill] |
| Delivered Torque (engine side) |      [fill] |      [fill] |
| Free Torque                    |      [fill] |      [fill] |
| Connected Sources              |      [fill] |      [fill] |
| Reachable Components           |      [fill] |      [fill] |

## Core Equations

1. Raw HP:

$$
HP_{raw}=\frac{T_{engine}\cdot RPM_{engine}}{5252}\cdot \eta
$$

2. Final HP:

$$
HP_{final}=HP_{raw}\cdot acceptance\cdot band
$$

3. Engine load model:

$$
T_{load}=T_{static}+k_1\omega+k_2\omega^2
$$

4. Frontier drive value (coupled mode):

$$
T_{frontier}=T_{free}\cdot K_{torque}+HP_{final}\cdot K_{hp}
$$

5. Frontier radius candidate:

$$
R_{candidate}=R_{base}+K_r\cdot\sqrt{T_{smoothed}}
$$

## Parameter Groups

### A) Engine Operating Band

- ENGINE_OPERATING_BAND_SOFT_MIN_RPM
- ENGINE_OPERATING_BAND_MIN_RPM
- ENGINE_OPERATING_BAND_MAX_RPM
- ENGINE_OPERATING_BAND_SOFT_MAX_RPM

Adjustment rule:

- Midgame RPM below target and HP suppressed: lower SOFT_MIN and MIN.
- Endgame overspeed too easy: lower MAX or SOFT_MAX.

### B) Engine Load Curve

- ENGINE_LOAD_STATIC_TORQUE
- ENGINE_LOAD_LINEAR_COEFF
- ENGINE_LOAD_QUADRATIC_COEFF
- ENGINE_COUPLED_LOAD_EXPONENT

Adjustment rule:

- Global bogging at all stages: lower STATIC first, then LINEAR.
- High-RPM only too hard: lower QUADRATIC.
- Giant-engine coupling too punitive: lower COUPLED_LOAD_EXPONENT.

### C) Source Identity

- POWER*NODE_NO_LOAD_RPM*{SPEED,BALANCED,TORQUE}
- POWER*NODE_STALL_TORQUE*{SPEED,BALANCED,TORQUE}
- Anchor droop defaults: min_output_ratio / output_droop_strength per type

Adjustment rule:

- Speed node should win on RPM contribution under moderate load.
- Torque node should win on stall/load holding.
- Balanced should remain viable but not best-in-slot.

### D) Frontier Progression

- FRONTIER_COUPLED_TORQUE_MULTIPLIER
- FRONTIER_COUPLED_HP_TO_TORQUE
- FRONTIER_RADIUS_SCALE_K
- FRONTIER_MIN_EXPANSION_STEP
- FRONTIER_RPM_GATE_SOFT_MIN
- FRONTIER_RPM_GATE_FULL
- FRONTIER_RPM_GATE_MIN_FACTOR

Adjustment rule:

- Frontier too jumpy: lower RADIUS_SCALE_K and/or MIN_EXPANSION_STEP.
- Frontier advances while idling: raise RPM gate thresholds.
- Frontier too tied to HP spikes: reduce HP_TO_TORQUE.

### E) Map Density and Routing Cost

- DEV_MAP_NODE_SPACING
- DEV_MAP_NODE_ROW_SPACING
- DEV_MAP_NODE_MIN_SEPARATION_FACTOR

Adjustment rule:

- Paths too long and friction-dominated: reduce SPACING/ROW_SPACING modestly.
- Too many trivial short links: increase separation factor.

## Variation Bonus Tuning

Current knobs (efficiency multiplier bonus):

- GEAR_VARIATION_BONUS_PER_TYPE
- GEAR_VARIATION_BONUS_MAX_TYPES
- GEAR_VARIATION_INCLUDE_CHAIN
- GEAR_VARIATION_CHAIN_BONUS
- GEAR_VARIATION_INCLUDE_COMPOUND
- GEAR_VARIATION_COMPOUND_BONUS_PER_STACK
- GEAR_VARIATION_COMPOUND_BONUS_MAX_STACKS

Scope:

- Counts small/medium/large gears.
- Excludes shaft, clutch, differential from variation scoring.

## One-Pass Calibration Workflow

1. Freeze one map seed and run midgame layout.
2. Record metrics in this sheet.
3. Tune only one parameter group (A-E).
4. Re-run same layout and compare deltas.
5. Repeat for endgame layout.
6. Validate frontier behavior after drivetrain settles.

## Recommended Starting Set (April 2026)

- Mid target: 10 RPM at 1000-node map.
- End target: 50 RPM (or 40-45 if readability is priority).
- Keep endgame settle below DRIVETRAIN_HIGH_SPEED_VISUAL_RPM unless a spectacle build is intended.
