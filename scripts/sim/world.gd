class_name World
extends RefCounted

# Pure simulation: dictionaries own their nested state; positions are body centres.
# attack_time counts down windup + active time; cooldown starts with the attack.
static func create(ids: Array) -> Dictionary:
	var ordered: Array = ids.duplicate()
	ordered.sort()
	var players: Dictionary = {}
	for index in range(ordered.size()):
		var angle: float = TAU * index / ordered.size()
		var spawn := Vector3(sin(angle), 0.0, cos(angle)) * Tuning.SPAWN_RADIUS
		spawn = _safe_spawn(spawn)
		players[int(ordered[index])] = _new_player(spawn, angle)
	return {"tick": 0, "players": players, "events": []}

static func _new_player(spawn: Vector3, yaw: float) -> Dictionary:
	return {
		"position": spawn, "velocity": Vector3.ZERO,
		"on_ground": true, "ground_angle": floor_angle(spawn), "yaw": yaw,
		"damage": 0.0, "stocks": Tuning.STOCKS, "hitstun": 0.0,
		"invuln": 0.0, "attack_time": 0.0, "cooldown": 0.0,
		"attack_hits": [], "spawn": spawn,
	}

static func step(world: Dictionary, commands: Dictionary, dt: float) -> Dictionary:
	var result: Dictionary = world.duplicate()
	result.players = world.players.duplicate(true)
	result.tick = int(world.tick) + 1
	result.events = []
	var ids: Array = result.players.keys()
	ids.sort()
	var active: Dictionary = {}
	for id in ids:
		var player: Dictionary = result.players[id]
		if player.stocks <= 0:
			continue
		var cmd: InputCmd = commands[id] if commands.has(id) else InputCmd.new(Vector2.ZERO, false, false, player.yaw, result.tick)
		var stunned: bool = player.hitstun > 0.0
		player.hitstun = maxf(0.0, player.hitstun - dt)
		player.invuln = maxf(0.0, player.invuln - dt)
		player.cooldown = maxf(0.0, player.cooldown - dt)
		player.yaw = cmd.yaw
		if cmd.shove and not stunned and player.cooldown <= 0.0 and player.attack_time <= 0.0:
			player.attack_time = Tuning.SHOVE_WINDUP + Tuning.SHOVE_ACTIVE
			player.cooldown = Tuning.SHOVE_COOLDOWN
			player.attack_hits = []
			result.events.append({"type": "shove", "player": id, "position": player.position})
		var previous_attack: float = player.attack_time
		player.attack_time = maxf(0.0, previous_attack - dt)
		# Intersect this tick's time interval with the active phase, not just its endpoint.
		active[id] = previous_attack > 0.0 and player.attack_time < Tuning.SHOVE_ACTIVE
		var movement_cmd := InputCmd.new(cmd.move, cmd.jump and not stunned, false, cmd.yaw, result.tick)
		_move_player(player, movement_cmd, stunned, dt, id, result.events)
	_separate(result.players, ids)
	# Detect every hit before applying impulses, so earlier ids cannot move hitboxes.
	var hits: Array = []
	for attacker_id in ids:
		if not active.get(attacker_id, false):
			continue
		var attacker: Dictionary = result.players[attacker_id]
		var forward: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, attacker.yaw)
		var centre: Vector3 = attacker.position + forward * Tuning.SHOVE_REACH
		for victim_id in ids:
			if victim_id == attacker_id or attacker.attack_hits.has(victim_id):
				continue
			var victim: Dictionary = result.players[victim_id]
			if victim.stocks <= 0 or victim.invuln > 0.0:
				continue
			if centre.distance_squared_to(victim.position) <= Tuning.SHOVE_RADIUS * Tuning.SHOVE_RADIUS:
				attacker.attack_hits.append(victim_id)
				var momentum: Vector3 = attacker.velocity
				momentum.y = 0.0
				hits.append({"attacker": attacker_id, "player": victim_id, "direction": forward, "momentum": momentum})
	for hit in hits:
		var victim: Dictionary = result.players[hit.player]
		victim.damage += Tuning.SHOVE_DAMAGE
		var impulse: Vector3 = hit.direction * (Tuning.BASE_KB + victim.damage * Tuning.KB_SCALE)
		impulse += hit.momentum * Tuning.MOMENTUM_TRANSFER + Vector3.UP * Tuning.KB_UP
		victim.velocity += impulse
		victim.on_ground = false
		victim.hitstun = Tuning.HITSTUN
		result.events.append({"type": "hit", "player": hit.player, "attacker": hit.attacker, "position": victim.position, "strength": impulse.length()})
	for id in ids:
		var player: Dictionary = result.players[id]
		if player.stocks > 0 and player.position.y < Tuning.KILL_PLANE:
			result.events.append({"type": "ko", "player": id, "position": player.position})
			player.stocks -= 1
			player.velocity = Vector3.ZERO
			player.damage = 0.0
			player.hitstun = 0.0
			player.attack_time = 0.0
			player.cooldown = 0.0
			player.attack_hits = []
			player.on_ground = false
			if player.stocks > 0:
				player.spawn = _safe_spawn(player.spawn)
				player.position = player.spawn
				player.ground_angle = floor_angle(player.spawn)
				player.on_ground = player.ground_angle <= Tuning.MAX_GROUND_ANGLE
				player.invuln = Tuning.RESPAWN_INVULN
	return result

static func _move_player(player: Dictionary, cmd: InputCmd, stunned: bool, dt: float, id: int, events: Array) -> void:
	var before: Vector3 = player.position
	var was_grounded: bool = player.on_ground and player.ground_angle <= Tuning.MAX_GROUND_ANGLE
	var movement_state := {"velocity": player.velocity, "on_ground": was_grounded, "ground_angle": player.ground_angle, "control_scale": Tuning.HITSTUN_CONTROL if stunned else 1.0}
	var moved: Dictionary = MovementSim.step(movement_state, cmd, dt)
	player.velocity = moved.velocity
	player.on_ground = false
	var after: Vector3 = before + player.velocity * dt
	var half_height: float = Tuning.BODY_HEIGHT * 0.5
	var surface: int = _floor_surface(after)
	if moved.on_ground and surface >= 0:
		var height: float = _surface_height(surface, after)
		var previous_height: float = before.y - half_height
		var continuous: bool = absf(height - previous_height) <= 0.00001
		if surface == 2 or surface == 3:
			continuous = continuous or absf(_surface_height(surface, before) - previous_height) <= 0.00001
			# The low edge joins the base plane continuously; other ramp edges are walls.
			var low_edge: float = Tuning.RAMP_LENGTH * 0.5
			if not continuous and absf(previous_height) <= 0.00001 and before.z >= low_edge and after.z < low_edge:
				var crossing: Vector3 = before.lerp(after, (before.z - low_edge) / (before.z - after.z))
				continuous = _surface_contains(surface, crossing)
		if continuous and _surface_angle(surface) <= Tuning.MAX_GROUND_ANGLE:
			after.y = height + half_height
			player.on_ground = true
			player.ground_angle = _surface_angle(surface)
		elif height > previous_height:
			# Raised vertical faces and steep ramps cannot become a walkable step.
			after = before
			player.velocity.x = 0.0
			player.velocity.z = 0.0
			player.on_ground = true
	# Sweep the feet against each bounded plane. This catches fast falls and ramp entry.
	if not player.on_ground and player.velocity.y <= 0.0:
		var earliest: float = INF
		var landing_surface: int = -1
		for index in range(6):
			if _surface_angle(index) > Tuning.MAX_GROUND_ANGLE:
				continue
			var start_distance: float = before.y - half_height - _surface_height(index, before)
			var end_distance: float = after.y - half_height - _surface_height(index, after)
			if start_distance < -0.00001 or end_distance > 0.00001 or start_distance <= end_distance:
				continue
			var fraction: float = clampf(start_distance / (start_distance - end_distance), 0.0, 1.0)
			var crossing: Vector3 = before.lerp(after, fraction)
			if not _surface_contains(index, crossing):
				continue
			if _surface_height(index, crossing) < floor_height(crossing) - 0.00001:
				continue
			if fraction < earliest:
				earliest = fraction
				landing_surface = index
		if landing_surface >= 0:
			if not _surface_contains(landing_surface, after):
				after = before.lerp(after, earliest)
			after.y = _surface_height(landing_surface, after) + half_height
			player.velocity.y = 0.0
			player.on_ground = true
			player.ground_angle = _surface_angle(landing_surface)
	# Entering a raised solid below its top is a wall collision, not a floor hole.
	if not player.on_ground and surface >= 0 and after.y - half_height < floor_height(after) - 0.00001:
		var support: float = floor_height(before)
		if before.y - half_height >= support - 0.00001 and floor_height(after) > support + 0.00001:
			after.x = before.x
			after.z = before.z
			player.velocity.x = 0.0
			player.velocity.z = 0.0
			if player.velocity.y <= 0.0 and after.y - half_height <= support:
				after.y = support + half_height
				player.velocity.y = 0.0
				player.on_ground = true
				player.ground_angle = floor_angle(before)
	if moved.on_ground and not player.on_ground:
		player.velocity.y -= Tuning.GRAVITY * dt
		after.y += player.velocity.y * dt
	player.position = after
	if not player.on_ground:
		player.ground_angle = 0.0
	if was_grounded and cmd.jump:
		events.append({"type": "jump", "player": id, "position": before})
	if not was_grounded and player.on_ground:
		events.append({"type": "land", "player": id, "position": after})

static func _separate(players: Dictionary, ids: Array) -> void:
	for first in range(ids.size()):
		var a: Dictionary = players[ids[first]]
		if a.stocks <= 0:
			continue
		for second in range(first + 1, ids.size()):
			var b: Dictionary = players[ids[second]]
			if b.stocks <= 0 or absf(a.position.y - b.position.y) >= Tuning.BODY_HEIGHT:
				continue
			var offset: Vector3 = b.position - a.position
			offset.y = 0.0
			var distance: float = offset.length()
			var overlap: float = Tuning.BODY_RADIUS * 2.0 - distance
			if overlap <= 0.0:
				continue
			var direction: Vector3 = offset / distance if distance > 0.00001 else Vector3.RIGHT
			var push: Vector3 = direction * overlap * Tuning.BODY_PUSH * 0.5
			_apply_separation(a, -push)
			_apply_separation(b, push)

static func _apply_separation(player: Dictionary, push: Vector3) -> void:
	var before: Vector3 = player.position
	player.position += push
	if not player.on_ground:
		return
	var surface: int = _floor_surface(player.position)
	var height: float = floor_height(player.position)
	var previous_height: float = before.y - Tuning.BODY_HEIGHT * 0.5
	if absf(height - previous_height) <= 0.00001:
		return
	if (surface == 2 or surface == 3) and _surface_angle(surface) <= Tuning.MAX_GROUND_ANGLE and absf(_surface_height(surface, before) - previous_height) <= 0.00001:
		player.position.y = height + Tuning.BODY_HEIGHT * 0.5
		player.ground_angle = _surface_angle(surface)
	elif height > previous_height:
		player.position = before
	else:
		player.on_ground = false

static func floor_height(position: Vector3) -> float:
	var surface: int = _floor_surface(position)
	return _surface_height(surface, position) if surface >= 0 else -INF

static func floor_angle(position: Vector3) -> float:
	var surface: int = _floor_surface(position)
	return _surface_angle(surface) if surface >= 0 else 0.0

static func _floor_surface(position: Vector3) -> int:
	if not _surface_contains(0, position):
		return -1
	var selected: int = 0
	var height: float = 0.0
	for index in range(1, 6):
		if _surface_contains(index, position):
			var candidate: float = _surface_height(index, position)
			if candidate > height:
				selected = index
				height = candidate
	return selected

static func _surface_contains(index: int, position: Vector3) -> bool:
	if absf(position.x) > Tuning.PLATFORM_SIZE * 0.5 or absf(position.z) > Tuning.PLATFORM_SIZE * 0.5:
		return false
	match index:
		0:
			return true
		1:
			return absf(position.x) <= Tuning.CENTER_SIZE * 0.5 and absf(position.z) <= Tuning.CENTER_SIZE * 0.5
		2, 3:
			var x: float = -Tuning.RAMP_OFFSET if index == 2 else Tuning.RAMP_OFFSET
			return absf(position.x - x) <= Tuning.RAMP_WIDTH * 0.5 and absf(position.z) <= Tuning.RAMP_LENGTH * 0.5
		4, 5:
			var x: float = -Tuning.LEDGE_OFFSET if index == 4 else Tuning.LEDGE_OFFSET
			return absf(position.x - x) <= Tuning.LEDGE_WIDTH * 0.5 and absf(position.z) <= Tuning.LEDGE_LENGTH * 0.5
	return false

static func _surface_height(index: int, position: Vector3) -> float:
	match index:
		1:
			return Tuning.CENTER_HEIGHT
		2, 3:
			return Tuning.RAMP_HEIGHT * (0.5 - position.z / Tuning.RAMP_LENGTH)
		4, 5:
			return Tuning.LEDGE_HEIGHT
	return 0.0

static func _surface_angle(index: int) -> float:
	return atan2(Tuning.RAMP_HEIGHT, Tuning.RAMP_LENGTH) if index == 2 or index == 3 else 0.0

static func _safe_spawn(point: Vector3) -> Vector3:
	var edge: float = maxf(0.0, Tuning.PLATFORM_SIZE * 0.5 - Tuning.BODY_RADIUS)
	point.x = clampf(point.x, -edge, edge)
	point.z = clampf(point.z, -edge, edge)
	point.y = floor_height(point) + Tuning.BODY_HEIGHT * 0.5
	return point
