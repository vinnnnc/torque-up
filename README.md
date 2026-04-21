# Ramp It Up

`Ramp It Up` is a Godot-based mechanical network optimization game about routing torque from distributed power nodes into a central engine.

The project currently focuses on readable top-down mechanical construction, engine-route optimization, and visible drivetrain feedback rather than full rigid-body simulation.

## Current Status

Implemented systems currently include:

- standard gears in three sizes
- chain connectors
- flywheel
- clutch
- differential
- multiple power node types
- sink-based engine scoring
- local disconnected subnetwork simulation
- condition, jam, underpowered, and direction-conflict feedback
- dev editor tools for power nodes, zones, barriers, save, load, and clear

## Quick Start

Requirements:

- Godot 4.6 with `GL Compatibility` support

Run:

1. Open the project folder in Godot.
2. Load [project.godot](project.godot).
3. Run the main scene configured at `res://scenes/main/Main.tscn`.

## Gameplay Snapshot

The current game loop is:

1. Place drivetrain parts.
2. Connect power nodes into useful local and engine-valid routes.
3. Manage friction, efficiency, torque limits, and conflicts.
4. Deliver torque into the central engine to raise horsepower output.

Important current rule:

- only power sources connected to the central engine contribute to score/output totals
- disconnected source islands still simulate locally so they can visibly spin, stall, jam, or conflict

## Documentation

Current implementation docs live in [docs/current-state/README.md](docs/current-state/README.md).

Start with:

- [docs/current-state/README.md](docs/current-state/README.md)
- [docs/current-state/components.md](docs/current-state/components.md)
- [docs/current-state/simulation.md](docs/current-state/simulation.md)
- [docs/current-state/placement-and-editor.md](docs/current-state/placement-and-editor.md)
- [docs/current-state/ui-and-world.md](docs/current-state/ui-and-world.md)

These documents are the best reference for the repository as it exists now.

## Session Management

The game uses persistent session tracking with local personal best records:

- **Auto-save on exit**: Component layout, network state, and lifetime HP are saved
- **Resume or start fresh**: Player can resume last session or clear and begin new game
- **Personal best**: Highest lifetime HP ever achieved is tracked locally and displayed in HUD
- **No leaderboards**: Focus is on self-improvement iteration, not competitive ranking

See [docs/progression-and-balance.md](docs/progression-and-balance.md) for session design and balancing parameters.

## Current UI

The HUD currently exposes:

- Horsepower
- Torque
- Efficiency
- RPM
- Personal best (top-right corner)

The build hotbar currently exposes:

- Gear S (key 1)
- Gear M (key 2)
- Gear L (key 3)
- Chain (key 4)
- Flywheel (key 5)
- Clutch (key 6)
- Differential (key 7)
- Delete mode (key X)

## Repository Structure

- [scripts/](scripts/): gameplay, simulation, UI, placement, and tooling logic
- [scenes/](scenes/): Godot scenes
- [assets/](assets/): art and icons
- [docs/current-state/](docs/current-state/): repository-aligned design and implementation docs
- [.github/copilot-instructions.md](.github/copilot-instructions.md): AI-facing repo guidance aligned to the current game state

## Notes

- `chain` is the canonical term. `belt` remains only as a compatibility alias in some code paths and save handling.
- shaft placement is deprecated for new builds; legacy shaft data is still supported for compatibility.
- clutch and differential visuals now use static housings with visible internal motion.
- flywheel, clutch, and differential use port-limited snapping rather than generic perimeter snapping.
