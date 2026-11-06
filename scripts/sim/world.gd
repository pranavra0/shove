class_name World
extends RefCounted

# Pure simulation: dictionaries own their nested state; positions are body centres.
# attack_time counts down windup + active time; cooldown starts with the attack.
static func create(ids: Array, mode: String = "ffa") -> Dictionary:
	var normalized_mode: String = "control" if mode == "control" else "ffa"
	var ordered: Array = ids.duplicate()
	ordered.sort()
	var players: Dictionary = {}
	for index in range(ordered.size()):
		var spawn: Vector3
		var yaw: float
		var team: int = -1
		if normalized_mode == "control":
			team = index % 2
			var team_size: int = int(ceil(float(ordered.size()) * 0.5)) if team == 0 else int(floor(float(ordered.size()) * 0.5))
			var team_slot: int = int(floor(float(index) * 0.5))
			var spawn_edge: float = maxf(0.0, float(Tuning.PLATFORM_SIZE) * 0.5 - float(Tuning.BODY_RADIUS))
			var team_x: float = minf(maxf(2.0, float(Tuning.CP_LANE_OFFSET) * 0.5), spawn_edge)
			var side: float = -1.0 if team == 0 else 1.0
			spawn = Vector3(side * team_x, 0.0, (float(team_slot) - float(team_size - 1) * 0.5) * 1.2)
			yaw = -PI * 0.5 if team == 0 else PI * 0.5
		else:
			var angle: float = TAU * index / ordered.size()
			spawn = Vector3(sin(angle), 0.0, cos(angle)) * Tuning.SPAWN_RADIUS
			yaw = angle
		spawn = _safe_spawn(spawn, normalized_mode)
		players[int(ordered[index])] = _new_player(spawn, yaw, team, normalized_mode)
	var world: Dictionary = {"tick": 0, "players": players, "events": [], "projectiles": {}, "walls": {}, "next_entity_id": 1, "mode": normalized_mode, "control": {}}
	if normalized_mode == "control":
		world.control = _new_control_state()
		_update_control_layout(world)
	return world

static func _new_player(spawn: Vector3, yaw: float, team: int = -1, mode: String = "ffa") -> Dictionary:
	return {
		"position": spawn, "velocity": Vector3.ZERO,
		"on_ground": true, "ground_angle": floor_angle(spawn, mode), "yaw": yaw,
		"damage": 0.0, "stocks": Tuning.STOCKS, "hitstun": 0.0,
		"invuln": 0.0, "attack_time": 0.0, "cooldown": 0.0,
		"attack_hits": [], "attack_serial": 0, "spawn": spawn,
		"element": "earth", "cooldowns": {}, "move_state": {}, "recovery_used": 0,
		"jump_held": false, "down_dashing": false, "dash_time": 0.0, "chain_timer": 0.0, "chain_hits": 0, "chain_target": -1,
		"team": team, "respawn_remaining": 0.0,
	}

static func _new_control_state() -> Dictionary:
	var zones: Array[Dictionary] = [
		{"position": Vector3.ZERO, "radius": 0.0, "owner": -1, "capturing": -1, "progress": 0.0},
		{"position": Vector3.ZERO, "radius": 0.0, "owner": -1, "capturing": -1, "progress": 0.0},
	]
	var scores: Array[float] = [0.0, 0.0]
	return {"zones": zones, "scores": scores, "winner_team": -1}

static func is_player_active(player: Dictionary) -> bool:
	var team: int = int(player.get("team", -1))
	if team >= 0:
		return float(player.get("respawn_remaining", 0.0)) <= 0.0
	return int(player.get("stocks", 0)) > 0

static func are_enemies(a: Dictionary, b: Dictionary) -> bool:
	var team_a: int = int(a.get("team", -1))
	var team_b: int = int(b.get("team", -1))
	if team_a >= 0 or team_b >= 0:
		return team_a >= 0 and team_b >= 0 and team_a != team_b
	return true

static func set_element(world: Dictionary, id: int, element: String) -> void:
	if not Kits.ELEMENTS.has(element) or not world.players.has(id):
		return
	var player: Dictionary = world.players[id]
	player.element = element
	player.cooldowns = {}
	player.move_state = {}
	player.recovery_used = 0
	player.jump_held = false
	player.down_dashing = false
	player.dash_time = 0.0
	player.chain_timer = 0.0
	player.chain_hits = 0
	player.chain_target = -1

static func aim_direction(yaw: float, pitch: float) -> Vector3:
	return Vector3.FORWARD.rotated(Vector3.UP, yaw).rotated(Vector3.RIGHT.rotated(Vector3.UP, yaw), pitch).normalized()

static func step(world: Dictionary, commands: Dictionary, dt: float) -> Dictionary:
	var result: Dictionary = world.duplicate(true)
	result.tick = int(world.tick) + 1
	result.events = []
	var mode: String = str(world.get("mode", "ffa"))
	if mode != "control":
		mode = "ffa"
	result.mode = mode
	var control_state: Dictionary = result.get("control", {})
	if mode == "control":
		if not control_state.has("zones") or not control_state.has("scores") or not control_state.has("winner_team"):
			control_state = _new_control_state()
		result.control = control_state
		_update_control_layout(result)
	else:
		result.control = {}
	var ids: Array = result.players.keys()
	ids.sort()
	var active: Dictionary = {}
	var was_grounded_by_id: Dictionary = {}
	for id: int in ids:
		var player: Dictionary = result.players[id]
		active[id] = false
		if mode == "control" and float(player.get("respawn_remaining", 0.0)) > 0.0:
			player.respawn_remaining = maxf(0.0, float(player.respawn_remaining) - maxf(dt, 0.0))
			if float(player.respawn_remaining) <= 0.0:
				_respawn_control_player(player)
		if not is_player_active(player):
			continue
		var cmd: InputCmd = commands[id] if commands.has(id) else InputCmd.new(Vector2.ZERO, false, false, player.yaw, result.tick)
		player.yaw = cmd.yaw
		var stunned: bool = player.hitstun > 0.0
		player.hitstun = maxf(0.0, float(player.hitstun) - dt)
		player.invuln = maxf(0.0, float(player.invuln) - dt)
		player.cooldown = maxf(0.0, float(player.cooldown) - dt)
		was_grounded_by_id[id] = bool(player.on_ground) and float(player.ground_angle) <= Tuning.MAX_GROUND_ANGLE
		player.chain_timer = maxf(0.0, float(player.chain_timer) - dt)
		if float(player.chain_timer) <= 0.0:
			player.chain_hits = 0
			player.chain_target = -1
		player.dash_time = maxf(0.0, float(player.dash_time) - dt)
		AbilitySim.before_move(result, int(id), cmd, dt, false, stunned)
		var shove: Dictionary = Kits.move(str(player.element), "shove")
		if cmd.shove and not stunned and float(player.cooldown) <= 0.0 and float(player.attack_time) <= 0.0:
			player.attack_time = float(shove.windup) + float(shove.active)
			player.cooldown = float(shove.cooldown)
			player.attack_hits = []
			player.attack_serial = int(player.attack_serial) + 1
			result.events.append({"type": "shove", "player": id, "position": player.position})
		var previous_attack: float = float(player.attack_time)
		player.attack_time = maxf(0.0, previous_attack - dt)
		active[id] = previous_attack > 0.0 and float(player.attack_time) < float(shove.active)
		var movement_cmd: InputCmd = InputCmd.new(cmd.move, cmd.jump and not stunned, false, cmd.yaw, result.tick)
		_move_player(player, movement_cmd, stunned, dt, int(id), result.events, result.walls, mode)
	for id: int in ids:
		var player: Dictionary = result.players[id]
		if not is_player_active(player):
			continue
		AbilitySim.after_move(result, int(id), bool(was_grounded_by_id.get(id, false)), false)
		if player.on_ground:
			player.recovery_used = 0
	_separate(result.players, ids, mode)
	# Detect every melee hit before applying impulses, so earlier ids cannot move hitboxes.
	var hits: Array = []
	for attacker_id: int in ids:
		if not active.get(attacker_id, false):
			continue
		var attacker: Dictionary = result.players[attacker_id]
		var shove: Dictionary = Kits.move(str(attacker.element), "shove")
		var forward: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, attacker.yaw)
		var centre: Vector3 = attacker.position + forward * float(shove.reach)
		for victim_id: int in ids:
			if victim_id == attacker_id or attacker.attack_hits.has(victim_id):
				continue
			var victim: Dictionary = result.players[victim_id]
			if not is_player_active(victim) or victim.invuln > 0.0 or not are_enemies(attacker, victim):
				continue
			if centre.distance_squared_to(victim.position) <= float(shove.size) * float(shove.size):
				attacker.attack_hits.append(victim_id)
				var momentum: Vector3 = attacker.velocity
				momentum.y = 0.0
				hits.append({"attacker": attacker_id, "player": victim_id, "direction": forward, "momentum": momentum, "data": shove})
	for hit: Dictionary in hits:
		var attacker: Dictionary = result.players[hit.attacker]
		var victim: Dictionary = result.players[hit.player]
		var shove: Dictionary = hit.data
		victim.damage += float(shove.damage)
		var impulse: Vector3 = hit.direction.normalized() * (float(shove.kb_base) + victim.damage * float(shove.kb_scale))
		impulse += hit.momentum * float(shove.momentum) + Vector3.UP * float(shove.kb_up)
		impulse *= _knockback_multiplier(result, attacker)
		victim.velocity += impulse
		victim.on_ground = false
		victim.hitstun = float(shove.hitstun)
		result.events.append({"type": "hit", "player": hit.player, "attacker": hit.attacker, "position": victim.position, "strength": impulse.length(), "source": "shove"})
	ProjectileSim.step(result, active, commands, dt)
	for id: int in ids:
		var player: Dictionary = result.players[id]
		if not is_player_active(player) or player.position.y >= Tuning.KILL_PLANE:
			continue
		result.events.append({"type": "ko", "player": id, "position": player.position})
		if mode == "control":
			_control_ko(result, player)
			continue
		player.stocks -= 1
		player.velocity = Vector3.ZERO
		player.damage = 0.0
		player.hitstun = 0.0
		player.attack_time = 0.0
		player.cooldown = 0.0
		player.attack_hits = []
		player.cooldowns = {}
		player.move_state = {}
		player.recovery_used = 0
		player.jump_held = false
		player.down_dashing = false
		player.dash_time = 0.0
		player.chain_timer = 0.0
		player.chain_hits = 0
		player.chain_target = -1
		player.on_ground = false
		if player.stocks > 0:
			player.spawn = _safe_spawn(player.spawn, mode)
			player.position = player.spawn
			player.ground_angle = floor_angle(player.spawn, mode)
			player.on_ground = player.ground_angle <= Tuning.MAX_GROUND_ANGLE
			player.invuln = Tuning.RESPAWN_INVULN
	if mode == "control":
		_step_control_objectives(result, dt, ids)
	return result

static func _update_control_layout(world: Dictionary) -> void:
	var control: Dictionary = world.control
	var zones: Array = control.zones
	for index in range(2):
		var zone: Dictionary = zones[index]
		var side: float = -1.0 if index == 0 else 1.0
		zone.position = Vector3(side * float(Tuning.CP_LANE_OFFSET), 0.0, 0.0)
		zone.radius = float(Tuning.CP_ZONE_RADIUS)
		zones[index] = zone
	control.zones = zones

static func _step_control_objectives(world: Dictionary, dt: float, ids: Array) -> void:
	var control: Dictionary = world.control
	if int(control.winner_team) >= 0:
		return
	var zones: Array = control.zones
	for zone_index in range(2):
		var zone: Dictionary = zones[zone_index]
		var team_zero_present: bool = false
		var team_one_present: bool = false
		var zone_position: Vector3 = zone.position
		var zone_radius: float = float(zone.radius)
		for id: int in ids:
			var player: Dictionary = world.players[id]
			var team: int = int(player.get("team", -1))
			if team < 0 or team > 1 or not is_player_active(player) or not bool(player.on_ground):
				continue
			var feet: float = player.position.y - float(Tuning.BODY_HEIGHT) * 0.5
			if absf(feet - floor_height(player.position, "control")) > float(Tuning.CP_CAPTURE_HEIGHT):
				continue
			var horizontal: Vector2 = Vector2(player.position.x - zone_position.x, player.position.z - zone_position.z)
			if horizontal.length_squared() <= zone_radius * zone_radius:
				if team == 0:
					team_zero_present = true
				else:
					team_one_present = true
		if team_zero_present and team_one_present:
			continue
		var capturing_team: int = 0 if team_zero_present else 1 if team_one_present else -1
		if capturing_team < 0:
			continue
		if int(zone.owner) == capturing_team:
			zone.capturing = -1
			zone.progress = 1.0
			zones[zone_index] = zone
			continue
		if int(zone.capturing) != capturing_team:
			zone.capturing = capturing_team
			zone.progress = 0.0
		var capture_time: float = maxf(float(Tuning.CP_CAPTURE_TIME), 0.000001)
		zone.progress = minf(1.0, float(zone.progress) + maxf(dt, 0.0) / capture_time)
		if float(zone.progress) >= 1.0:
			zone.owner = capturing_team
			zone.capturing = -1
			zone.progress = 1.0
		zones[zone_index] = zone
	var first_owner: int = int(zones[0].owner)
	var second_owner: int = int(zones[1].owner)
	control.zones = zones
	if first_owner >= 0 and first_owner == second_owner:
		var team: int = first_owner
		var scores: Array = control.scores
		scores[team] = float(scores[team]) + maxf(dt, 0.0) * float(Tuning.CP_SCORE_RATE)
		control.scores = scores
		if float(scores[team]) >= float(Tuning.CP_SCORE_TARGET):
			control.winner_team = team

static func _control_ko(world: Dictionary, player: Dictionary) -> void:
	player.stocks = maxi(0, int(player.stocks) - 1)
	var control: Dictionary = world.control
	var team: int = int(player.get("team", -1))
	if team >= 0 and team <= 1:
		var scores: Array = control.scores
		scores[team] = maxf(0.0, float(scores[team]) - float(Tuning.CP_RINGOUT_PENALTY))
		control.scores = scores
	player.velocity = Vector3.ZERO
	player.damage = 0.0
	player.hitstun = 0.0
	player.invuln = 0.0
	player.attack_time = 0.0
	player.cooldown = 0.0
	player.attack_hits = []
	player.cooldowns = {}
	player.move_state = {}
	player.recovery_used = 0
	player.jump_held = false
	player.down_dashing = false
	player.dash_time = 0.0
	player.chain_timer = 0.0
	player.chain_hits = 0
	player.chain_target = -1
	player.on_ground = false
	player.respawn_remaining = maxf(0.0, float(Tuning.CP_RESPAWN_DELAY))
	if float(player.respawn_remaining) <= 0.0:
		_respawn_control_player(player)
	else:
		player.position = Vector3(player.spawn.x, Tuning.KILL_PLANE - float(Tuning.BODY_HEIGHT), player.spawn.z)

static func _respawn_control_player(player: Dictionary) -> void:
	player.spawn = _safe_spawn(player.spawn, "control")
	player.position = player.spawn
	player.velocity = Vector3.ZERO
	player.on_ground = true
	player.ground_angle = floor_angle(player.spawn, "control")
	player.invuln = float(Tuning.RESPAWN_INVULN)
	player.respawn_remaining = 0.0

static func _knockback_multiplier(world: Dictionary, attacker: Dictionary) -> float:
	if str(world.get("mode", "ffa")) != "control":
		return 1.0
	var team: int = int(attacker.get("team", -1))
	if team < 0 or team > 1:
		return 1.0
	var control: Dictionary = world.get("control", {})
	var zones: Array = control.get("zones", [])
	if zones.size() == 2 and int(zones[0].owner) == team and int(zones[1].owner) == team:
		return float(Tuning.CP_KB_BONUS)
	return 1.0

static func apply_move_hit(world: Dictionary, attacker_id: int, victim_id: int, data: Dictionary, direction: Vector3, momentum: Vector3, source_slot: String) -> void:
	if not world.players.has(victim_id) or not world.players.has(attacker_id) or attacker_id == victim_id:
		return
	var victim: Dictionary = world.players[victim_id]
	var attacker: Dictionary = world.players[attacker_id]
	if not is_player_active(victim) or victim.invuln > 0.0 or not are_enemies(attacker, victim):
		return
	victim.damage = float(victim.damage) + float(data.damage)
	var impulse: Vector3 = direction.normalized() * (float(data.kb_base) + float(victim.damage) * float(data.kb_scale))
	impulse += momentum * float(data.momentum) + Vector3.UP * float(data.kb_up)
	impulse *= _knockback_multiplier(world, attacker)
	victim.velocity += impulse
	victim.on_ground = false
	var chained: bool = float(data.chain_stun) > 0.0 and float(attacker.chain_timer) > 0.0 and int(attacker.chain_hits) > 0
	var chain_extra: int = maxi(0, int(attacker.chain_hits))
	victim.hitstun = maxf(float(victim.hitstun), float(data.hitstun) + (float(data.chain_stun) * chain_extra if chained else 0.0))
	if float(data.chain_stun) > 0.0:
		attacker.chain_hits = int(attacker.chain_hits) + 1 if chained else 1
		attacker.chain_target = victim_id
		attacker.chain_timer = float(data.chain_window)
	world.events.append({"type": "hit", "player": victim_id, "attacker": attacker_id, "position": victim.position, "strength": impulse.length(), "source": source_slot})

static func predict_player(world: Dictionary, id: int, cmd: InputCmd, dt: float) -> Dictionary:
	if not world.players.has(id):
		return {}
	var isolated: Dictionary = world.duplicate()
	isolated.players = {id: world.players[id].duplicate(true)}
	isolated.events = []
	var player: Dictionary = isolated.players[id]
	if not is_player_active(player):
		return player
	player.yaw = cmd.yaw
	var stunned: bool = player.hitstun > 0.0
	player.hitstun = maxf(0.0, float(player.hitstun) - dt)
	player.invuln = maxf(0.0, float(player.invuln) - dt)
	player.cooldown = maxf(0.0, float(player.cooldown) - dt)
	var was_grounded: bool = bool(player.on_ground) and float(player.ground_angle) <= Tuning.MAX_GROUND_ANGLE
	player.chain_timer = maxf(0.0, float(player.chain_timer) - dt)
	if float(player.chain_timer) <= 0.0:
		player.chain_hits = 0
		player.chain_target = -1
	AbilitySim.before_move(isolated, id, cmd, dt, true, stunned)
	var shove: Dictionary = Kits.move(str(player.element), "shove")
	if cmd.shove and not stunned and float(player.cooldown) <= 0.0 and float(player.attack_time) <= 0.0:
		player.attack_time = float(shove.windup) + float(shove.active)
		player.cooldown = float(shove.cooldown)
		player.attack_hits = []
		player.attack_serial = int(player.attack_serial) + 1
	player.dash_time = maxf(0.0, float(player.dash_time) - dt)
	var old_attack: float = float(player.attack_time)
	player.attack_time = maxf(0.0, old_attack - dt)
	var movement_cmd: InputCmd = InputCmd.new(cmd.move, cmd.jump and not stunned, false, cmd.yaw, int(world.tick) + 1)
	var mode: String = str(world.get("mode", "ffa"))
	_move_player(player, movement_cmd, stunned, dt, id, isolated.events, world.walls, mode)
	AbilitySim.after_move(isolated, id, was_grounded, true)
	return player

static func _slam_hit(world: Dictionary, attacker_id: int, victim_id: int) -> void:
	if not world.players.has(attacker_id) or not world.players.has(victim_id) or attacker_id == victim_id:
		return
	var attacker: Dictionary = world.players[attacker_id]
	var victim: Dictionary = world.players[victim_id]
	if not is_player_active(attacker) or not is_player_active(victim) or victim.invuln > 0.0 or not are_enemies(attacker, victim):
		return
	var data: Dictionary = Kits.move(str(attacker.element), "down_dash")
	if attacker.position.distance_squared_to(victim.position) > float(data.slam_radius) * float(data.slam_radius):
		return
	var momentum: Vector3 = Vector3(attacker.velocity.x, 0.0, attacker.velocity.z)
	apply_move_hit(world, attacker_id, victim_id, data, Vector3.UP, momentum, "down_dash")

static func _move_player(player: Dictionary, cmd: InputCmd, stunned: bool, dt: float, id: int, events: Array, walls: Dictionary = {}, mode: String = "ffa") -> void:
	var before: Vector3 = player.position
	var was_grounded: bool = player.on_ground and player.ground_angle <= Tuning.MAX_GROUND_ANGLE
	var move_data: Dictionary = Kits.movement(player.element)
	var movement_state: Dictionary = {"velocity": player.velocity, "on_ground": was_grounded, "ground_angle": player.ground_angle, "control_scale": Tuning.HITSTUN_CONTROL if stunned else 1.0, "ground_speed_multiplier": float(move_data.ground_speed), "air_accel_multiplier": float(move_data.air_accel), "jump_multiplier": float(move_data.jump), "preserve_vertical": bool(player.down_dashing) or float(player.dash_time) > 0.0}
	var moved: Dictionary = MovementSim.step(movement_state, cmd, dt)
	player.velocity = moved.velocity
	player.on_ground = false
	var after: Vector3 = before + player.velocity * dt
	var half_height: float = Tuning.BODY_HEIGHT * 0.5
	var surface: int = _floor_surface(after, mode)
	if moved.on_ground and surface >= 0:
		var height: float = _surface_height(surface, after, mode)
		var previous_height: float = before.y - half_height
		var continuous: bool = absf(height - previous_height) <= 0.00001
		if surface == 2 or surface == 3:
			continuous = continuous or absf(_surface_height(surface, before, mode) - previous_height) <= 0.00001
			var low_edge: float = Tuning.RAMP_LENGTH * 0.5
			if not continuous and absf(previous_height) <= 0.00001 and before.z >= low_edge and after.z < low_edge:
				var crossing: Vector3 = before.lerp(after, (before.z - low_edge) / (before.z - after.z))
				continuous = _surface_contains(surface, crossing, mode)
		if continuous and _surface_angle(surface, mode) <= Tuning.MAX_GROUND_ANGLE:
			after.y = height + half_height
			player.on_ground = true
			player.ground_angle = _surface_angle(surface, mode)
		elif height > previous_height:
			after = before
			player.velocity.x = 0.0
			player.velocity.z = 0.0
			player.on_ground = true
	if not player.on_ground and player.velocity.y <= 0.0:
		var earliest: float = INF
		var landing_surface: int = -1
		for index in range(6):
			if _surface_angle(index, mode) > Tuning.MAX_GROUND_ANGLE:
				continue
			var start_distance: float = before.y - half_height - _surface_height(index, before, mode)
			var end_distance: float = after.y - half_height - _surface_height(index, after, mode)
			if start_distance < -0.00001 or end_distance > 0.00001 or start_distance <= end_distance:
				continue
			var fraction: float = clampf(start_distance / (start_distance - end_distance), 0.0, 1.0)
			var crossing: Vector3 = before.lerp(after, fraction)
			if not _surface_contains(index, crossing, mode):
				continue
			if _surface_height(index, crossing, mode) < floor_height(crossing, mode) - 0.00001:
				continue
			if fraction < earliest:
				earliest = fraction
				landing_surface = index
		if landing_surface >= 0:
			if not _surface_contains(landing_surface, after, mode):
				after = before.lerp(after, earliest)
			after.y = _surface_height(landing_surface, after, mode) + half_height
			player.velocity.y = 0.0
			player.on_ground = true
			player.ground_angle = _surface_angle(landing_surface, mode)
	if not player.on_ground and surface >= 0 and after.y - half_height < floor_height(after, mode) - 0.00001:
		var support: float = floor_height(before, mode)
		if before.y - half_height >= support - 0.00001 and floor_height(after, mode) > support + 0.00001:
			after.x = before.x
			after.z = before.z
			player.velocity.x = 0.0
			player.velocity.z = 0.0
			if player.velocity.y <= 0.0 and after.y - half_height <= support:
				after.y = support + half_height
				player.velocity.y = 0.0
				player.on_ground = true
				player.ground_angle = floor_angle(before, mode)
	_resolve_wall_collision(player, before, after, walls, half_height)
	after = player.position
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


static func _separate(players: Dictionary, ids: Array, mode: String = "ffa") -> void:
	for first in range(ids.size()):
		var a: Dictionary = players[ids[first]]
		if not is_player_active(a):
			continue
		for second in range(first + 1, ids.size()):
			var b: Dictionary = players[ids[second]]
			if not is_player_active(b) or absf(a.position.y - b.position.y) >= Tuning.BODY_HEIGHT:
				continue
			var offset: Vector3 = b.position - a.position
			offset.y = 0.0
			var distance: float = offset.length()
			var overlap: float = Tuning.BODY_RADIUS * 2.0 - distance
			if overlap <= 0.0:
				continue
			var direction: Vector3 = offset / distance if distance > 0.00001 else Vector3.RIGHT
			var push: Vector3 = direction * overlap * Tuning.BODY_PUSH * 0.5
			_apply_separation(a, -push, mode)
			_apply_separation(b, push, mode)

static func _apply_separation(player: Dictionary, push: Vector3, mode: String = "ffa") -> void:
	var before: Vector3 = player.position
	player.position += push
	if not player.on_ground:
		return
	var surface: int = _floor_surface(player.position, mode)
	var height: float = floor_height(player.position, mode)
	var previous_height: float = before.y - Tuning.BODY_HEIGHT * 0.5
	if absf(height - previous_height) <= 0.00001:
		return
	if (surface == 2 or surface == 3) and _surface_angle(surface, mode) <= Tuning.MAX_GROUND_ANGLE and absf(_surface_height(surface, before, mode) - previous_height) <= 0.00001:
		player.position.y = height + Tuning.BODY_HEIGHT * 0.5
		player.ground_angle = _surface_angle(surface, mode)
	elif height > previous_height:
		player.position = before
	else:
		player.on_ground = false

static func floor_height(position: Vector3, mode: String = "ffa") -> float:
	var surface: int = _floor_surface(position, mode)
	return _surface_height(surface, position, mode) if surface >= 0 else -INF

static func floor_angle(position: Vector3, mode: String = "ffa") -> float:
	var surface: int = _floor_surface(position, mode)
	return _surface_angle(surface, mode) if surface >= 0 else 0.0

static func _floor_surface(position: Vector3, mode: String = "ffa") -> int:
	if not _surface_contains(0, position, mode):
		return -1
	if mode == "control":
		return 0
	var selected: int = 0
	var height: float = 0.0
	for index in range(1, 6):
		if _surface_contains(index, position, mode):
			var candidate: float = _surface_height(index, position, mode)
			if candidate > height:
				selected = index
				height = candidate
	return selected

static func _surface_contains(index: int, position: Vector3, mode: String = "ffa") -> bool:
	if absf(position.x) > Tuning.PLATFORM_SIZE * 0.5 or absf(position.z) > Tuning.PLATFORM_SIZE * 0.5:
		return false
	if mode == "control":
		return index == 0
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

static func _surface_height(index: int, position: Vector3, mode: String = "ffa") -> float:
	if mode == "control":
		return 0.0
	match index:
		1:
			return Tuning.CENTER_HEIGHT
		2, 3:
			return Tuning.RAMP_HEIGHT * (0.5 - position.z / Tuning.RAMP_LENGTH)
		4, 5:
			return Tuning.LEDGE_HEIGHT
	return 0.0

static func _surface_angle(index: int, mode: String = "ffa") -> float:
	if mode == "control":
		return 0.0 if index == 0 else INF
	return atan2(Tuning.RAMP_HEIGHT, Tuning.RAMP_LENGTH) if index == 2 or index == 3 else 0.0

static func _safe_spawn(point: Vector3, mode: String = "ffa") -> Vector3:
	var edge: float = maxf(0.0, Tuning.PLATFORM_SIZE * 0.5 - Tuning.BODY_RADIUS)
	point.x = clampf(point.x, -edge, edge)
	point.z = clampf(point.z, -edge, edge)
	point.y = floor_height(point, mode) + Tuning.BODY_HEIGHT * 0.5
	return point
static func _resolve_wall_collision(player: Dictionary, before: Vector3, after: Vector3, walls: Dictionary, half_height: float) -> void:
	var earliest: float = INF
	var landing_y: float = 0.0
	var existing_support_endpoint: bool = false
	player.position = after
	for wall_id in walls:
		var wall: Dictionary = walls[wall_id]
		var centre: Vector3 = wall.position
		var size: Vector3 = wall.size
		var min_x: float = centre.x - size.x * 0.5 - Tuning.BODY_RADIUS
		var max_x: float = centre.x + size.x * 0.5 + Tuning.BODY_RADIUS
		var min_z: float = centre.z - size.z * 0.5 - Tuning.BODY_RADIUS
		var max_z: float = centre.z + size.z * 0.5 + Tuning.BODY_RADIUS
		var top: float = centre.y + size.y * 0.5
		var start_feet: float = before.y - half_height
		var end_feet: float = after.y - half_height
		if player.velocity.y <= 0.0 and absf(start_feet - top) <= 0.00001:
			var endpoint_supported: bool = after.x >= min_x and after.x <= max_x and after.z >= min_z and after.z <= max_z
			if endpoint_supported:
				if 0.0 < earliest:
					earliest = 0.0
					landing_y = top
					existing_support_endpoint = true
			continue
		if player.velocity.y <= 0.0 and start_feet > top + 0.00001 and end_feet <= top + 0.00001:
			var fraction: float = clampf((start_feet - top) / maxf(start_feet - end_feet, 0.000001), 0.0, 1.0)
			var crossing: Vector3 = before.lerp(after, fraction)
			if crossing.x < min_x or crossing.x > max_x or crossing.z < min_z or crossing.z > max_z:
				continue
			if fraction < earliest:
				earliest = fraction
				landing_y = top
	if earliest < INF:
		var landing_fraction: float = clampf((before.y - half_height - landing_y) / maxf(before.y - after.y, 0.000001), 0.0, 1.0)
		var landing_point: Vector3 = after if existing_support_endpoint else before.lerp(after, landing_fraction)
		player.position = Vector3(landing_point.x, landing_y + half_height, landing_point.z)
		player.velocity.y = 0.0
		player.on_ground = true
		player.ground_angle = 0.0
		return
	var delta: Vector3 = after - before
	var horizontal_fraction: float = 1.0
	var blocked: bool = false
	for wall_id in walls:
		var wall: Dictionary = walls[wall_id]
		var centre: Vector3 = wall.position
		var size: Vector3 = wall.size
		if after.y + half_height <= centre.y - size.y * 0.5 or before.y - half_height >= centre.y + size.y * 0.5:
			continue
		var min_x: float = centre.x - size.x * 0.5 - Tuning.BODY_RADIUS
		var max_x: float = centre.x + size.x * 0.5 + Tuning.BODY_RADIUS
		var min_z: float = centre.z - size.z * 0.5 - Tuning.BODY_RADIUS
		var max_z: float = centre.z + size.z * 0.5 + Tuning.BODY_RADIUS
		var x_interval: Vector2 = _sweep_axis(before.x, delta.x, min_x, max_x)
		var z_interval: Vector2 = _sweep_axis(before.z, delta.z, min_z, max_z)
		if x_interval.x > x_interval.y or z_interval.x > z_interval.y:
			continue
		var enter: float = maxf(x_interval.x, z_interval.x)
		var leave: float = minf(x_interval.y, z_interval.y)
		if enter > leave or leave < 0.0 or enter > 1.0:
			continue
		if enter >= 0.0 and enter < horizontal_fraction:
			horizontal_fraction = enter
			blocked = true
	if blocked:
		player.position = before + delta * maxf(0.0, horizontal_fraction - 0.00001)
		player.velocity.x = 0.0
		player.velocity.z = 0.0

static func _sweep_axis(origin: float, delta: float, minimum: float, maximum: float) -> Vector2:
	if absf(delta) < 0.000001:
		return Vector2(-INF, INF) if origin >= minimum and origin <= maximum else Vector2(1.0, -1.0)
	var first: float = (minimum - origin) / delta
	var second: float = (maximum - origin) / delta
	return Vector2(minf(first, second), maxf(first, second))
