# Simulation

## High-Level Model

The current simulation is split into two layers:

- local source simulation: disconnected power nodes run a lightweight torque-budget pass for visual feedback (spin vs stall)
- engine scoring simulation: only the subnetwork that reaches the central engine contributes to delivered torque, horsepower, efficiency, and HUD RPM

This avoids the old privileged "main power node" model while still keeping the engine as the authoritative scoring sink.

## Torque

Torque is gathered from active sources using source-specific output functions or rated torque values.

Important current rule:

- `active` for scoring means connected to the central engine
- source-to-engine connectivity is evaluated through player-placed components only (power nodes and engine do not bridge islands)

Torque processing currently includes:

- friction load from reachable component profiles
- shaft joint penalties
- zone-driven output modifiers and added load
- source droop under load ratio
- reflected source-side load scaling from source-to-engine ratio:
    - reduction ($|ratio| < 1$) lowers reflected load at the source side
    - overdrive ($|ratio| > 1$) raises reflected load at the source side

## Efficiency

Efficiency is currently based on:

- number of reachable engine-network connections
- zone efficiency modifiers
- a small mixed-network bonus when a reachable network uses both gears and shafts
- a gear-variation bonus based on small/medium/large gear diversity (with optional chain/compound add-ons)
- compound stack added-layer penalty (per added layer)

Efficiency is clamped to a minimum floor.

## RPM

The game tracks angular speed internally on components and source visuals.

HUD RPM is currently:

- the absolute RPM of the central engine drive
- gear ratio propagation uses per-edge tooth/radius ratio multipliers through the network traversal
- the engine edge ratio prefers tooth-count ratio when available
- derived from engine angular speed using $RPM = |\omega| \times 60 / 2\pi$

This is a display stat, not yet a full standalone simulation resource.

## Local Source Simulation

Disconnected source islands use a simplified local pass.

Per local power node, the game currently computes:

- reachable local components
- local friction load
- local torque droop
- local underpowered state

This allows isolated networks to:

- spin
- stall when out of torque
- show underpowered source visuals

Isolated islands do not feed engine scoring metrics.

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
- disconnected source islands use simplified visual drive targets rather than full per-path drive/conflict propagation
