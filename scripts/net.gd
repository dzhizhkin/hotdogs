extends Node

## Кооп через Epic Online Services: вход без аккаунта Epic (Device ID),
## комната ищется по короткому коду, игровой трафик идёт P2P —
## EOS сам пробивает NAT, а если не вышло, пускает через свой relay.
## Хост — один из игроков, он же решает, кто добежал первым.
## Живёт автозагрузкой, чтобы соединение переживало перезапуск сцены после кат-сцены.

signal race_started
signal player_state(peer_id: int, state: Array)
signal player_left(peer_id: int)
signal shoulder_requested(peer_id: int)
signal shoulder_windup(attacker_id: int, target_id: int, direction: Vector3)
signal shoulder_hit(attacker_id: int, target_id: int, impulse: Vector3)
signal winner_decided(peer_id: int, nick: String, time: float)
signal disconnected

const SOCKET := "hotdogs"
const BUCKET_PREFIX := "hotdogs:course7:"
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CODE_LENGTH := 4
const MAX_PLAYERS := 8
const CONNECT_TIMEOUT_MS := 15000

var active := false
var code := ""
var nick := ""
## peer_id → ник
var nicks := {}
var race_running := false
var race_seed := 0
var error := ""

var _peer: EOSGMultiplayerPeer
var _lobby: HLobby
var _eos_ready := false
var _race_started_msec := 0


func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_host() -> bool:
	return active and multiplayer.is_server()


func host_async(p_nick: String) -> bool:
	if not await _setup_async(p_nick):
		return false
	var rng := RandomNumberGenerator.new()
	code = ""
	for i in CODE_LENGTH:
		code += CODE_CHARS[rng.randi_range(0, CODE_CHARS.length() - 1)]

	var opts := EOS.Lobby.CreateLobbyOptions.new()
	opts.bucket_id = BUCKET_PREFIX + code
	opts.max_lobby_members = MAX_PLAYERS
	opts.permission_level = EOS.Lobby.LobbyPermissionLevel.PublicAdvertised
	opts.presence_enabled = false
	_lobby = await HLobbies.create_lobby_async(opts)
	if _lobby == null:
		return _fail("Не удалось создать комнату")

	_peer = EOSGMultiplayerPeer.new()
	if _peer.create_server(SOCKET) != OK:
		return _fail("Не удалось запустить сервер")
	multiplayer.multiplayer_peer = _peer
	nicks = {1: nick}
	active = true
	return true


func join_async(p_nick: String, p_code: String) -> bool:
	if not await _setup_async(p_nick):
		return false
	code = p_code.strip_edges().to_upper()
	# В комнату не заходим: из лобби нужен только PUID хоста, дальше всё по P2P
	var lobbies = await HLobbies.search_by_bucket_id_async(BUCKET_PREFIX + code)
	if lobbies == null or lobbies.is_empty():
		return _fail("Комната %s не найдена" % code)
	var host_puid: String = (lobbies[0] as HLobby).owner_product_user_id

	_peer = EOSGMultiplayerPeer.new()
	if _peer.create_client(SOCKET, host_puid) != OK:
		return _fail("Не удалось подключиться")
	multiplayer.multiplayer_peer = _peer

	var result := [0]
	var on_ok := func() -> void: result[0] = 1
	var on_fail := func() -> void: result[0] = -1
	multiplayer.connected_to_server.connect(on_ok)
	multiplayer.connection_failed.connect(on_fail)
	var deadline := Time.get_ticks_msec() + CONNECT_TIMEOUT_MS
	while result[0] == 0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	multiplayer.connected_to_server.disconnect(on_ok)
	multiplayer.connection_failed.disconnect(on_fail)
	if result[0] != 1:
		_close()
		return _fail("Хост не отвечает")

	active = true
	_hello.rpc_id(1, nick)
	return true


func start_race() -> void:
	if is_host() and not race_running:
		_start_race.rpc(randi())


func race_elapsed() -> float:
	return (Time.get_ticks_msec() - _race_started_msec) / 1000.0 if race_running else 0.0


func send_state(state: Array) -> void:
	if active:
		_state.rpc(state)


func request_shoulder_check() -> void:
	if active and race_running and not is_host():
		_request_shoulder_check.rpc_id(1, race_seed)


func send_shoulder_windup(attacker_id: int, target_id: int, direction: Vector3) -> void:
	if is_host() and race_running:
		_shoulder_windup.rpc(race_seed, attacker_id, target_id, direction)


func send_shoulder_hit(attacker_id: int, target_id: int, impulse: Vector3) -> void:
	if is_host() and race_running:
		_shoulder_hit.rpc(race_seed, attacker_id, target_id, impulse)


func claim_finish(time: float) -> void:
	if not active:
		return
	if is_host():
		_claim_finish(time)
	else:
		_claim_finish.rpc_id(1, time)


func nick_of(peer_id: int) -> String:
	return nicks.get(peer_id, "Сосиска")


# --- Сеть ---

@rpc("any_peer", "reliable")
func _hello(p_nick: String) -> void:
	if not multiplayer.is_server():
		return
	nicks[multiplayer.get_remote_sender_id()] = p_nick.strip_edges().left(16)
	_sync.rpc(nicks, race_running, race_seed, race_elapsed())


@rpc("authority", "reliable")
func _sync(p_nicks: Dictionary, p_race_running: bool, p_race_seed: int, elapsed: float) -> void:
	var joined_race := p_race_running and (not race_running or race_seed != p_race_seed)
	nicks = p_nicks
	race_running = p_race_running
	race_seed = p_race_seed
	if joined_race:
		_race_started_msec = Time.get_ticks_msec() - roundi(elapsed * 1000.0)
		race_started.emit()


@rpc("authority", "call_local", "reliable")
func _start_race(seed_value: int) -> void:
	race_seed = seed_value
	_race_started_msec = Time.get_ticks_msec()
	race_running = true
	race_started.emit()


@rpc("any_peer", "unreliable_ordered")
func _state(state: Array) -> void:
	player_state.emit(multiplayer.get_remote_sender_id(), state)


@rpc("any_peer", "reliable")
func _request_shoulder_check(seed_value: int) -> void:
	var peer_id := multiplayer.get_remote_sender_id()
	if is_host() and race_running and race_seed == seed_value and nicks.has(peer_id):
		shoulder_requested.emit(peer_id)


@rpc("authority", "call_local", "reliable")
func _shoulder_windup(seed_value: int, attacker_id: int, target_id: int, direction: Vector3) -> void:
	if race_running and race_seed == seed_value:
		shoulder_windup.emit(attacker_id, target_id, direction)


@rpc("authority", "call_local", "reliable")
func _shoulder_hit(seed_value: int, attacker_id: int, target_id: int, impulse: Vector3) -> void:
	if race_running and race_seed == seed_value:
		shoulder_hit.emit(attacker_id, target_id, impulse)


@rpc("any_peer", "reliable")
func _claim_finish(time: float) -> void:
	if not multiplayer.is_server() or not race_running:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	race_running = false
	_announce_winner.rpc(sender, nick_of(sender), time)


@rpc("authority", "call_local", "reliable")
func _announce_winner(peer_id: int, p_nick: String, time: float) -> void:
	race_running = false
	winner_decided.emit(peer_id, p_nick, time)


func _on_peer_disconnected(peer_id: int) -> void:
	nicks.erase(peer_id)
	player_left.emit(peer_id)
	if multiplayer.is_server():
		_sync.rpc(nicks, race_running, race_seed, race_elapsed())


func _on_server_disconnected() -> void:
	_close()
	error = "Хост вышел из игры"
	disconnected.emit()


# --- EOS ---

func _setup_async(p_nick: String) -> bool:
	error = ""
	nick = p_nick.strip_edges().left(16)
	if _eos_ready:
		return true
	var env := _load_env()
	var creds := HCredentials.new()
	creds.product_name = "Hotdogs"
	creds.product_version = "1.0"
	creds.product_id = env.get("EOS_PRODUCT_ID", "")
	creds.sandbox_id = env.get("EOS_SANDBOX_ID", "")
	creds.deployment_id = env.get("EOS_DEPLOYMENT_ID", "")
	creds.client_id = env.get("EOS_CLIENT_ID", "")
	creds.client_secret = env.get("EOS_CLIENT_SECRET", "")
	creds.encryption_key = env.get("EOS_ENCRYPTION_KEY", "")
	if creds.client_id == "" or creds.client_secret == "":
		return _fail("В .env не заданы EOS_CLIENT_ID и EOS_CLIENT_SECRET")
	if not await HPlatform.setup_eos_async(creds):
		return _fail("Не удалось запустить EOS")
	if not await HAuth.login_anonymous_async(nick):
		return _fail("Не удалось войти в EOS")
	# Новый Device ID проходит через Connect.CreateUser, после которого EOSG не запоминает
	# локального пользователя для P2P (issue #92) — повторный вход это чинит
	if EOSGMultiplayerPeer.get_local_user_id() == "":
		if not await HAuth.login_game_services_async(HAuth._last_connect_login_opts):
			return _fail("Не удалось войти в EOS")
	_eos_ready = true
	return true


func _load_env() -> Dictionary:
	var env := {}
	var file := FileAccess.open("res://.env", FileAccess.READ)
	if file == null:
		return env
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.begins_with("#"):
			continue
		var parts := line.split("=", false, 1)
		if parts.size() == 2:
			env[parts[0].strip_edges()] = parts[1].strip_edges().trim_prefix("\"").trim_suffix("\"")
	return env


func _fail(message: String) -> bool:
	error = message
	return false


func _close() -> void:
	active = false
	race_running = false
	race_seed = 0
	nicks = {}
	multiplayer.multiplayer_peer = null
	_peer = null
