extends CanvasLayer
## Hairpin lock: raise each pin to the shear line and let go there.
## Hold (mouse, touch, E or Space) lifts the current pin. Inside the shear band
## the pin trembles, ticks and the phone buzzes; letting go there sets it.
## Letting go elsewhere drops it; pushing it to the top makes it slip.
## The hairpin never breaks, so the lock cannot trap the player.
signal closed(id: String, solved: bool)

const RISE_SPEED := .55
const FALL_SPEED := 2.4
var game
var active := ""
var pins: Array = []
var current := 0
var holding := false
var finished := false
var root: Control
var board: Control
var caption: Label
var tremble := 0.0
var drop_flash := 0.0
var plug_turn := 0.0
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	layer = 30
	visible = false

func is_open() -> bool:
	return active != ""

func open(id: String, count: int) -> void:
	if active != "": return
	active = id
	finished = false
	current = 0
	holding = false
	plug_turn = 0.0
	rng.randomize()
	pins.clear()
	# Narrower bands on the longer night lock.
	var width := .16 if count <= 3 else .12
	for i in count:
		var low := rng.randf_range(.38, .72)
		pins.append({"height": 0.0, "low": low, "high": low + width, "set": false, "inside": false})
	for child in get_children(): child.queue_free()
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, .82)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	board = Control.new()
	board.set_anchors_preset(Control.PRESET_FULL_RECT)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.draw.connect(_draw_lock)
	root.add_child(board)
	var title := Label.new()
	title.text = "ЗАМОК"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 28
	title.offset_bottom = 64
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("e4d6bf"))
	root.add_child(title)
	caption = Label.new()
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_top = -150
	caption.offset_bottom = -84
	caption.offset_left = 40
	caption.offset_right = -40
	caption.add_theme_font_size_override("font_size", 22)
	caption.add_theme_color_override("font_color", Color("cdbf9f"))
	caption.text = "Держи, чтобы поднять штифт невидимкой. Отпусти, когда он дрогнет и щёлкнет."
	root.add_child(caption)
	var back := Button.new()
	back.name = "BackButton"
	back.text = "Отложить"
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(220, 54)
	back.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	back.offset_left = -110
	back.offset_right = 110
	back.offset_top = -70
	back.offset_bottom = -16
	back.pressed.connect(close.bind(false))
	root.add_child(back)
	visible = true
	root.modulate.a = 0
	create_tween().tween_property(root, "modulate:a", 1.0, .2)

func lock_rect() -> Rect2:
	var vp := get_viewport().get_visible_rect().size
	var w := minf(vp.x * .7, 120.0 * pins.size() + 160.0)
	var h := minf(vp.y * .5, 300.0)
	return Rect2((vp.x - w) * .5, vp.y * .16, w, h)

func pin_x(i: int) -> float:
	var r := lock_rect()
	return r.position.x + 120.0 + i * (r.size.x - 160.0) / maxf(pins.size() - 1, 1)

func _input(event: InputEvent) -> void:
	if active == "" or finished: return
	var press := false
	var release := false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# The back button handles its own clicks.
		var button: Control = root.get_node_or_null("BackButton")
		if button and button.get_global_rect().has_point(event.position): return
		press = event.pressed; release = not event.pressed
	elif event is InputEventScreenTouch:
		var button: Control = root.get_node_or_null("BackButton")
		if button and button.get_global_rect().has_point(event.position): return
		press = event.pressed; release = not event.pressed
	elif event is InputEventKey and not event.echo and event.keycode in [KEY_E, KEY_SPACE, KEY_ENTER]:
		press = event.pressed; release = not event.pressed
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close(false)
		get_viewport().set_input_as_handled()
		return
	else:
		return
	get_viewport().set_input_as_handled()
	if press: holding = true
	elif release and holding:
		holding = false
		let_go()

func let_go() -> void:
	var pin: Dictionary = pins[current]
	if pin["height"] >= pin["low"] and pin["height"] <= pin["high"]:
		pin["set"] = true
		pin["height"] = (pin["low"] + pin["high"]) * .5
		buzz(45)
		if game and is_instance_valid(game.audio): game.audio.ui()
		current += 1
		if current >= pins.size():
			finish()
		else:
			caption.text = "Щёлк. Следующий штифт."
	else:
		drop()

func drop() -> void:
	pins[current]["inside"] = false
	drop_flash = 1.0
	caption.text = "Штифт сорвался. Невидимка цела, попробуй ещё."
	if game: game.sound("locked")

func buzz(ms: int) -> void:
	if OS.has_feature("mobile"): Input.vibrate_handheld(ms)

func finish() -> void:
	finished = true
	caption.text = "Замок поддался."
	var tween := create_tween()
	tween.tween_property(self, "plug_turn", 1.0, .45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(.35)
	tween.tween_callback(close.bind(true))

func close(solved: bool) -> void:
	if active == "": return
	var id := active
	active = ""
	holding = false
	visible = false
	for child in get_children(): child.queue_free()
	closed.emit(id, solved)

# Test hook: put the current pin inside its band and release.
func solve_current() -> void:
	if active == "" or finished: return
	var pin: Dictionary = pins[current]
	pin["height"] = (pin["low"] + pin["high"]) * .5
	let_go()

func _process(delta: float) -> void:
	if active == "": return
	drop_flash = maxf(0.0, drop_flash - delta * 3.0)
	if not finished:
		var pin: Dictionary = pins[current]
		if holding:
			pin["height"] = minf(1.0, pin["height"] + RISE_SPEED * delta)
			var inside: bool = pin["height"] >= pin["low"] and pin["height"] <= pin["high"]
			if inside and not pin["inside"]:
				buzz(18)
				if game and is_instance_valid(game.audio): game.audio.ui()
			pin["inside"] = inside
			if pin["height"] >= 1.0:
				# Overpushed: the pin slips past the line and falls back.
				holding = false
				drop()
		else:
			pin["height"] = maxf(0.0, pin["height"] - FALL_SPEED * delta)
			pin["inside"] = false
		tremble = (sin(Time.get_ticks_msec() * .09) * 2.5) if pin["inside"] else 0.0
	if is_instance_valid(board): board.queue_redraw()

func _draw_lock() -> void:
	var r := lock_rect()
	var shear_y := r.position.y + r.size.y * .42
	var travel := r.size.y * .32
	# Brass housing, plug and the shear line between them.
	board.draw_rect(r, Color("5a4630"))
	board.draw_rect(r.grow(-8), Color("2b2219"))
	var plug := Rect2(r.position.x + 30, shear_y, r.size.x - 60, r.size.y * .5)
	var plug_color := Color("8a6a3d").lerp(Color("c8a560"), plug_turn)
	board.draw_rect(plug, plug_color)
	board.draw_line(Vector2(r.position.x + 20, shear_y), Vector2(r.end.x - 20, shear_y), Color("e2cf9c", .55), 2.0)
	for i in pins.size():
		var pin: Dictionary = pins[i]
		var x := pin_x(i)
		var lift: float = pin["height"] * travel
		var shake := tremble if i == current else 0.0
		# Key pin sits in the plug, driver pin and spring above the line.
		var key_pin := Rect2(x - 14 + shake, shear_y + 34 - lift, 28, 70)
		var driver := Rect2(x - 14 + shake, shear_y - 76 - lift + 4, 28, 72)
		if pin["set"]:
			key_pin.position.y = shear_y + 2
			driver.position.y = shear_y - 74
		var key_color := Color("d9c08a")
		if i == current and not finished:
			key_color = key_color.lerp(Color("f4e2b0"), .5 if pin["inside"] else 0.0).lerp(Color("b5524a"), drop_flash)
		elif pin["set"]:
			key_color = Color("9fb08a")
		board.draw_rect(key_pin, key_color)
		board.draw_rect(driver, Color("a7acb0"))
		var spring_top := r.position.y + 14
		var spring_bottom := driver.position.y
		var coils := 7
		for c in coils:
			var a := Vector2(x - 10 + shake, lerpf(spring_top, spring_bottom, float(c) / coils))
			var b := Vector2(x + 10 + shake, lerpf(spring_top, spring_bottom, (c + .5) / coils))
			board.draw_line(a, b, Color("8d8f86"), 2.0)
	if not finished and current < pins.size():
		# The hairpin enters from the left and lifts the current pin.
		var x := pin_x(current)
		var tip_y: float = shear_y + 104 - pins[current]["height"] * travel
		var start := Vector2(r.position.x - 140, plug.end.y - 18)
		board.draw_line(start, Vector2(x - 6, plug.end.y - 18), Color("2f2a26"), 6.0)
		board.draw_line(Vector2(x - 6, plug.end.y - 18), Vector2(x + 4, tip_y), Color("2f2a26"), 6.0)
	var done := 0
	for pin in pins: done += 1 if pin["set"] else 0
	var font := ThemeDB.fallback_font
	board.draw_string(font, Vector2(r.position.x, r.end.y + 34), "Штифты: %d / %d" % [done, pins.size()], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 20, Color("cdbf9f"))
