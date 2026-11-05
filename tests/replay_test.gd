extends SceneTree

var Tuning: Node
var World: GDScript
var Tape: GDScript
var Store: GDScript

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	Tuning = root.get_node("Tuning")
	World = load("res://scripts/sim/world.gd")
	Tape = load("res://scripts/dev/replay.gd")
	Store = load("res://scripts/dev/tuning_store.gd")
	_test_commands()
	_test_replay()
	print("PASS replay typed JSON/immutable commands/atomic rejection/live tuning/shove/KO/respawn")
	call_deferred("quit", 0)

func _test_commands() -> void:
	var command := InputCmd.new(Vector2(0.25, -0.5), true, true, 0.7, 9007199254740993)
	var decoded := InputCmd.from_dict(command.to_dict())
	assert(decoded.to_dict() == command.to_dict())
	var wire := command.to_dict()
	wire.move = [3.0, 4.0]
	assert(InputCmd.from_dict(wire).move.is_equal_approx(Vector2(0.6, 0.8)))
	wire.yaw = INF
	assert(InputCmd.from_dict(wire) == null)
	assert(InputCmd.from_dict({}) == null)

func _test_replay() -> void:
	var original: Dictionary = Store.snapshot()
	Tuning.SHOVE_DAMAGE += 7.0
	var captured: Dictionary = Store.snapshot()
	var world: Dictionary = World.create([-7, 2, 9007199254740993])
	world.players[-7].position = Vector3(4.0, Tuning.BODY_HEIGHT * 0.5, 6.0)
	world.players[2].position = Vector3(4.0, Tuning.BODY_HEIGHT * 0.5, 4.6)
	# A third participant starts below the kill plane, exercising real KO/respawn.
	world.players[9007199254740993].position = Vector3(40.0, Tuning.KILL_PLANE - 2.0, 0.0)
	world.players[9007199254740993].on_ground = false
	var tape = Tape.new()
	tape.begin(world, captured)
	var starting: Dictionary = world.duplicate(true)
	var saw_shove := false
	var saw_hit := false
	var saw_ko := false
	var saw_respawn := false
	var saved_command: Dictionary = {}
	for tick in range(160):
		var patch: Dictionary = {}
		if tick == 20:
			patch = {"GRAVITY": Tuning.GRAVITY * 1.25, "SHOVE_DAMAGE": Tuning.SHOVE_DAMAGE + 3.0}
			Store.apply(patch)
		var commands := {-7: InputCmd.new(Vector2.ZERO, tick == 40, tick == 0, 0.0, tick), 2: InputCmd.new(Vector2.ZERO, false, false, 0.0, tick)}
		var before: Dictionary = commands[-7].to_dict()
		tape.record(commands, patch)
		world = World.step(world, commands, Tuning.FIXED_DELTA)
		assert(commands[-7].to_dict() == before)
		if tick == 0:
			saved_command = before
			commands[-7].shove = false
			commands[-7].move = Vector2.RIGHT
			patch["GRAVITY"] = -999.0
			tape.finish(world)
			assert(tape.save("user://replay_test.json") == OK)
			var event_tape = Tape.new()
			assert(event_tape.load_file("user://replay_test.json") == OK)
			assert(event_tape.final_world == world and not event_tape.final_world.events.is_empty())
		for event in world.events:
			saw_shove = saw_shove or event.type == "shove"
			saw_hit = saw_hit or event.type == "hit"
			saw_ko = saw_ko or event.type == "ko"
		saw_respawn = saw_respawn or world.players[9007199254740993].invuln > 0.0
	tape.finish(world)
	assert(saw_shove and saw_hit and saw_ko and saw_respawn)
	assert(tape.initial_world == starting and tape.frames[0].commands[-7] == saved_command)
	assert(tape.save("user://replay_test.json") == OK)
	var loaded = Tape.new()
	assert(loaded.load_file("user://replay_test.json") == OK)
	assert(loaded.initial_world == tape.initial_world and loaded.final_world == world)
	assert(loaded.settings == captured and loaded.frames == tape.frames)
	assert(loaded.initial_world.players.has(9007199254740993))
	Store.apply(original)
	assert(Store.snapshot() != captured)
	Store.apply(loaded.settings)
	var replayed: Dictionary = loaded.restart()
	replayed.players[-7].position = Vector3.ZERO
	assert(loaded.initial_world == starting)
	replayed = loaded.restart()
	var count := 0
	while loaded.has_next():
		var commands: Dictionary = loaded.next_commands()
		Store.apply(loaded.frame_settings)
		replayed = World.step(replayed, commands, Tuning.FIXED_DELTA)
		count += 1
	assert(count == 160 and replayed == world and replayed == loaded.final_world)
	assert(loaded.next_commands().is_empty() and loaded.frame_settings.is_empty())
	# Corrupt a valid tagged tape: decoding must not replace any loaded state.
	var file := FileAccess.open("user://replay_test.json", FileAccess.READ)
	var envelope: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	envelope.tape = {"t": "Dictionary", "v": [["initial", {"t": "int", "v": "not an integer"}]]}
	file = FileAccess.open("user://replay_bad_test.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(envelope))
	file.close()
	var before_frames: Array = loaded.frames.duplicate(true)
	assert(loaded.load_file("user://replay_bad_test.json") == ERR_INVALID_DATA)
	assert(loaded.frames == before_frames and loaded.cursor == 160 and loaded.final_world == world)
	assert(loaded.restart() == starting and loaded.cursor == 0)
	var invalid = Tape.new()
	invalid.begin(starting, captured)
	invalid.record({-7: InputCmd.new()})
	invalid.finish(starting)
	assert(invalid.save("user://replay_invalid_test.json") == ERR_INVALID_DATA)
	Store.apply(original)
	DirAccess.remove_absolute("user://replay_test.json")
	DirAccess.remove_absolute("user://replay_bad_test.json")
