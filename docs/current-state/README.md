# Ramp It Up: Current State

This directory documents the game as it exists in the repository today.

It is not a pure pitch document. It describes implemented systems, current behavior, and known constraints so future work can extend the existing codebase without reintroducing outdated assumptions.

## Documents

- [components.md](components.md): placeable parts, power nodes, and mechanical behaviors
- [simulation.md](simulation.md): torque, RPM, engine scoring, local source simulation, conditions, and conflicts
- [placement-and-editor.md](placement-and-editor.md): snapping, socket rules, chain/shaft placement, and dev editor tooling
- [ui-and-world.md](ui-and-world.md): HUD, visual state language, zones, and barriers
- [calibration-sheet.md](calibration-sheet.md): parameter worksheet for RPM, HP, frontier, and map-density tuning

## Key Current Rules

- `chain` is the canonical connector name. `belt` remains as a legacy alias in code and save compatibility paths.
- Engine output is sink-based. Only power sources connected to the central engine contribute to delivered torque, horsepower, and engine RPM.
- Connectivity is component-only: power nodes and the central engine do not relay flow between disconnected islands.
- Disconnected power nodes use a simplified local torque-budget visual pass: isolated islands spin when budget allows and stall when overloaded.
- Flywheel, clutch, and differential are implemented as distinct components with port-limited snapping/connectivity.
- Clutch and differential visuals use a static housing with internal spin visuals rather than rotating the full shell.
- HUD currently exposes Horsepower, Torque, Efficiency, and RPM.

## Intended Use

Use these docs when:

- changing simulation rules
- adding components
- modifying placement behavior
- updating save/load behavior
- refreshing the project instructions for AI tooling
