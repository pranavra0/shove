class_name KitEntitiesView
extends Node3D

var _instances: Dictionary = {}
var _signatures: Dictionary = {}

var _materials: Dictionary = {}
func render_world(world: Dictionary) -> void:
	var live: Dictionary = {}
	for kind: String in ["projectiles", "walls"]:
		var entities: Dictionary = world.get(kind, {})
		for raw_id: Variant in entities:
			var entity: Dictionary = entities[raw_id]
			var id: int = int(raw_id)
			var key: String = "%s:%d" % [kind, id]
			live[key] = true
			var element: String = str(entity.get("element", "earth"))
			var owner_id: int = int(entity.get("owner", -1))
			var players: Dictionary = world.get("players", {})
			var owner_player: Dictionary = players.get(owner_id, {})
			var team: int = int(owner_player.get("team", -1))
			var signature: String = kind + ":" + element + ":" + str(team)
			if not _instances.has(key) or _signatures.get(key, "") != signature:
				_remove_entity(key)
				_create_entity(key, signature, kind, element, team, entity)
			_update_transform(_instances[key], kind, entity)
	for key: String in _instances.keys():
		if not live.has(key):
			_remove_entity(key)

func clear() -> void:
	for key: String in _instances.keys():
		_remove_entity(key)

func _create_entity(key: String, signature: String, kind: String, element: String, team: int, entity: Dictionary) -> void:
	var root := Node3D.new()
	root.name = key.replace(":", "_")
	var shape: Mesh
	if kind == "walls":
		var box := BoxMesh.new()
		box.size = entity.get("size", Vector3(2.0, 2.0, 0.3))
		shape = box
	else:
		var extent: float = float(entity.get("size", 0.35))
		if element == "fire":
			shape = _tetrahedron(extent * 2.0)
		elif element == "air":
			var ring := TorusMesh.new()
			ring.inner_radius = extent * 0.88
			ring.outer_radius = extent
			shape = ring
		elif element == "water":
			var box := BoxMesh.new()
			box.size = Vector3(extent, extent, extent * 2.8)
			shape = box
		else:
			var box := BoxMesh.new()
			box.size = Vector3.ONE * extent * 2.0
			shape = box
	var instance := _add_mesh(root, shape)
	var material: StandardMaterial3D = _entity_material(signature, kind, element, team)
	instance.material_override = material
	add_child(root)
	_instances[key] = root
	_signatures[key] = signature

func _entity_material(signature: String, kind: String, element: String, team: int) -> StandardMaterial3D:
	if _materials.has(signature):
		return _materials[signature]
	var color: Color = Kits.color(element)
	var team_color: Color = color
	if team >= 0:
		var team_colors: Array[Color] = Tuning.CP_TEAM_COLORS
		if team < team_colors.size():
			team_color = team_colors[team]
	var face_color: Color = Color("#747b82") if kind == "walls" else color
	if team >= 0:
		face_color = face_color.lerp(team_color, 0.48)
	var outline := ShaderMaterial.new()
	outline.shader = preload("res://scripts/view/outline.gdshader")
	outline.set_shader_parameter("outline_color", team_color if team >= 0 else color if kind == "walls" else Color(0.025, 0.03, 0.04))
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = face_color
	material.next_pass = outline
	_materials[signature] = material
	return material

func _add_mesh(root: Node3D, mesh: Mesh) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	root.add_child(instance)
	return instance

func _update_transform(root: Node3D, kind: String, entity: Dictionary) -> void:
	root.position = entity.get("position", Vector3.ZERO)
	if kind == "projectiles":
		var velocity: Vector3 = entity.get("velocity", Vector3.ZERO)
		if velocity.length_squared() > 0.0001:
			var direction: Vector3 = velocity.normalized()
			root.look_at(root.position + direction, Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.999 else Vector3.UP)

func _remove_entity(key: String) -> void:
	if _instances.has(key):
		var node: Node = _instances[key]
		remove_child(node)
		node.queue_free()
		_instances.erase(key)
	_signatures.erase(key)

func _tetrahedron(size: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var half: float = size * 0.5
	var points: Array[Vector3] = [Vector3(0, half, 0), Vector3(-half, -half, half), Vector3(half, -half, half), Vector3(0, -half, -half)]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var faces: Array[PackedInt32Array] = [PackedInt32Array([0, 1, 2]), PackedInt32Array([0, 2, 3]), PackedInt32Array([0, 3, 1]), PackedInt32Array([1, 3, 2])]
	for face: PackedInt32Array in faces:
		var a: Vector3 = points[face[0]]
		var b: Vector3 = points[face[1]]
		var c: Vector3 = points[face[2]]
		var normal: Vector3 = (b - a).cross(c - a).normalized()
		vertices.append(a)
		vertices.append(c)
		vertices.append(b)
		normals.append(normal)
		normals.append(normal)
		normals.append(normal)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
