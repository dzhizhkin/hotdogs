class_name SausagePuppet
extends Node3D

## Сосиска соперника с именем над головой.
## Положение приходит по сети ~20 раз в секунду, между пакетами сглаживаем.

const STAND_Y := 1.17
const SAUSAGE_RADIUS := 0.22
const SAUSAGE_LENGTH := 1.8
const STEP_RATE := 16.0
const OUTLINE_COLOR := Color(0.16, 0.07, 0.05)
const SAUSAGE_COLOR := Color(0.86, 0.34, 0.22)

## Точка под ногами по последнему пакету
var feet := Vector3.ZERO

var _heading := 0.0
var _pace := 0.0
var _on_floor := true
var _phase := 0.0
var _has_state := false
var _shove_pose_left := 0.0
var _shove_direction := Vector3.ZERO

var _model: Node3D
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _label: Label3D


func _init(nick: String, color := SAUSAGE_COLOR) -> void:
	_build(color)
	_label.text = nick


func set_nick(nick: String) -> void:
	_label.text = nick


func show_shoulder_windup(direction: Vector3) -> void:
	_shove_direction = direction
	_shove_pose_left = RaceShoulderChecks.WINDUP_TIME + RaceShoulderChecks.FOLLOW_THROUGH_TIME


static func animate_shove(model: Node3D, arms: Array[Node3D], direction: Vector3, time_left: float) -> void:
	var follow_through := RaceShoulderChecks.FOLLOW_THROUGH_TIME
	var elapsed := RaceShoulderChecks.WINDUP_TIME + follow_through - time_left
	var weight := minf(smoothstep(0.0, 0.08, elapsed), smoothstep(0.0, 0.12, time_left))
	var thrust := smoothstep(0.07, follow_through, time_left) * (1.0 - smoothstep(follow_through, follow_through + 0.08, time_left))
	if weight > 0.0:
		var heading := atan2(direction.x, direction.z)
		var lean := lerpf(-0.12, 0.32, thrust)
		var pose := Quaternion(Vector3.UP, heading) * Quaternion(Vector3.RIGHT, lean)
		model.quaternion = model.quaternion.slerp(pose, weight)
		model.position += direction * (0.28 * thrust * weight)
	for index in arms.size():
		var arm := arms[index]
		var side := -1.0 if index == 0 else 1.0
		arm.rotation.x = lerpf(arm.rotation.x, lerpf(0.62, -1.72, thrust), weight)
		arm.rotation.z = side * lerpf(0.5, 0.12, weight * thrust)
		arm.scale.y = 1.0 + 0.35 * weight * thrust


## state: [позиция ног, курс, темп бега, на земле]
func apply_state(state: Array) -> void:
	if state.size() < 4:
		return
	feet = state[0]
	_heading = state[1]
	_pace = state[2]
	_on_floor = state[3]
	if not _has_state:
		_has_state = true
		position = feet
	visible = true


func _process(delta: float) -> void:
	if not _has_state:
		visible = false
		return
	var k := 1.0 - exp(-15.0 * delta)
	# Возрождение — прыжок через полкарты, его не сглаживаем
	position = feet if position.distance_to(feet) > 4.0 else position.lerp(feet, k)
	var amount := minf(_pace, 1.0) if _on_floor else 0.0
	_phase += delta * STEP_RATE * minf(_pace, 1.3)

	_model.position = Vector3.UP * (STAND_Y + absf(sin(_phase)) * 0.16 * amount)
	var target := Quaternion(Vector3.UP, _heading) * Quaternion(Vector3.RIGHT, 0.15 * minf(_pace, 1.0))
	_shove_pose_left = maxf(0.0, _shove_pose_left - delta)
	_label.modulate = Color("#ffd584") if _shove_pose_left > RaceShoulderChecks.FOLLOW_THROUGH_TIME else Color.WHITE
	_model.quaternion = _model.quaternion.slerp(target, k)
	if _on_floor:
		var swing := sin(_phase) * 0.9 * amount
		_legs[0].rotation.x = swing
		_legs[1].rotation.x = -swing
		_arms[0].rotation.x = -swing
		_arms[1].rotation.x = swing
	else:
		_legs[0].rotation.x = 0.4
		_legs[1].rotation.x = -0.4
		for arm in _arms:
			arm.rotation.x = -2.2
	animate_shove(_model, _arms, _shove_direction, _shove_pose_left)


func _build(color: Color) -> void:
	_model = Node3D.new()
	add_child(_model)

	var body := CapsuleMesh.new()
	body.radius = SAUSAGE_RADIUS
	body.height = SAUSAGE_LENGTH
	body.radial_segments = 24
	body.rings = 8
	_mesh(_model, body, _toon(color))

	var white := _toon(Color.WHITE, false)
	var black := _toon(Color(0.05, 0.03, 0.03), false)
	var eye_mesh := _sphere(0.095)
	var pupil_mesh := _sphere(0.05)
	for side in [-1.0, 1.0]:
		var eye := _mesh(_model, eye_mesh, white, Vector3(0.09 * side, 0.55, 0.17))
		_mesh(eye, pupil_mesh, black, Vector3(0.0, 0.0, 0.065))
	_mesh(_model, _sphere(0.055), _toon(Color(0.35, 0.05, 0.08), false), Vector3(0.0, 0.33, 0.21)) \
		.scale = Vector3(1.3, 0.9, 0.5)

	var limb_mat := _toon(color.darkened(0.15))
	var glove_mat := _toon(Color.WHITE)
	var leg_mesh := CapsuleMesh.new()
	leg_mesh.radius = 0.04
	leg_mesh.height = 0.4
	leg_mesh.radial_segments = 16
	leg_mesh.rings = 4
	var shoe_mesh := _sphere(0.07)
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(0.09 * side, -0.75, 0.0)
		_model.add_child(leg)
		_mesh(leg, leg_mesh, limb_mat, Vector3(0.0, -0.18, 0.0))
		_mesh(leg, shoe_mesh, glove_mat, Vector3(0.0, -0.38, 0.04)).scale = Vector3(1.0, 0.6, 1.5)
		_legs.append(leg)

	var arm_mesh := CapsuleMesh.new()
	arm_mesh.radius = 0.035
	arm_mesh.height = 0.35
	arm_mesh.radial_segments = 16
	arm_mesh.rings = 4
	var hand_mesh := _sphere(0.06)
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(0.21 * side, -0.05, 0.0)
		arm.rotation.z = 0.5 * side
		_model.add_child(arm)
		_mesh(arm, arm_mesh, limb_mat, Vector3(0.0, -0.15, 0.0))
		_mesh(arm, hand_mesh, glove_mat, Vector3(0.0, -0.33, 0.0))
		_arms.append(arm)

	_label = Label3D.new()
	_label.position.y = STAND_Y + SAUSAGE_LENGTH * 0.5 + 0.45
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0012
	_label.font_size = 28
	_label.outline_size = 8
	_label.outline_modulate = Color(0.2, 0.05, 0.03)
	add_child(_label)


func _toon(color: Color, outline := true) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.specular_mode = BaseMaterial3D.SPECULAR_TOON
	mat.roughness = 0.55
	if outline:
		var line := StandardMaterial3D.new()
		line.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		line.albedo_color = OUTLINE_COLOR
		line.cull_mode = BaseMaterial3D.CULL_FRONT
		line.grow = true
		line.grow_amount = 0.018
		mat.next_pass = line
	return mat


func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	return mesh


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	parent.add_child(node)
	return node
