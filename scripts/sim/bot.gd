class_name BotSim
extends RefCounted

# Memory is caller-owned. Decisions sample on a reaction clock; safety steering is immediate.
static func command(world: Dictionary, id: int, memory: Dictionary, dt: float) -> Dictionary:
	var next: Dictionary = memory.duplicate(true)
	var tick: int = int(world.tick) + 1
	if not world.players.has(id) or world.players[id].stocks <= 0:
		return {"cmd": InputCmd.new(Vector2.ZERO, false, false, 0.0, tick), "memory": next}
	var player: Dictionary = world.players[id]
	var remaining: float = float(next.get("reaction_left", Tuning.BOT_REACTION)) - maxf(dt, 0.0)
	var target: int = int(next.get("target", -1))
	var lost_target: bool = target != -1 and (not world.players.has(target) or world.players[target].stocks <= 0)
	if remaining <= 0.0 or lost_target:
		target = _nearest_enemy(world.players, id)
		next.target = target
		next.seed = int(next.get("seed", posmod(id * 97 + 17, 65521)))
		var aim_sample: float = _sample(next)
		next.bhop = _sample(next) < clampf(Tuning.BOT_BHOP_SKILL, 0.0, 1.0)
		var direction := Vector3.ZERO
		var reaction_yaw: float = player.yaw
		if target != -1:
			direction = world.players[target].position - player.position
			direction.y = 0.0
			if direction.length_squared() > 0.0:
				direction = direction.normalized()
				reaction_yaw = atan2(-direction.x, -direction.z) + (aim_sample * 2.0 - 1.0) * Tuning.BOT_AIM_ERROR
		next.direction = direction
		next.yaw = reaction_yaw
		remaining = maxf(Tuning.BOT_REACTION, 0.0)
	next.reaction_left = remaining
	var desired: Vector3 = next.get("direction", Vector3.ZERO)
	var yaw: float = float(next.get("yaw", player.yaw))
	var position: Vector3 = player.position
	var horizontal := Vector3(player.velocity.x, 0.0, player.velocity.z)
	var recovering: bool = not player.on_ground and Vector2(position.x, position.z).length() > Tuning.BOT_RECOVER_RADIUS
	if recovering:
		desired = Vector3(-position.x, 0.0, -position.z).normalized()
	var margin: float = Tuning.BOT_EDGE_MARGIN
	if player.stocks > Tuning.BOT_SAFE_STOCKS:
		margin *= 0.5
	var safe_limit: float = maxf(0.0, Tuning.PLATFORM_SIZE * 0.5 - Tuning.BODY_RADIUS - margin)
	var predicted: Vector3 = position + horizontal * maxf(Tuning.BOT_REACTION, dt)
	var avoiding_edge: bool = false
	if absf(predicted.x) >= safe_limit and (desired.x * predicted.x > 0.0 or horizontal.x * predicted.x > 0.0):
		desired.x = -signf(predicted.x)
		avoiding_edge = true
	if absf(predicted.z) >= safe_limit and (desired.z * predicted.z > 0.0 or horizontal.z * predicted.z > 0.0):
		desired.z = -signf(predicted.z)
		avoiding_edge = true
	if not player.on_ground and not recovering and not avoiding_edge and desired.length_squared() > 0.0:
		desired = _air_strafe(desired, horizontal, dt)
	if desired.length_squared() > 1.0:
		desired = desired.normalized()
	var local_move: Vector3 = desired.rotated(Vector3.UP, -yaw)
	var jump: bool = bool(next.get("bhop", false)) and player.on_ground and desired.length_squared() > 0.0 and not avoiding_edge
	var shove: bool = false
	if target != -1 and world.players.has(target) and world.players[target].stocks > 0 and not recovering:
		var offset: Vector3 = world.players[target].position - position
		var facing: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, yaw)
		shove = offset.length_squared() <= Tuning.BOT_SHOVE_RANGE * Tuning.BOT_SHOVE_RANGE and facing.dot(offset) > 0.0
	return {"cmd": InputCmd.new(Vector2(local_move.x, local_move.z), jump, shove, yaw, tick), "memory": next}

static func _nearest_enemy(players: Dictionary, id: int) -> int:
	var ids: Array = players.keys()
	ids.sort()
	var target: int = -1
	var nearest: float = INF
	for candidate in ids:
		if candidate == id or players[candidate].stocks <= 0:
			continue
		var distance: float = players[id].position.distance_squared_to(players[candidate].position)
		if distance < nearest:
			nearest = distance
			target = candidate
	return target

static func _sample(memory: Dictionary) -> float:
	memory.seed = posmod(int(memory.seed) * 75 + 74, 65521)
	return float(memory.seed) / 65521.0

static func _air_strafe(desired: Vector3, velocity: Vector3, dt: float) -> Vector3:
	var speed: float = velocity.length()
	var skill: float = clampf(Tuning.BOT_BHOP_SKILL, 0.0, 1.0)
	if speed <= Tuning.AIR_SPEED_CAP or skill <= 0.0:
		return desired
	# Aim just below the air projection cap, leaving room for this tick's acceleration.
	var acceleration: float = Tuning.AIR_ACCELERATION * Tuning.AIR_SPEED_CAP * maxf(dt, 0.0)
	var angle: float = acos(clampf((Tuning.AIR_SPEED_CAP - acceleration) / speed, 0.0, 1.0))
	var forward: Vector3 = velocity / speed
	var left: Vector3 = forward.rotated(Vector3.UP, angle)
	var right: Vector3 = forward.rotated(Vector3.UP, -angle)
	var strafe: Vector3 = left if left.dot(desired) >= right.dot(desired) else right
	return desired.lerp(strafe, skill).normalized()
