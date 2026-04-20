# Core Loop Templates (Implementation Later)

These templates define optional level/challenge structures with explicit objectives and win conditions. They are experimental challenge designs layered on top of the core sandbox progression.

**Current Progression Model**: See [docs/progression-and-balance.md](progression-and-balance.md) for the sandbox progression structure (Phase 0–3) driven by torque milestones and the torque frontier unlock mechanic.

These templates represent alternative progression routes or optional challenge modes that could be explored later if the game expands beyond pure sandbox optimization.

---

## Template A: Throughput Ramp

- Objective: Reach and hold a horsepower target for a sustain window.
- Win condition: HP >= target for N seconds continuously.
- Fail pressure: Belt slip and load spikes reduce sustain reliability.
- Teaches: Stable topology over shortest path.

Recommended params:

- HP target: 140 (early), 190 (mid), 250 (late)
- Sustain time: 12s / 18s / 25s
- Penalty trigger: Stability < 70% resets sustain timer

## Template B: Torque Gate + RPM Gate

- Objective: Activate two locks with conflicting requirements.
- Lock 1: Minimum torque threshold.
- Lock 2: Minimum RPM threshold.
- Win condition: Both locks active at same time.
- Teaches: Mixed ratio strategy and branch specialization.

Recommended params:

- Torque lock: >= 85 torque
- RPM lock: >= 1.8x baseline speed
- Simultaneous hold: 6s

## Template C: Heat Corridor Routing

- Objective: Power distant node through hostile zone layout.
- Environmental pressure:
    - Heat zones increase belt slip.
    - Dust zones increase friction.
    - Cold zones improve efficiency but may reduce max RPM.
- Win condition: Deliver minimum HP while keeping efficiency above floor.
- Teaches: Route planning and component selection by environment.

Recommended params:

- Efficiency floor: 62%
- HP minimum: 120
- Heat slip multiplier: +25% in zone

## Template D: Stability Budget

- Objective: Maximize output without crossing instability cap.
- Budget pressure: Every overloaded edge or high split imbalance reduces stability.
- Win condition: HP >= target and stability >= threshold.
- Teaches: Distribution and redundancy over single trunk routing.

Recommended params:

- Stability threshold: 75%
- HP target: 175
- Overload events: each event -4% stability (temporary)

## Template E: Efficiency Trial (Connect vs Optimize)

- Objective: Same map has 3 medals.
- Bronze: Connect engine.
- Silver: Reach HP target.
- Gold: Reach HP + efficiency + stability simultaneously.
- Teaches: Transition from completion to optimization mastery.

Recommended params:

- Bronze: engine active once
- Silver: HP >= 160
- Gold: HP >= 160, efficiency >= 68%, stability >= 80% for 10s

## Component Role Rules (for all templates)

- Gears: ratio control, compact routing, moderate friction.
- Shafts: rigid transfer, low loss over medium spans, poor obstacle handling.
- Belts: obstacle bypass, high flexibility, slip risk under load/heat.
- Compound (stacked) gears: local ratio staging without extra footprint.

## Template Construction Checklist

- Include at least one route where belt is easiest but not best.
- Include at least one objective requiring both torque and speed behavior.
- Include one constrained area (barrier/zone) that forces tradeoff.
- Ensure there is a viable no-belt fallback path.
- Validate with 3 expected solution qualities: quick, efficient, stable.

## Suggested Rollout Order

1. Template E (medal ladder onboarding)
2. Template A (sustain pressure)
3. Template B (torque vs RPM split)
4. Template C (environment routing)
5. Template D (stability mastery)

## Telemetry to Log During Playtests

- Time to first engine activation
- Number of belts vs gears vs shafts
- Average efficiency and stability
- Failure cause distribution (slip, overload, disconnected)
- % players achieving silver/gold on first attempt

---

## Relationship to Sandbox Progression

The sandbox game (as defined in [docs/progression-and-balance.md](progression-and-balance.md)) provides organic progression through:

1. **Torque milestones** (50 → 150 → 300 → 500+ HP)
2. **Torque frontier unlock** (spatial progression gated by sustained torque)
3. **Session resume** (players iterate and refine layouts)
4. **Personal best tracking** (self-comparison, not ranking)

These templates represent **optional challenge structures** that could layer on top of sandbox mode:

- Single discrete objective with clear win/lose condition
- Alternative to "open-ended optimization"
- Could be gated by torque frontier or available anytime
- Experimental: test before committing to challenge mode

**Current Focus**: Build and balance the sandbox core first. Challenge templates are speculative design for potential future expansion.
