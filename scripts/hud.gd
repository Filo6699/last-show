extends CanvasLayer
signal advance_requested
signal choice_selected(index: int)
signal menu_action(action: String)
signal settings_changed(volume: float, sensitivity: float)
var root: Control
var touch: Control
var touch_enabled := false
var hint: Label
var objective: Label
var chapter: Label
var item: Label
var crosshair: Label
var notice: Label
var dialog: PanelContainer
var portrait: TextureRect
var speaker: Label
var words: Label
var choices: VBoxContainer
var next_button: Button
var menu: ColorRect
var menu_column: VBoxContainer
var fade: ColorRect
var flash: ColorRect
var text_tween: Tween
var notice_tween: Tween
var volume := 0.65
var sensitivity := 1.0
var line_ready := true
var showing_choices := false
var current_options: Array = []
var story_backdrop: ColorRect
var story_caption: Label
var silhouette: TextureRect
var scare_tween: Tween
var silhouette_tween: Tween
var dialogue_scroll: ScrollContainer

func _ready() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var theme := Theme.new()
	theme.default_font = preload("res://assets/fonts/DejaVuSerif.ttf")
	theme.default_font_size = 23
	story_backdrop = ColorRect.new()
	story_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	story_backdrop.color = Color(0.012, 0.014, 0.021)
	story_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(story_backdrop)
	story_backdrop.hide()
	root.theme = theme
	chapter = label("", Vector2(24, 20), Vector2(600, 36))
	chapter.add_theme_color_override("font_color", Color("c9b99e"))
	objective = label("", Vector2(24, 58), Vector2(560, 96))
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item = label("", Vector2(-280, 70), Vector2(250, 60))
	item.anchor_left = 1.0
	item.anchor_right = 1.0
	item.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	crosshair = label("·", Vector2(-6, -20), Vector2(12, 24))
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-6, -20)
	hint = label("", Vector2(-380, 30), Vector2(760, 58))
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	hint.position = Vector2(-380, 30)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_shadow_color", Color.BLACK)
	hint.add_theme_constant_override("shadow_offset_x", 2)
	hint.add_theme_constant_override("shadow_offset_y", 2)
	notice = label("", Vector2(-390, 100), Vector2(780, 86))
	notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	notice.position = Vector2(-390, 100)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.add_theme_color_override("font_color", Color("edd4a1"))
	touch = Control.new()
	touch.set_script(preload("res://scripts/touch_controls.gd"))
	touch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(touch)
	var pause_button := make_button("Ⅱ", func(): menu_action.emit("pause"))
	pause_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	pause_button.position = Vector2(-88, 20)
	pause_button.size = Vector2(64, 48)
	pause_button.custom_minimum_size = Vector2(64, 48)
	root.add_child(pause_button)

	dialog = PanelContainer.new()
	dialog.add_theme_stylebox_override("panel", panel_style())
	root.add_child(dialog)
	var scroll := ScrollContainer.new()
	dialogue_scroll = scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dialog.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	scroll.add_child(column)
	speaker = Label.new()
	speaker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speaker.add_theme_color_override("font_color", Color("e2c799"))
	column.add_child(speaker)
	words = Label.new()
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	words.add_theme_font_size_override("font_size", 27)
	column.add_child(words)
	choices = VBoxContainer.new()
	choices.add_theme_constant_override("separation", 8)
	column.add_child(choices)
	next_button = make_button("Продолжить", advance)
	column.add_child(next_button)
	portrait = TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(portrait)
	story_caption = label("", Vector2(-260, -60), Vector2(520, 70))
	story_caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	story_caption.position = Vector2(-260, -170)
	story_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	story_caption.add_theme_font_size_override("font_size", 42)
	silhouette = TextureRect.new()
	silhouette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	silhouette.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	silhouette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(silhouette)
	silhouette.hide()
	menu = ColorRect.new()
	menu.color = Color(0.025, 0.025, 0.04, 0.94)
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(menu)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(center)
	menu_column = VBoxContainer.new()
	menu_column.custom_minimum_size.x = 380
	menu_column.add_theme_constant_override("separation", 13)
	center.add_child(menu_column)
	fade = ColorRect.new()
	fade.color = Color.BLACK
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(fade)
	fade.hide()
	flash = ColorRect.new()
	flash.color = Color(0.75, 0.1, 0.08, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(flash)
	touch_enabled = DisplayServer.is_touchscreen_available() or "--touch" in OS.get_cmdline_user_args()
	touch.visible = touch_enabled
	dialog.hide()
	portrait.hide()
	menu.hide()
	root.resized.connect(layout_dialog)
	layout_dialog()

func label(text: String, position: Vector2, dimensions: Vector2) -> Label:
	var result := Label.new()
	result.text = text
	result.position = position
	result.size = dimensions
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(result)
	return result

func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("171822")
	style.border_color = Color("a98a5e")
	style.set_border_width_all(2)
	style.set_content_margin_all(20)
	return style

func make_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 54
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	return button

func layout_dialog() -> void:
	if not is_instance_valid(dialog):
		return
	var width := minf(1000, root.size.x - 40)
	var height := minf(370 if showing_choices else 250, root.size.y - 48)
	dialog.position = Vector2((root.size.x - width) * 0.5, root.size.y - height - 20)
	dialog.size = Vector2(width, height)
	var portrait_height := minf(330, maxf(0, root.size.y - height - 64))
	portrait.position = Vector2((root.size.x - 400) * 0.5, dialog.position.y - portrait_height - 12)
	portrait.size = Vector2(400, portrait_height)
	objective.size.x = minf(560, maxf(180, root.size.x - 140))
	for button in choices.get_children():
		var text: Label = button.get_node("Text")
		text.custom_minimum_size.x = maxf(160, width - 100)
		var font := text.get_theme_font("font")
		var measured := font.get_multiline_string_size(text.text, HORIZONTAL_ALIGNMENT_CENTER, maxf(160, width - 100), text.get_theme_font_size("font_size"))
		button.custom_minimum_size.y = maxf(60, measured.y + 32)

func show_line(who: String, text: String, image: Texture2D, options: Array, minimum_pause: float = 0) -> void:
	if text_tween and text_tween.is_running():
		text_tween.kill()
	speaker.text = who
	words.text = text
	words.visible_characters = 0
	dialogue_scroll.scroll_vertical = 0
	current_options = options
	showing_choices = not options.is_empty()
	for old in choices.get_children():
		choices.remove_child(old)
		old.queue_free()
	for index in options.size():
		var button := make_button("", func(): select_choice(index))
		var caption := Label.new()
		caption.name = "Text"
		caption.text = options[index]["text"]
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		caption.offset_left = 14
		caption.offset_right = -14
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(caption)
		choices.add_child(button)
	next_button.visible = not showing_choices
	portrait.texture = image
	portrait.visible = image != null
	dialog.show()
	hint.hide()
	crosshair.hide()
	touch.reset()
	touch.hide()
	line_ready = minimum_pause <= 0
	next_button.disabled = not line_ready
	text_tween = create_tween()
	text_tween.tween_property(words, "visible_characters", text.length(), maxf(0.01, text.length() / 45.0))
	layout_dialog.call_deferred()
	if minimum_pause > 0:
		var displayed_text := text
		await get_tree().create_timer(minimum_pause).timeout
		if words.text == displayed_text and dialog.visible:
			line_ready = true
			next_button.disabled = false

func advance() -> void:
	if not dialog.visible or not line_ready:
		return
	if words.visible_characters >= 0 and words.visible_characters < words.text.length():
		if text_tween: text_tween.kill()
		words.visible_characters = -1
		return
	if not showing_choices:
		advance_requested.emit()

func select_choice(index: int) -> void:
	if dialog.visible and line_ready and index >= 0 and index < current_options.size():
		choice_selected.emit(index)

func close_dialog() -> void:
	if text_tween: text_tween.kill()
	dialog.hide()
	portrait.hide()
	hint.show()
	crosshair.show()
	touch.visible = touch_enabled and not menu.visible

func set_hint(value: String) -> void:
	hint.text = ("[E]  " if not touch_enabled else "") + value if not value.is_empty() else ""

func set_objective(area: String, text: String, has_hairpin: bool = false) -> void:
	chapter.text = area
	objective.text = text
	item.text = "Невидимка" if has_hairpin else ""

func show_notice(text: String) -> void:
	if notice_tween: notice_tween.kill()
	notice.text = text
	notice.modulate.a = 1
	notice_tween = create_tween()
	notice_tween.tween_interval(3)
	notice_tween.tween_property(notice, "modulate:a", 0.0, 0.5)

func show_menu(kind: String, can_continue: bool = false) -> void:
	for child in menu_column.get_children():
		menu_column.remove_child(child)
		child.queue_free()
	var heading := Label.new()
	heading.text = "LAST SHOW" if kind == "main" else ("До встречи с Вальтером" if kind == "end" else "Пауза")
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 34)
	menu_column.add_child(heading)
	if kind == "end":
		var detail := Label.new()
		detail.text = "Ричард добрался до доктора.\nПродолжение истории — за пределами этой главы."
		detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		detail.add_theme_font_size_override("font_size", 19)
		menu_column.add_child(detail)
	if kind == "pause":
		menu_column.add_child(make_button("Вернуться в игру", func(): menu_action.emit("resume")))
	elif can_continue:
		menu_column.add_child(make_button("Продолжить", func(): menu_action.emit("continue")))
	menu_column.add_child(make_button("Пройти заново" if kind != "main" else "Новая игра", func(): menu_action.emit("new_game")))
	menu_column.add_child(make_button("Настройки", show_settings))
	if kind != "main":
		menu_column.add_child(make_button("Главное меню", func(): menu_action.emit("main_menu")))
	menu_column.add_child(make_button("Выйти", func(): menu_action.emit("quit")))
	menu.show()
	touch.reset()
	touch.hide()
	hint.hide()
	crosshair.hide()

func hide_menu() -> void:
	menu.hide()
	if not dialog.visible:
		touch.visible = touch_enabled
		hint.show()
		crosshair.show()

func show_settings() -> void:
	for child in menu_column.get_children():
		menu_column.remove_child(child)
		child.queue_free()
	for name in ["Громкость", "Чувствительность обзора"]:
		var caption := Label.new()
		caption.text = name
		menu_column.add_child(caption)
		var slider := HSlider.new()
		slider.min_value = 0 if name == "Громкость" else 0.4
		slider.max_value = 1 if name == "Громкость" else 2.5
		slider.step = 0.05
		slider.value = volume if name == "Громкость" else sensitivity
		slider.custom_minimum_size.y = 48
		slider.value_changed.connect(func(value):
			if name == "Громкость": volume = value
			else: sensitivity = value
			settings_changed.emit(volume, sensitivity))
		menu_column.add_child(slider)
	menu_column.add_child(make_button("Назад", func(): menu_action.emit("settings_back")))

func transition_out() -> void:
	fade.modulate.a = 0
	fade.show()
	var tween := create_tween()
	tween.tween_property(fade, "modulate:a", 1.0, 0.3)
	await tween.finished

func transition_in() -> void:
	var tween := create_tween()
	tween.tween_property(fade, "modulate:a", 0.0, 0.45)
	await tween.finished
	fade.hide()

func scare() -> void:
	if scare_tween: scare_tween.kill()
	flash.color.a = 0.75
	scare_tween = create_tween()
	scare_tween.tween_property(flash, "color:a", 0.0, 0.35)

func set_story_mode(mode: String) -> void:
	story_backdrop.visible = not mode.is_empty()
	story_backdrop.color = Color(0.012, 0.014, 0.021) if mode == "technical" else Color(0.82, 0.83, 0.80)
	chapter.add_theme_color_override("font_color", Color("564536") if mode == "photos" else Color("c9b99e"))
	for element in [objective, item]:
		element.add_theme_color_override("font_color", Color("23242a") if mode == "photos" else Color.WHITE)
	story_caption.text = ""
	silhouette.hide()
	if silhouette_tween: silhouette_tween.kill()

func show_caption(text: String) -> void:
	story_caption.text = text

func show_silhouette(image: Texture2D) -> void:
	silhouette.texture = image
	silhouette.size = Vector2(180, 240)
	silhouette.position = Vector2(root.size.x * 0.72, 110)
	silhouette.modulate = Color(0.45, 0.33, 0.37, 0.75)
	silhouette.show()
	silhouette_tween = create_tween()
	silhouette_tween.tween_interval(0.25)
	silhouette_tween.tween_property(silhouette, "modulate:a", 0.0, 0.15)

func reset_effects() -> void:
	if scare_tween: scare_tween.kill()
	if silhouette_tween: silhouette_tween.kill()
	if notice_tween: notice_tween.kill()
	flash.color.a = 0
	silhouette.hide()
	notice.text = ""
	story_caption.text = ""
