class_name ReplayTape
extends RefCounted

var initial_world: Dictionary = {}
var settings: Dictionary = {}
var frames: Array = []
var final_world: Dictionary = {}
var cursor: int = 0
var frame_settings: Dictionary = {}

func begin(world: Dictionary, captured_settings: Dictionary) -> void:
	initial_world = world.duplicate(true)
	settings = captured_settings.duplicate(true)
	frames = []
	final_world = {}
	cursor = 0
	frame_settings = {}

func record(commands: Dictionary, settings_patch: Dictionary = {}) -> void:
	var wire: Dictionary = {}
	for id in commands:
		assert(id is int and commands[id] is InputCmd)
		wire[id] = commands[id].to_dict()
	frames.append({"commands": wire, "settings": settings_patch.duplicate(true)})

func finish(world: Dictionary) -> void:
	final_world = world.duplicate(true)

func restart() -> Dictionary:
	cursor = 0
	frame_settings = {}
	return initial_world.duplicate(true)

func has_next() -> bool:
	return cursor < frames.size()

func next_commands() -> Dictionary:
	frame_settings = {}
	if not has_next():
		return {}
	var frame: Dictionary = frames[cursor]
	cursor += 1
	frame_settings = frame.settings.duplicate(true)
	var commands: Dictionary = {}
	for id in frame.commands:
		commands[id] = InputCmd.from_dict(frame.commands[id])
	return commands

func save(path: String) -> Error:
	var payload := {"initial": initial_world, "settings": settings, "frames": frames, "final": final_world}
	if not _valid(payload):
		return ERR_INVALID_DATA
	var encoded: Variant = _encode(payload)
	if encoded == null:
		return ERR_INVALID_DATA
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"version": 3, "tape": encoded}, "", true, true))
	return file.get_error()

func load_file(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return ERR_PARSE_ERROR
	var envelope: Variant = json.data
	if not envelope is Dictionary or envelope.size() != 2 or envelope.get("version") != 3 or not envelope.has("tape"):
		return ERR_INVALID_DATA
	var decoded: Dictionary = _decode(envelope.tape)
	if not decoded.ok or not _valid(decoded.value):
		return ERR_INVALID_DATA
	var payload: Dictionary = decoded.value
	initial_world = payload.initial
	settings = payload.settings
	frames = payload.frames
	final_world = payload.final
	cursor = 0
	frame_settings = {}
	return OK

# Tagged containers preserve integer dictionary keys and numeric/vector types without
# object deserialization. Integers use decimal strings, avoiding JSON's 53-bit limit.
static func _encode(value: Variant) -> Variant:
	match typeof(value):
		TYPE_BOOL, TYPE_STRING:
			return value
		TYPE_INT:
			return {"t": "int", "v": str(value)}
		TYPE_FLOAT:
			if not is_finite(value):
				return null
			var bytes := PackedByteArray()
			bytes.resize(8)
			bytes.encode_double(0, value)
			return {"t": "float", "v": bytes.hex_encode()}
		TYPE_VECTOR2:
			return {"t": "Vector2", "v": [value.x, value.y]} if value.is_finite() else null
		TYPE_VECTOR3:
			return {"t": "Vector3", "v": [value.x, value.y, value.z]} if value.is_finite() else null
		TYPE_COLOR:
			var channels := [value.r, value.g, value.b, value.a]
			for channel in channels:
				if not is_finite(channel):
					return null
			return {"t": "Color", "v": channels}
		TYPE_ARRAY, TYPE_DICTIONARY:
			var items: Array = []
			if value is Dictionary:
				for key in value:
					var encoded_key: Variant = _encode(key)
					var encoded_value: Variant = _encode(value[key])
					if encoded_key == null or encoded_value == null:
						return null
					items.append([encoded_key, encoded_value])
			else:
				for item in value:
					var encoded: Variant = _encode(item)
					if encoded == null:
						return null
					items.append(encoded)
			var tag := "Dictionary" if value is Dictionary else "Array"
			if value is Array and value.is_typed() and value.get_typed_builtin() == TYPE_COLOR:
				tag = "Colors"
			return {"t": tag, "v": items}
	return null

static func _decode(data: Variant, depth: int = 0) -> Dictionary:
	var bad := {"ok": false, "value": null}
	if depth > 64:
		return bad
	if data is bool or data is String:
		return {"ok": true, "value": data}
	if not data is Dictionary or data.size() != 2 or not data.has_all(["t", "v"]) or not data.t is String:
		return bad
	var value: Variant = data.v
	match data.t:
		"int":
			if not value is String or not value.is_valid_int() or str(int(value)) != value:
				return bad
			value = int(value)
		"float":
			if not value is String or value.length() != 16 or not value.is_valid_hex_number(false):
				return bad
			value = value.hex_decode().decode_double(0)
			if not is_finite(value):
				return bad
		"Vector2", "Vector3", "Color":
			var count: int = 2 if data.t == "Vector2" else (3 if data.t == "Vector3" else 4)
			if not value is Array or value.size() != count:
				return bad
			for component in value:
				if not (component is float or component is int) or not is_finite(float(component)):
					return bad
			if count == 2:
				value = Vector2(value[0], value[1])
			elif count == 3:
				value = Vector3(value[0], value[1], value[2])
			else:
				value = Color(value[0], value[1], value[2], value[3])
		"Array", "Colors", "Dictionary":
			if not value is Array:
				return bad
			var items: Array = []
			var entries: Dictionary = {}
			for item in value:
				if data.t == "Dictionary":
					if not item is Array or item.size() != 2:
						return bad
					var key := _decode(item[0], depth + 1)
					var entry := _decode(item[1], depth + 1)
					if not key.ok or not entry.ok or not (key.value is String or key.value is int) or entries.has(key.value):
						return bad
					entries[key.value] = entry.value
				else:
					var decoded := _decode(item, depth + 1)
					if not decoded.ok or (data.t == "Colors" and not decoded.value is Color):
						return bad
					items.append(decoded.value)
			value = entries if data.t == "Dictionary" else items
			if data.t == "Colors":
				var colors: Array[Color] = []
				colors.assign(items)
				value = colors
		_:
			return bad
	return {"ok": true, "value": value}

static func _valid(payload: Variant) -> bool:
	if not payload is Dictionary or not payload.has_all(["initial", "settings", "frames", "final"]) or payload.size() != 4:
		return false
	if not _valid_world(payload.initial) or not _valid_world(payload.final) or not payload.settings is Dictionary or not payload.frames is Array:
		return false
	if not _valid_codec_value(payload.settings) or payload.final.tick != payload.initial.tick + payload.frames.size() or payload.initial.players.keys() != payload.final.players.keys():
		return false
	if payload.frames.size() > 1000000:
		return false
	for frame in payload.frames:
		if not frame is Dictionary or frame.size() != 2 or not frame.has_all(["commands", "settings"]) or not frame.commands is Dictionary or not frame.settings is Dictionary:
			return false
		if frame.commands.size() > 8 or not _valid_codec_value(frame.settings):
			return false
		for id in frame.commands:
			if not id is int or not payload.initial.players.has(id) or not frame.commands[id] is Dictionary:
				return false
			var command := InputCmd.from_dict(frame.commands[id])
			if command == null or command.to_dict() != frame.commands[id]:
				return false
	return true

static func _valid_world(world: Variant) -> bool:
	if not world is Dictionary or world.size() != 8 or not world.has_all(["tick", "players", "events", "projectiles", "walls", "next_entity_id", "mode", "control"]):
		return false
	if not world.tick is int or world.tick < 0 or not world.players is Dictionary or world.players.size() > 8:
		return false
	if not world.mode is String or not ["ffa", "control"].has(world.mode) or not world.control is Dictionary:
		return false
	if world.mode == "ffa":
		if not world.control.is_empty():
			return false
	elif not _valid_control(world.control):
		return false
	if not world.events is Array or world.events.size() > 512 or not world.projectiles is Dictionary or world.projectiles.size() > 128:
		return false
	if not world.walls is Dictionary or world.walls.size() > 64 or not world.next_entity_id is int or world.next_entity_id < 1:
		return false
	var max_id: int = 0
	var team_counts: Array[int] = [0, 0]
	for id: Variant in world.players:
		if not id is int or not world.players[id] is Dictionary or not _valid_player(world.players[id], world.players, world.mode):
			return false
		if world.mode == "control":
			var player: Dictionary = world.players[id]
			team_counts[int(player.team)] += 1
			if team_counts[int(player.team)] > 4:
				return false
	for id in world.projectiles:
		if not id is int or id <= 0 or world.walls.has(id) or not world.projectiles[id] is Dictionary:
			return false
		var projectile: Dictionary = world.projectiles[id]
		if not _valid_projectile(projectile, id, world.players):
			return false
		max_id = maxi(max_id, id)
	for id in world.walls:
		if not id is int or id <= 0 or not world.walls[id] is Dictionary:
			return false
		var wall: Dictionary = world.walls[id]
		if not _valid_wall(wall, id, world.players):
			return false
		max_id = maxi(max_id, id)
	if world.next_entity_id <= max_id:
		return false
	for event in world.events:
		if not event is Dictionary or not event.get("type") is String or not event.get("player") is int or not world.players.has(event.player):
			return false
		if not _valid_codec_value(event):
			return false
	return true

static func _valid_control(control: Dictionary) -> bool:
	if control.size() != 3 or not control.has_all(["zones", "scores", "winner_team"]) or not control.zones is Array or control.zones.size() != 2 or not control.scores is Array or control.scores.size() != 2:
		return false
	if not control.winner_team is int or control.winner_team < -1 or control.winner_team > 1:
		return false
	for score: Variant in control.scores:
		if not _finite_number(score) or float(score) < 0.0 or float(score) > 2000000000.0:
			return false
	for zone: Variant in control.zones:
		if not zone is Dictionary or zone.size() != 5 or not zone.has_all(["position", "radius", "owner", "capturing", "progress"]):
			return false
		if not zone.position is Vector3 or not zone.position.is_finite() or zone.position.length_squared() > 100000000.0:
			return false
		if not _finite_number(zone.radius) or float(zone.radius) <= 0.0 or float(zone.radius) > 1000.0:
			return false
		if not zone.owner is int or zone.owner < -1 or zone.owner > 1 or not zone.capturing is int or zone.capturing < -1 or zone.capturing > 1:
			return false
		if not _finite_number(zone.progress) or float(zone.progress) < 0.0 or float(zone.progress) > 1.0:
			return false
	return true

static func _valid_player(player: Dictionary, players: Dictionary, mode: String) -> bool:
	var fields: Array = ["position", "velocity", "on_ground", "ground_angle", "yaw", "damage", "stocks", "hitstun", "invuln", "attack_time", "cooldown", "attack_hits", "spawn", "element", "cooldowns", "move_state", "recovery_used", "jump_held", "down_dashing", "dash_time", "chain_timer", "chain_hits", "chain_target", "attack_serial", "team", "respawn_remaining"]
	if player.size() != fields.size() or not player.has_all(fields):
		return false
	if not player.team is int or not _finite_number(player.respawn_remaining) or player.respawn_remaining < 0.0 or player.respawn_remaining > 60.0:
		return false
	if mode == "ffa":
		if player.team != -1 or player.respawn_remaining != 0.0:
			return false
	elif player.team < 0 or player.team > 1:
		return false
	for field in ["position", "velocity", "spawn"]:
		if not player[field] is Vector3 or not player[field].is_finite():
			return false
	for field in ["ground_angle", "yaw", "damage", "hitstun", "invuln", "attack_time", "cooldown", "dash_time", "chain_timer"]:
		if not _finite_number(player[field]):
			return false
		if field in ["hitstun", "invuln", "attack_time", "cooldown", "dash_time", "chain_timer"] and (float(player[field]) < 0.0 or float(player[field]) > 3600.0):
			return false
	if player.damage < 0.0 or player.damage > 1000000.0:
		return false
	if not player.on_ground is bool or not player.jump_held is bool or not player.down_dashing is bool:
		return false
	if not player.stocks is int or player.stocks < 0 or not player.recovery_used is int or player.recovery_used < 0 or player.recovery_used > 2 or not player.chain_hits is int or player.chain_hits < 0 or not player.chain_target is int or (player.chain_target != -1 and not players.has(player.chain_target)) or not player.attack_serial is int or player.attack_serial < 0:
		return false
	if not _valid_element(player.element) or not player.attack_hits is Array or player.attack_hits.size() > 8:
		return false
	for hit in player.attack_hits:
		if not hit is int or not players.has(hit):
			return false
	if not player.cooldowns is Dictionary or player.cooldowns.size() > 9:
		return false
	for slot in player.cooldowns:
		if not _valid_slot(slot) or not _finite_number(player.cooldowns[slot]) or player.cooldowns[slot] < 0.0 or player.cooldowns[slot] > 3600.0:
			return false
	var state: Variant = player.move_state
	if not state is Dictionary:
		return false
	if state.is_empty():
		return true
	if state.size() != 6 or not state.has_all(["slot", "windup", "duration", "aim", "strafe", "activated"]):
		return false
	return _valid_slot(state.get("slot")) and _finite_number(state.windup) and state.windup >= 0.0 and state.windup <= 3600.0 and _finite_number(state.duration) and state.duration >= 0.0 and state.duration <= 3600.0 and state.aim is Vector3 and state.aim.is_finite() and _finite_number(state.strafe) and state.activated is bool

static func _valid_projectile(entity: Dictionary, id: int, players: Dictionary) -> bool:
	var fields: Array = ["id", "position", "velocity", "owner", "element", "slot", "age", "deflections", "behavior", "damage", "kb_base", "kb_scale", "momentum", "size", "duration", "hitstun", "kb_up", "curve", "gravity", "homing", "bounce_count", "hit_ids", "spike_pop_speed", "spike_damage_mult", "spike_kb_mult"]
	if entity.size() != fields.size() or not entity.has_all(fields) or not entity.id is int or entity.id != id:
		return false
	if not entity.position is Vector3 or not entity.position.is_finite() or not entity.velocity is Vector3 or not entity.velocity.is_finite() or not entity.momentum is Vector3 or not entity.momentum.is_finite():
		return false
	if not entity.owner is int or not players.has(entity.owner) or not _valid_element(entity.element) or not _valid_projectile_slot(entity.slot):
		return false
	if not entity.behavior is String or not ["level", "spike", "lob", "curve"].has(entity.behavior) or not entity.hit_ids is Array or entity.hit_ids.size() > 8:
		return false
	for field in ["age", "damage", "kb_base", "kb_scale", "size", "duration", "hitstun", "kb_up", "gravity", "homing", "spike_pop_speed", "spike_damage_mult", "spike_kb_mult"]:
		if not _finite_number(entity[field]) or entity[field] < 0.0:
			return false
		if field in ["age", "duration", "hitstun"] and entity[field] > 3600.0:
			return false
	if not _finite_number(entity.curve):
		return false
	if entity.size <= 0.0 or entity.duration <= 0.0 or not entity.deflections is int or entity.deflections < 0 or entity.deflections > 1000000 or not entity.bounce_count is int or entity.bounce_count < 0 or entity.bounce_count > 1000000:
		return false
	for hit in entity.hit_ids:
		if not hit is int or not players.has(hit):
			return false
	return true

static func _valid_wall(entity: Dictionary, id: int, players: Dictionary) -> bool:
	var fields: Array = ["id", "position", "size", "owner", "element", "age", "duration", "hp", "hit_shoves"]
	if entity.size() != fields.size() or not entity.has_all(fields) or not entity.id is int or entity.id != id or not entity.position is Vector3 or not entity.position.is_finite() or not entity.size is Vector3 or not entity.size.is_finite() or entity.size.x <= 0.0 or entity.size.y <= 0.0 or entity.size.z <= 0.0 or not entity.owner is int or not players.has(entity.owner) or not _valid_element(entity.element) or not _finite_number(entity.age) or entity.age < 0.0 or entity.age > 3600.0 or not _finite_number(entity.duration) or entity.duration <= 0.0 or entity.duration > 3600.0 or not entity.hp is int or entity.hp <= 0 or not entity.hit_shoves is Dictionary or entity.hit_shoves.size() > 8:
		return false
	for owner in entity.hit_shoves:
		if not owner is int or not players.has(owner) or not entity.hit_shoves[owner] is int or entity.hit_shoves[owner] < 0:
			return false
	return true

static func _valid_codec_value(value: Variant, depth: int = 0) -> bool:
	if depth > 64:
		return false
	match typeof(value):
		TYPE_BOOL, TYPE_STRING, TYPE_INT:
			return true
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_VECTOR2:
			return value.is_finite()
		TYPE_VECTOR3:
			return value.is_finite()
		TYPE_COLOR:
			return is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a)
		TYPE_ARRAY:
			for item in value:
				if not _valid_codec_value(item, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			for key in value:
				if not (key is String or key is int) or not _valid_codec_value(key, depth + 1) or not _valid_codec_value(value[key], depth + 1):
					return false
			return true
	return false

static func _finite_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _valid_element(element: Variant) -> bool:
	return element is String and ["earth", "water", "fire", "air"].has(element)

static func _valid_slot(slot: Variant) -> bool:
	return slot is String and ["basic_shot", "curve_shot", "quick_fire", "shove", "high_jump", "down_dash", "wall", "h_dash", "recovery"].has(slot)

static func _valid_projectile_slot(slot: Variant) -> bool:
	return ["basic_shot", "curve_shot", "quick_fire"].has(slot)
