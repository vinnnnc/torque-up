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
- support stacked placement for compound gear setups

## Shaft

`shaft` is a dedicated bridge component rather than a normal gear.

Current behavior:

- represented as a two-end connector between gear centers
- uses endpoint-based connectivity metadata
- has lower friction than gear-only runs for long links
- uses shaft-specific placement, preview, and deletion distance logic
- contributes shaft joint penalties in simulation

## Chain

`chain` is the canonical flexible connector.

Current behavior:

- legacy `belt` code paths still exist for compatibility, but should be treated as aliases to chain
- connects two selected pulleys/sprockets
- uses span, radius, and chain-specific friction rules
- preserves rotational direction through the connector path
- older save data using belt terminology is still accepted by the dev editor loader

## Flywheel

`flywheel` is implemented as a placeable drivetrain component.

Current behavior:

- has a larger body than a standard gear
- snaps only to its discrete ports rather than its full perimeter
- contributes its own friction profile
- includes storage-related constants and script support for torque buffering
- currently behaves as a ported mechanical node in placement and simulation

## Clutch

`clutch` is implemented as a port-limited drivetrain component.

Current behavior:

- one input port and one output port
- placement snapping is restricted to those ports
- engagement logic compares source RPM vs network RPM with a threshold
- transmission can freewheel when disengaged
- visual shell remains fixed while internal rotor motion is shown through windows
- shell includes exposed tooth segments at the ports and visible input/output arrows

Current limitation:

- the connectivity and ratio model treats clutch links as ratio-neutral mechanical passes; richer engaged/disengaged propagation rules can still be expanded further

## Differential

`differential` is implemented as a three-port drivetrain component.

Current behavior:

- three constrained ports
- placement snapping is restricted to those ports
- supports merge-style RPM and torque helper functions in its component script
- visual shell remains fixed while the carrier and internal pinions visibly spin
- shell includes exposed tooth segments at the ports and arrow cues

Current limitation:

- the visual supports the idea of `1 input / 2 output` or `2 input / 1 output`, but the simulation is still effectively a symmetric three-port component with port-limited connectivity, not a fully role-directed device yet

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
