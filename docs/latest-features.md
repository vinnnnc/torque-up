# Latest Features (Section 8+)

Implementation brief for the latest feature set discussed after the initial shipped systems.

## 8. Power Node And Engine Stabilization Pass

### Motivation

With multi-source routing now focused on gears, compound gears, and chains, the
remaining blockers are:

- early-stage HP often sits below 1.0 and feels unrewarding
- network efficiency can collapse as route length grows, risking progression stalls
- unrestricted source RPM creates readability and balancing problems
- very high RPM makes placed gear teeth unreadable in top-down view

### Scope

- Active drivetrain scope: gears, compound gears, chain
- Flywheel, clutch, and differential are paused for now
- High-speed visual mode applies to placed components only (not power nodes)

### 8A. Power Node Size Pass

Introduce source gear radii smaller than current small gear to differentiate source profiles.

- Speed node uses the smallest source gear radius
- Balanced node uses a mid-small radius
- Torque node uses the largest source gear radius of the three

### 8B. Early-Game HP Uplift

Tune source torque/RPM and early-zone pressure so first valid layouts produce
clear, readable HP growth.

Target ranges:

- first stable engine route: 3-10 HP
- early optimized single/dual-source route: 15-40 HP

### 8C. Power Node RPM Limitation (Backdrive/Brake Model)

Limit source contribution by torque-vs-speed curves rather than hard RPM clamps.

```
tau_source(omega) = clamp(tau_stall * (1 - omega / omega_no_load), -tau_brake_max, tau_stall)
```

Behavior:

- below `omega_no_load`: positive drive torque
- at `omega_no_load`: near-zero contribution
- above `omega_no_load`: negative torque (source behaves as a brake)

### 8D. High-Speed Visual Mode (Placed Components Only)

Keep simulation RPM intact while protecting readability.

- define per-component visual RPM cap for toothed rendering
- above threshold, switch placed gears/chains to high-speed representation (blur ring / timing marks)
- power nodes keep their existing source visuals and do not switch modes in this pass

### 8E. Engine Sink Resistance and Operating Band

Prevent late-game torque stacking from flattening gameplay into one-axis scaling.

```
tau_load(omega) = tau_static + a * omega + b * omega^2
```

Scoring model:

- compute network input HP at the engine inlet from delivered torque and RPM
- compute effective scored HP by applying an engine operating-band efficiency multiplier
- keep RPM as a meaningful optimization axis without using a permanently rising hard RPM gate

### 8F. Central Engine Macro Gear Presentation

Rework the central engine into a visually massive gear to communicate load and
inertia while preserving playable connection density.

- engine visual shell radius can be very large
- engine mechanical connection radius must remain independently tunable
- only a small outer tooth arc is visibly exposed for network meshing/readability

### 8G. Cone-Shaped Playable Frontier and Camera Fence

Replace the current upper semicircle progression area with an upward cone
play-space rooted at the engine.

- placement/unlock validation uses cone angle + frontier radius
- world blockade/fog rendering follows cone boundaries
- camera movement is clamped to valid cone region and blocked lower area
- minimap should mirror cone geometry

## Acceptance Criteria

- [ ] Distinct source size profile per power node type is visible in-world
- [ ] First stable route reaches at least 3 HP without advanced layouts
- [ ] Overspeed branches can enter braking behavior
- [ ] Ratio-normalized merges outperform mismatched merges
- [ ] High-speed visual mode preserves readability
- [ ] Engine macro-gear presentation preserves practical routing density
- [ ] Cone frontier, camera fence, and minimap geometry stay aligned

## Implementation Phases

### Phase 1: Foundation Tunables

- constants in [scripts/core/project_paths.gd](../scripts/core/project_paths.gd)

### Phase 2: Source Behavior and Aggregation

- runtime source model in [scripts/components/anchor_rotor.gd](../scripts/components/anchor_rotor.gd)
- contribution aggregation in [scripts/core/game_manager.gd](../scripts/core/game_manager.gd)
- torque helpers in [scripts/features/torque/torque_system.gd](../scripts/features/torque/torque_system.gd)

### Phase 3: Engine Sink and Presentation

- engine resistance/scoring response in [scripts/core/game_manager.gd](../scripts/core/game_manager.gd)
- macro-gear visual/mechanical split

### Phase 4: World Geometry and Readability

- high-speed visual mode in drivetrain rendering scripts
- HUD, minimap, and cone frontier presentation updates

Current status:

- implemented: placed gear visuals switch to a high-speed readability mode (blur/timing ring) above threshold angular speed
- pending: any additional HUD/minimap readability polish tied to high-speed state

### Phase 5: Balance and Hardening

- early-game HP tuning
- long-session regression and anti-collapse verification
