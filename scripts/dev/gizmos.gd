class_name DevGizmos
extends MeshInstance3D

var _lines := ImmediateMesh.new()
var _drawing: bool = false

func _ready() -> void:
	mesh = _lines
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

var trajectory_enabled: bool = false

func render_frame(world: Dictionary, preview: Array = [], preview_color: Color = Color("#eeeeee")) -> void:
	visible = (Tuning.DEV_HITBOX_ENABLED or Tuning.DEV_VELOCITY_ENABLED or (trajectory_enabled and not preview.is_empty())) and not world.is_empty()
	if not visible:
		return
	_lines.clear_surfaces()
	_drawing = false
	for player: Dictionary in world.players.values():
		if not World.is_player_active(player):
			continue
		var at: Vector3 = player.position
		if Tuning.DEV_VELOCITY_ENABLED:
			_line(at, at + player.velocity * Tuning.DEV_VELOCITY_SCALE, Color("ffe28a"))
		if Tuning.DEV_HITBOX_ENABLED:
			var data: Dictionary = Kits.move(str(player.element), "shove")
			var center: Vector3 = at + Vector3.FORWARD.rotated(Vector3.UP, player.yaw) * float(data.reach)
			var color := Color("ff7865") if player.attack_time > 0.0 else Color("50e3ed")
			for axis in range(3):
				for segment in range(Tuning.DEV_GIZMO_SEGMENTS):
					var a: float = TAU * segment / Tuning.DEV_GIZMO_SEGMENTS
					var b: float = TAU * (segment + 1) / Tuning.DEV_GIZMO_SEGMENTS
					var first := Vector3(cos(a), sin(a), 0) * float(data.size)
					var second := Vector3(cos(b), sin(b), 0) * float(data.size)
					if axis == 1:
						first = Vector3(first.x, 0, first.y)
						second = Vector3(second.x, 0, second.y)
					elif axis == 2:
						first = Vector3(0, first.x, first.y)
						second = Vector3(0, second.x, second.y)
					_line(center + first, center + second, color)
	if preview.size() > 1:
		for i in range(preview.size() - 1):
			_line(preview[i], preview[i + 1], preview_color)
	if _drawing:
		_lines.surface_end()

func _line(from: Vector3, to: Vector3, color: Color) -> void:
	if not _drawing:
		_lines.surface_begin(Mesh.PRIMITIVE_LINES)
		_drawing = true
	_lines.surface_set_color(color)
	_lines.surface_add_vertex(from)
	_lines.surface_set_color(color)
	_lines.surface_add_vertex(to)
