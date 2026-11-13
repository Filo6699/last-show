extends CanvasLayer
## Opening cutscene from the screenplay: Richard, ringmaster, runs the last show
## of the season in first person. He sweeps the audience and announces each act;
## each announcement cuts to a short sepia flashback of that act. Ends on
## Richard's stage view and hands over to the "intro" dialogue (bow / applause).
signal finished

var game
var camera: Camera3D
var bars: Array[ColorRect] = []
var caption: Label
var title: Label
var subtitle: Label
var black: ColorRect
var sepia: ColorRect
var flash: ColorRect
var skip_button: Button
var playing := false
var skipped := false
var token := 0
var motion: Array[Tween] = []
var base_yaw := 0.0

func setup(owner_game) -> void:
	game = owner_game
	layer = 20
	camera = Camera3D.new()
	camera.name = "OpeningCamera"
	camera.fov = 62
	game.world.add_child(camera)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	sepia = ColorRect.new()
	sepia.set_anchors_preset(Control.PRESET_FULL_RECT)
	sepia.color = Color(.55, .38, .2, .22)
	sepia.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(sepia)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		if top: bar.offset_bottom = 78
		else: bar.offset_top = -96
		root.add_child(bar)
		bars.append(bar)
	black = ColorRect.new()
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.color = Color.BLACK
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(black)
	flash = ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(1, .96, .88, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash)
	var font: Font = preload("res://assets/fonts/DejaVuSerif.ttf")
	title = Label.new()
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.offset_bottom = -70
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", preload("res://assets/fonts/DejaVuSerifCondensed-Bold.ttf"))
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", Color("d8c39a"))
	root.add_child(title)
	subtitle = Label.new()
	subtitle.set_anchors_preset(Control.PRESET_FULL_RECT)
	subtitle.offset_top = 90
	subtitle.offset_left = 80
	subtitle.offset_right = -80
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_override("font", font)
	subtitle.add_theme_font_size_override("font_size", 22)
	subtitle.add_theme_color_override("font_color", Color("b9a888"))
	root.add_child(subtitle)
	caption = Label.new()
	caption.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_top = -92
	caption.offset_bottom = -12
	caption.offset_left = 60
	caption.offset_right = -60
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_theme_font_override("font", font)
	caption.add_theme_font_size_override("font_size", 24)
	caption.add_theme_color_override("font_color", Color("efe2c6"))
	root.add_child(caption)
	skip_button = Button.new()
	skip_button.text = "Пропустить ›"
	skip_button.focus_mode = Control.FOCUS_NONE
	skip_button.flat = true
	skip_button.add_theme_font_override("font", font)
	skip_button.add_theme_font_size_override("font_size", 18)
	skip_button.add_theme_color_override("font_color", Color("8f8470"))
	skip_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	skip_button.offset_left = -190
	skip_button.offset_right = -18
	skip_button.offset_top = 18
	skip_button.offset_bottom = 60
	skip_button.pressed.connect(skip)
	root.add_child(skip_button)
	visible = false

func _input(event: InputEvent) -> void:
	if not playing: return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER]:
		skip()
		get_viewport().set_input_as_handled()

func skip() -> void:
	if playing: skipped = true

func stop() -> void:
	token += 1
	skipped = true
	_cleanup()

func _cleanup() -> void:
	for tween in motion:
		if tween and tween.is_valid(): tween.kill()
	motion.clear()
	playing = false
	visible = false
	if is_instance_valid(camera) and camera.current: game.player.camera.make_current()
	if is_instance_valid(game) and is_instance_valid(game.location) and game.location.stage_show.cane:
		game.location.stage_show.cane.hide()

# Waits, returns false when the cutscene was skipped or replaced.
func hold(seconds: float, own: int) -> bool:
	var left := seconds
	while left > 0:
		await get_tree().process_frame
		if own != token or skipped: return false
		left -= get_process_delta_time()
	return true

func say(text: String) -> void:
	caption.text = text
	caption.modulate.a = 0
	var tween := create_tween()
	tween.tween_property(caption, "modulate:a", 1.0, .25)
	motion.append(tween)

func cut(flashback: bool) -> void:
	flash.color.a = .85
	var tween := create_tween()
	tween.tween_property(flash, "color:a", 0.0, .35)
	motion.append(tween)
	sepia.visible = flashback

func shot(from: Vector3, look: Vector3, drift: Vector3, seconds: float) -> void:
	camera.global_position = from
	camera.look_at(look)
	camera.make_current()
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(func(t: float):
		camera.global_position = from + drift * t
		camera.look_at(look), 0.0, 1.0, seconds)
	motion.append(tween)

func pov(yaw_offset: float, pitch: float, seconds: float) -> void:
	game.player.camera.make_current()
	sepia.visible = false
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(game.player, "rotation:y", base_yaw + yaw_offset, seconds)
	tween.tween_property(game.player.camera, "rotation:x", pitch, seconds)
	motion.append(tween)

func raise_cane() -> void:
	var cane: MeshInstance3D = game.location.stage_show.cane
	if not cane: return
	cane.show()
	cane.position.y = -.55
	var tween := create_tween()
	tween.tween_property(cane, "position:y", -.1, .35)
	tween.tween_interval(.8)
	tween.tween_property(cane, "position:y", -.55, .4)
	tween.tween_callback(cane.hide)
	motion.append(tween)

func stage_acts() -> void:
	# Performers come out to the ring for the flashbacks only; update_staging
	# returns everyone to their story marks when the scene ends.
	var a: Dictionary = game.actors
	for id in ["elsa", "bruno", "lili", "mordecai"]:
		a[id].show()
		a[id].collision_layer = 0
		game.location.placements.erase(id)
	a.elsa.position = Vector3(4.5, 9.0, 3.5)
	a.elsa.rotation.y = PI
	a.bruno.position = Vector3(-3.2, 1.55, 2.6)
	a.bruno.rotation.y = PI * .85
	a.lili.position = Vector3(game.layout.TRUNK.x, game.LILI_IN_TRUNK_Y, game.layout.TRUNK.z)
	a.lili.hide()
	a.mordecai.position = Vector3(4.2, 1.25, -1.2)
	a.mordecai.rotation.y = -PI * .6

func swing_elsa(seconds: float) -> void:
	var elsa: Node3D = game.actors.elsa
	var tween := create_tween()
	tween.tween_method(func(t: float):
		elsa.position = Vector3(4.5 + sin(t * TAU * 1.2) * 2.6, 9.0 - absf(cos(t * TAU * 1.2)) * .6, 3.5)
		elsa.rotation.z = -sin(t * TAU * 1.2) * .35, 0.0, 1.0, seconds)
	motion.append(tween)

func lift_bruno() -> void:
	var bruno: Node3D = game.actors.bruno
	var tween := create_tween()
	for i in 2:
		tween.tween_property(bruno, "position:y", 1.85, .45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_interval(.3)
		tween.tween_property(bruno, "position:y", 1.55, .3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	motion.append(tween)

func pop_lili() -> void:
	var lili: Node3D = game.actors.lili
	lili.show()
	lili.look_at(Vector3(2.6, lili.position.y, 3.4), Vector3.UP, true)
	var tween := create_tween()
	tween.tween_interval(.5)
	tween.tween_callback(func():
		game.full_game.set_dressing.set_trunk_open(true, true)
		game.sound("box_second"))
	tween.tween_property(lili, "position", lili.position + Vector3(0, 1.75, 0), .35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(lili, "position", game.layout.TRUNK + Vector3(-1.1, .35, 1.3), .4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	motion.append(tween)

func spin_mordecai() -> void:
	var mordecai: Node3D = game.actors.mordecai
	var tween := create_tween()
	tween.tween_property(mordecai, "rotation:y", mordecai.rotation.y + TAU, 1.4).set_trans(Tween.TRANS_SINE)
	tween.tween_property(mordecai, "rotation:x", -.25, .3)
	tween.tween_property(mordecai, "rotation:x", 0.0, .4)
	motion.append(tween)

func play() -> void:
	token += 1
	var own := token
	playing = true
	skipped = false
	visible = true
	caption.text = ""
	sepia.visible = false
	flash.color.a = 0
	black.modulate.a = 1
	black.show()
	title.text = ""
	subtitle.text = ""
	game.player.set_locked(true)
	game.hud.touch.hide()
	game.hud.crosshair.hide()
	base_yaw = game.player.rotation.y
	stage_acts()
	await _run(own)
	if own != token: return
	_cleanup()
	# Elsa's swing tilted her; story staging restores marks but not roll.
	game.actors.elsa.rotation = Vector3(0, PI, 0)
	game.actors.bruno.position.y = 1.55
	game.update_staging()
	game.player.rotation.y = base_yaw
	game.player.camera.rotation = Vector3.ZERO
	finished.emit()

func _run(own: int) -> void:
	title.text = "ПОСЛЕДНЕЕ ПРЕДСТАВЛЕНИЕ"
	subtitle.text = "Бродячий цирк. Двадцать лет его вечерами правит один человек: ведущий Ричард.\nСегодня он выходит на манеж в последний раз. Завтра приедет новый ведущий."
	title.modulate.a = 0
	subtitle.modulate.a = 0
	var intro := create_tween()
	intro.tween_property(title, "modulate:a", 1.0, .8)
	intro.tween_property(subtitle, "modulate:a", 1.0, .8)
	motion.append(intro)
	if not await hold(5.2, own): return
	var open := create_tween()
	open.tween_property(title, "modulate:a", 0.0, .5)
	open.parallel().tween_property(subtitle, "modulate:a", 0.0, .5)
	open.tween_property(black, "modulate:a", 0.0, .9)
	motion.append(open)
	game.sound("applause")
	# First person: Richard turns from one side of the audience to the other.
	game.player.rotation.y = base_yaw - .95
	game.player.camera.rotation.x = .12
	pov(.95, .16, 4.2)
	raise_cane()
	say("РИЧАРД: Дамы и господа! Добро пожаловать на последнее представление сезона!")
	if not await hold(4.4, own): return
	pov(.2, .5, 1.0)
	say("РИЧАРД: Под самым куполом, без страховки, несравненная Эльза!")
	if not await hold(1.8, own): return
	cut(true)
	shot(Vector3(3.2, 5.6, 8.2), Vector3(4.5, 8.4, 3.5), Vector3(-.9, .5, -.7), 3.6)
	swing_elsa(3.6)
	if not await hold(3.6, own): return
	cut(false)
	pov(-.45, .05, .6)
	say("РИЧАРД: Сильнейший человек на свете! Бруно!")
	if not await hold(1.7, own): return
	cut(true)
	shot(Vector3(-1.2, .7, 6.4), Vector3(-3.2, 1.9, 2.6), Vector3(.5, .1, -.6), 3.0)
	lift_bruno()
	if not await hold(3.0, own): return
	cut(false)
	pov(0.0, -.08, .6)
	say("РИЧАРД: Малышка Лили и волшебный сундук!")
	if not await hold(1.7, own): return
	cut(true)
	shot(Vector3(2.6, 1.5, 3.4), game.layout.TRUNK + Vector3(-.5, .7, .4), Vector3(.4, .2, .5), 3.0)
	pop_lili()
	if not await hold(3.0, own): return
	cut(false)
	pov(.5, .02, .6)
	say("РИЧАРД: И, конечно, наш Мордекай!")
	if not await hold(1.6, own): return
	cut(true)
	shot(Vector3(6.4, 1.7, 2.6), Vector3(4.2, 1.6, -1.2), Vector3(-.6, 0, -.4), 2.8)
	spin_mordecai()
	game.audio.emote("mordecai_laugh")
	if not await hold(2.8, own): return
	cut(false)
	game.actors.lili.hide()
	pov(0.0, .02, .9)
	raise_cane()
	say("РИЧАРД: Ваш ведущий, Ричард. Спасибо, что были с нами все эти годы!")
	if not await hold(3.4, own): return
	var out := create_tween()
	out.tween_property(caption, "modulate:a", 0.0, .4)
	motion.append(out)
	await hold(.45, own)
