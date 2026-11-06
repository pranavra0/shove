extends SceneTree

var tuning: Node
var world_sim: GDScript
var projectile_sim: GDScript
var kits_sim: GDScript
var replay_tape: GDScript
var input_cmd: GDScript

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	tuning = root.get_node_or_null("Tuning")
	world_sim = load("res://scripts/sim/world.gd")
	projectile_sim = load("res://scripts/sim/projectiles.gd")
	kits_sim = load("res://scripts/sim/kits.gd")
	input_cmd = load("res://scripts/sim/input_cmd.gd")
	replay_tape = load("res://scripts/dev/replay.gd")
	if tuning == null or world_sim == null or not world_sim.can_instantiate() or projectile_sim == null or not projectile_sim.can_instantiate() or kits_sim == null or not kits_sim.can_instantiate() or input_cmd == null or not input_cmd.can_instantiate() or replay_tape == null or not replay_tape.can_instantiate():
		_fail("Tuning autoload and simulation/kit/replay scripts must load and parse")
		return
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		_fail("Main scene must load")
		return
	var app = packed.instantiate()
	if not app.has_method("start_match"):
		_fail("Instantiated main scene must expose start_match; refusing to access main properties on a bare scene node")
		return
	root.add_child(app)
	current_scene = app
	if app.tuning_panel == null or app.network == null or app.gizmos == null:
		_fail("Main scene must finish constructing its tuning panel, network, and development gizmos")
		app.queue_free()
		return
	app.set_physics_process(false)
	app.start_match([1])
	if not app.world is Dictionary or not app.world.has("players") or not app.world.players.has(app.local_id):
		_fail("Main scene start_match must create the local World player before the smoke proceeds")
		app.queue_free()
		return
	app.flow.phase = "playing"
	app.menu_overlay.hide()
	app.paused = false
	var start_element: String = str(app.world.players[app.local_id].element)
	app._input(_key(KEY_C))
	var cycled: String = str(app.world.players[app.local_id].element)
	if not _check(cycled != start_element and app.recording.initial_world.players[app.local_id].element == cycled, "C must cycle the local kit and begin a fresh replay segment"):
		return
	app._input(_key(KEY_V))
	if not _check(app.dummy_ids.size() == 1 and app.world.players.size() == 2, "V must spawn a real dummy player"):
		return
	var dummy_id: int = app.dummy_ids[0]
	_stage_player(app.world, app.local_id, Vector3(0.0, 0.0, 0.0))
	_stage_player(app.world, dummy_id, Vector3(0.0, 0.0, -2.4))
	app.world.players[dummy_id].yaw = PI
	app.world.events.clear()
	app._begin_recording()
	tuning.DEV_DUMMY_INTERVAL = tuning.FIXED_DELTA
	var start_tick: int = app.world.tick
	var saw_shot: bool = false
	var saw_hit: bool = false
	for i in range(80):
		app._physics_process(tuning.FIXED_DELTA)
		for projectile in app.world.projectiles.values():
			if int(projectile.owner) == dummy_id:
				saw_shot = true
		if float(app.world.players[app.local_id].damage) > 0.0:
			saw_hit = true
	var recorded_shot: bool = false
	for frame: Dictionary in app.recording.frames:
		var commands: Dictionary = frame.get("commands", {})
		if commands.has(dummy_id) and (int(commands[dummy_id].get("moves", 0)) & input_cmd.BASIC_SHOT) != 0:
			recorded_shot = true
	if not _check(saw_shot and saw_hit and recorded_shot and app.world.tick > start_tick, "Timed dummy must fire a recorded actual projectile that hits the local player"):
		return
	var local_element: String = str(app.world.players[app.local_id].element)
	var wall_move: Dictionary = kits_sim.move(local_element, "wall")
	tuning.DEV_DUMMY_INTERVAL = float(wall_move.windup) + tuning.FIXED_DELTA * 2.0
	# Start wall coverage from pristine grounded players, with no hitstun, cooldown, or active ability state.
	app.world = world_sim.create([app.local_id, dummy_id])
	world_sim.set_element(app.world, app.local_id, local_element)
	world_sim.set_element(app.world, dummy_id, "earth")
	_stage_player(app.world, app.local_id, Vector3(0.0, 0.0, 0.0))
	_stage_player(app.world, dummy_id, Vector3(0.0, 0.0, 5.0))
	app.world.players[app.local_id].yaw = PI
	app.world.players[dummy_id].yaw = 0.0
	app._dummy_elapsed[dummy_id] = 0.0
	app.yaw = PI
	app._world_time = 0.0
	app._begin_recording()
	var wall_cmd = app._capture_command(app.local_id, input_cmd.WALL, false, PI)
	app.recording.record({app.local_id: wall_cmd})
	app._capture_sim_step({app.local_id: wall_cmd})
	var wall_setup_ticks: int = ceili(float(wall_move.windup) / tuning.FIXED_DELTA) + 4
	for i in range(wall_setup_ticks):
		if not app.world.walls.is_empty():
			break
		app._physics_process(tuning.FIXED_DELTA)
	if not _check(not app.world.walls.is_empty(), "A clean grounded local player must activate its real wall move"):
		return
	tuning.DEV_DUMMY_INTERVAL = 0.05
	app._dummy_elapsed[dummy_id] = 0.0
	var saw_wall_block: bool = false
	for i in range(120):
		app._physics_process(tuning.FIXED_DELTA)
		for event: Dictionary in app.world.events:
			if str(event.get("type", "")) == "wall_block":
				saw_wall_block = true
	if not _check(saw_wall_block, "Timed dummy projectile must collide with the actual wall"):
		return
	app._input(_key(KEY_V))
	if not _check(app.dummy_ids.is_empty() and not app.world.players.has(dummy_id) and app.recording.initial_world.players.size() == 1, "V must remove the dummy and restart recording without dangling players"):
		return
	for i in range(4):
		app._physics_process(tuning.FIXED_DELTA)
	if not _check(_save_and_verify_replay(app, "user://replays/kit_dev_after_v.json"), "Replay after V removal must save and reproduce the world"):
		return
	var live_world: Dictionary = app.world.duplicate(true)
	app._input(_key(KEY_B))
	if not _check(app.gizmos.trajectory_enabled, "B must enable local preview"):
		return
	Input.action_press("move_left")
	var preview: Array = app._trajectory_preview()
	var reference: Dictionary = live_world.duplicate(true)
	var expected: Array = []
	var shot_id: int = int(reference.next_entity_id)
	var aim: Vector3 = world_sim.aim_direction(app.yaw, clampf(app.pitch, -PI * 0.5, PI * 0.5))
	var strafe: float = Input.get_axis("move_left", "move_right")
	projectile_sim.spawn_projectile(reference, app.local_id, "curve_shot", aim, strafe)
	var curve_spawned: bool = reference.projectiles.has(shot_id) and str(reference.projectiles[shot_id].behavior) == "curve"
	var ticks: int = mini(ceili(tuning.DEV_TRAJECTORY_SECONDS / tuning.FIXED_DELTA), 128)
	var samples: int = clampi(tuning.DEV_TRAJECTORY_STEPS, 2, 128)
	var stride: int = maxi(1, ceili(float(ticks) / float(samples - 1)))
	for tick in range(ticks):
		if not reference.projectiles.has(shot_id):
			break
		if tick % stride == 0 or tick == ticks - 1:
			expected.append(reference.projectiles[shot_id].position)
		reference = world_sim.step(reference, {}, tuning.FIXED_DELTA)
	if not _check(curve_spawned and preview == expected and app.world == live_world and preview.size() <= samples, "Preview must match the bounded fixed-tick curved projectile path, including World collision, without mutating live World"):
		return
	Input.action_release("move_left")
	app._input(_key(KEY_B))
	if not _check(not app.gizmos.trajectory_enabled, "B must disable local preview"):
		return
	app._dev_actions.append(KEY_F3)
	app._run_dev_actions()
	app._dev_actions.append(KEY_F3)
	app._run_dev_actions()
	if not _check(app.bot_ids.size() == 2, "F3 must add two normal offline bots"):
		return
	app._dev_actions.append(KEY_F4)
	app._run_dev_actions()
	if not _check(app.bot_ids.size() == 1 and app.world.players.size() == 2, "First F4 must remove the newest bot"):
		return
	app._dev_actions.append(KEY_F4)
	app._run_dev_actions()
	if not _check(app.bot_ids.is_empty(), "Repeated F4 must clear bot IDs; remaining %s" % str(app.bot_ids)):
		return
	if not _check(app.world.players.size() == 1, "Repeated F4 must remove the next world player; remaining %s" % str(app.world.players.keys())):
		return
	if not _check(app._match_ids.size() == 1 and int(app._match_ids[0]) == app.local_id, "Repeated F4 must remove the next match ID; remaining %s" % str(app._match_ids)):
		return
	for i in range(4):
		app._physics_process(tuning.FIXED_DELTA)
	if not _check(_save_and_verify_replay(app, "user://replays/kit_dev_after_f4.json"), "Replay after F4 removal must save and reproduce the world"):
		return
	app.queue_free()
	await process_frame
	print("PASS kit dev: C kit/replay segment, V recorded timed dummy hit/wall collision/removal, B exact strafe curve preview, F4 cleanup/replay")
	quit(0)

func _save_and_verify_replay(app: Node, path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://replays"))
	app.recording.finish(app.world)
	if app.recording.save(path) != OK:
		return false
	var loaded = replay_tape.new()
	if loaded.load_file(path) != OK:
		return false
	var replayed: Dictionary = loaded.restart()
	while loaded.has_next():
		replayed = world_sim.step(replayed, loaded.next_commands(), tuning.FIXED_DELTA)
	return replayed == app.world and loaded.final_world == app.world

func _stage_player(world: Dictionary, id: int, horizontal: Vector3) -> void:
	var position := Vector3(horizontal.x, world_sim.floor_height(horizontal) + tuning.BODY_HEIGHT * 0.5, horizontal.z)
	var player: Dictionary = world.players[id]
	player.position = position
	player.spawn = position
	player.velocity = Vector3.ZERO
	player.on_ground = true
	player.ground_angle = world_sim.floor_angle(position)

func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event

func _check(ok: bool, message: String) -> bool:
	if ok:
		return true
	_fail(message)
	return false

func _fail(message: String) -> void:
	push_error("FAIL kit dev: " + message)
	quit(1)
