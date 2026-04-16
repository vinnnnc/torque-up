# UI And World

## HUD

The HUD currently exposes:

- Horsepower
- Torque
- Efficiency
- RPM

The bottom hotbar currently exposes:

- None
- Gear S
- Gear M
- Gear L
- Shaft
- Chain
- Flywheel
- Clutch
- Differential
- Delete

## Visual State Language

Components currently use color and motion to communicate state.

Examples:

- connected vs disconnected tint
- engine-route highlight tint
- stalled tint
- conflict tint
- condition heat / risk tinting
- shaft banding for visible spin
- static clutch/differential housings with visible internal motion

## Engine Route Highlighting

The game currently distinguishes:

- locally active subnetworks
- engine-valid route membership

Meaning:

- a component can be visibly powered by a nearby source
- but still remain outside the engine-scoring route

The engine route uses a separate highlight state from basic local activity.

## Power Node Presentation

Power nodes currently support:

- connection-state tinting
- underpowered tinting
- always-active idle spin where configured
- direct-drive or torque-based spin modes depending on current simulation state

## Zones

Current zone types available in tooling:

- heat
- cold
- dusty

Zone gizmos are editor-visible circular areas.

## Barriers

Barriers are circular blocked placement regions with editor gizmos.

Current behavior:

- affect placement and snapping space
- do not behave as simulation components

## Camera And World Interaction

The current project still follows the top-down readable mechanical-network presentation described in the original concept. The world remains the main interface, with the HUD used as a compact stat and tool strip rather than a management-heavy panel.
