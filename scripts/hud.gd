extends CanvasLayer
signal character_revealed(letter: String)
signal voice_started(id: String)
signal voice_stopped
signal ui_sound(back: bool)
var current_voice := ""
signal interaction_requested
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
var dialog_column: VBoxContainer
var portrait_stage: Control
var portrait: TextureRect
var portrait_tween: Tween
var speaker: Label
var words: Label
var choices: VBoxContainer
var next_button: Button
var menu: ColorRect
var menu_column: VBoxContainer
var menu_scroll:ScrollContainer
var main_menu_view
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
var choice_scroll: ScrollContainer
var action_button: Button
var pause_timer: Timer
var focus_frame: ReferenceRect
var photo_pair: HBoxContainer
var photo_dialog_style: StyleBox
var voice_speed := 22.0
var voice_color := Color("b5a185")
var ending_title:=""
var ending_description:=""
# Objective line and direction arrow at the top centre. The game feeds them
# every frame through set_guide(); they fade instead of popping.
const GUIDE_IVORY := Color("ecd9b8")
const GUIDE_BRASS := Color("a17b50")
var guide: Control
var guide_panel: Panel
var guide_arrow: Control
var guide_text := ""
var guide_active := false
var guide_has_direction := false
var guide_angle := 0.0
var guide_alpha := 0.0
var guide_arrow_alpha := 0.0
var guide_aligned := false

func _ready() -> void:
	pause_timer = Timer.new()
	pause_timer.one_shot = true
	pause_timer.timeout.connect(func():
		line_ready = true
		next_button.disabled = false)
	add_child(pause_timer)
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
	build_guide()
	item = label("", Vector2(-280, 70), Vector2(250, 60))
	item.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	item.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	crosshair = label("·", Vector2(-6, -20), Vector2(12, 24))
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -6
	crosshair.offset_right = 6
	crosshair.offset_top = -20
	crosshair.offset_bottom = 4
	hint = label("", Vector2(-380, 30), Vector2(760, 58))
	hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_shadow_color", Color.BLACK)
	hint.add_theme_constant_override("shadow_offset_x", 2)
	hint.add_theme_constant_override("shadow_offset_y", 2)
	notice = label("", Vector2(-390, 100), Vector2(780, 86))
	notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	action_button = make_button("", func(): interaction_requested.emit())
	action_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	action_button.position = Vector2(-300,-155)
	action_button.size = Vector2(270,90)
	root.add_child(action_button)
	action_button.hide()
	focus_frame = ReferenceRect.new()
	focus_frame.border_color = Color.WHITE
	focus_frame.border_width = 2.0
	focus_frame.editor_only = false
	focus_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(focus_frame)
	focus_frame.hide()
	touch.target_tapped.connect(func(): interaction_requested.emit())
	photo_pair = HBoxContainer.new()
	photo_pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	photo_pair.add_theme_constant_override("separation", 18)
	root.add_child(photo_pair)
	photo_pair.hide()

	dialog = PanelContainer.new()
	dialog.add_theme_stylebox_override("panel", panel_style())
	root.add_child(dialog)
	dialog_column = VBoxContainer.new()
	dialog_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialog_column.add_theme_constant_override("separation", 6)
	dialog.add_child(dialog_column)
	speaker = Label.new()
	speaker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speaker.add_theme_color_override("font_color", Color("e2c799"))
	speaker.add_theme_font_size_override("font_size", 19)
	dialog_column.add_child(speaker)
	# Only the reply scrolls; actions stay at the bottom of the panel.
	dialogue_scroll = ScrollContainer.new()
	dialogue_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dialogue_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialog_column.add_child(dialogue_scroll)
	words = Label.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	words.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	words.add_theme_font_size_override("font_size", 21)
	dialogue_scroll.add_child(words)
	choice_scroll = ScrollContainer.new()
	choice_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dialog_column.add_child(choice_scroll)
	choices = VBoxContainer.new()
	choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices.add_theme_constant_override("separation", 8)
	choice_scroll.add_child(choices)
	next_button = make_button("Продолжить", advance)
	dialog_column.add_child(next_button)
	# Clip the legs behind the dialogue, including beyond its side margins.
	portrait_stage = Control.new()
	portrait_stage.clip_contents = true
	portrait_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(portrait_stage)
	root.move_child(portrait_stage, dialog.get_index())
	portrait = TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_stage.add_child(portrait)
	portrait.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
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
	main_menu_view = preload("res://scripts/main_menu.gd").new()
	menu.add_child(main_menu_view)
	menu_scroll=ScrollContainer.new()
	menu_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_scroll.offset_left=20;menu_scroll.offset_top=20;menu_scroll.offset_right=-20;menu_scroll.offset_bottom=-20
	menu_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	menu.add_child(menu_scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal=Control.SIZE_EXPAND_FILL;center.size_flags_vertical=Control.SIZE_EXPAND_FILL
	menu_scroll.add_child(center)
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
	style.set_content_margin_all(12)
	return style

func make_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 54
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func(): ui_sound.emit(text in ["Назад","Главное меню"]))
	button.pressed.connect(action)
	return button

func layout_dialog() -> void:
	if not is_instance_valid(dialog):
		return
	# Anchored offsets are relative to the anchor; Control.position is not.
	var hint_width := minf(760, root.size.x - 48)
	hint.size = Vector2(minf(440, root.size.x - 48), 64)
	hint.position = Vector2((root.size.x - hint.size.x) / 2, root.size.y - 84)
	notice.offset_left = -hint_width / 2
	notice.offset_right = hint_width / 2
	notice.offset_top = 100 if root.size.y >= 600 else 65
	notice.offset_bottom = minf(root.size.y / 2 - 16, notice.offset_top + 86)
	item.offset_left = -minf(280, root.size.x - 24)
	item.offset_right = -24
	item.offset_top = 80
	item.offset_bottom = 140
	var width := minf(1000, root.size.x - 40)
	# Keep the same stage and panel between listening, replying and choices.
	# Otherwise the sprite changes size whenever the protagonist answers.
	# Keep the dialogue low and shallow so the speaker's face and the scene
	# remain visible. The small minimum preserves enough room for touch actions
	# on short landscape screens; the panel stays fixed across speakers and modes.
	var height := minf(maxf(184, root.size.y * .30), root.size.y - 24)
	if photo_pair.visible:
		width = minf(300, root.size.x - 40)
		height = minf(64, root.size.y - 48)
	main_menu_view.layout()
	dialog.position = Vector2((root.size.x - width) * 0.5, root.size.y - height - 20)
	dialog.size = Vector2(width, height)
	layout_portrait()
	layout_guide()
	var choice_height := 54.0
	# Reserve scrollbar and caption margins before measuring wrapped replies.
	var caption_width := maxf(1, width - 24 - 24 - choice_scroll.get_v_scroll_bar().get_combined_minimum_size().x)
	for button in choices.get_children():
		var text: Label = button.get_node("Text")
		var font := text.get_theme_font("font")
		var measured := font.get_multiline_string_size(text.text, HORIZONTAL_ALIGNMENT_CENTER, caption_width, text.get_theme_font_size("font_size"))
		choice_height = maxf(choice_height, measured.y + 18)
	for button in choices.get_children():
		button.custom_minimum_size.y = choice_height
	var choices_height := choice_height * current_options.size() + 6 * maxi(0, current_options.size() - 1)
	var has_body := not words.text.is_empty()
	if showing_choices and not has_body:
		# Empty story lines are choice-only beats. Let the choices use the whole
		# interior so short alternatives such as Sign / Refuse appear together.
		dialogue_scroll.custom_minimum_size.y = 0
		choice_scroll.custom_minimum_size.y = 0
		choice_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		choice_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		if showing_choices:
			# Keep two readable lines of story text visible above its choices.
			var body_min_height := words.get_line_height() * 2.0 + 2.0
			dialogue_scroll.custom_minimum_size.y = body_min_height
			var panel_style := dialog.get_theme_stylebox("panel")
			var panel_insets := panel_style.get_minimum_size().y
			var column_gaps: float = float(dialog_column.get_theme_constant("separation")) * 2.0
			var available_choice_height := maxf(0.0, height - panel_insets - speaker.get_combined_minimum_size().y - column_gaps - body_min_height)
			choice_scroll.custom_minimum_size.y = minf(choices_height, available_choice_height)
		else:
			dialogue_scroll.custom_minimum_size.y = 0
			choice_scroll.custom_minimum_size.y = 0

	layout_photo_pair()

func layout_portrait() -> void:
	# The panel stays in front; the visible silhouette ends at its top edge.
	portrait_stage.size = Vector2(root.size.x, maxf(0, dialog.position.y + 2))
	var portrait_space := Vector2(maxf(0, root.size.x - 40), maxf(0, dialog.position.y - 28))
	var portrait_size := portrait_space
	var portrait_top := 14.0
	if portrait.texture != null:
		var image_size := portrait.texture.get_size()
		var hip_fraction := float(portrait.texture.get_meta("dialogue_hip_fraction", 1.0))
		var relative_height := float(portrait.texture.get_meta("dialogue_height", 1.0))
		var visible_height := portrait_space.y * relative_height
		var scale_factor := minf(portrait_space.x / image_size.x, visible_height / (image_size.y * hip_fraction))
		portrait_size = image_size * scale_factor
		# The hips remain at the panel when width limits scaling on narrow screens.
		portrait_top = dialog.position.y - portrait_size.y * hip_fraction
		if hip_fraction >= 1.0:
			portrait_top = 14 + (portrait_space.y - portrait_size.y) * .5
	# Symmetric offsets keep the portrait centered even during viewport resizing.
	portrait.offset_left = -portrait_size.x * .5
	portrait.offset_right = portrait_size.x * .5
	portrait.offset_top = portrait_top
	portrait.offset_bottom = portrait.offset_top + portrait_size.y

func show_line(who: String, text: String, image: Texture2D, options: Array, minimum_pause: float = 0, portrait_mode: String = "speaker") -> void:
	pause_timer.stop()
	if text_tween:
		text_tween.kill()
	if dialog.get_theme_stylebox("panel") is StyleBoxEmpty and photo_dialog_style != null:
		dialog.add_theme_stylebox_override("panel", photo_dialog_style)
	speaker.show()
	words.show()
	dialogue_scroll.visible = not text.is_empty()
	choices.show()
	next_button.text = "Продолжить"
	speaker.text = who
	words.text = text
	words.visible_characters = 0
	words.visible = not text.is_empty()
	dialogue_scroll.scroll_vertical = 0
	choice_scroll.scroll_vertical = 0
	current_options = options
	showing_choices = not options.is_empty()
	for old in choices.get_children():
		choices.remove_child(old)
		old.queue_free()
	for index in options.size():
		var button := make_button("", func(): select_choice(index))
		button.disabled=options[index].get("disabled",false)
		var caption := Label.new()
		caption.name = "Text"
		caption.text = options[index]["text"]
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		caption.add_theme_font_size_override("font_size", 19)
		caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		caption.offset_left = 12
		caption.offset_right = -12
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(caption)
		choices.add_child(button)
	choice_scroll.visible = showing_choices
	next_button.visible = not showing_choices
	photo_pair.hide()
	show_portrait(image, portrait_mode)
	dialog.show()
	action_button.hide()
	hint.hide()
	crosshair.hide()
	touch.reset()
	touch.hide()
	line_ready = minimum_pause <= 0
	next_button.disabled = not line_ready
	text_tween = create_tween()
	if text.is_empty(): text_tween.tween_interval(.01)
	# Shape the whole line once; reveal glyphs without re-centering or rewrapping.
	for index in text.length():
		text_tween.tween_interval(1.0 / voice_speed)
		text_tween.tween_callback(reveal_character.bind(index+1,text[index]))
		if text[index] in [",", ";", ":"]: text_tween.tween_interval(.14)
		elif text[index] in [".", "!", "?", "…"]: text_tween.tween_interval(.28)
	layout_dialog()
	layout_dialog.call_deferred()
	if minimum_pause > 0: pause_timer.start(minimum_pause)

func show_portrait(image: Texture2D, mode: String) -> void:
	if portrait_tween: portrait_tween.kill()
	# Only dialogue context may retain a sprite. An unknown new speaker clears it.
	if mode != "background" or image != null:
		var changed := portrait.texture != image
		portrait.texture = image
		if changed: portrait.self_modulate = Color.WHITE
	portrait.visible = portrait.texture != null
	if not portrait.visible: return
	var tint := Color(.48, .48, .54) if mode == "background" else Color.WHITE
	portrait_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	portrait_tween.tween_property(portrait, "self_modulate", tint, .2)

func clear_portrait() -> void:
	if portrait_tween: portrait_tween.kill()
	portrait.hide()
	portrait.texture = null
	portrait.self_modulate = Color.WHITE

func pause_portrait(value: bool) -> void:
	if portrait_tween and portrait_tween.is_valid():
		if value: portrait_tween.pause()
		else: portrait_tween.play()

func reveal_character(count: int, letter: String) -> void:
	words.visible_characters=count
	if not menu.visible: character_revealed.emit(letter)

func advance() -> void:
	if not dialog.visible or not line_ready:
		return
	if words.visible_characters >= 0 and words.visible_characters < words.text.length():
		if text_tween: text_tween.kill()
		words.visible_characters = -1
		voice_stopped.emit()
		return
	if not showing_choices:
		advance_requested.emit()

func select_choice(index: int) -> void:
	if dialog.visible and line_ready and index >= 0 and index < current_options.size():
		choice_selected.emit(index)

func close_dialog() -> void:
	voice_stopped.emit()
	pause_timer.stop()
	if text_tween: text_tween.kill()
	dialog.hide()
	clear_portrait()
	photo_pair.hide()
	hint.hide()
	crosshair.show()
	touch.visible = touch_enabled and not menu.visible

func set_hint(value: String) -> void:
	hint.text = ("E · " if not touch_enabled else "")+value if not value.is_empty() else ""
	hint.visible=not value.is_empty() and not menu.visible and not dialog.visible
	action_button.hide()

func set_focus_bounds(bounds: Rect2) -> void:
	var available := bounds.has_area() and not dialog.visible and not menu.visible
	focus_frame.visible = false # Geometry shader highlights the actual object silhouette.
	touch.target_rect = bounds if available else Rect2()
	if available:
		focus_frame.position = bounds.position
		focus_frame.size = bounds.size
		hint.visible=not hint.text.is_empty()
	else:hint.hide()

func show_photo_pair(before: Texture2D, _after: Texture2D = null) -> void:
	pause_timer.stop()
	if text_tween: text_tween.kill()
	line_ready = true
	speaker.hide()
	words.hide()
	choices.hide()
	dialogue_scroll.hide()
	choice_scroll.hide()
	if not dialog.get_theme_stylebox("panel") is StyleBoxEmpty:
		photo_dialog_style = dialog.get_theme_stylebox("panel")
	dialog.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	next_button.text = "Назад"
	next_button.disabled = false
	next_button.show()
	words.visible_characters = -1
	clear_portrait()
	for child in photo_pair.get_children():
		photo_pair.remove_child(child); child.queue_free()
	# Only the original photograph is displayed, including old saved photo nodes.
	for entry in [["ДО", before]]:
		var column := VBoxContainer.new();column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		photo_pair.add_child(column)
		var title := Label.new();title.text=entry[0];title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(title)
		var picture := TextureRect.new();picture.texture=entry[1];picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(picture)
		if entry[1] == null:
			var missing := Label.new();missing.text="Снимок не сохранился";missing.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;column.add_child(missing)
	photo_pair.show()
	layout_dialog()
	# Container sizing settles after the dialogue line and its choices update.
	layout_photo_pair.call_deferred()

func layout_photo_pair() -> void:
	if not is_instance_valid(photo_pair) or not photo_pair.visible: return
	var height := maxf(0, dialog.position.y - 32)
	var width := minf(root.size.x - 40, height)
	photo_pair.position = Vector2((root.size.x - width) / 2, 16)
	photo_pair.size = Vector2(maxf(0, width), height)

func set_objective(area: String, text: String, has_hairpin: bool = false) -> void:
	chapter.text = area
	# The label swaps to the new text once the old one has faded out.
	guide_text = text
	chapter.hide()
	item.text = "Невидимка" if has_hairpin else ""

func build_guide() -> void:
	guide = Control.new()
	guide.name = "Guide"
	guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(guide)
	# A plain panel sized by hand: an autowrapped label inside a container
	# reports its height for a zero width and would stretch the panel.
	guide_panel = Panel.new()
	guide_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.067, 0.047, 0.071, 0.62)
	style.border_color = Color(GUIDE_BRASS, 0.6)
	style.border_width_bottom = 1
	style.border_width_top = 1
	guide_panel.add_theme_stylebox_override("panel", style)
	guide.add_child(guide_panel)
	objective = Label.new()
	objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
	objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Top-aligned so a stale wrapped minimum height cannot push the text down.
	objective.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective.add_theme_font_size_override("font_size", 19)
	objective.add_theme_color_override("font_color", GUIDE_IVORY)
	objective.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	objective.add_theme_constant_override("shadow_offset_x", 1)
	objective.add_theme_constant_override("shadow_offset_y", 1)
	guide_panel.add_child(objective)
	guide_arrow = Control.new()
	guide_arrow.name = "GuideArrow"
	guide_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	guide_arrow.size = Vector2(38, 38)
	guide_arrow.pivot_offset = guide_arrow.size * 0.5
	guide_arrow.draw.connect(draw_guide_arrow)
	guide.add_child(guide_arrow)
	guide.modulate.a = 0
	guide_arrow.modulate.a = 0
	guide.hide()

func layout_guide() -> void:
	if not is_instance_valid(guide): return
	var text := objective.text if not objective.text.is_empty() else guide_text
	var font := objective.get_theme_font("font")
	var font_size := objective.get_theme_font_size("font_size")
	# Stay clear of the pause button (and its touch zone) on the right.
	var available := maxf(150, root.size.x - 232)
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var width := minf(ceilf(text_width) + 48, available)
	var inner := width - 44
	var text_height := ceilf(font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, inner, font_size).y)
	objective.position = Vector2(22, 6)
	objective.size = Vector2(inner, 0)
	# Wrapped lines in a Label carry extra spacing the font measure misses.
	if objective.text == text: text_height = maxf(text_height, ceilf(objective.get_minimum_size().y))
	objective.size = Vector2(inner, text_height)
	var panel_height := text_height + 13
	guide_panel.position = Vector2.ZERO
	guide_panel.size = Vector2(width, panel_height)
	var top := 12.0 if root.size.y < 500 else 18.0
	guide.position = Vector2(roundf((root.size.x - width) * 0.5), top)
	guide.size = Vector2(width, panel_height + 44)
	guide_arrow.position = Vector2(roundf(width * 0.5 - guide_arrow.size.x * 0.5), panel_height + 7)

func set_guide(active: bool, angle: float = 0.0, has_direction: bool = false) -> void:
	guide_active = active
	guide_has_direction = has_direction
	if has_direction: guide_angle = angle

func _process(delta: float) -> void:
	if not is_instance_valid(guide): return
	var shown := guide_active and not guide_text.is_empty() and not menu.visible and not dialog.visible and not fade.visible and not story_backdrop.visible and not photo_pair.visible
	if objective.text != guide_text:
		# Fade the old objective out before showing the new one.
		guide_alpha = move_toward(guide_alpha, 0.0, delta * 4.0)
		if guide_alpha <= 0.0:
			objective.text = guide_text
			layout_guide()
	else:
		guide_alpha = move_toward(guide_alpha, 1.0 if shown else 0.0, delta * (2.2 if shown else 5.0))
	var arrow_shown := shown and guide_has_direction and objective.text == guide_text
	var arrow_was_hidden := guide_arrow_alpha <= 0.01
	guide_arrow_alpha = move_toward(guide_arrow_alpha, 1.0 if arrow_shown else 0.0, delta * (2.5 if arrow_shown else 5.0))
	guide.visible = guide_alpha > 0.0
	guide.modulate.a = ease(guide_alpha, 0.6)
	guide_arrow.modulate.a = ease(guide_arrow_alpha, 0.6)
	if guide_has_direction:
		if arrow_was_hidden: guide_arrow.rotation = guide_angle
		else: guide_arrow.rotation = wrapf(lerp_angle(guide_arrow.rotation, guide_angle, 1.0 - exp(-delta * 10.0)), -PI, PI)
	var aligned := absf(wrapf(guide_arrow.rotation, -PI, PI)) < 0.2
	if aligned != guide_aligned:
		guide_aligned = aligned
		guide_arrow.queue_redraw()

func draw_guide_arrow() -> void:
	var center := guide_arrow.size * 0.5
	guide_arrow.draw_circle(center, 17.5, Color(0.067, 0.047, 0.071, 0.62))
	guide_arrow.draw_arc(center, 17.5, 0, TAU, 44, Color(GUIDE_IVORY if guide_aligned else GUIDE_BRASS, 0.75), 1.0, true)
	# Arrow with a short stem, pointing up; the control's rotation turns it.
	# A bare notched head read as a chevron pointing backwards at this size.
	var shape := PackedVector2Array()
	for point in [Vector2(0, -12), Vector2(8, -2), Vector2(2.6, -2), Vector2(2.6, 10), Vector2(-2.6, 10), Vector2(-2.6, -2), Vector2(-8, -2)]:
		shape.append(center + point)
	var outline := shape.duplicate()
	outline.append(shape[0])
	guide_arrow.draw_colored_polygon(shape, GUIDE_IVORY if guide_aligned else Color(GUIDE_IVORY, 0.82))
	guide_arrow.draw_polyline(outline, Color(0, 0, 0, 0.45), 1.0, true)

func show_notice(text: String) -> void:
	if notice_tween: notice_tween.kill()
	notice.text = text
	notice.modulate.a = 1
	notice_tween = create_tween()
	notice_tween.tween_interval(3)
	notice_tween.tween_property(notice, "modulate:a", 0.0, 0.5)

func show_menu(kind: String, can_continue: bool = false) -> void:
	menu_scroll.scroll_vertical=0
	for child in menu_column.get_children():
		menu_column.remove_child(child)
		child.queue_free()
	var heading := Label.new()
	heading.text = "LAST SHOW" if kind == "main" else ((ending_title if not ending_title.is_empty() else "Конец игры") if kind == "end" else "Пауза")
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	heading.add_theme_font_size_override("font_size", 34)
	menu_column.add_child(heading)
	if kind == "pause":
		menu_column.add_child(make_button("Продолжить", func(): menu_action.emit("resume")))
		menu_column.add_child(make_button("Настройки", show_settings))
		menu_column.add_child(make_button("Главное меню", func(): menu_action.emit("main_menu")))
	elif kind == "end":
		var description:=Label.new();description.text=ending_description;description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		description.custom_minimum_size.x=0;menu_column.add_child(description)
		menu_column.add_child(make_button("Новая игра", func(): menu_action.emit("new_game")))
		menu_column.add_child(make_button("Концовки", func(): menu_action.emit("endings")))
		menu_column.add_child(make_button("Главное меню", func(): menu_action.emit("main_menu")))
	else:
		if can_continue:
			menu_column.add_child(make_button("Продолжить", func(): menu_action.emit("continue")))
		menu_column.add_child(make_button("Новая игра", func(): menu_action.emit("new_game")))
		menu_column.add_child(make_button("Настройки", show_settings))
		menu_column.add_child(make_button("Концовки", func(): menu_action.emit("endings")))
		menu_column.add_child(make_button("Выйти", func(): menu_action.emit("quit")))
	if kind == "main":
		var primary := true
		for child in menu_column.get_children():
			if child is Button:
				main_menu_view.style_button(child, primary)
				primary = false
	main_menu_view.configure(kind == "main", menu_column, menu_scroll)
	menu.color = Color(0.025, 0.025, 0.04, .25 if kind == "main" else .94)
	menu.show()
	action_button.hide()
	touch.reset()
	touch.hide()
	hint.hide()
	crosshair.hide()

func show_endings(found:Array,definitions:Dictionary) -> void:
	main_menu_view.configure(false, menu_column, menu_scroll)
	menu.color = Color(0.025, 0.025, 0.04, .94)
	for child in menu_column.get_children():menu_column.remove_child(child);child.queue_free()
	var title:=Label.new();title.text="Концовки · "+str(found.size())+" / "+str(definitions.size())
	title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;menu_column.add_child(title)
	for id in definitions:
		var row:=Label.new();row.text=("✓ "+definitions[id][0]) if found.has(id) else "Не открыта"
		row.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;row.custom_minimum_size.x=0
		menu_column.add_child(row)
	menu_column.add_child(make_button("Назад",func():menu_action.emit("settings_back")))
	menu.show()

func hide_menu() -> void:
	menu.hide()
	if not dialog.visible:
		touch.visible = touch_enabled
		hint.hide()
		crosshair.show()

func show_settings() -> void:
	main_menu_view.configure(false, menu_column, menu_scroll)
	menu.color = Color(0.025, 0.025, 0.04, .94)
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
	for element in [item]:
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

func set_voice(id: String) -> void:
	current_voice=id
	voice_started.emit(id)
	var voices := {
		"mordecai": [Color("ba8771"), 24.0, "Реплика"],
		"bruno": [Color("a8b4bd"), 18.0, "Слушать"],
		"elsa": [Color("91b9c9"), 20.0, "Слушать"],
		"lili": [Color("d1a0b5"), 28.0, "Дальше"],
		"walter": [Color("a6c0ab"), 21.0, "Слушать"]}
	var voice: Array = voices.get(id, [Color("c3b79f"), 22.0, "Продолжить"])
	voice_color = voice[0]
	voice_speed = voice[1]
	speaker.add_theme_color_override("font_color", voice_color)
	var style := panel_style()
	style.border_color = voice_color.darkened(.25)
	style.bg_color = Color("15191d").lerp(voice_color, .07)
	dialog.add_theme_stylebox_override("panel", style)
	next_button.text = "Продолжить"
	words.add_theme_font_override("font", preload("res://assets/fonts/SpecialElite-Regular.ttf") if id == "walter" else preload("res://assets/fonts/DejaVuSerif.ttf"))
