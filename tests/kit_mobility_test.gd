extends SceneTree

var Tuning: Node
var World: GDScript
var Kits: GDScript
var ProjectileSim: GDScript
const TAPE = preload("res://scripts/dev/replay.gd")
const BITS: Dictionary = {"high_jump": InputCmd.HIGH_JUMP, "h_dash": InputCmd.H_DASH, "down_dash": InputCmd.DOWN_DASH, "recovery": InputCmd.RECOVERY, "wall": InputCmd.WALL}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	Tuning = root.get_node("Tuning")
	World = load("res://scripts/sim/world.gd")
	Kits = load("res://scripts/sim/kits.gd")
	ProjectileSim = load("res://scripts/sim/projectiles.gd")
	var center: float = float(Tuning.CENTER_HEIGHT)
	var ramp: float = float(Tuning.RAMP_HEIGHT)
	var ledge: float = float(Tuning.LEDGE_HEIGHT)
	Tuning.CENTER_HEIGHT = 0.0
	Tuning.RAMP_HEIGHT = 0.0
	Tuning.LEDGE_HEIGHT = 0.0
	_test_jump_and_air_dash()
	_test_kit_movement_scalars()
	_test_slam_and_recovery()
	_test_offstage_recovery()
	_test_wall_shapes_and_tuning()
	_test_wall_projectile_contacts()
	_test_wall_shove_contacts()
	_test_wall_support_and_expiry()
	_test_wall_walkoff_and_horizontal_impulse()
	Tuning.CENTER_HEIGHT = center
	Tuning.RAMP_HEIGHT = ramp
	Tuning.LEDGE_HEIGHT = ledge
	print("PASS mobility/wall regressions")
	call_deferred("quit", 0)

func _fixture() -> Dictionary:
	var world: Dictionary = World.create([1, 2])
	_put(world.players[1], Vector3(4.0, Tuning.BODY_HEIGHT * 0.5, 6.0))
	_put(world.players[2], Vector3(-4.0, Tuning.BODY_HEIGHT * 0.5, -6.0))
	return world

func _put(player: Dictionary, point: Vector3) -> void:
	player.position = point
	player.velocity = Vector3.ZERO
	player.on_ground = is_equal_approx(point.y, World.floor_height(point) + Tuning.BODY_HEIGHT * 0.5)
	player.ground_angle = World.floor_angle(point)

func _cmd(moves: int = 0, yaw: float = 0.0, pitch: float = 0.0, move: Vector2 = Vector2.ZERO, jump: bool = false) -> InputCmd:
	var cmd: InputCmd = InputCmd.new(move, jump, false, yaw)
	cmd.moves = moves
	cmd.pitch = pitch
	return cmd

func _step(world: Dictionary, cmd: InputCmd = null) -> Dictionary:
	return World.step(world, {1: cmd} if cmd != null else {}, Tuning.FIXED_DELTA)

func _activate(world: Dictionary, slot: String, yaw: float = 0.0, pitch: float = 0.0) -> Dictionary:
	var data: Dictionary = Kits.move(str(world.players[1].element), slot)
	var ticks: int = int(ceil(float(data.windup) / Tuning.FIXED_DELTA))
	world = _step(world, _cmd(int(BITS[slot]), yaw, pitch))
	for tick in range(ticks - 1):
		world = _step(world)
	return _step(world)

func _count(events: Array, kind: String) -> int:
	var count: int = 0
	for event: Dictionary in events:
		if str(event.get("type", "")) == kind:
			count += 1
	return count

func _wall_fixture(element: String, horizontal: bool = false) -> Dictionary:
	var world: Dictionary = _fixture()
	World.set_element(world, 1, element)
	ProjectileSim.spawn_wall(world, 1, Vector3.DOWN if horizontal else Vector3.FORWARD)
	return world

func _test_jump_and_air_dash() -> void:
	for element: String in Kits.ELEMENTS:
		var world: Dictionary = _fixture()
		World.set_element(world, 1, element)
		var config: Dictionary = Kits.move(element, "high_jump")
		var ticks: int = int(ceil(float(config.windup) / Tuning.FIXED_DELTA))
		world = _step(world, _cmd(int(BITS.high_jump)))
		for tick in range(ticks - 1):
			world = _step(world)
		assert(float(world.players[1].velocity.y) > Tuning.JUMP_SPEED, "%s high jump must use its boosted launch after windup" % element)
		var air: Dictionary = _fixture()
		World.set_element(air, 1, element)
		_put(air.players[1], Vector3(4.0, 5.0, 6.0))
		air.players[1].velocity = Vector3(3.0, 0.0, 4.0)
		air = _activate(air, "h_dash")
		var dash: Vector3 = Vector3(air.players[1].velocity.x, 0.0, air.players[1].velocity.z)
		var data: Dictionary = Kits.move(element, "h_dash")
		var expected: Vector3 = Vector3.FORWARD * float(data.speed)
		if element == "air":
			expected += Vector3(3.0, 0.0, 4.0)
		assert(dash.is_equal_approx(expected), "%s horizontal dash momentum behavior changed" % element)

func _test_kit_movement_scalars() -> void:
	for element: String in Kits.ELEMENTS:
		var movement: Dictionary = Kits.movement(element)
		var ground: Dictionary = _fixture()
		World.set_element(ground, 1, element)
		ground = _step(ground, _cmd(0, 0.0, 0.0, Vector2.RIGHT))
		var expected_ground: float = minf(Tuning.GROUND_ACCELERATION * Tuning.WALK_SPEED * float(movement.ground_speed) * Tuning.FIXED_DELTA, Tuning.WALK_SPEED * float(movement.ground_speed))
		assert(is_equal_approx(float(ground.players[1].velocity.x), expected_ground), "%s World ground movement uses kit multiplier" % element)
		var air: Dictionary = _fixture()
		World.set_element(air, 1, element)
		_put(air.players[1], Vector3(4.0, 5.0, 6.0))
		air = _step(air, _cmd(0, 0.0, 0.0, Vector2.RIGHT))
		var wish_speed: float = minf(Tuning.WALK_SPEED * float(movement.ground_speed), Tuning.AIR_SPEED_CAP)
		var expected_air: float = minf(Tuning.AIR_ACCELERATION * wish_speed * float(movement.air_accel) * Tuning.FIXED_DELTA, Tuning.AIR_SPEED_CAP)
		assert(is_equal_approx(float(air.players[1].velocity.x), expected_air), "%s World air movement uses kit multiplier and shared speed cap" % element)
		var jump: Dictionary = _fixture()
		World.set_element(jump, 1, element)
		jump = _step(jump, _cmd(0, 0.0, 0.0, Vector2.ZERO, true))
		assert(is_equal_approx(float(jump.players[1].velocity.y), Tuning.JUMP_SPEED * float(movement.jump)), "%s World jump uses kit multiplier" % element)
		jump.players[1].position = Vector3(4.0, Tuning.BODY_HEIGHT * 0.5, 6.0)
		jump.players[1].velocity = Vector3.ZERO
		jump.players[1].on_ground = true
		jump = _step(jump, _cmd(0, 0.0, 0.0, Vector2.ZERO, true))
		assert(is_equal_approx(float(jump.players[1].velocity.y), Tuning.JUMP_SPEED * float(movement.jump)), "%s held jump auto-hops after a grounded landing" % element)

func _test_slam_and_recovery() -> void:
	var slam: Dictionary = _fixture()
	_put(slam.players[1], Vector3(4.0, 8.0, 6.0))
	_put(slam.players[2], Vector3(4.0, Tuning.BODY_HEIGHT * 0.5, 4.5))
	slam = _step(slam, _cmd(int(BITS.down_dash)))
	var hits: int = 0
	for tick in range(240):
		slam = _step(slam)
		hits += _count(slam.events, "hit")
		if slam.players[1].on_ground:
			break
	assert(slam.players[1].on_ground and hits == 1, "slam must hit once on landing")
	for tick in range(20):
		slam = _step(slam)
		hits += _count(slam.events, "hit")
	assert(hits == 1, "landed slam must not generate another AOE hit")
	var recover: Dictionary = _fixture()
	World.set_element(recover, 1, "air")
	_put(recover.players[1], Vector3(4.0, 7.0, 6.0))
	recover = _step(recover, _cmd(0, 0.0, 0.0, Vector2.ZERO, true))
	for tick in range(int(ceil(float(Kits.move("air", "recovery").windup) / Tuning.FIXED_DELTA)) - 1):
		recover = _step(recover, _cmd(0, 0.0, 0.0, Vector2.ZERO, true))
	assert(int(recover.players[1].recovery_used) == 1)
	for tick in range(5):
		recover = _step(recover, _cmd(0, 0.0, 0.0, Vector2.ZERO, true))
	assert(int(recover.players[1].recovery_used) == 1, "held jump edge cannot repeat recovery")
	recover = _step(recover, _cmd())
	recover = _step(recover, _cmd(0, 0.0, 0.0, Vector2.ZERO, true))
	for tick in range(int(ceil(float(Kits.move("air", "recovery").windup) / Tuning.FIXED_DELTA)) - 1):
		recover = _step(recover, _cmd(0, 0.0, 0.0, Vector2.ZERO, true))
	assert(int(recover.players[1].recovery_used) == 2, "released-and-repressed jump spends Air's second recovery use")
	var landing: Dictionary = _fixture()
	_put(landing.players[1], Vector3(4.0, 4.0, 6.0))
	landing = _activate(landing, "recovery")
	assert(int(landing.players[1].recovery_used) == 1, "real recovery activation spends a use before landing")
	landing.players[1].position = Vector3(4.0, 4.0, 6.0)
	landing.players[1].velocity = Vector3(0.0, -10.0, 0.0)
	landing.players[1].on_ground = false
	for tick in range(120):
		landing = _step(landing)
		if landing.players[1].on_ground:
			break
	assert(landing.players[1].on_ground and int(landing.players[1].recovery_used) == 0, "landing resets the airtime recovery count")

func _test_offstage_recovery() -> void:
	for element: String in Kits.ELEMENTS:
		var world: Dictionary = _fixture()
		World.set_element(world, 1, element)
		_put(world.players[1], Vector3(Tuning.PLATFORM_SIZE * 0.5 + 1.5, -1.0, 0.0))
		world.players[1].yaw = PI * 0.5
		world = _activate(world, "recovery", PI * 0.5)
		for tick in range(240):
			if world.players[1].on_ground:
				break
			world = _step(world)
		assert(world.players[1].on_ground and absf(world.players[1].position.x) <= Tuning.PLATFORM_SIZE * 0.5, "%s must recover from offstage before KO" % element)

func _test_wall_shapes_and_tuning() -> void:
	var vertical: Dictionary = _wall_fixture("earth")
	var wall: Dictionary = vertical.walls.values()[0]
	assert(wall.size.z < wall.size.x and wall.size.z < wall.size.y, "default aim spawns a vertical wall")
	var horizontal: Dictionary = _wall_fixture("earth", true)
	wall = horizontal.walls.values()[0]
	assert(wall.size.y < wall.size.x and wall.size.y < wall.size.z, "aiming down spawns a horizontal wall")
	var hp: Array[int] = []
	var depth: Array[float] = []
	var life: Array[float] = []
	for element: String in Kits.ELEMENTS:
		var fixture: Dictionary = _wall_fixture(element)
		wall = fixture.walls.values()[0]
		hp.append(int(wall.hp))
		depth.append(float(wall.size.x))
		life.append(float(wall.duration))
	assert(hp[0] > hp[3] and depth[0] > depth[3] and life[0] > life[3], "Earth walls must be tougher, larger, and longer-lived than Air walls")

func _test_wall_projectile_contacts() -> void:
	var world: Dictionary = _wall_fixture("earth")
	var wall_id: int = int(world.walls.keys()[0])
	var wall: Dictionary = world.walls[wall_id]
	wall.position = Vector3(0.0, 1.0, -2.0)
	wall.size = Vector3(4.0, 4.0, 0.4)
	world.walls[wall_id] = wall
	_put(world.players[2], Vector3(0.0, Tuning.BODY_HEIGHT * 0.5, -4.0))
	ProjectileSim.spawn_projectile(world, 1, "basic_shot", Vector3(0.0, 0.0, -1.0), 0.0)
	var first_shot: Dictionary = world.projectiles.values()[0]
	first_shot.position = Vector3(0.0, 1.0, -1.0)
	first_shot.velocity = Vector3(0.0, 0.0, -50.0)
	var hp: int = int(world.walls[wall_id].hp)
	var damage: float = float(world.players[2].damage)
	world = _step(world)
	assert(_count(world.events, "wall_block") == 1 and int(world.walls[wall_id].hp) == hp - 1, "projectile contact blocks and chips one HP")
	assert(is_equal_approx(float(world.players[2].damage), damage), "blocked shot cannot damage player behind wall")
	var remaining: int = int(world.walls[wall_id].hp)
	for index in range(remaining):
		ProjectileSim.spawn_projectile(world, 1, "basic_shot", Vector3(0.0, 0.0, -1.0), 0.0)
		var shot: Dictionary = world.projectiles.values()[-1]
		shot.position = Vector3(0.0, 1.0, -1.0)
		shot.velocity = Vector3(0.0, 0.0, -50.0)
		world = _step(world)
		assert(_count(world.events, "wall_block") == 1, "breaking shot must contact wall before wall removal")
		assert(is_equal_approx(float(world.players[2].damage), damage), "breaking contact cannot pass through to player on same tick")
	assert(not world.walls.has(wall_id), "N shot contacts destroy the wall")

func _test_wall_shove_contacts() -> void:
	var world: Dictionary = _wall_fixture("earth")
	var id: int = int(world.walls.keys()[0])
	var wall: Dictionary = world.walls[id]
	wall.position = Vector3(0.0, Tuning.BODY_HEIGHT * 0.5, -0.8)
	wall.size = Vector3(2.0, 2.0, 0.4)
	wall.duration = 20.0
	world.walls[id] = wall
	world.players[1].position = Vector3(0.0, Tuning.BODY_HEIGHT * 0.5, 0.0)
	world.players[1].yaw = 0.0
	var hp: int = int(wall.hp)
	world.players[1].attack_time = Tuning.SHOVE_ACTIVE
	world.players[1].attack_serial = 1
	world = _step(world)
	assert(world.walls.has(id) and int(world.walls[id].hp) == hp - 1, "one shove attack serial damages a nearby wall once")
	world.players[1].attack_time = Tuning.SHOVE_ACTIVE
	world = _step(world)
	assert(world.walls.has(id) and int(world.walls[id].hp) == hp - 1, "the same active shove cannot chip a wall twice")
	for serial in range(2, hp + 1):
		world.players[1].attack_time = Tuning.SHOVE_ACTIVE
		world.players[1].attack_serial = serial
		world = _step(world)
		if serial < hp:
			assert(world.walls.has(id) and int(world.walls[id].hp) == hp - serial, "distinct shove serials remove one wall HP")
	assert(not world.walls.has(id), "N distinct shove attacks destroy wall")

func _test_wall_support_and_expiry() -> void:
	var world: Dictionary = _wall_fixture("earth", true)
	var wall_id: int = int(world.walls.keys()[0])
	var wall: Dictionary = world.walls[wall_id]
	wall.position = Vector3(4.0, 3.0, 6.0)
	wall.size = Vector3(4.0, 0.5, 4.0)
	wall.duration = 2.0
	world.walls[wall_id] = wall
	_put(world.players[1], Vector3(4.0, 5.0, 6.0))
	world.players[1].velocity = Vector3(0.0, -20.0, 0.0)
	for tick in range(30):
		world = _step(world)
		if world.players[1].on_ground:
			break
	assert(world.players[1].on_ground and is_equal_approx(world.players[1].position.y, 3.0 + 0.25 + Tuning.BODY_HEIGHT * 0.5), "horizontal wall supports a swept falling landing")
	wall = world.walls[wall_id]
	wall.age = wall.duration - Tuning.FIXED_DELTA
	world.walls[wall_id] = wall
	world = _step(world)
	assert(not world.walls.has(wall_id), "expired wall support is removed")
	world.players[1].on_ground = false
	world.players[1].velocity = Vector3(0.0, -1.0, 0.0)
	world = _step(world)
	assert(not world.players[1].on_ground, "player falls when temporary wall support expires")

func _test_offstage_wall_replay_validity() -> void:
	for element: String in Kits.ELEMENTS:
		var world: Dictionary = _fixture()
		World.set_element(world, 1, element)
		_put(world.players[1], Vector3(Tuning.PLATFORM_SIZE * 0.5 + 2.0, 2.0, 0.0))
		world.players[1].on_ground = false
		var data: Dictionary = Kits.move(element, "wall")
		var ticks: int = int(ceil(float(data.windup) / Tuning.FIXED_DELTA))
		world = _step(world, _cmd(int(BITS.wall), PI * 0.5, -1.2))
		for tick in range(maxi(0, ticks - 2)):
			world = _step(world)
		var creation_feet: float = float(world.players[1].position.y) - Tuning.BODY_HEIGHT * 0.5
		world = _step(world)
		assert(not world.walls.is_empty(), "%s down-aim wall spawns offstage" % element)
		var spawned: Dictionary = world.walls.values()[0]
		assert(is_finite(spawned.position.x) and is_finite(spawned.position.y) and is_finite(spawned.position.z), "offstage wall placement is finite")
		assert(is_equal_approx(float(spawned.position.y), creation_feet), "airborne horizontal wall height uses creation-time caster feet")

func _test_wall_walkoff_and_horizontal_impulse() -> void:
	var world: Dictionary = _wall_fixture("earth", true)
	var wall_id: int = int(world.walls.keys()[0])
	var wall: Dictionary = world.walls[wall_id]
	wall.position = Vector3(4.0, 3.0, 6.0)
	wall.size = Vector3(4.0, 0.5, 4.0)
	world.walls[wall_id] = wall
	var top: float = float(wall.position.y) + float(wall.size.y) * 0.5
	world.players[1].position = Vector3(4.0, top + Tuning.BODY_HEIGHT * 0.5, 6.0)
	world.players[1].velocity = Vector3.ZERO
	world.players[1].on_ground = true
	world = _step(world, _cmd(0, 0.0, 0.0, Vector2.RIGHT))
	assert(world.players[1].position.x > 4.0 and world.players[1].on_ground, "player walks along a horizontal wall support")
	var walked_off: bool = false
	for tick in range(100):
		world = _step(world, _cmd(0, 0.0, 0.0, Vector2.RIGHT))
		if not world.players[1].on_ground:
			walked_off = true
			break
	assert(walked_off and world.players[1].velocity.y < 0.0, "player walks off a horizontal wall and begins falling")
	var impulse: Dictionary = _wall_fixture("earth", true)
	var impulse_wall_id: int = int(impulse.walls.keys()[0])
	var impulse_wall: Dictionary = impulse.walls[impulse_wall_id]
	impulse_wall.position = Vector3(4.0, 3.0, 6.0)
	impulse_wall.size = Vector3(4.0, 0.5, 4.0)
	impulse.walls[impulse_wall_id] = impulse_wall
	impulse.players[1].position = Vector3(4.0, 3.25 + Tuning.BODY_HEIGHT * 0.5, 6.0)
	impulse.players[1].velocity = Vector3(12.0, 0.0, 0.0)
	impulse.players[1].on_ground = true
	impulse = _step(impulse)
	assert(impulse.players[1].position.x > 4.0, "horizontal knockback advances a player supported by a wall")
