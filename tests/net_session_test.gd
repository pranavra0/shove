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
	var world: Dictionary = world_script.create([1, 2, 3, 4, 5, 6, 7, 8])
	for tick in range(90):
		var commands: Dictionary = {}
		for id in world.players:
			var angle: float = float(id) * 0.7 + float(tick) * 0.01
			commands[id] = InputCmd.new(Vector2(cos(angle), sin(angle)), tick % 7 == 0, tick % 39 == 0, angle, tick)
		world = world_script.step(world, commands, tune.FIXED_DELTA)
	var payload := {"epoch": 1, "serial": 4, "world": world, "flow": {"phase": "playing"}, "ack": 90, "echo": 7.0}
	var packet: PackedByteArray = session._encode_unreliable(payload)
	assert(packet.size() < 1280, "Eight-player unreliable snapshots must leave room for RPC headers below ENet's MTU")
	assert(session._decode_unreliable(packet) == payload)
	print("PASS network terminal authority/unacked flush/eight-player MTU/typed packet roundtrip bytes=", packet.size())
	session.free()
	quit(0)
