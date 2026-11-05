extends SceneTree

var Tuning: Node
var World: GDScript
var BotSim: GDScript
var MatchSim: GDScript

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	Tuning = root.get_node("Tuning")
	World = load("res://scripts/sim/world.gd")
	BotSim = load("res://scripts/sim/bot.gd")
	MatchSim = load("res://scripts/sim/match.gd")
	_test_bot_determinism_and_purity()
	_test_nearest_live_enemy_and_reaction()
	_test_aim_error()
	_test_stock_aware_edges_and_recovery()
	_test_bhop_and_air_strafe_skill()
	_test_countdown_and_idle_phases()
	_test_ringout_consumed_once()
	_test_winner_draw_and_rematch()
	_test_solo_practice()
	print("PASS bot deterministic/pure/nearest/reaction/aim/edge/recovery/bhop/strafe match countdown/KO-once/round-end/winner/draw/rematch/practice")
	call_deferred("quit", 0)

func _fixture(ids: Array = [1, 2, 3]) -> Dictionary:
	var world: Dictionary = World.create(ids)
	for index in range(ids.size()):
		var player: Dictionary = world.players[ids[index]]
		player.position = Vector3(index * 4.0, Tuning.BODY_HEIGHT * 0.5, 6.0)
		player.velocity = Vector3.ZERO
		player.on_ground = true
		player.yaw = 0.0
	return world

func _decide(world: Dictionary, memory: Dictionary = {}) -> Dictionary:
	return BotSim.command(world, 1, memory, Tuning.BOT_REACTION + 0.000001)

func _wish(cmd: InputCmd) -> Vector3:
	return Vector3(cmd.move.x, 0.0, cmd.move.y).rotated(Vector3.UP, cmd.yaw)

func _same_command(a: InputCmd, b: InputCmd) -> void:
	assert(a.move == b.move and a.jump == b.jump and a.shove == b.shove)
	assert(a.yaw == b.yaw and a.tick == b.tick)

func _test_bot_determinism_and_purity() -> void:
	var world: Dictionary = _fixture()
	var original: Dictionary = world.duplicate(true)
	var memory := {"nested": {"marker": [1, 2]}}
	var saved: Dictionary = memory.duplicate(true)
	var first: Dictionary = _decide(world, memory)
	var second: Dictionary = _decide(world, memory)
	_same_command(first.cmd, second.cmd)
	assert(first.memory == second.memory and memory == saved and world == original)
	first.memory.nested.marker.append(3)
	assert(memory == saved and second.memory.nested.marker == [1, 2])
	var a: Dictionary = world
	var b: Dictionary = world.duplicate(true)
	var ma: Dictionary = {}
	var mb: Dictionary = {}
	for frame in range(96):
		var ca: Dictionary = BotSim.command(a, 1, ma, Tuning.FIXED_DELTA)
		var cb: Dictionary = BotSim.command(b, 1, mb, Tuning.FIXED_DELTA)
		_same_command(ca.cmd, cb.cmd)
		assert(ca.cmd.tick == int(a.tick) + 1)
		ma = ca.memory
		mb = cb.memory
		a = World.step(a, {1: ca.cmd}, Tuning.FIXED_DELTA)
		b = World.step(b, {1: cb.cmd}, Tuning.FIXED_DELTA)
		assert(a == b and ma == mb)
	world.players[1].stocks = 0
	var inactive: Dictionary = _decide(world, saved)
	assert(inactive.cmd.move == Vector2.ZERO and not inactive.cmd.jump and not inactive.cmd.shove)
	var missing: Dictionary = BotSim.command(world, 99, saved, Tuning.FIXED_DELTA)
	assert(missing.cmd.move == Vector2.ZERO and missing.memory == saved)

func _test_nearest_live_enemy_and_reaction() -> void:
	var world: Dictionary = _fixture([1, 2, 3, 4])
	world.players[2].position = world.players[1].position + Vector3.RIGHT
	world.players[2].stocks = 0
	world.players[3].position = world.players[1].position + Vector3.RIGHT * 3.0
	world.players[4].position = world.players[1].position + Vector3.LEFT * 3.0
	var waiting: Dictionary = BotSim.command(world, 1, {}, 0.0)
	assert(waiting.cmd.move == Vector2.ZERO)
	var chosen: Dictionary = _decide(world)
	assert(chosen.memory.target == 3 and _wish(chosen.cmd).x > 0.99)
	world.players[4].position = world.players[1].position + Vector3.LEFT
	var delayed: Dictionary = BotSim.command(world, 1, chosen.memory, Tuning.BOT_REACTION * 0.5)
	assert(delayed.memory.target == 3 and delayed.cmd.yaw == chosen.cmd.yaw)
	var reacted: Dictionary = _decide(world, delayed.memory)
	assert(reacted.memory.target == 4 and _wish(reacted.cmd).x < -0.99)
	world.players[4].stocks = 0
	var lost: Dictionary = BotSim.command(world, 1, reacted.memory, 0.0)
	assert(lost.memory.target == 3)
	world.players[3].stocks = 0
	var alone: Dictionary = _decide(world, lost.memory)
	assert(alone.memory.target == -1 and alone.cmd.move == Vector2.ZERO and not alone.cmd.shove)

func _test_aim_error() -> void:
	var old_error: float = Tuning.BOT_AIM_ERROR
	var world: Dictionary = _fixture([1, 2])
	world.players[2].position = world.players[1].position + Vector3.FORWARD * 1.5
	Tuning.BOT_AIM_ERROR = 0.0
	var exact: Dictionary = _decide(world)
	assert(is_zero_approx(exact.cmd.yaw) and exact.cmd.shove)
	Tuning.BOT_AIM_ERROR = 0.1
	var noisy: Dictionary = _decide(world)
	var repeated: Dictionary = _decide(world)
	assert(absf(noisy.cmd.yaw) <= Tuning.BOT_AIM_ERROR and not is_zero_approx(noisy.cmd.yaw))
	_same_command(noisy.cmd, repeated.cmd)
	Tuning.BOT_AIM_ERROR = old_error

func _test_stock_aware_edges_and_recovery() -> void:
	var world: Dictionary = _fixture([1, 2])
	var limit: float = Tuning.PLATFORM_SIZE * 0.5 - Tuning.BODY_RADIUS - Tuning.BOT_EDGE_MARGIN
	world.players[1].position.x = limit + Tuning.BOT_EDGE_MARGIN * 0.1
	world.players[2].position.x = Tuning.PLATFORM_SIZE * 0.5 - Tuning.BODY_RADIUS
	world.players[1].stocks = Tuning.BOT_SAFE_STOCKS
	var careful: Dictionary = _decide(world)
	assert(_wish(careful.cmd).x < -0.99 and not careful.cmd.jump)
	world.players[1].stocks = Tuning.BOT_SAFE_STOCKS + 1
	var bold: Dictionary = _decide(world)
	assert(_wish(bold.cmd).x > 0.99)
	world.players[1].position = Vector3(0.0, 5.0, Tuning.BOT_RECOVER_RADIUS + 2.0)
	world.players[1].on_ground = false
	world.players[2].position = world.players[1].position + Vector3.BACK * 2.0
	var recovery: Dictionary = _decide(world)
	assert(_wish(recovery.cmd).z < -0.99 and not recovery.cmd.shove and not recovery.cmd.jump)
	world.players[1].position = Vector3(-Tuning.BOT_RECOVER_RADIUS - 2.0, 5.0, 0.0)
	world.players[2].position = world.players[1].position + Vector3.LEFT * 2.0
	recovery = _decide(world)
	assert(_wish(recovery.cmd).x > 0.99)
	# Outward momentum must be counter-steered even before the body reaches the margin.
	world.players[1].position = Vector3(limit - 0.5, 0.9, 6.0)
	world.players[1].velocity = Vector3.RIGHT * 20.0
	world.players[1].on_ground = true
	world.players[1].stocks = Tuning.BOT_SAFE_STOCKS
	world.players[2].position = Vector3(0.0, 0.9, 6.0)
	assert(_wish(_decide(world).cmd).x < 0.0)

func _test_bhop_and_air_strafe_skill() -> void:
	var skill: float = Tuning.BOT_BHOP_SKILL
	var world: Dictionary = _fixture([1, 2])
	world.players[2].position = world.players[1].position + Vector3.FORWARD * 4.0
	Tuning.BOT_BHOP_SKILL = 0.0
	var novice: Dictionary = _decide(world)
	assert(not novice.cmd.jump)
	Tuning.BOT_BHOP_SKILL = 1.0
	var expert: Dictionary = _decide(world)
	assert(expert.cmd.jump)
	world.players[1].on_ground = false
	world.players[1].velocity = Vector3.FORWARD * 12.0
	Tuning.BOT_BHOP_SKILL = 0.0
	novice = _decide(world)
	assert(_wish(novice.cmd).dot(Vector3.FORWARD) > 0.99)
	Tuning.BOT_BHOP_SKILL = 1.0
	# Use the fixed tick for the actual air-acceleration projection calculation.
	expert = BotSim.command(world, 1, {"reaction_left": 0.0}, Tuning.FIXED_DELTA)
	var wish: Vector3 = _wish(expert.cmd)
	assert(absf(wish.x) > 0.5 and not expert.cmd.jump)
	assert(world.players[1].velocity.dot(wish) < Tuning.AIR_SPEED_CAP)
	Tuning.BOT_BHOP_SKILL = skill

func _playing() -> Dictionary:
	var flow: Dictionary = MatchSim.create()
	flow.phase = "playing"
	return flow

func _test_countdown_and_idle_phases() -> void:
	var world: Dictionary = _fixture()
	var before: Dictionary = world.duplicate(true)
	var flow: Dictionary = MatchSim.create()
	assert(flow.phase == "menu" and flow.winner == -1 and flow.elapsed == 0.0)
	assert(MatchSim.step(flow, world, 10.0) == flow)
	flow.phase = "setup"
	assert(MatchSim.step(flow, world, 10.0) == flow)
	flow.phase = "countdown"
	var saved: Dictionary = flow.duplicate(true)
	var starting: Dictionary = MatchSim.step(flow, world, 0.0)
	assert(flow == saved and starting.countdown == int(ceil(Tuning.MATCH_COUNTDOWN)))
	var frames: int = int(round(Tuning.MATCH_COUNTDOWN / Tuning.FIXED_DELTA))
	for frame in range(frames - 1):
		flow = MatchSim.step(flow, world, Tuning.FIXED_DELTA)
		assert(flow.phase == "countdown")
		assert(flow.countdown == int(ceil(Tuning.MATCH_COUNTDOWN - flow.elapsed)))
	assert(flow.countdown == 1)
	flow = MatchSim.step(flow, world, Tuning.FIXED_DELTA)
	assert(flow.phase == "playing" and flow.countdown == 0 and flow.elapsed == 0.0)
	assert(world == before and world.tick == 0)

func _test_ringout_consumed_once() -> void:
	var world: Dictionary = _fixture()
	world.players[2].position.y = Tuning.KILL_PLANE - 1.0
	world = World.step(world, {}, Tuning.FIXED_DELTA)
	assert(world.events.any(func(event: Dictionary) -> bool: return event.type == "ko"))
	var flow: Dictionary = _playing()
	var original: Dictionary = flow.duplicate(true)
	var world_before: Dictionary = world.duplicate(true)
	flow = MatchSim.step(flow, world, Tuning.FIXED_DELTA)
	assert(flow.phase == "ringout" and flow.resume_phase == "playing" and flow.elapsed == 0.0)
	assert(original.phase == "playing" and world == world_before)
	flow = MatchSim.step(flow, world, Tuning.MATCH_RINGOUT_TIME * 0.5)
	assert(flow.phase == "ringout" and flow.elapsed > 0.0)
	flow = MatchSim.step(flow, world, Tuning.MATCH_RINGOUT_TIME * 0.5)
	assert(flow.phase == "playing")
	flow = MatchSim.step(flow, world, Tuning.FIXED_DELTA)
	assert(flow.phase == "playing" and flow.last_event_tick == world.tick)
	# A new tick's KO is a fresh event, even while already presenting a ringout.
	world.tick += 1
	flow = MatchSim.step(flow, world, Tuning.FIXED_DELTA)
	assert(flow.phase == "ringout" and flow.elapsed == 0.0)

func _test_winner_draw_and_rematch() -> void:
	var world: Dictionary = _fixture([1, 2])
	world.players[2].stocks = 1
	world.players[2].position.y = Tuning.KILL_PLANE - 1.0
	world = World.step(world, {}, Tuning.FIXED_DELTA)
	var flow: Dictionary = MatchSim.step(_playing(), world, Tuning.FIXED_DELTA)
	assert(flow.phase == "ringout" and flow.resume_phase == "round_end" and flow.winner == -1)
	flow = MatchSim.step(flow, world, Tuning.MATCH_RINGOUT_TIME)
	assert(flow.phase == "round_end" and flow.winner == 1 and flow.elapsed == 0.0)
	flow = MatchSim.step(flow, world, Tuning.MATCH_ROUND_END * 0.5)
	assert(flow.phase == "round_end")
	flow = MatchSim.step(flow, world, Tuning.MATCH_ROUND_END * 0.5)
	assert(flow.phase == "winner" and flow.winner == 1)
	assert(MatchSim.step(flow, world, 100.0) == flow)
	var rematch: Dictionary = MatchSim.create()
	assert(rematch.phase == "menu" and rematch.winner == -1 and rematch.last_event_tick == -1)
	assert(World.create([1, 2]).players[2].stocks == Tuning.STOCKS)
	world = _fixture([1, 2])
	for id in world.players:
		world.players[id].stocks = 1
		world.players[id].position.y = Tuning.KILL_PLANE - 1.0
	world = World.step(world, {}, Tuning.FIXED_DELTA)
	flow = MatchSim.step(_playing(), world, Tuning.FIXED_DELTA)
	assert(flow.phase == "ringout")
	flow = MatchSim.step(flow, world, Tuning.MATCH_RINGOUT_TIME)
	assert(flow.phase == "round_end" and flow.winner == -1)
	flow = MatchSim.step(flow, world, Tuning.MATCH_ROUND_END)
	assert(flow.phase == "winner" and flow.winner == -1)
	# A restored terminal World without events must still reach a result.
	world.events = []
	flow = MatchSim.step(_playing(), world, Tuning.FIXED_DELTA)
	assert(flow.phase == "round_end" and flow.winner == -1)

func _test_solo_practice() -> void:
	var world: Dictionary = _fixture([1])
	var flow: Dictionary = MatchSim.step(_playing(), world, Tuning.FIXED_DELTA)
	assert(flow.phase == "playing")
	world.players[1].stocks = 2
	world.players[1].position.y = Tuning.KILL_PLANE - 1.0
	world = World.step(world, {}, Tuning.FIXED_DELTA)
	flow = MatchSim.step(flow, world, Tuning.FIXED_DELTA)
	assert(flow.phase == "ringout" and flow.resume_phase == "playing")
	flow = MatchSim.step(flow, world, Tuning.MATCH_RINGOUT_TIME)
	assert(flow.phase == "playing")
	world.players[1].stocks = 0
	world.tick += 1
	world.events = [{"type": "ko", "player": 1}]
	flow = MatchSim.step(flow, world, Tuning.FIXED_DELTA)
	assert(flow.phase == "ringout" and flow.resume_phase == "round_end")
	flow = MatchSim.step(flow, world, Tuning.MATCH_RINGOUT_TIME)
	assert(flow.phase == "round_end" and flow.winner == -1)
