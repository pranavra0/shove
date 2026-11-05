class_name MovementSim
extends RefCounted

# Input: velocity, on_ground, ground_angle; optional control_scale scales air acceleration.
# Output is a new state dictionary; this method does not read or mutate scene state.
static func step(state: Dictionary, cmd: InputCmd, dt: float) -> Dictionary:
	var velocity: Vector3 = state.get("velocity", Vector3.ZERO)
	var ground_angle: float = state.get("ground_angle", 0.0)
	var grounded: bool = state.get("on_ground", false) and ground_angle <= Tuning.MAX_GROUND_ANGLE
	var wish := Vector3(cmd.move.x, 0.0, cmd.move.y).rotated(Vector3.UP, cmd.yaw)
	if wish.length_squared() > 1.0:
		wish = wish.normalized()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var jumping := grounded and cmd.jump
	if grounded and not jumping:
		var speed := horizontal.length()
		if speed > 0.0:
			var control: float = maxf(speed, Tuning.STOP_SPEED)
			var drop: float = control * Tuning.FRICTION * dt
			horizontal *= maxf(speed - drop, 0.0) / speed
	if grounded:
		velocity.y = 0.0
	else:
		velocity.y -= Tuning.GRAVITY * dt
	if wish.length_squared() > 0.0:
		var wish_speed: float = Tuning.WALK_SPEED
		var accel: float = Tuning.GROUND_ACCELERATION if grounded else Tuning.AIR_ACCELERATION
		if not grounded:
			wish_speed = minf(wish_speed, Tuning.AIR_SPEED_CAP)
		var current_speed := horizontal.dot(wish)
		var add_speed := wish_speed - current_speed
		if add_speed > 0.0:
			var control_scale: float = 1.0 if grounded else state.get("control_scale", 1.0)
			var acceleration: float = minf(accel * wish_speed * dt * control_scale, add_speed)
			horizontal += wish * acceleration
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if jumping:
		velocity.y = Tuning.JUMP_SPEED
	return {"velocity": velocity, "on_ground": grounded and not jumping, "ground_angle": ground_angle, "tick": cmd.tick}
