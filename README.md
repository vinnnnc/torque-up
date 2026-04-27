<p align="center">
  <img src="assets/banner.png" alt="Torque Up! banner" />
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Godot-4.6-blue?logo=godotengine&logoColor=white" alt="Godot 4.6" />
  <img src="https://img.shields.io/badge/Language-GDScript-informational?logo=godotengine&logoColor=white" alt="GDScript" />
  <img src="https://img.shields.io/badge/Renderer-GL%20Compatibility-lightgrey" alt="GL Compatibility" />
  <img src="https://img.shields.io/badge/Platform-Web-orange?logo=html5&logoColor=white" alt="Web" />
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License" />
</p>

# Torque Up!

`Torque Up!` is a Godot-based mechanical network optimization game about routing torque from distributed power nodes into a generator.

The project currently focuses on readable top-down mechanical construction, engine-route optimization, and visible drivetrain feedback rather than full rigid-body simulation.

## Current Status

Implemented systems currently include:

- standard gears in three sizes
- multiple power node sizes
- sink-based engine scoring
- local disconnected subnetwork simulation
- jam, and direction-conflict feedback
- dev editor tools for power nodes, zones, barriers, save, load, and clear

## Quick Start

Requirements:

- Godot 4.6 with `GL Compatibility` support

Run:

1. Open the project folder in Godot.
2. Load [project.godot](project.godot).
3. Run the main scene configured at `res://scenes/main/Main.tscn`.

## Web Export And Deploy

The repository includes a Web export preset and deployment metadata for Wavedash.

Files to know:

- [export_presets.cfg](export_presets.cfg)
- [wavedash.toml](wavedash.toml)

Typical flow:

1. Export the Web build from Godot into [export/](export/).
2. Verify the build boots via [export/index.html](export/index.html).
3. Upload using your Wavedash workflow/CLI from the repository root.

## Gameplay Snapshot

The current game loop is:

1. Place drivetrain parts.
2. Connect power nodes into useful local and engine-valid routes.
3. Manage efficiency, torque limits, and conflicts.
4. Deliver torque into the generator to raise output.

Important current rule:

- only power sources connected to the generator contribute to score/output totals
- disconnected source islands still simulate locally so they can visibly spin jam, or conflict

## Session Management

The game uses persistent session tracking with local personal best records:

- **Auto-save on exit**: Component layout, network state, and lifetime HP are saved
- **Resume or start fresh**: Player can resume last session or clear and begin new game
- **Personal best**: Highest lifetime HP ever achieved is tracked locally and displayed in HUD
- **No leaderboards**: Focus is on self-improvement iteration, not competitive ranking

See [docs/progression-and-balance.md](docs/progression-and-balance.md) for session design and balancing parameters.

## Current UI

The HUD currently exposes:

- Torque
- Time

The build hotbar currently exposes:

- Gear S (key 1)
- Gear M (key 2)
- Gear L (key 3)
- Delete mode (key X)

## Repository Structure

- [scripts/](scripts/): gameplay, simulation, UI, placement, and tooling logic
- [scenes/](scenes/): Godot scenes
- [assets/](assets/): art and icons
- [font/](font/): source font package and attribution notes used by UI/HUD font assets

## Credits And Attribution

Third-party assets and acknowledgements are tracked in [CREDITS.txt](CREDITS.txt).

This includes:

- sound effects sources
- Motion Control font attribution and license note
