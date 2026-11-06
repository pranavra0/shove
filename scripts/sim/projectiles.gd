class_name ProjectileSim
extends RefCounted

static func spawn_projectile(world: Dictionary, owner: int, slot: String, aim: Vector3, strafe: float) -> void:
	if world.projectiles.size() >= Tuning.MAX_PROJECTILES:
		return
	if not world.players.has(owner):
		return
	var player: Dictionary = world.players[owner]
	var data: Dictionary = Kits.move(str(player.element), slot)
	var direction: Vector3 = aim.normalized()
	var horizontal: Vector3 = Vector3(direction.x, 0.0, direction.z)
	var behavior: String = "level"
	if slot == "curve_shot":
		behavior = "curve"
		var threshold: float = float(data.pitch_threshold)
		if direction.y <= -threshold:
			behavior = "spike"
		elif direction.y >= threshold:
			behavior = "lob"
	var speed: float = float(data.speed)
	var velocity: Vector3 = direction * speed
	if behavior == "spike":
		velocity = horizontal.normalized() * float(data.spike_dive_speed) + Vector3.DOWN * absf(direction.y) * speed
	elif behavior == "lob":
		var lob_speed: float = speed * float(data.lob_speed_mult)
		velocity = horizontal.normalized() * lob_speed + Vector3.UP * maxf(0.0, direction.y * lob_speed)
	var side: Vector3 = Vector3(-horizontal.z, 0.0, horizontal.x).normalized()
	if slot == "curve_shot":
		velocity += side * strafe * float(data.curve_drift)
	var release_position: Vector3 = player.position + direction * (float(Tuning.BODY_RADIUS) + float(data.size))
	var id: int = int(world.next_entity_id)
	world.next_entity_id = id + 1
	var momentum: Vector3 = Vector3(player.velocity.x, 0.0, player.velocity.z)
	var projectile: Dictionary = {
		"id": id, "position": release_position, "velocity": velocity, "owner": owner,
		"element": str(player.element), "slot": slot, "age": 0.0, "deflections": 0,
		"behavior": behavior,
		"damage": float(data.damage) * float(data.spike_damage_mult if behavior == "spike" else data.lob_damage_mult if behavior == "lob" else 1.0),
		"kb_base": float(data.kb_base) * float(data.spike_kb_mult if behavior == "spike" else data.lob_kb_mult if behavior == "lob" else 1.0),
		"kb_scale": float(data.kb_scale) * float(data.spike_kb_mult if behavior == "spike" else data.lob_kb_mult if behavior == "lob" else 1.0),
		"momentum": momentum, "size": float(data.size),
		"duration": float(data.duration), "hitstun": float(data.hitstun),
		"kb_up": float(data.kb_up), "curve": strafe if slot == "curve_shot" else 0.0,
		"gravity": float(data.gravity), "homing": float(data.homing),
		"bounce_count": 0, "hit_ids": [],
		"spike_pop_speed": float(data.spike_pop_speed),
		"spike_damage_mult": float(data.spike_damage_mult),
		"spike_kb_mult": float(data.spike_kb_mult)
	}
	world.projectiles[id] = projectile
	world.events.append({"type": "projectile_spawn", "player": owner, "projectile": id, "slot": slot, "position": release_position})

static func spawn_wall(world: Dictionary, owner: int, aim: Vector3) -> void:
	if world.walls.size() >= Tuning.MAX_WALLS:
		return
	if not world.players.has(owner):
		return
	var player: Dictionary = world.players[owner]
	var data: Dictionary = Kits.move(str(player.element), "wall")
	var horizontal_aim: Vector3 = Vector3(aim.x, 0.0, aim.z).normalized()
	var horizontal_wall: bool = aim.y < float(data.wall_horizontal_threshold)
	var axis: Vector3 = horizontal_aim if horizontal_aim.length_squared() > 0.000001 else Vector3.FORWARD.rotated(Vector3.UP, float(player.yaw))
	var distance: float = float(data.placement_distance)
	var position: Vector3 = player.position + axis * distance
	var size: Vector3
	if horizontal_wall:
		size = Vector3(float(data.wall_width), float(data.wall_depth), float(data.wall_height))
		position.y = player.position.y - float(Tuning.BODY_HEIGHT) * 0.5 + (size.y * 0.5 if bool(player.on_ground) else 0.0)
	else:
		size = Vector3(float(data.wall_width), float(data.wall_height), float(data.wall_depth))
		position.y = player.position.y
	var id: int = int(world.next_entity_id)
	world.next_entity_id = id + 1
	var wall: Dictionary = {"id": id, "position": position, "size": size, "owner": owner, "element": str(player.element), "age": 0.0, "duration": float(data.duration), "hp": int(data.wall_hp), "hit_shoves": {}}
	world.walls[id] = wall
	world.events.append({"type": "wall_spawn", "player": owner, "wall": id, "position": position})

static func step(world: Dictionary, active_shoves: Dictionary, commands: Dictionary, dt: float) -> void:
	var walls: Dictionary = world.walls
	var projectiles: Dictionary = world.projectiles
	var wall_ids: Array = walls.keys()
	wall_ids.sort()
	var projectile_ids: Array = projectiles.keys()
	projectile_ids.sort()
	for wid in wall_ids:
		var wall: Dictionary = walls[wid]
		wall.age = float(wall.age) + dt
		if float(wall.age) >= float(wall.duration) or int(wall.hp) <= 0:
			walls.erase(wid)
	for pid in projectile_ids:
		if not projectiles.has(pid):
			continue
		var projectile: Dictionary = projectiles[pid]
		projectile.age = float(projectile.age) + dt
		if projectile.age >= projectile.duration:
			projectiles.erase(pid)
			continue
		var shooter: int = _deflector(world, projectile, active_shoves, commands)
		if shooter != -1:
			_deflect(projectile, world, shooter, commands[shooter])
		var start: Vector3 = projectile.position
		var velocity: Vector3 = projectile.velocity
		if float(projectile.homing) > 0.0:
			velocity = _home(world, projectile, velocity, dt)
		if float(projectile.curve) != 0.0:
			var side: Vector3 = Vector3(-velocity.z, 0.0, velocity.x).normalized()
			velocity += side * float(projectile.curve) * dt
		if projectile.behavior == "lob":
			velocity.y -= float(projectile.gravity) * dt
		elif projectile.behavior == "spike":
			velocity.y -= float(projectile.gravity) * dt
		projectile.velocity = velocity
		var finish: Vector3 = start + velocity * dt
		var best_t: float = 2.0
		var best_type: String = ""
		var best_id: int = -1
		for wid in wall_ids:
			if not walls.has(wid):
				continue
			var wall: Dictionary = walls[wid]
			var t: float = _segment_box_t(start, finish, wall.position, wall.size, float(projectile.size))
			if t >= 0.0 and t < best_t:
				best_t = t
				best_type = "wall"
				best_id = int(wid)
		var ids: Array = world.players.keys()
		ids.sort()
		for victim_id in ids:
			var victim: Dictionary = world.players[victim_id]
			if int(victim_id) == int(projectile.owner) or int(victim.stocks) <= 0 or float(victim.invuln) > 0.0 or projectile.hit_ids.has(int(victim_id)):
				continue
			var t: float = _segment_sphere_t(start, finish, victim.position, float(projectile.size) + float(Tuning.BODY_RADIUS))
			if t >= 0.0 and t < best_t:
				best_t = t
				best_type = "player"
				best_id = int(victim_id)
		var arena_t: float = _arena_hit_t(start, finish, float(projectile.size))
		if arena_t >= 0.0 and arena_t < best_t:
			best_t = arena_t
			best_type = "arena"
		var contact: Vector3 = start.lerp(finish, clampf(best_t, 0.0, 1.0)) if best_t <= 1.0 else finish
		if best_type == "wall":
			var hit_wall: Dictionary = walls[best_id]
			hit_wall.hp = int(hit_wall.hp) - 1
			world.events.append({"type": "wall_block", "player": int(hit_wall.owner), "projectile": int(pid), "position": contact})
			projectiles.erase(pid)
			if hit_wall.hp <= 0:
				walls.erase(best_id)
				world.events.append({"type": "wall_destroy", "player": int(hit_wall.owner), "wall": int(best_id), "position": contact})
		elif best_type == "player":
			var victim: int = best_id
			var move_data: Dictionary = Kits.move(str(projectile.element), str(projectile.slot))
			var hit_data: Dictionary = {"damage": float(projectile.damage), "kb_base": float(projectile.kb_base), "kb_scale": float(projectile.kb_scale), "momentum": float(move_data.momentum), "kb_up": float(projectile.kb_up), "hitstun": float(projectile.hitstun), "chain_window": float(move_data.chain_window), "chain_stun": float(move_data.chain_stun)}
			var hit_direction: Vector3 = velocity.normalized()
			if projectile.behavior == "spike":
				hit_direction = Vector3(velocity.x, absf(velocity.y) + float(projectile.spike_pop_speed), velocity.z).normalized()
			World.apply_move_hit(world, int(projectile.owner), victim, hit_data, hit_direction, projectile.momentum, str(projectile.slot))
			projectile.hit_ids.append(victim)
			if projectile.behavior == "spike" and int(projectile.bounce_count) == 0:
				projectile.position = finish
				projectiles[pid] = projectile
			else:
				projectiles.erase(pid)
		elif best_type == "arena" and projectile.behavior == "spike" and int(projectile.bounce_count) == 0:
			projectile.position = contact
			projectile.position.y += float(projectile.size) * 0.1
			projectile.bounce_count = 1
			projectile.velocity.y = float(projectile.spike_pop_speed)
			var spike_data: Dictionary = Kits.move(str(projectile.element), str(projectile.slot))
			var radius: float = float(spike_data.slam_radius)
			var targets: Array = world.players.keys()
			targets.sort()
			for target_id in targets:
				var target: Dictionary = world.players[target_id]
				if int(target_id) == int(projectile.owner) or int(target.stocks) <= 0 or float(target.invuln) > 0.0 or projectile.hit_ids.has(int(target_id)):
					continue
				var offset: Vector3 = target.position - contact
				if Vector2(offset.x, offset.z).length() > radius or offset.y > float(Tuning.BODY_HEIGHT) + radius:
					continue
				var hit_data: Dictionary = {"damage": float(projectile.damage), "kb_base": float(projectile.kb_base), "kb_scale": float(projectile.kb_scale), "momentum": float(spike_data.momentum), "kb_up": float(projectile.kb_up), "hitstun": float(projectile.hitstun), "chain_window": float(spike_data.chain_window), "chain_stun": float(spike_data.chain_stun)}
				World.apply_move_hit(world, int(projectile.owner), int(target_id), hit_data, Vector3.UP, projectile.momentum, str(projectile.slot))
				projectile.hit_ids.append(int(target_id))
			projectiles[pid] = projectile
		elif best_type == "arena":
			projectiles.erase(pid)
		else:
			projectile.position = finish
			if projectile.behavior == "curve":
				var state: Dictionary = Kits.move(str(projectile.element), str(projectile.slot))
				var drift: float = float(state.curve_drift)
				var curve_rate: float = float(state.curve_rate)
				var curve_sign: float = signf(float(projectile.curve))
				if curve_sign != 0.0:
					projectile.curve = float(projectile.curve) + curve_sign * absf(curve_rate) * dt
				else:
					curve_sign = 1.0
				projectile.velocity += Vector3(-projectile.velocity.z, 0.0, projectile.velocity.x).normalized() * drift * maxf(absf(float(projectile.curve)), drift) * curve_sign * dt
			projectiles[pid] = projectile
	for wid in wall_ids:
		if not walls.has(wid):
			continue
		var wall: Dictionary = walls[wid]
		for attacker_id in active_shoves.keys():
			if not bool(active_shoves[attacker_id]) or not world.players.has(int(attacker_id)):
				continue
			var attacker: Dictionary = world.players[int(attacker_id)]
			if not _in_shove(attacker, wall.position, float(Tuning.SHOVE_RADIUS) + maxf(wall.size.x, wall.size.z) * 0.5):
				continue
			var serial: int = int(attacker.attack_serial)
			if int(wall.hit_shoves.get(int(attacker_id), -1)) == serial:
				continue
			wall.hit_shoves[int(attacker_id)] = serial
			wall.hp = int(wall.hp) - 1
			if wall.hp <= 0:
				walls.erase(wid)
				break

static func _deflector(world: Dictionary, projectile: Dictionary, active: Dictionary, commands: Dictionary) -> int:
	var ids: Array = active.keys()
	ids.sort()
	for id in ids:
		if not bool(active[id]) or int(id) == int(projectile.owner) or not world.players.has(int(id)) or not commands.has(int(id)):
			continue
		var player: Dictionary = world.players[int(id)]
		if _in_shove(player, projectile.position, float(Tuning.SHOVE_RADIUS) + float(projectile.size)):
			return int(id)
	return -1

static func _deflect(projectile: Dictionary, world: Dictionary, owner: int, command: InputCmd) -> void:
	var old_speed: float = projectile.velocity.length()
	var move_data: Dictionary = Kits.move(str(world.players[owner].element), "shove")
	var direction: Vector3 = World.aim_direction(command.yaw, command.pitch).normalized()
	var new_speed: float = minf(old_speed * float(move_data.deflect_speed_gain), minf(float(move_data.max_speed), float(Tuning.DEFLECT_SPEED_CAP)))
	projectile.velocity = direction * new_speed
	projectile.damage = minf(float(projectile.damage) * float(move_data.deflect_damage_gain), minf(float(move_data.max_damage), float(Tuning.DEFLECT_DAMAGE_CAP)))
	projectile.owner = owner
	projectile.deflections = int(projectile.deflections) + 1
	projectile.momentum = Vector3(world.players[owner].velocity.x, 0.0, world.players[owner].velocity.z)
	world.events.append({"type": "deflect", "player": owner, "projectile": int(projectile.id), "position": projectile.position})

static func _home(world: Dictionary, projectile: Dictionary, velocity: Vector3, dt: float) -> Vector3:
	var ids: Array = world.players.keys()
	ids.sort()
	var target_id: int = -1
	var best: float = INF
	for id in ids:
		var p: Dictionary = world.players[id]
		if int(id) == int(projectile.owner) or int(p.stocks) <= 0 or bool(p.on_ground):
			continue
		var distance: float = projectile.position.distance_squared_to(p.position)
		if distance < best:
			best = distance
			target_id = int(id)
	if target_id == -1:
		return velocity
	var target: Vector3 = (world.players[target_id].position - projectile.position).normalized()
	var speed: float = velocity.length()
	return velocity.normalized().slerp(target, clampf(float(projectile.homing) * dt, 0.0, 1.0)).normalized() * speed

static func _in_shove(player: Dictionary, point: Vector3, radius: float) -> bool:
	var forward: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, float(player.yaw))
	var centre: Vector3 = player.position + forward * float(Tuning.SHOVE_REACH)
	var offset: Vector3 = point - centre
	return offset.length_squared() <= radius * radius

static func _segment_sphere_t(a: Vector3, b: Vector3, centre: Vector3, radius: float) -> float:
	var axis: Vector3 = b - a
	var length_sq: float = axis.length_squared()
	if length_sq <= 0.000001:
		return 0.0 if a.distance_squared_to(centre) <= radius * radius else -1.0
	var t: float = clampf((centre - a).dot(axis) / length_sq, 0.0, 1.0)
	return t if a.lerp(b, t).distance_squared_to(centre) <= radius * radius else -1.0

static func _segment_box_t(a: Vector3, b: Vector3, centre: Vector3, size: Vector3, radius: float) -> float:
	var lo: Vector3 = centre - size * 0.5 - Vector3.ONE * radius
	var hi: Vector3 = centre + size * 0.5 + Vector3.ONE * radius
	var delta: Vector3 = b - a
	var near_t: float = 0.0
	var far_t: float = 1.0
	for axis in 3:
		var origin: float = a[axis]
		var movement: float = delta[axis]
		if absf(movement) < 0.000001:
			if origin < lo[axis] or origin > hi[axis]:
				return -1.0
		else:
			var t1: float = (lo[axis] - origin) / movement
			var t2: float = (hi[axis] - origin) / movement
			near_t = maxf(near_t, minf(t1, t2))
			far_t = minf(far_t, maxf(t1, t2))
			if near_t > far_t:
				return -1.0
	return near_t if near_t <= 1.0 else -1.0

static func _arena_hit_t(a: Vector3, b: Vector3, radius: float) -> float:
	var earliest: float = -1.0
	var platform_size: float = float(Tuning.PLATFORM_SIZE)
	var platform_thickness: float = float(Tuning.PLATFORM_THICKNESS)
	var t: float = _segment_box_t(a, b, Vector3(0.0, -platform_thickness * 0.5, 0.0), Vector3(platform_size, platform_thickness, platform_size), radius)
	earliest = _earlier(earliest, t)
	var center_height: float = float(Tuning.CENTER_HEIGHT)
	t = _segment_box_t(a, b, Vector3(0.0, center_height - platform_thickness * 0.5, 0.0), Vector3(float(Tuning.CENTER_SIZE), platform_thickness, float(Tuning.CENTER_SIZE)), radius)
	earliest = _earlier(earliest, t)
	for index in [2, 3]:
		t = _ramp_hit_t(a, b, radius, int(index))
		earliest = _earlier(earliest, t)
	for sign_value in [-1.0, 1.0]:
		var ledge_x: float = float(Tuning.LEDGE_OFFSET) * sign_value
		var ledge_size: Vector3 = Vector3(float(Tuning.LEDGE_WIDTH), platform_thickness, float(Tuning.LEDGE_LENGTH))
		var ledge_position: Vector3 = Vector3(ledge_x, float(Tuning.LEDGE_HEIGHT) - platform_thickness * 0.5, 0.0)
		t = _segment_box_t(a, b, ledge_position, ledge_size, radius)
		earliest = _earlier(earliest, t)
	return earliest

static func _ramp_hit_t(a: Vector3, b: Vector3, radius: float, surface: int) -> float:
	var ramp_x: float = -float(Tuning.RAMP_OFFSET) if surface == 2 else float(Tuning.RAMP_OFFSET)
	var half_width: float = float(Tuning.RAMP_WIDTH) * 0.5 + radius
	var half_length: float = float(Tuning.RAMP_LENGTH) * 0.5 + radius
	var half_thickness: float = float(Tuning.RAMP_THICKNESS) * 0.5 + radius
	var slope: float = float(Tuning.RAMP_HEIGHT) / float(Tuning.RAMP_LENGTH)
	var intercept: float = float(Tuning.RAMP_HEIGHT) * 0.5
	var normal: Vector3 = Vector3(0.0, 1.0, slope).normalized()
	var plane_offset: float = intercept / sqrt(1.0 + slope * slope)
	var delta: Vector3 = b - a
	var best: float = -1.0
	for offset in [-half_thickness, half_thickness]:
		var denominator: float = normal.dot(delta)
		if absf(denominator) < 0.000001:
			continue
		var t: float = (plane_offset + float(offset) - normal.dot(a)) / denominator
		if t < 0.0 or t > 1.0:
			continue
		var point: Vector3 = a.lerp(b, t)
		if absf(point.x - ramp_x) <= half_width and absf(point.z) <= half_length:
			best = t if best < 0.0 else minf(best, t)
	var x_size: Vector3 = Vector3(float(Tuning.RAMP_WIDTH) + radius * 2.0, float(Tuning.RAMP_HEIGHT) + float(Tuning.RAMP_THICKNESS) + radius * 2.0, float(Tuning.RAMP_LENGTH) + radius * 2.0)
	var x_side: float = _segment_box_t(a, b, Vector3(ramp_x - float(Tuning.RAMP_WIDTH) * 0.5, float(Tuning.RAMP_HEIGHT) * 0.5, 0.0), Vector3(radius * 2.0, x_size.y, x_size.z), 0.0)
	best = _earlier(best, x_side)
	x_side = _segment_box_t(a, b, Vector3(ramp_x + float(Tuning.RAMP_WIDTH) * 0.5, float(Tuning.RAMP_HEIGHT) * 0.5, 0.0), Vector3(radius * 2.0, x_size.y, x_size.z), 0.0)
	best = _earlier(best, x_side)
	x_side = _segment_box_t(a, b, Vector3(ramp_x, float(Tuning.RAMP_HEIGHT) * 0.25, -float(Tuning.RAMP_LENGTH) * 0.5), Vector3(x_size.x, x_size.y, radius * 2.0), 0.0)
	best = _earlier(best, x_side)
	x_side = _segment_box_t(a, b, Vector3(ramp_x, float(Tuning.RAMP_HEIGHT) * 0.75, float(Tuning.RAMP_LENGTH) * 0.5), Vector3(x_size.x, x_size.y, radius * 2.0), 0.0)
	best = _earlier(best, x_side)
	return best

static func _earlier(current: float, candidate: float) -> float:
	if candidate < 0.0:
		return current
	return candidate if current < 0.0 else minf(current, candidate)
