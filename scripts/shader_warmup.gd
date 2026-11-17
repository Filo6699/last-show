extends CanvasLayer
## Loading screen shown once at launch. It continues the boot splash
## (assets/ui/boot_splash.png) and fills its bar while, behind it, the camera
## visits every area so the GPU driver compiles each material and light
## combination before play. Without it the first look at a new area froze the
## game for seconds (New Game, the first fade into the clinic, the roof).
signal finished
var game
var picture: TextureRect
var fill: ColorRect
# Marquee bulbs under the bar: a chase of light that keeps running on its own
# clock, so the screen looks alive even while the bar waits on a slow step.
var bulbs: Control
const BULB_COUNT := 15
const BULB_SPACING := 28.0
const BULB_RADIUS := 5.0
const BULB_Y := 470.0
const CHASE_SPEED := 9.0 # bulbs per second
var progress := 0.0
var started := 0
# Bar inside the splash image, in image pixels.
const SPLASH := Vector2(1280, 720)
const BAR := Rect2(430, 432, 420, 6)
# [position, facing, story phase that shows the area]
const TOUR := [
	[Vector3(0, .36, -5.8), Vector3(0, 1.35, 6.6), "intro"],
	[Vector3(-8, .05, 18), Vector3(-8, 1.6, 30), "news"],
	[Vector3(-12, .05, 26), Vector3(-12, 1.25, 29), "news"],
	[Vector3(-46, .05, 33.6), Vector3(-46.7, 1.45, 31.45), "elsa_dressing"],
	[Vector3(-20, .05, 40), Vector3(-20, 1.6, 50), "to_technical"],
	[Vector3(-19.6, .05, 57), Vector3(-16.75, 1.6, 57), "photos"],
	[Vector3(-10, 40.02, -18), Vector3(-7.85, 41.05, -10), "roof"],
	[Vector3(155, .05, 1.8), Vector3(151.9, .95, 2.6), "home"],
]
const YAWS := 4

func setup(owner_game) -> void:
	game = owner_game
	layer = 120
	var back := ColorRect.new(); back.color = ProjectSettings.get_setting("application/boot_splash/bg_color")
	back.set_anchors_preset(Control.PRESET_FULL_RECT); add_child(back)
	picture = TextureRect.new(); picture.texture = preload("res://assets/ui/boot_splash.png")
	picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(picture)
	fill = ColorRect.new(); fill.color = Color(.62, .12, .1)
	add_child(fill)
	bulbs = Control.new()
	bulbs.set_anchors_preset(Control.PRESET_FULL_RECT)
	bulbs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bulbs.draw.connect(draw_bulbs)
	add_child(bulbs)

func _process(_delta: float) -> void:
	# Place the fill over the bar of the splash picture as it is drawn now.
	var area := picture.size
	var k := minf(area.x / SPLASH.x, area.y / SPLASH.y)
	var origin := picture.position + (area - SPLASH * k) * .5
	fill.position = origin + BAR.position * k
	fill.size = Vector2(BAR.size.x * k * progress, BAR.size.y * k)
	bulbs.queue_redraw()

# Splash image coordinates to screen coordinates, as the picture is drawn now.
func to_screen(point: Vector2) -> Vector2:
	var area := picture.size
	var k := minf(area.x / SPLASH.x, area.y / SPLASH.y)
	return picture.position + (area - SPLASH * k) * .5 + point * k

func draw_bulbs() -> void:
	var k := minf(picture.size.x / SPLASH.x, picture.size.y / SPLASH.y)
	var head := fmod(Time.get_ticks_msec() / 1000.0 * CHASE_SPEED, float(BULB_COUNT + 6))
	var left := SPLASH.x * .5 - BULB_SPACING * (BULB_COUNT - 1) * .5
	for i in BULB_COUNT:
		# Brightest at the head of the chase, fading over the four bulbs behind it.
		var behind := head - i
		var glow := clampf(1.0 - behind / 4.0, 0.0, 1.0) if behind >= 0.0 else 0.0
		var centre := to_screen(Vector2(left + i * BULB_SPACING, BULB_Y))
		var radius := BULB_RADIUS * k
		if glow > 0.0: bulbs.draw_circle(centre, radius * 2.4, Color(.95, .62, .25, .18 * glow))
		bulbs.draw_circle(centre, radius, Color(.22, .15, .13).lerp(Color(1.0, .82, .5), glow))

func step() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

# The opening's sepia filter and Bruno's barbell first appear mid-scene; draw
# them once here, under the loading screen, so the show does not stall.
func warm_opening() -> void:
	var opening = game.opening
	if not is_instance_valid(opening): return
	if is_instance_valid(game.audio): game.audio.preload_opening()
	opening.build_barbell()
	if is_instance_valid(opening.barbell): opening.barbell.show()
	opening.sepia.material.set_shader_parameter("amount", 1.0)
	opening.sepia.show()
	opening.visible = true
	await step(); await step()
	opening.visible = false
	opening.sepia.hide()
	if is_instance_valid(opening.barbell): opening.barbell.hide()

# A short cover for New Game and Continue: the loading screen is drawn first,
# then `work` sets the scene up behind it, and the cover stays until the new
# scene has rendered a few frames, which is where the first-draw cost lands.
func cover(work: Callable) -> void:
	visible = true
	progress = 0.0
	await step(); await step()
	progress = .3
	if is_instance_valid(game.audio): game.audio.preload_opening()
	await step()
	progress = .5
	work.call()
	for i in 4:
		await step()
		progress = .5 + .125 * (i + 1)
	visible = false
	finished.emit()

func run() -> void:
	started = Time.get_ticks_msec()
	visible = true
	var saved_phase: String = game.phase
	var saved_flags: Dictionary = game.flags.duplicate(true)
	game.hud.hide_menu(); game.hud.fade.hide(); game.hud.story_backdrop.hide()
	game.player.set_locked(true)
	# Draw the loading screen first, then bring the world in piece by piece so
	# the bar moves while the driver compiles.
	var parts: Array[Node3D] = []
	for child in game.world.get_children():
		if child is Node3D and child != game.player and child.visible:
			parts.append(child); child.visible = false
	await step(); await step()
	await warm_opening()
	var steps := parts.size() + TOUR.size() * YAWS
	var done := 0
	for part in parts:
		part.visible = true
		await step()
		done += 1; progress = float(done) / steps
	for stop in TOUR:
		if game.phase != stop[2]:
			game.phase = stop[2]; game.update_staging()
		for i in YAWS:
			var at: Vector3 = stop[0]
			var dir: Vector3 = (stop[1] - at).rotated(Vector3.UP, TAU * i / YAWS)
			game.place_player(at, at + dir)
			game.player.set_locked(true)
			await step()
			done += 1; progress = float(done) / steps
	game.phase = saved_phase; game.flags = saved_flags
	game.update_staging()
	game.place_player(Vector3(0, .36, -5.8), Vector3(0, 1.35, 6.6))
	progress = 1.0
	await step()
	print("warmup_ms=", Time.get_ticks_msec() - started)
	visible = false
	finished.emit()
