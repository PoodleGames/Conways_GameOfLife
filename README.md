# Conway's Game of Life
### by PoodleGames

> *A mesmerizing cellular automaton — GPU-accelerated in Godot 4.5*

Watch as simple patterns evolve into complex, ever-changing life forms. A zero-player simulation where cells live, die, and multiply based on four elegant rules — powered entirely by your GPU.

---

## 📐 The Four Rules

| State | Condition | Result |
|---|---|---|
| Alive | < 2 neighbours | Dies (underpopulation) |
| Alive | 2 or 3 neighbours | Survives |
| Alive | > 3 neighbours | Dies (overpopulation) |
| Dead | exactly 3 neighbours | Becomes alive (reproduction) |

---

## ✨ Features

- **GPU-Accelerated** — Up to 120 generations per second via compute shaders; the simulation never touches the CPU after upload
- **Ping-Pong Rendering** — Double-buffered R8 textures for zero-copy state advancement
- **Colour Schemes** — Six palettes (Cyan/Purple, Fire, Ocean, Matrix, Sunset, Mint) with optional glow, applied by a dedicated colour-conversion shader
- **Starting Patterns** — Random, Random Clusters, Acorn, R-Pentomino, Gosper Glider Gun
- **Auto-Restart** — Detects stable/oscillating states by comparing live-cell counts and reinitialises automatically
- **Chaos Injection** — Periodically writes random live cells into the GPU texture to keep things evolving
- **Real-Time UI** — Adjust speed, density, pixel scale, pattern, and all timers while the simulation runs
- **Discord Rich Presence** — Shows current session via DiscordRPC addon

---

## 🎮 Controls

| Input | Action |
|---|---|
| `SPACE` / `R` | Restart with a new pattern |
| `ESC` | Clear the grid |
| `C` | Cycle colour scheme |
| `G` | Toggle glow |
| UI sliders/dropdowns | Adjust all parameters live |

---

## 🔧 Technical Details

Built with **Godot 4.5** using the `RenderingDevice` API for local GPU compute.

| Detail | Value |
|---|---|
| Engine | Godot 4.5 |
| Simulation texture format | `R8_UNORM` (ping-pong) |
| Output texture format | `RGBA8_UNORM` |
| Workgroup size | 8 × 8 |
| Max grid | 920 × 925 @ pixel scale 1 |
| Max simulation speed | 120 ticks/s |

### Architecture

```
game_of_life.glsl       ← Compute shader: advances one GoL generation
color_converter.glsl    ← Compute shader: maps cell state to RGBA + glow
game_of_life.gd         ← Main node: GPU setup, simulation loop, UI (colour version)
game_of_life_simple.gd  ← Main node: GPU setup, simulation loop, UI (greyscale version)
hud_label.gd            ← Label node: reads simulation state and updates HUD text
discord_rpc.gd          ← Node: sets Discord Rich Presence on startup
```

---

## 🖥️ Installation

### System Requirements

| | Minimum |
|---|---|
| OS | Windows 10/11, Linux, macOS |
| GPU | OpenGL 3.3+ |
| RAM | 2 GB |
| Storage | ~150 MB |

### Steps

1. Download the ZIP from the [itch.io page](https://poodlegames.itch.io)
2. Extract to a folder of your choice
3. Run the executable:
   - **Windows:** `ConwaysGameOfLife.exe`
   - **Linux:** `ConwaysGameOfLife.x86_64` — may need `chmod +x ConwaysGameOfLife.x86_64`
   - **macOS:** `ConwaysGameOfLife.app`

No additional installation required.

### Troubleshooting

**Game won't start**
- Update your GPU drivers
- Confirm your GPU supports OpenGL 3.3+
- Linux: ensure the binary has execute permissions (`chmod +x`)

**Performance issues**
- Lower game speed in the UI
- Increase pixel scale to reduce grid resolution
- Update GPU drivers

---

## 📜 Credits

| | |
|---|---|
| Developer | Pascal Menken (PoodleGames) |
| Engine | Godot 4.5 |
| Original concept | John Horton Conway (1970) |
| Special thanks | The Godot team |

---

*🧬 Life finds a way.*

---

## License

This project is licensed under the MIT License.

You are free to use, modify, distribute, and build upon this project, including for commercial purposes. See the [LICENSE](LICENSE) file for details.
