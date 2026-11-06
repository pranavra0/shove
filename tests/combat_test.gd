extends SceneTree

var Tuning: Node
var World: GDScript

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	Tuning = root.get_node("Tuning")
	World = load("res://scripts/sim/world.gd")
	_test_creation_and_purity()
	_test_windup_once_and_cooldown()
	_test_spherical_forward_hitbox()
	_test_damage_momentum_and_simultaneous_hits()
	_test_hitstun_control()
	_test_stocks_respawn_and_invulnerability()
	_test_soft_separation()
	_test_floors_and_swept_landing()
	_test_jump_landing_and_edge()
	_test_steep_rejection()
	_test_ramp_entry_faces()
	_test_bhop_knockback_distance()
	_test_tuning_spawn_bounds()
	print("PASS combat purity/multiplayer/windup/once/cooldown/hitbox/knockback/hitstun/stocks/invulnerability/separation/floors/jump/steep")
	call_deferred("quit", 0)

func _fixture(ids: Array = [1, 2]) -> Dictionary:
	var world: Dictionary = World.create(ids)
	for index in range(ids.size()):
		var player: Dictionary = world.players[ids[index]]
		_put(player, Vector3(4.0 + index * 3.0, Tuning.BODY_HEIGHT * 0.5, 6.0))
		player.spawn = player.position
		player.yaw = 0.0
	if ids.has(1) and ids.has(2):
		_put(world.players[2], Vector3(4.0, Tuning.BODY_HEIGHT * 0.5, 4.6))
		world.players[2].spawn = world.players[2].position
	return world

func _put(player: Dictionary, position: Vector3) -> void:
	player.position = position
	player.velocity = Vector3.ZERO
	player.on_ground = is_equal_approx(position.y - Tuning.BODY_HEIGHT * 0.5, World.floor_height(position))
	player.ground_angle = World.floor_angle(position)

func _count(events: Array, type: String) -> int:
	var count: int = 0
	for event in events:
		if event.type == type:
			count += 1
	return count

func _active(world: Dictionary, id: int = 1) -> void:
	world.players[id].attack_time = Tuning.SHOVE_ACTIVE
	world.players[id].cooldown = Tuning.SHOVE_COOLDOWN
	world.players[id].attack_hits = []

func _test_creation_and_purity() -> void:
	var created: Dictionary = World.create([99, -4, 7, 2])
	assert(created.players.keys() == [-4, 2, 7, 99])
	assert(created == World.create([2, 7, 99, -4]))
	assert(World.create([]).players.is_empty())
	for id in created.players:
		var player: Dictionary = created.players[id]
		assert(is_equal_approx(Vector2(player.position.x, player.position.z).length(), Tuning.SPAWN_RADIUS))
		assert(player.stocks == Tuning.STOCKS and player.damage == 0.0)
		assert(player.on_ground and player.position == player.spawn)
		assert(player.attack_hits.is_empty())
	var before: Dictionary = created.duplicate(true)
	var cmd := InputCmd.new(Vector2.RIGHT, true, true, 0.7, 12)
	var commands := {-4: cmd}
	var first: Dictionary = World.step(created, commands, Tuning.FIXED_DELTA)
	var second: Dictionary = World.step(created, commands, Tuning.FIXED_DELTA)
	assert(first == second and created == before)
	assert(first.tick == 1 and created.tick == 0)
	assert(commands.size() == 1 and commands[-4] == cmd)
	assert(cmd.move == Vector2.RIGHT and cmd.jump and cmd.shove and cmd.yaw == 0.7 and cmd.tick == 12)
	first.players[-4].attack_hits.append(99)
	first.players[-4].position = Vector3.ZERO
	assert(created == before and second.players[-4].attack_hits.is_empty())
	var next: Dictionary = World.step(second, {}, Tuning.FIXED_DELTA)
	assert(_count(next.events, "shove") == 0)
	assert(next.players[-4].yaw == cmd.yaw)

func _test_windup_once_and_cooldown() -> void:
	var world: Dictionary = _fixture()
	var command := {1: InputCmd.new(Vector2.ZERO, false, true)}
	var windup_frames: int = int(ceil(Tuning.SHOVE_WINDUP / Tuning.FIXED_DELTA))
	for frame in range(windup_frames - 1):
		world = World.step(world, command, Tuning.FIXED_DELTA)
		assert(world.players[2].damage == 0.0)
		assert(_count(world.events, "hit") == 0)
		assert(_count(world.events, "shove") == (1 if frame == 0 else 0))
	world = World.step(world, command, Tuning.FIXED_DELTA)
	assert(world.players[2].damage == Tuning.SHOVE_DAMAGE)
	assert(_count(world.events, "hit") == 1)
	assert(world.players[1].attack_hits == [2])
	for frame in range(int(ceil((Tuning.SHOVE_WINDUP + Tuning.SHOVE_ACTIVE) / Tuning.FIXED_DELTA))):
		_put(world.players[2], Vector3(4.0, Tuning.BODY_HEIGHT * 0.5, 4.6))
		world = World.step(world, {}, Tuning.FIXED_DELTA)
		assert(world.players[2].damage == Tuning.SHOVE_DAMAGE)
		assert(_count(world.events, "hit") == 0)
	assert(world.players[1].attack_time == 0.0)
	world = _fixture()
	world = World.step(world, command, Tuning.FIXED_DELTA)
	var cooldown_frames: int = int(ceil(Tuning.SHOVE_COOLDOWN / Tuning.FIXED_DELTA))
	for frame in range(1, cooldown_frames):
		world = World.step(world, command, Tuning.FIXED_DELTA)
		assert(_count(world.events, "shove") == 0)
	world = World.step(world, command, Tuning.FIXED_DELTA)
	assert(_count(world.events, "shove") == 1)
	assert(world.players[1].attack_hits.is_empty())
	var prior_damage: float = world.players[2].damage
	for frame in range(windup_frames - 1):
		_put(world.players[2], Vector3(4.0, Tuning.BODY_HEIGHT * 0.5, 4.6))
		world = World.step(world, command, Tuning.FIXED_DELTA)
	assert(world.players[2].damage == prior_damage + Tuning.SHOVE_DAMAGE)
	# A step spanning the entire active interval still resolves its hit.
	world = _fixture()
	world = World.step(world, command, Tuning.SHOVE_WINDUP + Tuning.SHOVE_ACTIVE + 0.01)
	assert(world.players[2].damage == Tuning.SHOVE_DAMAGE)

func _test_spherical_forward_hitbox() -> void:
	var world: Dictionary = _fixture([1, 2, 3, 4, 5])
	_put(world.players[3], Vector3(4.0, Tuning.BODY_HEIGHT * 0.5, 7.4))
	_put(world.players[4], Vector3(5.5, Tuning.BODY_HEIGHT * 0.5, 6.0))
	_put(world.players[5], Vector3(4.0, Tuning.BODY_HEIGHT * 0.5 + 3.0, 4.6))
	_active(world)
	world = World.step(world, {}, Tuning.FIXED_DELTA)
	assert(world.players[2].damage == Tuning.SHOVE_DAMAGE)
	for id in [3, 4, 5]:
		assert(world.players[id].damage == 0.0)
	world = _fixture()
	_put(world.players[2], Vector3(2.6, Tuning.BODY_HEIGHT * 0.5, 6.0))
	world.players[1].yaw = PI * 0.5
	_active(world)
	world = World.step(world, {}, Tuning.FIXED_DELTA)
	assert(world.players[2].damage == Tuning.SHOVE_DAMAGE)

func _test_damage_momentum_and_simultaneous_hits() -> void:
	var world: Dictionary = _fixture()
	world.players[1].velocity = Vector3(2.0, 0.0, -1.0)
	world.players[2].damage = 70.0
	_active(world)
	world = World.step(world, {}, Tuning.FIXED_DELTA)
	var victim: Dictionary = world.players[2]
	var attacker: Dictionary = world.players[1]
	var direction: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, attacker.yaw)
	var momentum: Vector3 = attacker.velocity
	momentum.y = 0.0
	var expected: Vector3 = direction * (Tuning.BASE_KB + victim.damage * Tuning.KB_SCALE) + momentum * Tuning.MOMENTUM_TRANSFER + Vector3.UP * Tuning.KB_UP
	assert(victim.velocity.is_equal_approx(expected))
	assert(victim.damage == 70.0 + Tuning.SHOVE_DAMAGE)
	assert(victim.hitstun == Tuning.HITSTUN and not victim.on_ground)
	var hit: Dictionary = world.events[0]
	assert(hit.type == "hit" and hit.player == 2 and hit.attacker == 1)
	assert(hit.position == victim.position and is_equal_approx(hit.strength, expected.length()))
	var low: Dictionary = _fixture()
	_active(low)
	low = World.step(low, {}, Tuning.FIXED_DELTA)
	assert(victim.velocity.length() > low.players[2].velocity.length())
	world = _fixture([1, 2, 3])
	_put(world.players[3], Vector3(4.9, Tuning.BODY_HEIGHT * 0.5, 4.6))
	_active(world)
	world = World.step(world, {}, Tuning.FIXED_DELTA)
	assert(_count(world.events, "hit") == 2)
	assert(world.players[1].attack_hits == [2, 3])
	# Off-axis victims follow the attacker's facing, not their radial separation.
	assert(is_zero_approx(world.players[3].velocity.x))
	assert(is_equal_approx(world.players[3].velocity.z, -(Tuning.BASE_KB + Tuning.SHOVE_DAMAGE * Tuning.KB_SCALE)))
	# Simultaneous attacks detect against the same positional snapshot.
	world = _fixture()
	world.players[2].yaw = PI
	_active(world, 1)
	_active(world, 2)
	world = World.step(world, {}, Tuning.FIXED_DELTA)
	assert(_count(world.events, "hit") == 2)
	assert(world.players[1].damage == Tuning.SHOVE_DAMAGE and world.players[2].damage == Tuning.SHOVE_DAMAGE)

func _test_hitstun_control() -> void:
	var normal: Dictionary = _fixture([1])
	_put(normal.players[1], Vector3(4.0, 5.0, 6.0))
	var stunned: Dictionary = normal.duplicate(true)
	stunned.players[1].hitstun = Tuning.HITSTUN
	var commands := {1: InputCmd.new(Vector2.RIGHT, true, true)}
	normal = World.step(normal, commands, Tuning.FIXED_DELTA)
	stunned = World.step(stunned, commands, Tuning.FIXED_DELTA)
	assert(is_equal_approx(stunned.players[1].velocity.x, normal.players[1].velocity.x * Tuning.HITSTUN_CONTROL))
	assert(is_equal_approx(stunned.players[1].velocity.y, normal.players[1].velocity.y))
	assert(stunned.players[1].hitstun < Tuning.HITSTUN)
	assert(_count(stunned.events, "shove") == 0)
	for frame in range(int(ceil(Tuning.HITSTUN / Tuning.FIXED_DELTA))):
		stunned = World.step(stunned, {}, Tuning.FIXED_DELTA)
	assert(stunned.players[1].hitstun == 0.0)
	stunned = _fixture([1])
	stunned.players[1].hitstun = Tuning.HITSTUN
	stunned = World.step(stunned, commands, Tuning.FIXED_DELTA)
	assert(stunned.players[1].on_ground and _count(stunned.events, "jump") == 0)

func _test_stocks_respawn_and_invulnerability() -> void:
	var world: Dictionary = _fixture()
	var spawn: Vector3 = world.players[2].spawn
	_put(world.players[2], Vector3(Tuning.PLATFORM_SIZE, Tuning.KILL_PLANE - 1.0, 0.0))
	world.players[2].damage = 90.0
	world.players[2].hitstun = 0.2
	world.players[2].attack_hits = [1]
	world = World.step(world, {}, Tuning.FIXED_DELTA)
	assert(_count(world.events, "ko") == 1)
	assert(world.events[0].player == 2)
	assert(world.players[2].stocks == Tuning.STOCKS - 1)
	assert(world.players[2].position == spawn and world.players[2].on_ground)
	assert(world.players[2].velocity == Vector3.ZERO and world.players[2].damage == 0.0)
	assert(world.players[2].hitstun == 0.0 and world.players[2].attack_hits.is_empty())
	assert(world.players[2].invuln == Tuning.RESPAWN_INVULN)
	_active(world)
	world = World.step(world, {}, Tuning.FIXED_DELTA)
	assert(world.players[2].damage == 0.0 and world.players[1].attack_hits.is_empty())
	assert(world.players[2].invuln < Tuning.RESPAWN_INVULN)
	world.players[2].invuln = Tuning.FIXED_DELTA * 0.5
	world = World.step(world, {}, Tuning.FIXED_DELTA)
	assert(world.players[2].damage == Tuning.SHOVE_DAMAGE)
	world.players[2].stocks = 1
	_put(world.players[2], Vector3(Tuning.PLATFORM_SIZE, Tuning.KILL_PLANE - 1.0, 0.0))
	world = World.step(world, {}, Tuning.FIXED_DELTA)
	assert(world.players[2].stocks == 0 and _count(world.events, "ko") == 1)
	var eliminated: Dictionary = world.players[2].duplicate(true)
	world = World.step(world, {2: InputCmd.new(Vector2.RIGHT, true, true)}, Tuning.FIXED_DELTA)
	assert(world.players[2] == eliminated and world.events.is_empty())
	_put(world.players[2], Vector3(4.0, Tuning.BODY_HEIGHT * 0.5, 4.6))
	_active(world)
	world = World.step(world, {}, Tuning.FIXED_DELTA)
	assert(world.players[2].damage == 0.0)

func _test_soft_separation() -> void:
	var world: Dictionary = _fixture()
	_put(world.players[2], world.players[1].position)
	var centre: Vector3 = world.players[1].position
	world = World.step(world, {}, Tuning.FIXED_DELTA)
	var distance: float = world.players[1].position.distance_to(world.players[2].position)
	assert(is_equal_approx(distance, Tuning.BODY_RADIUS * 2.0 * Tuning.BODY_PUSH))
	assert(distance > 0.0 and distance < Tuning.BODY_RADIUS * 2.0)
	assert(((world.players[1].position + world.players[2].position) * 0.5).is_equal_approx(centre))
	assert(world.players[1].velocity == Vector3.ZERO and world.players[2].velocity == Vector3.ZERO)
	assert(world.players[1].position.x < world.players[2].position.x)
	world = _fixture()
	_put(world.players[2], world.players[1].position + Vector3.UP * (Tuning.BODY_HEIGHT + 0.1))
	world = World.step(world, {}, Tuning.FIXED_DELTA)
	assert(world.players[1].position.x == world.players[2].position.x)

func _test_floors_and_swept_landing() -> void:
	assert(World.floor_height(Vector3.ZERO) == Tuning.CENTER_HEIGHT)
	assert(World.floor_height(Vector3(4.0, 50.0, 6.0)) == 0.0)
	assert(World.floor_height(Vector3(Tuning.PLATFORM_SIZE, 0.0, 0.0)) == -INF)
	for side in [-1.0, 1.0]:
		var ramp := Vector3(side * Tuning.RAMP_OFFSET, 0.0, 0.0)
		assert(is_equal_approx(World.floor_height(ramp), Tuning.RAMP_HEIGHT * 0.5))
		assert(is_equal_approx(World.floor_angle(ramp), atan2(Tuning.RAMP_HEIGHT, Tuning.RAMP_LENGTH)))
		ramp.z = -Tuning.RAMP_LENGTH * 0.5
		assert(is_equal_approx(World.floor_height(ramp), Tuning.RAMP_HEIGHT))
		ramp.z = Tuning.RAMP_LENGTH * 0.5
		assert(is_equal_approx(World.floor_height(ramp), 0.0))
		assert(World.floor_height(Vector3(side * Tuning.LEDGE_OFFSET, 0.0, 0.0)) == Tuning.LEDGE_HEIGHT)
	for position in [Vector3(4.0, 8.0, 6.0), Vector3(0.0, 8.0, 0.0), Vector3(Tuning.RAMP_OFFSET, 8.0, 0.0), Vector3(Tuning.LEDGE_OFFSET, 8.0, 0.0)]:
		var world: Dictionary = _fixture([1])
		_put(world.players[1], position)
		world.players[1].velocity = Vector3(0.0, -600.0, 0.0)
		world = World.step(world, {}, Tuning.FIXED_DELTA)
		assert(world.players[1].on_ground)
		assert(is_equal_approx(world.players[1].position.y, World.floor_height(position) + Tuning.BODY_HEIGHT * 0.5))
		assert(world.players[1].velocity.y == 0.0 and _count(world.events, "land") == 1)
	var world: Dictionary = _fixture([1])
	var start := Vector3(Tuning.RAMP_OFFSET, 0.0, 1.0)
	start.y = World.floor_height(start) + Tuning.BODY_HEIGHT * 0.5
	_put(world.players[1], start)
	world.players[1].velocity = Vector3(0.0, 0.0, -Tuning.WALK_SPEED)
	world = World.step(world, {1: InputCmd.new(Vector2.UP)}, Tuning.FIXED_DELTA)
	assert(world.players[1].on_ground and world.players[1].position.y > start.y)
	assert(is_equal_approx(world.players[1].position.y - Tuning.BODY_HEIGHT * 0.5, World.floor_height(world.players[1].position)))

func _test_jump_landing_and_edge() -> void:
	var world: Dictionary = _fixture([1])
	world = World.step(world, {1: InputCmd.new(Vector2.ZERO, true)}, Tuning.FIXED_DELTA)
	assert(_count(world.events, "jump") == 1 and not world.players[1].on_ground)
	var landed: bool = false
	for frame in range(128):
		world = World.step(world, {}, Tuning.FIXED_DELTA)
		if world.players[1].on_ground:
			assert(_count(world.events, "land") == 1)
			landed = true
			break
	assert(landed)
	world = World.step(world, {1: InputCmd.new(Vector2.ZERO, true)}, Tuning.FIXED_DELTA)
	assert(_count(world.events, "jump") == 1)
	world = _fixture([1])
	_put(world.players[1], Vector3(Tuning.PLATFORM_SIZE * 0.5 - 0.01, Tuning.BODY_HEIGHT * 0.5, 6.0))
	world.players[1].velocity = Vector3(Tuning.WALK_SPEED, 0.0, 0.0)
	world = World.step(world, {1: InputCmd.new(Vector2.RIGHT)}, Tuning.FIXED_DELTA)
	assert(not world.players[1].on_ground and world.players[1].velocity.y < 0.0)
	assert(world.players[1].position.y < Tuning.BODY_HEIGHT * 0.5)

func _test_steep_rejection() -> void:
	var previous_height: float = Tuning.RAMP_HEIGHT
	Tuning.RAMP_HEIGHT = Tuning.RAMP_LENGTH * 2.0
	var world: Dictionary = _fixture([1])
	var position := Vector3(Tuning.RAMP_OFFSET, 0.0, 0.0)
	position.y = World.floor_height(position) + Tuning.BODY_HEIGHT * 0.5
	_put(world.players[1], position)
	assert(world.players[1].ground_angle > Tuning.MAX_GROUND_ANGLE)
	world = World.step(world, {1: InputCmd.new(Vector2.ZERO, true)}, Tuning.FIXED_DELTA)
	assert(not world.players[1].on_ground and world.players[1].velocity.y < 0.0)
	assert(_count(world.events, "jump") == 0)
	position.y += 2.0
	_put(world.players[1], position)
	world.players[1].velocity = Vector3(0.0, -1000.0, 0.0)
	world = World.step(world, {}, Tuning.FIXED_DELTA)
	assert(not world.players[1].on_ground and _count(world.events, "land") == 0)
	Tuning.RAMP_HEIGHT = previous_height

func _test_ramp_entry_faces() -> void:
	var half_width: float = Tuning.RAMP_WIDTH * 0.5
	var half_length: float = Tuning.RAMP_LENGTH * 0.5
	for start in [Vector3(Tuning.RAMP_OFFSET + half_width + 0.01, Tuning.BODY_HEIGHT * 0.5, 0), Vector3(Tuning.RAMP_OFFSET, Tuning.BODY_HEIGHT * 0.5, -half_length - 0.01)]:
		var world: Dictionary = _fixture([1])
		_put(world.players[1], start)
		var move := Vector2.LEFT if start.z == 0.0 else Vector2.DOWN
		world.players[1].velocity = Vector3(move.x, 0, move.y) * Tuning.WALK_SPEED
		world = World.step(world, {1: InputCmd.new(move)}, Tuning.FIXED_DELTA)
		assert(world.players[1].on_ground and world.players[1].position == start, "Ramp side/high face must block rather than drop a grounded player through the base")
	var world: Dictionary = _fixture([1])
	var bottom := Vector3(Tuning.RAMP_OFFSET, Tuning.BODY_HEIGHT * 0.5, half_length + 0.01)
	_put(world.players[1], bottom)
	world.players[1].velocity = Vector3.FORWARD * Tuning.WALK_SPEED
	world = World.step(world, {1: InputCmd.new(Vector2.UP)}, Tuning.FIXED_DELTA)
	assert(world.players[1].on_ground and world.players[1].position.z < half_length and world.players[1].position.y > bottom.y, "The low ramp edge must be continuously walkable")
	world = _fixture([1])
	var airborne := Vector3(Tuning.RAMP_OFFSET + half_width + 0.01, Tuning.BODY_HEIGHT * 0.5 + 0.3, 0)
	_put(world.players[1], airborne)
	world.players[1].velocity = Vector3(-Tuning.WALK_SPEED, -1, 0)
	world = World.step(world, {}, Tuning.FIXED_DELTA)
	assert(is_equal_approx(world.players[1].position.x, airborne.x), "Airborne side entry below the ramp top must collide with its wall")
	for tick in range(30):
		world = World.step(world, {}, Tuning.FIXED_DELTA)
	assert(world.players[1].on_ground and is_equal_approx(world.players[1].position.y, Tuning.BODY_HEIGHT * 0.5), "Airborne wall collision must still land on the base platform")

func _launch_distance(speed: float, hopping: bool, damage: float = 0.0) -> float:
	var world: Dictionary = _fixture()
	world.players[1].velocity = Vector3.FORWARD * speed
	world.players[2].damage = damage
	var start: Vector3 = world.players[2].position
	var connected: bool = false
	for tick in range(int(ceil(Tuning.SHOVE_WINDUP / Tuning.FIXED_DELTA)) + 2):
		world = World.step(world, {1: InputCmd.new(Vector2.ZERO, hopping and tick == 0, tick == 0)}, Tuning.FIXED_DELTA)
		if _count(world.events, "hit") == 1:
			connected = true
			break
	assert(connected, "Standing and full-speed hopping attacks must both connect through the real windup")
	for tick in range(64):
		world = World.step(world, {}, Tuning.FIXED_DELTA)
	assert(world.players[2].stocks == Tuning.STOCKS)
	return start.z - world.players[2].position.z

func _test_bhop_knockback_distance() -> void:
	var standing: float = _launch_distance(0.0, false)
	var hopping: float = _launch_distance(Tuning.WALK_SPEED, true)
	var damaged: float = _launch_distance(0.0, false, 70.0)
	assert(hopping > standing * 1.2, "Full-speed bhop momentum must produce substantially more launch distance")
	assert(damaged > standing * 1.4, "Damage must scale actual displacement, not only a transient velocity")
	var transfer: float = Tuning.MOMENTUM_TRANSFER
	Tuning.MOMENTUM_TRANSFER = 0.0
	var no_transfer: float = _launch_distance(Tuning.WALK_SPEED, true)
	Tuning.MOMENTUM_TRANSFER = transfer
	assert(hopping > no_transfer + 1.0)
	print("LAUNCH DISTANCE standing=%.3fm bhop=%.3fm damaged=%.3fm no-transfer=%.3fm" % [standing, hopping, damaged, no_transfer])

func _test_tuning_spawn_bounds() -> void:
	var size: float = Tuning.PLATFORM_SIZE
	var radius: float = Tuning.SPAWN_RADIUS
	Tuning.PLATFORM_SIZE = 4.0
	Tuning.SPAWN_RADIUS = 20.0
	var world: Dictionary = World.create([1, 2, 3])
	for player in world.players.values():
		assert(player.position.is_finite(), "Shrinking the arena must never create an infinite spawn position")
		assert(absf(player.position.x) <= 2.0 and absf(player.position.z) <= 2.0)
	Tuning.PLATFORM_SIZE = size
	Tuning.SPAWN_RADIUS = radius
	world = World.create([1, 2])
	Tuning.PLATFORM_SIZE = 4.0
	world.players[1].position.y = Tuning.KILL_PLANE - 1.0
	world.players[1].on_ground = false
	world = World.step(world, {}, Tuning.FIXED_DELTA)
	var respawn: Dictionary = world.players[1]
	assert(respawn.position.is_finite() and absf(respawn.position.x) <= 2.0 and absf(respawn.position.z) <= 2.0, "Respawn must reproject the assigned spawn onto resized arena bounds")
	assert(is_equal_approx(respawn.position.y, World.floor_height(respawn.position) + Tuning.BODY_HEIGHT * 0.5))
	Tuning.PLATFORM_SIZE = size
