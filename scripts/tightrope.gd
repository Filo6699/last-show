extends CanvasLayer
## High wire under the canopy. On the wire Richard drifts off balance; the
## player counters with left/right (keys, stick or touch joystick). Gusts and
## walking make it worse, and the gusts grow toward the far end. Halfway the
## wire jolts and the lamps die: Richard has to stand and wait it out. That
## spot is also the checkpoint. Past the tipping point he falls, then the run
## restarts on the west board, or at the halfway mark once he has reached it.
const RESPAWN := Vector3(-7.3, 40.02, -2)
const RESPAWN_LOOK := Vector3(2.5, 41.3, -2)
const WIRE_SPEED := .38
const COUNTER := 3.0
# How long Richard must hold still in the middle while the wire settles.
const HOLD_TIME := 10.0

var game
var late
var on_wire := false
var falling := false
var lean := 0.0
var lean_speed := 0.0
var gust := 0.0
var gust_wait := 0.0
var gust_goal := 0.0
var grace := 0.0
var checkpoint := false
var mid_done := false
var hold := 0.0
var lamp_energy := {}
var shake := 0.0
var lamp_tween: Tween
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
	var progress := clampf((p.x - late.WIRE_A) / (late.WIRE_B - late.WIRE_A), 0, 1)
	if not mid_done and p.x >= mid_x(): start_hold()
	grace = maxf(0, grace - delta)
	# Gusts build gradually so a thumb on a touch stick has time to answer,
	# and grow stronger and more frequent the further Richard gets.
	gust_wait -= delta
	if gust_wait <= 0:
		gust_wait = rng.randf_range(lerpf(2.0, 1.0, progress), lerpf(3.0, 1.7, progress))
		var strength := lerpf(.2, .55, progress)
		gust_goal = rng.randf_range(.5, 1.0) * strength * (1.0 if rng.randf() < .5 else -1.0)
	gust = move_toward(gust, 0.0 if grace > 0 else gust_goal, delta * .9)
	if hold > 0:
		hold -= delta
		hint.text = "Трос ходит ходуном. Стой и держи равновесие: %d" % ceili(hold)
		if hold <= 0: end_hold()
	# A deep lean slows the step: careful players stop, recover, then go on.
	game.player.speed = maxf(.0001, 0.0 if hold > 0 else WIRE_SPEED * (1.0 - .7 * clampf(absf(lean), 0, 1)))
	var walking: float = absf(game.player.velocity.x) / WIRE_SPEED
	var counter := Input.get_axis("move_left", "move_right")
	if game.player.touch_move.length() > .01: counter = game.player.touch_move.x
	# The wire runs east; facing west flips which hand is "right".
	if -game.player.global_basis.z.x < 0: counter = -counter
	lean_speed += (gust * (.8 + walking * .5) + lean * .6 + counter * COUNTER) * delta
	lean_speed *= pow(.35, delta)
	lean = clampf(lean + lean_speed * delta, -1.2, 1.2)
	shake = maxf(0, shake - delta * 1.6)
	game.player.camera.rotation.z = -lean * .42 + sin(Time.get_ticks_msec() * .045) * shake * .06
	if absf(lean) >= 1.0: fall()

func mid_x() -> float:
	return (late.WIRE_A + late.WIRE_B) * .5

## The scripted beat halfway: the wire snaps taut and swings, the lamps under
## the canopy stutter and go out, and Richard must stand until it settles.
func start_hold() -> void:
	mid_done = true
	checkpoint = true
	hold = HOLD_TIME
	var side := -signf(lean) if absf(lean) > .05 else (1.0 if rng.randf() < .5 else -1.0)
	lean_speed += side * .4
	shake = 1.0
	gust_goal = 0.0
	gust_wait = 1.6
	game.player.velocity.x = 0
	game.audio.play("sfx_elsa_rig_creak_0%d" % rng.randi_range(1, 3), -2)
	game.audio.play("sfx_box_bump_02", -8)
	game.hud.show_notice("Трос дёрнулся. Не двигайся.")
	flicker_lamps()

func end_hold() -> void:
	hold = 0.0
	hint.text = hint_text()
	game.hud.show_notice("Успокоился. Половина позади.")

func roof_lamps() -> Array:
	var lamps := []
	for light in late.find_children("*", "OmniLight3D", true, false):
		if light.global_position.y > late.ROOF_FLOOR - 1: lamps.append(light)
	return lamps

func flicker_lamps() -> void:
	var lamps := roof_lamps()
	for light in lamps:
		if not lamp_energy.has(light): lamp_energy[light] = light.light_energy
	game.audio.play("sfx_light_flicker_0%d" % rng.randi_range(1, 3), -6)
	if lamp_tween: lamp_tween.kill()
	var tween := create_tween()
	lamp_tween = tween
	for level in [.15, 1.0, .05, .8, .0]:
		tween.tween_callback(set_lamps.bind(lamps, level))
		tween.tween_interval(rng.randf_range(.07, .16))
	# Dark for a few seconds, then the nearest lamps come back weaker.
	tween.tween_interval(3.2)
	tween.tween_callback(func(): game.audio.play("sfx_light_flicker_0%d" % rng.randi_range(1, 3), -10))
	for level in [.4, .1, .7]:
		tween.tween_callback(set_lamps.bind(lamps, level))
		tween.tween_interval(.12)

func set_lamps(lamps: Array, level: float) -> void:
	for light in lamps:
		if is_instance_valid(light): light.light_energy = lamp_energy.get(light, 1.0) * level

func restore_lamps() -> void:
	if lamp_tween: lamp_tween.kill()
	for light in lamp_energy:
		if is_instance_valid(light): light.light_energy = lamp_energy[light]
	lamp_energy.clear()

func hint_text() -> String:
	return "Наклоняй джойстик влево-вправо, чтобы держать равновесие" if game.hud.touch_enabled else "A / D: держать равновесие"

func set_on_wire(value: bool) -> void:
	on_wire = value
	show_ui(value)
	lean = 0.0
	lean_speed = 0.0
	gust = 0.0
	gust_goal = 0.0
	gust_wait = 1.5
	grace = 1.5
	shake = 0.0
	if hold > 0 and not value: hold = 0.0
	if value:
		normal_speed = game.player.speed
		game.player.speed = WIRE_SPEED
		hint.text = hint_text()
		if not checkpoint: game.hud.show_notice("Не смотри вниз.")
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
	# Wind arrow above the bar: shows where the next gust pushes, early.
	if absf(gust_goal) > .05:
		var dir: float = signf(gust_goal) * (-1.0 if -game.player.global_basis.z.x < 0 else 1.0)
		var ax: float = w * .5 + dir * w * .18
		var tip: Vector2 = Vector2(ax + dir * 14, -4)
		var wind_color := Color("d6c8aa", clampf(absf(gust_goal) * 1.6, .35, .9))
		bar.draw_colored_polygon(PackedVector2Array([tip, Vector2(ax, -11), Vector2(ax, 3)]), wind_color)
		bar.draw_line(Vector2(ax - dir * 18, -4), Vector2(ax, -4), wind_color, 3)
	var x := w * .5 + clampf(lean, -1, 1) * w * .5
	var color := Color("e7d9b8").lerp(Color("c0392b"), clampf((danger - .4) / .5, 0, 1))
	bar.draw_rect(Rect2(x - 5, 2, 10, 26), color)

func fall() -> void:
	if falling: return
	falling = true
	hold = 0.0
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
	card.tween_property(title, "modulate:a", 1.0, .15)
	card.tween_interval(.7)
	card.tween_property(title, "modulate:a", 0.0, .15)
	await card.finished
	if token != game.session: return
	game.player.camera.rotation = Vector3.ZERO
	game.player.set_physics_process(true)
	restore_lamps()
	falling = false
	set_on_wire(false)
	if checkpoint:
		game.place_player(Vector3(mid_x(), RESPAWN.y, late.WIRE_Z), RESPAWN_LOOK)
	else:
		game.place_player(RESPAWN, RESPAWN_LOOK)
	game.transitioning = false
	game.player.set_locked(false)
	game.hud.show_notice("С середины. Медленно." if checkpoint else "Ещё раз. Медленно.")
	create_tween().tween_property(black, "color:a", 0.0, .4)

func reset() -> void:
	falling = false
	checkpoint = false
	mid_done = false
	hold = 0.0
	restore_lamps()
	if on_wire: set_on_wire(false)
	black.color.a = 0
	title.modulate.a = 0
