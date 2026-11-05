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
	file.store_string(JSON.stringify({"version": 1, "tape": encoded}, "", true, true))
	return file.get_error()

func load_file(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return ERR_PARSE_ERROR
	var envelope: Variant = json.data
	if not envelope is Dictionary or envelope.size() != 2 or envelope.get("version") != 1 or not envelope.has("tape"):
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
	if payload.final.tick != payload.initial.tick + payload.frames.size() or payload.initial.players.keys() != payload.final.players.keys():
		return false
	for frame in payload.frames:
		if not frame is Dictionary or frame.size() != 2 or not frame.has_all(["commands", "settings"]) or not frame.commands is Dictionary or not frame.settings is Dictionary:
			return false
		for id in frame.commands:
			if not id is int or not payload.initial.players.has(id) or not frame.commands[id] is Dictionary:
				return false
			var command := InputCmd.from_dict(frame.commands[id])
			if command == null or command.to_dict() != frame.commands[id]:
				return false
	return true

static func _valid_world(world: Variant) -> bool:
	if not world is Dictionary or world.size() != 3 or not world.has_all(["tick", "players", "events"]):
		return false
	if not world.tick is int or world.tick < 0 or not world.players is Dictionary or not world.events is Array:
		return false
	for id in world.players:
		if not id is int or not world.players[id] is Dictionary:
			return false
		var player: Dictionary = world.players[id]
		if player.size() != 13 or not player.has_all(["position", "velocity", "on_ground", "ground_angle", "yaw", "damage", "stocks", "hitstun", "invuln", "attack_time", "cooldown", "attack_hits", "spawn"]):
			return false
		for field in ["position", "velocity", "spawn"]:
			if not player[field] is Vector3 or not player[field].is_finite():
				return false
		for field in ["ground_angle", "yaw", "damage", "hitstun", "invuln", "attack_time", "cooldown"]:
			if not (player[field] is float or player[field] is int) or not is_finite(float(player[field])):
				return false
		if not player.on_ground is bool or not player.stocks is int or not player.attack_hits is Array:
			return false
		for hit in player.attack_hits:
			if not hit is int or not world.players.has(hit):
				return false
	for event in world.events:
		if not event is Dictionary or not event.get("type") is String or not event.get("player") is int or not world.players.has(event.player):
			return false
	return true
