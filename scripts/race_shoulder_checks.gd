class_name RaceShoulderChecks
extends RefCounted

signal windup(attacker_id: int, target_id: int, direction: Vector3)
signal hit(attacker_id: int, target_id: int, impulse: Vector3)

const WINDUP_TIME := 0.30
const FOLLOW_THROUGH_TIME := 0.22
const INPUT_BUFFER := 0.18
const COOLDOWN := 4.0
const HIT_IMMUNITY := 0.9
const MAX_HEIGHT_DIFFERENCE := 0.32
const REACH := 3.2
const CONTACT_REACH := REACH + 0.9
const SIDE_IMPULSE := 10.5
const LIFT_IMPULSE := 3.4

class Racer:
	var feet: Vector3
	var heading: float
	var sampled_msec := Time.get_ticks_msec()

	func _init(position: Vector3, facing: float) -> void:
		feet = position
		heading = facing

class Attempt:
	var target_id: int
	var contact_time: float
	var direction: Vector3

	func _init(target: int, contact: float, aim: Vector3) -> void:
		target_id = target
		contact_time = contact
		direction = aim

var _time := 0.0
var _attempts: Dictionary[int, Attempt] = {}
var _ready_at: Dictionary[int, float] = {}
var _protected_until: Dictionary[int, float] = {}


func reset() -> void:
	_time = 0.0
	_attempts.clear()
	_ready_at.clear()
	_protected_until.clear()


func can_try(attacker_id: int) -> bool:
	return _attempts.has(attacker_id) or _ready_at.get(attacker_id, 0.0) <= _time


func nearest_target(attacker_id: int, racers: Dictionary[int, Racer]) -> int:
	var attacker: Racer = racers.get(attacker_id)
	if attacker == null or _protected(attacker_id) or _ready_at.get(attacker_id, 0.0) > _time:
		return 0
	var target_id := 0
	var nearest := REACH * REACH
	for rival_id in racers:
		if rival_id == attacker_id or _protected(rival_id):
			continue
		var offset := racers[rival_id].feet - attacker.feet
		var distance := Vector2(offset.x, offset.z).length_squared()
		if absf(offset.y) <= MAX_HEIGHT_DIFFERENCE and distance <= nearest:
			target_id = rival_id
			nearest = distance
	return target_id


func try_start(attacker_id: int, racers: Dictionary[int, Racer]) -> bool:
	var target_id := nearest_target(attacker_id, racers)
	if target_id == 0:
		return false
	var direction := _flat_offset(racers[attacker_id], racers[target_id]).normalized()
	if direction.is_zero_approx():
		var heading := racers[attacker_id].heading
		direction = Vector3(sin(heading), 0.0, cos(heading))
	_attempts[attacker_id] = Attempt.new(target_id, _time + WINDUP_TIME, direction)
	_ready_at[attacker_id] = _time + COOLDOWN
	windup.emit(attacker_id, target_id, direction)
	return true


## В выборку попадают только бегуны на земле без защиты после возрождения.
func advance(delta: float, racers: Dictionary[int, Racer], track: RaceTrack) -> void:
	_time += delta
	for attacker_id in _attempts.keys():
		var attempt := _attempts[attacker_id]
		if attempt.contact_time > _time:
			continue
		_attempts.erase(attacker_id)
		var attacker: Racer = racers.get(attacker_id)
		var target: Racer = racers.get(attempt.target_id)
		if attacker == null or target == null or _protected(attacker_id) or _protected(attempt.target_id):
			continue
		var offset := _flat_offset(attacker, target)
		# На бегу допускаем небольшой разрыв после замаха. Прыжок убирает цель из выборки.
		if offset.length_squared() <= CONTACT_REACH * CONTACT_REACH \
				and absf(target.feet.y - attacker.feet.y) <= MAX_HEIGHT_DIFFERENCE:
			var side := track.side_at(target.feet)
			if attempt.direction.dot(side) < -0.1:
				side = -side
			var impulse := (side + attempt.direction * 0.14).normalized() * SIDE_IMPULSE
			_protected_until[attempt.target_id] = _time + HIT_IMMUNITY
			hit.emit(attacker_id, attempt.target_id, impulse + Vector3.UP * LIFT_IMPULSE)


func _protected(racer_id: int) -> bool:
	return _protected_until.get(racer_id, 0.0) > _time


func _flat_offset(attacker: Racer, target: Racer) -> Vector3:
	var offset := target.feet - attacker.feet
	return Vector3(offset.x, 0.0, offset.z)
