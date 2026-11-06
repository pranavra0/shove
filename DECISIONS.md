# Phase 1 decisions

- The sandbox is generated from code in `scripts/main.gd`; there are no authored environment assets to maintain.
- Simulation state is a small dictionary (`velocity`, `on_ground`, `ground_angle`) and `MovementSim.step` returns a fresh state. `InputCmd` carries normalized input intent, jump/shove buttons, yaw, and tick; shove is sampled but intentionally has no effect in Phase 1.
- Source speed, gravity, stop-speed, and jump values are converted from inches-based Source units to metres in `scripts/tuning.gd`; acceleration coefficients are dimensionless. Simulation receives the fixed engine timestep (64 Hz) and uses Source-style acceleration/friction.
- Air control caps wish speed at 30 inches/second rather than clamping total horizontal velocity. This preserves existing momentum while preventing additional acceleration past the cap in the commanded direction.
- Jump is held-auto-hop: a held jump command jumps on each grounded simulation step. Ground checks accept only floor angles at or below 45 degrees.
- Movement axes are camera/player-yaw-relative; mouse yaw also turns the capsule to match travel facing. The orbit camera uses captured mouse input; Escape releases the cursor and clicking recaptures it.
- The platform is 40 metres square and geometry, camera, and movement tuning lives in the Tuning autoload so there are no scene-tuning literals scattered across the controller.

## M1 — Shared authoritative simulation

- No separate original-spec file exists in this checkout. The supplied task invariants and Phase 1 decisions are the implementation contract.
- `World.step` owns analytical collision as well as combat, so offline play, replay and the eventual server use identical scene-independent rules. Body-centre positions; sorted IDs; fresh nested player state and per-tick events.
- Shoves use facing direction, post-hit damage, and horizontal attacker velocity. Cooldown begins at attack initiation; one hit per victim per attack. Respawn is immediate at the player's assigned ring spawn, with two seconds of immunity; eliminated players remain as inert states.
- The fixed tick stays a constant; editable gameplay fields become variables in the same Tuning autoload for live tooling. Simulation reads tuning but never scene nodes, time or randomness.
- Command-line SceneTree tests defer simulation script loading until autoload initialization; direct eager loading cannot resolve Godot's Tuning singleton in this engine.
- Initialized project-local Git history because the checkout had no project repository and the enclosing repository contains unrelated projects. Only this project is committed.

## M2 — Offline flow and bots

- Bots return the same InputCmd type as humans plus explicit caller-owned memory. A small deterministic integer PRNG drives skill/aim decisions; replay needs no scene RNG state.
- Solo practice is selected separately from the required 1–7 bot free-for-all and does not immediately declare its sole player winner.
- Slow motion schedules fewer complete 1/64-second World steps; match-flow clocks keep advancing at the engine's fixed tick. World events dispatch only when World actually steps, avoiding duplicate KO/hit presentation.
- Host/Join show connection setup but remain explicitly unavailable until M5, rather than pretending to connect.

## M3 — Portable procedural rendering

- Compatibility/OpenGL remains the portable default on the available WSL graphics driver. Geometry-backed additive edge halos substitute for post-process bloom there; Forward+ enables native environment glow. Distance fog, not volumetric fog, is the portable void treatment.
- A procedural sky shader is kept independent of sky fog (`fog_sky_affect = 0`) so the gradient/cloud bands remain visible. Near-vertical upper rock strata preserve the floating-island silhouette from the above-platform gameplay camera.
- Camera collision queries static presentation proxies; player movement/collision remains exclusively analytical in World. All effects are event-driven cosmetics and never alter damage/stocks.
- Offline hitstop pauses complete simulation ticks rather than changing engine time scale. Online simulation will remain authoritative and use only cosmetic client hitstop.
- Sound effects/music are deterministic cached PCM, with a reusable voice pool; no imported audio or per-frame synthesis. Godot 4.7.2's Dummy-audio runs sometimes report a handful of WAV/playback resources at abrupt process shutdown despite explicit player cleanup; no runtime script errors were observed.
- Capture scenarios freeze simulation and stage reproducible presentation states. PNGs go outside the repository; tuning-panel capture is added at M4.

## M4 — Deterministic live iteration

- Editable settings are reflected from tuning.gd script variables, including Color/Vector2/Vector3 and typed palettes. Fixed-rate/conversion constants and the derived ground angle remain read-only. Reflection/factory metadata is cached; files and UI share type/range checks.
- Godot's decimal JSON parser changed `JUMP_SPEED` by one ULP even with full-precision output. Persisted scalar floats therefore use explicit IEEE-754 hex tags; integer IDs use decimal strings in replay's typed codec. Shipped human-editable numeric presets remain accepted.
- InputCmd decoding preserves float32 unit-vector roundoff within a small epsilon rather than renormalizing an already normalized command. MovementSim still caps its own wish vector; exact bot input roundtrips now survive persistence.
- Replay records a settings patch alongside the next command frame whenever live tuning changes, preserving entire normal matches across experiments. Playback applies those patches before each 1/64-second step and restores the user's previous settings afterward.
- Explicit dev mutations restart recording from the resulting World as a new segment; they are not hidden commands in the normal InputCmd protocol. Structural art/audio settings rebuild their views without resetting authoritative player state.

## M5 — Listen-server authority and deployment

- ENet server ID 1 owns World and MatchSim; clients submit only their own finite, bounded, monotonic InputCmd sequences. Bot IDs start at -2, reserving -1 for no-target/draw sentinels. Names/colors/readiness remain lobby metadata, not simulation fields.
- Unreliable inputs/snapshots receive artificial outbound delay/jitter/loss. Reliable ordered lobby/start/config/events/final packets are not permanently dropped by the simulator, avoiding stale starts and lost terminal outcomes across rematches.
- Input bundles and full snapshots are compressed as bounded, object-free Variant payloads to fit the unreliable MTU. Decompression is capped; the eight-player regression packet is 594 bytes.
- Prediction steps an isolated local player through the same World rules, preserving authoritative combat/stock state. Remote players use a 100 ms receive-time interpolation buffer. Terminal snapshots discard pending movement and interpolation history rather than simulating beyond the final result.
- Client hitstop freezes presentation only; the server clock continues. Offline hitstop still pauses whole simulation ticks. Online menus never pause the server, and only a focused window captures the mouse.
- Host tuning changes are sent reliably and recorded with the next authoritative input frame. Clients may change local cosmetic/camera/audio/network settings but not server simulation fields. Structural config signals fire before applying values so scene geometry/audio rebuild correctly.
- Server disconnect handling starts a new replay segment after the external roster edit. Normal complete matches retain every accepted human/bot command. Replay does not preserve lobby names/colors and is verified within the same tested engine build.
- A natural network regression initially exposed a terrain hole rather than a transport bug. Ramp low edges are continuous floors; raised side/high edges are walls, including airborne entry. Spawns are clamped/reprojected against the current arena to stay finite after live resizing.
- Full headless and two-window localhost runs passed with 100 ms one-way artificial latency/5% packet loss, and both peers observed a rematch. Direct-IP LAN/localhost is the tested deployment; matchmaking, NAT traversal and Internet hardening are outside this prototype.
- The default windowed launch opened successfully, but this WSL environment lacked PulseAudio's `libpulse.so.0` and an ALSA device. Godot selected Dummy audio. PCM synthesis/playback controls were exercised; audible output was not auditioned and requires a working host audio driver.
- The user moved the unchanged project from its nested directory to the repository root and committed the implementation. Continued work uses root-relative paths and preserves that history.

## M3 — Kits, abilities and projectiles

- Kit and ability behavior values are data-driven in `Tuning` and kit tables; `Kits`, `AbilitySim` and `ProjectileSim` remain pure and scene-free simulation modules.
- The World owns one copy of simulation state. Projectiles and walls are server-authoritative entities; clients interpolate them, and local prediction is limited to the local player rather than predicting authoritative walls.
- Live input is sampled from action just-pressed/just-released state in `main.gd`; it is not queued between simulation steps. Basic shot, quick fire and shove are held; curve shot is release-triggered, while high jump, down dash, wall and horizontal dash are press-triggered. Jump release/repress while airborne requests recovery. Short edge presses may be missed when simulation scheduling skips their sampling interval (notably slow motion); edge buffering remains an acceptance gap.
- History tracks entity membership as well as entity state, allowing spawned/removed projectiles and walls to be represented across snapshots and replay.
- Replay format v2 is a clean break from v1 and rejects v1 files. Determinism is scoped to the same build.
- Element selection is profile/setup data carried in simulation state. No M3 final regression or all-moves network-fixture pass is claimed here.

- The implemented kit table has four elements and nine move slots (`Kits.ELEMENTS`, `Kits.SLOTS`); move fields are selected by element/slot in `Kits.move`. `InputCmd` has seven wire fields. Basic shot, quick fire and shove are held; curve shot is release-triggered, high jump/down dash/wall/horizontal dash are press-triggered, and jump release/repress while airborne requests recovery. Pitch is part of the command and drives curve-shot level/spike/lob selection and horizontal/vertical wall placement.
- Projectile spawn data applies spike/lob damage and knockback multipliers; spike/lob speed formulas, homing/curve data, shove deflection gains/caps, entity lifetimes, and wall collision are implemented in `ProjectileSim`. `World.step` remains the authoritative pure simulation. Client prediction is intentionally local movement/windup only; remote players/projectiles/walls use snapshot interpolation, with projectiles interpolated and walls selected from discrete history. Replay persistence uses format v2.
- M3 acceptance evidence is limited: `kit_test.gd`, `kit_contract_test.gd`, `kit_mobility_test.gd`, `projectile_test.gd`, `net_prediction_test.gd`, `net_session_test.gd`, and `replay_test.gd` cover these contracts in scoped tests. This does not establish a full-kit network fixture or complete per-element/per-move network proof; the README's network regression describes match flow, not all kit actions.
- Preserve for M5: expose per-move, per-element tuning in the editor; ensure dev controls and authoritative network handling cover the kit/move behaviors; and add network acceptance evidence for complete kit coverage. Do not infer or broaden the original specification beyond these explicit requirements.
