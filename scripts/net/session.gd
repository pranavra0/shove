class_name NetSession
extends Node

signal lobby_updated()
signal world_updated(world: Dictionary, flow: Dictionary)
signal authoritative_events(events: Array, event_world: Dictionary)
signal settings_changed(values: Dictionary)
signal connection_error(reason: String)

var active: bool = false
var hosting: bool = false
var connected: bool = false
var local_id: int = 0
var members: Dictionary = {}
var bot_fill: int = 0
var world: Dictionary = {}
var authoritative_world: Dictionary = {}
var flow: Dictionary = {"phase": "lobby"}
var command_provider: Callable
var stats: Dictionary = {"ping": 0.0, "snapshot_rate": 0.0, "correction": 0.0, "input_depth": 0, "dropped": 0}
var recording: ReplayTape
var epoch: int = 0
# Reliable lobby/start/tuning payloads may contain the complete legal sparse kit override table.
const RELIABLE_RAW_LIMIT: int = 131072

var _peer: ENetMultiplayerPeer
var _prediction: ClientPrediction
var _profile: Dictionary = {}
var _commands: Dictionary = {}
var _held_commands: Dictionary = {}
var _acks: Dictionary = {}
var _received: Dictionary = {}
var _echo: Dictionary = {}
var _bot_memory: Dictionary = {}
var _pending_settings: Dictionary = {}
var _outbox: Array = []
var _rng := RandomNumberGenerator.new()
var _roster_rng := RandomNumberGenerator.new()
var _sequence: int = 0
var _serial: int = 0
var _last_serial: int = -1
var _event_serial: int = 0
var _last_event: int = 0
var _world_time: float = 0.0
var _snapshot_time: float = 0.0
var _started_at: float = 0.0
var _rate_started: float = 0.0
var _rate_count: int = 0
var _pending_peers: Dictionary = {}
var _last_ping_echo: float = 0.0

func _ready() -> void:
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(_connected_to_server)
	multiplayer.connection_failed.connect(_connection_failed)
	multiplayer.server_disconnected.connect(_server_disconnected)

func host(port: int, player_name: String, color: int, element: String = "earth") -> Error:
	close()
	_peer = ENetMultiplayerPeer.new()
	var error: Error = _peer.create_server(port, clampi(Tuning.NET_MAX_PLAYERS, 2, 8) - 1, 3)
	if error != OK:
		_peer = null
		return error
	multiplayer.multiplayer_peer = _peer
	active = true
	hosting = true
	connected = true
	local_id = 1
	_roster_rng.randomize()
	_rng.seed = Tuning.NET_SEED
	_profile = _member(player_name, color, false, element)
	members[1] = _profile.duplicate(true)
	lobby_updated.emit()
	return OK

func join(address: String, port: int, player_name: String, color: int, element: String = "earth") -> Error:
	close()
	_profile = _member(player_name, color, false, element)
	_peer = ENetMultiplayerPeer.new()
	var error: Error = _peer.create_client(address, port, 3)
	if error != OK:
		_peer = null
		return error
	multiplayer.multiplayer_peer = _peer
	active = true
	_roster_rng.randomize()
	_rng.seed = Tuning.NET_SEED
	return OK

func close() -> void:
	active = false
	connected = false
	hosting = false
	if _peer != null:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	local_id = 0
	members.clear()
	world = {}
	authoritative_world = {}
	flow = {"phase": "lobby"}
	bot_fill = 0
	epoch = 0
	recording = null
	_prediction = null
	_commands.clear()
	_held_commands.clear()
	_acks.clear()
	_received.clear()
	_echo.clear()
	_bot_memory.clear()
	_pending_settings.clear()
	_pending_peers.clear()
	_outbox.clear()
	_reset_clock()
	stats = {"ping": 0.0, "snapshot_rate": 0.0, "correction": 0.0, "input_depth": 0, "dropped": 0}

func set_profile(player_name: String, color: int, ready: bool, element: String = "earth") -> void:
	if not active or not connected:
		return
	var profile := _member(player_name, color, ready, element)
	_profile = profile.duplicate(true)
	if hosting:
		members[1] = profile
		_broadcast_lobby()
	else:
		members[local_id] = profile.duplicate(true)
		_schedule(1, "_profile_rpc", _profile_packet(profile), true)

func set_ready(ready: bool) -> void:
	if members.has(local_id):
		var profile: Dictionary = members[local_id]
		set_profile(str(profile.name), int(profile.color), ready, str(profile.element))

func set_bot_fill(count: int) -> void:
	if not hosting or str(flow.phase) != "lobby":
		return
	bot_fill = clampi(count, 0, clampi(Tuning.NET_MAX_PLAYERS, 2, 8) - _human_count())
	_sync_bots()
	_broadcast_lobby()

func start_match() -> bool:
	if not hosting or not active:
		return false
	for id in members:
		if not members[id].bot and not members[id].ready:
			return false
	_sync_bots()
	if members.size() < 2 or members.size() > 8:
		return false
	epoch += 1
	_outbox.clear()
	_reset_clock()
	_commands.clear()
	_received.clear()
	_acks.clear()
	_echo.clear()
	_bot_memory.clear()
	_held_commands.clear()
	_pending_settings.clear()
	world = World.create(members.keys())
	for id in members:
		World.set_element(world, int(id), str(members[id].get("element", "earth")))
	authoritative_world = world.duplicate(true)
	flow = MatchSim.create()
	flow.phase = "countdown"
	recording = ReplayTape.new()
	recording.begin(world, TuningStore.snapshot())
	var payload := {"epoch": epoch, "world": world, "flow": flow, "settings": TuningStore.encode(TuningStore.snapshot()), "members": members}
	_broadcast("_start_rpc", payload, true)
	world_updated.emit(world, flow)
	return true

func return_to_lobby() -> void:
	if not hosting:
		return
	if recording != null and not world.is_empty():
		recording.finish(world)
	_outbox.clear()
	world = {}
	authoritative_world = {}
	flow = {"phase": "lobby"}
	_broadcast_lobby()
	world_updated.emit(world, flow)

func push_tuning(field: String, value: Variant) -> void:
	if not hosting or not TuningStore.fields().has(field):
		return
	var values: Dictionary = TuningStore.decode(TuningStore.encode({field: value}))
	if values.is_empty():
		return
	settings_changed.emit(values)
	_pending_settings.merge(values, true)
	_broadcast("_settings_rpc", {"epoch": epoch, "settings": TuningStore.encode(values)}, true)
	TuningStore.apply(values)

func _physics_process(delta: float) -> void:
	if not active:
		return
	_flush_outbox()
	if not connected:
		if _now() - _started_at > Tuning.NET_CONNECT_TIMEOUT:
			_fail("Connection timed out")
		return
	if hosting:
		for id in _pending_peers.keys():
			if _now() - float(_pending_peers[id]) > Tuning.NET_CONNECT_TIMEOUT:
				_pending_peers.erase(id)
				_peer.disconnect_peer(id)
	if world.is_empty() or str(flow.phase) == "lobby":
		return
	if hosting:
		_server_tick()
	else:
		_client_tick(delta)

func _server_tick() -> void:
	var previous_phase: String = str(flow.phase)
	if previous_phase == "winner":
		return
	if previous_phase == "playing" or previous_phase == "ringout":
		var scale: float = Tuning.MATCH_RINGOUT_SCALE if previous_phase == "ringout" else 1.0
		if Tuning.DEV_SLOWMO_ENABLED:
			scale *= Tuning.DEV_SLOWMO_SCALE
		_world_time += Tuning.FIXED_DELTA * scale
		while _world_time + 0.0000001 >= Tuning.FIXED_DELTA:
			_world_time = maxf(0.0, _world_time - Tuning.FIXED_DELTA)
			var commands: Dictionary = {}
			for id in world.players:
				var cmd: InputCmd
				if members.has(id) and members[id].bot:
					var decision: Dictionary = BotSim.command(world, id, _bot_memory.get(id, {}), Tuning.FIXED_DELTA)
					_bot_memory[id] = decision.memory
					cmd = decision.cmd
				elif id == 1:
					cmd = _sample_command()
				else:
					if _commands.has(id) and not _commands[id].is_empty():
						var queue: Array = _commands[id]
						var next_value: Variant = queue.pop_front()
						cmd = next_value as InputCmd
						if queue.is_empty():
							_commands.erase(id)
						else:
							_commands[id] = queue
						_acks[id] = cmd.tick
						var held := InputCmd.new(cmd.move, cmd.jump, false, cmd.yaw, cmd.tick)
						held.pitch = cmd.pitch
						held.moves = cmd.moves & InputCmd.HELD_MOVES
						_held_commands[id] = held
					else:
						var fallback: InputCmd
						if _held_commands.has(id):
							fallback = _held_commands[id]
						else:
							fallback = InputCmd.new(Vector2.ZERO, false, false, world.players[id].yaw, int(_acks.get(id, 0)))
						cmd = InputCmd.new(fallback.move, fallback.jump, false, fallback.yaw, int(_acks.get(id, 0)))
						cmd.pitch = fallback.pitch
						cmd.moves = fallback.moves & InputCmd.HELD_MOVES
					# Fallback keeps movement/jump/yaw/pitch and BASIC_SHOT/QUICK_FIRE, never edges.
				commands[id] = cmd
			recording.record(commands, _pending_settings)
			_pending_settings.clear()
			world = World.step(world, commands, Tuning.FIXED_DELTA)
			if not world.events.is_empty():
				_event_serial += 1
				var event_packet := {"epoch": epoch, "id": _event_serial, "tick": world.tick, "events": world.events, "world": world}
				_broadcast("_events_rpc", event_packet, true)
				authoritative_events.emit(world.events, world)
	flow = MatchSim.step(flow, world, Tuning.FIXED_DELTA)
	if str(flow.phase) != previous_phase:
		_world_time = 0.0
	authoritative_world = world.duplicate(true)
	if str(flow.phase) == "winner":
		recording.finish(world)
		_send_snapshot(true)
	else:
		_snapshot_time += Tuning.FIXED_DELTA
		if _snapshot_time >= 1.0 / maxf(1.0, Tuning.NET_SNAPSHOT_RATE):
			_snapshot_time = 0.0
			_send_snapshot(false)
	world_updated.emit(world, flow)

func _client_tick(delta: float) -> void:
	if _prediction == null:
		return
	if str(flow.phase) == "playing" or str(flow.phase) == "ringout":
		var cmd := _sample_command()
		_sequence += 1
		cmd.tick = _sequence
		_prediction.advance(cmd, Tuning.FIXED_DELTA)
		var pending: Array = _prediction.unacknowledged()
		var count: int = clampi(Tuning.NET_INPUT_REDUNDANCY, 1, 64)
		var batch: Array = pending.slice(maxi(0, pending.size() - count))
		_schedule(1, "_input_rpc", {"epoch": epoch, "commands": batch, "sent": _now()}, false)
	world = _prediction.render_world(_now(), delta)
	stats.correction = _prediction.correction_magnitude
	stats.input_depth = _prediction.pending.size()
	world_updated.emit(world, flow)

func _sample_command() -> InputCmd:
	if command_provider.is_valid():
		var value: Variant = command_provider.call()
		if value is InputCmd:
			var copy: InputCmd = InputCmd.from_dict(value.to_dict())
			if copy != null:
				return copy
	return InputCmd.new()

func _send_snapshot(terminal: bool) -> void:
	_serial += 1
	var elapsed: float = _now() - _rate_started
	_rate_count += 1
	if elapsed >= 1.0:
		stats.snapshot_rate = _rate_count / elapsed
		_rate_count = 0
		_rate_started = _now()
	for id in members:
		if id == 1 or members[id].bot:
			continue
		var packet := {"epoch": epoch, "serial": _serial, "world": world, "flow": flow, "ack": int(_acks.get(id, 0)), "echo": float(_echo.get(id, 0.0))}
		_schedule(id, "_final_rpc" if terminal else "_snapshot_rpc", packet, terminal)

@rpc("any_peer", "call_remote", "reliable", 0)
func _hello_rpc(data: Dictionary) -> void:
	if not hosting:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not _pending_peers.has(sender):
		return
	_pending_peers.erase(sender)
	if str(flow.phase) != "lobby":
		_schedule(sender, "_rejected_rpc", {"reason": "Match already in progress; join from the lobby"}, true)
		return
	if _human_count() >= clampi(Tuning.NET_MAX_PLAYERS, 2, 8) or not _valid_profile(data):
		_schedule(sender, "_rejected_rpc", {"reason": "Lobby full or invalid profile"}, true)
		return
	members[sender] = _member(data.name, data.color, data.ready, data.element)
	bot_fill = mini(bot_fill, clampi(Tuning.NET_MAX_PLAYERS, 2, 8) - _human_count())
	_sync_bots()
	_broadcast_lobby()

@rpc("any_peer", "call_remote", "reliable", 0)
func _profile_rpc(data: Dictionary) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if hosting and members.has(sender) and _valid_profile(data):
		members[sender] = _member(data.name, data.color, data.ready, data.element)
		_broadcast_lobby()

@rpc("authority", "call_remote", "reliable", 0)
func _lobby_rpc(data: Dictionary) -> void:
	if hosting or not data.has_all(["members", "bots", "epoch", "lobby"]) or not data.members is Dictionary or not data.epoch is int or data.epoch < epoch:
		return
	members = data.members.duplicate(true)
	if members.has(local_id):
		var self_profile: Dictionary = members[local_id]
		_profile = _member(str(self_profile.name), int(self_profile.color), bool(self_profile.ready), str(self_profile.get("element", "earth")))
	bot_fill = int(data.bots)
	connected = true
	if data.lobby:
		_outbox.clear()
		world = {}
		authoritative_world = {}
		_prediction = null
		flow = {"phase": "lobby"}
	lobby_updated.emit()
	if data.lobby:
		world_updated.emit(world, flow)

@rpc("authority", "call_remote", "reliable", 0)
func _start_rpc(data: Dictionary) -> void:
	if hosting or not data.has_all(["epoch", "world", "flow", "settings", "members"]) or not data.epoch is int or data.epoch <= epoch or not data.settings is Dictionary or not data.flow is Dictionary or not data.members is Dictionary or not ReplayTape._valid_world(data.world):
		return
	var values: Dictionary = TuningStore.decode(data.settings)
	if values.is_empty() or not data.world.players.has(local_id):
		_fail("Invalid server match configuration")
		return
	settings_changed.emit(values)
	TuningStore.apply(values)
	epoch = data.epoch
	_outbox.clear()
	_reset_clock()
	members = data.members.duplicate(true)
	world = data.world.duplicate(true)
	authoritative_world = world.duplicate(true)
	flow = data.flow.duplicate(true)
	_prediction = ClientPrediction.new()
	_prediction.begin(world, local_id, _now())
	lobby_updated.emit()
	world_updated.emit(world, flow)

@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _input_rpc(packet: PackedByteArray) -> void:
	var data: Dictionary = _decode_unreliable(packet)
	var sender: int = multiplayer.get_remote_sender_id()
	if not hosting or not members.has(sender) or members[sender].bot or world.is_empty() or not data.has_all(["epoch", "commands", "sent"]) or data.epoch != epoch or not data.commands is Array or data.commands.size() > 64 or not _finite(data.sent):
		return
	var latest: int = int(_received.get(sender, 0))
	var previous: int = -1
	var parsed: Array = []
	for wire in data.commands:
		if not wire is Dictionary:
			return
		var cmd: InputCmd = InputCmd.from_dict(wire)
		if cmd == null or cmd.tick <= 0 or cmd.tick <= previous or cmd.tick > latest + clampi(Tuning.NET_MAX_PENDING, 1, 4096) + 64:
			return
		previous = cmd.tick
		parsed.append(cmd)
	var queue: Array = _commands.get(sender, [])
	var queue_limit: int = clampi(Tuning.NET_MAX_PENDING, 1, 4096)
	for value in parsed:
		var cmd: InputCmd = value
		if cmd.tick <= latest:
			continue
		if queue.size() >= queue_limit:
			break
		# Queue consumes release and edge intents once; fallback retains only HELD_MOVES.
		queue.append(cmd)
		latest = cmd.tick
	if latest > int(_received.get(sender, 0)):
		_received[sender] = latest
		_commands[sender] = queue
		_echo[sender] = float(data.sent)

@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _snapshot_rpc(packet: PackedByteArray) -> void:
	_receive_snapshot(_decode_unreliable(packet))

@rpc("authority", "call_remote", "reliable", 0)
func _final_rpc(data: Dictionary) -> void:
	_receive_snapshot(data)

func _receive_snapshot(data: Dictionary) -> void:
	if hosting or _prediction == null or not data.has_all(["epoch", "serial", "world", "flow", "ack", "echo"]) or data.epoch != epoch or not data.serial is int or data.serial <= _last_serial or not data.ack is int or not data.flow is Dictionary or not _finite(data.echo) or not ReplayTape._valid_world(data.world):
		return
	_last_serial = data.serial
	authoritative_world = data.world.duplicate(true)
	flow = data.flow.duplicate(true)
	if str(flow.phase) in ["round_end", "winner"]:
		_prediction.begin(authoritative_world, local_id, _now())
	else:
		_prediction.reconcile(authoritative_world, data.ack, _now())
	world = _prediction.render_world(_now(), 0.0)
	if float(data.echo) > _last_ping_echo:
		_last_ping_echo = float(data.echo)
		stats.ping = maxf(0.0, (_now() - _last_ping_echo) * 1000.0)
	_rate_count += 1
	var elapsed: float = _now() - _rate_started
	if elapsed >= 1.0:
		stats.snapshot_rate = _rate_count / elapsed
		_rate_count = 0
		_rate_started = _now()
	stats.correction = _prediction.correction_magnitude
	stats.input_depth = _prediction.pending.size()
	world_updated.emit(world, flow)

@rpc("authority", "call_remote", "reliable", 0)
func _events_rpc(data: Dictionary) -> void:
	if hosting or not data.has_all(["epoch", "id", "tick", "events", "world"]) or data.epoch != epoch or not data.id is int or data.id <= _last_event or not data.events is Array or not ReplayTape._valid_world(data.world):
		return
	_last_event = data.id
	authoritative_events.emit(data.events, data.world)

@rpc("authority", "call_remote", "reliable", 0)
func _settings_rpc(data: Dictionary) -> void:
	if hosting or not data.has_all(["epoch", "settings"]) or data.epoch != epoch or not data.settings is Dictionary:
		return
	var values: Dictionary = TuningStore.decode(data.settings)
	if not values.is_empty():
		settings_changed.emit(values)
		TuningStore.apply(values)

@rpc("authority", "call_remote", "reliable", 0)
func _rejected_rpc(data: Dictionary) -> void:
	_fail(str(data.get("reason", "Connection rejected")))

func _peer_connected(id: int) -> void:
	if hosting:
		_pending_peers[id] = _now()

func _peer_disconnected(id: int) -> void:
	_pending_peers.erase(id)
	if not hosting or not members.has(id):
		return
	members.erase(id)
	_commands.erase(id)
	_held_commands.erase(id)
	_received.erase(id)
	_acks.erase(id)
	_echo.erase(id)
	if not world.is_empty() and world.players.has(id) and str(flow.phase) != "winner":
		world = world.duplicate(true)
		world.players[id].stocks = 0
		world.players[id].velocity = Vector3.ZERO
		authoritative_world = world.duplicate(true)
		# A departure is an external roster edit, so start a new reproducible tape segment.
		recording = ReplayTape.new()
		recording.begin(world, TuningStore.snapshot())
	_broadcast_lobby()

func _connected_to_server() -> void:
	if not active or hosting:
		return
	local_id = multiplayer.get_unique_id()
	_schedule(1, "_hello_rpc", _profile_packet(_profile), true)

func _connection_failed() -> void:
	if active and not hosting:
		_fail("Could not connect to host")

func _server_disconnected() -> void:
	if active and not hosting:
		_fail("Host disconnected")

func _fail(reason: String) -> void:
	close()
	connection_error.emit(reason)

func _member(player_name: String, color: int, ready: bool, element: String = "earth") -> Dictionary:
	var clean: String = player_name.strip_edges().replace("\n", " ").replace("\r", " ").left(24)
	var selected_element: String = element if Kits.ELEMENTS.has(element) else "earth"
	return {"name": clean if not clean.is_empty() else "Player", "color": clampi(color, 0, maxi(0, Tuning.HUD_PLAYER_COLORS.size() - 1)), "ready": ready, "element": selected_element, "bot": false}

func _profile_packet(profile: Dictionary) -> Dictionary:
	return {"name": str(profile.name), "color": int(profile.color), "ready": bool(profile.ready), "element": str(profile.get("element", "earth"))}

func _valid_profile(data: Dictionary) -> bool:
	return data.size() == 4 and data.has_all(["name", "color", "ready", "element"]) and data.name is String and data.name.length() <= 128 and data.color is int and data.color >= 0 and data.color < Tuning.HUD_PLAYER_COLORS.size() and data.ready is bool and data.element is String and Kits.ELEMENTS.has(data.element)

func _human_count() -> int:
	var count: int = 0
	for id in members:
		if not members[id].bot:
			count += 1
	return count

func _sync_bots() -> void:
	var existing_bots: Dictionary = {}
	for id in members.keys():
		if members[id].bot:
			existing_bots[id] = members[id].duplicate(true)
			members.erase(id)
	bot_fill = clampi(bot_fill, 0, clampi(Tuning.NET_MAX_PLAYERS, 2, 8) - _human_count())
	for index in range(bot_fill):
		var bot_id: int = -index - 2
		if existing_bots.has(bot_id):
			members[bot_id] = existing_bots[bot_id]
			continue
		var profile := _member("Bot %d" % (index + 1), index + _human_count(), true, Kits.ELEMENTS[_roster_rng.randi_range(0, Kits.ELEMENTS.size() - 1)])
		profile.bot = true
		members[bot_id] = profile

func _broadcast_lobby() -> void:
	_broadcast("_lobby_rpc", {"members": members, "bots": bot_fill, "epoch": epoch, "lobby": str(flow.phase) == "lobby"}, true)
	lobby_updated.emit()

func _broadcast(method: String, data: Dictionary, reliable: bool) -> void:
	for id in members:
		if id != 1 and not members[id].bot:
			_schedule(id, method, data, reliable)

func _schedule(target: int, method: String, data: Dictionary, reliable: bool) -> void:
	if not reliable and _rng.randf() < clampf(Tuning.NET_PACKET_LOSS, 0.0, 1.0):
		stats.dropped += 1
		return
	if reliable:
		var raw: PackedByteArray = var_to_bytes(data)
		if raw.is_empty() or raw.size() > RELIABLE_RAW_LIMIT:
			stats.dropped += 1
			return
		rpc_id(target, method, data)
		return
	var encoded: PackedByteArray = _encode_unreliable(data)
	if encoded.is_empty():
		stats.dropped += 1
		return
	var delay: float = maxf(0.0, Tuning.NET_LATENCY_MS + _rng.randf_range(-Tuning.NET_JITTER_MS, Tuning.NET_JITTER_MS)) / 1000.0
	if delay <= 0.0:
		rpc_id(target, method, encoded)
		return
	if _outbox.size() >= 4096:
		stats.dropped += 1
		return
	_outbox.append({"target": target, "method": method, "data": encoded, "due": _now() + delay, "epoch": epoch})

func _flush_outbox() -> void:
	var now: float = _now()
	var waiting: Array = []
	for packet in _outbox:
		if packet.epoch != epoch:
			continue
		if packet.due > now:
			waiting.append(packet)
		elif not hosting or members.has(packet.target):
			rpc_id(packet.target, packet.method, packet.data)
	_outbox = waiting

func _reset_clock() -> void:
	_sequence = 0
	_serial = 0
	_last_serial = -1
	_event_serial = 0
	_last_event = 0
	_world_time = 0.0
	_snapshot_time = 0.0
	_rate_started = _now()
	_rate_count = 0
	_last_ping_echo = 0.0

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _finite(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

# Repeated dictionary keys compress well; keep unreliable snapshots below ENet's MTU.
# Decompression is bounded and object decoding is never enabled.
func _encode_unreliable(data: Dictionary) -> PackedByteArray:
	var raw: PackedByteArray = var_to_bytes(data)
	if raw.is_empty() or raw.size() > 65536:
		return PackedByteArray()
	var encoded: PackedByteArray = raw.compress(FileAccess.COMPRESSION_DEFLATE)
	return encoded if not encoded.is_empty() and encoded.size() <= 8192 else PackedByteArray()

func _decode_unreliable(packet: PackedByteArray) -> Dictionary:
	if packet.is_empty() or packet.size() > 8192:
		return {}
	var bytes: PackedByteArray = packet.decompress_dynamic(65536, FileAccess.COMPRESSION_DEFLATE)
	if bytes.is_empty():
		return {}
	var decoded: Variant = bytes_to_var(bytes)
	return decoded if decoded is Dictionary else {}
