class_name Kits
extends RefCounted

const ELEMENTS: Array[String] = ["earth", "water", "fire", "air"]
const SLOTS: Array[String] = ["basic_shot", "curve_shot", "quick_fire", "shove", "high_jump", "down_dash", "wall", "h_dash", "recovery"]
const ELEMENT_COLORS: Dictionary = {
	"earth": Color("#b47742"), "water": Color("#429fc2"),
	"fire": Color("#db6540"), "air": Color("#b9d9ec"),
}

static func movement(element: String) -> Dictionary:
	var prefix: String = _prefix(element)
	return {"ground_speed": float(Tuning.get(prefix + "GROUND_SPEED")), "air_accel": float(Tuning.get(prefix + "AIR_ACCEL")), "jump": float(Tuning.get(prefix + "JUMP"))}

static func color(element: String) -> Color:
	return ELEMENT_COLORS[element if ELEMENTS.has(element) else "earth"]

static func recovery_uses(element: String) -> int:
	return int(Tuning.get(_prefix(element) + "RECOVERY_USES"))

static func definition(element: String) -> Dictionary:
	var e: String = element if ELEMENTS.has(element) else "earth"
	var result: Dictionary = movement(e)
	result.recovery_uses = recovery_uses(e)
	result.color = color(e)
	var moves: Dictionary = {}
	for slot in SLOTS:
		moves[slot] = move(e, slot)
	result.moves = moves
	return result

static func base_move(element: String, slot: String) -> Dictionary:
	var e: String = element if ELEMENTS.has(element) else "earth"
	var prefix: String = _prefix(e)
	var damage_factor: float = float(Tuning.get(prefix + "DAMAGE"))
	var kb_factor: float = float(Tuning.get(prefix + "KB_SCALE"))
	var kb_base_factor: float = float(Tuning.get(prefix + "KB_BASE"))
	var speed_factor: float = float(Tuning.get(prefix + "PROJECTILE_SPEED"))
	var size_factor: float = float(Tuning.get(prefix + "PROJECTILE_SIZE"))
	var result: Dictionary = {
		"cooldown": 0.7, "windup": 0.06, "active": 0.08, "duration": 1.8,
		"damage": 10.0 * damage_factor, "kb_base": 3.0 * kb_base_factor, "kb_scale": 0.12 * kb_factor,
		"momentum": 0.2, "preserve_momentum": float(Tuning.get(prefix + "DASH_MOMENTUM")),
		"iframe_time": 0.0, "hitstun": Tuning.PROJECTILE_HITSTUN,
		"deflect_speed_gain": Tuning.DEFLECT_SPEED_GAIN, "speed": 18.0 * speed_factor,
		"size": 0.24 * size_factor, "deflect_damage_gain": Tuning.DEFLECT_DAMAGE_GAIN,
		"max_speed": Tuning.DEFLECT_SPEED_CAP, "max_damage": Tuning.DEFLECT_DAMAGE_CAP,
		"kb_up": Tuning.PROJECTILE_KB_UP, "gravity": Tuning.PROJECTILE_GRAVITY,
		"homing": minf(Tuning.PROJECTILE_HOMING_MAX, float(Tuning.get(prefix + "HOMING"))),
		"curve_rate": Tuning.PROJECTILE_CURVE_ACCEL, "curve_drift": Tuning.PROJECTILE_CURVE_MAX,
		"pitch_threshold": Tuning.PROJECTILE_PITCH_THRESHOLD,
		"spike_damage_mult": Tuning.PROJECTILE_SPIKE_DAMAGE_MULT, "spike_kb_mult": Tuning.PROJECTILE_SPIKE_KB_MULT,
		"lob_damage_mult": Tuning.PROJECTILE_LOB_DAMAGE_MULT, "lob_kb_mult": Tuning.PROJECTILE_LOB_KB_MULT,
		"lob_speed_mult": Tuning.PROJECTILE_LOB_SPEED_MULT, "spike_dive_speed": Tuning.PROJECTILE_SPIKE_DIVE_SPEED,
		"spike_pop_speed": Tuning.PROJECTILE_SPIKE_POP_SPEED,
		"wall_width": Tuning.WALL_WIDTH * float(Tuning.get(prefix + "WALL_SIZE")),
		"wall_height": Tuning.WALL_HEIGHT * float(Tuning.get(prefix + "WALL_SIZE")), "wall_depth": Tuning.WALL_DEPTH,
		"wall_hp": Tuning.WALL_HP * float(Tuning.get(prefix + "WALL_HP")),
		"placement_distance": Tuning.WALL_PLACEMENT_DISTANCE, "wall_horizontal_threshold": Tuning.WALL_HORIZONTAL_THRESHOLD,
		"slam_radius": Tuning.SLAM_RADIUS,
		"recovery_up": Tuning.RECOVERY_UP_SPEED * float(Tuning.get(prefix + "RECOVERY_SPEED")),
		"recovery_horizontal": Tuning.RECOVERY_HORIZONTAL_SPEED * float(Tuning.get(prefix + "RECOVERY_SPEED")),
		"chain_window": Tuning.PROJECTILE_CHAIN_WINDOW, "chain_stun": Tuning.PROJECTILE_CHAIN_STUN * float(Tuning.get(prefix + "CHAIN_STUN")),
		"tags": ["projectile", "level"],
	}
	match slot:
		"basic_shot": pass
		"curve_shot": result.merge({"cooldown": 1.0, "speed": 15.0 * speed_factor, "tags": ["projectile", "curve"]}, true)
		"quick_fire": result.merge({"cooldown": 0.3 * float(Tuning.get(prefix + "QUICK_COOLDOWN")), "damage": 6.0 * damage_factor, "speed": 17.0 * speed_factor, "tags": ["projectile", "rapid"]}, true)
		"shove": result.merge({"cooldown": Tuning.SHOVE_COOLDOWN, "windup": Tuning.SHOVE_WINDUP, "active": Tuning.SHOVE_ACTIVE, "duration": Tuning.SHOVE_ACTIVE, "damage": Tuning.SHOVE_DAMAGE, "kb_base": Tuning.BASE_KB, "kb_scale": Tuning.KB_SCALE, "momentum": Tuning.MOMENTUM_TRANSFER, "hitstun": Tuning.HITSTUN, "kb_up": Tuning.KB_UP, "speed": 0.0, "size": Tuning.SHOVE_RADIUS, "reach": Tuning.SHOVE_REACH, "tags": ["melee", "deflect"]}, true)
		"high_jump": result.merge({"cooldown": 1.0, "active": 0.0, "duration": 0.0, "speed": Tuning.JUMP_SPEED * Tuning.JUMP_HIGH_SPEED * float(Tuning.get(prefix + "JUMP")), "tags": ["jump"]}, true)
		"down_dash": result.merge({"cooldown": 1.0, "active": Tuning.DASH_DOWN_DURATION, "duration": Tuning.DASH_DOWN_DURATION, "speed": Tuning.DASH_DOWN_SPEED * float(Tuning.get(prefix + "DASH_SPEED")), "damage": Tuning.SLAM_DAMAGE * float(Tuning.get(prefix + "SLAM_DAMAGE")), "kb_base": Tuning.SLAM_KB_BASE, "kb_scale": Tuning.SLAM_KB_SCALE * kb_factor, "hitstun": Tuning.SLAM_HITSTUN, "preserve_momentum": float(Tuning.get(prefix + "DASH_MOMENTUM")), "iframe_time": 0.0, "tags": ["dash", "slam"]}, true)
		"wall": result.merge({"cooldown": 2.5 * float(Tuning.get(prefix + "WALL_COOLDOWN")), "active": 0.08, "duration": Tuning.WALL_DURATION * float(Tuning.get(prefix + "WALL_DURATION")), "wall_hp": Tuning.WALL_HP * float(Tuning.get(prefix + "WALL_HP")), "tags": ["wall"]}, true)
		"h_dash": result.merge({"cooldown": 0.8, "active": Tuning.DASH_HORIZONTAL_DURATION, "duration": Tuning.DASH_HORIZONTAL_DURATION, "speed": Tuning.DASH_HORIZONTAL_SPEED * float(Tuning.get(prefix + "DASH_SPEED")), "iframe_time": Tuning.DASH_IFRAME_TIME, "tags": ["dash", "horizontal"]}, true)
		"recovery": result.merge({"cooldown": 0.0, "active": 0.0, "duration": 0.0, "speed": Tuning.RECOVERY_UP_SPEED * float(Tuning.get(prefix + "RECOVERY_SPEED")), "tags": ["recovery"]}, true)
	return result

static func move(element: String, slot: String) -> Dictionary:
	var result := base_move(element, slot)
	var overrides: Dictionary = Tuning.KIT_OVERRIDES
	var element_overrides: Variant = overrides.get(element, {})
	if element_overrides is Dictionary:
		var slot_overrides: Variant = element_overrides.get(slot, {})
		if slot_overrides is Dictionary:
			result.merge(slot_overrides, true)
	return result

static func move_fields(slot: String) -> Array[String]:
	var schema: Dictionary = {
		"basic_shot": ["cooldown", "windup", "active", "duration", "damage", "kb_base", "kb_scale", "momentum", "hitstun", "speed", "size", "kb_up", "homing", "chain_window", "chain_stun"],
		"curve_shot": ["cooldown", "windup", "active", "duration", "damage", "kb_base", "kb_scale", "momentum", "hitstun", "speed", "size", "kb_up", "gravity", "homing", "curve_rate", "curve_drift", "pitch_threshold", "spike_damage_mult", "spike_kb_mult", "lob_damage_mult", "lob_kb_mult", "lob_speed_mult", "spike_dive_speed", "spike_pop_speed", "slam_radius", "chain_window", "chain_stun"],
		"quick_fire": ["cooldown", "windup", "active", "duration", "damage", "kb_base", "kb_scale", "momentum", "hitstun", "speed", "size", "kb_up", "homing", "chain_window", "chain_stun"],
		"shove": ["cooldown", "windup", "active", "damage", "kb_base", "kb_scale", "momentum", "hitstun", "kb_up", "size", "reach", "deflect_speed_gain", "deflect_damage_gain", "max_speed", "max_damage"],
		"high_jump": ["cooldown", "windup", "active", "speed", "iframe_time"],
		"down_dash": ["cooldown", "windup", "active", "speed", "damage", "kb_base", "kb_scale", "momentum", "hitstun", "kb_up", "iframe_time", "slam_radius", "chain_window", "chain_stun"],
		"wall": ["cooldown", "windup", "active", "duration", "wall_hp", "wall_width", "wall_height", "wall_depth", "placement_distance", "wall_horizontal_threshold"],
		"h_dash": ["cooldown", "windup", "active", "speed", "preserve_momentum", "iframe_time"],
		"recovery": ["cooldown", "windup", "active", "recovery_up", "recovery_horizontal", "iframe_time"],
	}
	var fields: Array[String] = []
	for field in schema.get(slot, []):
		fields.append(field)
	return fields

static func _prefix(element: String) -> String:
	var e: String = element if ELEMENTS.has(element) else "earth"
	return e.to_upper() + "_"
