# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-02-06

### Added
- Discord Rich Presence via `discord-rpc-gd` addon — shows session details and elapsed time
- Cross-platform support for the Discord SDK (Windows, Linux, macOS binaries)

### Changed
- Colour-scheme system fully integrated: six palettes (Cyan/Purple, Fire, Ocean, Matrix, Sunset, Mint)
- Glow effect togglable at runtime via `G` key
- HUD overlay moved to dedicated `overlay_font.gd` label node
- Major refactor of `gpu_version.gd` and `node_2d.gd` for the colour pipeline

## [0.3.0] - 2026-02-06

### Added
- `color_converter.glsl` — dedicated GPU compute shader for RGBA colour conversion and glow
- Six colour palettes with per-palette dead/alive/glow colour definitions
- `overlay_font.gd` — separate label node that reads simulation state and renders the HUD
- Custom application icon

### Changed
- Simulation output upgraded from greyscale (`FORMAT_L8`) to full RGBA (`FORMAT_RGBA8`)
- `gpu_version.gd` restructured to support the two-shader pipeline (GoL + colour conversion)
- `node_2d.gd` expanded with colour scheme cycling, glow toggle, and updated rendering loop

## [0.2.0] - 2026-02-04

### Added
- Auto-restart on stable/still-life detection
- Export presets configuration for Windows, Linux, and macOS builds
- Restart label node in scene tree

## [0.1.0] - 2026-02-04

### Added
- Initial GPU-accelerated Game of Life simulation using Godot 4 `RenderingDevice` compute shaders
- `game_of_life.glsl` — compute shader implementing Conway's rules with ping-pong R8 textures
- `gpu_version.gd` — simulation loop, ping-pong buffer management, UI wiring
- `node_2d.gd` — greyscale display via `Sprite2D`, pattern seeding, chaos injection
- Starting patterns: Random, Random Clusters, Acorn, R-Pentomino, Gosper Glider Gun
- Real-time UI controls: game speed, density, pixel scale, pattern selection, auto-restart, chaos injection intervals
- Stability detection via live-cell count comparison
- Chaos injection: periodic random cell writes directly into the active GPU texture
- Project configuration, `.gitignore`, `.editorconfig`