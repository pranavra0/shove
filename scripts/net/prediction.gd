class_name ClientPrediction
extends RefCounted

# Pending wire commands and simulation state never share ownership with the session.
var predicted: Dictionary = {}
var pending: Array = []
var correction_magnitude: float = 0.0
var _id: int = 0
var _durations: Dictionary = {}
var _history: Array = []
var _offset: Vector3 = Vector3.ZERO
var _last_ack: int = -1
var _last_sequence: int = -1
var _last_tick: int = -1
const HISTORY_LIMIT: int = 64

func begin(world: Dictionary, id: int, now: float) -> void:
	_id = id
	predicted = world.duplicate(true)
	pending.clear()
	_durations.clear()
	_history.clear()
	_offset = Vector3.ZERO
	correction_magnitude = 0.0
	_last_ack = -1
	_last_sequence = -1
	_last_tick = int(world.get("tick", 0))
	_history.append({"time": now, "world": world.duplicate(true)})

func advance(cmd: InputCmd, dt: float) -> Dictionary:
	if predicted.is_empty() or cmd.tick <= _last_sequence:
		return predicted.duplicate(true)
	_last_sequence = cmd.tick
	pending.append(cmd.to_dict().duplicate(true))
	_durations[cmd.tick] = dt
	while pending.size() > maxi(1, Tuning.NET_MAX_PENDING):
		var removed: Dictionary = pending.pop_front()
		_durations.erase(int(removed.tick))
	predicted = _step_local(predicted, cmd, dt)
	return predicted.duplicate(true)

func _step_local(world: Dictionary, cmd: InputCmd, dt: float) -> Dictionary:
	var result: Dictionary = world.duplicate(true)
	result.events = []
	if not world.players.has(_id):
		return result
	# The simulation helper predicts only this player; entities and authoritative combat
	# state remain the untouched deep copy from the latest server snapshot.
	var player: Dictionary = World.predict_player(world, _id, cmd, dt)
	result.players[_id] = player
	return result

func reconcile(world: Dictionary, ack: int, now: float) -> void:
	var tick: int = int(world.get("tick", 0))
	if tick < _last_tick or ack < _last_ack or (tick == _last_tick and ack == _last_ack):
		return
	var previous: Dictionary = predicted
	var previous_authority: Dictionary = _history.back().world if not _history.is_empty() else {}
	_last_tick = tick
	_last_ack = ack
	_last_sequence = maxi(_last_sequence, ack)
	while not pending.is_empty() and int(pending[0].tick) <= ack:
		var removed: Dictionary = pending.pop_front()
		_durations.erase(int(removed.tick))
	predicted = world.duplicate(true)
	for wire in pending:
		var cmd: InputCmd = InputCmd.from_dict(wire)
		predicted = _step_local(predicted, cmd, float(_durations[int(wire.tick)]))
	if previous.get("players", {}).has(_id) and predicted.players.has(_id):
		var old_player: Dictionary = previous.players[_id]
		var new_player: Dictionary = predicted.players[_id]
		var reset: bool = _discontinuous(old_player, new_player)
		if previous_authority.get("players", {}).has(_id) and world.players.has(_id):
			reset = reset or _discontinuous(previous_authority.players[_id], world.players[_id])
		_offset = Vector3.ZERO if reset else old_player.position + _offset - new_player.position
		if _offset.length() <= Tuning.NET_RECONCILE_EPSILON:
			_offset = Vector3.ZERO
	else:
		_offset = Vector3.ZERO
	correction_magnitude = _offset.length()
	_history.append({"time": now, "world": world.duplicate(true)})
	while _history.size() > HISTORY_LIMIT:
		_history.pop_front()

func _discontinuous(a: Dictionary, b: Dictionary) -> bool:
	return a.stocks != b.stocks or a.spawn != b.spawn or (float(b.invuln) > float(a.invuln) + 0.00001) or a.position.distance_to(b.position) > Tuning.NET_TELEPORT_DISTANCE

func render_world(now: float, delta: float) -> Dictionary:
	if predicted.is_empty():
		return {}
	_offset *= exp(-maxf(0.0, Tuning.NET_CORRECTION_SPEED) * maxf(0.0, delta))
	if _offset.length() <= Tuning.NET_RECONCILE_EPSILON:
		_offset = Vector3.ZERO
	correction_magnitude = _offset.length()
	var result: Dictionary = predicted.duplicate(true)
	var target: float = now - Tuning.NET_INTERPOLATION
	if not _history.is_empty():
		var left: Dictionary = _history.front()
		var right: Dictionary = _history.back()
		if target <= float(left.time):
			right = left
		elif target >= float(right.time):
			left = right
		else:
			for index in range(1, _history.size()):
				if float(_history[index].time) >= target:
					left = _history[index - 1]
					right = _history[index]
					break
		var span: float = float(right.time) - float(left.time)
		var weight: float = clampf((target - float(left.time)) / span, 0.0, 1.0) if span > 0.0 else 1.0
		var left_world: Dictionary = left.world
		var right_world: Dictionary = right.world
		for id in right_world.players:
			if int(id) == _id:
				continue
			var b: Dictionary = right_world.players[id]
			var remote: Dictionary = b.duplicate(true)
			if left_world.players.has(id):
				var a: Dictionary = left_world.players[id]
				if not _discontinuous(a, b):
					remote.position = a.position.lerp(b.position, weight)
					remote.velocity = a.velocity.lerp(b.velocity, weight)
					remote.yaw = lerp_angle(float(a.yaw), float(b.yaw), weight)
			result.players[id] = remote
		var left_projectiles: Dictionary = left_world.get("projectiles", {})
		var right_projectiles: Dictionary = right_world.get("projectiles", {})
		var discrete_world: Dictionary = right_world if weight >= 1.0 else left_world
		var rendered_projectiles: Dictionary = discrete_world.get("projectiles", {}).duplicate(true)
		for id in rendered_projectiles:
			if not left_projectiles.has(id) or not right_projectiles.has(id):
				continue
			var a_projectile: Dictionary = left_projectiles[id]
			var b_projectile: Dictionary = right_projectiles[id]
			if int(a_projectile.owner) != int(b_projectile.owner) or str(a_projectile.behavior) != str(b_projectile.behavior):
				continue
			var rendered: Dictionary = rendered_projectiles[id]
			var from_position: Vector3 = a_projectile.position
			var to_position: Vector3 = b_projectile.position
			var from_velocity: Vector3 = a_projectile.velocity
			var to_velocity: Vector3 = b_projectile.velocity
			rendered.position = from_position.lerp(to_position, weight)
			rendered.velocity = from_velocity.lerp(to_velocity, weight)
			rendered_projectiles[id] = rendered
		result["projectiles"] = rendered_projectiles
		var historical_walls: Dictionary = discrete_world.get("walls", {})
		result["walls"] = historical_walls.duplicate(true)
	if result.players.has(_id):
		result.players[_id].position += _offset
	return result

func unacknowledged() -> Array:
	return pending.duplicate(true)
