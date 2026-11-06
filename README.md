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
| Space (hold) | Auto-hop; releasing and repressing in air recovers an air jump |
| LMB | Basic attack |
| RMB | Release curve |
| Q | Quick attack |
| F | Shove |
| E | High jump |
| Ctrl | Air slam |
| R | Wall (aim down for a horizontal wall) |
| Shift | Dash |
| Escape | Pause offline; open a non-pausing menu online |
| F1 | Live tuning panel (simulation continues) |
| F2 | Reset offline match / host starts an online rematch |
| F3 / F4 | Spawn / remove bot offline (up to eight players) |
| F5 | Toggle quarter-speed offline simulation scheduling |
| F6 / F7 / F8 | Hitboxes / velocity vectors / debug HUD |
| F9 / F10 | Add 100% damage / teleport to center (offline) |
| F11 / F12 | Save replay / replay it after leaving an online session |
| M | Toggle music during gameplay |
The F1–F12, M and Escape development/menu controls are preserved.
Four kits define distinct combat styles:

- **Earth:** slow, large projectiles; strong knockback; walls and slam.
- **Water:** fast, quick attacks; consecutive hits cause stun within 2 seconds.
- **Fire:** highest damage and lowest knockback scale; slight air-target homing; slow wall cooldown.
- **Air:** fast, small shots with the highest knockback scale; momentum-preserving dash and two recoveries.

The element is selected in offline setup or the online profile, and is part of simulation state.
Each kit provides nine moves: basic shot, curve shot, quick fire, shove, high jump, down dash/slam, wall, horizontal dash and recovery. Basic shot, quick fire and shove are held controls; curve shot activates on release, while E, Ctrl, R and Shift activate on press. Releasing and repressing Space in air can request a recovery. Move requests are prioritized, cooldown-gated, and use the selected kit's move data. Aim pitch distinguishes curve-shot behavior: aiming down produces a spike and aiming up a lob. Walls are placed horizontally or vertically according to aim, and projectiles can be deflected by shove; deflection transfers ownership and increases speed/damage up to configured caps.

Movement scalars, per-element move values, projectile multipliers and recovery counts are defined by the simulation kit/tuning data. These are current implementation facts, not evidence that every per-move/per-element value has been exposed through the live editor or verified across the network.

The portable default renderer is Compatibility/OpenGL. The default white-model presentation uses flat outlined primitives, a subtle world-space grid, hard directional shadows and a two-tone horizon. Decorative particles are disabled; gameplay hitstop, small shake and speed FOV remain toggleable in F1.

## Host / Join (2–8 players)

Launch two instances with `godot --path .`.

1. In the first, choose **Host**, enter a player name, color and UDP port (default **7777**), then **Host**.
2. In the second, choose **Join**, enter **127.0.0.1** and the same port for localhost, then **Connect**. For LAN play, use the host's LAN IP and allow its UDP port through the firewall.
3. Each human, including the host, toggles **Ready to play**. The host can select **Bot fill** up to eight total participants.
4. The host chooses **Start match**. Countdown, ring-outs, stocks and winner are server-authoritative. The host can **Rematch** directly or **Return to lobby**.
5. **Leave session** returns to the main menu; host disconnection closes clients cleanly.

Both instances must run the same project/engine revision. This is a direct-IP listen server, not an Internet matchmaking/NAT-traversal service. Online Escape menus release local input without pausing the server. Only the focused window captures the mouse.

The server simulates at 64 Hz and sends snapshots at `NET_SNAPSHOT_RATE` (32 Hz by default). Clients predict their own movement and attack windup, reconcile unacknowledged commands, and interpolate remote players and authoritative projectiles/walls with `NET_INTERPOLATION` (100 ms by default). Projectile and wall simulation, hit detection and all damage/stocks are server-authoritative.

F1 exposes `NET_LATENCY_MS`, `NET_JITTER_MS` and `NET_PACKET_LOSS` (a fraction: `0.05` means 5%). These affect unreliable input/snapshot delivery; reliable lobby/start/events/final results remain reliable. The overlay shows RTT, received snapshot rate, correction magnitude, pending input depth and simulated drops.


## Tests and scene smoke

```sh
tools/test.sh
godot --headless --path . --script tests/scene_smoke.gd
python3 tools/net_test.py --godot godot
```

The runner imports script classes, runs every `tests/*_test.gd`, and fails on script errors as well as process failures. Scene smoke drives actual menu/setup/countdown/bot movement/KO/winner/rematch behavior. Simulation runs at a fixed 64 Hz; render callbacks only animate presentation.

The network regression launches an actual ENet server and two headless clients with BotSim inputs, **100 ms one-way simulated latency, 10 ms jitter and 5% packet loss**. A compact one-stock arena fixture runs to a natural winner; all peers must agree on terminal stocks/winner and observe a fresh rematch countdown. Logs/results are written to a printed temporary directory outside the repository.

To run two actual rendered peers and capture live lobby/play/KO/winner/rematch surfaces:

```sh
python3 tools/net_test.py --godot godot --gui \
  --capture-dir /tmp/shove-online-review --hold-seconds 3
```

Choose a new, empty capture directory for each network run. This driver uses ordinary bot commands, not staged network outcomes. `--expected-clients=1..7` can change the headless peer count; the GUI driver intentionally uses two windows.

The rendered kit/input/replay smoke drives the actual main scene and requires a graphical display with the game window focused; it is deliberately not headless because it exercises focused input capture and rendered gameplay. Run it separately from the headless gates:

```sh
godot --audio-driver Dummy --path . --script tests/kit_scene_smoke.gd
```

The Dummy audio driver avoids requiring audible output. The smoke exercises all nine actions, camera pitch, projectile/wall creation and replay; it is not evidence of full-kit network action coverage.


## Deterministic screenshots

Requires a working graphical display; Godot's `--headless` renderer cannot produce viewport images.

```sh
godot --path . --fixed-fps 64 --script tools/screenshot.gd -- \
  --scenario=all --output=/tmp/shove-captures
```

Scenarios: `menu`, `arena`, `bhop`, `impact`, `ko`, `hud`, `tuning`, `debug`, `countdown`, `winner`, `character`, `projectile`, `earth`, `water`, `fire`, `air`, `spike`, `wall_block`, `deflect`. Committed milestone images are in `docs/shots/m3/`. Default output is `user://screenshots`; `--output` accepts an absolute directory. Captures are 1280×800 PNGs. `--hold` keeps the staged window open.

## Live tuning and replay

Press **F1** or choose **Tuning** from the menu. Search by field name; fields are grouped by prefix. Sliders/number inputs, toggles, color pickers, vector components and palette editors apply instantly. The mouse is released while the panel is open; opponents keep playing.

- **Save / Load**: named JSON files under `user://presets/`.
- **Shipped presets**: **Source-tight**, **Quake-fast**, **Chaos**. Selecting one resets unspecified fields to factory defaults, then applies its overrides.
- **Reset defaults** restores the factory script values.
- **Copy diff** prints and copies changed `var NAME = value` declarations for replacing fields in `scripts/tuning.gd`.
- Tick rate and derived conversion/angle fields are read-only. Structural arena/audio changes rebuild the affected presentation; animation/feel values update directly.
- Online clients can edit local camera/audio/visual/network controls; simulation settings belong to the host. Host changes are transmitted authoritatively. World-mutation dev hotkeys remain offline-only, except host F2/rematch.

Offline matches and the online host record InputCmd streams, initial World/tuning state, and every live tuning patch. Winners automatically save `user://replays/latest.json`; F11 saves the current prefix. Replay format v2 is a clean break and rejects v1 files. After leaving an online session, F12 or **Replay latest** plays the recorded stream, reports exact final-state verification, then restores the previous tuning. Clients do not possess other players' complete authoritative input streams. Determinism is promised for the same build.

Dev mutations (spawn/remove bot, damage, teleport) and server-observed disconnections start a new recording segment at the changed World. Slow motion and hitstop affect scheduling, not the fixed simulation timestep. Replay reproduces simulation state, not online lobby names/colors.


## Architecture

- `scripts/sim/`: scene-free movement, multiplayer World, deterministic bots, match state machine, `Kits`, `AbilitySim` and `ProjectileSim`; these simulation modules are pure.
- `scripts/tuning.gd`: centralized movement, combat, bot, camera, visual, effects, HUD and audio settings. Tick rate is an invariant.
- `scripts/main.gd`: fixed-tick orchestration, code-built menus and presentation integration.
- `scripts/view/`: procedural arena, avatars, effects, HUD, shaders and cached synthesized PCM audio.
- `scripts/dev/`: reflected tuning/presets, typed replay persistence and visual debug gizmos.
- `scripts/net/`: ENet authority/lobby, bounded compressed wire payloads, prediction/reconciliation and remote interpolation.
- `DECISIONS.md` / `CHANGELOG.md`: milestone tradeoffs and verification history.
## Known rough edges and verification limits

- Primitive art and analytical collision are intentionally simple.
- Local prediction intentionally excludes remote-player body collision and combat. The server resolves these and reconciles the client; crowded/laggy brawls remain a playtesting target.
- Internet/NAT behavior and eight separate human clients have not been exercised.
- Audio samples, loop/mute behavior and playback state were verified. Audible output could not be auditioned here: the WSL environment lacked `libpulse.so.0` and an ALSA device, so Godot fell back to Dummy audio. Use a host with a working audio driver; on Ubuntu/WSLg, check `libpulse0` and the PulseAudio/WSLg connection. `--audio-driver Dummy` is appropriate for automated runs, not audible play.
- Some Godot 4.7.2 Dummy-audio exits report a few WAV/playback resource leaks despite explicit player cleanup. Test runners reject script/runtime errors; expected invalid-preset warnings and this shutdown warning are documented separately.
- Replay determinism is within the same build; cross-version/platform floating-point identity is not promised.

## Ten tuning experiments

Change one group at a time, save a named preset, then compare a recorded attack or match:

1. **Momentum as a weapon:** `MOMENTUM_TRANSFER` **0.85 → 1.4**. Compare standing and full-speed bhop launches.
2. **Air steering:** `AIR_SPEED_CAP` **0.762 → 1.5 → 3.2**; then try `AIR_ACCELERATION` **10 → 16**. Watch recoverability versus effortless speed gain.
3. **Slippery landings:** `FRICTION` **4 → 2.5**, then `STOP_SPEED` **2.54 → 1.5**. Compare preserved speed with grounded precision.
4. **Attack commitment:** `SHOVE_WINDUP` **0.10 → 0.07 / 0.14**, holding the active window fixed. Compare reactive hits with readable telegraphs.
5. **Early versus late kills:** separately try `BASE_KB` **8 → 10** and `KB_SCALE` **0.16 → 0.22**. Compare low- and high-damage opponents.
6. **Airtime and recovery:** `GRAVITY` **20.32 → 14**, then `KB_UP` **5 → 7**. Judge whether launches create counterplay or overly long falls.
7. **Hitstun agency:** `HITSTUN` **0.30 → 0.20 / 0.40** and `HITSTUN_CONTROL` **0.15 → 0.35**. Compare launch readability with recovery control.
8. **Bot personality:** `BOT_REACTION` **0.12 → 0.06 / 0.25** and `BOT_BHOP_SKILL` **0.75 → 0.35 / 0.95**. Compare aggressive pressure with approachable opponents.
9. **Juice versus clarity:** `JUICE_HITSTOP_DURATION` **0.055 → 0.025 / 0.08**, then `JUICE_SHAKE_STRENGTH` **0.025 → 0.012 / 0.035**. Toggle either effect off as a readability baseline.
10. **Network feel:** `NET_LATENCY_MS` **100 → 200**, `NET_PACKET_LOSS` **0.05 → 0.10**, then `NET_INTERPOLATION` **0.10 → 0.15**. Compare correction magnitude, pending depth and remote smoothness.
