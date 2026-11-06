class_name InputCmd
extends RefCounted

const BASIC_SHOT: int = 1
const CURVE_SHOT: int = 2
const QUICK_FIRE: int = 4
const HIGH_JUMP: int = 8
const DOWN_DASH: int = 16
const WALL: int = 32
const H_DASH: int = 64
const RECOVERY: int = 128
const HELD_MOVES: int = BASIC_SHOT | QUICK_FIRE

var move: Vector2 = Vector2.ZERO
var jump: bool = false
var shove: bool = false
var yaw: float = 0.0
var tick: int = 0
var pitch: float = 0.0
var moves: int = 0

func _init(p_move: Vector2 = Vector2.ZERO, p_jump: bool = false, p_shove: bool = false, p_yaw: float = 0.0, p_tick: int = 0) -> void:
	move = p_move
	jump = p_jump
	shove = p_shove
	yaw = p_yaw
	tick = p_tick

func to_dict() -> Dictionary:
	return {"move": [move.x, move.y], "jump": jump, "shove": shove, "yaw": yaw, "tick": tick, "pitch": pitch, "moves": moves}

static func from_dict(data: Dictionary) -> InputCmd:
	if data.size() != 7 or not data.has_all(["move", "jump", "shove", "yaw", "tick", "pitch", "moves"]):
		return null
	if not data.move is Array or data.move.size() != 2 or not data.jump is bool or not data.shove is bool:
		return null
	if not data.moves is int or data.moves < 0 or data.moves > 255 or not data.tick is int:
		return null
	if not _finite_number(data.move[0]) or not _finite_number(data.move[1]) or not _finite_number(data.yaw) or not _finite_number(data.pitch):
		return null
	if absf(float(data.move[0])) > 1.0 or absf(float(data.move[1])) > 1.0:
		return null
	if absf(float(data.yaw)) > 1000000.0 or float(data.pitch) < -PI / 2.0 or float(data.pitch) > PI / 2.0:
		return null
	if data.tick < 0 or data.tick > 9007199254740991:
		return null
	var direction := Vector2(float(data.move[0]), float(data.move[1]))
	if direction.length_squared() > 1.000001:
		return null
	var cmd := InputCmd.new(direction, data.jump, data.shove, float(data.yaw), data.tick)
	cmd.pitch = float(data.pitch)
	cmd.moves = data.moves
	return cmd

static func _finite_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))
