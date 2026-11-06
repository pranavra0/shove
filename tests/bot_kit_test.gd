extends SceneTree

var Tuning: Node
var World: GDScript
var BotSim: GDScript
var ProjectileSim: GDScript
var original: Dictionary = {}
var failed: bool = false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	# --script starts before autoloads are ready.
	Tuning = root.get_node("Tuning")
	World = load("res://scripts/sim/world.gd")
	BotSim = load("res://scripts/sim/bot.gd")
	ProjectileSim = load("res://scripts/sim/projectiles.gd")
	for key in ["CENTER_HEIGHT", "RAMP_HEIGHT", "LEDGE_HEIGHT", "BOT_REACTION", "BOT_AIM_ERROR", "BOT_BHOP_SKILL", "BOT_DEFLECT_SKILL"]:
		original[key] = Tuning.get(key)
	Tuning.CENTER_HEIGHT = 0.0
	Tuning.RAMP_HEIGHT = 0.0
	Tuning.LEDGE_HEIGHT = 0.0
	Tuning.BOT_REACTION = 0.0
	Tuning.BOT_AIM_ERROR = 0.0
	Tuning.BOT_BHOP_SKILL = 0.0
	_test_lead()
	_test_curve_around_wall()
	_test_wall_defense()
	_test_skill_deflect()
	_test_slam()
	_test_recovery()
	_test_momentum_safe_dash()
	_test_determinism_and_purity()
	for key in original:
		Tuning.set(key, original[key])
	if failed:
		quit(1)
		return
	print("PASS kit-aware bot outcomes")
	quit(0)

func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("bot_kit_test: " + message)
	failed = true
	return false

func _world(bot_position: Vector3, enemy_position: Vector3) -> Dictionary:
	var world: Dictionary = World.create([1, 2])
	_place(world.players[1], bot_position)
	_place(world.players[2], enemy_position)
	return world

func _place(player: Dictionary, point: Vector3) -> void:
	player.position = point
	player.spawn = point
	player.velocity = Vector3.ZERO
	player.on_ground = is_equal_approx(point.y, Tuning.BODY_HEIGHT * 0.5)
	player.ground_angle = 0.0
	player.yaw = 0.0

func _bot(world: Dictionary, memory: Dictionary = {}) -> Dictionary:
	return BotSim.command(world, 1, memory, Tuning.FIXED_DELTA)

func _incoming(world: Dictionary, z: float) -> Dictionary:
	ProjectileSim.spawn_projectile(world, 2, "basic_shot", Vector3.BACK, 0.0)
	var ids: Array = world.projectiles.keys()
	var projectile: Dictionary = world.projectiles[ids.back()]
	projectile.position = Vector3(0.0, 0.9, z)
	projectile.velocity = Vector3(0.0, 0.0, 18.0)
	return projectile

func _test_lead() -> void:
	var world: Dictionary = _world(Vector3(0.0, 0.9, 0.0), Vector3(0.0, 0.9, -10.0))
	world.players[2].velocity = Vector3(4.0, 0.0, 0.0)
	var result: Dictionary = _bot(world)
	var cmd: InputCmd = result.cmd
	var memory: Dictionary = result.memory
	if not _check(World.aim_direction(cmd.yaw, cmd.pitch).x > 0.0, "moving-target aim must lead in the target's direction"):
		return
	var shot: Dictionary = {}
	for i in range(240):
		world = World.step(world, {1: cmd}, Tuning.FIXED_DELTA)
		for event in world.events:
			if event.type == "projectile_spawn" and int(event.player) == 1:
				shot = world.projectiles.get(int(event.projectile), {})
				break
		if not shot.is_empty():
			break
		var next: Dictionary = _bot(world, memory)
		cmd = next.cmd
		memory = next.memory
	if not _check(not shot.is_empty(), "bot command must produce a real projectile"):
		return
	_check(float(shot.velocity.x) > 0.0, "spawned projectile velocity must lead the moving target")

func _test_curve_around_wall() -> void:
	var world: Dictionary = _world(Vector3(0.0, 0.9, 4.0), Vector3(0.0, 0.9, -4.0))
	# Place a live, real wall on the direct firing line.
	world.players[2].position = Vector3(0.0, 0.9, -2.0)
	world.players[2].yaw = PI
	ProjectileSim.spawn_wall(world, 2, Vector3.BACK)
	var wall_id: int = int(world.walls.keys()[0])
	var wall: Dictionary = world.walls[wall_id]
	world.players[2].position = Vector3(0.0, 0.9, -4.0)
	world.players[2].yaw = 0.0
	var result: Dictionary = _bot(world)
	var cmd: InputCmd = result.cmd
	if not _check((cmd.moves & InputCmd.CURVE_SHOT) != 0, "obstructed target must select a curve shot"):
		return
	var memory: Dictionary = result.memory
	var curve_id: int = -1
	var crossed_live_wall: bool = false
	var blocked: int = 0
	for i in range(220):
		world = World.step(world, {1: cmd}, Tuning.FIXED_DELTA)
		for event in world.events:
			if event.type == "projectile_spawn" and int(event.player) == 1 and str(event.slot) == "curve_shot":
				curve_id = int(event.projectile)
			if event.type == "wall_block" and int(event.projectile) == curve_id:
				blocked += 1
		if curve_id >= 0 and world.projectiles.has(curve_id) and world.walls.has(wall_id):
			var projectile: Dictionary = world.projectiles[curve_id]
			var clearance: float = float(wall.size.x) * 0.5 + float(projectile.size)
			if projectile.position.z < wall.position.z and absf(projectile.position.x - wall.position.x) > clearance:
				crossed_live_wall = true
		if crossed_live_wall:
			break
	_check(curve_id >= 0 and crossed_live_wall and blocked == 0, "tracked curve projectile must pass the live wall plane without a wall block")

func _test_wall_defense() -> void:
	var world: Dictionary = _world(Vector3(0.0, 0.9, 0.0), Vector3(0.0, 0.9, -12.0))
	var incoming: Dictionary = _incoming(world, -5.0)
	var result: Dictionary = _bot(world)
	var cmd: InputCmd = result.cmd
	if not _check((cmd.moves & InputCmd.WALL) != 0, "incoming shot outside shove range must request a wall"):
		return
	var projectile_direction: Vector3 = (incoming.position - world.players[1].position).normalized()
	if not _check(World.aim_direction(cmd.yaw, cmd.pitch).dot(projectile_direction) > 0.9, "wall defense must aim at the projectile"):
		return
	var memory: Dictionary = result.memory
	var blocked: int = 0
	for i in range(100):
		world = World.step(world, {1: cmd}, Tuning.FIXED_DELTA)
		for event in world.events:
			if event.type == "wall_block" and int(event.projectile) == int(incoming.id):
				blocked += 1
		var next: Dictionary = _bot(world, memory)
		cmd = next.cmd
		memory = next.memory
		if blocked > 0:
			break
	_check(blocked == 1 and world.players[1].damage == 0.0, "defensive wall must actually block the incoming projectile")

func _test_skill_deflect() -> void:
	Tuning.BOT_DEFLECT_SKILL = 1.0
	var world: Dictionary = _world(Vector3(0.0, 0.9, 0.0), Vector3(0.0, 0.9, -12.0))
	var incoming: Dictionary = _incoming(world, -3.4)
	var projectile_id: int = int(incoming.id)
	var result: Dictionary = _bot(world)
	var cmd: InputCmd = result.cmd
	if not _check(cmd.shove, "skill-one bot must request timed projectile deflection"):
		return
	var aim: Vector3 = (incoming.position - world.players[1].position).normalized()
	if not _check(World.aim_direction(cmd.yaw, cmd.pitch).dot(aim) > 0.9, "deflect must aim at the incoming projectile, not its owner"):
		return
	var memory: Dictionary = result.memory
	var deflected: bool = false
	for i in range(40):
		world = World.step(world, {1: cmd}, Tuning.FIXED_DELTA)
		for event in world.events:
			if event.type == "deflect" and int(event.player) == 1:
				deflected = true
		var next: Dictionary = _bot(world, memory)
		if i == 0:
			var active_projectile: Dictionary = world.projectiles.get(projectile_id, {})
			var continued_aim: Vector3 = World.aim_direction(next.cmd.yaw, next.cmd.pitch)
			var projectile_direction: Vector3 = (active_projectile.position - world.players[1].position).normalized()
			if not _check(float(world.players[1].attack_time) > Tuning.SHOVE_ACTIVE and next.cmd.moves == 0 and continued_aim.dot(projectile_direction) > 0.9, "bot must preserve projectile aim without a competing move during shove windup"):
				return
		cmd = next.cmd
		memory = next.memory
		if deflected:
			break
	if not _check(deflected and world.projectiles.has(projectile_id) and int(world.projectiles[projectile_id].owner) == 1, "deflection must transfer the live projectile to bot ownership"):
		return
	Tuning.BOT_DEFLECT_SKILL = 0.0
	world = _world(Vector3(0.0, 0.9, 0.0), Vector3(0.0, 0.9, -12.0))
	incoming = _incoming(world, -5.0)
	result = _bot(world)
	cmd = result.cmd
	if not _check(not cmd.shove and (cmd.moves & InputCmd.WALL) != 0, "skill-zero bot must choose wall defense rather than request deflection"):
		return
	var wall_blocked: bool = false
	memory = result.memory
	for i in range(100):
		world = World.step(world, {1: cmd}, Tuning.FIXED_DELTA)
		for event in world.events:
			if event.type == "wall_block" and int(event.projectile) == int(incoming.id):
				wall_blocked = true
		var defense_step: Dictionary = _bot(world, memory)
		cmd = defense_step.cmd
		memory = defense_step.memory
		if wall_blocked:
			break
	_check(wall_blocked, "skill-zero defense must still let its actual wall block the shot")

func _test_slam() -> void:
	var world: Dictionary = _world(Vector3(0.0, 3.0, 0.0), Vector3(0.0, 0.9, 0.0))
	world.players[1].on_ground = false
	world.players[1].velocity = Vector3.ZERO
	var result: Dictionary = _bot(world)
	var cmd: InputCmd = result.cmd
	if not _check((cmd.moves & InputCmd.DOWN_DASH) != 0, "airborne bot above a grounded enemy must request slam"):
		return
	var memory: Dictionary = result.memory
	var hits: int = 0
	for i in range(120):
		world = World.step(world, {1: cmd}, Tuning.FIXED_DELTA)
		for event in world.events:
			if event.type == "hit" and int(event.attacker) == 1 and int(event.player) == 2 and str(event.get("source", "")) == "down_dash":
				hits += 1
		var next: Dictionary = _bot(world, memory)
		cmd = next.cmd
		memory = next.memory
		if hits > 0:
			break
	_check(hits > 0 and world.players[2].damage > 0.0, "slam must land and damage the grounded enemy")

func _test_recovery() -> void:
	for element in ["earth", "water", "fire", "air"]:
		var world: Dictionary = _world(Vector3(Tuning.PLATFORM_SIZE * 0.5 + 1.5, -1.0, 0.0), Vector3(0.0, 0.9, 0.0))
		World.set_element(world, 1, element)
		world.players[1].on_ground = false
		world.players[1].velocity = Vector3(2.0, -4.0, 0.0)
		var result: Dictionary = _bot(world)
		var cmd: InputCmd = result.cmd
		if not _check((cmd.moves & InputCmd.RECOVERY) != 0, "%s offstage bot must request recovery" % element):
			return
		var memory: Dictionary = result.memory
		var landed: bool = false
		var ko: bool = false
		for i in range(360):
			world = World.step(world, {1: cmd}, Tuning.FIXED_DELTA)
			for event in world.events:
				if event.type == "land" and int(event.player) == 1:
					landed = true
				if event.type == "ko" and int(event.player) == 1:
					ko = true
			var next: Dictionary = _bot(world, memory)
			cmd = next.cmd
			memory = next.memory
			if landed or ko:
				break
		if not _check(landed and not ko and world.players[1].stocks > 0, "%s recovery must land before KO" % element):
			return
		var player_position: Vector3 = world.players[1].position
		if not _check(absf(player_position.x) <= Tuning.PLATFORM_SIZE * 0.5 and absf(player_position.z) <= Tuning.PLATFORM_SIZE * 0.5, "%s recovery must return inside safe stage bounds" % element):
			return

func _test_momentum_safe_dash() -> void:
	var edge: float = Tuning.PLATFORM_SIZE * 0.5 - Tuning.BODY_RADIUS - Tuning.BOT_EDGE_MARGIN - 0.1
	var world: Dictionary = _world(Vector3(edge, 4.0, 0.0), Vector3(-12.0, 0.9, 0.0))
	World.set_element(world, 1, "air")
	world.players[1].on_ground = false
	world.players[1].velocity = Vector3(30.0, 0.0, 0.0)
	var cmd: InputCmd = _bot(world).cmd
	if not _check((cmd.moves & InputCmd.H_DASH) == 0, "air dash must not inherit outward momentum into an offstage endpoint"):
		return
	world = World.step(world, {1: cmd}, Tuning.FIXED_DELTA)
	var dash_moves: int = 0
	for event in world.events:
		if event.type == "move" and int(event.player) == 1 and str(event.slot) == "h_dash":
			dash_moves += 1
	_check(dash_moves == 0 and world.players[1].stocks > 0 and absf(world.players[1].position.x) < Tuning.PLATFORM_SIZE * 0.5, "safe dash refusal must keep the actual player onstage")

func _test_determinism_and_purity() -> void:
	var world: Dictionary = _world(Vector3(0.0, 0.9, 4.0), Vector3(2.0, 0.9, -4.0))
	world.players[2].velocity = Vector3(1.0, 0.0, 0.0)
	var original_world: Dictionary = world.duplicate(true)
	var memory: Dictionary = {"seed": 12345, "reaction_left": 0.0}
	var original_memory: Dictionary = memory.duplicate(true)
	var first: Dictionary = BotSim.command(world, 1, memory, Tuning.FIXED_DELTA)
	var second: Dictionary = BotSim.command(world, 1, memory, Tuning.FIXED_DELTA)
	_check(first.cmd.to_dict() == second.cmd.to_dict() and first.memory == second.memory, "same world and memory must reproduce command and memory")
	_check(world == original_world and memory == original_memory, "command selection must not mutate input world or caller-owned memory")
