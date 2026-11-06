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
	var command := InputCmd.new(Vector2(0.25, -0.5), true, true, 0.7, 9007199254740991)
	command.pitch = 0.4
	command.moves = InputCmd.BASIC_SHOT | InputCmd.CURVE_SHOT | InputCmd.QUICK_FIRE | InputCmd.HIGH_JUMP | InputCmd.DOWN_DASH | InputCmd.WALL | InputCmd.H_DASH | InputCmd.RECOVERY
	var wire: Dictionary = command.to_dict()
	var decoded := InputCmd.from_dict(wire)
	assert(decoded.to_dict() == wire)
	wire.pitch = PI
	assert(InputCmd.from_dict(wire) == null)
	wire = command.to_dict()
	wire.pitch = -PI / 2.0
	wire.moves = 0
	assert(InputCmd.from_dict(wire) != null)
	wire.moves = -1
	assert(InputCmd.from_dict(wire) == null)
	wire = command.to_dict()
	wire.moves = 256
	assert(InputCmd.from_dict(wire) == null)
	wire = command.to_dict()
	wire.move = [1.1, 0.0]
	assert(InputCmd.from_dict(wire) == null)
	assert(InputCmd.from_dict({}) == null)

func _test_replay() -> void:
	var original: Dictionary = Store.snapshot()
	Tuning.SHOVE_DAMAGE += 7.0
	var captured: Dictionary = Store.snapshot()
	var world: Dictionary = World.create([-7, 2, 3, 9007199254740993])
	World.set_element(world, -7, "earth")
	World.set_element(world, 2, "water")
	World.set_element(world, 3, "fire")
	World.set_element(world, 9007199254740993, "air")
	for id in world.players:
		world.players[id].cooldowns = {"basic_shot": 0.1, "curve_shot": 0.2, "quick_fire": 0.3, "shove": 0.4, "high_jump": 0.5, "down_dash": 0.6, "wall": 0.7, "h_dash": 0.8, "recovery": 0.9}
	world.players[3].position = Vector3(40.0, Tuning.BODY_HEIGHT * 0.5, 40.0)
	world.players[3].spawn = world.players[3].position
	world.players[-7].position = Vector3(4.0, Tuning.BODY_HEIGHT * 0.5, 6.0)
	world.players[2].position = Vector3(4.0, Tuning.BODY_HEIGHT * 0.5, 4.6)
	# A third participant starts below the kill plane, exercising real KO/respawn.
	world.players[9007199254740993].position = Vector3(40.0, Tuning.KILL_PLANE - 2.0, 0.0)
	world.players[9007199254740993].on_ground = false
	world.next_entity_id = 3
	world.projectiles[1] = {"id": 1, "position": Vector3(100.0, 10.0, 100.0), "velocity": Vector3.RIGHT, "owner": -7, "element": "earth", "slot": "basic_shot", "age": 0.0, "deflections": 0, "behavior": "level", "damage": 2.0, "kb_base": 1.0, "kb_scale": 0.1, "momentum": Vector3.ZERO, "size": 0.2, "duration": 100.0, "hitstun": 0.1, "kb_up": 1.0, "curve": 0.0, "gravity": 0.0, "homing": 0.0, "bounce_count": 0, "hit_ids": [], "spike_pop_speed": 0.0, "spike_damage_mult": 1.0, "spike_kb_mult": 1.0}
	world.walls[2] = {"id": 2, "position": Vector3(100.0, 1.0, 100.0), "size": Vector3(1.0, 2.0, 1.0), "owner": 2, "element": "water", "age": 0.0, "duration": 100.0, "hp": 3, "hit_shoves": {}}
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
	assert(loaded.initial_world.players[-7].element == "earth" and loaded.initial_world.players[2].element == "water")
	assert(loaded.initial_world.players[3].element == "fire" and loaded.initial_world.players[9007199254740993].element == "air")
	assert(loaded.initial_world.players[-7].cooldowns.size() == 9 and loaded.initial_world == starting)
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
	assert(envelope.version == 3)
	envelope.version = 2
	file = FileAccess.open("user://replay_bad_test.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(envelope))
	file.close()
	assert(loaded.load_file("user://replay_bad_test.json") == ERR_INVALID_DATA)
	envelope.version = 1
	file = FileAccess.open("user://replay_bad_test.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(envelope))
	file.close()
	assert(loaded.load_file("user://replay_bad_test.json") == ERR_INVALID_DATA)
	envelope.version = 3
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
	var unsupported = Tape.new()
	unsupported.begin(starting, {"script_resource": World})
	unsupported.finish(starting)
	assert(unsupported.save("user://replay_invalid_test.json") == ERR_INVALID_DATA)
	var malformed: Dictionary = starting.duplicate(true)
	malformed.players[-7].element = "lightning"
	assert(not Tape._valid({"initial": malformed, "settings": {}, "frames": [], "final": starting}))
	malformed = starting.duplicate(true)
	malformed.players[-7].cooldowns["basic_shot"] = INF
	assert(not Tape._valid({"initial": malformed, "settings": {}, "frames": [], "final": starting}))
	malformed = starting.duplicate(true)
	malformed.players[-7].cooldowns["invalid_slot"] = 0.1
	assert(not Tape._valid({"initial": malformed, "settings": {}, "frames": [], "final": starting}))
	malformed = starting.duplicate(true)
	malformed.projectiles[1] = {"id": 1, "position": Vector3.ZERO, "velocity": Vector3.ZERO, "owner": 1234, "element": "earth", "slot": "basic_shot", "age": 0.0, "deflections": 0, "behavior": "level", "damage": 1.0, "kb_base": 1.0, "kb_scale": 1.0, "momentum": Vector3.ZERO, "size": 1.0, "duration": 1.0, "hitstun": 0.0, "kb_up": 1.0, "curve": 0.0, "gravity": 0.0, "homing": 0.0, "bounce_count": 0, "hit_ids": [], "spike_pop_speed": 0.0, "spike_damage_mult": 1.0, "spike_kb_mult": 1.0}
	malformed.next_entity_id = 2
	assert(not Tape._valid({"initial": malformed, "settings": {}, "frames": [], "final": starting}))
	var control_world: Dictionary = World.create([1, 2, 3, 4], "control")
	assert(Tape._valid_world(control_world))
	var bad_control: Dictionary = control_world.duplicate(true)
	bad_control.players[1].team = -1
	assert(not Tape._valid_world(bad_control))
	bad_control = control_world.duplicate(true)
	bad_control.control.zones[0].progress = 1.1
	assert(not Tape._valid_world(bad_control))
	bad_control = control_world.duplicate(true)
	bad_control.control.scores[1] = INF
	assert(not Tape._valid_world(bad_control))
	bad_control = control_world.duplicate(true)
	bad_control.players[1].respawn_remaining = 61.0
	assert(not Tape._valid_world(bad_control))
	bad_control = starting.duplicate(true)
	bad_control.mode = "control"
	assert(Store.decode(Store.encode(original)) == original)
	Store.apply(original)
	assert(Store.snapshot() == original)
	assert(Store.decode(Store.encode({"BOT_CONTROL_ZONE_MARGIN": 2.0, "BOT_CONTROL_CENTER_RADIUS": 3.0})).size() == 2)
	assert(Store.decode(Store.encode({"BOT_CONTROL_ZONE_MARGIN": -1.0})).is_empty())
	assert(Store.decode(Store.encode({"BOT_CONTROL_CENTER_RADIUS": 0.0})).is_empty())
	assert(Store.decode(Store.encode({"CP_CAPTURE_TIME": 0.0})).is_empty())
	assert(Store.decode(Store.encode({"CP_SCORE_RATE": -1.0})).is_empty())
	assert(Store.decode(Store.encode({"CP_TEAM_COLORS": [Color.BLUE]})).is_empty())
	assert(Store.decode(Store.encode({"CP_TEAM_COLORS": [Color.BLUE, Color.ORANGE]})).has("CP_TEAM_COLORS"))
	assert(not Tape._valid_world(bad_control))
	Store.apply(original)
	DirAccess.remove_absolute("user://replay_test.json")
	DirAccess.remove_absolute("user://replay_bad_test.json")
