extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world_script: GDScript = load("res://scripts/sim/world.gd")
	var session_script: GDScript = load("res://scripts/net/session.gd")
	var prediction_script: GDScript = load("res://scripts/net/prediction.gd")
	var tune: Node = root.get_node("Tuning")
	var session = session_script.new()
	root.add_child(session)
	session.local_id = 2
	session.epoch = 1
	var initial: Dictionary = world_script.create([1, 2])
	session._prediction = prediction_script.new()
	session._prediction.begin(initial, 2, 0.0)
	session._prediction.advance(InputCmd.new(Vector2.UP, true, false, 0.0, 7), tune.FIXED_DELTA)
	session._prediction.advance(InputCmd.new(Vector2.UP, false, false, 0.0, 8), tune.FIXED_DELTA)
	var terminal: Dictionary = initial.duplicate(true)
	terminal.tick = 3
	terminal.players[1].stocks = 0
	terminal.players[1].position.y = tune.KILL_PLANE - 1.0
	session._receive_snapshot({"epoch": 1, "serial": 1, "world": terminal, "flow": {"phase": "winner", "winner": 2}, "ack": 6, "echo": 0.0})
	assert(session.world == terminal, "A terminal snapshot must discard unacknowledged movement instead of replaying beyond the final state")
	assert(session._prediction.pending.is_empty() and session.stats.input_depth == 0)
	var malformed: Dictionary = terminal.duplicate(true)
	malformed.players[1].element = "invalid"
	session._receive_snapshot({"epoch": 1, "serial": 2, "world": malformed, "flow": {"phase": "playing"}, "ack": 6, "echo": 0.0})
	assert(session.world == terminal, "Network snapshots reject malformed element fields without changing authoritative state")
	var world: Dictionary = world_script.create([1, 2, 3, 4, 5, 6, 7, 8])
	for id in world.players:
		world_script.set_element(world, id, ["earth", "water", "fire", "air"][int(id) % 4])
	for tick in range(90):
		var commands: Dictionary = {}
		for id in world.players:
			var angle: float = float(id) * 0.7 + float(tick) * 0.01
			var command: InputCmd = InputCmd.new(Vector2(cos(angle), sin(angle)), tick % 7 == 0, tick % 39 == 0, angle, tick)
			command.pitch = 0.25
			command.moves = 255 if tick % 9 == 0 else InputCmd.BASIC_SHOT | InputCmd.QUICK_FIRE
			commands[id] = command
		world = world_script.step(world, commands, tune.FIXED_DELTA)
	var payload := {"epoch": 1, "serial": 4, "world": world, "flow": {"phase": "playing"}, "ack": 90, "echo": 7.0}
	var packet: PackedByteArray = session._encode_unreliable(payload)
	var raw: PackedByteArray = var_to_bytes(payload)
	assert(packet.size() <= 8192, "Eight-player full-kit snapshots remain within the compressed packet bound; ENet may fragment")
	assert(raw.size() <= 65536, "Eight-player full-kit snapshots remain within the bounded raw decode limit")
	assert(session._decode_unreliable(packet) == payload)
	print("PASS network terminal authority/unacked flush/eight-player bounded packet/typed packet roundtrip compressed=", packet.size(), " raw=", raw.size())
	session.free()
	quit(0)
