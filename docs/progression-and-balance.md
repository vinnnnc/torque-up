# Progression and Balance

Core design decisions around game progression, session management, and scoring.

## Session Management

### Overview

**Ramp It Up** is a sandbox/endless optimization game with persistent session tracking. No competitive leaderboards or multiplayer ranking systems.

### Session Lifecycle

1. **Start New Session**
    - Player clicks "New Session" or launches game
    - Components container is cleared
    - Lifetime HP counter resets to 0
    - Session timer starts
    - Network initializes with only the central engine

2. **Build and Optimize**
    - Player places components, routes power sources
    - Game accumulates `lifetime_hp` based on delivered torque × efficiency × reliability over time
    - Reliability multiplier accounts for recent jam events in rolling 60-second window
    - Session state updates continuously

3. **Exit Session**
    - Player clicks "Save and Exit" or quits game
    - Current session is auto-saved locally: `{ lifetime_hp, components[], connections[], timestamp }`
    - Personal best updated only if lifetime_hp exceeds previous best
    - HUD displays: "Personal Best: X HP (Hh Mm Ss)"

4. **Resume Session**
    - Player clicks "Resume Last Session"
    - Previous component layout and network state are reloaded
    - Lifetime HP counter resumes from last saved value
    - Session timer resumes from last duration
    - Player continues building and optimizing

### Personal Best Tracking

- **Storage**: Local JSON file per player (one entry: `personal_best.json`)
- **Contents**:
    ```json
    {
        "lifetime_hp": 487.5,
        "session_duration_seconds": 283,
        "timestamp": "2026-04-20T14:32:00Z",
        "component_count": 14,
        "efficiency_ratio": 0.78
    }
    ```
- **Update Rule**: Only replaced when current session `lifetime_hp` exceeds stored best
- **Display**: HUD shows "PB: X HP" in upper-right corner
- **Compare**: "New personal best!" message on exit if session beat previous record

### Why This Design

- **Encourages iteration**: Players refine layouts over multiple exits/resumes rather than starting over
- **Avoids competition pressure**: Focus shifts from ranking against others to self-improvement
- **Supports different play styles**: Speedrunners can optimize for time; perfectionists can pursue HP without clock pressure
- **Sandbox feel**: Feels like a toy you keep building on, not a race
- **Low technical debt**: No server, no sync issues, pure local JSON

---

## Progression: Early Game → Sandbox Mastery

### Phase 0: Introduction (Torque = 0–50)

**Goal**: Learn connectivity and basic torque flow.

- Start with engine + 1 balanced power node within build radius
- Introduce: gears, chain, basic zones
- Learning objectives:
    - Place components to connect power to engine
    - Observe that disconnected nodes don't contribute to HP
    - Watch how gears change RPM and torque direction
    - See friction/load affect efficiency

**Progression Signal**: First 50 HP accumulated

---

### Phase 1: Efficiency Mastery (Torque = 50–150)

**Goal**: Optimize torque delivery without losing efficiency to friction.

- Introduce: multiple power nodes at varying ranges
- New mechanics:
    - Ratio propagation: size differences affect RPM/torque trade
    - Sprocket auto-conversion on chain placement
    - Power-node RPM limit model (sources drop to neutral, then braking when oversped)
    - Zone modifiers (heat, cold, dust)

**Learning objectives**:

- Balance RPM and torque to reach HP targets
- Avoid over-friction by choosing appropriate connectors
- Use zones strategically (heat escape route, cold efficiency boost)
- Observe efficiency multiplier impact on final HP

**Progression Signal**: First 150 HP accumulated

---

### Phase 2: Network Architecture (Torque = 150–300)

**Goal**: Handle multiple sources and distributed routing.

- Introduce:
    - Compound gear stacks for local ratio without footprint
    - Multi-source convergence via ratio normalization (no differential)
    - Barriers and complex zone layouts
    - Reliability multiplier: jam penalties

**Learning objectives**:

- Design multi-source networks with gear ratio balancing
- Understand when compounds reduce physical size vs when they add efficiency cost
- Manage jam risk through network stability (redundancy, flow balancing)
- Predict how reliability affects long-term HP accumulation

**Progression Signal**: First 300 HP accumulated

---

### Phase 3: Advanced Optimization (Torque = 300+)

**Goal**: Maximize efficiency and reliability under complex constraints.

- Sandbox toolset fully available
- No new mechanics; focus shifts to elegant problem-solving
- Optional challenge: beat personal best time-per-HP

**Learning objectives**:

- Understand intricate zone interactions
- Design highly stable multi-branch networks
- Optimize for specific HP targets with minimal friction overhead
- Speedrun or perfect-run scenarios

---

## Balancing Parameters

### Power Node Characteristics

| Type     | Torque (N⋅m) | RPM | Notes                                        |
| -------- | ------------ | --- | -------------------------------------------- |
| Balanced | 50           | 400 | Neutral starting point                       |
| Torque   | 85           | 250 | Slow and strong; needs ratio boost for speed |
| Speed    | 30           | 600 | Fast but weak; needs ratio reduction or mult |

### HP Target Thresholds

| Milestone | Torque (N⋅m) | Min Efficiency | Expected Time | Notes                    |
| --------- | ------------ | -------------- | ------------- | ------------------------ |
| Phase 0   | 50           | 40%            | 5–10 min      | Single-source practice   |
| Phase 1   | 150          | 60%            | 15–30 min     | Multi-component routing  |
| Phase 2   | 300          | 65%            | 30–60 min     | Multi-source + compounds |
| Phase 3   | 500+         | 70%            | 60+ min       | Mastery/speedrun zone    |

### Efficiency Penalties (per stage)

| Component/Stage | Loss |
| --------------- | ---- |
| Gear mesh       | 2%   |
| Chain           | 3%   |
| Compound layer  | 4%   |
| Zone (hot)      | 3-8% |
| Zone (cold)     | -2%  |
| Zone (dusty)    | 4-6% |

### Friction Load Thresholds

| Condition         | Trigger                                 |
| ----------------- | --------------------------------------- |
| Underpowered      | Delivered torque < sum of friction load |
| Jam risk          | Load ratio > 85% per component          |
| Jam triggered     | Load ratio > 100% for > 3 seconds       |
| Conflict override | Direction mismatch detected             |

### Reliability Multiplier

```
recent_jams_60s = count(jam events in last 60 seconds)
reliability_multiplier = max(0.35, 1.0 - JAM_PENALTY_PER_JAM * recent_jams_60s)
                       = max(0.35, 1.0 - 0.08 * recent_jams_60s)
lifetime_hp += horsepower * delta * reliability_multiplier
```

- Each jam reduces future HP accumulation by 8%
- Can go as low as 35% (catastrophic jam cascade)
- Slowly recovers as 60-second window expires

---

## Torque Frontier Unlock (Fog Progression)

### Design

World is fogged beyond a circular boundary expanding from the central engine. Boundary expands based on sustained delivered torque.

### Unlock Mechanics

```
smoothed_torque_t = 0.85 * delivered_torque_t + 0.15 * smoothed_torque_(t-1)
candidate_radius = base_radius + 3.5 * sqrt(smoothed_torque_t)
unlocked_radius = max(unlocked_radius, candidate_radius)
```

### Tuning Values

- `base_radius`: 120 units (encloses engine + initial power node placement zone)
- `alpha`: 0.85 (85% current torque, 15% history — responds to sustained 3–5 second improvements)
- `k`: 3.5 (radius scalar — sqrt ensures diminishing returns)
- `min_expansion_step`: 5 units (avoid sub-pixel thrashing on HUD)
- `max_radius_clamp`: 600 units (optional per-session cap)

### Progression Mapping

| Delivered Torque | Unlocked Radius | Approx Phase   |
| ---------------- | --------------- | -------------- |
| 10               | 120             | Phase 0 (init) |
| 50               | 185             | Phase 0 (goal) |
| 150              | 310             | Phase 1 (goal) |
| 300              | 455             | Phase 2 (goal) |
| 500+             | 600             | Phase 3+       |

### UX Display

- **Frontier ring**: Subtle circular border at current unlocked_radius; updates smoothly
- **Fog**: Semi-transparent veil outside frontier; blocks placement/snap
- **HUD progress bar**: "Frontier unlocking: X / Y torque for next expansion"
- **Optional hint**: On approach to next milestone, show "+X radius on next 50 torque"

---

## Balancing Philosophy

### Design Tension Resolution

**Realism vs. Gameplay**:

- Real mechanical systems have ~5–10% loss per stage; we use 2–4% to keep gameplay rewarding
- Real torque addition is complex; we use simplified curve merging in differentials
- Accept these abstractions to keep decision cycles short

**Challenge vs. Accessibility**:

- Early phases reward basic connectivity; later phases demand optimization
- No hard failure state; underpowered is visible feedback, not instant loss
- Jams are recoverable (disconnect one component, reset timer)

**Time Investment vs. Reward**:

- Phase 0 (10 min) → feels like quick puzzle
- Phase 1 (30 min) → feels like medium optimization sprint
- Phase 2+ (60+ min) → feels like long-term build project
- Personal best encourages revisiting without pressure to rank globally

---

## Future Balancing Passes

Once features are live and playtested:

1. **Adjust efficiency penalties** if early phases feel too easy or late phases too punishing
2. **Tune torque thresholds** for frontier unlock if progression feels gated wrong
3. **Rebalance jam penalties** if jam recovery feels either trivial or frustrating
4. **Tweak zone modifiers** if certain zones are universally avoided or always optimal
5. **Add optional difficulty settings** (e.g., "strict reliability" mode with higher penalties)
