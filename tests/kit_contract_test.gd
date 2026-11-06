extends SceneTree

var Tuning: Node
var World: GDScript
var Kits: GDScript
var Tape: GDScript
var original: Dictionary

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	Tuning = root.get_node("Tuning")
	World = load("res://scripts/sim/world.gd")
	Kits = load("res://scripts/sim/kits.gd")
	Tape = load("res://scripts/dev/replay.gd")
	original = {"CENTER_HEIGHT": Tuning.CENTER_HEIGHT, "RAMP_HEIGHT": Tuning.RAMP_HEIGHT, "LEDGE_HEIGHT": Tuning.LEDGE_HEIGHT}
	Tuning.CENTER_HEIGHT = 0.0
	Tuning.RAMP_HEIGHT = 0.0
	Tuning.LEDGE_HEIGHT = 0.0
	_test_priority()
	_test_iframes()
	_test_curve_replay()
	for key in original:
		Tuning.set(key, original[key])
	print("PASS kit activation contracts")
	call_deferred("quit", 0)

func _fixture() -> Dictionary:
	var world: Dictionary = World.create([1, 2])
	_place(world.players[1], Vector3(4.0, Tuning.BODY_HEIGHT * 0.5, 6.0))
	_place(world.players[2], Vector3(-4.0, Tuning.BODY_HEIGHT * 0.5, -6.0))
	return world

func _place(player: Dictionary, point: Vector3) -> void:
	player.position = point
	player.velocity = Vector3.ZERO
	player.on_ground = is_equal_approx(point.y, World.floor_height(point) + Tuning.BODY_HEIGHT * 0.5)
	player.ground_angle = World.floor_angle(point)

func _cmd(bits: int = 0, jump: bool = false) -> InputCmd:
	var cmd := InputCmd.new(Vector2.ZERO, jump, false, 0.0)
	cmd.moves = bits
	return cmd

func _step(world: Dictionary, cmd: InputCmd = null) -> Dictionary:
	return World.step(world, {1: cmd} if cmd != null else {}, Tuning.FIXED_DELTA)

func _activate(world: Dictionary, bits: int, jump: bool = false) -> Dictionary:
	var windup: float = float(Kits.move("earth", _slot(bits)).windup)
	var ticks: int = int(ceil(windup / Tuning.FIXED_DELTA))
	world = _step(world, _cmd(bits, jump))
	for i in range(ticks - 1):
		world = _step(world)
	return _step(world)

func _slot(bits: int) -> String:
	for slot in ["recovery", "down_dash", "high_jump", "h_dash", "wall", "curve_shot", "quick_fire", "basic_shot"]:
		if bits == _bit(slot):
			return slot
	return "basic_shot"

func _bit(slot: String) -> int:
	return {"recovery": InputCmd.RECOVERY, "down_dash": InputCmd.DOWN_DASH, "high_jump": InputCmd.HIGH_JUMP, "h_dash": InputCmd.H_DASH, "wall": InputCmd.WALL, "curve_shot": InputCmd.CURVE_SHOT, "quick_fire": InputCmd.QUICK_FIRE, "basic_shot": InputCmd.BASIC_SHOT}[slot]

func _test_priority() -> void:
	var bits: int
	var world: Dictionary
	world = _fixture()
	world.players[1].cooldowns.basic_shot = 1.0
	world = _activate(world, InputCmd.BASIC_SHOT | InputCmd.H_DASH)
	assert(Vector2(world.players[1].velocity.x, world.players[1].velocity.z).length() > 1.0, "cooled-down basic fire must allow ready dash")
	world = _fixture()
	world = _activate(world, InputCmd.BASIC_SHOT | InputCmd.HIGH_JUMP)
	assert(world.players[1].velocity.y > Tuning.JUMP_SPEED, "high jump must win over held basic fire")
	world = _fixture()
	_place(world.players[1], Vector3(4.0, 5.0, 6.0))
	world.players[1].cooldowns.basic_shot = 1.0
	world = _activate(world, InputCmd.BASIC_SHOT, true)
	assert(world.players[1].velocity.y > 0.0 and int(world.players[1].recovery_used) == 1, "jump-edge recovery must win over cooled-down fire")
	world = _fixture()
	world = _activate(world, InputCmd.DOWN_DASH | InputCmd.WALL)
	assert(not world.walls.is_empty(), "wall must actually activate")

func _test_iframes() -> void:
	for slot in ["basic_shot", "curve_shot", "quick_fire", "wall", "high_jump", "recovery", "down_dash"]:
		var world: Dictionary = _fixture()
		if slot in ["recovery", "down_dash"]:
			_place(world.players[1], Vector3(4.0, 5.0, 6.0))
		world = _activate(world, _bit(slot))
		assert(float(world.players[1].invuln) == 0.0, "%s must not grant invulnerability" % slot)
	var dash: Dictionary = _fixture()
	_place(dash.players[1], Vector3(4.0, 5.0, 6.0))
	dash = _activate(dash, InputCmd.H_DASH)
	assert(float(dash.players[1].invuln) > 0.0 and is_equal_approx(float(Kits.move("earth", "h_dash").iframe_time), float(Tuning.DASH_IFRAME_TIME)), "horizontal dash must grant configured invulnerability")

func _test_curve_replay() -> void:
	var world: Dictionary = _fixture()
	world = _activate(world, InputCmd.CURVE_SHOT)
	assert(world.projectiles.size() == 1, "curve shot must spawn a projectile")
	assert(Tape._valid_world(world), "live curve projectile world must validate")
	var tape = Tape.new()
	tape.begin(world, {})
	tape.finish(world)
	assert(tape.save("user://kit_curve_replay.json") == OK)
	var loaded = Tape.new()
	assert(loaded.load_file("user://kit_curve_replay.json") == OK)
	assert(loaded.initial_world == world and loaded.final_world == world, "curve projectile snapshots must round-trip exactly")
