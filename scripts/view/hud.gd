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
var _panel: StyleBoxFlat
var _local_panel: StyleBoxFlat
var _world: Dictionary = {}
var _ids: Array = []
var _local_id: int = 1
var _camera: Camera3D
var _layout_size := Vector2(1280.0, 800.0)
var _ui_scale: float = 1.0
var _time: float = 0.0
var _last_tick: int = -1
var _consumed_tick: int = -1
var _consumed_events: Dictionary = {}
var _phase: String = ""
var _countdown: int = -1
var _hit: Dictionary = {}
var _stock_pop: Dictionary = {}
var _damage: Dictionary = {}
var _stocks: Dictionary = {}
var _motion: Dictionary = {}
var _speed: float = 0.0
var _banner: String = ""
var _banner_sub: String = ""
var _banner_color := Color.WHITE
var _banner_remaining: float = 0.0
var _banner_duration: float = 1.0
var _banner_persistent: bool = false

func setup(app: Node) -> void:
	_app = app
	layer = 2
	debug_visible = Tuning.HUD_DEBUG_ENABLED
	if is_instance_valid(_canvas):
		return
	_font = ThemeDB.fallback_font
	_panel = _make_panel(Tuning.HUD_PANEL_BORDER)
	_local_panel = _make_panel(Tuning.HUD_CYAN)
	_canvas = HUDCanvas.new()
	_canvas.name = "GameplayHUD"
	_canvas.hud = self
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)

func _make_panel(border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Tuning.HUD_PANEL
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(Tuning.HUD_PANEL_CORNER_RADIUS)
	return style

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
	_time += maxf(delta, 0.0)
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
	for id in _ids:
		var player: Dictionary = world.players[id]
		var damage: float = float(player.get("damage", 0.0))
		var stocks: int = int(player.get("stocks", 0))
		if _damage.has(id) and damage > float(_damage[id]):
			_hit[id] = Tuning.HUD_HIT_DURATION
		if _stocks.has(id) and stocks < int(_stocks[id]):
			_stock_pop[id] = Tuning.HUD_STOCK_POP_DURATION
		_damage[id] = damage
		_stocks[id] = stocks
		_hit[id] = maxf(0.0, float(_hit.get(id, 0.0)) - delta)
		_stock_pop[id] = maxf(0.0, float(_stock_pop.get(id, 0.0)) - delta)
		var motion: Dictionary = _motion.get(id, {})
		if bool(player.get("on_ground", false)) and motion.has("land_tick"):
			if float(tick - int(motion.land_tick)) * Tuning.FIXED_DELTA > Tuning.HUD_CHAIN_WINDOW:
				motion.chain = 0
				_motion[id] = motion
	if world.players.has(local_id):
		var velocity: Vector3 = world.players[local_id].get("velocity", Vector3.ZERO)
		var actual_speed: float = Vector2(velocity.x, velocity.z).length()
		_speed = lerpf(_speed, actual_speed, 1.0 - exp(-Tuning.HUD_SPEED_SMOOTHING * delta))
	else:
		_speed = 0.0
	_banner_remaining = maxf(0.0, _banner_remaining - delta)
	_update_flow(phase, flow)
	_canvas.queue_redraw()

func consume(events: Array) -> void:
	# Main dispatches after World.step; tick time remains correct during hitstop,
	# slow motion, or several simulation steps between rendered frames.
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
		var id: int = int(event.get("player", -1))
		var motion: Dictionary = _motion.get(id, {"chain": 0})
		match str(event.get("type", "")):
			"hit":
				_hit[id] = Tuning.HUD_HIT_DURATION
			"ko":
				_stock_pop[id] = Tuning.HUD_STOCK_POP_DURATION
				motion.chain = 0
				motion.erase("land_tick")
				_announce("K.O.", "%s  /  RING OUT" % _player_name(id), Tuning.HUD_CORAL, Tuning.HUD_KO_DURATION)
			"land":
				motion.land_tick = tick
			"jump":
				var linked: bool = motion.has("land_tick") and float(tick - int(motion.land_tick)) * Tuning.FIXED_DELTA <= Tuning.HUD_CHAIN_WINDOW
				motion.chain = int(motion.get("chain", 0)) + 1 if linked else 1
				motion.erase("land_tick")
		_motion[id] = motion

func _clear_round() -> void:
	_last_tick = -1
	_consumed_tick = -1
	_consumed_events.clear()
	_phase = ""
	_countdown = -1
	_hit.clear()
	_stock_pop.clear()
	_damage.clear()
	_stocks.clear()
	_motion.clear()
	_speed = 0.0
	_banner_remaining = 0.0
	_banner_persistent = false

func _update_flow(phase: String, flow: Dictionary) -> void:
	if phase == "countdown":
		var number: int = int(flow.get("countdown", 3))
		if number != _countdown or phase != _phase:
			_countdown = number
			_announce(str(maxi(number, 1)), "GET READY  /  BUILD MOMENTUM", Tuning.HUD_TEXT, Tuning.HUD_BANNER_DURATION)
	elif phase != _phase:
		match phase:
			"playing":
				if _phase == "countdown":
					_announce("GO!", "MOMENTUM IS A WEAPON", Tuning.HUD_CYAN, Tuning.HUD_BANNER_DURATION)
			"round_end":
				_announce("ROUND OVER", "LAST SHOVE. LAST STANDING.", Tuning.HUD_TEXT, Tuning.HUD_BANNER_DURATION)
			"winner":
				var winner: int = int(flow.get("winner", -1))
				_announce("VICTORY" if winner == _local_id else ("WINNER" if winner != -1 else "DRAW"), ("YOU TAKE THE ARENA" if winner == _local_id else "%s TAKES THE ARENA" % _player_name(winner)) if winner != -1 else "NO ONE LEFT STANDING", _player_color(winner) if winner != -1 else Tuning.HUD_TEXT, Tuning.HUD_BANNER_DURATION)
				_banner_persistent = true
	_phase = phase

func _announce(title: String, subtitle: String, color: Color, duration: float) -> void:
	_banner = title
	_banner_sub = subtitle
	_banner_color = color
	_banner_duration = maxf(duration, 0.001)
	_banner_remaining = duration
	_banner_persistent = false

func _player_color(id: int) -> Color:
	if _app.get("network") != null and _app.network.active and _app.network.members.has(id):
		return Tuning.HUD_PLAYER_COLORS[posmod(int(_app.network.members[id].color), Tuning.HUD_PLAYER_COLORS.size())]
	return Tuning.HUD_PLAYER_COLORS[posmod(id - 1, Tuning.HUD_PLAYER_COLORS.size())]

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
	_draw_hint(canvas)
	_draw_cards(canvas)
	_draw_motion(canvas)
	_draw_indicators(canvas)
	_draw_banner(canvas)
	if debug_visible:
		_draw_debug(canvas)

func _draw_hint(canvas: Control) -> void:
	var width: float = minf(Tuning.HUD_HINT_WIDTH, _layout_size.x - Tuning.HUD_MARGIN * 2.0)
	var rect := Rect2(Vector2((_layout_size.x - width) * 0.5, Tuning.HUD_MARGIN), Vector2(width, Tuning.HUD_HINT_HEIGHT))
	canvas.draw_style_box(_panel, rect)
	var hint: String = "WASD  MOVE     SPACE  HOP     E / LMB  SHOVE     F1  TUNING     ESC  PAUSE"
	if _phase == "countdown":
		hint = "KEEP YOUR SPEED  /  SHOVE RIVALS OFF THE ISLAND"
	_text(canvas, Vector2(_layout_size.x * 0.5, rect.position.y + Tuning.HUD_HINT_HEIGHT * 0.67), hint, Tuning.HUD_HINT_SIZE, Tuning.HUD_MUTED, true)

func _draw_cards(canvas: Control) -> void:
	var count: int = mini(_ids.size(), 8)
	var gap: float = Tuning.HUD_CARD_GAP
	var width: float = minf(Tuning.HUD_CARD_WIDTH, (_layout_size.x - Tuning.HUD_MARGIN * 2.0 - gap * (count - 1)) / count)
	var row_width: float = width * count + gap * (count - 1)
	var origin := Vector2((_layout_size.x - row_width) * 0.5, _layout_size.y - Tuning.HUD_MARGIN - Tuning.HUD_CARD_HEIGHT)
	for index in range(count):
		var id: int = int(_ids[index])
		var player: Dictionary = _world.players[id]
		var stocks: int = int(player.get("stocks", 0))
		var damage: float = float(player.get("damage", 0.0))
		var hit: float = clampf(float(_hit.get(id, 0.0)) / maxf(Tuning.HUD_HIT_DURATION, 0.001), 0.0, 1.0)
		var shake := Vector2(sin(_time * Tuning.HUD_HIT_FREQUENCY.x + id), cos(_time * Tuning.HUD_HIT_FREQUENCY.y + id)) * Tuning.HUD_HIT_SHAKE * hit
		var rect := Rect2(origin + Vector2(index * (width + gap), 0.0) + shake, Vector2(width, Tuning.HUD_CARD_HEIGHT))
		var color: Color = _player_color(id)
		if stocks <= 0:
			color = Tuning.HUD_MUTED
		canvas.draw_style_box(_local_panel if id == _local_id and stocks > 0 else _panel, rect)
		canvas.draw_rect(Rect2(rect.position + Vector2(8.0, 0.0), Vector2(width - 16.0, 3.0)), color)
		_text(canvas, rect.position + Vector2(12.0, 23.0), _player_name(id), Tuning.HUD_CARD_NAME_SIZE, color)
		var heat: float = clampf(damage / maxf(Tuning.HUD_DAMAGE_HOT_PERCENT, 1.0), 0.0, 1.0)
		var percent_color: Color = Tuning.HUD_TEXT.lerp(Tuning.HUD_DAMAGE_WARM, heat * 2.0) if heat < 0.5 else Tuning.HUD_DAMAGE_WARM.lerp(Tuning.HUD_DAMAGE_HOT, heat * 2.0 - 1.0)
		percent_color = percent_color.lerp(Color.WHITE, hit * 0.65)
		var number: String = "%d%%" % roundi(damage) if stocks > 0 else "OUT"
		_text(canvas, rect.position + Vector2(12.0, 65.0), number, Tuning.HUD_DAMAGE_SIZE + roundi(hit * Tuning.HUD_HIT_PERCENT_POP), percent_color if stocks > 0 else Tuning.HUD_MUTED)
		_draw_stocks(canvas, rect, stocks, color, float(_stock_pop.get(id, 0.0)))

func _draw_stocks(canvas: Control, rect: Rect2, stocks: int, color: Color, pop_remaining: float) -> void:
	var radius: float = Tuning.HUD_STOCK_RADIUS
	var total: int = maxi(Tuning.STOCKS, stocks)
	var spacing: float = minf(radius * 3.4, (rect.size.x - 28.0) / maxf(float(total), 1.0))
	var origin: Vector2 = rect.position + Vector2(15.0, rect.size.y - 16.0)
	for index in range(total):
		var position: Vector2 = origin + Vector2(index * spacing, 0.0)
		canvas.draw_circle(position, radius, color if index < stocks else Color(Tuning.HUD_MUTED, 0.22))
	if pop_remaining <= 0.0:
		return
	var progress: float = 1.0 - clampf(pop_remaining / maxf(Tuning.HUD_STOCK_POP_DURATION, 0.001), 0.0, 1.0)
	var center: Vector2 = origin + Vector2(stocks * spacing, -progress * Tuning.HUD_STOCK_POP_RISE)
	var pop_color := Color(Tuning.HUD_CORAL, 1.0 - progress)
	canvas.draw_arc(center, radius + progress * Tuning.HUD_STOCK_POP_EXPAND, 0.0, TAU, 24, pop_color, 2.0, true)
	canvas.draw_line(center + Vector2(-4.0, -4.0), center + Vector2(4.0, 4.0), pop_color, 2.0, true)
	canvas.draw_line(center + Vector2(-4.0, 4.0), center + Vector2(4.0, -4.0), pop_color, 2.0, true)

func _draw_motion(canvas: Control) -> void:
	if not _world.players.has(_local_id):
		return
	var rect := Rect2(Vector2(Tuning.HUD_MARGIN, _layout_size.y - Tuning.HUD_MARGIN - Tuning.HUD_CARD_HEIGHT - Tuning.HUD_CARD_GAP - Tuning.HUD_MOTION_HEIGHT), Vector2(Tuning.HUD_MOTION_WIDTH, Tuning.HUD_MOTION_HEIGHT))
	canvas.draw_style_box(_panel, rect)
	var chain: int = int(_motion.get(_local_id, {}).get("chain", 0))
	var heat: float = clampf(float(chain) / maxf(float(Tuning.HUD_CHAIN_HOT), 1.0), 0.0, 1.0)
	var color: Color = Tuning.HUD_CYAN.lerp(Tuning.HUD_CORAL, heat)
	_text(canvas, rect.position + Vector2(12.0, 28.0), "%.1f" % _speed, Tuning.HUD_MOTION_FONT_SIZE, color)
	_text(canvas, rect.position + Vector2(74.0, 27.0), "m/s", Tuning.HUD_HINT_SIZE, Tuning.HUD_MUTED)
	_text(canvas, rect.position + Vector2(rect.size.x - 69.0, 27.0), "×%d" % chain, Tuning.HUD_MOTION_FONT_SIZE, color)
	_text(canvas, rect.position + Vector2(12.0, 46.0), "SPEED / MOMENTUM", Tuning.HUD_HINT_SIZE - 2, Tuning.HUD_MUTED)
	_text(canvas, rect.position + Vector2(rect.size.x - 69.0, 46.0), "BHOP", Tuning.HUD_HINT_SIZE - 2, color)
	var meter := Rect2(rect.position + Vector2(12.0, rect.size.y - 11.0), Vector2(rect.size.x - 24.0, Tuning.HUD_SPEED_METER_HEIGHT))
	canvas.draw_rect(meter, Color(Tuning.HUD_MUTED, 0.18))
	meter.size.x *= clampf(_speed / maxf(Tuning.HUD_SPEED_METER_MAX, 0.01), 0.0, 1.0)
	canvas.draw_rect(meter, color)

func _draw_indicators(canvas: Control) -> void:
	if not is_instance_valid(_camera):
		return
	var center: Vector2 = _layout_size * 0.5
	var margin: float = Tuning.HUD_INDICATOR_MARGIN
	var bounds := Rect2(Vector2(margin, margin + Tuning.HUD_HINT_HEIGHT), Vector2(_layout_size.x - margin * 2.0, _layout_size.y - margin * 2.0 - Tuning.HUD_CARD_HEIGHT - Tuning.HUD_HINT_HEIGHT))
	for id in _ids:
		if int(id) == _local_id:
			continue
		var player: Dictionary = _world.players[id]
		if int(player.get("stocks", 0)) <= 0:
			continue
		var position: Vector3 = player.get("position", Vector3.ZERO)
		var behind: bool = _camera.is_position_behind(position)
		var projected: Vector2 = _camera.unproject_position(position) / _ui_scale
		if not behind and Rect2(Vector2.ZERO, _layout_size).has_point(projected):
			continue
		var direction: Vector2 = projected - center
		if behind:
			# Behind-camera projection is mirrored; camera-space XY gives its true side.
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
		var radius: float = Tuning.HUD_INDICATOR_RADIUS
		var color: Color = _player_color(int(id))
		canvas.draw_circle(point, radius, Tuning.HUD_PANEL)
		canvas.draw_arc(point, radius, 0.0, TAU, 24, color, 1.5, true)
		var tangent := Vector2(-direction.y, direction.x)
		var tip: Vector2 = point + direction * (radius + 8.0)
		canvas.draw_colored_polygon(PackedVector2Array([tip, point + direction * radius + tangent * 4.0, point + direction * radius - tangent * 4.0]), color)
		_text(canvas, point + Vector2(0.0, 4.0), str(id), Tuning.HUD_INDICATOR_FONT_SIZE, color, true)

func _draw_banner(canvas: Control) -> void:
	if _banner_remaining <= 0.0 and not _banner_persistent:
		return
	var age: float = _banner_duration - _banner_remaining
	var enter: float = clampf(age / maxf(Tuning.HUD_BANNER_POP, 0.001), 0.0, 1.0)
	var alpha: float = 1.0 if _banner_persistent else minf(1.0, _banner_remaining / maxf(Tuning.HUD_BANNER_POP, 0.001))
	var pop: float = 1.0 + (1.0 - enter) * Tuning.HUD_BANNER_POP_SCALE
	var size: int = roundi(Tuning.HUD_BANNER_SIZE * pop)
	# Long round/winner labels stay within the central third, even at eight players.
	var width: float = _font.get_string_size(_banner, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if width > _layout_size.x * Tuning.HUD_BANNER_MAX_WIDTH:
		size = roundi(size * _layout_size.x * Tuning.HUD_BANNER_MAX_WIDTH / width)
	var center := Vector2(_layout_size.x * 0.5, _layout_size.y * (Tuning.HUD_WINNER_Y if _phase == "winner" else Tuning.HUD_BANNER_Y))
	center.y -= (1.0 - enter) * Tuning.HUD_BANNER_LIFT
	var origin: Vector2 = center - Vector2(_font.get_string_size(_banner, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * 0.5, 0.0)
	canvas.draw_string_outline(_font, origin, _banner, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Tuning.HUD_BANNER_OUTLINE, Color(Tuning.HUD_PANEL, alpha))
	canvas.draw_string(_font, origin, _banner, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(_banner_color, alpha))
	_text(canvas, center + Vector2(0.0, Tuning.HUD_BANNER_SUB_GAP), _banner_sub, Tuning.HUD_BANNER_SUB_SIZE, Color(Tuning.HUD_TEXT, alpha), true)

func _draw_debug(canvas: Control) -> void:
	var player: Dictionary = _world.players.get(_local_id, {})
	var velocity: Vector3 = player.get("velocity", Vector3.ZERO)
	var text: String = "%s  |  TICK %d  |  %d FPS  |  %d PLAYERS" % [_phase.to_upper(), int(_world.get("tick", 0)), Engine.get_frames_per_second(), _ids.size()]
	_text(canvas, Vector2(Tuning.HUD_MARGIN, Tuning.HUD_MARGIN + Tuning.HUD_HINT_HEIGHT + 24.0), text, Tuning.HUD_DEBUG_SIZE, Tuning.HUD_CYAN)
	_text(canvas, Vector2(Tuning.HUD_MARGIN, Tuning.HUD_MARGIN + Tuning.HUD_HINT_HEIGHT + 43.0), "VEL %.2f / %.2f / %.2f   %s" % [velocity.x, velocity.y, velocity.z, "GROUND" if player.get("on_ground", false) else "AIR"], Tuning.HUD_DEBUG_SIZE, Tuning.HUD_MUTED)
