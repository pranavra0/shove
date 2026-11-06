extends SceneTree

var Tuning: Node
var World: GDScript
var BotSim: GDScript
var failed: bool = false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	Tuning = root.get_node("Tuning")
	World = load("res://scripts/sim/world.gd")
	BotSim = load("res://scripts/sim/bot.gd")
	if Tuning == null or World == null or BotSim == null:
		push_error("Control bot test could not load initialized simulation dependencies")
		quit(1)
		return
	_test_split_team_and_ignore_teammates()
	_test_bot_capture_and_team_score()
	_test_zero_stock_respawn_activity()
	_test_center_fighting_determinism_and_purity()
	if failed:
		quit(1)
		return
	print("PASS control bot zone split/enemy selection/capture-score/zero-stock activity/center fight/determinism/purity")
	quit(0)

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failed = true

func _fixture() -> Dictionary:
	var world: Dictionary = World.create([1, 2, 3, 4], "control")
	for id: int in world.players:
		var player: Dictionary = world.players[id]
		player.position = Vector3(0.0, Tuning.BODY_HEIGHT * 0.5, 0.0)
		player.velocity = Vector3.ZERO
		player.on_ground = true
		player.yaw = 0.0
	return world

func _wish(cmd: InputCmd) -> Vector3:
	return Vector3(cmd.move.x, 0.0, cmd.move.y).rotated(Vector3.UP, cmd.yaw)

func _test_split_team_and_ignore_teammates() -> void:
	var world: Dictionary = _fixture()
	world.players[1].position = Vector3(0.0, Tuning.BODY_HEIGHT * 0.5, 0.0)
	world.players[3].position = Vector3(1.0, Tuning.BODY_HEIGHT * 0.5, 0.0)
	world.players[2].position = Vector3(5.0, Tuning.BODY_HEIGHT * 0.5, 0.0)
	world.players[4].position = Vector3(-5.0, Tuning.BODY_HEIGHT * 0.5, 0.0)
	var first: Dictionary = BotSim.command(world, 1, {"reaction_left": 0.0}, Tuning.FIXED_DELTA)
	var second: Dictionary = BotSim.command(world, 3, {"reaction_left": 0.0}, Tuning.FIXED_DELTA)
	_check(first.memory.target == 2 and second.memory.target == 2, "control bots must select enemies, not closer teammates")
	var zone0: Vector3 = world.control.zones[0].position
	var zone1: Vector3 = world.control.zones[1].position
	_check(_wish(first.cmd).dot(Vector3(zone0.x, 0.0, zone0.z).normalized()) > 0.5, "first teammate should split toward side zone zero")
	_check(_wish(second.cmd).dot(Vector3(zone1.x, 0.0, zone1.z).normalized()) > 0.5, "second teammate should split toward side zone one")

func _test_bot_capture_and_team_score() -> void:
	var world: Dictionary = _fixture()
	for team_rank: int in range(2):
		var id: int = 1 if team_rank == 0 else 3
		var zone: Dictionary = world.control.zones[team_rank]
		world.players[id].position = Vector3(zone.position.x, Tuning.BODY_HEIGHT * 0.5, zone.position.z)
	var memories: Dictionary = {1: {}, 3: {}}
	for frame: int in range(900):
		var commands: Dictionary = {}
		for id: int in [1, 3]:
			var decision: Dictionary = BotSim.command(world, id, memories[id], Tuning.FIXED_DELTA)
			commands[id] = decision.cmd
			memories[id] = decision.memory
		world = World.step(world, commands, Tuning.FIXED_DELTA)
		if int(world.control.zones[0].owner) == 0 and int(world.control.zones[1].owner) == 0 and float(world.control.scores[0]) > 0.0:
			break
	_check(int(world.control.zones[0].owner) == 0 and int(world.control.zones[1].owner) == 0, "bot commands must stand long enough to capture both zones through World.step")
	_check(float(world.control.scores[0]) > 0.0, "owning both bot-captured zones must advance team score")

func _test_zero_stock_respawn_activity() -> void:
	var world: Dictionary = _fixture()
	var player: Dictionary = world.players[1]
	player.stocks = 1
	player.position = Vector3(player.spawn.x, Tuning.KILL_PLANE - 1.0, player.spawn.z)
	player.velocity = Vector3.ZERO
	player.on_ground = false
	world = World.step(world, {}, Tuning.FIXED_DELTA)
	_check(int(world.players[1].stocks) == 0 and float(world.players[1].respawn_remaining) > 0.0, "real control ringout must decrement stocks and start delayed respawn")
	var frame: int = 0
	while float(world.players[1].respawn_remaining) > 0.0 and frame < 900:
		world = World.step(world, {}, Tuning.FIXED_DELTA)
		frame += 1
	player = world.players[1]
	_check(frame < 900 and float(player.respawn_remaining) == 0.0 and int(player.stocks) == 0, "zero-stock player must finish the real respawn delay")
	_check(World.is_player_active(player), "a control player must be active after a zero-stock respawn")
	var memory: Dictionary = {}
	for capture_frame: int in range(900):
		var decision: Dictionary = BotSim.command(world, 1, memory, Tuning.FIXED_DELTA)
		memory = decision.memory
		world = World.step(world, {1: decision.cmd}, Tuning.FIXED_DELTA)
		if int(world.control.zones[0].owner) == 0:
			break
	_check(int(world.players[1].stocks) == 0 and int(world.control.zones[0].owner) == 0, "respawned zero-stock bot must act through World.step and capture its side zone")

func _test_center_fighting_determinism_and_purity() -> void:
	var world: Dictionary = _fixture()
	world.control.zones[0].owner = 0
	world.control.zones[1].owner = 0
	world.players[1].position = Vector3(10.0, Tuning.BODY_HEIGHT * 0.5, 0.0)
	world.players[2].position = Vector3(0.0, Tuning.BODY_HEIGHT * 0.5, 0.0)
	world.players[3].position = Vector3(12.0, Tuning.BODY_HEIGHT * 0.5, 0.0)
	world.players[4].position = Vector3(2.0, Tuning.BODY_HEIGHT * 0.5, 0.0)
	var original: Dictionary = world.duplicate(true)
	var memory: Dictionary = {"nested": {"value": [7]}, "reaction_left": 0.0}
	var saved_memory: Dictionary = memory.duplicate(true)
	var first: Dictionary = BotSim.command(world, 1, memory, Tuning.FIXED_DELTA)
	var second: Dictionary = BotSim.command(world, 1, memory, Tuning.FIXED_DELTA)
	_check(first.cmd.to_dict() == second.cmd.to_dict() and first.memory == second.memory, "control bot decisions must be deterministic")
	_check(world == original and memory == saved_memory, "control bot decisions must not mutate world or caller memory")
	_check(first.memory.target == 4 and _wish(first.cmd).x < -0.5, "with both zones held the bot must fight toward the center and select its nearest enemy")
