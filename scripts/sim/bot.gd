class_name BotSim
extends RefCounted

# Memory is caller-owned. Decisions sample on a reaction clock; safety steering is immediate.
static func command(world: Dictionary, id: int, memory: Dictionary, dt: float) -> Dictionary:
	var next: Dictionary = memory.duplicate(true)
	var tick: int = int(world.tick) + 1
	if not world.players.has(id) or world.players[id].stocks <= 0:
		return {"cmd": InputCmd.new(Vector2.ZERO, false, false, 0.0, tick), "memory": next}
	var player: Dictionary = world.players[id]
	next.seed = int(next.get("seed", posmod(id * 97 + 17, 65521)))
	var remaining: float = float(next.get("reaction_left", Tuning.BOT_REACTION)) - maxf(dt, 0.0)
	var target: int = int(next.get("target", -1))
	var lost_target: bool = target != -1 and (not world.players.has(target) or world.players[target].stocks <= 0)
	if remaining <= 0.0 or lost_target:
		target = _nearest_enemy(world.players, id)
		next.target = target
		var aim_sample: float = _sample(next)
		next.bhop = _sample(next) < clampf(Tuning.BOT_BHOP_SKILL, 0.0, 1.0)
		var direction := Vector3.ZERO
		var reaction_yaw: float = player.yaw
		var reaction_pitch: float = 0.0
		if target != -1:
			var enemy: Dictionary = world.players[target]
			direction = enemy.position - player.position
			direction.y = 0.0
			if direction.length_squared() > 0.0:
				var dist: float = player.position.distance_to(enemy.position)
				var shot: Dictionary = Kits.move(str(player.element), "basic_shot")
				var lead: float = minf(dist / maxf(float(shot.speed), 0.001), Tuning.BOT_LEAD_LIMIT) * Tuning.BOT_AIM_LEAD
				var aim_delta: Vector3 = enemy.position + enemy.velocity * lead - player.position
				var horizontal_dist: float = Vector2(aim_delta.x, aim_delta.z).length()
				reaction_yaw = atan2(-aim_delta.x, -aim_delta.z) + (aim_sample * 2.0 - 1.0) * Tuning.BOT_AIM_ERROR
				reaction_pitch = clampf(atan2(aim_delta.y, horizontal_dist), -Tuning.BOT_AIM_PITCH_MAX, Tuning.BOT_AIM_PITCH_MAX)
				direction = direction.normalized()
		next.direction = direction
		next.yaw = reaction_yaw
		next.pitch = reaction_pitch
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
		desired = _air_strafe(desired, horizontal, dt, float(Kits.movement(str(player.element)).air_accel))
	if desired.length_squared() > 1.0:
		desired = desired.normalized()
	var local_move: Vector3 = desired.rotated(Vector3.UP, -yaw)
	var jump: bool = bool(next.get("bhop", false)) and player.on_ground and desired.length_squared() > 0.0 and not avoiding_edge
	var cmd := InputCmd.new(Vector2(local_move.x, local_move.z), jump, false, yaw, tick)
	cmd.pitch = float(next.get("pitch", 0.0))
	if float(player.hitstun) <= 0.0 and player.move_state.is_empty():
		_kit_intent(world, id, player, target, cmd, next, dt, safe_limit, recovering, avoiding_edge)
	return {"cmd": cmd, "memory": next}

static func _kit_intent(world: Dictionary, id: int, player: Dictionary, target: int, cmd: InputCmd, memory: Dictionary, dt: float, safe_limit: float, recovering: bool, avoiding_edge: bool) -> void:
	var movement_world: Vector3 = Vector3(cmd.move.x, 0.0, cmd.move.y).rotated(Vector3.UP, cmd.yaw)
	var element: String = str(player.element)
	var edge_limit: float = Tuning.PLATFORM_SIZE * 0.5 - Tuning.BODY_RADIUS
	var offstage: bool = not player.on_ground and (absf(player.position.x) > edge_limit or absf(player.position.z) > edge_limit)
	var recover_timer: float = maxf(0.0, float(memory.get("recovery_timer", 0.0)) - maxf(dt, 0.0))
	if offstage and int(player.recovery_used) < Kits.recovery_uses(element) and _ready(player, "recovery") and player.velocity.y <= Tuning.BOT_RECOVERY_TRIGGER_Y and recover_timer <= 0.0:
		cmd.moves = InputCmd.RECOVERY
		cmd.shove = false
		cmd.yaw = atan2(player.position.x, player.position.z)
		cmd.pitch = Tuning.BOT_RECOVERY_PITCH
		cmd.move = Vector2(0.0, -1.0)
		memory.recovery_timer = Tuning.BOT_RECOVERY_REPEAT
		return
	memory.recovery_timer = recover_timer
	var threat: Dictionary = _incoming(world, id, player)
	if not threat.is_empty():
		var t: float = float(threat.time)
		var shove: Dictionary = Kits.move(str(player.element), "shove")
		var deflect_time: float = float(shove.windup) + (float(shove.reach) + float(shove.size)) / maxf(float(threat.speed), 0.001) + Tuning.BOT_DEFLECT_EARLY
		var threat_id: int = int(threat.id)
		var deflect_gate: bool = bool(memory.get("deflect_gate", false))
		if int(memory.get("deflect_threat", -1)) != threat_id:
			memory.deflect_threat = threat_id
			deflect_gate = _sample(memory) < clampf(Tuning.BOT_DEFLECT_SKILL, 0.0, 1.0)
			memory.deflect_gate = deflect_gate
		if int(memory.get("deflect_attempt", -1)) == threat_id and not _ready_shove(player):
			# Preserve the committed shove's aim throughout windup and active frames;
			# a wall request here can intercept the same shot before it is deflected.
			cmd.moves = 0
			cmd.move = Vector2.ZERO
			_aim_at(cmd, player.position, threat.position)
			return
		if _ready_shove(player) and t <= deflect_time and deflect_gate:
			memory.deflect_attempt = threat_id
			cmd.shove = true
			cmd.moves = 0
			cmd.move = Vector2.ZERO
			_aim_at(cmd, player.position, threat.position)
			return
		if t > float(Kits.move(element, "wall").windup) and _ready(player, "wall"):
			cmd.moves = InputCmd.WALL
			cmd.shove = false
			cmd.move = Vector2.ZERO
			_aim_at(cmd, player.position, threat.position)
			cmd.pitch = 0.0
			return
	if target == -1 or not world.players.has(target) or world.players[target].stocks <= 0:
		return
	var enemy: Dictionary = world.players[target]
	var offset: Vector3 = enemy.position - player.position
	var distance: float = Vector2(offset.x, offset.z).length()
	if not player.on_ground and enemy.on_ground and player.position.y - enemy.position.y >= Tuning.BOT_SLAM_HEIGHT and distance <= float(Kits.move(element, "down_dash").slam_radius) and _ready(player, "down_dash"):
		cmd.moves = InputCmd.DOWN_DASH
		cmd.move = Vector2.ZERO
		cmd.shove = false
		return
	if player.on_ground and enemy.position.y - player.position.y >= Tuning.BOT_HIGH_JUMP_HEIGHT and distance <= Tuning.BOT_HIGH_JUMP_RANGE and _ready(player, "high_jump"):
		cmd.moves = InputCmd.HIGH_JUMP
		cmd.move = Vector2.ZERO
		return
	if distance > Tuning.BOT_DASH_RANGE and _ready(player, "h_dash"):
		var dash: Dictionary = Kits.move(element, "h_dash")
		var dash_direction: Vector3 = Vector3(-sin(cmd.yaw), 0.0, -cos(cmd.yaw))
		var dash_velocity: Vector3 = dash_direction * float(dash.speed)
		var preserve: float = float(dash.preserve_momentum)
		if preserve > 0.0:
			dash_velocity = Vector3(player.velocity.x, 0.0, player.velocity.z) + dash_velocity * preserve
		var endpoint: Vector3 = player.position + dash_velocity * float(dash.active)
		if absf(endpoint.x) < safe_limit and absf(endpoint.z) < safe_limit:
			cmd.moves = InputCmd.H_DASH
			return
	if _ready(player, "quick_fire") and distance <= Tuning.BOT_QUICK_RANGE:
		cmd.moves = InputCmd.QUICK_FIRE
	elif _ready(player, "basic_shot"):
		cmd.moves = InputCmd.BASIC_SHOT
	if not recovering and not avoiding_edge and cmd.moves != 0 and _wall_obstructs(world, player.position, enemy.position) and _ready(player, "curve_shot"):
		cmd.moves = InputCmd.CURVE_SHOT
		cmd.move.x = -1.0 if posmod(id, 2) == 0 else 1.0
		_curve_aim(world, player.position, enemy.position, cmd, id, element)
		var local_preserved: Vector3 = movement_world.rotated(Vector3.UP, -cmd.yaw)
		cmd.move.y = clampf(local_preserved.z, -1.0, 1.0)
		if cmd.move.length_squared() > 1.0:
			cmd.move = cmd.move.normalized()
	var facing: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, cmd.yaw)
	if not recovering and distance <= Tuning.BOT_SHOVE_RANGE and facing.dot(offset) > 0.0:
		cmd.shove = true

static func _curve_aim(world: Dictionary, origin: Vector3, enemy: Vector3, cmd: InputCmd, id: int, element: String) -> void:
	var line: Vector3 = enemy - origin
	var side: Vector3 = Vector3(-line.z, 0.0, line.x).normalized()
	var sign: float = -1.0 if posmod(id, 2) == 0 else 1.0
	var wall_ids: Array = world.walls.keys()
	wall_ids.sort()
	for wall_id in wall_ids:
		var wall: Dictionary = world.walls[wall_id]
		if not _segment_hits_box(origin, enemy, wall.position, wall.size):
			continue
		var curve_data: Dictionary = Kits.move(element, "curve_shot")
		var extent: float = absf(side.x) * wall.size.x * 0.5 + absf(side.z) * wall.size.z * 0.5
		var waypoint: Vector3 = wall.position + side * sign * (extent + float(curve_data.size) + Tuning.BOT_CURVE_MARGIN)
		_aim_at(cmd, origin, waypoint)
		return

static func _segment_hits_box(start: Vector3, finish: Vector3, center: Vector3, size: Vector3) -> bool:
	var delta: Vector3 = finish - start
	var lo: Vector3 = center - size * 0.5
	var hi: Vector3 = center + size * 0.5
	var tmin: float = 0.0
	var tmax: float = 1.0
	for axis in range(3):
		var a: float = start[axis]
		var d: float = delta[axis]
		if absf(d) < 0.000001:
			if a < lo[axis] or a > hi[axis]:
				return false
		else:
			var t1: float = (lo[axis] - a) / d
			var t2: float = (hi[axis] - a) / d
			tmin = maxf(tmin, minf(t1, t2))
			tmax = minf(tmax, maxf(t1, t2))
			if tmin > tmax:
				return false
	return tmax >= 0.0 and tmin <= 1.0
static func _ready(player: Dictionary, slot: String) -> bool:
	return float(player.cooldowns.get(slot, 0.0)) <= 0.0

static func _ready_shove(player: Dictionary) -> bool:
	return float(player.cooldown) <= 0.0 and float(player.attack_time) <= 0.0

static func _aim_at(cmd: InputCmd, origin: Vector3, point: Vector3) -> void:
	var delta: Vector3 = point - origin
	cmd.yaw = atan2(-delta.x, -delta.z)
	cmd.pitch = atan2(delta.y, Vector2(delta.x, delta.z).length())

static func _incoming(world: Dictionary, id: int, player: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_time: float = INF
	var ids: Array = world.projectiles.keys()
	ids.sort()
	for pid in ids:
		var projectile: Dictionary = world.projectiles[pid]
		if int(projectile.owner) == id:
			continue
		var velocity: Vector3 = projectile.velocity
		var speed_sq: float = velocity.length_squared()
		if speed_sq <= 0.000001:
			continue
		var rel: Vector3 = player.position - projectile.position
		var time: float = rel.dot(velocity) / speed_sq
		if time <= 0.0 or time >= Tuning.BOT_PROJECTILE_LOOKAHEAD or time >= best_time:
			continue
		var closest: Vector3 = projectile.position + velocity * time
		var radius: float = Tuning.BODY_RADIUS + float(projectile.size) + Tuning.BOT_PROJECTILE_MARGIN
		if closest.distance_squared_to(player.position) <= radius * radius:
			best_time = time
			best = {"id": int(pid), "time": time, "speed": sqrt(speed_sq), "position": projectile.position}
	return best

static func _wall_obstructs(world: Dictionary, start: Vector3, finish: Vector3) -> bool:
	var wall_ids: Array = world.walls.keys()
	wall_ids.sort()
	for wall_id in wall_ids:
		var wall: Dictionary = world.walls[wall_id]
		if _segment_hits_box(start, finish, wall.position, wall.size):
			return true
	return false

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

static func _air_strafe(desired: Vector3, velocity: Vector3, dt: float, air_accel: float = -1.0) -> Vector3:
	var speed: float = velocity.length()
	var skill: float = clampf(Tuning.BOT_BHOP_SKILL, 0.0, 1.0)
	if speed <= Tuning.AIR_SPEED_CAP or skill <= 0.0:
		return desired
	var accel_multiplier: float = 1.0 if air_accel < 0.0 else air_accel
	var acceleration: float = Tuning.AIR_ACCELERATION * accel_multiplier * Tuning.AIR_SPEED_CAP * maxf(dt, 0.0)
	var angle: float = acos(clampf((Tuning.AIR_SPEED_CAP - acceleration) / speed, 0.0, 1.0))
	var forward: Vector3 = velocity / speed
	var left: Vector3 = forward.rotated(Vector3.UP, angle)
	var right: Vector3 = forward.rotated(Vector3.UP, -angle)
	var strafe: Vector3 = left if left.dot(desired) >= right.dot(desired) else right
	return desired.lerp(strafe, skill).normalized()
