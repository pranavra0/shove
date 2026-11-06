class_name GameHUD
extends CanvasLayer

# This layer is presentation only: consume is the sole event entry point.
class HUDCanvas extends Control:
	var hud: GameHUD

	func _draw() -> void:
		if is_instance_valid(hud):
			hud._draw_hud(self)

var debug_visible: bool = false
var _app: Node
var _canvas: HUDCanvas
var _font: Font
var _world: Dictionary = {}
var _ids: Array = []
var _local_id: int = 1
var _camera: Camera3D
var _layout_size := Vector2(1280.0, 800.0)
var _ui_scale: float = 1.0
var _last_tick: int = -1
var _consumed_tick: int = -1
var _consumed_events: Dictionary = {}
var _phase: String = ""
var _countdown: int = -1
var _speed: float = 0.0
var _result: String = ""
var _result_remaining: float = 0.0
var _result_persistent: bool = false
var _cooldown_total_cache: Dictionary = {}

const COOLDOWN_SLOTS: Array[String] = ["basic_shot", "curve_shot", "quick_fire", "shove", "high_jump", "down_dash", "wall", "h_dash", "recovery"]
const COOLDOWN_GLYPHS: Dictionary = {"basic_shot": "LMB", "curve_shot": "RMB", "quick_fire": "Q", "shove": "F", "high_jump": "E", "down_dash": "Ctrl", "wall": "R", "h_dash": "Shift", "recovery": "Space"}


func setup(app: Node) -> void:
	_app = app
	layer = 2
	debug_visible = Tuning.HUD_DEBUG_ENABLED
	if is_instance_valid(_canvas):
		return
	_font = ThemeDB.fallback_font
	_canvas = HUDCanvas.new()
	_canvas.name = "GameplayHUD"
	_canvas.hud = self
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)

func reset_match() -> void:
	_clear_round()
	_ids.clear()
	if is_instance_valid(_canvas):
		_canvas.queue_redraw()

func render_frame(world: Dictionary, flow: Dictionary, local_id: int, camera: Camera3D, delta: float) -> void:
	if not is_instance_valid(_canvas):
		return
	_world = world
	_local_id = local_id
	_camera = camera
	var elapsed: float = maxf(delta, 0.0)
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_ui_scale = maxf(0.1, minf(Tuning.HUD_SCALE_MAX, minf(viewport_size.x / Tuning.HUD_REFERENCE_SIZE.x, viewport_size.y / Tuning.HUD_REFERENCE_SIZE.y)))
	_layout_size = viewport_size / _ui_scale
	_canvas.scale = Vector2.ONE * _ui_scale
	_canvas.size = _layout_size
	var phase: String = str(flow.get("phase", "menu"))
	_canvas.visible = not world.is_empty() and phase != "menu" and phase != "setup"
	if not _canvas.visible:
		_clear_round()
		return
	var tick: int = int(world.get("tick", 0))
	if tick < _last_tick:
		_clear_round()
	_last_tick = tick
	_ids = world.get("players", {}).keys()
	_ids.sort()
	_speed = 0.0
	var players: Dictionary = world.get("players", {})
	if players.has(local_id):
		var local_player: Dictionary = players[local_id]
		if World.is_player_active(local_player):
			var velocity: Vector3 = local_player.get("velocity", Vector3.ZERO)
			_speed = Vector2(velocity.x, velocity.z).length()
	_result_remaining = maxf(0.0, _result_remaining - elapsed)
	_update_flow(phase, flow)
	_canvas.queue_redraw()

func consume(events: Array) -> void:
	var tick: int = _last_tick
	if is_instance_valid(_app):
		var current_world: Variant = _app.get("world")
		if current_world is Dictionary:
			tick = int(current_world.get("tick", tick))
	if tick < _consumed_tick:
		_clear_round()
	if tick != _consumed_tick:
		_consumed_tick = tick
		_consumed_events.clear()
	for value in events:
		if not value is Dictionary:
			continue
		var event: Dictionary = value
		var fingerprint: int = hash(event)
		if _consumed_events.has(fingerprint):
			continue
		_consumed_events[fingerprint] = true
		match str(event.get("type", "")):
			"ko":
				_result = "%s  K.O." % _player_name(int(event.get("player", -1)))
				_result_remaining = Tuning.HUD_KO_DURATION
				_result_persistent = false
			"wall_block":
				_result = "WALL BLOCK"
				_result_remaining = Tuning.HUD_BANNER_DURATION
				_result_persistent = false
			"deflect":
				_result = "PROJECTILE DEFLECTED"
				_result_remaining = Tuning.HUD_BANNER_DURATION
				_result_persistent = false

func _clear_round() -> void:
	_last_tick = -1
	_consumed_tick = -1
	_consumed_events.clear()
	_phase = ""
	_countdown = -1
	_speed = 0.0
	_result = ""
	_result_remaining = 0.0
	_result_persistent = false

func _update_flow(phase: String, flow: Dictionary) -> void:
	if phase == "countdown":
		var number: int = maxi(int(flow.get("countdown", 3)), 1)
		if number != _countdown or phase != _phase:
			_countdown = number
			_result = str(number)
			_result_remaining = Tuning.HUD_BANNER_DURATION
			_result_persistent = false
	elif phase != _phase:
		match phase:
			"playing":
				if _phase == "countdown":
					_result = "GO"
					_result_remaining = Tuning.HUD_BANNER_DURATION
					_result_persistent = false
			"round_end":
				_result = "ROUND OVER"
				_result_remaining = Tuning.HUD_BANNER_DURATION
				_result_persistent = false
			"winner":
				_result = ""
				_result_remaining = 0.0
				_result_persistent = false
	_phase = phase

func invalidate_tuning() -> void:
	_cooldown_total_cache.clear()

func _player_color(id: int) -> Color:
	var player: Dictionary = _world.get("players", {}).get(id, {})
	var color: Color = Kits.color(str(player.get("element", "earth")))
	var team: int = int(player.get("team", -1))
	if team >= 0:
		var colors: Array[Color] = Tuning.CP_TEAM_COLORS
		if team < colors.size():
			color = color.lerp(colors[team], 0.72)
	return color

func _cooldown_total(element: String, slot: String) -> float:
	if not _cooldown_total_cache.has(element):
		var totals: Dictionary = {}
		for move_slot: String in COOLDOWN_SLOTS:
			totals[move_slot] = float(Kits.move(element, move_slot).get("cooldown", 0.0))
		_cooldown_total_cache[element] = totals
	var cached: Dictionary = _cooldown_total_cache[element]
	return float(cached.get(slot, 0.0))

func _player_name(id: int) -> String:
	if id == _local_id:
		return "YOU"
	if _app.get("network") != null and _app.network.active and _app.network.members.has(id):
		return str(_app.network.members[id].name).left(12)
	var players: Dictionary = _world.get("players", {})
	if players.has(id):
		var label: String = str(players[id].get("name", ""))
		if not label.is_empty():
			return label.left(12)
	return "P%02d" % id

func _text(canvas: Control, position: Vector2, text: String, font_size: int, color: Color, centered: bool = false) -> void:
	var origin: Vector2 = position
	if centered:
		origin.x -= _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * 0.5
	canvas.draw_string(_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw_hud(canvas: Control) -> void:
	if _world.is_empty() or _ids.is_empty():
		return
	_draw_damage(canvas)
	if str(_world.get("mode", "ffa")) == "control":
		_draw_team_scores(canvas)
	_draw_speed(canvas)
	_draw_cooldowns(canvas)
	_draw_indicators(canvas)
	_draw_result(canvas)
	if debug_visible:
		_draw_debug(canvas)

func _draw_damage(canvas: Control) -> void:
	var count: int = mini(_ids.size(), 8)
	var gap: float = Tuning.HUD_PLAYER_GAP
	var width: float = minf(Tuning.HUD_PLAYER_WIDTH, (_layout_size.x - Tuning.HUD_MARGIN * 2.0 - gap * (count - 1)) / count)
	var row_width: float = width * count + gap * (count - 1)
	var origin_x: float = (_layout_size.x - row_width) * 0.5
	var top_height: float = Tuning.HUD_DAMAGE_SIZE + 7.0 + Tuning.HUD_STOCK_SIZE + 4.0
	var top_backing := Rect2(Vector2(origin_x - Tuning.HUD_TOP_BACKING_PAD, Tuning.HUD_MARGIN - Tuning.HUD_TOP_BACKING_PAD), Vector2(row_width + Tuning.HUD_TOP_BACKING_PAD * 2.0, top_height + Tuning.HUD_TOP_BACKING_PAD * 2.0))
	canvas.draw_rect(top_backing, Tuning.HUD_TOP_BACKING_COLOR)
	for index in range(count):
		var id: int = int(_ids[index])
		var player: Dictionary = _world.players[id]
		var stocks: int = int(player.get("stocks", 0))
		var damage: float = float(player.get("damage", 0.0))
		var heat: float = clampf(damage / Tuning.HUD_DAMAGE_HOT_PERCENT, 0.0, 1.0)
		var color: Color = Tuning.HUD_DAMAGE_STEPS[mini(int(heat * Tuning.HUD_DAMAGE_STEPS.size()), Tuning.HUD_DAMAGE_STEPS.size() - 1)]
		if not World.is_player_active(player):
			color = Tuning.HUD_MUTED
		var x: float = origin_x + index * (width + gap)
		_text(canvas, Vector2(x, Tuning.HUD_MARGIN + Tuning.HUD_DAMAGE_SIZE), "%d%%" % roundi(damage), Tuning.HUD_DAMAGE_SIZE, color)
		var stock_color: Color = color
		if str(_world.get("mode", "ffa")) == "control":
			stock_color = _player_color(id) if World.is_player_active(player) else Tuning.HUD_MUTED
		var square_size: float = Tuning.HUD_STOCK_SIZE
		var stock_gap: float = Tuning.HUD_STOCK_GAP
		for stock in range(stocks):
			var box := Rect2(Vector2(x + stock * (square_size + stock_gap), Tuning.HUD_MARGIN + Tuning.HUD_DAMAGE_SIZE + 7.0), Vector2(square_size, square_size))
			canvas.draw_rect(box, stock_color)
		var accent := Rect2(Vector2(x, Tuning.HUD_MARGIN + top_height - 2.0), Vector2(width, 2.0))
		canvas.draw_rect(accent, _player_color(id))

func _draw_team_scores(canvas: Control) -> void:
	var control: Dictionary = _world.get("control", {})
	var scores: Array = control.get("scores", [0.0, 0.0])
	var damage_row_height: float = Tuning.HUD_DAMAGE_SIZE + 7.0 + Tuning.HUD_STOCK_SIZE + 4.0
	var score_baseline: float = Tuning.HUD_MARGIN + damage_row_height + Tuning.HUD_TOP_BACKING_PAD * 2.0 + Tuning.HUD_RESULT_SIZE
	for team in range(2):
		var color: Color = _team_color(team)
		var score: float = float(scores[team]) if team < scores.size() else 0.0
		var label: String = "TEAM %d  %03d" % [team + 1, roundi(score)]
		var position: Vector2 = Vector2(Tuning.HUD_MARGIN, score_baseline)
		if team == 1:
			position.x = _layout_size.x - Tuning.HUD_MARGIN - _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, Tuning.HUD_RESULT_SIZE).x
		_text(canvas, position, label, Tuning.HUD_RESULT_SIZE, color)

func _team_color(team: int) -> Color:
	var colors: Array[Color] = Tuning.CP_TEAM_COLORS
	return colors[team] if team >= 0 and team < colors.size() else Tuning.HUD_TEXT

func _draw_speed(canvas: Control) -> void:
	var x: float = Tuning.HUD_MARGIN
	var y: float = _layout_size.y - Tuning.HUD_MARGIN
	_text(canvas, Vector2(x, y - Tuning.HUD_SPEED_FONT_SIZE - Tuning.HUD_SPEED_BAR_GAP), "%.1f" % _speed, Tuning.HUD_SPEED_FONT_SIZE, Tuning.HUD_TEXT)
	var bar := Rect2(Vector2(x, y - Tuning.HUD_SPEED_BAR_HEIGHT), Vector2(Tuning.HUD_SPEED_BAR_WIDTH, Tuning.HUD_SPEED_BAR_HEIGHT))
	canvas.draw_rect(bar, Color(Tuning.HUD_MUTED, 0.25))
	bar.size.x *= clampf(_speed / maxf(Tuning.HUD_SPEED_METER_MAX, 0.01), 0.0, 1.0)
	canvas.draw_rect(bar, Tuning.HUD_TEXT)

func _draw_cooldowns(canvas: Control) -> void:
	if not _world.players.has(_local_id):
		return
	var player: Dictionary = _world.players[_local_id]
	var slots: Dictionary = player.get("cooldowns", {})
	var element: String = str(player.get("element", "earth"))
	var bar_width: float = Tuning.HUD_COOLDOWN_WIDTH
	var gap: float = Tuning.HUD_COOLDOWN_GAP
	var total_width: float = bar_width * COOLDOWN_SLOTS.size() + gap * (COOLDOWN_SLOTS.size() - 1)
	var start_x: float = (_layout_size.x - total_width) * 0.5
	var bar_y: float = _layout_size.y - Tuning.HUD_COOLDOWN_BOTTOM_MARGIN - Tuning.HUD_COOLDOWN_HEIGHT
	var glyph_baseline: float = bar_y - Tuning.HUD_COOLDOWN_GLYPH_GAP
	var padding: float = Tuning.HUD_COOLDOWN_PADDING
	var font_size: int = Tuning.HUD_COOLDOWN_FONT_SIZE
	var backing := Rect2(
		Vector2(start_x - padding, glyph_baseline - font_size - padding),
		Vector2(total_width + padding * 2.0, font_size + Tuning.HUD_COOLDOWN_GLYPH_GAP + Tuning.HUD_COOLDOWN_HEIGHT + padding * 2.0)
	)
	canvas.draw_rect(backing, Tuning.HUD_COOLDOWN_BACKING_COLOR)
	for slot_index in range(COOLDOWN_SLOTS.size()):
		var slot: String = COOLDOWN_SLOTS[slot_index]
		var total: float = _cooldown_total(element, slot)
		var fallback: float = float(player.get("cooldown", 0.0)) if slot == "shove" else 0.0
		var remaining: float = float(slots.get(slot, fallback))
		var ratio: float = clampf(remaining / maxf(total, 0.001), 0.0, 1.0)
		var unavailable: bool = slot == "recovery" and not bool(player.get("on_ground", false)) and int(player.get("recovery_used", 0)) >= Kits.recovery_uses(element)
		var color: Color = Tuning.HUD_MUTED if unavailable else _player_color(_local_id)
		if unavailable:
			ratio = 1.0
		var x: float = start_x + slot_index * (bar_width + gap)
		var glyph: String = COOLDOWN_GLYPHS[slot]
		var glyph_width: float = _font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		_text(canvas, Vector2(x + (bar_width - glyph_width) * 0.5, glyph_baseline), glyph, font_size, color)
		var bar := Rect2(Vector2(x, bar_y), Vector2(bar_width, Tuning.HUD_COOLDOWN_HEIGHT))
		if ratio > 0.0:
			var fill: Rect2 = bar
			fill.size.x *= ratio
			canvas.draw_rect(fill, color)
		canvas.draw_rect(bar, color, false)

func _draw_indicators(canvas: Control) -> void:
	if not is_instance_valid(_camera):
		return
	var center: Vector2 = _layout_size * 0.5
	var margin: float = Tuning.HUD_INDICATOR_MARGIN
	var bounds := Rect2(Vector2(margin, margin + Tuning.HUD_PLAYER_TOP), Vector2(_layout_size.x - margin * 2.0, _layout_size.y - margin * 2.0 - Tuning.HUD_PLAYER_TOP - Tuning.HUD_BOTTOM_RESERVED))
	for id in _ids:
		if int(id) == _local_id:
			continue
		var player: Dictionary = _world.players[id]
		if not World.is_player_active(player):
			continue
		var position: Vector3 = player.get("position", Vector3.ZERO)
		var behind: bool = _camera.is_position_behind(position)
		var projected: Vector2 = _camera.unproject_position(position) / _ui_scale
		if not behind and Rect2(Vector2.ZERO, _layout_size).has_point(projected):
			continue
		var direction: Vector2 = projected - center
		if behind:
			var relative: Vector3 = _camera.global_transform.affine_inverse() * position
			direction = Vector2(relative.x, -relative.y)
		if direction.length_squared() < 0.001:
			direction = Vector2.DOWN
		direction = direction.normalized()
		var distance: float = INF
		if absf(direction.x) > 0.001:
			distance = minf(distance, ((bounds.end.x if direction.x > 0.0 else bounds.position.x) - center.x) / direction.x)
		if absf(direction.y) > 0.001:
			distance = minf(distance, ((bounds.end.y if direction.y > 0.0 else bounds.position.y) - center.y) / direction.y)
		var point: Vector2 = center + direction * maxf(0.0, distance)
		var tangent := Vector2(-direction.y, direction.x)
		var tip: Vector2 = point + direction * Tuning.HUD_INDICATOR_SIZE
		canvas.draw_colored_polygon(PackedVector2Array([tip, point + tangent * Tuning.HUD_INDICATOR_SIZE * 0.55, point - tangent * Tuning.HUD_INDICATOR_SIZE * 0.55]), _player_color(int(id)))

func _draw_result(canvas: Control) -> void:
	if str(_world.get("mode", "ffa")) == "control":
		return
	if _result.is_empty() or (_result_remaining <= 0.0 and not _result_persistent):
		return
	_text(canvas, Vector2(_layout_size.x * 0.5, _layout_size.y * Tuning.HUD_RESULT_Y), _result, Tuning.HUD_RESULT_SIZE, Tuning.HUD_TEXT, true)

func _draw_debug(canvas: Control) -> void:
	var player: Dictionary = _world.players.get(_local_id, {})
	var velocity: Vector3 = player.get("velocity", Vector3.ZERO)
	var text: String = "%s  |  TICK %d  |  %d FPS  |  %d PLAYERS" % [_phase.to_upper(), int(_world.get("tick", 0)), Engine.get_frames_per_second(), _ids.size()]
	_text(canvas, Vector2(Tuning.HUD_MARGIN, Tuning.HUD_MARGIN + Tuning.HUD_PLAYER_TOP + 24.0), text, Tuning.HUD_DEBUG_SIZE, Tuning.HUD_MUTED)
	_text(canvas, Vector2(Tuning.HUD_MARGIN, Tuning.HUD_MARGIN + Tuning.HUD_PLAYER_TOP + 43.0), "VEL %.2f / %.2f / %.2f   %s" % [velocity.x, velocity.y, velocity.z, "GROUND" if player.get("on_ground", false) else "AIR"], Tuning.HUD_DEBUG_SIZE, Tuning.HUD_MUTED)
