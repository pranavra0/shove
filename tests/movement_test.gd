extends SceneTree

var MovementSim: GDScript

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	MovementSim = load("res://scripts/sim/movement.gd")
	var tune: Node = load("res://scripts/tuning.gd").new()
	var dt: float = 1.0 / tune.TICK_RATE
	var cmd := InputCmd.new(Vector2.RIGHT, false, false, 0.0, 1)
	var start := {"velocity": Vector3.ZERO, "on_ground": true, "ground_angle": 0.0}
	var accelerated: Dictionary = MovementSim.step(start, cmd, dt)
	assert(accelerated.velocity.x > 0.0)
	assert(accelerated.velocity.x <= tune.WALK_SPEED)
	var fast := {"velocity": Vector3(tune.WALK_SPEED, 0.0, 0.0), "on_ground": true, "ground_angle": 0.0}
	var friction: Dictionary = MovementSim.step(fast, InputCmd.new(), dt)
	assert(friction.velocity.x < tune.WALK_SPEED)
	var air := {"velocity": Vector3.ZERO, "on_ground": false, "ground_angle": 0.0}
	var airborne: Dictionary = MovementSim.step(air, cmd, dt)
	assert(airborne.velocity.x <= tune.AIR_SPEED_CAP)
	var capped: Dictionary = MovementSim.step({"velocity": Vector3(tune.AIR_SPEED_CAP, 0.0, 0.0), "on_ground": false, "ground_angle": 0.0}, cmd, dt)
	assert(is_equal_approx(capped.velocity.x, tune.AIR_SPEED_CAP))
	var jump_cmd := InputCmd.new(Vector2.ZERO, true, false, 0.0, 2)
	var jumping: Dictionary = MovementSim.step(fast, jump_cmd, dt)
	assert(is_equal_approx(jumping.velocity.x, tune.WALK_SPEED))
	assert(is_equal_approx(jumping.velocity.y, tune.JUMP_SPEED))
	var strafe := InputCmd.new(Vector2.DOWN, false, false, 0.0, 3)
	var air_speed: float = tune.AIR_SPEED_CAP
	var air_result: Dictionary = MovementSim.step({"velocity": Vector3(air_speed, 0.0, 0.0), "on_ground": false, "ground_angle": 0.0}, strafe, dt)
	assert(Vector2(air_result.velocity.x, air_result.velocity.z).length() > air_speed)
	var bhopping: Dictionary = jumping
	for frame in range(1000):
		var horizontal := Vector2(bhopping.velocity.x, bhopping.velocity.z)
		var forward := horizontal.normalized()
		var perpendicular := Vector2(-forward.y, forward.x)
		var target_dot: float = tune.AIR_SPEED_CAP - tune.AIR_ACCELERATION * tune.AIR_SPEED_CAP * dt
		var forward_dot: float = clampf(target_dot / horizontal.length(), -1.0, 1.0)
		var wish := forward * forward_dot + perpendicular * sqrt(1.0 - forward_dot * forward_dot)
		var strafe_yaw: float = atan2(-wish.y, wish.x)
		bhopping = MovementSim.step({"velocity": bhopping.velocity, "on_ground": false, "ground_angle": 0.0}, InputCmd.new(Vector2.RIGHT, false, false, strafe_yaw, frame), dt)
		if Vector2(bhopping.velocity.x, bhopping.velocity.z).length() > tune.WALK_SPEED:
			break
	assert(Vector2(bhopping.velocity.x, bhopping.velocity.z).length() > tune.WALK_SPEED)
	print("PASS movement accelerate/friction/air-cap/jump/bhop-speed")
	tune.free()
	call_deferred("quit", 0)
