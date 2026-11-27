class_name RaceRunner
extends CharacterBody3D

const WALK_SPEED := 3.2
const SPRINT_SPEED := 5.5
const JUMP_SPEED := 8.0
const GRAVITY := 20.0
const STAND_Y := 1.17

const ACCELERATION := 14.0
const AIR_CONTROL := 0.6
const COYOTE_TIME := 0.12
const FINISH_RADIUS := 3.2
const RESPAWN_PROTECTION := 1.0
const SPINNER_KNOCK_DECAY := 5.0
const SHOVE_KNOCK_DECAY := 16.0

var pace: float:
	get:
		return horizontal_velocity.length() / WALK_SPEED
var horizontal_velocity: Vector3:
	get:
		return _move_velocity + _knock
var jumped := false
var bumped := false
var fall_speed := 0.0

var _move_velocity := Vector3.ZERO
var _knock := Vector3.ZERO
var _knock_decay := SPINNER_KNOCK_DECAY
var _push_cooldown := 0.0
var _shoulder_protection := 0.0
var _shoulder_hit := Vector3.ZERO
var _coyote := 0.0
var _ground_ray := PhysicsRayQueryParameters3D.new()


func _init() -> void:
	floor_snap_length = 0.4
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = STAND_Y * 2.0
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = STAND_Y
	add_child(collider)
	_ground_ray.exclude = [get_rid()]


func step(delta: float, desired_velocity: Vector3, jump: bool, track: RaceTrack) -> void:
	var on_floor := is_on_floor()
	var control := 1.0 if on_floor else AIR_CONTROL
	_move_velocity = _move_velocity.move_toward(desired_velocity, ACCELERATION * control * delta)
	_knock = _knock.move_toward(Vector3.ZERO, _knock_decay * delta)

	_coyote = COYOTE_TIME if on_floor else _coyote - delta
	# Прижимаемся к полу, чтобы регистрировать опору даже стоя на месте.
	var vertical := -1.0 if on_floor else velocity.y - GRAVITY * delta
	jumped = jump and _coyote > 0.0
	if jumped:
		vertical = JUMP_SPEED
		_coyote = 0.0

	_push_cooldown -= delta
	_shoulder_protection = maxf(0.0, _shoulder_protection - delta)
	var push := track.spinner_push(global_position)
	bumped = push != Vector3.ZERO and _push_cooldown <= 0.0
	if bumped:
		_push_cooldown = 0.4
		_knock_decay = SPINNER_KNOCK_DECAY
	elif _shoulder_hit != Vector3.ZERO and not jumped and on_floor:
		push = _shoulder_hit
		bumped = true
		_knock_decay = SHOVE_KNOCK_DECAY
		# Сохраняем бег вдоль трассы, но текущий шаг не гасит боковой удар.
		_move_velocity = _move_velocity.slide(Vector3(push.x, 0.0, push.z).normalized())
		_shoulder_protection = RaceShoulderChecks.HIT_IMMUNITY
	if bumped:
		_knock = Vector3(push.x, 0.0, push.z)
		vertical = push.y
	_shoulder_hit = Vector3.ZERO

	fall_speed = -vertical
	velocity = horizontal_velocity + Vector3.UP * vertical
	move_and_slide()


func teleport(spot: Vector3) -> void:
	global_position = spot
	velocity = Vector3.ZERO
	_move_velocity = Vector3.ZERO
	_knock = Vector3.ZERO
	_shoulder_hit = Vector3.ZERO
	_shoulder_protection = RESPAWN_PROTECTION


func can_shoulder_check() -> bool:
	return is_on_floor() and _shoulder_protection <= 0.0 and _shoulder_hit == Vector3.ZERO


func receive_shoulder_hit(impulse: Vector3) -> void:
	if can_shoulder_check():
		_shoulder_hit = impulse


func reached_finish() -> bool:
	var feet := global_position
	return is_on_floor() and absf(feet.y) < 0.2 and Vector2(feet.x, feet.z).length() < FINISH_RADIUS


func ground_below() -> float:
	_ground_ray.from = global_position + Vector3.UP * 0.5
	_ground_ray.to = _ground_ray.from + Vector3.DOWN * 30.0
	var hit := get_world_3d().direct_space_state.intersect_ray(_ground_ray)
	return (hit.position as Vector3).y if hit else NAN
