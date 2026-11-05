extends SceneTree
## Explicit multi-process integration driver; tools/net_test.py owns orchestration.
## All gameplay is the real main scene and NetSession, driven by normal BotSim inputs.

var Tuning: Node
var BotSim: GDScript
var _app: Node
var _network
var _role := ""
var _peer_name := ""
var _port := 7777
var _result_dir := ""
var _expected_clients := 2
var _timeout := 85.0
var _gui := false
var _capture_dir := ""
var _hold_seconds := 3.0
var _started_at := 0.0
var _lobby_at := -1.0
var _winner_at := -1.0
var _rematch_at := -1.0
var _started_match := false
var _started_rematch := false
var _ready_sent := false
var _failed := false
var _reported := false
var _memory: Dictionary = {}
var _terminal: Dictionary = {}
var _rematch: Dictionary = {}
var _captures: Dictionary = {}
var _commands := 0
var _moving_commands := 0
var _shove_commands := 0
var _updates := 0
var _ko_events := 0
var _peak_snapshot_rate := 0.0
var _peak_dropped := 0
var _phases: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _parse_arguments():
		return
	_started_at = _now()
	Tuning = root.get_node("Tuning")
	BotSim = load("res://scripts/sim/bot.gd")
	# Configure before instantiating Main so the actual arena uses the same fixture.
	# The host also transmits this configuration through NetSession at match start.
	var fixture := {
		"NET_LATENCY_MS": 100.0, "NET_JITTER_MS": 10.0, "NET_PACKET_LOSS": 0.05,
		"STOCKS": 1, "PLATFORM_SIZE": 18.0, "SPAWN_RADIUS": 5.0,
		"CENTER_SIZE": 3.0, "RAMP_OFFSET": 4.0, "RAMP_WIDTH": 2.0,
		"LEDGE_OFFSET": 7.0, "LEDGE_WIDTH": 2.0, "BOT_EDGE_MARGIN": 2.0,
		"BASE_KB": 14.0, "SHOVE_DAMAGE": 25.0, "KB_SCALE": 0.2,
		"KB_UP": 6.0, "KILL_PLANE": -8.0, "BOT_REACTION": 0.06,
		"BOT_BHOP_SKILL": 0.4,
	}
	for field: String in fixture:
		Tuning.set(field, fixture[field])
	if _gui:
		if DisplayServer.get_name() == "headless":
			_fail("--gui needs a real rendering display, not the dummy renderer")
			return
		root.size = Vector2i(960, 640)
		root.title = "SHOVE / network " + _peer_name
		root.position = DisplayServer.screen_get_position() + Vector2i(24 if _role == "server" else 1010, 48)
	var scene: PackedScene = load("res://scenes/main.tscn")
	if scene == null:
		_fail("Cannot load the real main scene")
		return
	_app = scene.instantiate()
	root.add_child(_app)
	current_scene = _app
	_network = _app.get("network")
	if _network == null:
		_fail("Main must expose its real NetSession as app.network")
		return
	_network.command_provider = _bot_command
	_network.world_updated.connect(_on_world_updated)
	_network.authoritative_events.connect(_on_authoritative_events)
	_network.connection_error.connect(_on_connection_error)
	var error: Error
	if _role == "server":
		error = _network.host(_port, _peer_name, 0)
	else:
		error = _network.join("127.0.0.1", _port, _peer_name, 1 if _peer_name == "client1" else 2)
	if error != OK:
		_fail("%s failed: %s" % [_role, error_string(error)])
		return
	if _role == "server":
		_network.set_bot_fill(0)
		_write_json("server-ready.json", {"port": _port, "pid": OS.get_process_id()})
	while not _failed:
		await process_frame
		if _now() - _started_at > _timeout:
			_fail("Peer timeout: phase=%s epoch=%d members=%s terminal=%s rematch=%s" % [
				_network.flow.get("phase", "unknown"), _network.epoch,
				_network.members, not _terminal.is_empty(), not _rematch.is_empty()])
			return
		_observe_stats()
		if not _ready_sent and _network.connected and _network.members.has(_network.local_id):
			_network.set_ready(true)
			_ready_sent = true
		if not _started_match and _all_ready():
			if _lobby_at < 0.0:
				_lobby_at = _now()
				_queue_capture("lobby")
			if _role == "server" and _now() - _lobby_at >= _stage_hold():
				_started_match = _network.start_match()
				if not _started_match:
					_fail("Host rejected start despite all expected human peers being ready")
					return
		if _network.epoch == 1 and _network.flow.get("phase", "") == "winner" and _terminal.is_empty():
			_record_terminal()
			if _failed:
				return
		if _role == "server" and not _terminal.is_empty() and not _started_rematch:
			# A filesystem barrier only coordinates the test, never gameplay: every
			# peer must have observed the reliable terminal world before rematching.
			if _marker_count(".terminal.json") == _expected_clients + 1 and _now() - _winner_at >= _stage_hold():
				_started_rematch = _network.start_match()
				if not _started_rematch:
					_fail("Host could not start a rematch from the actual winner phase")
					return
		if _network.epoch == 2 and _network.flow.get("phase", "") == "countdown" and _rematch.is_empty():
			_record_rematch()
			if _failed:
				return
		if not _rematch.is_empty() and not _reported and _now() - _rematch_at >= _stage_hold() and _captures_complete():
			_reported = true
			_write_json(_peer_name + ".result.json", _result())
			print("NET_PEER_PASS %s winner=%s stocks=%s rematch_epoch=%d" % [_peer_name, _terminal.winner, _terminal.stocks, _rematch.epoch])
		if _reported and _marker_count(".result.json") == _expected_clients + 1:
			# Leave enough time for every process to observe the barrier before
			# the host tears down ENet; late disconnects cannot invalidate results.
			await create_timer(1.0).timeout
			quit(0)
			return


func _bot_command() -> InputCmd:
	if _network.world.is_empty() or not _network.world.has("players"):
		return InputCmd.new()
	var decision: Dictionary = BotSim.command(_network.world, _network.local_id, _memory, Tuning.FIXED_DELTA)
	_memory = decision.memory
	var command: InputCmd = decision.cmd
	_commands += 1
	if command.move.length_squared() > 0.0:
		_moving_commands += 1
	if command.shove:
		_shove_commands += 1
	return command


func _all_ready() -> bool:
	if not _network.connected or _network.members.size() != _expected_clients + 1:
		return false
	for member: Dictionary in _network.members.values():
		if bool(member.get("bot", false)) or not bool(member.get("ready", false)):
			return false
	return true


func _on_world_updated(_world: Dictionary, flow: Dictionary) -> void:
	_updates += 1
	var phase: String = str(flow.get("phase", ""))
	if not _phases.has(phase):
		_phases.append(phase)
	if _network.epoch == 1 and phase == "playing":
		_queue_capture("playing")
	if _network.epoch == 1 and phase == "ringout":
		_queue_capture("ko")


func _on_authoritative_events(events: Array, _event_world: Dictionary) -> void:
	if _network.epoch != 1:
		return
	for event: Dictionary in events:
		if event.get("type", "") == "ko":
			_ko_events += 1
			_queue_capture("ko")


func _on_connection_error(reason: String) -> void:
	if not _reported:
		_fail("Real network connection failed: " + reason)


func _observe_stats() -> void:
	_peak_snapshot_rate = maxf(_peak_snapshot_rate, float(_network.stats.get("snapshot_rate", 0.0)))
	_peak_dropped = maxi(_peak_dropped, int(_network.stats.get("dropped", 0)))


func _stocks(world: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for id: int in world.get("players", {}):
		result[str(id)] = int(world.players[id].stocks)
	return result


func _record_terminal() -> void:
	var world: Dictionary = _network.authoritative_world
	var stocks: Dictionary = _stocks(world)
	var winner: int = int(_network.flow.get("winner", -1))
	var live: Array = []
	for id: String in stocks:
		if int(stocks[id]) > 0:
			live.append(int(id))
	if stocks.size() != _expected_clients + 1 or live.size() != 1 or winner != int(live[0]):
		_fail("Expected one natural winner and every real peer in authoritative terminal world: winner=%d stocks=%s" % [winner, stocks])
		return
	_terminal = {"epoch": _network.epoch, "tick": int(world.get("tick", -1)), "winner": winner, "stocks": stocks}
	_winner_at = _now()
	_queue_capture("winner")
	_write_json(_peer_name + ".terminal.json", _terminal)


func _record_rematch() -> void:
	if _terminal.is_empty():
		_fail("Observed rematch before this peer received the first terminal state")
		return
	var world: Dictionary = _network.authoritative_world
	var stocks: Dictionary = _stocks(world)
	if stocks.size() != _expected_clients + 1:
		_fail("Rematch lost a real peer: " + str(stocks))
		return
	for stock: int in stocks.values():
		if stock != int(Tuning.STOCKS):
			_fail("Rematch did not reset authoritative stocks: " + str(stocks))
			return
	_rematch = {"epoch": _network.epoch, "phase": str(_network.flow.phase), "stocks": stocks, "tick": int(world.get("tick", -1))}
	_rematch_at = _now()
	_memory.clear()
	_queue_capture("rematch")


func _result() -> Dictionary:
	return {
		"ok": true, "role": _role, "name": _peer_name, "local_id": _network.local_id,
		"terminal": _terminal, "rematch": _rematch, "phases": _phases,
		"commands": _commands, "moving_commands": _moving_commands, "shove_commands": _shove_commands,
		"world_updates": _updates, "ko_events": _ko_events,
		"peak_snapshot_rate": _peak_snapshot_rate, "dropped": _peak_dropped,
		"stats": _network.stats.duplicate(true), "captures": _captures,
		"latency_ms": Tuning.NET_LATENCY_MS, "packet_loss": Tuning.NET_PACKET_LOSS,
		"elapsed_seconds": _now() - _started_at,
	}


func _queue_capture(stage: String) -> void:
	if not _gui or _capture_dir.is_empty() or _captures.has(stage):
		return
	_captures[stage] = "pending"
	_capture.call_deferred(stage)


func _capture(stage: String) -> void:
	# Capture the live application after actual rendering, without staging poses,
	# changing the world, pausing the session, or calling capture_scenario().
	await process_frame
	await RenderingServer.frame_post_draw
	var texture := root.get_texture()
	if texture == null:
		_fail("Real viewport returned no texture for " + stage)
		return
	var image := texture.get_image()
	if image == null or image.is_empty():
		_fail("Real viewport returned an empty image for " + stage)
		return
	var path := _capture_dir.path_join(_peer_name + "-" + stage + ".png")
	var error := image.save_png(path)
	if error != OK:
		_fail("Cannot save %s: %s" % [path, error_string(error)])
		return
	_captures[stage] = path
	print("NET_CAPTURE " + path)


func _captures_complete() -> bool:
	if not _gui or _capture_dir.is_empty():
		return true
	for stage: String in ["lobby", "playing", "ko", "winner", "rematch"]:
		if not _captures.has(stage) or _captures[stage] == "pending":
			return false
	return true


func _stage_hold() -> float:
	return _hold_seconds if _gui else 0.25


func _marker_count(suffix: String) -> int:
	var directory := DirAccess.open(_result_dir)
	if directory == null:
		return 0
	var count := 0
	for filename: String in directory.get_files():
		if filename.ends_with(suffix):
			count += 1
	return count


func _write_json(filename: String, value: Dictionary) -> void:
	var path := _result_dir.path_join(filename)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("Cannot write result artifact: " + path)
		return
	file.store_string(JSON.stringify(value, "\t"))
	file.close()


func _parse_arguments() -> bool:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--role="):
			_role = argument.trim_prefix("--role=")
		elif argument.begins_with("--port="):
			_port = argument.trim_prefix("--port=").to_int()
		elif argument.begins_with("--name="):
			_peer_name = argument.trim_prefix("--name=")
		elif argument.begins_with("--result-dir="):
			_result_dir = argument.trim_prefix("--result-dir=")
		elif argument.begins_with("--expected-clients="):
			_expected_clients = argument.trim_prefix("--expected-clients=").to_int()
		elif argument.begins_with("--timeout="):
			_timeout = argument.trim_prefix("--timeout=").to_float()
		elif argument == "--gui":
			_gui = true
		elif argument.begins_with("--capture-dir="):
			_capture_dir = argument.trim_prefix("--capture-dir=")
		elif argument.begins_with("--hold-seconds="):
			_hold_seconds = argument.trim_prefix("--hold-seconds=").to_float()
	if not ["server", "client"].has(_role) or _peer_name.is_empty() or not _peer_name.is_valid_identifier():
		_fail("Require --role=server/client and an identifier --name=")
		return false
	if not _result_dir.is_absolute_path() or _port < 1 or _port > 65535 or _expected_clients < 1 or _expected_clients > 7 or _timeout <= 0.0 or _hold_seconds < 0.0:
		_fail("Require an absolute --result-dir, valid port/client count, positive timeout and nonnegative hold")
		return false
	if DirAccess.make_dir_recursive_absolute(_result_dir) != OK:
		_fail("Cannot create result directory: " + _result_dir)
		return false
	if not _capture_dir.is_empty():
		if not _gui or not _capture_dir.is_absolute_path() or DirAccess.make_dir_recursive_absolute(_capture_dir) != OK:
			_fail("--capture-dir requires --gui and a writable absolute directory")
			return false
	return true


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	push_error("NET_PEER_FAIL %s: %s" % [_peer_name, message])
	if not _result_dir.is_empty() and not _peer_name.is_empty():
		var file := FileAccess.open(_result_dir.path_join(_peer_name + ".result.json"), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({"ok": false, "name": _peer_name, "error": message}, "\t"))
			file.close()
	quit(1)
