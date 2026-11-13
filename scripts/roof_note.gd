extends CanvasLayer
## Close-up of the folded note on the east roof deck. A sheet of paper fills
## the middle of the screen with one handwritten line; any key, click or tap
## puts it back down.
const TEXT := "Точно ли это то,\nчего ты хочешь,\nРичард?"
const PAPER := Color("e9e0c9")
const INK := Color("2a2230")

var game
var dim: ColorRect
var sheet: Control
var hand: FontVariation
var tween: Tween
var opened_at := 0

func setup(owner_game) -> void:
	game = owner_game
	layer = 8
	dim = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, .72)
	add_child(dim)
	sheet = Control.new()
	sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.draw.connect(draw_sheet)
	add_child(sheet)
	hand = FontVariation.new()
	hand.base_font = preload("res://assets/fonts/DejaVuSerif.ttf")
	# Forward slant and slightly narrow letters read as quick handwriting.
	hand.variation_transform = Transform2D(Vector2(.86, 0), Vector2(-.3, 1), Vector2.ZERO)
	hand.spacing_glyph = -1
	visible = false

func is_open() -> bool:
	return visible

func open() -> void:
	if visible: return
	game.player.set_locked(true)
	game.audio.play("sfx_photo_take", -10)
	visible = true
	opened_at = Time.get_ticks_msec()
	layout()
	dim.modulate.a = 0
	sheet.modulate.a = 0
	sheet.scale = Vector2(.9, .9)
	if tween: tween.kill()
	tween = create_tween().set_parallel(true)
	tween.tween_property(dim, "modulate:a", 1.0, .25)
	tween.tween_property(sheet, "modulate:a", 1.0, .25)
	tween.tween_property(sheet, "scale", Vector2.ONE, .3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func close() -> void:
	if not visible: return
	game.audio.play("sfx_photo_drop", -12)
	if tween: tween.kill()
	tween = create_tween().set_parallel(true)
	tween.tween_property(dim, "modulate:a", 0.0, .2)
	tween.tween_property(sheet, "modulate:a", 0.0, .2)
	tween.chain().tween_callback(func():
		visible = false
		if not game.transitioning and not game.hud.dialog.visible: game.player.set_locked(false))

func reset() -> void:
	if tween: tween.kill()
	visible = false

func layout() -> void:
	var view: Vector2 = get_viewport().get_visible_rect().size
	var height := minf(view.y * .78, view.x * .9 / .78)
	sheet.size = Vector2(height * .78, height)
	sheet.position = (view - sheet.size) / 2
	sheet.pivot_offset = sheet.size / 2
	sheet.rotation = -.03

func _input(event: InputEvent) -> void:
	if not visible: return
	if event is InputEventMouseMotion or event is InputEventScreenDrag: return
	get_viewport().set_input_as_handled()
	# Ignore the press that opened the note.
	if Time.get_ticks_msec() - opened_at < 250: return
	if event.is_pressed() and not event.is_echo(): close()

func draw_sheet() -> void:
	var s := sheet.size
	# Paper with a soft shadow, a fold across the middle and worn edges.
	sheet.draw_rect(Rect2(Vector2(8, 10), s), Color(0, 0, 0, .35))
	sheet.draw_rect(Rect2(Vector2.ZERO, s), PAPER)
	sheet.draw_rect(Rect2(0, s.y * .5, s.x, s.y * .5), Color(0, 0, 0, .04))
	sheet.draw_line(Vector2(0, s.y * .5), Vector2(s.x, s.y * .5), Color("bfb397"), 2)
	sheet.draw_line(Vector2(0, s.y * .5 + 2), Vector2(s.x, s.y * .5 + 2), Color(1, 1, 1, .35), 1)
	for i in 6:
		sheet.draw_circle(Vector2(s.x * (.15 + i * .14), s.y * (.82 + (i % 2) * .05)), s.x * .03, Color("a99a78", .08))
	# One line in pencil-dark ink. Each letter wobbles a little on its own.
	var size := int(s.x * .095)
	var lines := TEXT.split("\n")
	var line_height := size * 1.55
	var top := s.y * .5 - line_height * (lines.size() - 1) * .5 - s.y * .06
	var seed := 7
	for row in lines.size():
		var line: String = lines[row]
		var width := hand.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var pen := Vector2((s.x - width) * .5 + (row - 1) * s.x * .03, top + row * line_height)
		for letter in line:
			seed = (seed * 1103515245 + 12345) & 0x7fffffff
			var jitter := float(seed % 1000) / 1000.0 - .5
			var advance := hand.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			sheet.draw_set_transform(pen + Vector2(0, jitter * size * .08), jitter * .07)
			sheet.draw_string(hand, Vector2.ZERO, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, size, INK.lerp(Color("4a4250"), absf(jitter)))
			pen.x += advance
		sheet.draw_set_transform(Vector2.ZERO)
	var close_hint := "Нажми, чтобы положить" if game.hud.touch_enabled else "Любая клавиша: положить"
	var font: Font = preload("res://assets/fonts/DejaVuSerif.ttf")
	var hint_size := int(clampf(s.x * .035, 13, 18))
	var hint_width := font.get_string_size(close_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, hint_size).x
	sheet.draw_string(font, Vector2((s.x - hint_width) * .5, s.y - hint_size * 1.4), close_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, hint_size, Color("8a7c62"))
