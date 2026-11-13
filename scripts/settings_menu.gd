extends Node
## Settings page in the main menu's velvet-and-brass dress. Every control is a
## large tap target that works from touch events alone: the project does not
## emulate the mouse from touch, and Godot's sliders ignore raw touches.
const MAIN_MENU = preload("res://scripts/main_menu.gd")
const IVORY := Color("ecd9b8")
const BRASS := Color("a17b50")
const RED := Color("8c292c")
const INK := Color("25181d")
const DIM := Color("b8a585")
var hud
var active := false
var panel: PanelContainer
var columns: GridContainer
var rows: Array[Control] = []
var compact := false
var quality_row: Control
var smoothing_row: Control
var sharpness_row: Control
var shadows_row: Control
const PRESET_IDS := ["low", "medium", "high"]

class ValueBar extends Control:
	## Brass notches like a theatre dimmer board. Tap or drag anywhere on it.
	signal value_changed(value: float)
	const NOTCHES := 20
	var min_value := 0.0
	var max_value := 1.0
	var step := .05
	var value := 0.0
	var dragging := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func set_value(amount: float, notify := true) -> void:
		amount = clampf(snappedf(amount, step), min_value, max_value)
		if is_equal_approx(amount, value): return
		value = amount
		queue_redraw()
		if notify: value_changed.emit(value)

	func pick(x: float) -> void:
		var inset := 14.0
		var ratio := clampf((x - inset) / maxf(1.0, size.x - inset * 2), 0.0, 1.0)
		set_value(lerpf(min_value, max_value, ratio))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			if event.pressed: pick(event.position.x)
			accept_event()
		elif event is InputEventScreenDrag:
			pick(event.position.x)
			accept_event()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			if event.pressed: pick(event.position.x)
			accept_event()
		elif event is InputEventMouseMotion and dragging:
			pick(event.position.x)
			accept_event()

	func _draw() -> void:
		var frame := StyleBoxFlat.new()
		frame.bg_color = Color("110c12e8")
		frame.border_color = BRASS
		frame.set_border_width_all(1)
		frame.set_corner_radius_all(4)
		draw_style_box(frame, Rect2(Vector2.ZERO, size))
		var inset := 14.0
		var span := size.x - inset * 2
		var ratio := inverse_lerp(min_value, max_value, value) if max_value > min_value else 0.0
		var gap := span / NOTCHES
		for i in NOTCHES:
			var lit := (i + .5) / NOTCHES <= ratio + .001
			var height := size.y * (.30 + .30 * float(i) / (NOTCHES - 1))
			var rect := Rect2(inset + i * gap + gap * .18, (size.y - height) * .5, gap * .64, height)
			draw_rect(rect, IVORY if lit else Color(BRASS, .35))
		# The red lozenge from the title rule marks the exact value.
		var center := Vector2(inset + span * ratio, size.y * .5)
		var r := minf(11.0, size.y * .22)
		draw_colored_polygon(PackedVector2Array([center + Vector2(0, -r * 1.5), center + Vector2(r, 0), center + Vector2(0, r * 1.5), center + Vector2(-r, 0)]), RED)
		draw_polyline(PackedVector2Array([center + Vector2(0, -r * 1.5), center + Vector2(r, 0), center + Vector2(0, r * 1.5), center + Vector2(-r, 0), center + Vector2(0, -r * 1.5)]), IVORY, 1.5, true)

func setup(owner_hud) -> void:
	hud = owner_hud

func build(column: VBoxContainer) -> void:
	active = true
	rows.clear()
	var heading := Label.new()
	heading.text = "Настройки"
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_override("font", MAIN_MENU.TITLE_FONT)
	heading.add_theme_font_size_override("font_size", 38)
	heading.add_theme_color_override("font_color", IVORY)
	heading.add_theme_color_override("font_shadow_color", Color(0, 0, 0, .65))
	heading.add_theme_constant_override("shadow_offset_y", 3)
	column.add_child(heading)
	var rule := MAIN_MENU.TitleRule.new()
	rule.custom_minimum_size = Vector2(0, 14)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)
	panel = PanelContainer.new()
	var velvet := StyleBoxFlat.new()
	velvet.bg_color = Color(.075, .035, .05, .92)
	velvet.border_color = Color(BRASS, .8)
	velvet.set_border_width_all(1)
	velvet.set_corner_radius_all(6)
	velvet.content_margin_left = 24; velvet.content_margin_right = 24
	velvet.content_margin_top = 16; velvet.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", velvet)
	column.add_child(panel)
	columns = GridContainer.new()
	columns.add_theme_constant_override("h_separation", 36)
	columns.add_theme_constant_override("v_separation", 10)
	panel.add_child(columns)
	var left := section_column()
	var right := section_column()
	var mood := section_column()
	section(left, "Звук и управление")
	left.add_child(value_row("Громкость", 0.0, 1.0, .05, hud.volume,
		func(value): return str(roundi(value * 100)) + "%",
		func(value): hud.volume = value; hud.settings_changed.emit(hud.volume, hud.sensitivity)))
	left.add_child(value_row("Чувствительность обзора", .4, 2.5, .1, hud.sensitivity,
		func(value): return "%.1f×" % value,
		func(value): hud.sensitivity = value; hud.settings_changed.emit(hud.volume, hud.sensitivity)))
	var graphics = hud.graphics
	if graphics:
		section(left, "Экран")
		left.add_child(choice_row("Частота кадров", ["30", "60", "Макс."], graphics.FPS_LIMITS.find(graphics.fps_limit),
			func(index): graphics.set_option("fps_limit", graphics.FPS_LIMITS[index])))
		left.add_child(choice_row("Счётчик кадров", ["Скрыт", "Показан"], 1 if graphics.show_fps else 0,
			func(index): graphics.set_option("show_fps", index == 1)))
		section(right, "Изображение")
		quality_row = choice_row("Качество", ["Низкое", "Среднее", "Высокое"], PRESET_IDS.find(graphics.preset),
			func(index): graphics.set_preset(PRESET_IDS[index]))
		smoothing_row = choice_row("Сглаживание", ["Выкл.", "FXAA", "MSAA 2×", "MSAA 4×"], graphics.aa,
			func(index): graphics.set_option("aa", index))
		sharpness_row = choice_row("Чёткость 3D", ["50%", "70%", "85%", "100%"], nearest_scale(graphics.scale),
			func(index): graphics.set_option("scale", graphics.SCALES[index]))
		shadows_row = choice_row("Тени", ["Выкл", "Ближние", "Больше"], graphics.shadows,
			func(index): graphics.set_option("shadows", index))
		for row in [quality_row, smoothing_row, sharpness_row, shadows_row]: right.add_child(row)
		section(mood, "Атмосфера")
		mood.add_child(choice_row("Туман и дымка", ["Нет", "Обычная", "Густая"], graphics.haze,
			func(index): graphics.set_option("haze", index)))
		mood.add_child(choice_row("Освещение", ["Обычное", "Тёмное", "Мрак"], graphics.darkness,
			func(index): graphics.set_option("darkness", index)))
		mood.add_child(choice_row("Зернистость", ["Нет", "Лёгкая", "Сильная"], graphics.grain,
			func(index): graphics.set_option("grain", index)))
		if not graphics.changed.is_connected(refresh): graphics.changed.connect(refresh)
		refresh()
	var back: Button = hud.make_button("Назад", func(): hud.menu_action.emit("settings_back"))
	hud.main_menu_view.style_button(back, false)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.custom_minimum_size.x = minf(260, hud.root.size.x - 64)
	column.add_child(back)
	layout()

# A preset rewrites the three picture options; a manual change clears it.
func refresh() -> void:
	if not active or not is_instance_valid(quality_row): return
	var graphics = hud.graphics
	select(quality_row, PRESET_IDS.find(graphics.preset))
	select(smoothing_row, graphics.aa)
	select(sharpness_row, nearest_scale(graphics.scale))
	select(shadows_row, graphics.shadows)
	caption_note(quality_row, "своё" if graphics.preset == "custom" else "")

func nearest_scale(value: float) -> int:
	var best := 0
	for i in hud.graphics.SCALES.size():
		if absf(hud.graphics.SCALES[i] - value) < absf(hud.graphics.SCALES[best] - value): best = i
	return best

func section_column() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	columns.add_child(box)
	return box

func section(box: VBoxContainer, title: String) -> void:
	var header := Label.new()
	header.text = title.to_upper()
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_theme_color_override("font_color", BRASS)
	header.add_theme_font_size_override("font_size", 16)
	box.add_child(header)
	var line := ColorRect.new()
	line.color = Color(BRASS, .45)
	line.custom_minimum_size.y = 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(line)

func row_shell(title: String) -> VBoxContainer:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var top := HBoxContainer.new()
	row.add_child(top)
	var caption := Label.new()
	caption.name = "Caption"
	caption.text = title
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_theme_color_override("font_color", IVORY)
	caption.add_theme_font_size_override("font_size", 20)
	top.add_child(caption)
	var note := Label.new()
	note.name = "Note"
	note.add_theme_color_override("font_color", DIM)
	note.add_theme_font_size_override("font_size", 19)
	top.add_child(note)
	rows.append(row)
	return row

func caption_note(row: Control, text: String) -> void:
	row.get_child(0).get_node("Note").text = text

func value_row(title: String, low: float, high: float, step: float, value: float, format: Callable, changed: Callable) -> VBoxContainer:
	var row := row_shell(title)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	row.add_child(line)
	var bar := ValueBar.new()
	bar.min_value = low; bar.max_value = high; bar.step = step
	bar.set_value(value, false)
	var minus := segment("−", false)
	var plus := segment("+", false)
	for button in [minus, plus]:
		button.add_theme_font_size_override("font_size", 28)
		button.size_flags_horizontal = Control.SIZE_FILL
	minus.pressed.connect(func(): hud.ui_sound.emit(false); bar.set_value(bar.value - step))
	plus.pressed.connect(func(): hud.ui_sound.emit(false); bar.set_value(bar.value + step))
	line.add_child(minus); line.add_child(bar); line.add_child(plus)
	caption_note(row, format.call(bar.value))
	bar.value_changed.connect(func(amount):
		caption_note(row, format.call(amount))
		changed.call(amount))
	row.set_meta("bar", bar)
	return row

func choice_row(title: String, labels: Array, selected: int, picked: Callable) -> VBoxContainer:
	var row := row_shell(title)
	var line := HBoxContainer.new()
	line.name = "Choices"
	line.add_theme_constant_override("separation", 6)
	row.add_child(line)
	for index in labels.size():
		var button := segment(labels[index], index == selected)
		button.pressed.connect(func():
			hud.ui_sound.emit(false)
			select(row, index)
			picked.call(index))
		line.add_child(button)
	return row

func select(row: Control, index: int) -> void:
	var line: HBoxContainer = row.get_node("Choices")
	for i in line.get_child_count(): restyle(line.get_child(i), i == index)

func segment(text: String, selected: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_text = true
	restyle(button, selected)
	return button

func restyle(button: Button, selected: bool) -> void:
	button.set_meta("selected", selected)
	var text := INK if selected else IVORY
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, text)
	button.add_theme_stylebox_override("normal", fill(IVORY if selected else Color("110c12e8"), IVORY if selected else BRASS))
	button.add_theme_stylebox_override("hover", fill(Color("fff0d5") if selected else Color("32202a"), IVORY))
	button.add_theme_stylebox_override("pressed", fill(Color("c4a782") if selected else Color("4b242c"), BRASS))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

func fill(color: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8; style.content_margin_right = 8
	return style

func layout() -> void:
	if not active or not is_instance_valid(panel): return
	var area: Vector2 = hud.root.size
	# Two columns on landscape screens; a single scrolling column otherwise.
	var wide := area.x >= 900
	compact = area.y < 640
	columns.columns = 3 if area.x >= 1100 else (2 if wide else 1)
	var width := minf(1120, area.x - 64)
	hud.menu_column.custom_minimum_size.x = width
	hud.menu_column.add_theme_constant_override("separation", 6 if compact else 10)
	var control_height := 56 if compact else 64
	for row in rows:
		var line: HBoxContainer = row.get_child(1)
		for control in line.get_children():
			control.custom_minimum_size.y = control_height
			if control is Button:
				control.add_theme_font_size_override("font_size", 28 if control.text in ["−", "+"] else (17 if control.get_parent().get_child_count() >= 4 else (19 if compact else 21)))
				if control.text in ["−", "+"]: control.custom_minimum_size.x = control_height
		var caption: Label = row.get_child(0).get_node("Caption")
		caption.add_theme_font_size_override("font_size", 18 if compact else 20)
