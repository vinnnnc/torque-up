<p align="center">
  <img src="assets/images/banner.png" alt="Torque Up! banner" />
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Godot-4.6-blue?logo=godotengine&logoColor=white" alt="Godot 4.6" />
  <img src="https://img.shields.io/badge/Language-GDScript-informational?logo=godotengine&logoColor=white" alt="GDScript" />
  <img src="https://img.shields.io/badge/Renderer-GL%20Compatibility-lightgrey" alt="GL Compatibility" />
  <img src="https://img.shields.io/badge/Platform-Web-orange?logo=html5&logoColor=white" alt="Web" />
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License" />
  <img src="https://img.shields.io/badge/Gamedev.js%20Jam%202026-Machines-purple" alt="Gamedev.js Jam 2026" />
</p>

# Torque Up!

`Torque Up!` is a Godot-based mechanical network optimization game about routing torque from distributed power nodes into a generator.

The project currently focuses on readable top-down mechanical construction, generator-route optimization, and visible drivetrain feedback rather than full rigid-body simulation.

## Gamedev.js Jam 2026

This game is an entry in the [Gamedev.js Jam 2026](https://itch.io/jam/gamedevjs-2026).

- **Theme:** Machines
- **Dates:** April 13–26 2026
- **Challenges entered:** Open Source (GitHub), Deploy to Wavedash

## Current Status

Implemented systems currently include:

- standard gears in three sizes
- multiple power node sizes
- sink-based generator scoring
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

## Web Export And Publishing

The repository includes a Web export preset for publishing to browser-based platforms.

Files to know:

- [export_presets.cfg](export_presets.cfg)
- [wavedash.toml](wavedash.toml)

Typical flow:

1. Export the Web build from Godot into [export/](export/).
2. Verify the build boots via [export/index.html](export/index.html).
3. Upload the exported build to your target host.

## Gameplay Snapshot

The current game loop is:

1. Place drivetrain parts.
2. Connect power nodes into useful local and generator-valid routes.
3. Manage efficiency, torque limits, and conflicts.
4. Deliver torque into the generator to raise output.

Important current rule:

- only power sources connected to the generator contribute to score/output totals
- disconnected source islands still simulate locally so they can visibly spin, jam, or conflict

## Session Management

The current build supports run/session flow:

- **Resume or start fresh**: Player can resume last session or clear and begin a new run

## Current UI

The HUD currently exposes:

- Torque (generator load)
- Time (run timer)

The build hotbar currently exposes:

- Gear S (key 1)
- Gear M (key 2)
- Gear L (key 3)
- Delete mode (key X)

## Repository Structure

- [scripts/](scripts/): gameplay, simulation, UI, placement, and tooling logic
- [scenes/](scenes/): Godot scenes
- [assets/](assets/): art and icons
- [assets/fonts/](assets/fonts/): source font package and attribution notes used by UI/HUD font assets

## License

The game code is licensed under [MIT](LICENSE).

Third-party assets are licensed separately and are not re-licensed under MIT.
See [CREDITS.txt](CREDITS.txt) for attribution details.

For the bundled Motion Control font, the full SIL Open Font License text is included at [assets/fonts/OFL.txt](assets/fonts/OFL.txt).

## Credits And Attribution

Third-party assets and acknowledgements are tracked in [CREDITS.txt](CREDITS.txt).

This includes:

- sound effects sources
- Motion Control font attribution and license note (with OFL text in [assets/fonts/OFL.txt](assets/fonts/OFL.txt))
