extends SceneTree

var Tuning: Node
var World: GDScript
var Kits: GDScript
var ProjectileSim: GDScript

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	Tuning = root.get_node("Tuning")
	World = load("res://scripts/sim/world.gd")
	Kits = load("res://scripts/sim/kits.gd")
	ProjectileSim = load("res://scripts/sim/projectiles.gd")
	for key in ["CENTER_HEIGHT", "RAMP_HEIGHT", "LEDGE_HEIGHT"]:
		Tuning.set(key, 0.0)
	_test_spawn_and_curve()
	_test_shape_and_lob_landing()
	_test_swept_geometry()
	_test_deflection()
	_test_homing()
	_test_water_chain()
	_test_elements()
	print("PASS projectile behavior")
	quit()

func _world(ids: Array = [1, 2]) -> Dictionary:
	var world: Dictionary = World.create(ids)
	for i in range(ids.size()):
		var p: Dictionary = world.players[ids[i]]
		p.position = Vector3(0.0, Tuning.BODY_HEIGHT * 0.5, 0.0) if i == 0 else Vector3(15.0 + i * 10.0, Tuning.BODY_HEIGHT * 0.5, 15.0)
		p.spawn = p.position
		p.velocity = Vector3.ZERO
		p.on_ground = true
	return world

func _spawn(world: Dictionary, owner: int, slot: String, aim: Vector3 = Vector3.FORWARD, strafe: float = 0.0) -> Dictionary:
	var before: Array = world.projectiles.keys()
	ProjectileSim.spawn_projectile(world, owner, slot, aim, strafe)
	for id in world.projectiles:
		if not before.has(id):
			return world.projectiles[id]
	return {}

func _test_spawn_and_curve() -> void:
	var world: Dictionary = _world()
	for slot in ["basic_shot", "quick_fire"]:
		var p: Dictionary = _spawn(world, 1, slot, Vector3(0.0, 0.7, -1.0))
		assert(p.behavior == "level")
		var before: Vector3 = p.velocity
		ProjectileSim.step(world, {}, {}, Tuning.FIXED_DELTA)
		assert(p.velocity.is_equal_approx(before))
	world = _world()
	var left: Dictionary = _spawn(world, 1, "curve_shot", Vector3.FORWARD, -1.0)
	var right: Dictionary = _spawn(world, 1, "curve_shot", Vector3.FORWARD, 1.0)
	var tiny: Dictionary = _spawn(world, 1, "curve_shot", Vector3.FORWARD, 0.0)
	ProjectileSim.step(world, {}, {}, Tuning.FIXED_DELTA)
	assert(left.velocity.x * right.velocity.x < 0.0)
	assert(absf(tiny.velocity.x) < absf(left.velocity.x))

func _test_shape_and_lob_landing() -> void:
	var world: Dictionary = _world()
	var level: Dictionary = _spawn(world, 1, "curve_shot", Vector3.FORWARD)
	var spike: Dictionary = _spawn(world, 1, "curve_shot", Vector3(0.0, -0.8, -1.0))
	var lob: Dictionary = _spawn(world, 1, "curve_shot", Vector3(0.0, 0.8, -1.0))
	var data: Dictionary = Kits.move("earth", "curve_shot")
	assert(is_equal_approx(spike.damage, data.damage * data.spike_damage_mult))
	assert(is_equal_approx(spike.kb_base, data.kb_base * data.spike_kb_mult))
	assert(is_equal_approx(spike.kb_scale, data.kb_scale * data.spike_kb_mult))
	assert(is_equal_approx(lob.damage, data.damage * data.lob_damage_mult))
	assert(is_equal_approx(lob.kb_base, data.kb_base * data.lob_kb_mult))
	assert(is_equal_approx(lob.kb_scale, data.kb_scale * data.lob_kb_mult))
	assert(spike.velocity.y < 0.0 and spike.spike_pop_speed > 0.0)
	for element in Kits.ELEMENTS:
		var landing: Dictionary = _world()
		World.set_element(landing, 1, element)
		var shot: Dictionary = _spawn(landing, 1, "curve_shot", Vector3(0.0, 0.7, -0.7))
		var id: int = int(shot.id)
		var last_age: float = 0.0
		var last_velocity: Vector3 = Vector3.ZERO
		for i in range(120):
			ProjectileSim.step(landing, {}, {}, Tuning.FIXED_DELTA)
			if not landing.projectiles.has(id):
				last_age = float(shot.age)
				last_velocity = shot.velocity
				break
		assert(not landing.projectiles.has(id))
		assert(last_age + Tuning.FIXED_DELTA < shot.duration)
		assert(last_velocity.y < 0.0)
		assert(shot.position.y + last_velocity.y * Tuning.FIXED_DELTA - shot.size <= 0.0)
		assert(shot.owner == 1)
	for slot in ["basic_shot", "quick_fire", "curve_shot"]:
		_test_hit_formula(slot, Vector3.FORWARD)
	_test_hit_formula("curve_shot", Vector3(0.0, -0.8, -1.0))
	_test_hit_formula("curve_shot", Vector3(0.0, 0.8, -1.0))

func _test_hit_formula(slot: String, aim: Vector3) -> void:
	var world: Dictionary = _world()
	var attacker: Dictionary = world.players[1]
	attacker.velocity = Vector3(4.0, 0.0, 1.0)
	var p: Dictionary = _spawn(world, 1, slot, aim)
	var victim: Dictionary = world.players[2]
	attacker.velocity = Vector3(20.0, 0.0, 10.0)
	p.position = Vector3(4.0, 3.0, 6.0)
	p.velocity = Vector3(0.0, -10.0, -20.0) if p.behavior == "spike" or p.behavior == "lob" else Vector3(0.0, 0.0, -20.0)
	victim.position = p.position + p.velocity * Tuning.FIXED_DELTA * 0.5
	victim.velocity = Vector3(1.0, 2.0, 3.0)
	victim.damage = 0.0
	victim.invuln = 0.0
	victim.stocks = 3
	var old_velocity: Vector3 = victim.velocity
	var old_damage: float = victim.damage
	var hit: Dictionary = Kits.move(str(p.element), slot)
	var post_damage: float = old_damage + p.damage
	var expected_direction: Vector3 = p.velocity
	if p.behavior == "spike" or p.behavior == "lob":
		expected_direction.y -= p.gravity * Tuning.FIXED_DELTA
	if p.behavior == "spike":
		expected_direction = Vector3(expected_direction.x, absf(expected_direction.y) + p.spike_pop_speed, expected_direction.z)
	var expected: Vector3 = expected_direction.normalized() * (p.kb_base + post_damage * p.kb_scale) + Vector3(4.0, 0.0, 1.0) * hit.momentum + Vector3.UP * p.kb_up
	var id: int = int(p.id)
	ProjectileSim.step(world, {}, {}, Tuning.FIXED_DELTA)
	assert(is_equal_approx(victim.damage, old_damage + p.damage))
	assert(victim.velocity.is_equal_approx(old_velocity + expected))
	assert(victim.hitstun > 0.0)
	var hits: int = 0
	for event in world.events:
		if event.type == "hit":
			hits += 1
	assert(hits == 1)
	assert(not world.projectiles.has(id) or p.behavior == "spike")

func _test_swept_geometry() -> void:
	var world: Dictionary = _world([1, 2, 3])
	var p: Dictionary = _spawn(world, 1, "basic_shot")
	var id: int = int(p.id)
	p.position = Vector3(0.0, 0.8, 0.0)
	p.velocity = Vector3.DOWN * 100.0
	ProjectileSim.step(world, {}, {}, Tuning.FIXED_DELTA)
	assert(not world.projectiles.has(id))
	Tuning.CENTER_HEIGHT = 2.0
	world = _world([1, 2, 3])
	p = _spawn(world, 1, "basic_shot")
	id = int(p.id)
	p.position = Vector3(0.0, 1.0, 4.0)
	p.velocity = Vector3(0.0, 0.0, -400.0)
	ProjectileSim.step(world, {}, {}, Tuning.FIXED_DELTA)
	assert(not world.projectiles.has(id))
	assert(not p.hit_ids.has(2) and not p.hit_ids.has(3))
	Tuning.CENTER_HEIGHT = 0.0

func _test_deflection() -> void:
	var world: Dictionary = _world([1, -2, 3])
	World.set_element(world, 1, "fire")
	World.set_element(world, -2, "fire")
	var p: Dictionary = _spawn(world, 1, "basic_shot")
	var id: int = int(p.id)
	p.position = Vector3(0.0, 2.0, 0.0)
	var initial_speed: float = p.velocity.length()
	var initial_damage: float = p.damage
	var cmd: InputCmd = InputCmd.new(Vector2.ZERO, false, true, 0.0, 0)
	for i in range(36):
		var shover: int = -2 if i % 2 == 0 else 3
		world.players[-2].position = Vector3(15.0, 2.0, 15.0)
		world.players[3].position = Vector3(-15.0, 2.0, 15.0)
		world.players[shover].position = p.position - Vector3.FORWARD * Tuning.SHOVE_REACH
		world.players[shover].yaw = 0.0
		ProjectileSim.step(world, {shover: true}, {shover: cmd}, Tuning.FIXED_DELTA)
		assert(world.projectiles.has(id))
		assert(p.owner == shover and p.deflections == i + 1)
		assert(p.velocity.length() >= initial_speed)
		assert(p.damage >= initial_damage)
		assert(p.velocity.length() <= Tuning.DEFLECT_SPEED_CAP)
		assert(p.damage <= Tuning.DEFLECT_DAMAGE_CAP)
		assert(p.position.y < 3.0)
	var capped_speed: float = p.velocity.length()
	var capped_damage: float = p.damage
	assert(is_equal_approx(capped_speed, Tuning.DEFLECT_SPEED_CAP))
	assert(is_equal_approx(capped_damage, Tuning.DEFLECT_DAMAGE_CAP))
	var next_shover: int = 3 if p.owner == -2 else -2
	world.players[next_shover].position = p.position - Vector3.FORWARD * Tuning.SHOVE_REACH
	ProjectileSim.step(world, {next_shover: true}, {next_shover: cmd}, Tuning.FIXED_DELTA)
	assert(p.deflections == 37 and p.owner == next_shover)
	assert(p.element == "fire", "Deflection transfers ownership without changing the projectile's element")
	var high_shover: int = 3 if p.owner != 3 else -2
	world.players[high_shover].position = p.position + Vector3.UP * 10.0
	var count: int = p.deflections
	var current_owner: int = p.owner
	ProjectileSim.step(world, {high_shover: true}, {high_shover: cmd}, Tuning.FIXED_DELTA)
	assert(p.deflections == count and p.owner == current_owner)

func _test_homing() -> void:
	var world: Dictionary = _world([1, -2, 3])
	World.set_element(world, 1, "fire")
	var p: Dictionary = _spawn(world, 1, "basic_shot")
	var id: int = int(p.id)
	p.position = Vector3(0.0, 3.0, 0.0)
	p.velocity = Vector3.FORWARD * 10.0
	world.players[-2].position = Vector3(5.0, 4.0, -6.0)
	world.players[-2].on_ground = false
	ProjectileSim.step(world, {}, {}, Tuning.FIXED_DELTA)
	assert(world.projectiles.has(id))
	assert(p.velocity.x > 0.0)
	var x: float = p.velocity.x
	world.players[-2].on_ground = true
	ProjectileSim.step(world, {}, {}, Tuning.FIXED_DELTA)
	assert(world.projectiles.has(id))
	assert(is_equal_approx(p.velocity.x, x))

func _fire_water_hit(world: Dictionary, target_id: int) -> void:
	var p: Dictionary = _spawn(world, 1, "basic_shot")
	var victim: Dictionary = world.players[target_id]
	p.position = victim.position + Vector3.BACK * 0.8
	p.velocity = Vector3.FORWARD * 60.0
	victim.velocity = Vector3.ZERO
	victim.invuln = 0.0
	victim.stocks = 3
	ProjectileSim.step(world, {}, {}, Tuning.FIXED_DELTA)

func _test_water_chain() -> void:
	var world: Dictionary = _world([1, 2, 3])
	World.set_element(world, 1, "water")
	var second: Vector3 = Vector3(4.0, 0.9, 4.0)
	world.players[2].position = second
	world.players[3].position = Vector3(20.0, 1.0, 20.0)
	_fire_water_hit(world, 2)
	assert(world.players[1].chain_hits == 1)
	assert(world.players[1].chain_target == 2)
	assert(world.players[2].damage > 0.0 and world.players[2].hitstun > 0.0)
	var base_stun: float = world.players[2].hitstun
	for i in range(30):
		world = World.step(world, {}, Tuning.FIXED_DELTA)
	world.players[3].position = Vector3(4.0, 0.9, 4.0)
	_fire_water_hit(world, 3)
	assert(world.players[1].chain_hits == 2 and world.players[1].chain_target == 3)
	assert(world.players[3].hitstun > base_stun)
	for i in range(int(ceil(float(Kits.move("water", "basic_shot").chain_window) / Tuning.FIXED_DELTA)) + 1):
		world = World.step(world, {}, Tuning.FIXED_DELTA)
	world.players[2].position = second
	_fire_water_hit(world, 2)
	assert(world.players[1].chain_hits == 1 and world.players[1].chain_target == 2)

func _test_elements() -> void:
	var stats: Dictionary = {}
	for element in Kits.ELEMENTS:
		var world: Dictionary = _world([1, 2])
		World.set_element(world, 1, element)
		var p: Dictionary = _spawn(world, 1, "basic_shot")
		stats[element] = [p.damage, p.size, p.velocity.length()]
	assert(stats.earth[0] != stats.water[0] and stats.water[0] != stats.fire[0] and stats.fire[0] != stats.air[0])
	assert(stats.earth[1] != stats.water[1] and stats.water[1] != stats.fire[1] and stats.fire[1] != stats.air[1])
	assert(stats.earth[2] != stats.water[2] and stats.water[2] != stats.fire[2] and stats.fire[2] != stats.air[2])
