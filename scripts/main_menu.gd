extends Control
## Presentation only: actions and save handling remain owned by the HUD/game.
const TITLE_FONT = preload("res://assets/fonts/DejaVuSerifCondensed-Bold.ttf")
const CHARACTER = preload("res://assets/characters/colored/mordecai.png")
const IVORY := Color("ecd9b8")
const BRASS := Color("a17b50")
const RED := Color("8c292c")

class TitleRule extends Control:
	func _draw() -> void:
		var center := size * .5
		draw_line(Vector2(0, center.y), Vector2(center.x - 13, center.y), Color("a17b50"), 1.0, true)
		draw_line(Vector2(center.x + 13, center.y), Vector2(size.x, center.y), Color("a17b50"), 1.0, true)
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(0, -7), center + Vector2(6, 0),
			center + Vector2(0, 7), center + Vector2(-6, 0)]), Color("8c292c"))

var character: TextureRect
var active := false
var column: VBoxContainer
var scroll: ScrollContainer

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fabric := ShaderMaterial.new()
	fabric.shader = preload("res://assets/shaders/menu_stage.gdshader")
	backdrop.material = fabric
	add_child(backdrop)
	character = TextureRect.new()
	character.texture = CHARACTER
	character.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	character.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	character.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(character)
	resized.connect(layout)
	hide()

func configure(value: bool, buttons: VBoxContainer, viewport_scroll: ScrollContainer) -> void:
	active = value
	visible = value
	column = buttons
	scroll = viewport_scroll
	layout()

func layout() -> void:
	if not is_instance_valid(column): return
	var wide := size.x >= 760
	var compact := size.y < 520
	var width := minf(440, size.x * .36) if wide else minf(420, size.x - 48)
	var left := size.x * .07 if wide else (size.x - width) * .5
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = (12 if compact else 36) if active else 20
	scroll.offset_bottom = -scroll.offset_top
	scroll.offset_left = left if active else 20.0
	scroll.offset_right = left + width - size.x if active else -20.0
	column.custom_minimum_size.x = maxf(0, width - 16) if active else minf(380, size.x - 64)
	column.add_theme_constant_override("separation", (7 if compact else 10) if active else 13)
	if not active: return
	if column.get_child_count() > 0:
		var heading := column.get_child(0) as Label
		if heading:
			heading.text = "LAST SHOW" if compact else "LAST\nSHOW"
			heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if wide else HORIZONTAL_ALIGNMENT_CENTER
			heading.add_theme_font_override("font", TITLE_FONT)
			heading.add_theme_font_size_override("font_size", int(minf(42, width * .115) if compact else minf(112, width * .265)))
			heading.add_theme_constant_override("line_spacing", -22 if not compact else 0)
			heading.add_theme_color_override("font_color", IVORY)
			heading.add_theme_color_override("font_shadow_color", Color(0, 0, 0, .65))
			heading.add_theme_constant_override("shadow_offset_y", 3)
			var rule := heading.get_node_or_null("TitleRule")
			if rule == null:
				rule = TitleRule.new()
				rule.name = "TitleRule"
				rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
				heading.add_child(rule)
				rule.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
				rule.offset_top = -5
				rule.offset_bottom = 7
			rule.visible = not compact
			rule.queue_redraw()
	for child in column.get_children():
		if child is Button:
			child.custom_minimum_size.y = 48 if compact else 58
			child.add_theme_font_size_override("font_size", 23 if compact else 27)
	# The artist's complete PNG remains untouched; the stage clips the lower body.
	character.visible = wide
	var image_height := size.y * 1.57
	var image_size := CHARACTER.get_size() * (image_height / CHARACTER.get_height())
	character.size = image_size
	character.position = Vector2(size.x * .755 - image_size.x * .5, 24)

func style_button(button: Button, primary: bool) -> void:
	button.set_meta("menu_primary", primary)
	button.focus_mode = Control.FOCUS_ALL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_color_override("font_color", Color("25181d") if primary else IVORY)
	button.add_theme_color_override("font_hover_color", Color("25181d") if primary else Color("fff0d5"))
	button.add_theme_color_override("font_pressed_color", Color("25181d") if primary else IVORY)
	button.add_theme_color_override("font_focus_color", Color("25181d") if primary else Color("fff0d5"))
	button.add_theme_stylebox_override("normal", button_style(IVORY if primary else Color("110c12e8"), BRASS))
	button.add_theme_stylebox_override("hover", button_style(Color("fff0d5") if primary else Color("32202a"), IVORY))
	button.add_theme_stylebox_override("pressed", button_style(Color("c4a782") if primary else Color("4b242c"), BRASS))
	var focus := button_style(Color.TRANSPARENT, IVORY)
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override("focus", focus)
	var arrow := Label.new()
	arrow.text = "▸"
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow.add_theme_color_override("font_color", RED if primary else BRASS)
	arrow.add_theme_font_size_override("font_size", 28)
	button.add_child(arrow)
	arrow.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	arrow.offset_left = -40
	arrow.offset_right = -16
	arrow.offset_top = -20
	arrow.offset_bottom = 20
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func button_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 22
	style.content_margin_right = 48
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style
