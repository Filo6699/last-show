extends CanvasLayer
## High wire under the canopy. On the wire Richard drifts off balance; the
## player counters with left/right (keys, stick or touch joystick). Gusts and
## walking make it worse. Past the tipping point he falls and dies, then the
## run restarts on the west board.
const RESPAWN := Vector3(-7.3, 40.02, -2)
const RESPAWN_LOOK := Vector3(2.5, 41.3, -2)
const WIRE_SPEED := 1.35
const COUNTER := 3.0

var game
var late
var on_wire := false
var falling := false
var lean := 0.0
var lean_speed := 0.0
var gust := 0.0
var gust_wait := 0.0
var normal_speed := 3.4
var bar: Control
var hint: Label
var black: ColorRect
var title: Label
var rng := RandomNumberGenerator.new()

func setup(owner_game) -> void:
	game = owner_game
	late = game.full_game.late
	layer = 7
	rng.randomize()
	bar = Control.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.offset_left = -200
	bar.offset_right = 200
	bar.offset_top = -150
	bar.offset_bottom = -120
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.draw.connect(draw_bar)
	add_child(bar)
	hint = Label.new()
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_left = -300
	hint.offset_right = 300
	hint.offset_top = -116
	hint.offset_bottom = -86
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color("d6c8aa"))
	add_child(hint)
	black = ColorRect.new()
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.color = Color(0, 0, 0, 0)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)
	title = Label.new()
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color("b23a2e"))
	title.modulate.a = 0
	add_child(title)
	show_ui(false)

func show_ui(value: bool) -> void:
	bar.visible = value
	hint.visible = value

func is_on_wire(p: Vector3) -> bool:
	return game.phase == "roof" and p.x > late.WIRE_A + .15 and p.x < late.WIRE_B - .15 \
		and absf(p.z - late.WIRE_Z) < .9 and p.y > late.ROOF_FLOOR - 1.2 and p.y < late.ROOF_FLOOR + 2

func _physics_process(delta: float) -> void:
	if falling: return
	var p: Vector3 = game.player.global_position
	var wire := is_on_wire(p)
	if wire != on_wire: set_on_wire(wire)
	if not on_wire: return
	# Keep Richard centred on the wire: sideways input leans instead of stepping.
	game.player.global_position.z = late.WIRE_Z
	game.player.velocity.z = 0
	if game.player.locked or game.transitioning or game.hud.menu.visible: return
	gust_wait -= delta
	if gust_wait <= 0:
		gust_wait = rng.randf_range(.6, 1.6)
		gust = rng.randf_range(-.45, .45)
	var walking: float = absf(game.player.velocity.x) / WIRE_SPEED
	var counter := Input.get_axis("move_left", "move_right")
	if game.player.touch_move.length() > .01: counter = game.player.touch_move.x
	# The wire runs east; facing west flips which hand is "right".
	if -game.player.global_basis.z.x < 0: counter = -counter
	lean_speed += (gust * (.8 + walking * .5) + lean * 1.0 + counter * COUNTER) * delta
	lean_speed *= pow(.35, delta)
	lean = clampf(lean + lean_speed * delta, -1.2, 1.2)
	game.player.camera.rotation.z = -lean * .42
	if absf(lean) >= 1.0: fall()

func set_on_wire(value: bool) -> void:
	on_wire = value
	show_ui(value)
	lean = 0.0
	lean_speed = 0.0
	gust = 0.0
	gust_wait = 1.0
	if value:
		normal_speed = game.player.speed
		game.player.speed = WIRE_SPEED
		var touch: bool = game.hud.touch_enabled
		hint.text = "Наклоняй джойстик влево-вправо, чтобы держать равновесие" if touch else "A / D: держать равновесие"
		game.hud.show_notice("Не смотри вниз.")
	else:
		game.player.speed = normal_speed
		game.player.camera.rotation.z = 0

func _process(_delta: float) -> void:
	if on_wire: bar.queue_redraw()

func draw_bar() -> void:
	var w := bar.size.x
	var danger := absf(lean)
	bar.draw_rect(Rect2(0, 10, w, 10), Color(0, 0, 0, .55))
	bar.draw_rect(Rect2(w * .35, 10, w * .3, 10), Color("6f7f5e", .55))
	bar.draw_line(Vector2(w * .5, 4), Vector2(w * .5, 26), Color("d6c8aa", .6), 2)
	var x := w * .5 + clampf(lean, -1, 1) * w * .5
	var color := Color("e7d9b8").lerp(Color("c0392b"), clampf((danger - .4) / .5, 0, 1))
	bar.draw_rect(Rect2(x - 5, 2, 10, 26), color)

func fall() -> void:
	if falling: return
	falling = true
	show_ui(false)
	var token: int = game.session
	game.player.set_locked(true)
	game.player.set_physics_process(false)
	game.transitioning = true
	var side := signf(lean) if lean != 0 else 1.0
	var start: Vector3 = game.player.global_position
	var wind: Node = game.audio.play("sfx_escape_wind", -4)
	game.audio.cue("lili_glimpse")
	var tween := create_tween().set_parallel(true)
	tween.tween_property(game.player.camera, "rotation:z", -side * 1.3, .5)
	tween.tween_property(game.player.camera, "rotation:x", -1.2, 1.1)
	tween.tween_property(game.player, "global_position", start + Vector3(0, -26, side * -2.5), 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(black, "color:a", 1.0, .25).set_delay(1.15)
	await tween.finished
	if token != game.session: return
	if is_instance_valid(wind): wind.stop()
	game.audio.play("sfx_box_bump_01", 0)
	title.text = "РИЧАРД СОРВАЛСЯ"
	var card := create_tween()
	card.tween_property(title, "modulate:a", 1.0, .4)
	card.tween_interval(1.8)
	card.tween_property(title, "modulate:a", 0.0, .4)
	await card.finished
	if token != game.session: return
	game.player.camera.rotation = Vector3.ZERO
	game.player.set_physics_process(true)
	game.place_player(RESPAWN, RESPAWN_LOOK)
	falling = false
	set_on_wire(false)
	game.transitioning = false
	game.player.set_locked(false)
	game.hud.show_notice("Ещё раз. Медленно.")
	create_tween().tween_property(black, "color:a", 0.0, .6)

func reset() -> void:
	falling = false
	if on_wire: set_on_wire(false)
	black.color.a = 0
	title.modulate.a = 0
