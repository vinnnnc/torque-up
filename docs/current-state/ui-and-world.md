# UI And World

## HUD

The HUD currently exposes:

- Horsepower
- Torque
- Efficiency
- Energy (kJ)
- Generator (kW)

The HUD also now exposes two inspection layers:

- a hover tooltip for components, connectors, the engine, and power nodes
- a toggleable network overlay summary (`Q` by default)

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

## Inspection UI

### Hover Tooltip

Hovering a component currently shows a tooltip with:

- component name
- current state badges such as connected, engine-route, underpowered, conflict, jam risk, jammed, bottleneck, and sprocket mode where applicable
- local RPM where available
- local torque where the component exposes it
- current friction and load ratio on engine-connected parts
- type-specific details such as tooth count, chain/shaft span length, flywheel charge, clutch engagement, and differential merge efficiency

Holding `Shift` while hovering expands the tooltip with raw values such as
angular velocity, condition state, heat, dust, and other low-level diagnostics.

### Network Overlay

Press `Q` to toggle the network overlay panel.

The overlay currently summarizes:

- horsepower
- delivered torque
- generator output RPM (debug/tuning)
- generator power output (kW)
- aggregate efficiency
- friction load
- connected source count vs total source count
- reachable component count
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
