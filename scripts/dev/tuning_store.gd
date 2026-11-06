class_name TuningStore
extends RefCounted

const SOURCE = preload("res://scripts/tuning.gd")
static var _field_names: Array[String] = []
static var _factory_defaults: Dictionary = {}

static func fields() -> Array[String]:
	if _field_names.is_empty():
		var script: Script = SOURCE
		for property in script.get_script_property_list():
			var name: String = property.name
			if name == name.to_upper() and name != "MAX_GROUND_ANGLE" and property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				_field_names.append(name)
	return _field_names.duplicate()

static func defaults() -> Dictionary:
	if _factory_defaults.is_empty():
		var factory: Node = SOURCE.new()
		for name in fields():
			_factory_defaults[name] = factory.get(name)
		factory.free()
	return _factory_defaults.duplicate(true)

static func snapshot() -> Dictionary:
	var result: Dictionary = {}
	for name in fields():
		result[name] = Tuning.get(name)
	return result.duplicate(true)

# Bounds are inferred from factory types/scale; exceptions describe domain invariants,
# not a second set of gameplay defaults. The same constraints guard files and UI.
static func bounds(name: String, value: Variant) -> Vector2:
	var magnitude: float = absf(float(value))
	var high: float = maxf(1.0, magnitude * 8.0)
	var low: float = 0.0
	if name == "DEV_TRAJECTORY_SECONDS":
		return Vector2(1.0 / 64.0, 2.0)
	if name == "DEV_TRAJECTORY_STEPS":
		return Vector2(2.0, 128.0)
	if name == "WALL_HORIZONTAL_THRESHOLD":
		return Vector2(-1.0, 0.0)
	if name == "NET_PORT":
		return Vector2(1.0, 65535.0)
	if name == "NET_MAX_PLAYERS":
		return Vector2(2.0, 8.0)
	if name == "NET_SNAPSHOT_RATE":
		return Vector2(1.0, 64.0)
	if name == "NET_LATENCY_MS":
		return Vector2(0.0, 2000.0)
	if name == "NET_JITTER_MS":
		return Vector2(0.0, 1000.0)
	if name == "NET_PACKET_LOSS":
		return Vector2(0.0, 1.0)
	if name == "NET_INPUT_REDUNDANCY":
		return Vector2(1.0, 64.0)
	if name == "NET_MAX_PENDING":
		return Vector2(1.0, 512.0)
	if name == "NET_CONNECT_TIMEOUT":
		return Vector2(0.1, 60.0)
	if name.contains("PITCH") or name.contains("YAW") or name == "KILL_PLANE":
		low = -maxf(high, 180.0)
	if name.contains("VOLUME") or name.contains("SKILL") or name.contains("CONTROL") or name.ends_with("_DENSITY"):
		high = 1.0
	if name == "MAX_GROUND_ANGLE_DEGREES":
		return Vector2(0.0, 89.0)
	if name == "CAMERA_FOV":
		return Vector2(1.0, 179.0)
	if name.contains("COUNT") or name.contains("MAX_PARTICLES") or name.contains("MAX_TRAIL") or name.contains("MAX_RINGS") or name.contains("MAX_POPUPS"):
		high = minf(high, 4096.0)
	if name == "AUDIO_SAMPLE_RATE":
		return Vector2(8000.0, 96000.0)
	if name == "AUDIO_VOICES":
		return Vector2(1.0, 128.0)
	if name.ends_with("_SIZE") or name.ends_with("_WIDTH") or name.ends_with("_HEIGHT") or name.ends_with("_LENGTH") or name.ends_with("_RADIUS") or name.ends_with("_THICKNESS") or name.ends_with("_DURATION") or name.ends_with("_INTERVAL") or name.ends_with("_DISTANCE") or name.ends_with("_REFERENCE") or name.ends_with("_RANGE") or name.ends_with("_BPM") or name.ends_with("_SEGMENTS") or name == "STOCKS" or name == "CAMERA_FAR" or name.ends_with("_METER_MAX"):
		low = 1.0 if typeof(value) == TYPE_INT else 0.0001
	if name.ends_with("_SEGMENTS"):
		low = 3.0
	return Vector2(low, high)

static func kit_bounds(element: String, slot: String, field: String) -> Vector2:
	if not Kits.ELEMENTS.has(element) or not Kits.SLOTS.has(slot) or not Kits.move_fields(slot).has(field):
		return Vector2(0.0, 0.0)
	# Kit ranges describe the editor/preset domain, not the live scalar-derived
	# move. A preset therefore remains valid after unrelated tuning changes.
	if field in ["wall_horizontal_threshold", "pitch_threshold"]:
		return Vector2(-1.0, 1.0)
	if field == "wall_hp":
		return Vector2(1.0, 10000.0)
	if field in ["size", "reach", "wall_width", "wall_height", "wall_depth", "slam_radius"]:
		return Vector2(0.0001, 1000.0)
	if field == "duration":
		return Vector2(0.0001, 60.0) if slot in ["basic_shot", "curve_shot", "quick_fire", "wall"] else Vector2(0.0, 60.0)
	if field in ["cooldown", "windup", "active", "iframe_time", "hitstun", "chain_window", "chain_stun"]:
		return Vector2(0.0, 60.0)
	if field in ["damage", "kb_base", "kb_scale", "momentum", "speed", "kb_up", "gravity", "curve_rate", "curve_drift", "spike_damage_mult", "spike_kb_mult", "lob_damage_mult", "lob_kb_mult", "lob_speed_mult", "spike_dive_speed", "spike_pop_speed", "placement_distance", "recovery_up", "recovery_horizontal"]:
		return Vector2(0.0, 1000.0)
	if field in ["homing", "preserve_momentum"]:
		return Vector2(0.0, 1.0)
	return Vector2(0.0, 1000.0)

static func _typed_kit_number(value: Variant) -> Variant:
	if value is Dictionary:
		if value.get("type") != "float":
			return null
		var hex: Variant = value.get("value")
		if not hex is String or hex.length() != 16 or not hex.is_valid_hex_number(false):
			return null
		value = hex.hex_decode().decode_double(0)
	return float(value) if _finite_number(value) else null

static func _typed_kit_overrides(value: Variant) -> Variant:
	if not value is Dictionary:
		return null
	var result: Dictionary = {}
	for element in value:
		if typeof(element) != TYPE_STRING or not Kits.ELEMENTS.has(element) or not value[element] is Dictionary:
			return null
		var slots: Dictionary = {}
		for slot in value[element]:
			if typeof(slot) != TYPE_STRING or not Kits.SLOTS.has(slot) or not value[element][slot] is Dictionary:
				return null
			var fields: Dictionary = {}
			for field in value[element][slot]:
				if typeof(field) != TYPE_STRING or not Kits.move_fields(slot).has(field):
					return null
				var decoded: Variant = _typed_kit_number(value[element][slot][field])
				if decoded == null:
					return null
				var limits := kit_bounds(element, slot, field)
				var number: float = float(decoded)
				if number < limits.x or number > limits.y or (field == "wall_hp" and number != floorf(number)):
					return null
				fields[field] = number
			if not fields.is_empty():
				slots[slot] = fields
		if not slots.is_empty():
			result[element] = slots
	return result

static func encode(values: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for name in values:
		result[name] = _encode_value(values[name])
	return result

static func _encode_value(value: Variant) -> Variant:
	if value is float:
		var bytes := PackedByteArray()
		bytes.resize(8)
		bytes.encode_double(0, value)
		return {"type": "float", "value": bytes.hex_encode()}
	if value is Color:
		return {"type": "Color", "value": [value.r, value.g, value.b, value.a]}
	if value is Vector2:
		return {"type": "Vector2", "value": [value.x, value.y]}
	if value is Vector3:
		return {"type": "Vector3", "value": [value.x, value.y, value.z]}
	if value is Dictionary:
		var entries: Dictionary = {}
		for key in value:
			entries[key] = _encode_value(value[key])
		return entries
	if value is Array:
		var items: Array = []
		for item in value:
			items.append(_encode_value(item))
		return {"type": "Array[Color]", "value": items}
	return value

static func _finite_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))

static func _typed_value(value: Variant, factory: Variant) -> Variant:
	match typeof(factory):
		TYPE_BOOL:
			return value if typeof(value) == TYPE_BOOL else null
		TYPE_INT, TYPE_FLOAT:
			if typeof(factory) == TYPE_FLOAT and value is Dictionary and value.get("type") == "float":
				var hex: Variant = value.get("value")
				if not hex is String or hex.length() != 16 or not hex.is_valid_hex_number(false):
					return null
				value = hex.hex_decode().decode_double(0)
			if not _finite_number(value):
				return null
			if typeof(factory) == TYPE_INT:
				return int(value) if float(value) == floorf(float(value)) and absf(float(value)) < 2147483647.0 else null
			return float(value)
		TYPE_COLOR, TYPE_VECTOR2, TYPE_VECTOR3:
			var tag: String = {TYPE_COLOR: "Color", TYPE_VECTOR2: "Vector2", TYPE_VECTOR3: "Vector3"}[typeof(factory)]
			var count: int = 4 if factory is Color else (2 if factory is Vector2 else 3)
			if not value is Dictionary or value.get("type") != tag or not value.get("value") is Array or value.value.size() != count:
				return null
			for component in value.value:
				if not _finite_number(component) or absf(float(component)) > 1000000.0:
					return null
			var v: Array = value.value
			if factory is Color:
				return Color(v[0], v[1], v[2], v[3])
			if factory is Vector2:
				return Vector2(v[0], v[1])
			return Vector3(v[0], v[1], v[2])
		TYPE_ARRAY:
			if not value is Dictionary or value.get("type") != "Array[Color]" or not value.get("value") is Array or value.value.is_empty() or value.value.size() > 64:
				return null
			var colors: Array[Color] = []
			for item in value.value:
				var color: Variant = _typed_value(item, Color.WHITE)
				if color == null:
					return null
				colors.append(color)
			return colors
	return null

static func decode(values: Dictionary) -> Dictionary:
	var factory := defaults()
	var result: Dictionary = {}
	for name in values:
		if not factory.has(name):
			push_warning("Unknown tuning field: %s" % str(name))
			return {}
		var value: Variant
		if name == "KIT_OVERRIDES":
			value = _typed_kit_overrides(values[name])
		else:
			value = _typed_value(values[name], factory[name])
		if value == null:
			push_warning("Invalid tuning type: %s" % name)
			return {}
		if name != "KIT_OVERRIDES" and (value is float or value is int):
			var limits := bounds(name, factory[name])
			if float(value) < limits.x or float(value) > limits.y:
				push_warning("Unsafe tuning value: %s" % name)
				return {}
		if name == "HUD_REFERENCE_SIZE" and (value.x <= 0.0 or value.y <= 0.0):
			push_warning("HUD reference size must be positive")
			return {}
		result[name] = value
	var merged := snapshot()
	merged.merge(result, true)
	if merged.CAMERA_MIN_PITCH > merged.CAMERA_MAX_PITCH or merged.AUDIO_HIT_MIN_PITCH <= 0.0 or merged.AUDIO_HIT_MIN_PITCH > merged.AUDIO_HIT_MAX_PITCH or merged.AUDIO_WIND_START_SPEED >= merged.AUDIO_WIND_FULL_SPEED or merged.JUICE_SPEED_LINES_THRESHOLD >= merged.JUICE_SPEED_LINES_FULL_SPEED:
		push_warning("Invalid tuning range")
		return {}
	return result

static func apply(values: Dictionary) -> void:
	var valid := decode(encode(values))
	for name in valid:
		Tuning.set(name, valid[name])

static func save(path: String, values: Dictionary) -> Error:
	var encoded := encode(values)
	if not values.is_empty() and decode(encoded).is_empty():
		return ERR_INVALID_DATA
	var error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error != OK:
		return error
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(encoded, "\t", true, true))
	return file.get_error()

static func load_values(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Cannot open tuning preset: %s" % path)
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		push_warning("Invalid tuning JSON: %s" % path)
		return {}
	return decode(parser.data)
