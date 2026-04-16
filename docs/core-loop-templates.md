# Core Loop Templates (Implementation Later)

These templates define level structure and objective pressure so gameplay is optimization-focused rather than simple connectivity.

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
