extends SceneTree
## Explicit multi-process integration driver; tools/net_test.py owns orchestration.
## All gameplay is the real main scene and NetSession, driven by normal BotSim inputs.

var Tuning: Node
var BotSim: GDScript
var KitDefs: GDScript
var ReplayCodec: GDScript
var TuningCodec: GDScript
var WorldSim: GDScript
var MatchFlowSim: GDScript
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
var _scenario := "baseline"
var _kit_slots: Array[String] = ["basic_shot", "curve_shot", "quick_fire", "shove", "high_jump", "recovery", "down_dash", "h_dash", "wall"]
var _kit_flags: Dictionary = {"basic_shot": InputCmd.BASIC_SHOT, "curve_shot": InputCmd.CURVE_SHOT, "quick_fire": InputCmd.QUICK_FIRE, "high_jump": InputCmd.HIGH_JUMP, "down_dash": InputCmd.DOWN_DASH, "recovery": InputCmd.RECOVERY, "h_dash": InputCmd.H_DASH, "wall": InputCmd.WALL}
var _kit_index := 0
var _kit_activated: Dictionary = {}
var _kit_outcomes: Dictionary = {"projectile_spawns": 0, "wall_spawns": 0, "projectile_state": 0, "wall_state": 0, "slam_hits": 0, "shove_hits": 0, "deflects": 0, "high_jump_up": 0, "recovery_used": 0, "down_dash_state": 0, "h_dash_speed": 0, "shove_cooldown": 0}
var _recovery_jump_sent := false
var _recovery_jump_released := false
var _kit_patch_sent := false
var _deflect_done := false
var _replay_verified := false
var _kit_patch_received := false
var _legal_settings_bytes := 0
var _full_start_payload_bytes := 0
var _replicated_worlds := 0
var _interpolated_projectiles := 0
var _last_projectile_positions: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _parse_arguments():
		return
	_started_at = _now()
	Tuning = root.get_node("Tuning")
	BotSim = load("res://scripts/sim/bot.gd")
	KitDefs = load("res://scripts/sim/kits.gd")
	ReplayCodec = load("res://scripts/dev/replay.gd")
	TuningCodec = load("res://scripts/dev/tuning_store.gd")
	WorldSim = load("res://scripts/sim/world.gd")
	MatchFlowSim = load("res://scripts/sim/match.gd")
	if BotSim == null or KitDefs == null or ReplayCodec == null or TuningCodec == null or WorldSim == null or MatchFlowSim == null:
		_fail("Could not load runtime simulation/data scripts after Tuning initialization")
		return
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
	if _scenario == "full-kit":
		fixture.merge({
			"SPAWN_RADIUS": 1.3, "CENTER_SIZE": 5.0, "BASE_KB": 1.0,
			"SHOVE_DAMAGE": 1.0, "KB_SCALE": 0.01, "KB_UP": 1.0, "KILL_PLANE": -20.0,
		}, true)
	for field: String in fixture:
		Tuning.set(field, fixture[field])
	if _scenario == "full-kit":
		_legal_settings_bytes = _measure_legal_settings_bytes()
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
	_network.settings_changed.connect(_on_settings_changed)
	var error: Error
	if _role == "server":
		error = _network.host(_port, _peer_name, 0)
	else:
		error = _network.join("127.0.0.1", _port, _peer_name, 1 if _peer_name == "client1" else 2, "water" if _peer_name == "client1" else "fire")
	if error != OK:
		_fail("%s failed: %s" % [_role, error_string(error)])
		return
	if _role == "server":
		_network.set_bot_fill(1 if _scenario == "full-kit" else 0)
		if _scenario == "full-kit":
			_network.members[-2].element = "air"
			_network._broadcast_lobby()
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
				if _scenario == "full-kit" and _role == "server":
					_full_start_payload_bytes = _measure_full_start_payload_bytes()
					var reliable_limit: int = _reliable_raw_limit()
					if _full_start_payload_bytes > reliable_limit:
						_fail("Maximally populated legal start payload exceeds reliable transport bound (%d): %d" % [reliable_limit, _full_start_payload_bytes])
						return
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
	if _scenario == "full-kit" and _kit_index < _kit_slots.size():
		if _peer_name == "client2":
			if _kit_index in [3, 4, 5, 6, 7, 8] and not _deflect_done:
				var actor_id := _kit_actor_id()
				if actor_id >= 0 and _network.world.players.has(actor_id):
					var to_actor: Vector3 = _network.world.players[actor_id].position - _network.world.players[_network.local_id].position
					var forward := Vector3(to_actor.x, 0.0, to_actor.z).normalized()
					var target: Vector3 = _network.world.players[actor_id].position + Vector3(-forward.z, 0.0, forward.x) * 1.5
					var aim: Vector3 = target - _network.world.players[_network.local_id].position
					var shot := InputCmd.new(Vector2.ZERO, false, false, atan2(-aim.x, -aim.z))
					shot.moves = InputCmd.BASIC_SHOT
					_commands += 1
					return shot
			_commands += 1
			return InputCmd.new()
		if _peer_name == "client1":
			var actor_id := _kit_actor_id()
			if actor_id < 0 or not _network.world.players.has(actor_id):
				return InputCmd.new()
			var slot: String = _kit_slots[_kit_index]
			var actor: Dictionary = _network.world.players[actor_id]
			var airborne := not bool(actor.on_ground)
			if slot == "recovery" and not airborne:
				if not _recovery_jump_sent:
					_recovery_jump_sent = true
					var jump_cmd := InputCmd.new()
					jump_cmd.jump = true
					_commands += 1
					return jump_cmd
				if not _recovery_jump_released:
					_recovery_jump_released = true
					_commands += 1
					return InputCmd.new()
				_recovery_jump_sent = false
				_recovery_jump_released = false
				return InputCmd.new()
			var target_id := _named_player_id("client2") if slot == "shove" or (_kit_index >= 4 and not _deflect_done) else _nearest_target(actor_id)
			var yaw := 0.0
			if target_id >= 0:
				var offset: Vector3 = _network.world.players[target_id].position - actor.position
				yaw = atan2(-offset.x, -offset.z)
			var scripted := InputCmd.new(Vector2.ZERO, slot == "recovery" and airborne, slot == "shove" or (_kit_index >= 4 and not _deflect_done), yaw)
			scripted.moves = int(_kit_flags.get(slot, 0))
			if slot in ["basic_shot", "curve_shot", "quick_fire"]:
				scripted.pitch = 0.8
			_commands += 1
			return scripted
		if _role == "server":
			_commands += 1
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

func _kit_actor_id() -> int:
	return _named_player_id("client1")

func _named_player_id(player_name: String) -> int:
	for id: Variant in _network.members:
		if str(_network.members[id].get("name", "")) == player_name:
			return int(id)
	return -1

func _nearest_target(actor_id: int) -> int:
	var best_id := -1
	var best_distance := INF
	for id: int in _network.world.players:
		if id == actor_id:
			continue
		var distance: float = _network.world.players[actor_id].position.distance_squared_to(_network.world.players[id].position)
		if distance < best_distance:
			best_distance = distance
			best_id = id
	return best_id


func _all_ready() -> bool:
	if not _network.connected or _network.members.size() != _expected_clients + 1 + (1 if _scenario == "full-kit" else 0):
		return false
	for member: Dictionary in _network.members.values():
		if not bool(member.get("ready", false)):
			return false
	return true


func _on_world_updated(_world: Dictionary, flow: Dictionary) -> void:
	_updates += 1
	if ReplayCodec._valid_world(_world):
		var complete := true
		var has_cooldown_value := false
		for player: Dictionary in _world.players.values():
			var player_cooldown: Variant = player.get("cooldown", 0.0)
			var cooldowns: Dictionary = player.get("cooldowns", {})
			complete = complete and KitDefs.ELEMENTS.has(str(player.get("element", ""))) and (player_cooldown is int or player_cooldown is float) and is_finite(float(player_cooldown)) and float(player_cooldown) >= 0.0
			for slot: Variant in cooldowns:
				var value: Variant = cooldowns[slot]
				if not KitDefs.SLOTS.has(str(slot)) or not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0.0:
					complete = false
				if (value is int or value is float) and float(value) > 0.0:
					has_cooldown_value = true
			has_cooldown_value = has_cooldown_value or float(player.get("cooldown", 0.0)) > 0.0
		if complete and has_cooldown_value:
			_replicated_worlds += 1
		if _role == "client" and _check_interpolation_midpoint():
			_interpolated_projectiles += 1
	var phase: String = str(flow.get("phase", ""))
	if not _phases.has(phase):
		_phases.append(phase)
	if _network.epoch == 1 and phase == "playing":
		_queue_capture("playing")
	if _network.epoch == 1 and phase == "ringout":
		_queue_capture("ko")
	if _scenario == "full-kit" and _role == "server" and not _kit_patch_sent and _kit_index >= _kit_slots.size() and _kit_outcomes.projectile_state >= 3 and _kit_outcomes.wall_state >= 1 and _kit_outcomes.deflects >= 1:
		_kit_patch_sent = true
		_network.push_tuning("KIT_OVERRIDES", {"water": {"basic_shot": {"damage": 16.0}}})
		_network.push_tuning("SHOVE_DAMAGE", 25.0)
		_network.push_tuning("BASE_KB", 14.0)
		_network.push_tuning("KB_SCALE", 0.2)
		_network.push_tuning("KILL_PLANE", -8.0)

func _check_interpolation_midpoint() -> bool:
	if _network._prediction == null:
		return false
	var history: Array = _network._prediction._history
	for index in range(1, history.size()):
		var left: Dictionary = history[index - 1].world
		var right: Dictionary = history[index].world
		for id: int in left.get("projectiles", {}):
			if not right.get("projectiles", {}).has(id):
				continue
			var a: Dictionary = left.projectiles[id]
			var b: Dictionary = right.projectiles[id]
			if int(a.owner) != int(b.owner) or str(a.behavior) != str(b.behavior) or a.position == b.position:
				continue
			var now: float = (float(history[index - 1].time) + float(history[index].time)) * 0.5 + Tuning.NET_INTERPOLATION
			var rendered: Dictionary = _network._prediction.render_world(now, 0.0)
			if not rendered.get("projectiles", {}).has(id):
				continue
			var expected: Vector3 = a.position.lerp(b.position, 0.5)
			var actual: Vector3 = rendered.projectiles[id].position
			if actual.distance_to(expected) < 0.0001 and actual != a.position and actual != b.position:
				return true
	return false
func _on_authoritative_events(events: Array, event_world: Dictionary) -> void:
	if _network.epoch != 1:
		return
	var actor_id := _kit_actor_id()
	for event: Dictionary in events:
		if event.get("type", "") == "ko":
			_ko_events += 1
			_queue_capture("ko")
		if event.get("type", "") == "deflect" and int(event.get("player", -1)) == actor_id:
			_kit_outcomes.deflects += 1
			_deflect_done = true
			if _kit_activated.has("wall"):
				_kit_index = _kit_slots.size()
		if _scenario == "full-kit" and int(event.get("player", -1)) == actor_id:
			var slot := ""
			if event.get("type", "") == "shove":
				slot = "shove"
			elif event.get("type", "") == "move":
				slot = str(event.get("slot", ""))
			if not slot.is_empty() and _kit_slots.has(slot) and not _kit_activated.has(slot):
				var actor: Dictionary = event_world.get("players", {}).get(actor_id, {})
				var velocity: Vector3 = actor.get("velocity", Vector3.ZERO)
				var physical := true
				match slot:
					"high_jump":
						physical = velocity.y > 0.0 or actor.get("position", Vector3.ZERO).y > actor.get("spawn", Vector3.ZERO).y
						if physical:
							_kit_outcomes.high_jump_up += 1
					"recovery":
						physical = int(actor.get("recovery_used", 0)) > 0 and velocity.y > 0.0
						if physical:
							_kit_outcomes.recovery_used += 1
					"down_dash":
						physical = bool(actor.get("down_dashing", false)) or velocity.y < 0.0
						if physical:
							_kit_outcomes.down_dash_state += 1
					"h_dash":
						physical = Vector2(velocity.x, velocity.z).length() > 0.1
						if physical:
							_kit_outcomes.h_dash_speed += 1
					"shove":
						physical = float(actor.get("cooldown", 0.0)) > 0.0
						if physical:
							_kit_outcomes.shove_cooldown += 1
				if physical:
					_kit_activated[slot] = true
					if slot != "wall" or _deflect_done:
						_kit_index += 1
		if event.get("type", "") == "hit" and int(event.get("attacker", -1)) == actor_id and event.get("source", "") == "down_dash":
			_kit_outcomes.slam_hits += 1
			continue
		if event.get("type", "") == "hit" and int(event.get("attacker", -1)) == actor_id and event.get("source", "") == "shove":
			_kit_outcomes.shove_hits += 1
			continue
		if int(event.get("player", -1)) != actor_id:
			continue
		if event.get("type", "") == "projectile_spawn":
			_kit_outcomes.projectile_spawns += 1
			if event_world.get("projectiles", {}).has(int(event.get("projectile", -1))):
				_kit_outcomes.projectile_state += 1
		elif event.get("type", "") == "wall_spawn":
			_kit_outcomes.wall_spawns += 1
			if event_world.get("walls", {}).has(int(event.get("wall", -1))):
				_kit_outcomes.wall_state += 1


func _on_settings_changed(values: Dictionary) -> void:
	var overrides: Variant = values.get("KIT_OVERRIDES", {})
	if overrides is Dictionary and overrides.get("water", {}).get("basic_shot", {}).get("damage", 0.0) == 16.0:
		_kit_patch_received = true

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
	if stocks.size() != _expected_clients + 1 + (1 if _scenario == "full-kit" else 0) or live.size() != 1 or winner != int(live[0]):
		_fail("Expected one natural winner and every real peer in authoritative terminal world: winner=%d stocks=%s" % [winner, stocks])
		return
	_terminal = {"epoch": _network.epoch, "tick": int(world.get("tick", -1)), "winner": winner, "stocks": stocks}
	_winner_at = _now()
	_queue_capture("winner")
	_write_json(_peer_name + ".terminal.json", _terminal)
	if _scenario == "full-kit" and _role == "server":
		_replay_verified = _verify_recording()
		if not _replay_verified:
			_fail("Host replay diverged after the live KIT_OVERRIDES patch")

func _verify_recording() -> bool:
	var tape = _network.recording
	if tape == null or not tape.settings.get("KIT_OVERRIDES", {}) is Dictionary:
		return false
	var patch_seen := false
	for frame: Dictionary in tape.frames:
		if frame.settings.has("KIT_OVERRIDES"):
			patch_seen = true
	if not patch_seen:
		return false
	var restore: Dictionary = TuningCodec.snapshot()
	TuningCodec.apply(tape.settings)
	var replay_world: Dictionary = tape.restart()
	while tape.has_next():
		var commands: Dictionary = tape.next_commands()
		if not tape.frame_settings.is_empty():
			TuningCodec.apply(tape.frame_settings)
		replay_world = WorldSim.step(replay_world, commands, Tuning.FIXED_DELTA)
	var matches: bool = replay_world == tape.final_world
	TuningCodec.apply(restore)
	return matches


func _record_rematch() -> void:
	if _terminal.is_empty():
		_fail("Observed rematch before this peer received the first terminal state")
		return
	var world: Dictionary = _network.authoritative_world
	var stocks: Dictionary = _stocks(world)
	if stocks.size() != _expected_clients + 1 + (1 if _scenario == "full-kit" else 0):
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


func _max_legal_overrides() -> Dictionary:
	var overrides: Dictionary = {}
	for element: String in KitDefs.ELEMENTS:
		var slots: Dictionary = {}
		for slot: String in KitDefs.SLOTS:
			var fields: Dictionary = {}
			for field: String in KitDefs.move_fields(slot):
				fields[field] = TuningCodec.kit_bounds(element, slot, field).y
			if not fields.is_empty():
				slots[slot] = fields
		overrides[element] = slots
	return overrides

func _measure_legal_settings_bytes() -> int:
	var values: Dictionary = TuningCodec.snapshot()
	values["KIT_OVERRIDES"] = _max_legal_overrides()
	return var_to_bytes(TuningCodec.encode(values)).size()

func _measure_full_start_payload_bytes() -> int:
	var maximum_settings: Dictionary = TuningCodec.snapshot()
	maximum_settings["KIT_OVERRIDES"] = _max_legal_overrides()
	var world_value: Dictionary = WorldSim.create(_network.members.keys())
	for id: int in _network.members:
		WorldSim.set_element(world_value, id, str(_network.members[id].get("element", "earth")))
	var start_flow: Dictionary = MatchFlowSim.create()
	start_flow.phase = "countdown"
	var payload := {
		"epoch": _network.epoch + 1, "world": world_value, "flow": start_flow,
		"settings": TuningCodec.encode(maximum_settings), "members": _network.members,
	}
	return var_to_bytes(payload).size()
func _reliable_raw_limit() -> int:
	var network_script: Script = _network.get_script()
	return int(network_script.get_script_constant_map().get("RELIABLE_RAW_LIMIT", 0))


func _elements(world_value: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for player: Dictionary in world_value.get("players", {}).values():
		var element: String = str(player.get("element", ""))
		if not result.has(element):
			result.append(element)
	result.sort()
	return result

func _result() -> Dictionary:
	return {
		"ok": true, "role": _role, "name": _peer_name, "local_id": _network.local_id,
		"terminal": _terminal, "rematch": _rematch, "phases": _phases,
		"commands": _commands, "moving_commands": _moving_commands, "shove_commands": _shove_commands,
		"world_updates": _updates, "ko_events": _ko_events,
		"peak_snapshot_rate": _peak_snapshot_rate, "dropped": _peak_dropped,
		"stats": _network.stats.duplicate(true), "captures": _captures,
		"latency_ms": Tuning.NET_LATENCY_MS, "jitter_ms": Tuning.NET_JITTER_MS, "packet_loss": Tuning.NET_PACKET_LOSS,
		"elapsed_seconds": _now() - _started_at,
		"elements": _elements(_network.authoritative_world),
		"replay_verified": _replay_verified,
		"kit_patch_received": _kit_patch_received,
		"full_kit": {
			"activated_moves": _kit_activated.size(), "slots": _kit_activated,
			"projectile_spawns": _kit_outcomes.projectile_spawns, "wall_spawns": _kit_outcomes.wall_spawns,
			"projectile_state": _kit_outcomes.projectile_state, "wall_state": _kit_outcomes.wall_state,
			"slam_hits": _kit_outcomes.slam_hits, "shove_hits": _kit_outcomes.shove_hits,
			"deflects": _kit_outcomes.deflects,
			"high_jump_up": _kit_outcomes.high_jump_up, "recovery_used": _kit_outcomes.recovery_used,
			"down_dash_state": _kit_outcomes.down_dash_state, "h_dash_speed": _kit_outcomes.h_dash_speed,
			"shove_cooldown": _kit_outcomes.shove_cooldown,
		},
		"legal_settings_bytes": _legal_settings_bytes,
		"full_start_payload_bytes": _full_start_payload_bytes,
		"reliable_raw_limit": _reliable_raw_limit(),
		"replicated_worlds": _replicated_worlds,
		"interpolated_projectiles": _interpolated_projectiles,
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
		elif argument.begins_with("--scenario="):
			_scenario = argument.trim_prefix("--scenario=")
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
