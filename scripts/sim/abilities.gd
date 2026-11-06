class_name AbilitySim
extends RefCounted

static func before_move(world: Dictionary, id: int, cmd: InputCmd, dt: float, predict: bool = false, stunned: bool = false) -> void:
	if not world.players.has(id):
		return
	var player: Dictionary = world.players[id]
	var step_dt: float = maxf(dt, 0.0)
	var cooldowns: Dictionary = player.cooldowns
	for slot in cooldowns.keys():
		cooldowns[slot] = maxf(0.0, float(cooldowns[slot]) - step_dt)
	player.cooldowns = cooldowns
	var was_jump_held: bool = bool(player.get("jump_held", false))
	player.jump_held = cmd.jump
	var state: Dictionary = player.move_state
	if not state.is_empty():
		var remaining: float = step_dt
		if not bool(state.activated):
			var windup: float = float(state.windup)
			if remaining >= windup:
				remaining -= windup
				state.windup = 0.0
				_activate(world, id, player, state, cmd, predict)
			else:
				state.windup = windup - remaining
				remaining = 0.0
		if bool(state.activated):
			state.duration = maxf(0.0, float(state.duration) - remaining)
			if float(state.duration) <= 0.0:
				state = {}
		player.move_state = state
		return
	if stunned:
		return
	var intents: Array = [
		["recovery", InputCmd.RECOVERY], ["down_dash", InputCmd.DOWN_DASH],
		["high_jump", InputCmd.HIGH_JUMP], ["h_dash", InputCmd.H_DASH],
		["wall", InputCmd.WALL], ["curve_shot", InputCmd.CURVE_SHOT],
		["quick_fire", InputCmd.QUICK_FIRE], ["basic_shot", InputCmd.BASIC_SHOT],
	]
	var requests: int = int(cmd.moves)
	if cmd.jump and not was_jump_held and not bool(player.on_ground):
		requests |= InputCmd.RECOVERY
	var element: String = str(player.element)
	var selected: String = ""
	for intent in intents:
		var slot: String = str(intent[0])
		var bit: int = int(intent[1])
		if (requests & bit) == 0 or float(cooldowns.get(slot, 0.0)) > 0.0 or not _valid_activation(player, slot):
			continue
		if slot == "recovery" and int(player.recovery_used) >= Kits.recovery_uses(element):
			continue
		selected = slot
		break
	if selected == "":
		return
	var data: Dictionary = Kits.move(element, selected)
	var aim: Vector3 = World.aim_direction(cmd.yaw, cmd.pitch).normalized()
	var state_new: Dictionary = {"slot": selected, "windup": maxf(0.0, float(data.get("windup", 0.0))), "duration": maxf(0.0, float(data.get("active", 0.0))), "aim": aim, "strafe": cmd.move.x, "activated": false}
	player.cooldowns[selected] = maxf(0.0, float(data.get("cooldown", 0.0)))
	player.move_state = state_new
	# Consume this tick's windup, preserving the move's deterministic activation tick.
	if step_dt >= float(state_new.windup):
		var remaining_dt: float = step_dt - float(state_new.windup)
		state_new.windup = 0.0
		_activate(world, id, player, state_new, cmd, predict)
		state_new.duration = maxf(0.0, float(state_new.duration) - remaining_dt)
		if float(state_new.duration) <= 0.0:
			player.move_state = {}
		else:
			player.move_state = state_new
	else:
		state_new.windup = float(state_new.windup) - step_dt
		player.move_state = state_new

static func after_move(world: Dictionary, id: int, was_grounded: bool, predict: bool = false) -> void:
	if not world.players.has(id):
		return
	var player: Dictionary = world.players[id]
	if bool(player.on_ground):
		if bool(player.down_dashing):
			if not predict:
				var victim_ids: Array = world.players.keys()
				victim_ids.sort()
				for victim_id in victim_ids:
					if int(victim_id) != id:
						World._slam_hit(world, id, int(victim_id))
			player.down_dashing = false
			player.dash_time = 0.0
		player.recovery_used = 0

static func _valid_activation(player: Dictionary, slot: String) -> bool:
	match slot:
		"high_jump":
			return bool(player.on_ground)
		"down_dash":
			return not bool(player.on_ground)
		"recovery":
			return not bool(player.on_ground)
		_:
			return true

static func _activate(world: Dictionary, id: int, player: Dictionary, state: Dictionary, cmd: InputCmd, predict: bool) -> void:
	if bool(state.activated):
		return
	var slot: String = str(state.slot)
	var data: Dictionary = Kits.move(str(player.element), slot)
	var direction: Vector3 = state.aim
	var velocity: Vector3 = player.velocity
	var horizontal: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	match slot:
		"basic_shot", "curve_shot", "quick_fire":
			if not predict:
				ProjectileSim.spawn_projectile(world, id, slot, direction, float(state.strafe))
		"wall":
			if not predict:
				ProjectileSim.spawn_wall(world, id, direction)
		"high_jump":
			velocity.y = float(data.get("speed", Tuning.JUMP_SPEED))
			player.on_ground = false
		"down_dash":
			velocity.y = -absf(float(data.get("speed", 0.0)))
			player.down_dashing = true
			player.dash_time = float(data.get("duration", 0.0))
		"h_dash":
			var dash: Vector3 = Vector3(direction.x, 0.0, direction.z)
			if dash.length_squared() <= 0.000001:
				dash = Vector3.FORWARD.rotated(Vector3.UP, cmd.yaw)
			dash = dash.normalized() * float(data.get("speed", 0.0))
			if float(data.get("preserve_momentum", 0.0)) > 0.0:
				horizontal += dash * float(data.get("preserve_momentum", 0.0))
			else:
				horizontal = dash
			velocity.x = horizontal.x
			velocity.z = horizontal.z
		"recovery":
			var recovery: Vector3 = Vector3(direction.x, 0.0, direction.z)
			if recovery.length_squared() > 0.000001:
				recovery = recovery.normalized() * float(data.get("recovery_horizontal", 0.0))
			else:
				recovery = Vector3.ZERO
			velocity.x = recovery.x
			velocity.z = recovery.z
			velocity.y = float(data.get("recovery_up", data.get("speed", 0.0)))
			player.recovery_used = int(player.recovery_used) + 1
	player.velocity = velocity
	var iframe: float = float(data.get("iframe_time", 0.0))
	if iframe > 0.0:
		player.invuln = maxf(float(player.invuln), iframe)
	state.activated = true
	if world.has("events"):
		world.events.append({"type": "move", "player": id, "slot": slot, "position": player.position})
