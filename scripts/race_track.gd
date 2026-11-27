class_name RaceTrack
extends Node3D

## Трасса собирается по общему зерну генерации. У каждого участка свои координаты и направление.

enum Obstacle { STAIRS, STAGGERED, SPINNER, DISCS }

class JumpRun:
	var edges := PackedVector2Array()
	var lane_scale := 1.0
	var lane_end: float

class Spinner:
	var arm: Node3D
	var phase: float
	var speed: float

	func angle_at(time: float) -> float:
		return phase + time * speed

class DiscCrossing:
	var takeoff_x: float
	var landing_x: float
	var bodies: Array[AnimatableBody3D] = []
	var centers: Array[Vector3] = []
	var phase: float
	var speed: float
	var amplitude: float

	func center_at(index: int, time: float) -> Vector3:
		var offset := sin(time * speed + phase + index * PI) * amplitude
		return centers[index] + Vector3(0.0, 0.0, offset)

class Leg:
	var frame := Node3D.new()
	var length: float
	var start_distance: float
	var top: float
	var jump_runs: Array[JumpRun] = []
	var crossings: Array[DiscCrossing] = []
	var checkpoints := PackedVector3Array()

const WIDTH := 8.0
const THICKNESS := 0.6
const FALL_Y := -8.0
const TABLE_EDGE := -8.0
const SPAWN_X := 4.0
const TURN_RADIUS := 5.1

# Вращающаяся палка на пицце
const PIZZA_RADIUS := 5.5
const SPINNER_LENGTH := 10.0
const SPINNER_RADIUS := 0.35
const SPINNER_HEIGHT := 0.6
const SPINNER_PUSH := 7.0

# Огурцы, которые ездят поперёк трассы
const DISC_RADIUS := 2.0

const OUTLINE_COLOR := Color(0.16, 0.07, 0.05)

var layout_seed := 0
var spawn_point := Vector3.ZERO
var spawn_heading := PI * 0.5
var time := 0.0
var legs: Array[Leg] = []

var _spinners: Array[Spinner] = []
var _rng := RandomNumberGenerator.new()


func _init(seed_value: int, elapsed: float) -> void:
	layout_seed = seed_value
	time = elapsed
	_rng.seed = layout_seed
	_build()
	_move_parts()


func _ready() -> void:
	spawn_point = legs[0].frame.to_global(Vector3(SPAWN_X, 0.0, 0.0))


func _physics_process(delta: float) -> void:
	time += delta
	_move_parts()


func progress_at(feet: Vector3) -> float:
	var leg := _nearest_leg(feet)
	var point := leg.frame.to_local(feet)
	return leg.start_distance + clampf(point.x, 0.0, _leg_limit(leg))


func side_at(feet: Vector3) -> Vector3:
	return _nearest_leg(feet).frame.global_basis.z


func _nearest_leg(feet: Vector3) -> Leg:
	var closest := legs[0]
	var nearest := INF
	for leg in legs:
		var point := leg.frame.to_local(feet)
		var along := clampf(point.x, 0.0, _leg_limit(leg))
		var distance := Vector2(point.x - along, point.z).length_squared()
		if distance < nearest:
			nearest = distance
			closest = leg
	return closest


func _leg_limit(leg: Leg) -> float:
	return leg.length - TABLE_EDGE if leg == legs.back() else leg.length


func near_spinner(feet: Vector3) -> bool:
	for spinner in _spinners:
		var offset := feet - spinner.arm.global_position
		if Vector2(offset.x, offset.z).length_squared() < (PIZZA_RADIUS + 1.0) ** 2:
			return true
	return false


## Толчок от вращающейся палки для бегуна в точке feet в мировых координатах.
func spinner_push(feet: Vector3, ahead := 0.0) -> Vector3:
	for spinner in _spinners:
		var rel := feet - spinner.arm.global_position + Vector3.UP * SPINNER_HEIGHT
		if absf(rel.x) > PIZZA_RADIUS or absf(rel.z) > PIZZA_RADIUS:
			continue
		if rel.y < -0.5 or rel.y > SPINNER_HEIGHT + SPINNER_RADIUS:
			continue
		var angle := spinner.angle_at(time + ahead) + spinner.arm.get_parent_node_3d().global_rotation.y
		var axis := Vector3(cos(angle), 0.0, -sin(angle))
		var flat := Vector3(rel.x, 0.0, rel.z)
		var along := flat.dot(axis)
		if absf(along) > SPINNER_LENGTH * 0.5:
			continue
		var side := flat - axis * along
		if side.length() > SPINNER_RADIUS + 0.35:
			continue
		# Скорость точки палки ω × r; толкает только та сторона, что едет на бегуна.
		var tangent := Vector3.UP.cross(axis * along) * spinner.speed
		if side.dot(tangent) < 0.0:
			continue
		var dir := tangent.normalized() if tangent.length() > 0.5 else side.normalized()
		return dir * (SPINNER_PUSH + tangent.length()) + Vector3.UP * 5.0
	return Vector3.ZERO


func _move_parts() -> void:
	for spinner in _spinners:
		spinner.arm.rotation.y = spinner.angle_at(time)
	for leg in legs:
		for crossing in leg.crossings:
			for index in crossing.bodies.size():
				crossing.bodies[index].position = crossing.center_at(index, time) - Vector3.UP * THICKNESS * 0.5


# --- Построение ---

func _build() -> void:
	var wood := _toon(Color(0.74, 0.52, 0.32))
	var cheese := _toon(Color(1.0, 0.8, 0.25))
	var bread := _toon(Color(0.93, 0.7, 0.4))
	var toast := _toon(Color(0.74, 0.38, 0.2))
	var pizza := _toon(Color(0.96, 0.62, 0.26))
	var cucumber := _toon(Color(0.45, 0.76, 0.32))

	var order: Array[Obstacle] = [
		Obstacle.STAIRS, Obstacle.STAGGERED, Obstacle.SPINNER, Obstacle.SPINNER, Obstacle.DISCS, Obstacle.DISCS,
	]
	order.append(Obstacle.STAIRS if _rng.randf() < 0.5 else Obstacle.STAGGERED)
	for i in range(order.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var obstacle := order[i]
		order[i] = order[j]
		order[j] = obstacle

	var side := -1.0 if _rng.randf() < 0.5 else 1.0
	var angles := [0.0, side * _rng.randf_range(0.45, 0.72), -side * _rng.randf_range(0.45, 0.72), 0.0]
	var low := _rng.randf_range(2.5, 3.8)
	var high := _rng.randf_range(4.8, 6.3)
	var levels := [0.0, low, high, 0.0] if _rng.randf() < 0.5 else [0.0, high, low, 0.0]
	var short_leg := _rng.randi_range(0, angles.size() - 1)

	var junction := Vector3.ZERO
	var distance := 0.0
	var obstacle_index := 0
	for i in angles.size():
		var leg := Leg.new()
		leg.frame.position = junction
		leg.frame.rotation.y = angles[i]
		leg.start_distance = distance
		leg.top = levels[i]
		legs.append(leg)
		add_child(leg.frame)

		var x := 0.0
		if i == 0:
			x = _slab(leg, x, 12.0, 12.0, 0.0, wood)
		else:
			# До первой ступеньки остаётся место, чтобы закончить поворот.
			var previous_top: float = levels[i - 1]
			x = _slab(leg, x, TURN_RADIUS, WIDTH, previous_top, wood)
			x = _build_level_steps(leg, x, previous_top, leg.top, cheese, bread)

		for section in (1 if i == short_leg else 2):
			leg.checkpoints.append(Vector3(x + 1.2, leg.top, 0.0))
			x = _slab(leg, x, _rng.randf_range(4.7, 6.0), WIDTH, leg.top, wood)
			match order[obstacle_index]:
				Obstacle.STAIRS:
					x = _build_stairs(leg, x, cheese, bread)
				Obstacle.STAGGERED:
					x = _build_staggered(leg, x, toast, bread)
				Obstacle.SPINNER:
					x = _build_pizza(leg, x, pizza, bread)
				Obstacle.DISCS:
					x = _build_crossing(leg, x, cucumber)
			obstacle_index += 1

		leg.checkpoints.append(Vector3(x + 1.4, leg.top, 0.0))
		if i == angles.size() - 1:
			leg.length = _slab(leg, x, _rng.randf_range(8.0, 10.0), WIDTH, leg.top, bread)
			_build_finish_arch(leg, leg.length, bread)
		else:
			leg.length = _slab(leg, x, 5.2, WIDTH, leg.top, wood)
			_build_turn(leg, angles[i + 1], bread)

		distance += leg.length
		junction += leg.frame.basis * Vector3(leg.length, 0.0, 0.0)

	# Последний участок ведёт прямо к столу с булочкой при любой форме трассы.
	position = Vector3(TABLE_EDGE, 0.0, 0.0) - junction


func _build_turn(leg: Leg, next_angle: float, mat: Material) -> void:
	var corner := Vector3(leg.length, leg.top, 0.0)
	_disc(leg.frame, StaticBody3D.new(), corner - Vector3.UP * 0.035, TURN_RADIUS, mat)

	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("#a32c27")
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.cull_mode = BaseMaterial3D.CULL_DISABLED
	var arrow := ImmediateMesh.new()
	arrow.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for point in [
		Vector3(-1.1, 0.0, -0.26), Vector3(0.4, 0.0, -0.26), Vector3(0.4, 0.0, 0.26),
		Vector3(-1.1, 0.0, -0.26), Vector3(0.4, 0.0, 0.26), Vector3(-1.1, 0.0, 0.26),
		Vector3(0.32, 0.0, -0.62), Vector3(1.35, 0.0, 0.0), Vector3(0.32, 0.0, 0.62),
	]:
		arrow.surface_add_vertex(point)
	arrow.surface_end()
	var marker := _mesh(leg.frame, arrow, paint, corner + Vector3.UP * 0.025)
	marker.rotation.y = next_angle - leg.frame.rotation.y


func _build_stairs(leg: Leg, x: float, cheese: Material, bread: Material) -> float:
	var run := JumpRun.new()
	leg.jump_runs.append(run)
	var top := leg.top
	for i in _rng.randi_range(3, 4):
		run.edges.append(Vector2(x, top))
		top += _rng.randf_range(0.36, 0.58)
		x += _rng.randf_range(1.55, 1.85)
		leg.checkpoints.append(Vector3(x + 1.3, top, 0.0))
		x = _slab(leg, x, _rng.randf_range(4.6, 6.2), 6.5, top, cheese)
	run.edges.append(Vector2(x, top))
	x += _rng.randf_range(1.55, 1.85)
	leg.checkpoints.append(Vector3(x + 1.3, top, 0.0))
	x = _slab(leg, x, 4.5, WIDTH, top, bread)
	run.lane_end = x
	return _build_level_steps(leg, x, top, leg.top, cheese, bread)


func _build_level_steps(leg: Leg, x: float, from_top: float, to_top: float, cheese: Material, bread: Material) -> float:
	var rising := to_top > from_top
	var count := ceili(absf(to_top - from_top) / (1.05 if rising else 1.25))
	var top := from_top
	var run: JumpRun
	if rising:
		run = JumpRun.new()
		leg.jump_runs.append(run)
	for i in count:
		if rising:
			# Разрыв даёт время набрать высоту до вертикальной грани следующего блока.
			run.edges.append(Vector2(x, top))
			x += _rng.randf_range(1.1, 1.25)
		var next_top := lerpf(from_top, to_top, float(i + 1) / count)
		var depth := absf(next_top - top) + 0.35
		top = next_top
		var length := _rng.randf_range(3.25, 3.55) if rising else _rng.randf_range(2.4, 2.8)
		var mat := cheese if i % 2 == 0 else bread
		leg.checkpoints.append(Vector3(x + 1.1, top, 0.0))
		x = _slab(leg, x, length, WIDTH, top, mat, 0.0, maxf(THICKNESS, depth))
	if rising:
		run.lane_end = x
	return x


func _build_staggered(leg: Leg, x: float, toast: Material, bread: Material) -> float:
	var run := JumpRun.new()
	run.lane_scale = 0.25
	leg.jump_runs.append(run)
	var side := -1.0 if _rng.randf() < 0.5 else 1.0
	for i in _rng.randi_range(3, 4):
		run.edges.append(Vector2(x, leg.top))
		x += _rng.randf_range(1.6, 2.1)
		leg.checkpoints.append(Vector3(x + 1.3, leg.top, 0.0))
		var z := side * _rng.randf_range(1.0, 1.65)
		var mat := bread if i % 2 == 0 else toast
		x = _slab(leg, x, _rng.randf_range(4.8, 6.5), _rng.randf_range(5.1, 5.8), leg.top, mat, z)
		side = -side
	run.edges.append(Vector2(x, leg.top))
	x += _rng.randf_range(1.6, 2.1)
	run.lane_end = x + 1.5
	return x


func _build_pizza(leg: Leg, x: float, pizza: Material, bread: Material) -> float:
	var spinner := Spinner.new()
	var center := Vector3(x + PIZZA_RADIUS - 1.5, leg.top, 0.0)
	spinner.phase = _rng.randf_range(0.0, TAU)
	spinner.speed = _rng.randf_range(1.1, 1.45) * (-1.0 if _rng.randf() < 0.5 else 1.0)
	_spinners.append(spinner)
	_disc(leg.frame, StaticBody3D.new(), center, PIZZA_RADIUS, pizza)
	spinner.arm = _build_spinner(leg.frame, center, bread)
	_build_pepperoni(leg.frame, center)
	# Пицца заходит под подход и выход, включая боковые дорожки вокруг оси.
	return center.x + PIZZA_RADIUS - 1.5


func _build_crossing(leg: Leg, x: float, cucumber: Material) -> float:
	var crossing := DiscCrossing.new()
	crossing.takeoff_x = x - 0.65
	crossing.phase = _rng.randf_range(0.0, TAU)
	crossing.speed = _rng.randf_range(0.95, 1.15)
	crossing.amplitude = _rng.randf_range(1.7, 2.35)
	for i in 2:
		var center := Vector3(x + _rng.randf_range(0.45, 0.7) + DISC_RADIUS, leg.top, 0.0)
		var body := _disc(leg.frame, AnimatableBody3D.new(), center, DISC_RADIUS, cucumber) as AnimatableBody3D
		crossing.bodies.append(body)
		crossing.centers.append(center)
		x = center.x + DISC_RADIUS
	crossing.landing_x = x + _rng.randf_range(0.45, 0.65)
	leg.crossings.append(crossing)
	return crossing.landing_x


func _slab(leg: Leg, from_x: float, length: float, width: float, top: float, mat: Material, z := 0.0, thickness := THICKNESS) -> float:
	var body := StaticBody3D.new()
	body.position = Vector3(from_x + length * 0.5, top - thickness * 0.5, z)
	leg.frame.add_child(body)
	_box(body, Vector3(length, thickness, width), mat)
	return from_x + length


func _disc(parent: Node3D, body: StaticBody3D, center: Vector3, radius: float, mat: Material) -> StaticBody3D:
	body.position = center - Vector3.UP * THICKNESS * 0.5
	parent.add_child(body)
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = THICKNESS
	_collider(body, shape)
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = THICKNESS
	mesh.rings = 0
	_mesh(body, mesh, mat)
	return body


func _build_spinner(parent: Node3D, center: Vector3, mat: Material) -> Node3D:
	# Ось в центре — твёрдая, сама палка только визуальная, толкает её spinner_push
	var hub := StaticBody3D.new()
	hub.position = center + Vector3.UP * 0.6
	parent.add_child(hub)
	var hub_shape := CylinderShape3D.new()
	hub_shape.radius = 0.6
	hub_shape.height = 1.2
	_collider(hub, hub_shape)
	var hub_mesh := CylinderMesh.new()
	hub_mesh.top_radius = 0.5
	hub_mesh.bottom_radius = 0.6
	hub_mesh.height = 1.2
	hub_mesh.radial_segments = 32
	hub_mesh.rings = 0
	_mesh(hub, hub_mesh, _toon(Color(0.88, 0.16, 0.14)))

	var arm := Node3D.new()
	arm.position = center + Vector3.UP * SPINNER_HEIGHT
	parent.add_child(arm)
	var stick := CapsuleMesh.new()
	stick.radius = SPINNER_RADIUS
	stick.height = SPINNER_LENGTH
	stick.radial_segments = 32
	stick.rings = 8
	_mesh(arm, stick, mat).rotation.z = PI * 0.5
	return arm


func _build_pepperoni(parent: Node3D, center: Vector3) -> void:
	var mat := _toon(Color(0.78, 0.18, 0.14), false)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.45
	mesh.bottom_radius = 0.45
	mesh.height = 0.04
	mesh.radial_segments = 24
	mesh.rings = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var positions := PackedVector3Array()
	for i in 14:
		var angle := rng.randf() * TAU
		var dist := sqrt(rng.randf()) * (PIZZA_RADIUS - 0.7)
		positions.append(center + Vector3(cos(angle) * dist, 0.02, sin(angle) * dist))
	_batch_mesh(parent, mesh, mat, positions)


func _build_finish_arch(leg: Leg, finish_x: float, mat: Material) -> void:
	for side in [-1.0, 1.0]:
		var pillar := StaticBody3D.new()
		pillar.position = Vector3(finish_x - 0.5, 2.0, (WIDTH * 0.5 + 0.4) * side)
		leg.frame.add_child(pillar)
		var shape := CylinderShape3D.new()
		shape.radius = 0.35
		shape.height = 4.0
		_collider(pillar, shape)
		var mesh := CapsuleMesh.new()
		mesh.radius = 0.35
		mesh.height = 4.4
		mesh.radial_segments = 32
		mesh.rings = 8
		_mesh(pillar, mesh, mat)

	# Клетчатый баннер «финиш»
	var white := _toon(Color(0.97, 0.95, 0.9), false)
	var red := _toon(Color(0.88, 0.16, 0.14), false)
	var cell := BoxMesh.new()
	var cells := 12
	var width := WIDTH + 0.8
	cell.size = Vector3(0.3, 0.35, width / cells)
	var white_cells := PackedVector3Array()
	var red_cells := PackedVector3Array()
	for row in 2:
		for i in cells:
			var pos := Vector3(finish_x - 0.5, 3.9 - row * 0.35, -width * 0.5 + (i + 0.5) * width / cells)
			if (i + row) % 2 == 0:
				white_cells.append(pos)
			else:
				red_cells.append(pos)
	_batch_mesh(leg.frame, cell, white, white_cells)
	_batch_mesh(leg.frame, cell, red, red_cells)


# --- Хелперы ---

func _box(body: StaticBody3D, size: Vector3, mat: Material) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	_collider(body, shape)
	var mesh := BoxMesh.new()
	mesh.size = size
	_mesh(body, mesh, mat)


func _collider(body: CollisionObject3D, shape: Shape3D) -> void:
	var node := CollisionShape3D.new()
	node.shape = shape
	body.add_child(node)


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	parent.add_child(node)
	return node


func _batch_mesh(parent: Node3D, mesh: Mesh, mat: Material, positions: PackedVector3Array) -> void:
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = mesh
	batch.instance_count = positions.size()
	for i in positions.size():
		batch.set_instance_transform(i, Transform3D(Basis.IDENTITY, positions[i]))
	var node := MultiMeshInstance3D.new()
	node.multimesh = batch
	node.material_override = mat
	parent.add_child(node)


func _toon(color: Color, outline := true) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.specular_mode = BaseMaterial3D.SPECULAR_TOON
	mat.roughness = 0.6
	if outline:
		var line := StandardMaterial3D.new()
		line.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		line.albedo_color = OUTLINE_COLOR
		line.cull_mode = BaseMaterial3D.CULL_FRONT
		line.grow = true
		line.grow_amount = 0.03
		mat.next_pass = line
	return mat
