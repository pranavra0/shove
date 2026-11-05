# Changelog

## v0.3 M1 — White-model visual reset

- Replaced neon/debris/crystal/cloud presentation with neutral outlined geometry, a subtle world-space grid, two flat horizon tones and hard white directional shadows. Compatibility materials use bounded diffuse lighting so the grid remains visible.
- Simplified avatars to a capsule, facing block and floating hands. Disabled decorative bursts/trails/popups by default; reduced toggleable hitstop, shake and speed FOV.
- Added isolated character/two-player capture staging and committed rendered evidence in `docs/shots/m1/`; inspected arena, fight and close-up. Actual projectile-flight capture depends on the M3 projectile simulation and remains tracked there.
- Verified all eight headless suites, actual scene menu-to-rematch smoke, and rendered capture scenarios on Godot 4.7.2. No GDScript language server is configured; engine import/runtime gates provide diagnostics.

## Phase 1

- Added a runnable Godot 4 code-generated movement sandbox with fixed 64 Hz simulation, Source-style ground acceleration/friction and air acceleration cap, auto-hop, and steep-slope rejection.
- Added yaw-relative keyboard movement, orbit mouse camera, 40 m platform with ramp/box props, capsule player, and speed/ground/tick HUD.
- Added deterministic tests for acceleration, friction, air wish-speed cap, jump-frame friction, and bhop air-strafe speed exceeding ground speed.

## M1 — Combat core

- Replaced scene-owned movement with deterministic, scene-free `World.create/step` for arbitrary player IDs; analytical arena floors, swept landings, and soft player separation.
- Added directional windup/active/cooldown shoves, damage-scaled knockback and horizontal momentum transfer, hitstun air-control reduction, stocks, kill plane, respawn reset and invulnerability.
- Added playable three-player combat sandbox and combat regression coverage. `tools/test.sh` runs every headless unit script; `tests/scene_smoke.gd` exercises the actual scene for 120 physics frames.
- Verified movement and combat suites and headless scene smoke on Godot 4.7.2.

## M2 — Offline matches

- Added deterministic reaction-delayed bots with nearest-enemy targeting, aim error, bhop/air-strafe skill, low-stock edge caution and airborne recovery.
- Added menu, 1–7 bot setup, solo practice, countdown, playing, ring-out slow motion, round-end, winner and rematch; Escape pauses offline play.
- Added bot/match unit coverage and expanded scene smoke through real bot movement, KO, winner and rematch. All headless suites and scene smoke pass.
- Autonomous four-bot match completed at tick 4588: 27 hits, 11 ring-outs, player 3 won.

## M3 — Procedural presentation

- Added floating-island art, stacked tapered rock strata, orbiting debris, external crystal pillars, patterned surf lanes, center/ledges, procedural void sky/cloud sea, fog, shadows and colored rim lighting.
- Added primitive-built visor characters with per-player colors, facing, procedural stride/lean/squash/stretch, shove poses, hit wobble/tumble and invulnerability flicker.
- Added toggleable hitstop/shake/flash, shockwaves, shards, damage popups, movement/comet trails, dust/puffs, speed lines, animated KO/countdown/winner text and damage/stock/offscreen/speed/bhop HUD.
- Added smoothed orbit camera with collision, bob/tilt, look-ahead, speed FOV and KO tracking. E and left mouse both shove.
- Added synthesized cached SFX, wind/footsteps and an eight-bar procedural music loop with live mute/volume controls.
- Built `tools/screenshot.gd`; rendered and inspected menu, arena, bhop, impact, KO and six-player HUD PNGs, iterating on silhouette, sky, exposure and HUD spacing.
- All headless suites and scene smoke pass. Presentation smoke verified FOV, hitstop/shake, music toggle/loop and audible-range, non-clipped PCM for nine SFX.

## M4 — Live iteration tooling

- Added reflected, prefix-grouped and searchable F1 tuning panel with numeric sliders/inputs, toggles, colors, vectors and palettes; instant application, typed user JSON save/load, factory reset and copyable GDScript diffs.
- Shipped Source-tight, Quake-fast and Chaos presets; added all requested dev hotkeys and hitbox/velocity gizmos.
- Added exact replay-lite recording/persistence/playback, including initial World, full tuning and per-frame live tuning patches, automatic winner save and final-state verification.
- Added typed tuning/replay regression suites and an actual-scene live panel/replay test. Corrected empty-search filtering and float32 input normalization exposed by real UI/bot recordings.
- All headless tests, scene smoke and dev-hotkey smoke pass. Rendered and inspected tuning controls, eight-player HUD, debug gizmos, countdown and winner captures.

## M5 — Authoritative online matches

- Added ENet listen-server Host/Join with names/colors, ready controls, host start, bot fill, lobby return, disconnect cleanup and online rematches for 2–8 total players.
- Added 64 Hz server authority, 32 Hz snapshots, tick-tagged redundant commands/ACKs, local movement/windup prediction, reconciliation, smoothed correction and remote snapshot interpolation. Shove hits, damage and stocks remain server-owned.
- Added authoritative event delivery, reliable terminal snapshots, bounded compressed unreliable payloads, configurable latency/jitter/loss and a network stats overlay. Terminal snapshots clear pending prediction.
- Added host input-stream replays and authoritative live tuning propagation, client-local presentation/network controls, focus-aware mouse capture and non-pausing online menus.
- Fixed ramp side/high-edge entry falling through the base floor, added airborne wall/low-edge regressions, and reprojected spawns after live arena resizing. Added actual launch-distance acceptance: standing 7.491 m, full-speed bhop 11.275 m, high damage 15.255 m, momentum disabled 7.522 m.
- All eight headless test suites and scene smoke passed. A real server plus two clients completed a natural match and rematch with 100 ms one-way latency, 10 ms jitter and 5% loss; stocks/winner matched on all peers. Two rendered peers completed the same flow, with live lobby/play/KO/winner/rematch images inspected.
- Additional real-ENet menu smoke covered ready/color-capable setup, six-bot fill/eight-player play, non-pausing online menus, a negative-ID bot winner, return to lobby and host disconnect. Eight-player compressed snapshot regression measured 594 bytes.
- Completed the runbook, limitations and ten tuning experiments. The project now lives at the repository root; existing user commits were preserved.
- Re-ran the complete headless suite, scene smoke, three-process network regression and all ten screenshot scenarios from the relocated repository root; all passed, and the seven required capture surfaces were inspected.
