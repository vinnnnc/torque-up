# Simulation

## High-Level Model

The current simulation is split into two layers:

- local source simulation: every power node can drive the connected subnetwork around it for visual and state feedback
- engine scoring simulation: only the subnetwork that reaches the central engine contributes to delivered torque, horsepower, efficiency, and HUD RPM

This avoids the old privileged "main power node" model while still keeping the engine as the authoritative scoring sink.

## Torque

Torque is gathered from active sources using source-specific output functions or rated torque values.

Important current rule:

- `active` for scoring means connected to the central engine

Torque processing currently includes:

- friction load from reachable component profiles
- shaft joint penalties
- zone-driven output modifiers and added load
- source droop under load ratio

## Efficiency

Efficiency is currently based on:

- number of reachable engine-network connections
- zone efficiency modifiers
- a small mixed-network bonus when a reachable network uses both gears and shafts

Efficiency is clamped to a minimum floor.

## RPM

The game tracks angular speed internally on components and source visuals.

HUD RPM is currently:

- the absolute RPM of the central engine drive
- derived from engine angular speed using $RPM = |\omega| \times 60 / 2\pi$

This is a display stat, not yet a full standalone simulation resource.

## Local Source Simulation

Disconnected source islands are still simulated.

Per local power node, the game currently computes:

- reachable local components
- local friction load
- local torque droop
- local underpowered state
- local drive utilization
- local direction conflicts

This allows isolated networks to:

- spin
- stall when out of torque
- show underpowered visuals
- hard-stop on conflict or jam

## Direction and Conflict

Rotation direction is determined by graph traversal through meshing relationships and connector rules.

Current conflict handling:

- if two paths demand opposite rotation on the same component, the component is marked as conflicted
- conflicted components hard-stop instead of continuing to interpolate through the conflict
- the same hard-stop behavior applies to jammed and stalled states for readability

## Conditions and Jams

The condition system tracks per-component:

- heat
- cold stress
- contamination
- jam timer
- strain timer
- wear

Threshold states:

- normal
- strained
- unstable
- risk
- jammed

Current behavior:

- zones and load ratios feed into condition accumulation
- sustained high-risk operation can trigger temporary jams
- repeated jams add permanent wear pressure

## Zones and Barriers

Zones can modify:

- friction multiplier
- efficiency multiplier
- added torque load
- power output multiplier
- additive power output

Barrier zones do not modify simulation directly. They block placement and snapping space.

## Current Known Limits

- clutch and differential still use simplified ratio propagation in the graph layer
- differential roles are not yet fully directional in simulation
- local subnetworks are simulated per source and merged heuristically for motion/conflict presentation rather than through a full multi-source solver
