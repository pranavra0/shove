# Changelog

## v0.3 M6 — Control points

- Added selectable Control points mode alongside Free-for-all (the default): two balanced teams, side-zone captures, ownership scoring and knockback bonus, team-score ring-out penalty, and delayed respawns without elimination at zero stocks. Added team/zone presentation, objective-aware bots, and mode-aware replay/network/scene behavior.
- Bumped the replay format to v3 for the current mode/state schema. v3 rejects v1 and v2 recordings; no migration or compatibility shim is provided, so older recordings do not load.
- `tools/test.sh` passed all 17 suites. The rendered focused-window control scene passed mode selection, 4v4 bot capture, zero-stock respawn input, natural team winner/rematch and default FFA. The real host/two-client/Air-bot control ENet run passed under 100 ms one-way latency, 10 ms jitter and 5% loss; peers agreed on terminal state and rematch reset, and the host replay matched. Inspected and accepted `docs/shots/m6/control_setup.png`, `control_capture.png`, and `control_winner.png`.
- Some headless smoke exits reported ObjectDB shutdown warnings, and some ENet packets triggered MTU-fragmentation warnings; no script errors were reported in the observed passing gates.
- Also passed the rendered native-input smoke (all nine actions plus pitch, entities and replay) and baseline three-peer FFA ENet regression. The final full-kit network gate is the only remaining M6 verification item.

## v0.3 M5 — Per-move tuning and developer tools

- Added sparse element → move → numeric-field `KIT_OVERRIDES` with scalar/per-kit base precedence, typed preset/replay/host settings persistence, and searchable lazy-built per-element/per-move F1 sections. The editor exposes active simulation fields while omitting inert values; `active` is cast-lock time, not physical dash duration.
- Added **Even** (basic-shot values only), **Earth Heavy** and **Air Chaos** presets while retaining Source-tight, Quake-fast and Chaos. Verified all three against actual World effects after preset load, not JSON alone.
- Added offline C kit cycling with a new replay segment, V's timed projectile-firing dummy, and B's view-only fixed-tick curve-shot preview from current aim/strafe (also viewable online). Verified dummy hits/wall blocks, cleanup/replay behavior, preview path, HUD cooldown invalidation and active/windup shove pose.
- Verified all 14 headless suites, offline scene smoke, rendered nine-action input/replay smoke, F1 tuning/persistence/client-edit guard smoke, dev smoke, three preset World checks, and a clean rendered UI smoke. Inspected and accepted `docs/shots/m5/tuning_element.png`, `dummy.png` and `trajectory.png`.
- The impaired three-peer full-kit ENet run used 100 ms one-way latency, 10 ms jitter and 5% loss; it represented all four elements and exercised all nine move slots with physical outcomes. Both clients passed projectile interpolation checks, and the host replay matched exactly after live tuning. Settings/full-start payloads measured 81,396/85,152 bytes within the 131,072-byte bound. Coverage represents all nine slots plus all four elements, not every element/slot combination.

## v0.3 M4 — Kit-aware bots

- Updated deterministic caller-owned BotSim behavior to lead target movement, route curve shots around obstructing walls, defend against projectiles with skill-gated shove deflection or walls, slam grounded opponents, and recover/steer safely near edges using shared Source movement.
- Randomized bot kit assignments for offline match start, offline F3 additions, and host-filled online rosters before recording; capture mode seeds the offline roster RNG from participant IDs, and rematches retain assigned elements. The F3 input/dev-action smoke passed, confirming the new element in the initial tape while preserving the selected human element.
- After the F3 RNG callsite repair, all 13 headless suites passed (exit 0). Offline scene smoke, natural bot combat smoke (32 frames, nine move activation events, eight projectiles, one hit and one wall block, no runtime errors), roster/capture/rematch lifecycle and impaired three-peer ENet match/rematch also passed. M4's network run covered match flow only; full-kit move acceptance was added and verified in M5. One ObjectDB shutdown warning reported six instances in bot combat and seven in the roster throwaway run.

## v0.3 M3 — Kits, abilities and projectiles

- Added four selectable elemental kits with nine move slots each, kit-scaled movement/recovery, held/edge input handling, pitch-driven curve-shot spike/lob behavior, and horizontal/vertical walls. Projectile simulation covers kit-specific data, shove deflection, and wall/projectile contacts; World remains the pure authoritative simulation.
- Added replay format v2 for kit/input/entity state and extended prediction/interpolation to snapshots containing projectiles and walls. Local prediction remains limited to the local player; authoritative projectiles and walls are not locally predicted.
- Verified all 12 headless suites, actual offline scene smoke, and rendered `tests/kit_scene_smoke.gd` covering nine actions, pitch, entities and replay. A real ENet host with two clients completed a bot-driven natural match and rematch under simulated latency/jitter/loss; this is not full-kit network action proof. Captured M3 presentation evidence is in `docs/shots/m3/`.
- The M5 follow-on completed per-move/per-element editing, dev tooling and full-kit network acceptance; see the M5 entry above. The M3 network regression at that milestone covered match flow only.

## v0.3 M2 — Minimal HUD and menus

- Replaced ornate player cards with steady damage numbers/discrete color steps and filled stock squares; added a compact speed meter, glyph-only cooldown bars and outlined edge triangles.
- Rebuilt menus as aligned transparent option lists with underline selection; reduced countdown/feed/results to single lines and matched F1 controls to the flat neutral theme.
- Captured and inspected four-player HUD, menu, tuning panel and winner surfaces in `docs/shots/m2/`. Corrected low-contrast HUD text and duplicate winner text found in screenshots.
- All eight headless suites and the actual offline menu-to-rematch smoke pass on Godot 4.7.2.

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
