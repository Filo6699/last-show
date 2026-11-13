extends Node
## The walk from Walter's clinic back through the arena to the roof ladder.
## Once Richard leaves the clinic the show lights are dead and he walks by
## flashlight. Figures with glowing eyes stand in the dark and vanish the
## moment the beam touches them. Two staged scares and a panic layer
## (breathing, heartbeat, vignette, camera tremor) run on top.
const PHASES := ["return_arena", "roof_access"]
const FIGURE_LIMIT := 4
const BEAM_RANGE := 17.0
const BEAM_ANGLE := 21.0
const VIGNETTE := """
shader_type canvas_item;
uniform float panic = 0.0;
uniform float pulse = 0.0;
void fragment() {
	float d = distance(UV, vec2(.5));
	float dark = smoothstep(.62 - panic * .3, .2 - panic * .12, d);
	COLOR = vec4(mix(vec3(0), vec3(.07, 0, 0), pulse * panic * panic), (1.0 - dark) * (.4 + panic * .5));
}
"""

var game
var flashlight: SpotLight3D
var figures: Array[Sprite3D] = []
var figure_texture: Texture2D = preload("res://assets/ui/shadow_figure.png")
var dimmed: Dictionary = {}
var active := false
var panic := 0.0
var spawn_wait := 2.0
var flicker_wait := 0.0
var beam_off := 0.0
var drawing := false
var draw_token := 0
var heart_wait := 0.0
var breath: AudioStreamPlayer
var breath_wait := 3.0
var overlay: CanvasLayer
var vignette := ShaderMaterial.new()
var lunge: Sprite3D
var rng := RandomNumberGenerator.new()

func setup(owner_game) -> void:
	game = owner_game
	rng.randomize()
	flashlight = SpotLight3D.new()
	flashlight.name = "Flashlight"
	flashlight.spot_range = BEAM_RANGE
	flashlight.spot_angle = BEAM_ANGLE
	flashlight.spot_angle_attenuation = .7
	flashlight.spot_attenuation = .9
	flashlight.light_energy = 3.2
	flashlight.light_color = Color(1, .93, .78)
	flashlight.position = Vector3(.18, -.2, 0)
	flashlight.visible = false
	game.player.camera.add_child(flashlight)
	overlay = CanvasLayer.new()
	overlay.layer = 6
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = VIGNETTE
	vignette.shader = shader
	rect.material = vignette
	overlay.add_child(rect)
	overlay.visible = false
	add_child(overlay)

func should_run() -> bool:
	if not game.phase in PHASES: return false
	if game.flags.get("flashlight", false): return true
	# The beam clicks on when Richard steps out of the clinic.
	if game.room_at(game.player.position) != "clinic":
		game.flags["flashlight"] = true
		return true
	return false

func _process(delta: float) -> void:
	var run := should_run()
	if run != active:
		if run: begin()
		else: finish()
	if not active: return
	var paused: bool = game.hud.menu.visible or game.get_tree().paused
	if paused: return
	var story_busy: bool = game.player.locked or game.transitioning
	update_beam(delta)
	update_figures(delta, story_busy)
	if not story_busy: staged_scares()
	update_panic(delta)

func begin() -> void:
	active = true
	overlay.visible = true
	draw_flashlight()
	# Kill every light outside the clinic; the beam is all Richard has.
	var clinic := AABB(Vector3(-24, -1, 53.5), Vector3(8, 6, 7))
	for light in game.world.find_children("*", "Light3D", true, false):
		if light == flashlight or clinic.has_point(light.global_position): continue
		dimmed[light] = light.light_energy
		light.light_energy = 0.0
	var env: Environment = game.player.camera.environment
	if env:
		env.ambient_light_energy = .035
		env.fog_light_color = Color(.01, .012, .02)
	breath_wait = 3.0

func finish() -> void:
	active = false
	drawing = false
	draw_token += 1
	flashlight.visible = false
	overlay.visible = false
	for light in dimmed:
		if is_instance_valid(light): light.light_energy = dimmed[light]
	dimmed.clear()
	for figure in figures:
		if is_instance_valid(figure): figure.queue_free()
	figures.clear()
	lunge = null
	panic = 0.0
	game.player.camera.h_offset = 0
	game.player.camera.v_offset = 0
	if is_instance_valid(breath): breath.queue_free()
	breath = null

# Called on new game / load so a fresh run never inherits the dark.
func reset() -> void:
	if active: finish()

# The lights die first. Richard stands in the dark for a moment, then fumbles
# the torch out of his coat and lifts the beam from his feet to eye level.
func draw_flashlight() -> void:
	draw_token += 1
	var token := draw_token
	drawing = true
	flashlight.visible = false
	await get_tree().create_timer(1.0).timeout
	if token != draw_token: return
	game.hud.show_notice("Темно. Фонарь… где-то в кармане.")
	await get_tree().create_timer(2.0).timeout
	if token != draw_token: return
	game.audio.play("sfx_flashlight_click", 0, Vector3.INF, "SFX", 2)
	flashlight.rotation.x = -1.1
	flashlight.light_energy = 0.0
	flashlight.visible = true
	var tween := create_tween().set_parallel(true)
	tween.tween_property(flashlight, "rotation:x", 0.0, .7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var energy := create_tween()
	for level in [1.6, .2, 2.4, .6, 3.2]:
		energy.tween_property(flashlight, "light_energy", level, .07)
	await energy.finished
	if token != draw_token: return
	drawing = false
	flicker_wait = 3.0

func update_beam(delta: float) -> void:
	if drawing: return
	if beam_off > 0:
		beam_off -= delta
		flashlight.visible = beam_off <= 0
		if beam_off <= 0: game.audio.play("sfx_flashlight_click", 0, Vector3.INF, "SFX", 2)
		return
	# Panic makes the old bulb stutter.
	flicker_wait -= delta
	if flicker_wait <= 0:
		flicker_wait = rng.randf_range(2.0, 7.0) * (1.4 - panic)
		if panic > .45 and rng.randf() < panic:
			var tween := create_tween()
			for i in rng.randi_range(2, 4):
				tween.tween_callback(func(): flashlight.light_energy = .3)
				tween.tween_interval(rng.randf_range(.03, .09))
				tween.tween_callback(func(): flashlight.light_energy = 3.2)
				tween.tween_interval(rng.randf_range(.04, .12))

func kill_beam(seconds: float) -> void:
	beam_off = seconds
	flashlight.visible = false
	game.audio.play("sfx_flashlight_click", 0, Vector3.INF, "SFX", 4)

func eye() -> Vector3:
	return game.player.camera.global_position

func in_beam(point: Vector3) -> bool:
	if not flashlight.visible or flashlight.light_energy < 1: return false
	var to := point - eye()
	if to.length() > BEAM_RANGE: return false
	var forward: Vector3 = -game.player.camera.global_basis.z
	return rad_to_deg(forward.angle_to(to.normalized())) < BEAM_ANGLE * .85 and clear_line(eye(), point)

func clear_line(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [game.player.get_rid()]
	return game.player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func make_figure(at: Vector3) -> Sprite3D:
	var figure := Sprite3D.new()
	figure.texture = figure_texture
	figure.pixel_size = .0042
	figure.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	figure.shaded = false
	figure.offset = Vector2(0, 256)
	figure.position = at
	game.world.add_child(figure)
	figures.append(figure)
	return figure

# A spot in the dark: on the floor, in line of sight, outside the beam.
func dark_spot(near: float, far: float) -> Variant:
	var space: PhysicsDirectSpaceState3D = game.player.get_world_3d().direct_space_state
	for attempt in 10:
		var angle := rng.randf() * TAU
		var p: Vector3 = game.player.global_position + Vector3(cos(angle), 0, sin(angle)) * rng.randf_range(near, far)
		var down := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2.5, p + Vector3.DOWN * 3)
		var hit := space.intersect_ray(down)
		if hit.is_empty(): continue
		var floor_point: Vector3 = hit.position
		if absf(floor_point.y - game.player.global_position.y) > 1.2: continue
		if not clear_line(eye(), floor_point + Vector3.UP * 1.7): continue
		if in_beam(floor_point + Vector3.UP * 1.7): continue
		return floor_point
	return null

func update_figures(delta: float, story_busy: bool) -> void:
	spawn_wait -= delta
	if not story_busy and spawn_wait <= 0 and figures.size() < FIGURE_LIMIT:
		spawn_wait = rng.randf_range(2.5, 6.0)
		var spot = dark_spot(6.0, 13.0)
		if spot != null: make_figure(spot)
	for figure in figures.duplicate():
		if not is_instance_valid(figure):
			figures.erase(figure)
			continue
		if figure.has_meta("leaving"): continue
		var head: Vector3 = figure.global_position + Vector3.UP * 1.75
		if in_beam(head):
			if figure == lunge:
				lunge = null
				figure.queue_free()
				figures.erase(figure)
				jump_scare("Не смотри. Не смотри на неё.")
				continue
			vanish(figure)
		elif figure != lunge and head.distance_to(eye()) < 2.2:
			# Nobody lit it and it came too close: gone with a breath on the neck.
			vanish(figure)
			panic = minf(1.0, panic + .25)

func vanish(figure: Sprite3D) -> void:
	figure.set_meta("leaving", true)
	game.audio.play("sfx_whisper", 0, figure.global_position + Vector3.UP * 1.6, "SFX", -4)
	panic = minf(1.0, panic + .12)
	var tween := create_tween()
	tween.tween_property(figure, "modulate:a", 0.0, .12)
	tween.tween_callback(func():
		figures.erase(figure)
		figure.queue_free())

func jump_scare(line: String) -> void:
	game.shake_camera(.06)
	game.audio.cue("lili_glimpse")
	panic = 1.0
	game.hud.show_notice(line)

func staged_scares() -> void:
	var p: Vector3 = game.player.global_position
	var flags: Dictionary = game.flags
	# 1. Stepping into the arena: the bulb dies and they are all around him.
	if game.phase == "roof_access" and not flags.get("dark_ring", false):
		flags["dark_ring"] = true
		kill_beam(2.2)
		for i in 7:
			var angle := TAU * i / 7.0 + rng.randf() * .3
			var at := p + Vector3(cos(angle), 0, sin(angle)) * rng.randf_range(3.5, 5.5)
			at.y = p.y - .36
			if clear_line(eye(), at + Vector3.UP * 1.7): make_figure(at)
		panic = .8
		game.audio.play("sfx_heartbeat", 0, Vector3.INF, "SFX", 8)
		get_tree().create_timer(2.3).timeout.connect(func():
			if not active: return
			for figure in figures.duplicate():
				if is_instance_valid(figure) and not figure.has_meta("leaving"): vanish(figure)
			game.hud.show_notice("Это тени. Просто тени. Дыши, Ричард."))
	# 2. Halfway to the ladder something waits right behind him.
	var to_mast := Vector2(p.x - game.full_game.late.MAST.x, p.z - game.full_game.late.MAST.z).length()
	if game.phase == "roof_access" and to_mast < 13.0 and not flags.get("dark_lunge", false):
		flags["dark_lunge"] = true
		var back: Vector3 = game.player.camera.global_basis.z
		back.y = 0
		var at := p + back.normalized() * 1.6
		at.y = p.y - .36
		lunge = make_figure(at)
		game.audio.play("sfx_whisper", 0, at + Vector3.UP * 1.6, "SFX", 8)
		game.hud.show_notice("Сзади кто-то дышит.")
	if lunge and is_instance_valid(lunge):
		# It follows him until he turns round.
		var back: Vector3 = game.player.camera.global_basis.z
		back.y = 0
		lunge.global_position = lunge.global_position.lerp(p + back.normalized() * 1.5 + Vector3(0, -.36, 0), .08)
	# 3. At the ladder the bulb gives out once more.
	if game.phase == "roof_access" and to_mast < 4.0 and not flags.get("dark_ladder", false):
		flags["dark_ladder"] = true
		kill_beam(1.2)
		panic = maxf(panic, .7)
		game.hud.show_notice("Наверх. Быстрее наверх.")

# Single human breaths (inhale then exhale) instead of a loop: silent while calm, fading in
# with panic, faster and a little louder when scared, never on a fixed rhythm.
func update_breath(delta: float) -> void:
	breath_wait -= delta
	if breath_wait > 0 or panic < .18: return
	if is_instance_valid(breath) and breath.playing:
		breath_wait = .3
		return
	var amount := smoothstep(.18, 1.0, panic)
	breath_wait = lerpf(3.8, 1.7, amount) * randf_range(.8, 1.35)
	var id: String = ["sfx_breath_a", "sfx_breath_b", "sfx_breath_c"][randi() % 3]
	var node: Node = game.audio.play(id, 0, Vector3.INF, "SFX", lerpf(-8.0, 3.0, amount) + randf_range(-2.0, 1.0))
	node.pitch_scale = randf_range(.9, 1.08) + amount * .12
	breath = node as AudioStreamPlayer

func update_panic(delta: float) -> void:
	var near := 0
	for figure in figures:
		if is_instance_valid(figure) and figure.global_position.distance_to(game.player.global_position) < 8: near += 1
	var target := .15 + near * .1
	panic = move_toward(panic, maxf(target, 0.0), delta * (.12 if panic > target else .05))
	vignette.set_shader_parameter("panic", panic)
	vignette.set_shader_parameter("pulse", .5 + .5 * sin(Time.get_ticks_msec() * .001 * TAU * (1.2 + panic * 1.4)))
	update_breath(delta)
	heart_wait -= delta
	if heart_wait <= 0 and panic > .35:
		heart_wait = lerpf(1.1, .45, panic)
		var beat: Node = game.audio.play("sfx_heartbeat", 0, Vector3.INF, "SFX", lerpf(-10.0, 2.0, panic))
		beat.pitch_scale = 1.0 + panic * .3
	var tremor := panic * panic * .012
	var t := Time.get_ticks_msec() * .001
	game.player.camera.h_offset = sin(t * 23.0) * tremor + sin(t * 7.1) * tremor
	game.player.camera.v_offset = sin(t * 19.0 + 1.3) * tremor
