extends CanvasLayer
## Hairpin lock close-up with two variations.
## "pins" (service door): a cut-away cylinder. Hold to lift the lit pin with the
##   hairpin; when the split between its two halves reaches the shear line the
##   pin glows, trembles and clicks. Let go there to set it.
## "dial" (roof door): the face of the cylinder. Drag sideways to turn the plug
##   with the tension wrench. Near the right spot it trembles and buzzes harder;
##   hold still on it to catch the gate. Turning far past it slips back.
## The hairpin never breaks, so the lock cannot trap the player.
signal closed(id: String, solved: bool)

const RISE_SPEED := .42
const FALL_SPEED := 2.2
const BAND := .085 # Half-width of the release window, in lift units.
const TRAVEL := 120.0 # Pixels of full lift in the 1280x720 design space.
const SHEAR := 330.0
const KEY_REST := 436.0 # Bottom of a resting key pin, just above the keyway.
const DRIVER := 64.0
const DIAL_GATES := 3
const DIAL_SPOT := .07
const DIAL_NEAR := .3
const DIAL_HOLD := .55

const GOLD := Color("ffcf73")
const FAIL := Color("d2493b")
const BRASS := Color("a7834a")
const BRASS_DARK := Color("5b4429")
const STEEL := Color("8e9398")
const IRON := Color("2a2622")

var game
var active := ""
var mode := "pins"
var pins: Array = []
var gates: Array = []
var current := 0
var holding := false
var finished := false
var root: Control
var board: Control
var caption: Label
var hint: Label
var drop_flash := 0.0
var set_flash := 0.0
var plug_turn := 0.0
var time := 0.0
var rng := RandomNumberGenerator.new()
# Dial variation.
var angle := 0.0
var shown_turn := 0.0
var drag_from := 0.0
var drag_angle := 0.0
var pointer_x := 0.0
var key_dir := 0.0
var catch_time := 0.0
var pulse_clock := 0.0
var was_inside := false
var glow_tex: GradientTexture2D

func _ready() -> void:
	layer = 30
	visible = false
	glow_tex = GradientTexture2D.new()
	glow_tex.fill = GradientTexture2D.FILL_RADIAL
	glow_tex.fill_from = Vector2(.5, .5)
	glow_tex.fill_to = Vector2(1, .5)
	glow_tex.width = 128
	glow_tex.height = 128
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(.35, Color(1, 1, 1, .45))
	glow_tex.gradient = g

func is_open() -> bool:
	return active != ""

func start(id: String, count: int) -> void:
	open(id, count)

func open(id: String, count: int) -> void:
	if active != "": return
	active = id
	mode = "dial" if id == "roof" else "pins"
	finished = false
	current = 0
	holding = false
	key_dir = 0.0
	plug_turn = 0.0
	angle = 0.0
	shown_turn = 0.0
	catch_time = 0.0
	drop_flash = 0.0
	set_flash = 0.0
	was_inside = false
	rng.randomize()
	pins.clear()
	gates.clear()
	if mode == "pins":
		var last := -1.0
		for i in count:
			# Neighbouring pins differ in height so the row reads like a real key cut.
			var need := rng.randf_range(.30, .62)
			while absf(need - last) < .08: need = rng.randf_range(.30, .62)
			last = need
			pins.append({"need": need, "height": 0.0, "set": false, "inside": false})
	else:
		for i in DIAL_GATES: gates.append(rng.randf_range(.32, .8))
	for child in get_children(): child.queue_free()
	build_ui()
	visible = true
	root.modulate.a = 0
	create_tween().tween_property(root, "modulate:a", 1.0, .25)

func build_ui() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	board = Control.new()
	board.set_anchors_preset(Control.PRESET_FULL_RECT)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.draw.connect(_draw_board)
	root.add_child(board)
	var title := Label.new()
	title.text = "ДВЕРЬ НА КРЫШУ" if active == "roof" else "СЛУЖЕБНАЯ ДВЕРЬ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 22
	title.offset_bottom = 52
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("8f8068"))
	root.add_child(title)
	caption = Label.new()
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_top = -124
	caption.offset_bottom = -88
	caption.add_theme_font_size_override("font_size", 24)
	caption.add_theme_color_override("font_color", Color("e8d6b0"))
	caption.add_theme_color_override("font_shadow_color", Color.BLACK)
	caption.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(caption)
	hint = Label.new()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hint.offset_top = 52
	hint.offset_bottom = 90
	hint.add_theme_font_size_override("font_size", 22)
	hint.add_theme_color_override("font_color", Color("f0dcae"))
	hint.add_theme_color_override("font_shadow_color", Color.BLACK)
	hint.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(hint)
	var key := "lockpick_hint_" + mode
	if game == null or not game.flags.get(key, false):
		hint.text = "Держи, пока штифт не засветится, и отпусти." if mode == "pins" \
			else "Веди в сторону, пока замок не задрожит, и замри."
		if game: game.flags[key] = true
	var back := Button.new()
	back.name = "BackButton"
	back.text = "Отложить"
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(200, 52)
	back.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	back.offset_left = -100
	back.offset_right = 100
	back.offset_top = -78
	back.offset_bottom = -26
	back.add_theme_font_size_override("font_size", 21)
	back.add_theme_color_override("font_color", Color("cdbf9f"))
	back.add_theme_color_override("font_hover_color", Color("f0dcae"))
	for state in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(.07, .06, .05, .85) if state != "pressed" else Color(.16, .12, .08, .9)
		style.border_color = Color("6e5a3e") if state == "normal" else Color("a98a5e")
		style.set_border_width_all(1)
		style.set_corner_radius_all(6)
		back.add_theme_stylebox_override(state, style)
	back.pressed.connect(close.bind(false))
	root.add_child(back)

# Design space is 1280x720; centre it in whatever the viewport is.
func origin() -> Vector2:
	var vp := get_viewport().get_visible_rect().size
	return (vp - Vector2(1280, 720)) * .5

func _input(event: InputEvent) -> void:
	if active == "" or finished: return
	var press := false
	var release := false
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		if event is InputEventMouseButton and event.button_index != MOUSE_BUTTON_LEFT: return
		# The back button handles its own clicks.
		var button: Control = root.get_node_or_null("BackButton")
		if button and button.get_global_rect().has_point(event.position): return
		press = event.pressed; release = not event.pressed
		pointer_x = event.position.x
	elif event is InputEventMouseMotion or event is InputEventScreenDrag:
		pointer_x = event.position.x
		if mode == "dial" and holding:
			var vp := get_viewport().get_visible_rect().size
			angle = clampf(drag_angle + (pointer_x - drag_from) / (vp.x * .45), 0.0, 1.0)
		return
	elif event is InputEventKey and event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_A, KEY_D] and mode == "dial":
		var right: bool = event.keycode in [KEY_RIGHT, KEY_D]
		if event.pressed: key_dir = 1.0 if right else -1.0
		elif (key_dir > 0) == right: key_dir = 0.0
		get_viewport().set_input_as_handled()
		return
	elif event is InputEventKey and not event.echo and event.keycode in [KEY_E, KEY_SPACE, KEY_ENTER]:
		if mode == "dial":
			# One-button fallback: E turns forward while held.
			key_dir = 1.0 if event.pressed else 0.0
			get_viewport().set_input_as_handled()
			return
		press = event.pressed; release = not event.pressed
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close(false)
		get_viewport().set_input_as_handled()
		return
	else:
		return
	get_viewport().set_input_as_handled()
	if press:
		holding = true
		drag_from = pointer_x
		drag_angle = angle
	elif release and holding:
		holding = false
		if mode == "pins": let_go()

# --- Pins -----------------------------------------------------------------

func let_go() -> void:
	var pin: Dictionary = pins[current]
	if absf(pin["height"] - pin["need"]) <= BAND:
		pin["set"] = true
		pin["inside"] = false
		set_flash = 1.0
		buzz(45)
		click(.75, -4)
		current += 1
		hint.text = ""
		if current >= pins.size(): finish()
		else: caption.text = "Щёлк. Штифт встал."
	else:
		drop("Рано. Штифт упал." if pin["height"] < pin["need"] else "Слишком высоко. Штифт упал.")

func drop(text: String) -> void:
	pins[current]["inside"] = false
	drop_flash = 1.0
	caption.text = text
	fail_sound()
	buzz(90)

func process_pins(delta: float) -> void:
	var pin: Dictionary = pins[current]
	if holding:
		pin["height"] = minf(1.0, pin["height"] + RISE_SPEED * delta)
		var inside: bool = absf(pin["height"] - pin["need"]) <= BAND
		if inside and not pin["inside"]:
			buzz(22)
			click(1.35, -10)
		pin["inside"] = inside
		if pin["height"] >= 1.0:
			# Overpushed: the pin slips past the line and falls back.
			holding = false
			drop("Слишком высоко. Штифт упал.")
	else:
		pin["height"] = maxf(0.0, pin["height"] - FALL_SPEED * delta)
		pin["inside"] = false

# --- Dial -----------------------------------------------------------------

func process_dial(delta: float) -> void:
	var turning := holding or key_dir != 0.0
	if key_dir != 0.0: angle = clampf(angle + key_dir * delta * .4, 0.0, 1.0)
	elif not holding: angle = move_toward(angle, 0.0, delta * 1.4)
	var target: float = gates[current]
	var d := absf(angle - target)
	var near := proximity()
	var inside := d <= DIAL_SPOT and turning
	if inside:
		if not was_inside:
			click(1.35, -10)
			buzz(25)
		catch_time += delta
		if catch_time >= DIAL_HOLD: catch_gate()
	else:
		catch_time = maxf(0.0, catch_time - delta * 2.0)
	was_inside = inside
	if turning and near > 0.0:
		pulse_clock -= delta
		if pulse_clock <= 0.0:
			pulse_clock = lerpf(.5, .1, near)
			buzz(int(6 + near * 18))
			if not inside: click(.9 + near * .4, -26 + near * 10)
	if turning and angle > target + .2:
		holding = false
		key_dir = 0.0
		drop_flash = 1.0
		caption.text = "Перекрутил. Ещё раз, мягче."
		fail_sound()
		buzz(90)

func proximity() -> float:
	if mode != "dial" or current >= gates.size(): return 0.0
	return clampf(1.0 - absf(angle - gates[current]) / DIAL_NEAR, 0.0, 1.0)

func catch_gate() -> void:
	current += 1
	catch_time = 0.0
	was_inside = false
	set_flash = 1.0
	angle = 0.0
	drag_from = pointer_x
	drag_angle = 0.0
	buzz(45)
	click(.75, -4)
	hint.text = ""
	if current >= gates.size(): finish()
	else: caption.text = "Щёлк. Ещё %s." % ("один" if gates.size() - current == 1 else "два")

# --- Shared ---------------------------------------------------------------

func buzz(ms: int) -> void:
	if OS.has_feature("mobile"): Input.vibrate_handheld(ms)

func audio_ok() -> bool:
	return game != null and is_instance_valid(game.get("audio"))

func click(pitch: float, db: float) -> void:
	if not audio_ok(): return
	var p := AudioStreamPlayer.new()
	p.stream = game.audio.stream("sfx_flashlight_click")
	p.pitch_scale = pitch
	p.volume_db = db
	p.bus = "UI"
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

func fail_sound() -> void:
	if audio_ok(): game.audio.play("sfx_door_locked", -13)

func finish() -> void:
	finished = true
	holding = false
	key_dir = 0.0
	caption.text = "Замок поддался."
	if audio_ok():
		game.audio.ui()
		# The service door plays its own unlock cue at the door.
		if active == "roof": game.audio.play("sfx_lock_hairpin", -7)
	var tween := create_tween()
	tween.tween_property(self, "plug_turn", 1.0, .5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(.45)
	tween.tween_callback(close.bind(true))

func close(solved: bool) -> void:
	if active == "": return
	var id := active
	active = ""
	holding = false
	key_dir = 0.0
	visible = false
	for child in get_children(): child.queue_free()
	closed.emit(id, solved)

# Test hook: solve the current pin or gate.
func solve_current() -> void:
	if active == "" or finished: return
	if mode == "dial":
		catch_gate()
		return
	var pin: Dictionary = pins[current]
	pin["height"] = pin["need"]
	let_go()

func _process(delta: float) -> void:
	if active == "": return
	time += delta
	drop_flash = maxf(0.0, drop_flash - delta * 2.5)
	set_flash = maxf(0.0, set_flash - delta * 2.0)
	if not finished:
		if mode == "pins": process_pins(delta)
		else: process_dial(delta)
	var turn_goal := (current * .28 + angle * .32) if not finished else PI * .5
	shown_turn = lerpf(shown_turn, turn_goal, minf(1.0, delta * 14.0))
	if is_instance_valid(board): board.queue_redraw()

# --- Drawing --------------------------------------------------------------

func glow(at: Vector2, radius: float, color: Color) -> void:
	board.draw_texture_rect(glow_tex, Rect2(at - Vector2(radius, radius), Vector2(radius, radius) * 2), false, color)

func box(rect: Rect2, color: Color, radius := 0, border := Color.TRANSPARENT, shadow := 0) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.anti_aliasing = true
	if border.a > 0:
		style.border_color = border
		style.set_border_width_all(2)
	if shadow > 0:
		style.shadow_color = Color(0, 0, 0, .6)
		style.shadow_size = shadow
		style.shadow_offset = Vector2(0, shadow * .3)
	board.draw_style_box(style, rect)

func vgrad(rect: Rect2, top: Color, bottom: Color) -> void:
	board.draw_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]),
		PackedColorArray([top, top, bottom, bottom]))

# A turned metal pin: horizontal cylinder shading and chamfered ends.
func column(cx: float, top: float, bottom: float, w: float, base: Color, tip := 0.0, cap := 3.0) -> void:
	var stops := [-1.0, -.7, -.25, .2, .7, 1.0]
	var hw := w * .5
	for s in stops.size() - 1:
		var a: float = stops[s]
		var b: float = stops[s + 1]
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		for t in [a, b, b, a]:
			var bottom_y: float = bottom - tip * maxf(0.0, absf(t) - .35) / .65
			var top_y: float = top + cap * maxf(0.0, absf(t) - .6) / .4
			pts.append(Vector2(cx + t * hw, top_y if pts.size() < 2 else bottom_y))
			cols.append(shade(base, t))
		board.draw_polygon(pts, cols)

func shade(base: Color, t: float) -> Color:
	var light := 1.0 - absf(t + .25) * .75
	return base.darkened(.55 * (1.0 - light)).lightened(maxf(0.0, light - .75) * 1.2)

func _draw_board() -> void:
	var vp := board.size
	# Dark room with a warm pool of light on the lock.
	board.draw_rect(Rect2(Vector2.ZERO, vp), Color(.025, .02, .018, .93))
	var o := origin()
	board.draw_set_transform(o)
	glow(Vector2(640, 340), 560, Color(.55, .38, .2, .22))
	if mode == "pins": draw_pins()
	else: draw_dial()
	board.draw_set_transform(Vector2.ZERO)

func pin_x(i: int) -> float:
	var pitch := 150.0 if pins.size() <= 3 else 112.0
	return 640.0 - pitch * (pins.size() - 1) * .5 + 40.0 + i * pitch

func draw_pins() -> void:
	var n := pins.size()
	var left := pin_x(0) - 150.0
	var right := pin_x(n - 1) + 90.0
	var sink := plug_turn * 7.0
	var shake := Vector2(sin(time * 90.0) * 5.0 * drop_flash, 0)
	board.draw_set_transform(origin() + shake)
	# Housing shell around the plug.
	var housing := Rect2(left, 132, right - left, 400)
	box(housing, BRASS_DARK, 16, Color("2a1f14"), 34)
	vgrad(housing.grow(-3), Color(1, .9, .7, .10), Color(0, 0, 0, .35))
	for k in 6: board.draw_line(Vector2(left + 14, 150 + k * 30), Vector2(right - 14, 150 + k * 30), Color(1, .9, .7, .025), 1.0)
	# Plug.
	var plug := Rect2(left + 4, SHEAR + sink, right - left - 26, 170)
	box(plug, BRASS, 6)
	vgrad(plug, Color(1, .95, .8, .18), Color(0, 0, 0, .32))
	board.draw_line(Vector2(plug.position.x, plug.position.y + 1), Vector2(plug.end.x, plug.position.y + 1), Color(1, .93, .75, .35), 1.5)
	# Keyway along the bottom of the plug.
	var keyway := Rect2(left - 70, 432 + sink, right - left + 40, 48)
	box(keyway, Color("120e0b"), 4)
	board.draw_line(Vector2(keyway.position.x, keyway.end.y), keyway.end, Color(1, .9, .7, .12), 1.0)
	# Front flange of the cylinder with its rounded lip.
	var face := Rect2(left - 54, 108, 58, 450)
	box(face, BRASS, 14, Color("3a2b19"), 18)
	vgrad(Rect2(face.position.x + 4, face.position.y + 6, 18, face.size.y - 12), Color(1, .95, .8, .22), Color(1, .95, .8, .05))
	box(Rect2(face.position.x - 4, 432 + sink, face.size.x + 8, 48), Color("120e0b"), 4)
	# Shear line.
	var line_glow := 0.0
	if not finished and current < n: line_glow = 1.0 if pins[current]["inside"] else 0.0
	line_glow = maxf(line_glow, plug_turn)
	board.draw_line(Vector2(left + 6, SHEAR), Vector2(right - 6, SHEAR), Color(GOLD, .22 + .5 * line_glow), 2.0)
	for i in n: draw_pin(i, sink)
	draw_wrench(Vector2(left - 50, 470 + sink), plug_turn * .35)
	if not finished and current < n: draw_hairpin(left)
	draw_progress(n, current, 576)

func draw_pin(i: int, sink: float) -> void:
	var pin: Dictionary = pins[i]
	var x := pin_x(i)
	var key_len: float = KEY_REST - SHEAR - pin["need"] * TRAVEL
	var lift: float = 0.0 if pin["set"] else pin["height"] * TRAVEL
	var is_current := i == current and not finished
	var inside: bool = is_current and pin["inside"]
	var shake := sin(time * 75.0 + i) * 2.2 if inside else 0.0
	x += shake
	# Chamber bored through housing and plug.
	var chamber := Rect2(x - 20, 150, 40, KEY_REST - 150 + sink)
	box(chamber, Color("17110c"), 3)
	board.draw_line(Vector2(chamber.end.x - 1, 152), Vector2(chamber.end.x - 1, chamber.end.y), Color(1, .9, .7, .08), 1.0)
	if is_current: box(chamber.grow(3), Color.TRANSPARENT, 5, Color(GOLD, .18 + .1 * sin(time * 4.0)))
	var key_bottom := KEY_REST + sink - lift
	var key_top := key_bottom - key_len
	var driver_bottom := key_top
	if pin["set"]:
		key_bottom = KEY_REST + sink
		key_top = key_bottom - key_len
		driver_bottom = SHEAR - 2.0
	var driver_top := driver_bottom - DRIVER
	# Spring from the chamber top to the driver.
	var coils := 9
	var pts := PackedVector2Array()
	for c in coils * 2 + 1:
		var t := float(c) / (coils * 2)
		var side := 0.0 if c == 0 or c == coils * 2 else (-1.0 if c % 2 == 0 else 1.0)
		pts.append(Vector2(x + side * 12.0, lerpf(154.0, driver_top, t)))
	board.draw_polyline(pts, Color(0, 0, 0, .6), 4.0, true)
	board.draw_polyline(pts, Color("9da3a6"), 2.4, true)
	var hi := PackedVector2Array()
	for p in pts: hi.append(p + Vector2(-.6, -.8))
	board.draw_polyline(hi, Color(1, 1, 1, .25), 1.0, true)
	# Driver (steel) and key pin (brass, pointed tip).
	column(x, driver_top, driver_bottom - 1.0, 30, STEEL, 0.0, 4.0)
	var key_color := Color("d8b46e")
	if pin["set"]: key_color = Color("c9a865")
	if is_current: key_color = key_color.lerp(FAIL, drop_flash)
	column(x, key_top + 1.0, key_bottom, 28, key_color, 9.0, 3.0)
	if inside:
		glow(Vector2(x, SHEAR), 70, Color(GOLD, .75 + .2 * sin(time * 30.0)))
		board.draw_line(Vector2(x - 22, SHEAR), Vector2(x + 22, SHEAR), Color(1, .95, .75), 3.0)
	if pin["set"]:
		var fade := set_flash if i == current - 1 else 0.0
		glow(Vector2(x, SHEAR), 46 + 40 * fade, Color(GOLD, .28 + .6 * fade))

func draw_hairpin(left: float) -> void:
	var pin: Dictionary = pins[current]
	var x := pin_x(current) + (sin(time * 75.0 + current) * 2.2 if pin["inside"] else 0.0)
	var tip_y: float = KEY_REST - pin["height"] * TRAVEL
	var low := 470.0
	var grip := Vector2(left - 300, 545)
	var pts := PackedVector2Array([grip, Vector2(left - 170, 505), Vector2(left - 60, low),
		Vector2(x - 30, low), Vector2(x - 4, low - 18), Vector2(x, tip_y + 2)])
	var col := Color("26211d")
	board.draw_polyline(pts, Color(0, 0, 0, .55), 11.0, true)
	board.draw_polyline(pts, col, 7.0, true)
	var hi := PackedVector2Array()
	for p in pts: hi.append(p + Vector2(0, -2.0))
	board.draw_polyline(hi, Color(.8, .74, .66, .5), 1.6, true)
	# The crimped outer leg and the rubber tip of a bobby pin.
	var wave := PackedVector2Array()
	for k in 13:
		var t := k / 12.0
		var p := (grip + Vector2(0, 16)).lerp(grip + Vector2(150, 82), t)
		wave.append(p + Vector2(0, sin(t * TAU * 2.5) * 5.0 * t))
	board.draw_polyline(wave, Color(0, 0, 0, .5), 10.0, true)
	board.draw_polyline(wave, col, 7.0, true)
	board.draw_arc(grip + Vector2(0, 8), 8.0, PI * .5, PI * 1.5, 12, col, 7.0, true)
	board.draw_circle(wave[wave.size() - 1], 7.0, Color("15120f"))

func draw_wrench(at: Vector2, turn: float) -> void:
	# L-shaped tension wrench hooked into the keyway and hanging below.
	board.draw_set_transform(origin() + at, turn)
	var col := Color("34312f")
	box(Rect2(-8, -4, 76, 12), Color(0, 0, 0, .5), 3)
	box(Rect2(-8, -12, 74, 12), col, 2)
	box(Rect2(-10, -12, 16, 160), col, 3)
	box(Rect2(-14, 120, 24, 44), Color("1c1a19"), 6)
	board.draw_line(Vector2(-7, -11), Vector2(64, -11), Color(1, 1, 1, .28), 1.5)
	board.draw_line(Vector2(-9, -10), Vector2(-9, 118), Color(1, 1, 1, .2), 1.5)
	board.draw_set_transform(origin())

func draw_progress(n: int, done: int, y: float) -> void:
	var gap := 34.0
	for i in n:
		var c := Vector2(640 - gap * (n - 1) * .5 + i * gap, y)
		if i < done:
			glow(c, 18, Color(GOLD, .5))
			board.draw_circle(c, 7, GOLD)
		elif i == done and not finished:
			board.draw_arc(c, 8, 0, TAU, 24, Color("e8d6b0", .8), 2.0, true)
		else:
			board.draw_arc(c, 7, 0, TAU, 24, Color("6b5d49", .7), 1.5, true)

func draw_dial() -> void:
	var near := proximity() if not finished else 0.0
	var tremble := Vector2(sin(time * 83.0), cos(time * 71.0)) * near * near * 3.5
	tremble += Vector2(sin(time * 90.0) * 6.0 * drop_flash, 0)
	var c := Vector2(640, 320)
	# Iron escutcheon plate with four screws.
	var plate := Rect2(c - Vector2(210, 215), Vector2(420, 430))
	box(plate, IRON, 22, Color("15120f"), 36)
	vgrad(plate.grow(-4), Color(1, .9, .75, .07), Color(0, 0, 0, .3))
	for s in [Vector2(-172, -177), Vector2(172, -177), Vector2(-172, 177), Vector2(172, 177)]:
		board.draw_circle(c + s, 11, Color("1a1714"))
		board.draw_circle(c + s, 9, Color("4a443d"))
		board.draw_line(c + s + Vector2(-6, 2), c + s + Vector2(6, -2), Color("1a1714"), 2.0)
	# Brass bezel and the plug inside it.
	board.draw_circle(c, 158, Color("17120d"))
	board.draw_circle(c, 150, BRASS_DARK)
	board.draw_arc(c, 142, PI * .95, PI * 1.85, 48, Color(1, .9, .7, .28), 8.0, true)
	board.draw_arc(c, 142, PI * -.05, PI * .85, 48, Color(0, 0, 0, .3), 8.0, true)
	# Gate marks on the bezel; caught gates glow.
	for g in gates.size():
		var a := -PI * .5 + (g + 1) * .28
		var p := c + Vector2.from_angle(a) * 142
		if g < current or finished:
			glow(p, 22, Color(GOLD, .6))
			board.draw_circle(p, 5, GOLD)
		else:
			board.draw_circle(p, 4, Color("2c2117"))
	if near > 0.0 and not finished:
		glow(c + tremble, 150 + 40 * near, Color(GOLD, .8 * near * near + .25 * set_flash))
	elif set_flash > 0.0:
		glow(c, 190, Color(GOLD, .5 * set_flash))
	board.draw_circle(c, 126, Color("120e0b"))
	var pc := c + tremble
	board.draw_circle(pc, 120, BRASS)
	board.draw_arc(pc, 112, PI * 1.0, PI * 1.75, 40, Color(1, .95, .8, .25), 10.0, true)
	board.draw_arc(pc, 112, 0, PI * .7, 40, Color(0, 0, 0, .22), 10.0, true)
	board.draw_arc(pc, 120, 0, TAU, 64, Color(0, 0, 0, .5), 2.0, true)
	if drop_flash > 0.0: board.draw_arc(pc, 122, 0, TAU, 64, Color(FAIL, drop_flash), 4.0, true)
	if catch_time > 0.0:
		board.draw_arc(pc, 132, -PI * .5, -PI * .5 + TAU * catch_time / DIAL_HOLD, 48, Color(GOLD, .9), 5.0, true)
	# Keyway, wrench and hairpin turn with the plug.
	board.draw_set_transform(origin() + pc, shown_turn)
	var keyway := PackedVector2Array([Vector2(-9, -78), Vector2(9, -78), Vector2(9, -30), Vector2(3, -20),
		Vector2(11, -8), Vector2(11, 50), Vector2(3, 62), Vector2(-9, 62), Vector2(-9, 20), Vector2(-3, 10), Vector2(-9, 0)])
	board.draw_colored_polygon(keyway, Color("0d0a08"))
	board.draw_polyline(keyway + PackedVector2Array([keyway[0]]), Color(0, 0, 0, .6), 2.0, true)
	board.draw_line(Vector2(-12, -96), Vector2(12, -96), Color(0, 0, 0, .25), 2.0)
	# Tension wrench in the bottom of the keyway, bent out to the right.
	var wrench := Color("3b3836")
	board.draw_polyline(PackedVector2Array([Vector2(0, 52), Vector2(0, 92), Vector2(180, 130)]), Color(0, 0, 0, .5), 13.0, true)
	board.draw_polyline(PackedVector2Array([Vector2(0, 52), Vector2(0, 92), Vector2(180, 130)]), wrench, 10.0, true)
	board.draw_line(Vector2(-3, 54), Vector2(-3, 90), Color(1, 1, 1, .2), 1.0)
	board.draw_line(Vector2(2, 89), Vector2(178, 126), Color(1, 1, 1, .2), 1.0)
	# Hairpin from the top of the keyway out to the upper right.
	var hp := PackedVector2Array([Vector2(0, -60), Vector2(0, -105), Vector2(60, -160), Vector2(125, -185)])
	board.draw_polyline(hp, Color(0, 0, 0, .55), 9.0, true)
	board.draw_polyline(hp, Color("26211d"), 6.0, true)
	var hi := PackedVector2Array()
	for p in hp: hi.append(p + Vector2(-1.5, -1))
	board.draw_polyline(hi, Color(.75, .7, .65, .45), 1.4, true)
	board.draw_circle(Vector2(127, -186), 8.0, Color("15120f"))
	board.draw_set_transform(origin())
	# Direction cue before the first turn.
	if current == 0 and angle < .02 and not holding and not finished:
		var a := .45 + .25 * sin(time * 3.0)
		board.draw_arc(c, 185, -PI * .5 + .15, -PI * .5 + .9, 32, Color("e8d6b0", a), 3.0, true)
		var tip := c + Vector2.from_angle(-PI * .5 + .9) * 185
		var dir := Vector2.from_angle(-PI * .5 + .9 + PI * .5)
		board.draw_colored_polygon(PackedVector2Array([tip + dir * 12, tip - dir * 2 + dir.orthogonal() * 9, tip - dir * 2 - dir.orthogonal() * 9]), Color("e8d6b0", a))
	draw_progress(gates.size(), current, 576)
