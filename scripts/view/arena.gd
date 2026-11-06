class_name ArenaView
extends Node3D

const SKY_UPPER_TONE: Color = Color(0.78, 0.78, 0.78, 1.0)
const SKY_LOWER_TONE: Color = Color(0.68, 0.68, 0.68, 1.0)

var mode: String = "ffa"

func _ready() -> void:
	var surface := ShaderMaterial.new()
	surface.shader = preload("res://scripts/view/arena_surface.gdshader")
	var outline := ShaderMaterial.new()
	outline.shader = preload("res://scripts/view/outline.gdshader")
	surface.next_pass = outline
	var size: float = Tuning.PLATFORM_SIZE
	_box(Vector3(0, -Tuning.PLATFORM_THICKNESS * 0.5, 0), Vector3(size, Tuning.PLATFORM_THICKNESS, size), surface, true)
	# The four-sided underside retains the original silhouette and platform extent.
	var depth: float = Tuning.VIS_ROCK_DEPTH
	for layer in range(3):
		var stone := CylinderMesh.new()
		stone.top_radius = size * (0.70 - float(layer) * 0.01)
		stone.bottom_radius = size * (0.69 - float(layer) * 0.01) if layer < 2 else size * 0.38
		stone.height = depth / 3.0
		stone.radial_segments = 4
		var facet := _material(Color("#bcbcbc").darkened(0.035 * layer), outline)
		var mass := _mesh(stone, Vector3(0, -Tuning.PLATFORM_THICKNESS - stone.height * (layer + 0.5), 0), facet)
		mass.rotation.y = PI * 0.25
	if mode == "control":
		_control_lanes(size)
	else:
		var top := _material(Color("#dedede"), outline)
		_box(Vector3(0,Tuning.CENTER_HEIGHT * 0.5,0),Vector3(Tuning.CENTER_SIZE,Tuning.CENTER_HEIGHT,Tuning.CENTER_SIZE),top,true)
		for side in [-1.0,1.0]:
			_ramp(side * Tuning.RAMP_OFFSET,surface)
			_box(Vector3(side * Tuning.LEDGE_OFFSET,Tuning.LEDGE_HEIGHT * 0.5,0),Vector3(Tuning.LEDGE_WIDTH,Tuning.LEDGE_HEIGHT,Tuning.LEDGE_LENGTH),top,true)
	animate(0.0,0.0)

func _control_lanes(size: float) -> void:
	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.albedo_color = Color(0.77, 0.79, 0.78, 0.32)
	line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for boundary: float in [-6.0, 6.0]:
		_box(Vector3(boundary, 0.006, 0), Vector3(0.035, 0.008, size * 0.9), line_material)

func _material(color: Color, outline: ShaderMaterial) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	material.next_pass = outline
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

func _ramp(x: float, material: Material) -> void:
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

static func ensure_scene_environment(environment_root: Node) -> void:
	var world_environment: WorldEnvironment = environment_root.get_node_or_null("ArenaWorldEnvironment") as WorldEnvironment
	if world_environment == null:
		world_environment = WorldEnvironment.new()
		world_environment.name = "ArenaWorldEnvironment"
		environment_root.add_child(world_environment)
	if world_environment.environment == null:
		world_environment.environment = Environment.new()
	var environment: Environment = world_environment.environment
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#ffffff")
	environment.ambient_light_energy = Tuning.VIS_AMBIENT_ENERGY
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.fog_enabled = false
	environment.glow_enabled = false
	var sky: Sky = environment.sky
	if sky == null:
		sky = Sky.new()
	var sky_material: ShaderMaterial = sky.sky_material as ShaderMaterial
	if sky_material == null:
		sky_material = ShaderMaterial.new()
	sky_material.shader = preload("res://scripts/view/void_sky.gdshader")
	sky_material.set_shader_parameter("upper_tone", SKY_UPPER_TONE)
	sky_material.set_shader_parameter("lower_tone", SKY_LOWER_TONE)
	sky.sky_material = sky_material
	environment.sky = sky
	var sun: DirectionalLight3D = environment_root.get_node_or_null("ArenaDirectionalLight") as DirectionalLight3D
	if sun == null:
		sun = DirectionalLight3D.new()
		sun.name = "ArenaDirectionalLight"
		environment_root.add_child(sun)
	sun.rotation_degrees = Vector3(Tuning.LIGHT_PITCH, Tuning.LIGHT_YAW, 0.0)
	sun.light_color = Color("#ffffff")
	sun.light_energy = Tuning.VIS_SUN_ENERGY
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 100.0
	sun.light_angular_distance = 0.0

func animate(_delta: float, _time: float) -> void:
	pass
