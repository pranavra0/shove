# Shove

A code-built, momentum-driven brawler with Free-for-all and Control points modes. Build speed with Source-style air strafing, shove rivals off a floating island, or capture and defend team zones. Godot 4; verified with 4.7.2. No imported art or audio assets.

## Run

From this directory:

```sh
godot --path .
```

Choose **Play vs Bots**, select **Free-for-all** or **Control points** in the mode option, choose 1–7 bots (maximum eight total), then **Start**. Free-for-all is the default. **Solo practice** remains available without opponents. Free-for-all uses three stocks by default and the last active player wins; Control points is team-based, awards score for zone ownership and knockbacks, and has no stock elimination. **Rematch** keeps the mode and participants.


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
| C | Cycle your kit offline (starts a new replay segment) |
| V | Toggle a timed projectile-firing dummy offline |
| B | Toggle the local curve-shot trajectory preview (online viewing allowed) |
| M | Toggle music during gameplay |
The F1–F12, M and Escape development/menu controls are preserved.
Four kits define distinct combat styles:

- **Earth:** slow, large projectiles; strong knockback; walls and slam.
- **Water:** fast, quick attacks; consecutive hits cause stun within 2 seconds.
- **Fire:** highest damage and lowest knockback scale; slight air-target homing; slow wall cooldown.
- **Air:** fast, small shots with the highest knockback scale; momentum-preserving dash and two recoveries.

The selected mode is part of simulation state. Control points uses two balanced teams (up to 4v4), two side zones and a broad, flat three-lane platform with an unobstructed center. A player captures only while grounded in a zone: one uncontested team fills its progress, an empty or contested zone freezes, and a new capturing team starts from zero. The existing owner keeps the zone until an opposing capture completes. Owning both zones scores for that team and applies the configured full-knockback bonus. First team to the target score wins. Ring-outs cost the team score and trigger a delayed respawn; players are not eliminated, including when their stock counter reaches zero.

Control presentation uses two team accents and outlined, text-free zone fill rings. Control bots split across the side objectives, capture or defend zones, and fight around the center when objective pressure allows; their movement/capture behavior is tuned separately from Free-for-all bot decisions. Team limits apply to both bots and humans.

Control mode tuning is available in F1 alongside other simulation fields. Current defaults: `CP_LANE_OFFSET` 12 m, `CP_ZONE_RADIUS` 3 m, `CP_CAPTURE_TIME` 2 s, `CP_CAPTURE_HEIGHT` 0.3 m, `CP_SCORE_RATE` 4 points/s, `CP_SCORE_TARGET` 100 points, `CP_KB_BONUS` 1.15×, `CP_RINGOUT_PENALTY` 2 points, `CP_RESPAWN_DELAY` 2 s, and `CP_TEAM_COLORS` [`#4d8ec9`, `#d98245`]. Control bot objective defaults are `BOT_CONTROL_ZONE_MARGIN` 2 m and `BOT_CONTROL_CENTER_RADIUS` 3 m. Capture time, zone radius and target score must be positive; score rates, delays and penalties are nonnegative; knockback bonus is at least 1; the team color array has exactly two entries.

In Control points, offline F3 adds a normal team-assigned bot and V adds the existing timed basic-shot dummy; both obey the eight-player roster cap. The dummy aims at the local player but is assigned a team like any roster member, so same-team fire does not deal friendly damage. V remains an offline developer tool; online bot fill is host-controlled.

The remaining `BOT_*` fields control reaction/aim, bhop, edge and recovery behavior, threat response, and move-selection distances. Numeric distances/speeds are metres (or metres/second where a speed is named), timing values are seconds, and skill/probability fields are normalized fractions. Live tuning remains recorded in replay and host-authoritative online.

The portable default renderer is Compatibility/OpenGL. The default white-model presentation uses flat outlined primitives, a subtle world-space grid, hard directional shadows and a two-tone horizon. Decorative particles are disabled; gameplay hitstop, small shake and speed FOV remain toggleable in F1.

## Host / Join (2–8 players)

Launch two instances with `godot --path .`.

1. In the first, choose **Host**, enter a player name, color and UDP port (default **7777**), then **Host**.
2. In the second, choose **Join**, enter **127.0.0.1** and the same port for localhost, then **Connect**. For LAN play, use the host's LAN IP and allow its UDP port through the firewall.
3. Each human, including the host, toggles **Ready to play**. The host can select **Bot fill** up to eight total participants.
4. The host chooses the mode (**Free-for-all** by default or **Control points**) and **Start match**. Countdown, ring-outs, stocks and winner are server-authoritative. The host can **Rematch** directly or **Return to lobby**.

Both instances must run the same project/engine revision. This is a direct-IP listen server, not an Internet matchmaking/NAT-traversal service. Online Escape menus release local input without pausing the server. Only the focused window captures the mouse.

The server simulates at 64 Hz and sends snapshots at `NET_SNAPSHOT_RATE` (32 Hz by default). Clients predict their own movement and attack windup, reconcile unacknowledged commands, and interpolate remote players and authoritative projectiles/walls with `NET_INTERPOLATION` (100 ms by default). Projectile and wall simulation, hit detection and all damage/stocks are server-authoritative.

F1 exposes `NET_LATENCY_MS`, `NET_JITTER_MS` and `NET_PACKET_LOSS` (a fraction: `0.05` means 5%). These affect unreliable input/snapshot delivery; reliable lobby/start/events/final results remain reliable. The overlay shows RTT, received snapshot rate, correction magnitude, pending input depth and simulated drops.


## Tests and scene smoke

```sh
tools/test.sh
godot --headless --path . --script tests/scene_smoke.gd
python3 tools/net_test.py --godot godot
```

Observed M6 verification: `tools/test.sh` passed all 17 suites; the rendered focused-window control scene passed actual mode selection, 4v4 bot capture, zero-stock respawn input, natural team winner/rematch and default-FFA behavior. A rendered host-lobby smoke verified the real host UI's Control mode selection, three-bot fill, Ready/Host start, and the authoritative 2v2 flat Control World. The rendered native-input smoke passed all nine actions plus pitch, entities and replay; baseline three-peer FFA ENet passed. The real control ENet scenario passed with a host, two clients and an Air bot under 100 ms one-way latency, 10 ms jitter and 5% packet loss; all peers agreed on terminal result and rematch reset, and the host replay matched. The five rendered screenshots `docs/shots/m6/control_lobby.png`, `control_online_host.png`, `control_setup.png`, `control_capture.png`, and `control_winner.png` were inspected and accepted. The final full-kit network gate remains pending after a run failed to observe its expected slam outcome; M6 is not yet a fully verified milestone.

```sh
godot --headless --path . --script tests/control_test.gd
godot --headless --path . --script tests/control_replay_test.gd
godot --audio-driver Dummy --path . --script tests/control_scene_smoke.gd
godot --headless --path . --script tests/bot_control_test.gd
python3 tools/net_test.py --godot godot --scenario=control
```
`control_test.gd`, `control_replay_test.gd`, and `bot_control_test.gd` are headless checks; `tools/test.sh` runs the full `tests/*_test.gd` suite. `control_scene_smoke.gd` drives the real main scene, including focused input after a zero-stock respawn, so it requires a graphical display and the game window to be focused; do not run it with `--headless`.

Capture the control-capture presentation scenario on a graphical display:

```sh
godot --path . --fixed-fps 64 --script tools/screenshot.gd -- \
  --scenario=control_capture --output=/tmp/shove-control-capture
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

The Dummy audio driver avoids requiring audible output. The smoke exercises all nine actions, camera pitch, projectile/wall creation and replay; it does not exercise online network play.


## Deterministic screenshots

Requires a working graphical display; Godot's `--headless` renderer cannot produce viewport images.

```sh
godot --path . --fixed-fps 64 --script tools/screenshot.gd -- \
  --scenario=all --output=/tmp/shove-captures
```
Scenarios: `menu`, `arena`, `bhop`, `impact`, `ko`, `hud`, `tuning`, `debug`, `countdown`, `winner`, `character`, `projectile`, `earth`, `water`, `fire`, `air`, `spike`, `wall_block`, `deflect`, `tuning_element`, `dummy`, `trajectory`, `control_capture`. Committed milestone images are in `docs/shots/m3/`; five M6 screenshots (`control_lobby`, `control_online_host`, `control_setup`, `control_capture`, `control_winner`) were inspected and accepted in `docs/shots/m6/`. Default output is `user://screenshots`; `--output` accepts an absolute directory. Captures are 1280×800 PNGs. `--hold` keeps the staged window open.

## Live tuning and replay

Press **F1** or choose **Tuning** from the menu. Search fields by name; scalar settings are grouped by prefix. Numeric controls, toggles, colors, vectors and palettes apply immediately. The **KIT MOVES** sections are lazy-built per element, then searchable by element, move and field. They expose numeric move overrides through sparse `KIT_OVERRIDES` data (element → move → field): absent fields continue to derive from the shared scalar and per-element base values, while explicit overrides take precedence. Fields are checked and persisted by the existing typed preset/replay pipeline. The mouse is released while the panel is open; opponents keep playing.

- **Save / Load**: named JSON files under `user://presets/`.
- **Shipped presets**: **Even** sets each kit's basic-shot damage to 10, base knockback to 3, knockback scale to 0.12 and speed to 18; it does not equalize other moves. **Earth Heavy** sets Earth basic-shot base knockback to 7, wall HP to 12, width/height to 5 and duration to 16; its shove uses damage 22, base knockback 10, scale 0.19 and cooldown 0.75. **Air Chaos** sets Air curve-shot speed 23, drift 0.28, homing 0.3 and damage 9; dash active time 0.3/invulnerability 0.12; recovery speeds 17 up/13 horizontal. **Source-tight**, **Quake-fast** and **Chaos** remain available. Selecting any preset resets unspecified fields to factory defaults, then applies its overrides.
- **Reset defaults** restores factory script values; **Copy diff** prints and copies changed scalar `var NAME = value` declarations for `scripts/tuning.gd`.
- Fixed tick rate and derived/conversion fields remain read-only. `active` controls a move's cast/lock window, not physical dash duration; physical dash duration is not an editable field. Inert fields such as `cost`, recovery speed, and basic/quick-shot gravity are excluded from per-move editing.
- Online clients can edit local camera/audio/visual/network controls; simulation settings belong to the host and host changes are transmitted authoritatively. World-mutation controls remain offline-only, except host F2/rematch.

Offline matches and the online host record InputCmd streams, initial World/tuning state, and every live tuning patch. Winners automatically save `user://replays/latest.json`; F11 saves the current prefix. The current replay format is v3; it rejects v1 and v2 files, with no migration or compatibility shim. Old-format recordings therefore do not load in this build. After leaving an online session, F12 or **Replay latest** plays a supported recording, reports exact final-state verification, then restores the previous tuning. Clients do not possess other players' complete authoritative input streams. Determinism is promised for the same build.

- **C** cycles your kit offline and starts a new replay segment. **V** toggles an offline timed projectile-firing dummy; its shots use actual simulation and can contact walls. **B** toggles the neutral-gray curve-shot trajectory preview, also viewable online: it uses current aim and actual strafe, previews a fixed-64-Hz isolated simulation for at most 128 ticks (two seconds by default), and samples at most 128 points. The simulated actor's future commands are idle; preview does not mutate the live World.
- Avatar shove poses track move windup/active time, and HUD cooldown totals are invalidated when tuning changes.
Dev mutations (spawn/remove bot or dummy, damage, teleport, cycle kit) and server-observed disconnections begin a new recording segment at the changed World. Slow motion and hitstop affect scheduling, not the fixed simulation timestep. Replay reproduces simulation state, not online lobby names/colors.


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
- Input actions are sampled at simulation steps rather than buffered between them; a brief press/release edge can be missed if scheduling skips that sample, notably during slow motion. Edge buffering is not implemented.
- M6-specific verification is mostly complete: the 17-suite run, rendered control scene, native-input smoke, baseline and control network scenarios, and inspected M6 screenshots are recorded above. The final full-kit network gate remains pending; see CHANGELOG.md and DECISIONS.md.
- Some headless smoke exits reported ObjectDB shutdown warnings, and some ENet packets triggered MTU-fragmentation warnings; no script errors were reported in the observed passing gates. These warnings are documented rather than suppressed.
- Audio samples, loop/mute behavior and playback state were verified. Audible output could not be auditioned here: the WSL environment lacked `libpulse.so.0` and an ALSA device, so Godot fell back to Dummy audio. Use a host with a working audio driver; on Ubuntu/WSLg, check `libpulse0` and the PulseAudio/WSLg connection. `--audio-driver Dummy` is appropriate for automated runs, not audible play.
- Replay determinism is within the same build; cross-version/platform floating-point identity is not promised. Replay records simulation state, not online lobby names/colors.

## Ten tuning experiments

Change one item or related field group at a time, save a named preset, and record the build, starting values, scenario, and observed result. These are suggested values for comparative playtests, not balance claims:

1. **Curve-shot shaping:** Compare `PROJECTILE_CURVE_MAX` **0.12 → 0.06 / 0.18** (curve amount) and `PROJECTILE_CURVE_ACCEL` **8 → 5 / 12** (m/s²); record path curvature, wall clearance and hit rate.
2. **Deflection tradeoff:** Compare `DEFLECT_SPEED_GAIN` **1.12 → 1.0 / 1.3** and `DEFLECT_DAMAGE_GAIN` **1.08 → 1.0 / 1.2** (multipliers); record deflected projectile speed, damage, and whether the caps `DEFLECT_SPEED_CAP` (m/s) / `DEFLECT_DAMAGE_CAP` (damage) are reached.
3. **Wall counterplay:** Compare `WALL_DURATION` **8 → 4 / 12 s** and `WALL_HP` **3 → 2 / 5**; record blocks, wall lifetime and whether walls dominate lane control.
4. **Water chain window:** Compare `PROJECTILE_CHAIN_WINDOW` **2 → 1 / 3 s** and `PROJECTILE_CHAIN_STUN` **0.18 → 0.10 / 0.25 s**; record consecutive-hit chains and opponent control time.
5. **Fire homing:** Compare per-move `FIRE` curve-shot `homing` override **0.12 → 0.06 / 0.2** (use KIT MOVES; this is a homing fraction, bounded by `PROJECTILE_HOMING_MAX=1.0`); record hits against moving targets and missed shots. Clear the sparse override to restore the derived kit value.
6. **Recovery window:** Compare `RECOVERY_UP_SPEED` **13 → 10 / 16 m/s**, `RECOVERY_HORIZONTAL_SPEED` **10 → 7 / 13 m/s**, and the per-kit `*_RECOVERY_USES` values (integer uses); record successful recoveries and unintended safe returns.
7. **Kit preset combat:** Compare **Even** against **Earth Heavy** and **Air Chaos**, then record element, preset, move, damage/knockback, and outcome. These presets are real supported profiles; Even changes basic-shot values only.
8. **Capture pacing:** Compare `CP_CAPTURE_TIME` **2 → 1.5 / 3 s** and `CP_ZONE_RADIUS` **3 → 2.5 / 4 m**; record capture/contest durations and captures per match. Positive capture time and radius are required.
9. **Ownership score/bonus:** Compare `CP_SCORE_RATE` **4 → 2 / 6 points/s**, `CP_SCORE_TARGET` **100 → 60 / 140 points**, and `CP_KB_BONUS` **1.15 → 1.0 / 1.3**; record score rate, time to target, and measured knockback change. Score target must be positive and bonus at least 1.
10. **Ring-out and respawn:** Compare `CP_RINGOUT_PENALTY` **2 → 0 / 4 points** and `CP_RESPAWN_DELAY` **2 → 1 / 3 s**; record penalty, inactive delay, safe return and subsequent movement at zero stocks. Ring-out never eliminates a Control player.
