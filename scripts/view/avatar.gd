class_name AvatarView
extends Node3D

var player_id: int = -1
var _color := Color.WHITE
var _rig: Node3D
var _left_hand: Node3D
var _right_hand: Node3D
var _material: ShaderMaterial
var _impact: float = 0.0
var _landing: float = 0.0
var _grounded: bool = true
var _built: bool = false

func setup(id: int, color: Color, label: String) -> void:
	player_id = id
	_color = color
	if _built:
		_material.set_shader_parameter("body_color", _color)

func _ready() -> void:
	_build()

func _build() -> void:
	if _built:
		return
	_built = true
	_rig = Node3D.new()
	add_child(_rig)
	_material = ShaderMaterial.new()
	_material.shader = preload("res://scripts/view/avatar_toon.gdshader")
	_material.set_shader_parameter("body_color", _color)
	var outline := ShaderMaterial.new()
	outline.shader = preload("res://scripts/view/outline.gdshader")
	outline.set_shader_parameter("outline_width", 2.0)
	_material.next_pass = outline
	_capsule(_rig, Vector3(0.0, 0.0, 0.0), 0.37, 1.35, _material)
	var visor_mesh := BoxMesh.new()
	visor_mesh.size = Vector3(0.42, 0.22, 0.16)
	var visor := MeshInstance3D.new()
	visor.mesh = visor_mesh
	visor.material_override = _material
	visor.position = Vector3(0.0, 0.26, -0.39)
	_rig.add_child(visor)
	_left_hand = _capsule(_rig, Vector3(-0.48, -0.12, -0.04), 0.16, 0.32, _material)
	_right_hand = _capsule(_rig, Vector3(0.48, -0.12, -0.04), 0.16, 0.32, _material)

func _capsule(parent: Node3D, at: Vector3, radius: float, height: float, material: Material) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	mesh.rings = 6
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = at
	parent.add_child(node)
	return node

func render_state(state: Dictionary, delta: float, time: float) -> void:
	if not _built:
		_build()
	position = state.get("position", Vector3.ZERO)
	visible = int(state.get("stocks", 1)) > 0
	if not visible:
		return
	rotation.y = float(state.get("yaw", 0.0))
	var velocity: Vector3 = state.get("velocity", Vector3.ZERO)
	var local_velocity: Vector3 = Basis(Vector3.UP, -rotation.y) * velocity
	var grounded: bool = state.get("on_ground", true)
	if grounded and not _grounded:
		_landing = 1.0
	_grounded = grounded
	_landing = move_toward(_landing, 0.0, delta * Tuning.VIS_ANIMATION_SPEED)
	_impact = move_toward(_impact, 0.0, delta * Tuning.VIS_ANIMATION_SPEED * 0.5)
	var blend: float = 1.0 - exp(-delta * Tuning.VIS_ANIMATION_SPEED)
	var stretch: float = Tuning.VIS_JUMP_STRETCH * clampf(velocity.y / maxf(1.0, Tuning.JUMP_SPEED), -0.5, 1.0) if not grounded else 0.0
	var squash: float = _landing * Tuning.VIS_LAND_SQUASH
	_rig.scale = _rig.scale.lerp(Vector3(1.0 - stretch * 0.35 + squash * 0.5, 1.0 + stretch - squash, 1.0 - stretch * 0.35 + squash * 0.5), blend)
	var wobble: float = sin(time * Tuning.VIS_HIT_FREQUENCY) * _impact * Tuning.VIS_HIT_WOBBLE
	var lean := Vector3(local_velocity.z * Tuning.VIS_LEAN, 0.0, -local_velocity.x * Tuning.VIS_LEAN)
	lean.x += wobble
	lean.z += wobble
	if float(state.get("hitstun", 0.0)) > 0.0 and not grounded:
		lean.z += sin(time * Tuning.VIS_TUMBLE_RATE) * Tuning.VIS_HIT_WOBBLE * 2.0
	_rig.rotation = _rig.rotation.lerp(lean, blend)
	var speed: float = Vector2(velocity.x, velocity.z).length()
	var stride: float = sin(time * speed * Tuning.VIS_STRIDE_RATE) * Tuning.VIS_STRIDE_AMOUNT if grounded else 0.0
	var attack: float = float(state.get("attack_time", 0.0))
	var reach: float = 0.0
	if attack > Tuning.SHOVE_ACTIVE:
		reach = -Tuning.VIS_WINDUP_PULL * (1.0 - (attack - Tuning.SHOVE_ACTIVE) / maxf(0.001, Tuning.SHOVE_WINDUP))
	elif attack > 0.0:
		reach = Tuning.VIS_PUNCH_REACH * sin(PI * clampf(1.0 - attack / maxf(0.001, Tuning.SHOVE_ACTIVE), 0.0, 1.0))
	_left_hand.position.z = lerpf(_left_hand.position.z, -0.04 - reach - stride * 0.5, blend)
	_right_hand.position.z = lerpf(_right_hand.position.z, -0.04 - reach + stride * 0.5, blend)
	_left_hand.position.y = -0.12 + maxf(0.0, reach) * 0.3
	_right_hand.position.y = _left_hand.position.y
	_rig.visible = float(state.get("invuln", 0.0)) <= 0.0 or int(time * Tuning.VIS_INVULN_RATE) % 2 == 0

func react(event: Dictionary) -> void:
	if int(event.get("player", -1)) != player_id:
		return
	match String(event.get("type", "")):
		"hit":
			_impact = 1.0
		"land":
			_landing = 1.0
		"ko":
			_impact = 0.0
			_landing = 0.0
