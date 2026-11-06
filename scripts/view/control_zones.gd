class_name ControlZonesView
extends Node3D

const RING_SEGMENTS: int = 64
const NEUTRAL_COLOR: Color = Color("#c5c9c7")

var _zone_nodes: Array[Node3D] = []
var _fills: Array[MeshInstance3D] = []
var _outlines: Array[MeshInstance3D] = []
var _progress_rings: Array[MeshInstance3D] = []
var _last_capturing: Array[int] = [-2, -2]
var _last_progress: Array[float] = [-1.0, -1.0]

func _ready() -> void:
	for index in range(2):
		var zone := Node3D.new()
		zone.name = "ControlZone%d" % index
		add_child(zone)
		_zone_nodes.append(zone)
		_fills.append(_disc(zone, 0.04))
		_outlines.append(_outline(zone, 0.08))
		_progress_rings.append(_progress_ring(zone, 0.105))

func render_world(world: Dictionary) -> void:
	var control: Dictionary = world.get("control", {})
	var zones: Array = control.get("zones", [])
	if str(world.get("mode", "ffa")) != "control" or zones.size() != 2:
		clear()
		return
	for index in range(2):
		var value: Variant = zones[index]
		if not value is Dictionary:
			_zone_nodes[index].visible = false
			continue
		var zone: Dictionary = value
		var node: Node3D = _zone_nodes[index]
		node.visible = true
		var position: Vector3 = zone.get("position", Vector3.ZERO)
		var radius: float = maxf(0.1, float(zone.get("radius", 1.0)))
		node.position = Vector3(position.x, 0.0, position.z)
		var owner: int = int(zone.get("owner", -1))
		var capturing: int = int(zone.get("capturing", -1))
		var progress: float = clampf(float(zone.get("progress", 0.0)), 0.0, 1.0)
		var fill_material: StandardMaterial3D = _fills[index].material_override as StandardMaterial3D
		var outline_material: StandardMaterial3D = _outlines[index].material_override as StandardMaterial3D
		var progress_material: StandardMaterial3D = _progress_rings[index].material_override as StandardMaterial3D
		fill_material.albedo_color = Color(_team_color(owner), 0.22) if owner >= 0 else Color(NEUTRAL_COLOR, 0.20)
		outline_material.albedo_color = _team_color(owner) if owner >= 0 else NEUTRAL_COLOR.darkened(0.18)
		progress_material.albedo_color = _team_color(capturing) if capturing >= 0 else Color.TRANSPARENT
		_progress_rings[index].visible = capturing >= 0
		if _last_progress[index] != progress or _last_capturing[index] != capturing:
			_progress_rings[index].mesh = _arc_mesh(0.88, 0.99, progress)
			_last_progress[index] = progress
			_last_capturing[index] = capturing
		_fills[index].scale = Vector3(radius, 1.0, radius)
		_outlines[index].scale = Vector3(radius, 1.0, radius)
		_progress_rings[index].scale = Vector3(radius, 1.0, radius)

func clear() -> void:
	for zone: Node3D in _zone_nodes:
		zone.visible = false
	_last_capturing = [-2, -2]
	_last_progress = [-1.0, -1.0]

func _team_color(team: int) -> Color:
	var colors: Array[Color] = Tuning.CP_TEAM_COLORS
	if team >= 0 and team < colors.size():
		return colors[team]
	return NEUTRAL_COLOR

func _disc(parent: Node3D, height: float) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = _disc_mesh(1.0)
	var material := _flat_material(Color(NEUTRAL_COLOR, 0.20))
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	instance.material_override = material
	instance.position.y = height
	parent.add_child(instance)
	return instance

func _outline(parent: Node3D, height: float) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = _torus_mesh(1.0)
	instance.material_override = _flat_material(NEUTRAL_COLOR.darkened(0.18))
	instance.position.y = height
	parent.add_child(instance)
	return instance

func _progress_ring(parent: Node3D, height: float) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = _arc_mesh(0.88, 0.99, 0.0)
	instance.material_override = _flat_material(Color.TRANSPARENT)
	instance.position.y = height
	parent.add_child(instance)
	return instance

func _flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material

func _disc_mesh(radius: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.012
	mesh.radial_segments = RING_SEGMENTS
	return mesh

func _torus_mesh(radius: float) -> TorusMesh:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius * 0.94
	mesh.outer_radius = radius
	mesh.rings = RING_SEGMENTS
	mesh.ring_segments = 6
	return mesh

func _arc_mesh(inner_radius: float, outer_radius: float, progress: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var count: int = maxi(1, int(ceil(float(RING_SEGMENTS) * progress)))
	for segment in range(count):
		var start_angle: float = -PI * 0.5 + TAU * progress * float(segment) / float(count)
		var end_angle: float = -PI * 0.5 + TAU * progress * float(segment + 1) / float(count)
		var inner_start := Vector3(cos(start_angle) * inner_radius, 0.0, sin(start_angle) * inner_radius)
		var outer_start := Vector3(cos(start_angle) * outer_radius, 0.0, sin(start_angle) * outer_radius)
		var inner_end := Vector3(cos(end_angle) * inner_radius, 0.0, sin(end_angle) * inner_radius)
		var outer_end := Vector3(cos(end_angle) * outer_radius, 0.0, sin(end_angle) * outer_radius)
		# Godot renders clockwise-wound triangles as front faces; keep these sectors upward-facing.
		vertices.append_array(PackedVector3Array([inner_start, outer_start, outer_end, inner_start, outer_end, inner_end]))
		for vertex_index in range(6):
			normals.append(Vector3.UP)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
