class_name JuiceView
extends Node3D

const OverlayScript = preload("res://scripts/view/juice_overlay.gd")

# The owner consumes freeze_remaining in real physics ticks; this view never
# pauses World, changes Engine.time_scale, or writes to a World dictionary.
var shake: float = 0.0
var freeze_remaining: float = 0.0
var ko_target := Vector3.ZERO
var ko_remaining: float = 0.0

var _last_event_tick: int = -1
var _last_motion_tick: int = -1
var _particles: Array[Dictionary] = []
var _rings: Array[Dictionary] = []
var _trails: Array[Dictionary] = []
var _popups: Array[Dictionary] = []
var _previous_positions: Dictionary = {}
var _comet_until: Dictionary = {}
var _random := RandomNumberGenerator.new()
var _geometry := ImmediateMesh.new()
var _mesh_instance: MeshInstance3D
var _overlay: OverlayScript
var _canvas: CanvasLayer
var _vertex_count: int = 0

func _ready() -> void:
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "ProceduralJuice"
	_mesh_instance.mesh = _geometry
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	_mesh_instance.material_override = material
	add_child(_mesh_instance)
	_canvas = CanvasLayer.new()
	_canvas.name = "JuiceOverlay"
	_canvas.layer = 1
	add_child(_canvas)
	_overlay = OverlayScript.new()
	_canvas.add_child(_overlay)

func consume(events: Array, world: Dictionary, local_id: int) -> void:
	var tick: int = int(world.get("tick", 0))
	if tick < _last_event_tick:
		clear()
	if tick == _last_event_tick:
		return
	_last_event_tick = tick
	var players: Dictionary = world.get("players", {})
	for index in range(events.size()):
		var event: Dictionary = events[index]
		var id: int = int(event.get("player", -1))
		var point: Vector3 = event.get("position", Vector3.ZERO)
		_seed(tick, id, index)
		match str(event.get("type", "")):
			"hit":
				var strength: float = maxf(0.0, float(event.get("strength", 0.0)))
				var tint: Color = Tuning.JUICE_CYAN if id == local_id else Tuning.JUICE_CORAL
				if is_instance_valid(_overlay):
					_overlay.flash()
				if Tuning.JUICE_HITSTOP_ENABLED:
					freeze_remaining = maxf(freeze_remaining, clampf(Tuning.JUICE_HITSTOP_DURATION + strength * Tuning.JUICE_HITSTOP_STRENGTH_SCALE, 0.0, Tuning.JUICE_HITSTOP_MAX_DURATION))
				if Tuning.JUICE_SHAKE_ENABLED:
					shake = minf(Tuning.JUICE_SHAKE_MAX, shake + strength * Tuning.JUICE_SHAKE_STRENGTH)
				if Tuning.JUICE_SHOCKWAVE_ENABLED:
					_ring(point, tint)
				if Tuning.JUICE_SHARDS_ENABLED:
					_burst(point, Tuning.JUICE_SHARDS_COUNT, Tuning.JUICE_SHARDS_DURATION, Tuning.JUICE_SHARDS_SPEED, Tuning.JUICE_SHARDS_SIZE, tint, "hit")
				if Tuning.JUICE_DAMAGE_POPUP_ENABLED:
					_popup(point, float(event.get("damage", Tuning.SHOVE_DAMAGE)), tint)
				if Tuning.JUICE_COMET_ENABLED and strength >= Tuning.JUICE_COMET_THRESHOLD:
					_comet_until[id] = tick + int(ceil(Tuning.JUICE_COMET_DURATION * Tuning.TICK_RATE))
					_previous_positions[id] = point
			"land":
				if Tuning.JUICE_LANDING_PUFF_ENABLED:
					point.y -= Tuning.BODY_HEIGHT * 0.5
					_burst(point, Tuning.JUICE_LANDING_PUFF_COUNT, Tuning.JUICE_LANDING_PUFF_DURATION, Tuning.JUICE_LANDING_PUFF_SPEED, Tuning.JUICE_LANDING_PUFF_SIZE, Tuning.JUICE_DUST_COLOR, "land")
			"ko":
				_comet_until.erase(id)
				_previous_positions.erase(id)
				if Tuning.JUICE_KO_ENABLED:
					ko_target = point
					ko_remaining = Tuning.JUICE_KO_DURATION
					if Tuning.JUICE_SHAKE_ENABLED:
						shake = minf(Tuning.JUICE_SHAKE_MAX, shake + Tuning.JUICE_KO_SHAKE_STRENGTH)
			"jump":
				# Break the dust cadence at takeoff without altering player state.
				if players.has(id):
					_previous_positions[id] = point

func render_frame(world: Dictionary, local_id: int, camera: Camera3D, delta: float) -> void:
	var elapsed: float = maxf(0.0, delta)
	shake = move_toward(shake, 0.0, Tuning.JUICE_SHAKE_DECAY * elapsed) if Tuning.JUICE_SHAKE_ENABLED else 0.0
	ko_remaining = maxf(0.0, ko_remaining - elapsed) if Tuning.JUICE_KO_ENABLED else 0.0
	if not Tuning.JUICE_HITSTOP_ENABLED:
		freeze_remaining = 0.0
	_advance_effects(elapsed)
	var tick: int = int(world.get("tick", 0))
	if tick < _last_motion_tick:
		clear()
	if tick != _last_motion_tick:
		_emit_motion(world, tick)
		_last_motion_tick = tick
	var speed: float = 0.0
	var players: Dictionary = world.get("players", {})
	if players.has(local_id) and int(players[local_id].get("stocks", 0)) > 0:
		var velocity: Vector3 = players[local_id].get("velocity", Vector3.ZERO)
		speed = Vector2(velocity.x, velocity.z).length()
	if is_instance_valid(_overlay):
		_overlay.advance(elapsed, speed, tick)
	if is_instance_valid(camera):
		_redraw(camera)

func _seed(tick: int, id: int, salt: int) -> void:
	_random.seed = ((tick + 1) * 73856093 + (id + 7) * 19349663 + (salt + 1) * 83492791) & 0x7fffffff

func _emit_motion(world: Dictionary, tick: int) -> void:
	var players: Dictionary = world.get("players", {})
	var ids: Array = players.keys()
	ids.sort()
	var trail_ticks: int = maxi(1, int(round(Tuning.JUICE_TRAIL_INTERVAL * Tuning.TICK_RATE)))
	var footstep_ticks: int = maxi(1, int(round(Tuning.JUICE_FOOTSTEP_DUST_INTERVAL * Tuning.TICK_RATE)))
	for id in ids:
		var player: Dictionary = players[id]
		if int(player.get("stocks", 0)) <= 0:
			_previous_positions.erase(id)
			_comet_until.erase(id)
			continue
		var point: Vector3 = player.get("position", Vector3.ZERO)
		var velocity: Vector3 = player.get("velocity", Vector3.ZERO)
		var speed: float = Vector2(velocity.x, velocity.z).length()
		var comet: bool = Tuning.JUICE_COMET_ENABLED and tick <= int(_comet_until.get(id, -1))
		if _comet_until.has(id) and not comet:
			_comet_until.erase(id)
		if tick % trail_ticks == 0:
			var previous: Vector3 = _previous_positions.get(id, point)
			# Teleports/respawns are not a continuous flight path.
			var max_distance: float = maxf(1.0, velocity.length() * Tuning.JUICE_TRAIL_INTERVAL * 4.0)
			if previous.distance_squared_to(point) <= max_distance * max_distance and previous.distance_squared_to(point) > 0.0001:
				if comet or (Tuning.JUICE_TRAIL_ENABLED and speed >= Tuning.JUICE_TRAIL_THRESHOLD):
					_trail(previous, point, comet, int(id))
			_previous_positions[id] = point
		if Tuning.JUICE_FOOTSTEP_DUST_ENABLED and bool(player.get("on_ground", false)) and speed >= Tuning.JUICE_FOOTSTEP_DUST_THRESHOLD and (tick + int(id)) % footstep_ticks == 0:
			_seed(tick, int(id), 301)
			var feet: Vector3 = point - Vector3.UP * Tuning.BODY_HEIGHT * 0.5
			_burst(feet, Tuning.JUICE_FOOTSTEP_DUST_COUNT, Tuning.JUICE_FOOTSTEP_DUST_DURATION, Tuning.JUICE_FOOTSTEP_DUST_SPEED, Tuning.JUICE_FOOTSTEP_DUST_SIZE, Tuning.JUICE_DUST_COLOR, "dust")

func _burst(point: Vector3, count: int, duration: float, speed: float, size: float, color: Color, kind: String) -> void:
	for index in range(maxi(0, count)):
		if _particles.size() >= maxi(0, Tuning.JUICE_MAX_PARTICLES):
			break
		var direction := Vector3(_random.randf_range(-1.0, 1.0), _random.randf_range(-0.3, 1.0), _random.randf_range(-1.0, 1.0)).normalized()
		if kind != "hit":
			direction.y = absf(direction.y) * 0.45 + 0.15
		var lifetime: float = maxf(0.001, duration * _random.randf_range(0.7, 1.0))
		_particles.append({
			"position": point, "velocity": direction * speed * _random.randf_range(0.4, 1.0),
			"life": lifetime, "duration": lifetime, "size": size * _random.randf_range(0.65, 1.3),
			"angle": _random.randf_range(0.0, TAU), "spin": _random.randf_range(-8.0, 8.0),
			"color": Tuning.JUICE_IVORY if kind == "hit" and index % 3 == 0 else color, "kind": kind,
		})

func _ring(point: Vector3, color: Color) -> void:
	if _rings.size() >= maxi(0, Tuning.JUICE_MAX_RINGS):
		return
	_rings.append({"position": point, "color": color, "life": Tuning.JUICE_SHOCKWAVE_DURATION, "duration": maxf(0.001, Tuning.JUICE_SHOCKWAVE_DURATION)})

func _trail(from: Vector3, to: Vector3, comet: bool, id: int) -> void:
	if _trails.size() >= maxi(0, Tuning.JUICE_MAX_TRAIL_SEGMENTS):
		return
	var duration: float = maxf(0.001, Tuning.JUICE_COMET_TRAIL_DURATION if comet else Tuning.JUICE_TRAIL_DURATION)
	_trails.append({"from": from, "to": to, "life": duration, "duration": duration,
		"width": Tuning.JUICE_COMET_WIDTH if comet else Tuning.JUICE_TRAIL_WIDTH,
		"color": Tuning.JUICE_CORAL if comet else (Tuning.JUICE_CYAN if id % 2 == 0 else Tuning.JUICE_IVORY), "comet": comet})

func _popup(point: Vector3, damage: float, tint: Color) -> void:
	if _popups.size() >= maxi(0, Tuning.JUICE_MAX_POPUPS):
		return
	var label := Label3D.new()
	label.text = "+%d%%" % int(round(damage))
	label.font_size = Tuning.JUICE_DAMAGE_POPUP_FONT_SIZE
	label.pixel_size = Tuning.JUICE_DAMAGE_POPUP_PIXEL_SIZE
	label.outline_size = maxi(1, Tuning.JUICE_DAMAGE_POPUP_FONT_SIZE / 5)
	label.outline_modulate = Tuning.JUICE_DUST_COLOR.darkened(0.85)
	label.modulate = tint
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = point + Vector3.UP * Tuning.BODY_HEIGHT * 0.6
	add_child(label)
	_popups.append({"label": label, "start": label.position, "life": Tuning.JUICE_DAMAGE_POPUP_DURATION, "duration": maxf(0.001, Tuning.JUICE_DAMAGE_POPUP_DURATION)})

func _advance_effects(delta: float) -> void:
	for index in range(_particles.size() - 1, -1, -1):
		var particle: Dictionary = _particles[index]
		particle.life -= delta
		if particle.life <= 0.0:
			_particles.remove_at(index)
			continue
		var gravity: float = Tuning.JUICE_SHARDS_GRAVITY if particle.kind == "hit" else Tuning.JUICE_SHARDS_GRAVITY * 0.15
		particle.velocity.y -= gravity * delta
		particle.position += particle.velocity * delta
		particle.angle += particle.spin * delta
	for collection in [_rings, _trails]:
		for index in range(collection.size() - 1, -1, -1):
			collection[index].life -= delta
			if collection[index].life <= 0.0:
				collection.remove_at(index)
	for index in range(_popups.size() - 1, -1, -1):
		var popup: Dictionary = _popups[index]
		popup.life -= delta
		var label: Label3D = popup.label
		if popup.life <= 0.0 or not Tuning.JUICE_DAMAGE_POPUP_ENABLED:
			label.queue_free()
			_popups.remove_at(index)
			continue
		var progress: float = 1.0 - popup.life / popup.duration
		label.position = popup.start + Vector3.UP * Tuning.JUICE_DAMAGE_POPUP_RISE * progress
		label.scale = Vector3.ONE * (1.0 + sin(progress * PI) * 0.18)
		label.modulate.a = minf(1.0, (1.0 - progress) * 3.0)

func _redraw(camera: Camera3D) -> void:
	_geometry.clear_surfaces()
	_vertex_count = 0
	if _particles.is_empty() and _rings.is_empty() and _trails.is_empty():
		return
	var right: Vector3 = camera.global_basis.x
	var up: Vector3 = camera.global_basis.y
	for particle in _particles:
		if (particle.kind == "hit" and not Tuning.JUICE_SHARDS_ENABLED) or (particle.kind == "dust" and not Tuning.JUICE_FOOTSTEP_DUST_ENABLED) or (particle.kind == "land" and not Tuning.JUICE_LANDING_PUFF_ENABLED):
			continue
		var fraction: float = particle.life / particle.duration
		var color: Color = particle.color
		color.a = fraction
		var length: float = particle.size * (0.4 + fraction * 0.6)
		var axis: Vector3 = right * cos(particle.angle) + up * sin(particle.angle)
		var side: Vector3 = -right * sin(particle.angle) + up * cos(particle.angle)
		var point: Vector3 = particle.position
		_triangle(point + axis * length * 1.8, point - axis * length + side * length * 0.55, point - axis * length - side * length * 0.55, color)
	if Tuning.JUICE_SHOCKWAVE_ENABLED:
		for ring in _rings:
			var progress: float = 1.0 - ring.life / ring.duration
			var radius: float = Tuning.JUICE_SHOCKWAVE_RADIUS * (1.0 - pow(1.0 - progress, 3.0))
			var width: float = Tuning.JUICE_SHOCKWAVE_WIDTH * (1.0 - progress)
			var color: Color = ring.color
			color.a = 1.0 - progress
			var point: Vector3 = ring.position
			var segments: int = maxi(3, Tuning.JUICE_SHOCKWAVE_SEGMENTS)
			for index in range(segments):
				var angle_a: float = TAU * float(index) / segments
				var angle_b: float = TAU * float(index + 1) / segments
				var axis_a: Vector3 = right * cos(angle_a) + up * sin(angle_a)
				var axis_b: Vector3 = right * cos(angle_b) + up * sin(angle_b)
				_quad(point + axis_a * radius, point + axis_b * radius, point + axis_b * maxf(0.0, radius - width), point + axis_a * maxf(0.0, radius - width), color)
	for trail in _trails:
		if (trail.comet and not Tuning.JUICE_COMET_ENABLED) or (not trail.comet and not Tuning.JUICE_TRAIL_ENABLED):
			continue
		var fraction: float = trail.life / trail.duration
		var direction: Vector3 = trail.to - trail.from
		var normal: Vector3 = camera.global_position - (trail.to + trail.from) * 0.5
		var side: Vector3 = direction.cross(normal).normalized() * trail.width * fraction
		var color: Color = trail.color
		color.a = fraction * 0.8
		_quad(trail.from - side * 0.3, trail.to - side, trail.to + side, trail.from + side * 0.3, color)
		if trail.comet:
			var core: Color = Tuning.JUICE_IVORY
			core.a = fraction
			_quad(trail.from - side * 0.1, trail.to - side * 0.3, trail.to + side * 0.3, trail.from + side * 0.1, core)
	if _vertex_count > 0:
		_geometry.surface_end()

func _triangle(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	if _vertex_count == 0:
		_geometry.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_vertex_count += 3
	_geometry.surface_set_color(color)
	_geometry.surface_add_vertex(a)
	_geometry.surface_add_vertex(b)
	_geometry.surface_add_vertex(c)

func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_triangle(a, b, c, color)
	_triangle(a, c, d, color)

func clear() -> void:
	for popup in _popups:
		var label: Label3D = popup.label
		label.queue_free()
	_popups.clear()
	_particles.clear()
	_rings.clear()
	_trails.clear()
	_previous_positions.clear()
	_comet_until.clear()
	_geometry.clear_surfaces()
	_last_event_tick = -1
	_last_motion_tick = -1
	shake = 0.0
	freeze_remaining = 0.0
	ko_remaining = 0.0
	ko_target = Vector3.ZERO
	if is_instance_valid(_overlay):
		_overlay.flash_remaining = 0.0
		_overlay.speed_strength = 0.0
		_overlay.queue_redraw()
