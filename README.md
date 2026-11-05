# Shove

A code-built, momentum-driven stock brawler. Build speed with Source-style air strafing, shove rivals off a floating island, and keep your last stock. Godot 4; verified with 4.7.2. No imported art or audio assets.

## Run

From this directory:

```sh
godot --path .
```

Choose **Play vs Bots**, select 1–7 bots, then **Start**. Select **Solo practice** for a sandbox without opponents. Three stocks by default; the last player standing wins. **Rematch** restarts with the same participants.

| Control | Action |
|---|---|
| WASD | Camera-relative movement |
| Mouse | Third-person orbit/aim |
| Space (hold) | Auto-bhop |
| E / left mouse | Shove |
| Escape | Pause/resume offline; release cursor |
| F1 | Live tuning panel (simulation continues) |
| F2 | Reset match |
| F3 / F4 | Spawn / remove bot (up to eight players) |
| F5 | Toggle quarter-speed simulation scheduling |
| F6 / F7 / F8 | Hitboxes / velocity vectors / debug HUD |
| F9 / F10 | Add 100% damage / teleport to center |
| F11 / F12 | Save latest replay / replay it |
| M | Toggle music |

The portable default renderer is Compatibility/OpenGL. Directional shadows, distance fog, procedural sky and geometry-backed neon halos do not require Forward+. Native environment glow is enabled with `--rendering-method forward_plus` on supported graphics drivers.

## Tests and scene smoke

```sh
tools/test.sh
godot --headless --path . --script tests/scene_smoke.gd
```

The runner imports script classes, runs every `tests/*_test.gd`, and fails on script errors as well as process failures. Scene smoke drives actual menu/setup/countdown/bot movement/KO/winner/rematch behavior. Simulation runs at a fixed 64 Hz; render callbacks only animate presentation.

## Deterministic screenshots

Requires a working graphical display; Godot's `--headless` renderer cannot produce viewport images.

```sh
godot --path . --fixed-fps 64 --script tools/screenshot.gd -- \
  --scenario=all --output=/tmp/shove-captures
```

Scenarios: `menu`, `arena`, `bhop`, `impact`, `ko`, `hud` (eight players), `tuning`, `debug`, `countdown`, `winner`. Default output is `user://screenshots`; `--output` accepts an absolute directory. Captures are 1280×800 PNGs. `--hold` keeps the staged window open.

## Live tuning and replay

Press **F1** or choose **Tuning** from the menu. Search by field name; fields are grouped by prefix. Sliders/number inputs, toggles, color pickers, vector components and palette editors apply instantly. The mouse is released while the panel is open; opponents keep playing.

- **Save / Load**: named JSON files under `user://presets/`.
- **Shipped presets**: **Source-tight**, **Quake-fast**, **Chaos**. Selecting one resets unspecified fields to factory defaults, then applies its overrides.
- **Reset defaults** restores the factory script values.
- **Copy diff** prints and copies changed `var NAME = value` declarations for replacing fields in `scripts/tuning.gd`.
- Tick rate and derived conversion/angle fields are read-only. Structural arena/audio changes rebuild the affected presentation; animation/feel values update directly.

Matches record InputCmd streams, initial World/tuning state, and every live tuning patch. Winners automatically save `user://replays/latest.json`; F11 saves the current prefix. F12 or **Replay latest** plays the recorded stream, reports exact final-state verification, then restores the previous tuning. No scene RNG or imported physics state is needed.

Dev mutations (spawn/remove bot, damage, teleport) start a new recording segment at the mutated World. Slow motion and hitstop affect playback scheduling, not the fixed simulation timestep.


## Architecture

- `scripts/sim/`: scene-free movement, multiplayer World, deterministic bots and match state machine.
- `scripts/tuning.gd`: centralized movement, combat, bot, camera, visual, effects, HUD and audio settings. Tick rate is an invariant.
- `scripts/main.gd`: fixed-tick orchestration, code-built menus and presentation integration.
- `scripts/view/`: procedural arena, avatars, effects, HUD, shaders and cached synthesized PCM audio.
- `scripts/dev/`: reflected tuning/presets, typed replay persistence and visual debug gizmos.
- `DECISIONS.md` / `CHANGELOG.md`: milestone tradeoffs and verification history.

Host/Join connection fields are intentionally unavailable before the M5 networking cutover.
