# Components

## Standard Gears

Three standard gears are supported:

- `gear_small`
- `gear_medium`
- `gear_large`

They are the default meshing components for most builds.

Current behavior:

- use regular circular perimeter snapping
- contribute friction and torque load based on profile
- rotate directly when driven
- support Phase 1 compound stacking (max 2 layers)
- same-size stack is blocked for gear+gear and allowed for gear+sprocket
- converted sprocket-mode gears cannot form gear-mesh links
- stacked layers share angular velocity (rigid-coupled presentation)
- each added compound layer applies efficiency and response penalties

## Power Nodes

Power nodes are equal-class sources.

Types:

- balanced
- torque
- speed

Current behavior:

- every power node has its own output curve and spin parameters
- all power nodes can run local subnetworks even when disconnected from the engine
- only engine-connected power nodes contribute to score/output totals
- local subnetworks can become underpowered, jammed, stalled, or direction-conflicted

## Central Engine

The central engine is the scoring sink.

Current behavior:

- engine-connected source networks determine delivered torque and horsepower
- engine RPM is derived from the actual drive chain multiplier, then converted to HUD RPM
- engine connection state is separate from local source activity
