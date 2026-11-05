class_name InputCmd
extends RefCounted

var move: Vector2 = Vector2.ZERO
var jump: bool = false
var shove: bool = false
var yaw: float = 0.0
var tick: int = 0

func _init(p_move: Vector2 = Vector2.ZERO, p_jump: bool = false, p_shove: bool = false, p_yaw: float = 0.0, p_tick: int = 0) -> void:
	move = p_move
	jump = p_jump
	shove = p_shove
	yaw = p_yaw
	tick = p_tick

func to_dict() -> Dictionary:
	return {"move": [move.x, move.y], "jump": jump, "shove": shove, "yaw": yaw, "tick": tick}

static func from_dict(data: Dictionary) -> InputCmd:
	if data.size() != 5 or not data.has_all(["move", "jump", "shove", "yaw", "tick"]):
		return null
	if not data.move is Array or data.move.size() != 2 or not data.jump is bool or not data.shove is bool:
		return null
	for number in [data.move[0], data.move[1], data.yaw]:
		if not (number is float or number is int) or not is_finite(float(number)):
			return null
	var tick_value: int
	if data.tick is String and data.tick.is_valid_int() and str(int(data.tick)) == data.tick:
		tick_value = int(data.tick)
	elif data.tick is int:
		tick_value = data.tick
	elif data.tick is float and is_finite(data.tick) and data.tick == floor(data.tick) and absf(data.tick) <= 9007199254740991.0:
		tick_value = int(data.tick)
	else:
		return null
	var direction := Vector2(float(data.move[0]), float(data.move[1]))
	if not direction.is_finite():
		return null
	# Preserve float32 unit-vector roundoff; MovementSim independently caps wish length.
	if direction.length_squared() > 1.000001:
		direction = direction.normalized()
	return InputCmd.new(direction, data.jump, data.shove, float(data.yaw), tick_value)
