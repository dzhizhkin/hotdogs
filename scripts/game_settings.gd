extends Node

const SETTINGS_PATH := "user://settings.cfg"
const AUTO := "auto"
const FAST := "fast"
const BALANCED := "balanced"
const HIGH := "high"
const QUALITY_MODES := [AUTO, FAST, BALANCED, HIGH]
const QUALITY_NAMES := {FAST: "Быстро", BALANCED: "Баланс", HIGH: "Высокое"}
const PIXEL_BUDGETS := {
	FAST: 1440.0 * 900.0,
	BALANCED: 1920.0 * 1080.0,
	HIGH: 2560.0 * 1440.0,
}

var mode := AUTO
var detected_quality := FAST
var nickname := ""
var bot_difficulty := RaceBot.Difficulty.NORMAL
var _config := ConfigFile.new()


func _ready() -> void:
	_config.load(SETTINGS_PATH)
	nickname = str(_config.get_value("player", "nick", ""))
	var saved_difficulty = _config.get_value("solo", "difficulty", RaceBot.Difficulty.NORMAL)
	if saved_difficulty is int and saved_difficulty >= 0 and saved_difficulty < RaceBot.DIFFICULTY_NAMES.size():
		bot_difficulty = saved_difficulty as RaceBot.Difficulty
	var saved_mode := str(_config.get_value("graphics", "mode", AUTO))
	if saved_mode in QUALITY_MODES:
		mode = saved_mode
	var saved_detection := str(_config.get_value("graphics", "detected_quality", ""))
	if PIXEL_BUDGETS.has(saved_detection):
		detected_quality = saved_detection
	elif DisplayServer.get_name() != "headless":
		detected_quality = _detect_quality()
		_config.set_value("graphics", "detected_quality", detected_quality)
		_config.save(SETTINGS_PATH)
	get_window().size_changed.connect(_apply_quality)
	_apply_quality()


func set_quality(new_mode: String) -> Error:
	if new_mode not in QUALITY_MODES:
		return ERR_INVALID_PARAMETER
	mode = new_mode
	_config.set_value("graphics", "mode", mode)
	_apply_quality()
	return _config.save(SETTINGS_PATH)


func save_nickname(value: String) -> Error:
	nickname = value
	_config.set_value("player", "nick", nickname)
	return _config.save(SETTINGS_PATH)


func set_bot_difficulty(difficulty: RaceBot.Difficulty) -> Error:
	bot_difficulty = difficulty
	_config.set_value("solo", "difficulty", bot_difficulty)
	return _config.save(SETTINGS_PATH)


func _detect_quality() -> String:
	if RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
		return BALANCED
	if RenderingServer.get_video_adapter_vendor().to_lower().contains("apple"):
		return BALANCED
	return FAST


func _apply_quality() -> void:
	var quality := detected_quality if mode == AUTO else mode
	var window := get_window()
	var size := window.size
	var budget: float = PIXEL_BUDGETS[quality]
	window.scaling_3d_scale = sqrt(budget / maxf(budget, size.x * size.y))
	window.msaa_3d = Viewport.MSAA_2X if quality == HIGH else Viewport.MSAA_DISABLED
	window.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if quality == BALANCED else Viewport.SCREEN_SPACE_AA_DISABLED
