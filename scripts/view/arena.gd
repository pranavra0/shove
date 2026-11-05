class_name ArenaView
extends Node3D

var _debris: Array[Node3D] = []
var _orbits: Array[Vector3] = []

func _ready() -> void:
	var top := ShaderMaterial.new()
	top.shader = preload("res://scripts/view/arena_surface.gdshader")
	top.set_shader_parameter("base_color", Tuning.VIS_TOP_COLOR)
	top.set_shader_parameter("line_color", Tuning.VIS_LANE_COLOR)
	var rock := _material(Tuning.VIS_ROCK_COLOR)
	var coral := _material(Tuning.VIS_EDGE_COLOR, Tuning.VIS_EDGE_EMISSION)
	var cyan := _material(Tuning.VIS_LANE_COLOR, Tuning.VIS_EDGE_EMISSION)
	var size: float = Tuning.PLATFORM_SIZE
	_box(Vector3(0, -Tuning.PLATFORM_THICKNESS * 0.5, 0), Vector3(size, Tuning.PLATFORM_THICKNESS, size), top, true)
	# Stacked four-sided frusta give the island a readable, thick rock silhouette.
	var depth: float = Tuning.VIS_ROCK_DEPTH
	for layer in range(3):
		var stone := CylinderMesh.new()
		stone.top_radius = size * (0.70 - float(layer) * 0.01)
		stone.bottom_radius = size * (0.69 - float(layer) * 0.01) if layer < 2 else size * 0.38
		stone.height = depth / 3.0
		stone.radial_segments = 4
		var facet := _material(Tuning.VIS_ROCK_COLOR.lightened(0.035 * layer))
		var mass := _mesh(stone, Vector3(0, -Tuning.PLATFORM_THICKNESS - stone.height * (layer + 0.5), 0), facet)
		mass.rotation.y = PI * 0.25
	# Geometry-backed halos preserve the neon edge on Compatibility without bloom.
	var halo := _material(Tuning.VIS_EDGE_COLOR, Tuning.VIS_EDGE_EMISSION)
	halo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo.albedo_color = Color(Tuning.VIS_EDGE_COLOR, 0.10)
	halo.emission_energy_multiplier = 0.15 * Tuning.VIS_EDGE_EMISSION
	for side in [-1.0, 1.0]:
		_box(Vector3(side * (size * 0.5 - 0.12), 0.035, 0), Vector3(0.22,0.09,size), coral)
		_box(Vector3(0, 0.035, side * (size * 0.5 - 0.12)), Vector3(size,0.09,0.22), coral)
		_box(Vector3(side * (size * 0.5 - 0.16),0.012,0),Vector3(0.85,0.012,size+0.3),halo)
		_box(Vector3(0,0.012,side * (size * 0.5 - 0.16)),Vector3(size+0.3,0.012,0.85),halo)
		for j in range(20):
			_box(Vector3(side * (size * 0.5 - 0.5),0.07,-size * 0.5 + 1.0 + j * size / 20.0),Vector3(0.45,0.03,0.10),cyan)
	_box(Vector3(0,Tuning.CENTER_HEIGHT * 0.5,0),Vector3(Tuning.CENTER_SIZE,Tuning.CENTER_HEIGHT,Tuning.CENTER_SIZE),top,true)
	_ring(Vector3(0,Tuning.CENTER_HEIGHT + 0.025,0),Tuning.CENTER_SIZE * 0.4,coral)
	for side in [-1.0,1.0]:
		_ramp(side * Tuning.RAMP_OFFSET,top,cyan)
		_box(Vector3(side * Tuning.LEDGE_OFFSET,Tuning.LEDGE_HEIGHT * 0.5,0),Vector3(Tuning.LEDGE_WIDTH,Tuning.LEDGE_HEIGHT,Tuning.LEDGE_LENGTH),top,true)
		_box(Vector3(side * Tuning.LEDGE_OFFSET,Tuning.LEDGE_HEIGHT + 0.02,0),Vector3(Tuning.LEDGE_WIDTH,0.04,0.10),coral)
	for i in range(8):
		var angle: float = TAU * i / 8.0 + 0.18
		var point := Vector3(cos(angle),0,sin(angle)) * size * 0.82
		var pillar := CylinderMesh.new()
		pillar.top_radius = 0.7
		pillar.bottom_radius = 1.3
		pillar.height = 4.0 + (i % 3)
		pillar.radial_segments = 5
		_mesh(pillar, point + Vector3.DOWN * 2.0, rock)
		for j in range(3):
			var crystal := CylinderMesh.new()
			crystal.top_radius = 0.0
			crystal.bottom_radius = 0.35 + j * 0.12
			crystal.height = 1.8 + j * 0.7
			crystal.radial_segments = 5
			var shard := _mesh(crystal,point + Vector3(j * 0.7 - 0.7,1.0 + j * 0.25,0),cyan if i % 2 == 0 else coral)
			shard.rotation.z = (j - 1) * 0.25
	for i in range(Tuning.VIS_DEBRIS_COUNT):
		var debris := MeshInstance3D.new()
		var stone := SphereMesh.new()
		stone.radial_segments = 5
		stone.rings = 3
		stone.radius = 0.5 + (i % 4) * 0.2
		stone.height = stone.radius * 1.7
		debris.mesh = stone
		debris.material_override = rock
		add_child(debris)
		_debris.append(debris)
		_orbits.append(Vector3(TAU * i / maxf(1,Tuning.VIS_DEBRIS_COUNT),size * (0.65 + (i % 3) * 0.09),-2.0 - i % 5))
	_environment()
	animate(0.0,0.0)

func _material(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.86
	material.emission_enabled = emission > 0.0
	material.emission = color
	material.emission_energy_multiplier = emission
	return material

func _mesh(mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = at
	add_child(node)
	return node

func _box(at: Vector3, size: Vector3, material: Material, collision: bool = false) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_mesh(mesh,at,material)
	if collision:
		var shape := BoxShape3D.new()
		shape.size = size
		_proxy(shape,Transform3D(Basis.IDENTITY,at))

func _proxy(shape: Shape3D, transform: Transform3D) -> void:
	var body := StaticBody3D.new()
	body.name = "CameraProxy"
	body.collision_layer = 1
	body.collision_mask = 0
	body.transform = transform
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child(body)

func _triangles(vertices: Array, material: Material) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex in vertices:
		surface.add_vertex(vertex)
	surface.generate_normals()
	_mesh(surface.commit(),Vector3.ZERO,material)

func _ramp(x: float, material: Material, accent: Material) -> void:
	var w: float = Tuning.RAMP_WIDTH * 0.5
	var l: float = Tuning.RAMP_LENGTH * 0.5
	var h: float = Tuning.RAMP_HEIGHT
	var a := Vector3(x-w,h,-l)
	var b := Vector3(x+w,h,-l)
	var c := Vector3(x+w,0,l)
	var d := Vector3(x-w,0,l)
	var e := Vector3(x-w,0,-l)
	var f := Vector3(x+w,0,-l)
	_triangles([a,c,b,a,d,c,a,b,f,a,f,e,a,e,d,b,c,f],material)
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([a,b,c,d,e,f])
	_proxy(shape,Transform3D.IDENTITY)
	for side in [-1.0,1.0]:
		var strip := BoxMesh.new()
		strip.size = Vector3(0.08,0.035,sqrt(l*l*4+h*h))
		var node := _mesh(strip,Vector3(x + side * (w-0.10),h*0.5+0.025,0),accent)
		node.rotation.x = atan2(h,l*2)

func _ring(at: Vector3, radius: float, material: Material) -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = radius - 0.045
	ring.outer_radius = radius + 0.045
	ring.rings = 48
	ring.ring_segments = 6
	_mesh(ring,at,material)

func _environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ShaderMaterial.new()
	sky_material.shader = preload("res://scripts/view/void_sky.gdshader")
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("81b8d3")
	environment.ambient_light_energy = Tuning.VIS_AMBIENT_ENERGY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("20334e")
	environment.fog_density = Tuning.VIS_FOG_DENSITY
	environment.fog_sky_affect = 0.0
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		environment.glow_enabled = true
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(Tuning.LIGHT_PITCH,Tuning.LIGHT_YAW,0)
	sun.light_color = Color("ffe2be")
	sun.light_energy = Tuning.VIS_SUN_ENERGY
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 100.0
	sun.light_angular_distance = Tuning.VIS_SHADOW_SOFTNESS
	add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20,140,0)
	rim.light_color = Tuning.VIS_LANE_COLOR
	rim.light_energy = Tuning.VIS_RIM_LIGHT_ENERGY
	add_child(rim)
	# Layered translucent ellipses form a luminous cloud sea beneath the island.
	for i in range(7):
		var cloud := SphereMesh.new()
		cloud.radius = 24.0 + i * 5.0
		cloud.height = 1.0
		var material := _material(Color(0.08,0.21,0.30,0.12),Tuning.VIS_VOID_CLOUD_EMISSION)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var node := _mesh(cloud,Vector3(sin(i*2.1)*14,-20-i*1.7,cos(i*2.1)*14),material)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func animate(_delta: float, time: float) -> void:
	for i in range(_debris.size()):
		var orbit: Vector3 = _orbits[i]
		var angle: float = orbit.x + time * Tuning.VIS_DEBRIS_RATE * (0.5 + (i % 3) * 0.2)
		_debris[i].position = Vector3(cos(angle)*orbit.y,orbit.z+sin(time*Tuning.VIS_DEBRIS_BOB_RATE+i)*Tuning.VIS_DEBRIS_BOB,sin(angle)*orbit.y)
		_debris[i].rotation = Vector3(time*Tuning.VIS_DEBRIS_SPIN.x+i,angle,time*Tuning.VIS_DEBRIS_SPIN.y)
