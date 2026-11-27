class_name GameInterface
extends CanvasLayer

signal solo_requested
signal host_requested
signal join_requested

const MENU_ART := preload("res://assets/ui/menu_art.jpg")
const CREAM := Color("#fff2df")
const PAPER := Color("#fffaee")
const INK := Color("#311b14")
const MUTED := Color("#725447")
const BORDER := Color("#d8bca2")
const RED := Color("#ae3023")
const GOLD := Color("#ffd584")
const SHOULDER_TUTORIAL := "Нажми E рядом с соперником, чтобы толкнуть его руками.\nПробел — отпрыгнуть от толчка."

var menu: Control
var nickname: LineEdit
var room_code: LineEdit
var timer: Label
var fps: Label
var room: Label
var fade: ColorRect
var result: CenterContainer
var _result_title: Label
var _result_time: Label
var _countdown: Label
var _hint: Label
var _shoulder_hint: Label
var _shoulder_tutorial_left := 0.0
var _shoulder_warning_left := 0.0
var _shoulder_ready := false
var _status: Label
var _quality: OptionButton
var _difficulty: OptionButton
var _actions: Array[Button] = []
var _heading_font := SystemFont.new()


func _ready() -> void:
	_heading_font.font_names = PackedStringArray(["Avenir Next", "Segoe UI", "DejaVu Sans"])
	_heading_font.font_weight = 900
	_build_hud()
	_build_menu()


func _process(delta: float) -> void:
	_shoulder_tutorial_left = maxf(0.0, _shoulder_tutorial_left - delta)
	_shoulder_warning_left = maxf(0.0, _shoulder_warning_left - delta)
	_update_shoulder_hint()


func set_menu_busy(busy: bool, message: String) -> void:
	_status.text = message
	_status.visible = not message.is_empty()
	for action in _actions:
		action.disabled = busy
	nickname.editable = not busy
	room_code.editable = not busy
	_quality.disabled = busy
	_difficulty.disabled = busy


func show_race(show_timer: bool, show_room: bool) -> void:
	menu.hide()
	timer.visible = show_timer
	room.visible = show_room
	_hint.show()
	fps.show()


func show_countdown(number: int) -> void:
	_countdown.text = str(number) if number > 0 else "Старт!"
	_countdown.show()
	if number == 0:
		create_tween().tween_callback(_countdown.hide).set_delay(0.75)


func show_shoulder_hint() -> void:
	_shoulder_tutorial_left = 5.0
	_update_shoulder_hint()


func set_shoulder_ready(ready: bool) -> void:
	_shoulder_ready = ready


func show_shoulder_warning() -> void:
	_shoulder_warning_left = RaceShoulderChecks.WINDUP_TIME + 0.1
	_update_shoulder_hint()


func clear_shoulder_hint() -> void:
	_shoulder_tutorial_left = 0.0
	_shoulder_warning_left = 0.0
	_shoulder_ready = false
	_shoulder_hint.hide()


func _update_shoulder_hint() -> void:
	_shoulder_hint.modulate = Color.WHITE
	if _shoulder_warning_left > 0.0:
		_shoulder_hint.text = "Толчок! Пробел — отпрыгнуть"
		_shoulder_hint.modulate = GOLD
	elif _shoulder_ready:
		_shoulder_hint.text = "E · Толкнуть"
	elif _shoulder_tutorial_left > 0.0:
		_shoulder_hint.text = SHOULDER_TUTORIAL
		_shoulder_hint.modulate.a = minf(1.0, _shoulder_tutorial_left / 0.4)
	else:
		_shoulder_hint.hide()
		return
	_shoulder_hint.show()


func show_finish(winner: String, finish_time: String, player_won := false) -> void:
	timer.hide()
	room.hide()
	_hint.hide()
	clear_shoulder_hint()
	_countdown.hide()
	if player_won:
		_result_title.text = "Ты выиграл гонку!"
	else:
		_result_title.text = "Хот-дог готов!" if winner.is_empty() else "Победитель — %s" % winner
	_result_time.text = "Время  %s" % finish_time


func _build_menu() -> void:
	menu = Control.new()
	menu.name = "MainMenu"
	add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.hide()

	var art := TextureRect.new()
	art.texture = MENU_ART
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.anchor_right = 0.57

	var panel := ColorRect.new()
	panel.color = CREAM
	menu.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = art.anchor_right

	var center := CenterContainer.new()
	panel.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var form := VBoxContainer.new()
	form.custom_minimum_size.x = 398.0
	form.add_theme_constant_override("separation", 18)
	center.add_child(form)

	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation", -2)
	form.add_child(heading)
	var title := _label("HOTDOGS", 68, INK)
	title.add_theme_font_override("font", _heading_font)
	heading.add_child(title)
	heading.add_child(_label("Гонка с препятствиями", 21, MUTED))

	var solo_section := VBoxContainer.new()
	solo_section.add_theme_constant_override("separation", 8)
	form.add_child(solo_section)
	var solo := _button("Играть одному", true)
	solo.name = "Solo"
	solo.pressed.connect(solo_requested.emit)
	solo_section.add_child(solo)
	_difficulty = _option_row(solo_section, "Сложность ботов", "BotDifficulty")
	for difficulty_name in RaceBot.DIFFICULTY_NAMES:
		_difficulty.add_item(difficulty_name)
	_difficulty.select(GameSettings.bot_difficulty)
	_difficulty.item_selected.connect(_select_difficulty)
	form.add_child(_divider())

	var online := VBoxContainer.new()
	online.add_theme_constant_override("separation", 8)
	form.add_child(online)
	online.add_child(_label("Игра с друзьями", 20, INK))
	nickname = _field("Твой ник", 16)
	nickname.name = "Nickname"
	nickname.text = GameSettings.nickname
	online.add_child(nickname)
	var host := _button("Создать комнату")
	host.pressed.connect(host_requested.emit)
	online.add_child(host)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	online.add_child(join_row)
	room_code = _field("Код комнаты", Net.CODE_LENGTH)
	room_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(room_code)
	var join := _button("Войти")
	join_row.add_child(join)
	join.pressed.connect(join_requested.emit)
	room_code.text_submitted.connect(func(_text: String) -> void:
		if not join.disabled:
			join_requested.emit())
	_actions = [solo, host, join]

	_status = _label("", 15, RED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = form.custom_minimum_size.x
	_status.hide()
	form.add_child(_status)
	form.add_child(_divider())

	_quality = _option_row(form, "Графика", "GraphicsQuality")
	_quality.tooltip_text = "Авто выбирает качество по видеокарте при первом запуске"
	_quality.add_item("Авто · %s" % GameSettings.QUALITY_NAMES[GameSettings.detected_quality])
	for index in range(1, GameSettings.QUALITY_MODES.size()):
		_quality.add_item(GameSettings.QUALITY_NAMES[GameSettings.QUALITY_MODES[index]])
	_quality.select(GameSettings.QUALITY_MODES.find(GameSettings.mode))
	_quality.item_selected.connect(_select_quality)

	var footer := _label("F11  ·  Полный экран / окно", 14, MUTED)
	form.add_child(footer)


func _select_quality(index: int) -> void:
	var error := GameSettings.set_quality(GameSettings.QUALITY_MODES[index])
	set_menu_busy(false, "" if error == OK else "Не удалось сохранить качество графики")


func _select_difficulty(index: int) -> void:
	var error := GameSettings.set_bot_difficulty(index as RaceBot.Difficulty)
	set_menu_busy(false, "" if error == OK else "Не удалось сохранить сложность ботов")


func _build_hud() -> void:
	fade = ColorRect.new()
	fade.color = Color.BLACK
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	timer = _badge("0:00.0", 28, GOLD)
	add_child(timer)
	timer.position = Vector2(24.0, 20.0)
	timer.hide()

	var corner := VBoxContainer.new()
	corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corner.add_theme_constant_override("separation", 8)
	add_child(corner)
	corner.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	corner.offset_right = -24.0
	corner.offset_left = -24.0
	corner.offset_top = 20.0
	corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	fps = _badge("", 17, GOLD)
	fps.size_flags_horizontal = Control.SIZE_SHRINK_END
	corner.add_child(fps)
	fps.hide()
	room = _badge("", 17, CREAM)
	room.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	room.size_flags_horizontal = Control.SIZE_SHRINK_END
	corner.add_child(room)
	room.hide()

	_hint = _badge("WASD  Бег     Пробел  Прыжок     Shift  Ускорение     Мышь  Камера     Esc  Курсор", 17, CREAM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_bottom = -20.0
	_hint.offset_top = -60.0
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.hide()

	var shoulder_prompt := CenterContainer.new()
	shoulder_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shoulder_prompt)
	shoulder_prompt.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	shoulder_prompt.offset_top = -128.0
	shoulder_prompt.offset_bottom = -69.0
	_shoulder_hint = _badge(SHOULDER_TUTORIAL, 17, CREAM)
	_shoulder_hint.name = "ShoulderHint"
	_shoulder_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shoulder_prompt.add_child(_shoulder_hint)
	_shoulder_hint.hide()

	var start_prompt := CenterContainer.new()
	start_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(start_prompt)
	start_prompt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_countdown = _label("", 76, GOLD)
	_countdown.name = "StartCountdown"
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown.custom_minimum_size.x = 132.0
	_countdown.add_theme_font_override("font", _heading_font)
	_countdown.add_theme_stylebox_override("normal", _box(Color("#301a14ed"), 22, Color("#79503b"), 28, 8))
	start_prompt.add_child(_countdown)
	_countdown.hide()

	result = CenterContainer.new()
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(result)
	result.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result.modulate.a = 0.0
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", _box(Color("#301a14"), 26, Color("#79503b"), 42, 28))
	result.add_child(card)
	var result_text := VBoxContainer.new()
	result_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_text.add_theme_constant_override("separation", 8)
	card.add_child(result_text)
	_result_title = _label("Хот-дог готов!", 46, GOLD)
	_result_title.add_theme_font_override("font", _heading_font)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_text.add_child(_result_title)
	_result_time = _label("", 23, CREAM)
	_result_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_text.add_child(_result_time)


func _badge(value: String, size: int, color: Color) -> Label:
	var label := _label(value, size, color)
	label.add_theme_stylebox_override("normal", _box(Color("#2b1712e8"), 12, Color("#b483544a"), 14, 7))
	return label


func _label(value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(value: String, primary := false) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = 54.0 if primary else 44.0
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_button(button, primary)
	return button


func _style_button(button: BaseButton, primary: bool) -> void:
	var color := CREAM if primary else INK
	button.add_theme_font_size_override("font_size", 21 if primary else 17)
	button.add_theme_color_override("font_color", color)
	button.add_theme_color_override("font_hover_color", color)
	button.add_theme_color_override("font_focus_color", color)
	button.add_theme_color_override("font_pressed_color", color)
	button.add_theme_color_override("font_disabled_color", MUTED)
	button.add_theme_stylebox_override("normal", _box(RED if primary else PAPER, 10, RED if primary else BORDER))
	button.add_theme_stylebox_override("hover", _box(Color("#bc3d2a") if primary else Color("#ffedce"), 10, RED if primary else BORDER))
	button.add_theme_stylebox_override("pressed", _box(Color("#8e251b") if primary else Color("#f1d3ab"), 10, RED if primary else BORDER))
	button.add_theme_stylebox_override("disabled", _box(Color("#efdfc9"), 10, BORDER))
	button.add_theme_stylebox_override("focus", _box(Color.TRANSPARENT, 10, RED.darkened(0.3), 12, 8, 2))


func _field(placeholder: String, limit: int) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.max_length = limit
	field.custom_minimum_size.y = 44.0
	field.add_theme_font_size_override("font_size", 17)
	field.add_theme_color_override("font_color", INK)
	field.add_theme_color_override("font_placeholder_color", MUTED)
	field.add_theme_color_override("caret_color", INK)
	field.add_theme_color_override("selection_color", RED)
	field.add_theme_color_override("font_selected_color", PAPER)
	field.add_theme_color_override("font_uneditable_color", MUTED)
	field.add_theme_stylebox_override("normal", _box(PAPER, 10, BORDER))
	field.add_theme_stylebox_override("focus", _box(Color.TRANSPARENT, 10, RED, 12, 8, 2))
	field.add_theme_stylebox_override("read_only", _box(Color("#efdfc9"), 10, BORDER))
	return field


func _option_row(parent: Control, title: String, node_name: String) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)
	var caption := _label(title, 18, INK)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(caption)
	var option := OptionButton.new()
	option.name = node_name
	option.custom_minimum_size = Vector2(214.0, 44.0)
	option.add_theme_constant_override("modulate_arrow", 1)
	option.add_theme_constant_override("arrow_margin", 14)
	_style_button(option, false)
	row.add_child(option)
	var popup := option.get_popup()
	popup.add_theme_stylebox_override("panel", _box(PAPER, 10, BORDER))
	popup.add_theme_stylebox_override("hover", _box(Color("#ffedce"), 6, Color.TRANSPARENT))
	popup.add_theme_color_override("font_color", INK)
	popup.add_theme_color_override("font_hover_color", INK)
	popup.add_theme_font_size_override("font_size", 17)
	popup.add_theme_constant_override("v_separation", 12)
	return option


func _divider() -> ColorRect:
	var line := ColorRect.new()
	line.color = BORDER
	line.custom_minimum_size.y = 1.0
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _box(fill: Color, radius: int, border: Color, horizontal := 12, vertical := 8, width := 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = horizontal
	style.content_margin_right = horizontal
	style.content_margin_top = vertical
	style.content_margin_bottom = vertical
	return style
