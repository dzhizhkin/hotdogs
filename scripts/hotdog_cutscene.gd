extends Node3D

## Кат-сцена: мультяшная сосиска подбегает и запрыгивает в булочку,
## затем камера переходит на вид сверху и хот-дог поливают майонезом.
## Вся геометрия строится в коде, внешних ассетов нет.
## В игровом режиме сначала сосиской управляет игрок (вид от 3-го лица),
## а кат-сцена запускается, когда он подбегает к булочке.

signal finished

## Включает управление сосиской до кат-сцены
@export var playable := false

# Тайминги фаз, секунды
const RUN_END := 2.6
const CROUCH_END := 2.9
const JUMP_END := 3.6
const TOP_CUT := 4.6
const BOTTLE_IN_END := 5.3
const POUR_END := 8.4
const BOTTLE_OUT_END := 9.0
const HAPPY_END := 9.8
const FADE_START := 10.2
const END_TIME := 12.5

const RUN_FROM_X := -7.0
const JUMP_FROM_X := -2.4
const JUMP_HEIGHT := 1.6
const STAND_Y := RaceRunner.STAND_Y
const LIE_POS := Vector3(0.0, 0.46, 0.0)
const SAUSAGE_RADIUS := 0.22
const SAUSAGE_LENGTH := 1.8
const BUN_LENGTH := 1.55
const STEP_RATE := 16.0

# Зигзаг майонеза вдоль сосиски (глаза на +X не заливаем)
const MAYO_X_FROM := -0.66
const MAYO_X_TO := 0.1
const MAYO_WAVES := 4.5
const MAYO_AMPLITUDE := 0.17
const MAYO_STEP := 0.022
const MAYO_SAMPLES := 668
const NOZZLE_HEIGHT := 1.1

const BLINKS := [1.2, 4.15, 6.3, 9.3, 9.75]

# Игровой режим
# Возрождение там, где упал: на последней опоре, чуть отступив от края
const RESPAWN_BACKOFF := 1.0
const CAMERA_DISTANCE := 7.0
const MOUSE_SENSITIVITY := 0.004
const START_COUNT := 3

# Кооп
const NET_SEND_INTERVAL := 0.05
const SPAWN_SPREAD := 1.2
const SHOULDER_STATE_TIMEOUT_MS := 300

# Звуки: имя файла в assets/audio/sfx → громкость, дБ
const SFX := {
	"step": -14.0, "jump": -8.0, "land": -9.0, "bonk": -4.0, "fall": -8.0, "pop": -8.0,
	"squish": -4.0, "mayo": -8.0, "giggle": -6.0, "fanfare": -6.0, "whistle": -8.0, "click": -10.0,
	"countdown": -8.0,
}
# Глубже этой высоты сосиска точно летит в пропасть — свистим
const FALL_WHISTLE_Y := -2.0

const OUTLINE_COLOR := Color(0.16, 0.07, 0.05)
const SAUSAGE_COLOR := Color(0.86, 0.34, 0.22)
const BUN_COLOR := Color(0.94, 0.68, 0.36)
const MAYO_COLOR := Color(1.0, 0.98, 0.93)

const GROUND_SHADER := """
shader_type spatial;
render_mode specular_disabled;

uniform vec3 color_a : source_color = vec3(0.85, 0.2, 0.18);
uniform vec3 color_b : source_color = vec3(0.97, 0.94, 0.88);
uniform float cell = 0.6;
uniform float fade_from = 12.0;
uniform float fade_to = 40.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 c = floor(world_pos.xz / cell);
	vec3 col = mix(color_a, color_b, mod(c.x + c.y, 2.0));
	// Вдали клетка сливается в средний цвет, чтобы не было муара
	float fade = smoothstep(fade_from, fade_to, length(VERTEX));
	ALBEDO = mix(col, (color_a + color_b) * 0.5, fade);
	ROUGHNESS = 0.9;
}
"""

var _t := 0.0
var _done := false

var _camera: Camera3D
var _sausage: Node3D
var _sausage_skin: StandardMaterial3D
var _sausage_limbs: StandardMaterial3D
var _eyes: Array[Node3D] = []
var _pupils: Array[MeshInstance3D] = []
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _limbs: Array[Node3D] = []
var _mouth: MeshInstance3D
var _bliss: Node3D
var _happy_eyes: Node3D
var _grin: Node3D
var _bun: Node3D
var _bottle: Node3D
var _bottle_body: MeshInstance3D
var _stream: MeshInstance3D
var _ui: GameInterface
var _last_fps := -1

var _playing := false
var _play_time := 0.0
var _countdown_left := 0.0
var _heading := 0.0
var _land_squash := 0.0
var _safe_spots: Array[Vector3] = []
var _safe_timer := 0.0
var _body: RaceRunner
var _track: RaceTrack
var _bots: Array[RaceBot] = []
var _racers: Array[RaceRunner] = []
var _shoulder_checks := RaceShoulderChecks.new()
var _shove_pose_left := 0.0
var _shove_direction := Vector3.ZERO
var _shoulder_cooldown_left := 0.0
var _shoulder_requests: Dictionary[int, float] = {}
var _run_phase := 0.0
var _cam_yaw := 0.0
var _cam_pitch := 0.35
# Откуда сосиска прыгает в булочку (точка под ногами) и как она в этот момент повёрнута
var _jump_from := Vector3(JUMP_FROM_X, 0.0, 0.0)
var _q_jump: Quaternion
# Кат-сцена начата из игры: камера плавно перетекает из вида от 3-го лица
var _seamless := false
var _cam_from_pos := Vector3.ZERO
var _cam_from_look := Vector3.ZERO

var _in_menu := false
## peer_id → сосиска другого игрока
var _puppets := {}
var _remote_shoulder_racers: Dictionary[int, RaceShoulderChecks.Racer] = {}
var _net_timer := 0.0
var _claimed := false

var _sfx := {}
var _falling := false

var _q_run: Quaternion
var _q_lie: Quaternion
var _last_step_sign := 1.0
var _mayo_mat: StandardMaterial3D
var _mayo_blobs: MultiMesh
var _mayo_progress := PackedFloat32Array()
var _puff_mesh: SphereMesh
var _puff_mat: StandardMaterial3D
var _shadow_mesh: CylinderMesh
var _shadow_mat: StandardMaterial3D
var _sausage_shadow: MeshInstance3D


func _ready() -> void:
	_ui = GameInterface.new()
	add_child(_ui)
	_ui.solo_requested.connect(_menu_solo)
	_ui.host_requested.connect(_menu_host)
	_ui.join_requested.connect(_menu_join)
	Net.race_started.connect(_on_race_started)
	Net.player_state.connect(_on_player_state)
	Net.player_left.connect(_on_player_left)
	Net.shoulder_requested.connect(_queue_shoulder_request)
	Net.shoulder_windup.connect(_show_shoulder_windup)
	Net.shoulder_hit.connect(_apply_shoulder_hit)
	Net.winner_decided.connect(_on_winner_decided)
	Net.disconnected.connect(_on_net_disconnected)
	_shoulder_checks.windup.connect(_on_shoulder_windup)
	_shoulder_checks.hit.connect(_on_shoulder_hit)
	if playable and not Net.active:
		_add_sfx("click")
		_in_menu = true
		_ui.menu.show()
		return

	_build_world()
	if playable:
		# После кат-сцены продолжаем играть в той же комнате.
		_start_play()
	else:
		_update(0.0)


func _build_world() -> void:
	# Бег: лицом на 3/4 к камере, с наклоном вперёд
	_q_run = Quaternion(Vector3.BACK, -0.12) * Quaternion(Vector3.UP, deg_to_rad(50.0))
	# Лёжа: ось сосиски вдоль +X, лицо смотрит вверх
	_q_lie = Basis(Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)).get_rotation_quaternion()
	_q_jump = _q_run

	_mayo_mat = _toon(MAYO_COLOR, false)
	_mayo_mat.roughness = 0.2
	_puff_mesh = _sphere(0.1)
	_puff_mat = _toon(Color(0.95, 0.93, 0.9), false)

	_build_environment()
	_build_table()
	_build_bun()
	_build_sausage()
	_build_mayo_blobs()
	_build_bottle()
	for sfx_name: String in SFX:
		if not _sfx.has(sfx_name):
			_add_sfx(sfx_name)


func _process(delta: float) -> void:
	var fps := Engine.get_frames_per_second()
	if fps != _last_fps:
		_last_fps = fps
		_ui.fps.text = "FPS: %d" % fps
	if _done:
		return
	if _playing or _in_menu:
		return
	_play_cues(_t, _t + delta)
	_t += delta
	_update(_t)
	if _t >= END_TIME:
		_finish()


func _physics_process(delta: float) -> void:
	if _playing and not _done:
		_update_play(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo() \
			and (event as InputEventKey).keycode == KEY_F11:
		var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	if _playing:
		_play_input(event)


func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit()
	# Запущена отдельно — проигрываем по кругу
	if get_tree().current_scene == self:
		get_tree().reload_current_scene.call_deferred()


func _update(t: float) -> void:
	_animate_sausage(t)
	_animate_sausage_shadow(t)
	_animate_bun(t)
	_animate_mayo(t)
	_animate_face(t)
	_animate_camera(t)
	_animate_overlay(t)


# --- Игровой режим ---

func _start_play(difficulty := RaceBot.Difficulty.NO_BOTS) -> void:
	var layout_seed := randi()
	if Net.active:
		layout_seed = Net.race_seed if Net.race_running else Net.code.hash()
		_play_time = Net.race_elapsed()
	_build_track(layout_seed, _play_time)
	_playing = true
	_setup_input()
	_body = RaceRunner.new()
	_racers.append(_body)
	if not Net.active and difficulty != RaceBot.Difficulty.NO_BOTS:
		# Участники гонки сталкиваются с трассой, но могут обгонять друг друга вплотную.
		_body.collision_layer = 0
		for slot in RaceBot.NAMES.size():
			var bot := RaceBot.new()
			bot.configure(_track, difficulty, slot)
			bot.shadow = _shadow(bot, Vector3.UP * 0.02, Vector3(0.27, 1.0, 0.27))
			add_child(bot)
			_bots.append(bot)
			_racers.append(bot)
	add_child(_body)
	_body.teleport(_spawn_spot())
	_heading = _track.spawn_heading
	_cam_yaw = _heading + PI
	_ui.show_race(not Net.active or Net.race_running, Net.active or not _bots.is_empty())
	if Net.race_running or not _bots.is_empty():
		_ui.show_shoulder_hint()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_animate_bun(0.0)
	_animate_mayo(0.0)
	if Net.active:
		_update_play(0.0)
	else:
		_countdown_left = float(START_COUNT)
		_track.set_physics_process(false)
		_set_fade(0.0)
		_animate_player(0.0, true)
		_update_solo(0.0)
		_ui.show_countdown(START_COUNT)
		_play_sfx("countdown")
	_follow_camera(0.0, true)


func _setup_input() -> void:
	var bindings := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"sprint": [KEY_SHIFT],
		"jump": [KEY_SPACE],
		"shoulder_check": [KEY_E],
	}
	for action: String in bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: Key in bindings[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)


func _play_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_cam_yaw -= motion.screen_relative.x * MOUSE_SENSITIVITY
		_cam_pitch = clampf(_cam_pitch + motion.screen_relative.y * MOUSE_SENSITIVITY, -0.1, 1.1)
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventKey and event.is_pressed() and not event.is_echo() \
			and (event as InputEventKey).keycode in [KEY_ENTER, KEY_KP_ENTER]:
		Net.start_race()


func _update_play(delta: float) -> void:
	if _countdown_left > 0.0:
		_update_countdown(delta)
		return
	_play_time += delta
	_shove_pose_left = maxf(0.0, _shove_pose_left - delta)
	_shoulder_cooldown_left = maxf(0.0, _shoulder_cooldown_left - delta)
	var was_on_floor := _body.is_on_floor()

	# Движение относительно камеры
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish := Basis(Vector3.UP, _cam_yaw) * Vector3(input.x, 0.0, input.y)
	var speed := RaceRunner.SPRINT_SPEED if Input.is_action_pressed("sprint") else RaceRunner.WALK_SPEED
	_body.step(delta, wish * speed, Input.is_action_just_pressed("jump"), _track)
	if _body.jumped:
		_play_sfx("jump", 0.08)
	if _body.bumped:
		_play_sfx("bonk", 0.05)

	var on_floor := _body.is_on_floor()
	if on_floor and not was_on_floor:
		_land_squash = 1.0
		# Сход с края на ступеньку ниже — не приземление, шлёпаем только после полёта
		if _body.fall_speed > 4.0:
			_play_sfx("land", 0.1)
	_land_squash = move_toward(_land_squash, 0.0, delta * 6.0)

	_remember_safe_spot(delta)
	if not _falling and _body.global_position.y < FALL_WHISTLE_Y:
		_falling = true
		_play_sfx("fall", 0.05)
	if _body.global_position.y < RaceTrack.FALL_Y:
		_respawn()

	_animate_player(delta, on_floor)
	_follow_camera(delta)
	if _ui.fade.visible:
		_set_fade(1.0 - smoothstep(0.0, 0.5, _play_time))
	_ui.timer.text = _format_time(_play_time)
	var shoulder_pressed := Input.is_action_just_pressed("shoulder_check") and _shoulder_cooldown_left <= 0.0
	if Net.active:
		if Net.race_running and (_body.jumped or (shoulder_pressed and not Net.is_host())):
			_net_timer = 0.0
		_update_net(delta)
		if _body.reached_finish() and Net.race_running and not _claimed:
			# Кто первый — решает хост, кат-сцену запустит его ответ
			_claimed = true
			Net.claim_finish(_play_time)
		if _playing and Net.race_running:
			_update_shoulder_checks(delta, shoulder_pressed)
	else:
		_update_solo(delta)
		if _playing and not _bots.is_empty():
			_update_shoulder_checks(delta, shoulder_pressed)


func _update_countdown(delta: float) -> void:
	_body.step(delta, Vector3.ZERO, false, _track)
	_animate_player(delta, _body.is_on_floor())
	_follow_camera(delta)

	var previous := ceili(_countdown_left)
	_countdown_left = maxf(_countdown_left - delta, 0.0)
	var nearest_second := roundf(_countdown_left)
	if is_equal_approx(_countdown_left, nearest_second):
		_countdown_left = nearest_second
	var count := ceili(_countdown_left)
	if count != previous:
		_ui.show_countdown(count)
		_play_sfx("countdown" if count > 0 else "whistle")
		if count == 0:
			_track.set_physics_process(true)


func _update_solo(delta: float) -> void:
	if _bots.is_empty():
		if _body.reached_finish():
			_start_cutscene()
		return
	var player_progress := _track.progress_at(_body.global_position)
	var place := 1
	var winner: RaceBot
	for bot in _bots:
		if delta > 0.0:
			bot.advance(delta, _racers, _shoulder_checks.can_try(bot.get_instance_id()))
		if _track.progress_at(bot.global_position) > player_progress:
			place += 1
		if bot.reached_finish() and (winner == null or bot.global_position.length_squared() < winner.global_position.length_squared()):
			winner = bot
	_ui.room.text = "Место %d из %d" % [place, _bots.size() + 1]
	if _body.reached_finish():
		_start_cutscene("", _play_time, Vector3.INF, true)
	elif winner != null:
		_sausage_skin.albedo_color = winner.racer_color
		_sausage_limbs.albedo_color = winner.racer_color.darkened(0.15)
		_start_cutscene(winner.racer_name, _play_time, winner.global_position)
		if _cam_from_pos.distance_squared_to(_jump_from) > 100.0:
			_cam_from_pos = _jump_from + Vector3(-3.5, 2.1, 4.2)


func _animate_player(delta: float, on_floor: bool) -> void:
	var flat_velocity := _body.horizontal_velocity
	if flat_velocity.length() > 0.1:
		_heading = lerp_angle(_heading, atan2(flat_velocity.x, flat_velocity.z), 1.0 - exp(-12.0 * delta))
	var pace := _body.pace
	var amount := minf(pace, 1.0) if on_floor else 0.0
	_run_phase += delta * STEP_RATE * minf(pace, 1.3)

	var bob := absf(sin(_run_phase)) * 0.16 * amount
	_sausage.position = _body.global_position + Vector3.UP * (STAND_Y + bob)
	_sausage.quaternion = _run_rotation(_heading, minf(pace, 1.0))
	if on_floor:
		# В движении пружинит от шагов, на месте — «дышит», после приземления сплющивается
		_set_squash(1.0 + 0.06 * cos(_run_phase * 2.0) * amount
			+ 0.02 * sin(_play_time * 3.0) * (1.0 - amount) - 0.2 * _land_squash)
		_swing_limbs(_run_phase, amount)
	else:
		# В полёте вытягивается по скорости и раскидывает руки
		_set_squash(1.0 + clampf(_body.velocity.y * 0.02, -0.12, 0.15))
		_legs[0].rotation.x = 0.4
		_legs[1].rotation.x = -0.4
		for arm in _arms:
			arm.rotation.x = -2.2
	SausagePuppet.animate_shove(_sausage, _arms, _shove_direction, _shove_pose_left)

	_animate_sausage_shadow(0.0, _body.ground_below())
	_animate_face(0.0)
	if fmod(_play_time, 3.7) > 3.57:
		for eye in _eyes:
			eye.scale = Vector3(1.0, 0.12, 1.0)


func _remember_safe_spot(delta: float) -> void:
	# Движущиеся огурцы не годятся: к моменту возрождения их там уже нет
	var floor_hit := _body.get_last_slide_collision()
	if not _body.is_on_floor() or floor_hit == null or floor_hit.get_collider() is AnimatableBody3D:
		return
	_safe_timer -= delta
	if _safe_timer > 0.0:
		return
	_safe_timer = 0.05
	var pos := _body.global_position
	if not _safe_spots.is_empty() and _safe_spots.back().distance_to(pos) < 0.05:
		return
	_safe_spots.append(pos)
	if _safe_spots.size() > 40:
		_safe_spots.pop_front()


func _respawn() -> void:
	# Последняя опора — у самого края, поэтому отступаем по своим следам назад
	var spot := _track.spawn_point
	if not _safe_spots.is_empty():
		var edge: Vector3 = _safe_spots.back()
		spot = edge
		for i in range(_safe_spots.size() - 1, -1, -1):
			var candidate: Vector3 = _safe_spots[i]
			spot = candidate
			if Vector2(candidate.x - edge.x, candidate.z - edge.z).length() >= RESPAWN_BACKOFF:
				break
	_shove_pose_left = 0.0
	_teleport(spot)
	_net_timer = 0.0
	_falling = false
	_play_sfx("pop", 0.1)
	for leg in _legs:
		_spawn_puff(leg)


func _teleport(spot: Vector3) -> void:
	_body.teleport(spot)
	_animate_player(0.0, true)
	_follow_camera(0.0, true)


func _spawn_spot() -> Vector3:
	if not Net.active:
		return _track.spawn_point
	# Раскидываем игроков поперёк старта, чтобы не стояли друг в друге
	var slot := multiplayer.get_unique_id() % 7 - 3
	return _track.spawn_point + Vector3(0.0, 0.0, slot * SPAWN_SPREAD)


func _format_time(seconds: float) -> String:
	return "%d:%04.1f" % [int(seconds) / 60, fmod(seconds, 60.0)]


func _follow_camera(delta: float, snap := false) -> void:
	# Цель — ноги без покачивания от шагов, иначе камера трясётся при беге
	var feet := _body.global_position if _playing else Vector3(_sausage.position.x, 0.0, _sausage.position.z)
	var target := feet + Vector3.UP

	var offset := Basis(Vector3.UP, _cam_yaw) * Basis(Vector3.RIGHT, -_cam_pitch) * Vector3(0.0, 0.0, CAMERA_DISTANCE)
	var desired := target + offset
	desired.y = maxf(desired.y, target.y - 0.7)
	var pos := desired if snap else _camera.global_position.lerp(desired, 1.0 - exp(-10.0 * delta))
	_camera.look_at_from_position(pos, target, Vector3.UP)


## В булочку прыгает победитель с точки, в которой он финишировал.
func _start_cutscene(winner_nick := "", time := -1.0, winner_feet := Vector3.INF, player_won := false) -> void:
	_playing = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for puppet: SausagePuppet in _puppets.values():
		puppet.queue_free()
	_puppets.clear()
	for bot in _bots:
		bot.queue_free()
	_bots.clear()
	_racers.clear()
	_reset_shoulder_checks()
	if time < 0.0:
		time = _play_time
	_ui.show_finish(winner_nick, _format_time(time), player_won)
	var feet := _body.global_position if winner_feet == Vector3.INF else winner_feet
	# Прыгает в булочку прямо с того места, где стоит, развернувшись к ней
	_jump_from = Vector3(feet.x, 0.0, feet.z)
	var to_bun := LIE_POS - _jump_from
	_q_jump = _run_rotation(atan2(to_bun.x, to_bun.z), 0.0)
	_seamless = true
	_cam_from_pos = _camera.global_position
	_cam_from_look = _jump_from + Vector3.UP
	_t = RUN_END


# --- Толчок руками ---

func _update_shoulder_checks(delta: float, shoulder_pressed: bool) -> void:
	var racers: Dictionary[int, RaceShoulderChecks.Racer] = {}
	var local_id := _local_shoulder_id()
	for racer in _racers:
		if racer.can_shoulder_check():
			var motion := racer.horizontal_velocity
			var racer_id := local_id if racer == _body else racer.get_instance_id()
			var heading := _heading if racer == _body else atan2(motion.x, motion.z)
			racers[racer_id] = RaceShoulderChecks.Racer.new(racer.global_position, heading)
	var now := Time.get_ticks_msec()
	for peer_id in _remote_shoulder_racers:
		var remote := _remote_shoulder_racers[peer_id]
		if now - remote.sampled_msec <= SHOULDER_STATE_TIMEOUT_MS:
			racers[peer_id] = remote
	if Net.active and not Net.is_host():
		if shoulder_pressed:
			Net.request_shoulder_check()
	else:
		_shoulder_checks.advance(delta, racers, _track)
		if shoulder_pressed:
			_queue_shoulder_request(local_id)
		for peer_id in _shoulder_requests.keys():
			if _shoulder_requests[peer_id] < _play_time or _shoulder_checks.try_start(peer_id, racers):
				_shoulder_requests.erase(peer_id)
		for bot in _bots:
			var bot_id := bot.get_instance_id()
			if bot.wants_shoulder_check(delta, _shoulder_checks.nearest_target(bot_id, racers)):
				_shoulder_checks.try_start(bot_id, racers)
	_ui.set_shoulder_ready(_shoulder_cooldown_left <= 0.0 and _shoulder_checks.nearest_target(local_id, racers) != 0)


func _local_shoulder_id() -> int:
	return multiplayer.get_unique_id() if Net.active else _body.get_instance_id()


func _reset_shoulder_checks() -> void:
	_shove_pose_left = 0.0
	if _sausage != null:
		SausagePuppet.animate_shove(_sausage, _arms, Vector3.ZERO, 0.0)
	_shoulder_cooldown_left = 0.0
	_remote_shoulder_racers.clear()
	_shoulder_requests.clear()
	_shoulder_checks.reset()
	_ui.clear_shoulder_hint()


func _queue_shoulder_request(peer_id: int) -> void:
	if _playing:
		_shoulder_requests[peer_id] = _play_time + RaceShoulderChecks.INPUT_BUFFER


func _on_shoulder_windup(attacker_id: int, target_id: int, direction: Vector3) -> void:
	if Net.active:
		Net.send_shoulder_windup(attacker_id, target_id, direction)
	else:
		_show_shoulder_windup(attacker_id, target_id, direction)


func _show_shoulder_windup(attacker_id: int, target_id: int, direction: Vector3) -> void:
	if not _playing:
		return
	var local_id := _local_shoulder_id()
	if target_id == local_id:
		_ui.show_shoulder_warning()
	if attacker_id == local_id:
		_shove_direction = direction
		_shove_pose_left = RaceShoulderChecks.WINDUP_TIME + RaceShoulderChecks.FOLLOW_THROUGH_TIME
		_shoulder_cooldown_left = RaceShoulderChecks.COOLDOWN
	elif Net.active:
		var puppet := _puppets.get(attacker_id) as SausagePuppet
		if puppet != null:
			puppet.show_shoulder_windup(direction)
	else:
		var bot := instance_from_id(attacker_id) as RaceBot
		if bot != null:
			bot.show_shoulder_windup(direction)


func _on_shoulder_hit(attacker_id: int, target_id: int, impulse: Vector3) -> void:
	if Net.active:
		Net.send_shoulder_hit(attacker_id, target_id, impulse)
	else:
		_apply_shoulder_hit(attacker_id, target_id, impulse)


func _apply_shoulder_hit(attacker_id: int, target_id: int, impulse: Vector3) -> void:
	if not _playing:
		return
	var local_id := _local_shoulder_id()
	if attacker_id == local_id:
		_play_sfx("bonk", 0.05)
	if target_id == local_id:
		_body.receive_shoulder_hit(impulse)
	elif not Net.active:
		var bot := instance_from_id(target_id) as RaceBot
		if bot != null:
			bot.receive_shoulder_hit(impulse)


# --- Кооп ---

func _update_net(delta: float) -> void:
	_net_timer -= delta
	if _net_timer <= 0.0:
		_net_timer = NET_SEND_INTERVAL
		Net.send_state([_body.global_position, _heading, _body.pace, _body.is_on_floor(),
			Net.race_running and _body.can_shoulder_check(), Net.race_seed])

	var lines := PackedStringArray(["Комната %s" % Net.code])
	var ids: Array = Net.nicks.keys()
	ids.sort()
	for id: int in ids:
		lines.append(("• " if id == multiplayer.get_unique_id() else "  ") + Net.nick_of(id))
	if not Net.race_running:
		lines.append("")
		lines.append("Enter — старт" if Net.is_host() else "Ждём старта от хоста")
	_ui.room.text = "\n".join(lines)
	for id: int in _puppets:
		(_puppets[id] as SausagePuppet).set_nick(Net.nick_of(id))


func _on_race_started() -> void:
	if not _playing:
		return
	_claimed = false
	_play_time = Net.race_elapsed()
	_build_track(Net.race_seed, _play_time)
	_safe_spots.clear()
	_safe_timer = 0.0
	_net_timer = 0.0
	_reset_shoulder_checks()
	_ui.timer.visible = true
	_ui.show_shoulder_hint()
	_cam_yaw = _track.spawn_heading + PI
	_heading = _track.spawn_heading
	_teleport(_spawn_spot())
	_play_sfx("whistle")


func _on_player_state(peer_id: int, state: Array) -> void:
	if not _playing:
		return
	if not _puppets.has(peer_id):
		var puppet := SausagePuppet.new(Net.nick_of(peer_id))
		add_child(puppet)
		_puppets[peer_id] = puppet
	(_puppets[peer_id] as SausagePuppet).apply_state(state)
	if not Net.race_running or not Net.nicks.has(peer_id):
		return
	if state.size() >= 6 and state[5] == Net.race_seed and state[4] == true \
			and state[0] is Vector3 and state[0].is_finite() and state[1] is float and is_finite(state[1]):
		_remote_shoulder_racers[peer_id] = RaceShoulderChecks.Racer.new(state[0], state[1])
	else:
		_remote_shoulder_racers.erase(peer_id)


func _on_player_left(peer_id: int) -> void:
	_shoulder_requests.erase(peer_id)
	_remote_shoulder_racers.erase(peer_id)
	if _puppets.has(peer_id):
		(_puppets[peer_id] as SausagePuppet).queue_free()
		_puppets.erase(peer_id)


func _on_winner_decided(peer_id: int, nick: String, time: float) -> void:
	if not _playing:
		return
	var feet := Vector3.INF
	if peer_id != multiplayer.get_unique_id() and _puppets.has(peer_id):
		feet = (_puppets[peer_id] as SausagePuppet).feet
	_start_cutscene(nick, time, feet)


func _on_net_disconnected() -> void:
	_reset_shoulder_checks()
	if _playing:
		_ui.room.text = Net.error
		_ui.timer.visible = true


func _menu_nick() -> String:
	var nick := _ui.nickname.text.strip_edges()
	if nick.is_empty():
		_ui.set_menu_busy(false, "Введи ник")
		_ui.nickname.grab_focus()
	else:
		GameSettings.save_nickname(nick)
	return nick


func _menu_solo() -> void:
	_play_sfx("click")
	_enter_race(GameSettings.bot_difficulty)


func _menu_host() -> void:
	_play_sfx("click")
	var nick := _menu_nick()
	if nick.is_empty():
		return
	_ui.set_menu_busy(true, "Создаём комнату…")
	if await Net.host_async(nick):
		_enter_race()
	else:
		_ui.set_menu_busy(false, Net.error)


func _menu_join() -> void:
	_play_sfx("click")
	var nick := _menu_nick()
	if nick.is_empty():
		return
	var code := _ui.room_code.text.strip_edges()
	if code.length() != Net.CODE_LENGTH:
		_ui.set_menu_busy(false, "Код комнаты содержит %d символа" % Net.CODE_LENGTH)
		_ui.room_code.grab_focus()
		return
	_ui.set_menu_busy(true, "Подключаемся…")
	if await Net.join_async(nick, code):
		_enter_race()
	else:
		_ui.set_menu_busy(false, Net.error)


func _enter_race(difficulty := RaceBot.Difficulty.NO_BOTS) -> void:
	_ui.set_menu_busy(true, "Загружаем трассу…")
	# Даём меню отобразить статус до подготовки 3D-сцены.
	await get_tree().process_frame
	await get_tree().process_frame
	_build_world()
	_in_menu = false
	_start_play(difficulty)


# --- Звуки ---

func _add_sfx(sfx_name: String) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = load("res://assets/audio/sfx/%s.wav" % sfx_name)
	player.volume_db = SFX[sfx_name]
	player.max_polyphony = 4
	add_child(player)
	_sfx[sfx_name] = player


func _play_sfx(sfx_name: String, pitch_spread := 0.0) -> void:
	var player: AudioStreamPlayer = _sfx[sfx_name]
	player.pitch_scale = 1.0 + randf_range(-pitch_spread, pitch_spread)
	player.play()


## Звуки кат-сцены привязаны к её таймингам: играют, когда время перешло отметку
func _play_cues(from: float, to: float) -> void:
	var cues := {
		CROUCH_END: "jump",
		JUMP_END: "squish",
		BOTTLE_IN_END: "mayo",
		BOTTLE_IN_END + 0.4: "giggle",
		FADE_START + 0.5: "fanfare",
	}
	for time: float in cues:
		if from < time and time <= to:
			_play_sfx(cues[time])


# --- Анимация ---

func _animate_sausage(t: float) -> void:
	if t < RUN_END:
		var phase := t * STEP_RATE
		var x := lerpf(RUN_FROM_X, JUMP_FROM_X, t / RUN_END)
		_sausage.position = Vector3(x, STAND_Y + absf(sin(phase)) * 0.16, 0.0)
		_sausage.quaternion = _q_run
		_set_squash(1.0 + 0.06 * cos(phase * 2.0))
		_swing_limbs(phase, 1.0)
	elif t < CROUCH_END:
		var k := smoothstep(RUN_END, CROUCH_END, t)
		_sausage.position = _jump_from + _jump_dir() * 0.15 * k + Vector3.UP * (STAND_Y - 0.3 * k)
		_sausage.quaternion = _q_jump
		_set_squash(1.0 - 0.25 * k)
		for leg in _legs:
			leg.rotation.x = 0.0
		for arm in _arms:
			arm.rotation.x = 1.0 * k
	elif t < JUMP_END:
		var s := (t - CROUCH_END) / (JUMP_END - CROUCH_END)
		var from := _jump_from + _jump_dir() * 0.15 + Vector3.UP * (STAND_Y - 0.3)
		_sausage.position = from.lerp(LIE_POS, s) + Vector3.UP * 4.0 * JUMP_HEIGHT * s * (1.0 - s)
		_sausage.quaternion = _q_jump.slerp(_q_lie, smoothstep(0.1, 0.85, s))
		_set_squash(lerpf(0.75, 1.0, minf(s * 6.0, 1.0)) + 0.25 * sin(PI * s))
		var tuck := 1.0 - smoothstep(0.3, 0.85, s)
		for limb in _limbs:
			limb.visible = tuck > 0.01
			limb.scale = Vector3.ONE * maxf(tuck, 0.01)
		for arm in _arms:
			arm.rotation.x = lerpf(1.0, -2.5, smoothstep(0.0, 0.3, s))
	else:
		var w := _landing_wobble(t)
		var h := 0.0
		if t > BOTTLE_OUT_END and t < HAPPY_END:
			var u := (t - BOTTLE_OUT_END) / (HAPPY_END - BOTTLE_OUT_END)
			h = sin(u * PI * 4.0) * 0.07 * (1.0 - u)
		# Щекотно: перекатывается с боку на бок и подрагивает от смеха
		var joy := _joy(t)
		var roll := (sin(t * 9.0) * 0.2 + sin(t * 23.0) * 0.05) * joy
		var yaw := sin(t * 6.3) * 0.07 * joy
		_sausage.position = LIE_POS + Vector3.UP * absf(sin(t * 22.0)) * 0.025 * joy
		_sausage.quaternion = Quaternion(Vector3.UP, yaw) * Quaternion(Vector3.RIGHT, roll) * _q_lie
		# Локальная Z лежащей сосиски смотрит вверх — по ней и сплющиваем
		_sausage.scale = Vector3(1.0 + w * 0.4 + h, 1.0 + w * 0.2 - h * 0.5, 1.0 - w + h)
		for limb in _limbs:
			limb.visible = false


func _swing_limbs(phase: float, amount: float) -> void:
	var swing := sin(phase) * 0.9 * amount
	_legs[0].rotation.x = swing
	_legs[1].rotation.x = -swing
	_arms[0].rotation.x = -swing
	_arms[1].rotation.x = swing
	# Шаг приходится на смену знака синуса — в этот момент нога касается земли
	var step_sign := signf(sin(phase))
	if step_sign != 0.0 and step_sign != _last_step_sign:
		_last_step_sign = step_sign
		if amount > 0.4:
			_spawn_puff(_legs[0] if step_sign > 0.0 else _legs[1])
			_play_sfx("step", 0.15)


func _run_rotation(heading: float, lean: float) -> Quaternion:
	return Quaternion(Vector3.UP, heading) * Quaternion(Vector3.RIGHT, 0.15 * lean)


func _jump_dir() -> Vector3:
	var dir := LIE_POS - _jump_from
	dir.y = 0.0
	return dir.normalized()


func _animate_sausage_shadow(t: float, ground_y := 0.0) -> void:
	_sausage_shadow.visible = t < JUMP_END and not is_nan(ground_y)
	if not _sausage_shadow.visible:
		return
	# Пятно тянется вдоль проекции сосиски и сжимается с высотой
	var axis := _sausage.global_basis.y.normalized()
	var lowest := _sausage.position.y - ground_y - absf(axis.y) * SAUSAGE_LENGTH * 0.5
	var fade := clampf(1.0 - lowest / 3.0, 0.4, 1.0)
	_sausage_shadow.position = Vector3(_sausage.position.x, ground_y + 0.02, _sausage.position.z)
	_sausage_shadow.scale = Vector3(
		(0.3 + absf(axis.x) * SAUSAGE_LENGTH * 0.5) * fade,
		1.0,
		(0.3 + absf(axis.z) * SAUSAGE_LENGTH * 0.5) * fade)


func _joy(t: float) -> float:
	return smoothstep(BOTTLE_IN_END - 0.2, BOTTLE_IN_END + 0.3, t) * (1.0 - smoothstep(POUR_END + 0.6, HAPPY_END + 0.3, t))


func _set_squash(stretch: float) -> void:
	var side := 1.0 / sqrt(stretch)
	_sausage.scale = Vector3(side, stretch, side)


func _landing_wobble(t: float) -> float:
	if t < JUMP_END:
		return 0.0
	var tau := t - JUMP_END
	return 0.35 * exp(-5.0 * tau) * cos(18.0 * tau)


func _animate_bun(t: float) -> void:
	var w := _landing_wobble(t)
	_bun.scale = Vector3(1.0 + 0.08 * w, 1.0 - 0.25 * w, 1.0 + 0.12 * w)


func _animate_mayo(t: float) -> void:
	_bottle.visible = t >= TOP_CUT
	_stream.visible = false
	if t < TOP_CUT:
		return

	var nozzle_y := LIE_POS.y + SAUSAGE_RADIUS + NOZZLE_HEIGHT
	var start := _surface_point(0.0)
	start.y = nozzle_y
	var tilt := Vector3(-0.6, 0.0, 0.0)

	if t < BOTTLE_IN_END:
		var k := smoothstep(TOP_CUT, BOTTLE_IN_END, t)
		_bottle.position = (start + Vector3(-1.6, 1.8, -0.6)).lerp(start, k)
		_bottle_body.scale = Vector3.ONE
	elif t < POUR_END:
		var p := (t - BOTTLE_IN_END) / (POUR_END - BOTTLE_IN_END)
		_pour_to(p)
		var hit := _sausage.to_global(_lie_local(_surface_point(p)))
		var nozzle := Vector3(hit.x, nozzle_y, hit.z)
		_bottle.position = nozzle
		tilt.z = sin(t * 6.0) * 0.08
		var squeeze := 0.9 + 0.03 * sin(t * 9.0)
		_bottle_body.scale = Vector3(squeeze, 1.0, squeeze)
		_stream.visible = true
		_stream.position = (nozzle + hit) * 0.5
		var thick := 1.0 + 0.15 * sin(t * 31.0)
		_stream.scale = Vector3(thick, nozzle.y - hit.y, thick)
	else:
		_pour_to(1.0)
		var end := _surface_point(1.0)
		end.y = nozzle_y
		var k := smoothstep(POUR_END, BOTTLE_OUT_END, t)
		_bottle.position = end.lerp(end + Vector3(1.8, 1.8, -0.6), k * k)
		_bottle_body.scale = Vector3.ONE
	_bottle.rotation = tilt


func _surface_point(p: float) -> Vector3:
	var x := lerpf(MAYO_X_FROM, MAYO_X_TO, p)
	var z := sin(p * TAU * MAYO_WAVES) * MAYO_AMPLITUDE
	var y := LIE_POS.y + sqrt(maxf(SAUSAGE_RADIUS * SAUSAGE_RADIUS - z * z, 0.0))
	return Vector3(x, y, z)


# Точка на неподвижно лежащей сосиске → её локальные координаты,
# чтобы майонез держался на поверхности, пока она ёрзает
func _lie_local(point: Vector3) -> Vector3:
	return _q_lie.inverse() * (point - LIE_POS)


func _build_mayo_blobs() -> void:
	# Расставляем капли по траектории заранее, чтобы их шаг не зависел от FPS.
	var last := Vector3.INF
	for sample in range(MAYO_SAMPLES + 1):
		var p := float(sample) / MAYO_SAMPLES
		var point := _surface_point(p)
		if point.distance_squared_to(last) >= MAYO_STEP * MAYO_STEP:
			_mayo_progress.append(p)
			last = point

	_mayo_blobs = MultiMesh.new()
	_mayo_blobs.transform_format = MultiMesh.TRANSFORM_3D
	_mayo_blobs.mesh = _sphere(0.055, 16, 8)
	_mayo_blobs.instance_count = _mayo_progress.size()
	_mayo_blobs.visible_instance_count = 0
	# Все капли с запасом помещаются в локальные границы сосиски.
	_mayo_blobs.custom_aabb = AABB(Vector3(-0.5, -1.0, -0.5), Vector3(1.0, 2.0, 1.0))
	var node := MultiMeshInstance3D.new()
	node.multimesh = _mayo_blobs
	node.material_override = _mayo_mat
	_sausage.add_child(node)


func _pour_to(p: float) -> void:
	var visible_count := _mayo_blobs.visible_instance_count
	var index := visible_count
	while index < _mayo_progress.size() and _mayo_progress[index] <= p:
		_grow_blob(index, _lie_local(_surface_point(_mayo_progress[index])))
		index += 1
	if index != visible_count:
		_mayo_blobs.visible_instance_count = index


func _grow_blob(index: int, point: Vector3) -> void:
	_mayo_blobs.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3.ONE * 0.01), point))
	# Локальная Z сосиски — вертикаль, капля приплюснута по ней
	var size := randf_range(0.9, 1.15)
	var tween := create_tween()
	tween.tween_method(func(scale: Vector3) -> void:
		_mayo_blobs.set_instance_transform(index, Transform3D(Basis.from_scale(scale), point)),
		Vector3.ONE * 0.01, Vector3(size, size, size * 0.6), 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _spawn_puff(leg: Node3D) -> void:
	var puff := MeshInstance3D.new()
	puff.mesh = _puff_mesh
	puff.material_override = _puff_mat
	add_child(puff)
	var pos := leg.to_global(Vector3(0.0, -0.38, 0.0))
	pos.y = 0.06
	puff.position = pos
	puff.scale = Vector3.ONE * 0.3
	var tween := puff.create_tween()
	tween.tween_property(puff, "scale", Vector3.ONE * 1.5, 0.3).set_ease(Tween.EASE_OUT)
	# Пыль отлетает назад, против направления бега
	var back := -_sausage.global_basis.z
	back.y = 0.0
	tween.parallel().tween_property(puff, "position", pos + back.normalized() * 0.35 + Vector3.UP * 0.15, 0.55)
	tween.tween_property(puff, "scale", Vector3.ONE * 0.01, 0.25)
	tween.tween_callback(puff.queue_free)


func _animate_face(t: float) -> void:
	var closed := false
	for b: float in BLINKS:
		if t >= b and t < b + 0.13:
			closed = true
	# От удовольствия глаза закрываются и превращаются в дуги ^ ^
	var joy := _joy(t)
	var laugh := absf(sin(t * 22.0))
	for eye in _eyes:
		eye.visible = joy < 0.5
		eye.scale = Vector3(1.0, 0.12 if closed else maxf(1.0 - 2.0 * joy, 0.05), 1.0)
	_happy_eyes.visible = joy >= 0.5
	_bliss.visible = joy > 0.0

	# Куда смотрят зрачки: на булочку, потом в камеру, потом на бутылку
	var target := _camera.global_position
	if t < RUN_END + 0.3:
		target = Vector3(0.0, 0.5, 0.0)
	elif t >= TOP_CUT and t < BOTTLE_OUT_END:
		target = _bottle.global_position
	var to_local := _sausage.global_basis.inverse()
	for i in _eyes.size():
		var dir := (to_local * (target - _eyes[i].global_position)).normalized()
		dir.z = maxf(dir.z, 0.0) + 0.9
		_pupils[i].position = dir.normalized() * 0.065

	# Круглый рот сменяется широкой улыбкой, которая подрагивает от смеха
	_mouth.visible = joy < 0.3
	_mouth.scale = Vector3(1.3, 0.9, 0.5) * maxf(1.0 - joy / 0.3, 0.01)
	var grin := clampf((joy - 0.3) / 0.7, 0.0, 1.0)
	_grin.visible = grin > 0.0
	_grin.scale = Vector3(1.0, maxf(grin * (0.7 + 0.3 * laugh), 0.01), 1.0)


func _animate_camera(t: float) -> void:
	var pos: Vector3
	var look: Vector3
	if t < TOP_CUT:
		# Вид сбоку: камера едет за сосиской и плавно перекадрируется на булочку
		var run_x := lerpf(RUN_FROM_X, JUMP_FROM_X, minf(t / RUN_END, 1.0))
		var frame_x := lerpf(run_x, -0.9, smoothstep(RUN_END - 1.2, JUMP_END, t))
		var push := smoothstep(JUMP_END, TOP_CUT, t)
		pos = Vector3(frame_x + 0.2 * push, 1.7 - 0.2 * push, 6.2 - 1.2 * push)
		look = Vector3(frame_x + 0.4 + 0.3 * push, 0.9 - 0.2 * push, 0.0)
		if _seamless:
			# Из вида от 3-го лица камера перетекает в боковой план с той же стороны стола,
			# чтобы не пролетать сквозь прыгающую сосиску
			if _cam_from_pos.z < 0.0:
				pos.z = -pos.z
			var k := smoothstep(RUN_END, JUMP_END + 0.4, t)
			pos = _cam_from_pos.lerp(pos, k)
			look = _cam_from_look.lerp(look, k)
	else:
		# Вид сверху с лёгким наездом
		var k := smoothstep(TOP_CUT, FADE_START, t)
		pos = Vector3(-0.05, 3.0 - 0.4 * k, 0.85 - 0.1 * k)
		look = Vector3(-0.05, 0.45, 0.0)
	if t >= JUMP_END and t < TOP_CUT:
		var shake := 0.1 * exp(-9.0 * (t - JUMP_END))
		pos += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * shake
	_camera.look_at_from_position(pos, look, Vector3.UP)


func _animate_overlay(t: float) -> void:
	var alpha := 1.0 - smoothstep(0.0, 0.5, t)
	alpha = maxf(alpha, smoothstep(FADE_START, FADE_START + 0.7, t))
	_set_fade(alpha)
	_ui.result.modulate.a = smoothstep(FADE_START + 0.5, FADE_START + 1.0, t)


func _set_fade(alpha: float) -> void:
	_ui.fade.visible = alpha > 0.0
	_ui.fade.color.a = alpha


# --- Построение сцены ---

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.6, 0.92)
	sky_mat.sky_horizon_color = Color(0.86, 0.9, 0.95)
	sky_mat.ground_horizon_color = Color(0.86, 0.9, 0.95)
	sky_mat.ground_bottom_color = Color(0.5, 0.45, 0.4)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.light_energy = 1.2
	# Настоящие тени в Mobile рябят на скатерти, вместо них мультяшные пятна
	sun.shadow_enabled = false
	add_child(sun)

	_camera = Camera3D.new()
	_camera.fov = 45.0
	add_child(_camera)
	_camera.current = true


func _build_table() -> void:
	var shader := Shader.new()
	shader.code = GROUND_SHADER
	var cloth_mat := ShaderMaterial.new()
	cloth_mat.shader = shader
	# Стол со скатертью: финиш трассы, верх на y = 0
	var table := StaticBody3D.new()
	table.position = Vector3(0.0, -0.5, 0.0)
	add_child(table)
	var table_size := Vector3(-RaceTrack.TABLE_EDGE * 2.0, 1.0, -RaceTrack.TABLE_EDGE * 2.0)
	var table_shape := BoxShape3D.new()
	table_shape.size = table_size
	var table_collider := CollisionShape3D.new()
	table_collider.shape = table_shape
	table.add_child(table_collider)
	var table_mesh := BoxMesh.new()
	table_mesh.size = table_size
	_mesh(table, table_mesh, cloth_mat)

	# Далеко внизу — кафельный пол кухни, туда и падают
	var tiles_mat := ShaderMaterial.new()
	tiles_mat.shader = shader
	tiles_mat.set_shader_parameter("color_a", Color(0.55, 0.72, 0.85))
	tiles_mat.set_shader_parameter("color_b", Color(0.92, 0.95, 0.97))
	tiles_mat.set_shader_parameter("cell", 4.0)
	tiles_mat.set_shader_parameter("fade_from", 80.0)
	tiles_mat.set_shader_parameter("fade_to", 250.0)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(800.0, 800.0)
	_mesh(self, floor_mesh, tiles_mat, Vector3(0.0, -40.0, 0.0))

	var plate := CylinderMesh.new()
	plate.top_radius = 1.4
	plate.bottom_radius = 1.25
	plate.height = 0.06
	plate.rings = 0
	var plate_node := _mesh(self, plate, _toon(Color(0.98, 0.98, 1.0)), Vector3(0.0, 0.03, 0.0))
	plate_node.scale = Vector3(1.0, 1.0, 0.6)

	_shadow_mesh = CylinderMesh.new()
	_shadow_mesh.top_radius = 1.0
	_shadow_mesh.bottom_radius = 1.0
	_shadow_mesh.height = 0.002
	_shadow_mesh.radial_segments = 48
	_shadow_mesh.rings = 0
	_shadow_mat = StandardMaterial3D.new()
	_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_mat.albedo_color = Color(0.2, 0.02, 0.02, 0.6)
	# Тень под тарелкой и под булочкой на тарелке
	_shadow(self, Vector3(0.1, 0.01, 0.06), Vector3(1.45, 1.0, 0.87))
	_shadow(self, Vector3(0.08, 0.062, 0.05), Vector3(0.98, 1.0, 0.5))
	_sausage_shadow = _shadow(self, Vector3.ZERO, Vector3.ONE)


func _build_track(layout_seed: int, elapsed: float) -> void:
	if is_instance_valid(_track):
		remove_child(_track)
		_track.queue_free()
	_track = RaceTrack.new(layout_seed, elapsed)
	add_child(_track)


func _build_bun() -> void:
	_bun = Node3D.new()
	_bun.position = Vector3(0.0, 0.04, 0.0)
	add_child(_bun)
	var mat := _toon(BUN_COLOR)

	# Капсулы повёрнуты вдоль X: локальная X капсулы смотрит вверх
	var half := CapsuleMesh.new()
	half.radius = 0.26
	half.height = BUN_LENGTH
	half.radial_segments = 40
	half.rings = 10
	for side in [-1.0, 1.0]:
		var node := _mesh(_bun, half, mat, Vector3(0.0, 0.3, 0.25 * side))
		node.rotation.z = PI * 0.5

	var bottom := CapsuleMesh.new()
	bottom.radius = 0.3
	bottom.height = BUN_LENGTH
	bottom.radial_segments = 40
	bottom.rings = 10
	var bottom_node := _mesh(_bun, bottom, mat, Vector3(0.0, 0.15, 0.0))
	bottom_node.rotation.z = PI * 0.5
	bottom_node.scale = Vector3(0.5, 1.0, 1.4)


func _build_sausage() -> void:
	_sausage = Node3D.new()
	add_child(_sausage)

	var body := CapsuleMesh.new()
	body.radius = SAUSAGE_RADIUS
	body.height = SAUSAGE_LENGTH
	body.radial_segments = 48
	body.rings = 12
	_sausage_skin = _toon(SAUSAGE_COLOR)
	_mesh(_sausage, body, _sausage_skin)

	var white := _toon(Color.WHITE, false)
	var black := _toon(Color(0.05, 0.03, 0.03), false)

	var eye_mesh := _sphere(0.095)
	var pupil_mesh := _sphere(0.05)
	var glint_mesh := _sphere(0.018)
	for side in [-1.0, 1.0]:
		var eye := Node3D.new()
		eye.position = Vector3(0.09 * side, 0.55, 0.17)
		_sausage.add_child(eye)
		_mesh(eye, eye_mesh, white)
		var pupil := _mesh(eye, pupil_mesh, black)
		_mesh(pupil, glint_mesh, white, Vector3(0.015, 0.02, 0.035))
		_eyes.append(eye)
		_pupils.append(pupil)

	var mouth_mat := _toon(Color(0.35, 0.05, 0.08), false)
	_mouth = _mesh(_sausage, _sphere(0.055), mouth_mat, Vector3(0.0, 0.33, 0.21))

	# Блаженное лицо на время полива: глаза-дуги ^ ^, румянец и широкая улыбка
	_bliss = Node3D.new()
	_sausage.add_child(_bliss)
	var blush_mat := _toon(Color(1.0, 0.5, 0.55), false)
	var blush_mesh := _sphere(0.05)
	for side in [-1.0, 1.0]:
		var blush := _mesh(_bliss, blush_mesh, blush_mat, Vector3(0.155 * side, 0.43, 0.15))
		blush.scale = Vector3(1.0, 0.6, 0.4)

	_happy_eyes = Node3D.new()
	_sausage.add_child(_happy_eyes)
	var line_mat := _toon(Color(0.12, 0.04, 0.03), false)
	for side in [-1.0, 1.0]:
		var arc := PackedVector2Array()
		for i in 9:
			var a := PI * i / 8.0
			arc.append(Vector2(0.09 * side + 0.065 * cos(a), 0.52 + 0.05 * sin(a)))
		_face_tube(_happy_eyes, arc, 0.016, line_mat)

	# Улыбка в форме «D»: прямой верх, круглый низ; масштабом по Y открывается от смеха
	_grin = Node3D.new()
	_grin.position = Vector3(0.0, 0.37, 0.0)
	_sausage.add_child(_grin)
	_mesh(_grin, _face_half_disc(0.115, 0.1, 0.01), _flat(Color(0.35, 0.05, 0.08)))
	var teeth := PackedVector2Array([Vector2(-0.085, -0.013), Vector2(0.085, -0.013)])
	_mesh(_grin, _face_ribbon(teeth, 0.024, 0.016), _flat(Color.WHITE))
	var tongue := _mesh(_grin, _sphere(0.05), _flat(Color(1.0, 0.42, 0.48)), _face_point(Vector2(0.0, -0.072), 0.0))
	tongue.scale = Vector3(1.0, 0.5, 0.3)

	_sausage_limbs = _toon(SAUSAGE_COLOR.darkened(0.15))
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
		_sausage.add_child(leg)
		_mesh(leg, leg_mesh, _sausage_limbs, Vector3(0.0, -0.18, 0.0))
		var shoe := _mesh(leg, shoe_mesh, glove_mat, Vector3(0.0, -0.38, 0.04))
		shoe.scale = Vector3(1.0, 0.6, 1.5)
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
		_sausage.add_child(arm)
		_mesh(arm, arm_mesh, _sausage_limbs, Vector3(0.0, -0.15, 0.0))
		_mesh(arm, hand_mesh, glove_mat, Vector3(0.0, -0.33, 0.0))
		_arms.append(arm)

	_limbs.append_array(_legs)
	_limbs.append_array(_arms)


func _build_bottle() -> void:
	# Начало координат бутылки — кончик носика
	_bottle = Node3D.new()
	_bottle.visible = false
	add_child(_bottle)
	var red := _toon(Color(0.88, 0.16, 0.14))

	var nozzle := CylinderMesh.new()
	nozzle.top_radius = 0.055
	nozzle.bottom_radius = 0.012
	nozzle.height = 0.16
	nozzle.radial_segments = 24
	nozzle.rings = 0
	_mesh(_bottle, nozzle, red, Vector3(0.0, 0.08, 0.0))

	var cap := CylinderMesh.new()
	cap.top_radius = 0.13
	cap.bottom_radius = 0.13
	cap.height = 0.12
	cap.radial_segments = 32
	cap.rings = 0
	_mesh(_bottle, cap, red, Vector3(0.0, 0.22, 0.0))

	var body := CylinderMesh.new()
	body.top_radius = 0.2
	body.bottom_radius = 0.2
	body.height = 0.75
	body.radial_segments = 48
	body.rings = 0
	_bottle_body = _mesh(_bottle, body, _toon(Color(0.98, 0.96, 0.88)), Vector3(0.0, 0.655, 0.0))

	var band := CylinderMesh.new()
	band.top_radius = 0.205
	band.bottom_radius = 0.205
	band.height = 0.2
	band.radial_segments = body.radial_segments
	band.rings = 0
	_mesh(_bottle_body, band, _toon(Color(0.98, 0.78, 0.2), false), Vector3(0.0, -0.05, 0.0))

	var stream := CylinderMesh.new()
	stream.top_radius = 0.024
	stream.bottom_radius = 0.024
	stream.height = 1.0
	stream.radial_segments = 16
	stream.rings = 0
	_stream = _mesh(self, stream, _mayo_mat)
	_stream.visible = false
	_stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Бутылка висит у самой камеры, её размытая тень только шумит на скатерти
	for part in _bottle.find_children("*", "MeshInstance3D", true, false):
		(part as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# --- Хелперы ---

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


func _shadow(parent: Node3D, pos: Vector3, size: Vector3) -> MeshInstance3D:
	var node := _mesh(parent, _shadow_mesh, _shadow_mat, pos)
	node.scale = size
	return node


func _flat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


# Точка лица (x поперёк, y вдоль сосиски), прижатая к её цилиндрической поверхности
func _face_point(p: Vector2, lift: float) -> Vector3:
	return Vector3(p.x, p.y, sqrt(maxf(SAUSAGE_RADIUS * SAUSAGE_RADIUS - p.x * p.x, 0.0)) + lift)


# Лента заданной ширины вдоль ломаной, лежащая на поверхности сосиски
func _face_ribbon(points: PackedVector2Array, width: float, lift: float) -> ArrayMesh:
	# Дробим на короткие отрезки, иначе плоские куски проваливаются под изогнутую кожу
	var dense := PackedVector2Array()
	for i in points.size() - 1:
		var steps := maxi(ceili(points[i].distance_to(points[i + 1]) / 0.008), 1)
		for s in steps:
			dense.append(points[i].lerp(points[i + 1], float(s) / steps))
	dense.append(points[points.size() - 1])

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.BACK)
	for i in dense.size() - 1:
		var a := dense[i]
		var b := dense[i + 1]
		var n := (b - a).normalized().orthogonal() * width * 0.5
		var quad: Array[Vector3] = [
			_face_point(a + n, lift), _face_point(a - n, lift),
			_face_point(b + n, lift), _face_point(b - n, lift),
		]
		# Обе стороны треугольников, чтобы ничего не отсекалось
		for idx in [0, 1, 2, 2, 1, 3, 0, 2, 1, 2, 3, 1]:
			st.add_vertex(quad[idx])
	return st.commit()


# Плавная линия из перекрывающихся капсул, лежащих на поверхности сосиски
func _face_tube(parent: Node3D, points: PackedVector2Array, radius: float, mat: Material) -> void:
	for i in points.size() - 1:
		var a := _face_point(points[i], 0.0)
		var b := _face_point(points[i + 1], 0.0)
		var capsule := CapsuleMesh.new()
		capsule.radius = radius
		capsule.height = a.distance_to(b) + radius * 2.0
		capsule.radial_segments = 12
		capsule.rings = 2
		var node := _mesh(parent, capsule, mat, (a + b) * 0.5)
		var y := (b - a).normalized()
		var z := Vector3(node.position.x, 0.0, node.position.z).normalized()
		var x := y.cross(z).normalized()
		node.basis = Basis(x, y, x.cross(y))


# Полуэллипс с прямым верхним краем на y = 0
func _face_half_disc(rx: float, ry: float, lift: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.BACK)
	var center := _face_point(Vector2.ZERO, lift)
	var steps := 20
	for i in steps:
		var a0 := PI * i / steps
		var a1 := PI * (i + 1) / steps
		st.add_vertex(center)
		st.add_vertex(_face_point(Vector2(rx * cos(a0), -ry * sin(a0)), lift))
		st.add_vertex(_face_point(Vector2(rx * cos(a1), -ry * sin(a1)), lift))
	return st.commit()


func _sphere(radius: float, radial_segments := 24, rings := 12) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = radial_segments
	mesh.rings = rings
	return mesh


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	parent.add_child(node)
	return node
