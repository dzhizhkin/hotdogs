class_name RaceBot
extends RaceRunner

enum Difficulty { NO_BOTS, EASY, NORMAL, HARD }

const DIFFICULTY_NAMES := ["Без ботов", "Легко", "Средне", "Сложно"]
const NAMES := ["Чили", "Паприка", "Карри"]
const COLORS := [Color("#c45150"), Color("#bf754b"), Color("#d4a541")]
const LANES := [-1.35, 1.35, -2.45]
const SPEEDS := [0.0, 3.90, 4.95, 5.8]
const SPINNER_LOOKAHEAD := [0.0, 0.15, 0.22, 0.30]
const START_DELAYS := [0.0, 0.7, 0.35, 0.0]
const RESPAWN_DELAYS := [0.0, 0.85, 0.45, 0.08]
const FLIGHT_TIME := 2.0 * JUMP_SPEED / GRAVITY

var racer_name: String
var racer_color: Color
var shadow: MeshInstance3D

var _track: RaceTrack
var _puppet: SausagePuppet
var _speed: float
var _disc_speed: float
var _lane: float
var _landing := Vector3.INF
var _checkpoint: Vector3
var _leg_index := 0
var _next_checkpoint := 0
var _wait: float
var _difficulty: Difficulty
var _heading: float
var _shove_target := 0
var _shove_reaction_left := 0.0


func configure(track: RaceTrack, difficulty: Difficulty, slot: int) -> void:
	_track = track
	_difficulty = difficulty
	_speed = SPEEDS[difficulty] - slot * 0.08
	_disc_speed = clampf(_speed, 4.35, SPRINT_SPEED)
	_lane = LANES[slot]
	_wait = START_DELAYS[difficulty] + slot * (0.08 if difficulty == Difficulty.HARD else 0.13)
	_heading = track.spawn_heading
	racer_name = NAMES[slot]
	racer_color = COLORS[slot]
	position = track.spawn_point + Vector3(0.0, 0.0, _lane)
	_checkpoint = position
	collision_layer = 0
	_puppet = SausagePuppet.new(racer_name, racer_color)
	add_child(_puppet)
	_pose(true)


func advance(delta: float, racers: Array[RaceRunner], look_for_shoulder: bool) -> void:
	_wait -= delta
	if _wait > 0.0:
		step(delta, Vector3.ZERO, false, _track)
	else:
		_navigate(delta, racers, look_for_shoulder)
	if global_position.y < RaceTrack.FALL_Y:
		teleport(_checkpoint)
		_landing = Vector3.INF
		_wait = RESPAWN_DELAYS[_difficulty]
	_pose(is_on_floor())
	var ground_y := ground_below()
	shadow.visible = not is_nan(ground_y)
	if shadow.visible:
		var height := global_position.y - ground_y
		var radius := 0.3 * clampf(0.9 - height / 3.0, 0.4, 1.0)
		shadow.position.y = 0.02 - height
		shadow.scale = Vector3(radius, 1.0, radius)


func show_shoulder_windup(direction: Vector3) -> void:
	_puppet.show_shoulder_windup(direction)


func wants_shoulder_check(delta: float, target_id: int) -> bool:
	if _wait > 0.0 or horizontal_velocity.length_squared() < WALK_SPEED * WALK_SPEED:
		target_id = 0
	if _shove_target != target_id:
		_shove_target = target_id
		_shove_reaction_left = 0.34
	_shove_reaction_left -= delta
	return target_id != 0 and _shove_reaction_left <= 0.0


func _navigate(delta: float, racers: Array[RaceRunner], look_for_shoulder: bool) -> void:
	var grounded := is_on_floor()
	if _landing != Vector3.INF:
		if not grounded:
			step(delta, _toward(_landing, _disc_speed), false, _track)
			return
		_landing = Vector3.INF

	var leg := _track.legs[_leg_index]
	var feet := leg.frame.to_local(global_position)
	var turning := _leg_index < _track.legs.size() - 1
	if turning and grounded and feet.x >= leg.length - 0.65:
		_checkpoint = leg.frame.to_global(Vector3(leg.length, leg.top, 0.0))
		_leg_index += 1
		_next_checkpoint = 0
		leg = _track.legs[_leg_index]
		feet = leg.frame.to_local(global_position)
		turning = _leg_index < _track.legs.size() - 1

	var floor_hit := get_last_slide_collision() if grounded else null
	var disc_body := floor_hit.get_collider() as AnimatableBody3D if floor_hit != null else null
	if grounded and disc_body == null:
		_remember_checkpoint(leg, feet.x)
	for crossing in leg.crossings:
		if feet.x >= crossing.takeoff_x - 2.4 and feet.x < crossing.landing_x:
			var disc := crossing.bodies.find(disc_body) if disc_body != null else -1
			_cross_discs(delta, leg, crossing, disc, feet)
			return

	if not turning and feet.x > leg.length - 3.0:
		step(delta, _toward(Vector3.ZERO, _speed), false, _track)
		return

	var lane := _lane
	var jump := false
	var on_jump_run := false
	for run in leg.jump_runs:
		if feet.x < run.edges[0].x - 4.5 or feet.x > run.lane_end:
			continue
		on_jump_run = true
		lane *= run.lane_scale
		if grounded:
			for edge in run.edges:
				if feet.x >= edge.x - 0.42 and feet.x <= edge.x + 0.2 and absf(feet.y - edge.y) < 0.18:
					jump = true
					break
		break
	if turning:
		# К повороту смещаемся к середине площадки, чтобы не срезать над пропастью.
		lane *= clampf((leg.length - feet.x) / 5.0, 0.0, 1.0)
	var near_spinner := _track.near_spinner(global_position)
	if look_for_shoulder and can_shoulder_check() and not on_jump_run and not near_spinner and feet.x < leg.length - 3.0:
		lane = _shoulder_lane(racers, leg, feet, lane)
	var heading := Vector3(1.0, 0.0, clampf(lane - feet.z, -0.9, 0.9)).normalized()
	var desired := leg.frame.global_basis * heading * _speed
	if grounded and not jump and near_spinner:
		jump = _anticipate_spinner(desired)
	step(delta, desired, jump, _track)


func _shoulder_lane(racers: Array[RaceRunner], leg: RaceTrack.Leg, feet: Vector3, lane: float) -> float:
	var nearest := 2.5 * 2.5
	for rival in racers:
		if rival == self or not rival.can_shoulder_check():
			continue
		var target := leg.frame.to_local(rival.global_position)
		var offset := target - feet
		if offset.x < 0.25 or absf(offset.z) > 1.6 or absf(offset.y) > RaceShoulderChecks.MAX_HEIGHT_DIFFERENCE:
			continue
		var distance := offset.length_squared()
		if distance < nearest:
			nearest = distance
			lane = clampf(target.z, -RaceTrack.WIDTH * 0.3, RaceTrack.WIDTH * 0.3)
	return lane


func _cross_discs(delta: float, leg: RaceTrack.Leg, crossing: RaceTrack.DiscCrossing, current_disc: int, feet: Vector3) -> void:
	var staging := Vector3(crossing.takeoff_x, leg.top, signf(_lane) * 1.25)
	if current_disc >= 0:
		staging = crossing.center_at(current_disc, _track.time) + Vector3.RIGHT * 0.75

	var target := Vector3(crossing.landing_x + 0.55, leg.top, feet.z)
	var tolerance := 0.25
	var last_disc := current_disc == crossing.bodies.size() - 1
	if not last_disc:
		target = crossing.center_at(current_disc + 1, _track.time + FLIGHT_TIME) - Vector3.RIGHT * 0.45
		tolerance = RaceTrack.DISC_RADIUS - 0.75

	var launch_margin := 0.65 if _difficulty == Difficulty.HARD else 0.20
	var offset := leg.frame.global_basis * (target - feet)
	if is_on_floor() and feet.x >= staging.x - launch_margin and _can_reach(offset, tolerance):
		# На выходе можно приземлиться дальше от края и сохранить скорость.
		if last_disc and _difficulty == Difficulty.HARD:
			target.x = maxf(target.x, feet.x + _disc_speed * FLIGHT_TIME)
		_landing = leg.frame.to_global(target)
		step(delta, _toward(_landing, _disc_speed), true, _track)
		return

	step(delta, _toward(leg.frame.to_global(staging), _speed, 3.2), false, _track)


func _can_reach(offset: Vector3, tolerance: float) -> bool:
	offset.y = 0.0
	# Пока бот разгоняется в воздухе, он пролетает меньше, чем на полной скорости.
	var speed_to_gain := _disc_speed - clampf(horizontal_velocity.dot(offset.normalized()), 0.0, _disc_speed)
	var reach := _disc_speed * FLIGHT_TIME - speed_to_gain * speed_to_gain / (2.0 * ACCELERATION * AIR_CONTROL)
	return offset.length() <= reach + tolerance


func _anticipate_spinner(desired: Vector3) -> bool:
	var ahead: float = SPINNER_LOOKAHEAD[_difficulty]
	while ahead >= 0.10:
		if _track.spinner_push(global_position + desired * ahead, ahead) != Vector3.ZERO:
			return true
		ahead -= 0.05
	return false


func _toward(target: Vector3, speed: float, approach := 5.0) -> Vector3:
	var offset := target - global_position
	offset.y = 0.0
	return (offset * approach).limit_length(speed)


func _remember_checkpoint(leg: RaceTrack.Leg, track_x: float) -> void:
	while _next_checkpoint < leg.checkpoints.size() and track_x >= leg.checkpoints[_next_checkpoint].x:
		_checkpoint = leg.frame.to_global(leg.checkpoints[_next_checkpoint])
		_next_checkpoint += 1


func _pose(on_floor: bool) -> void:
	var motion := horizontal_velocity
	if motion.length_squared() > 0.01:
		_heading = atan2(motion.x, motion.z)
	_puppet.apply_state([Vector3.ZERO, _heading, pace, on_floor])
