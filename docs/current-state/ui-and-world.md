# UI And World

## HUD

The HUD stats panel currently shows:

- Generator Load Torque (displayed in the Energy row)
- Run Timer (MM:SS elapsed time)

The Horsepower row exists in the scene tree but renders empty in the current build.

The bottom hotbar currently exposes:

- None
- Gear S
- Gear M
- Gear L
- Delete

Shaft, Chain, Flywheel, Clutch, and Differential buttons are present in the scene tree but are hidden and disabled in the current build.

The HUD also exposes two inspection layers:

- a hover tooltip for components, the engine, and power nodes
- a toggleable network overlay summary (`Q` by default)

## Inspection UI

### Hover Tooltip

Hovering a component currently shows a tooltip with:

- component name
- current state badges such as connected, engine-route, underpowered, conflict, jammed, and bottleneck where applicable
- local RPM where available
- local torque where the component exposes it
- zone type for components inside a zone

Holding `Shift` while hovering expands the tooltip with raw values such as
angular velocity, condition state, heat, dust, and other low-level diagnostics.

### Network Overlay

Press `Q` to toggle the network overlay panel.

The overlay currently summarizes:

- horsepower (with target band hint for 1–2 connected sources)
- net torque and engine input torque
- aggregate efficiency
- friction load
- connected source count vs total source count, and reachable component count
- underpowered state
- current bottleneck component by friction load

## Visual State Language

Components currently use color and motion to communicate state.

Examples:

- connected vs disconnected tint
- engine-route highlight tint
- stalled tint
- conflict tint
- condition heat / risk tinting

## Engine Route Highlighting

The game currently distinguishes:

- locally active subnetworks
- engine-valid route membership

Meaning:

- a component can be visibly powered by a nearby source
- but still remain outside the engine-scoring route

The engine route uses a separate highlight state from basic local activity.

Frontier progression now also uses a generator RPM ramp gate, so early weak spin
produces slower distance/brightness growth and stronger networks unlock space faster.

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

The tooltip and overlay now provide the first explicit readout layer on top of
the existing tint and motion language rather than replacing it.
