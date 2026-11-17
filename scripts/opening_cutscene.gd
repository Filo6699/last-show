extends CanvasLayer
## Opening cutscene from the screenplay: Richard, ringmaster, runs the last show
## of the season in first person. He sweeps the audience and announces each act;
## each announcement cuts to a short shot of that act. The whole scene is an old
## sepia print. Every act ends with its performer leaving the ring, and the
## spotlight cut hides the moment they are gone. Ends on Richard's stage view and
## hands over to the "intro" dialogue (bow / applause).
signal finished

# Bruno's one-handed press: right upper arm swing and elbow bend around the
# skeleton's forward axis (radians; negative swings the right arm out and up).
const RACK := Vector2(-1.35, -1.75) # weight on the shoulder, forearm upright
const OVERHEAD := Vector2(-2.95, -.12) # arm locked straight above the head
const HAND_REACH := .62 # elbow to the middle of the fist, metres
const SEPIA_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float amount : hint_range(0.0, 1.0) = 1.0;
void fragment() {
	vec3 c = texture(screen_texture, SCREEN_UV).rgb;
	// Old print: luminance on a warm brown ramp, darks lifted a little so the
	// dim tent stays readable, edges burnt in.
	float l = pow(dot(c, vec3(0.299, 0.587, 0.114)), 0.85);
	vec3 tone = vec3(l * 1.08 + 0.025, l * 0.88 + 0.018, l * 0.64 + 0.008);
	float edge = smoothstep(0.3, 0.8, length((SCREEN_UV - 0.5) * vec2(1.0, 0.8)));
	COLOR = vec4(mix(c, tone * (1.0 - edge * 0.4), amount), 1.0);
}
"""

## Poses one arm on top of the idle animation; `influence` blends it in and out.
class ArmPose extends SkeletonModifier3D:
	var upper := -1
	var fore := -1
	var raise := 0.0
	var bend := 0.0
	func _process_modification_with_delta(_delta: float) -> void:
		var skeleton := get_skeleton()
		if skeleton == null or upper < 0 or fore < 0: return
		var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(upper))
		var arm := parent * skeleton.get_bone_pose(upper)
		arm.basis = Basis(Vector3.BACK, raise) * arm.basis
		skeleton.set_bone_pose_rotation(upper, (parent.basis.inverse() * arm.basis).get_rotation_quaternion())
		var forearm := arm * skeleton.get_bone_pose(fore)
		forearm.basis = Basis(Vector3.BACK, bend) * forearm.basis
		skeleton.set_bone_pose_rotation(fore, (arm.basis.inverse() * forearm.basis).get_rotation_quaternion())

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
var arm_pose: ArmPose
var barbell: Node3D

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
	sepia.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = SEPIA_SHADER
	sepia.material = ShaderMaterial.new()
	sepia.material.shader = shader
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
	flash.color = Color(1, .93, .8, 0)
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
	if playing and is_instance_valid(game) and is_instance_valid(game.audio): game.audio.opening_stop(.6)
	playing = false
	visible = false
	end_lift()
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

func cue(id: String, lufs := NAN, pitch := 1.0) -> void:
	if is_instance_valid(game.audio): game.audio.opening_sound(id, lufs, pitch)

func cheer(seconds: float, lufs: float) -> void:
	if is_instance_valid(game.audio): game.audio.opening_cheer(seconds, lufs)

# Calls each [seconds, Callable] beat at that time from now (seconds ascending).
func beats(list: Array) -> void:
	var tween := create_tween()
	motion.append(tween)
	var now := 0.0
	for beat in list:
		if beat[0] > now: tween.tween_interval(beat[0] - now)
		now = maxf(now, beat[0])
		tween.tween_callback(beat[1])

# The act is over: the light goes .4 s before the shot ends, then the performer leaves.
func act_end(id: String, seconds: float) -> void:
	beats([[seconds - .4, lights_out.bind(send_off.bind(id))]])

# Into an act: a warm flash, the band already rolling.
func cut_in() -> void:
	flash.color.a = .6
	var tween := create_tween()
	tween.tween_property(flash, "color:a", 0.0, .35)
	motion.append(tween)

# End of an act: the spotlight is switched off and the screen goes black;
# `vanish` runs only once nothing is visible, so no performer pops out in view.
func lights_out(vanish: Callable) -> void:
	cue("sfx_open_light_cut")
	black.modulate.a = 0
	black.show()
	var tween := create_tween()
	tween.tween_property(black, "modulate:a", 1.0, .14)
	tween.tween_callback(vanish)
	motion.append(tween)

# Back to Richard's eyes out of the blackout.
func lights_up() -> void:
	var tween := create_tween()
	tween.tween_property(black, "modulate:a", 0.0, .4)
	motion.append(tween)

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
	# Performers come out to the ring for their acts only; each one leaves for
	# their story mark behind a light cut (send_off), and update_staging holds
	# them there when the scene ends.
	var a: Dictionary = game.actors
	for id in ["elsa", "bruno", "lili", "mordecai"]:
		a[id].show()
		a[id].collision_layer = 0
		game.location.placements.erase(id)
	a.elsa.position = Vector3(4.5, 9.0, 3.5)
	a.elsa.rotation = Vector3(0, PI, 0)
	a.bruno.position = Vector3(-3.2, 1.55, 2.6)
	a.bruno.rotation = Vector3(0, PI * .85, 0)
	a.lili.position = Vector3(game.layout.TRUNK.x, game.LILI_IN_TRUNK_Y, game.layout.TRUNK.z)
	a.lili.rotation = Vector3.ZERO
	a.lili.hide()
	a.mordecai.position = Vector3(4.2, 1.25, -1.2)
	a.mordecai.rotation = Vector3(0, -PI * .6, 0)
	build_barbell()

# Where each performer goes once the light is off: the same marks the story
# staging uses, so the end of the scene changes nothing on screen.
func send_off(id: String) -> void:
	var actor: Node3D = game.actors[id]
	match id:
		"elsa":
			actor.position = game.layout.ELSA_DRESSING + Vector3(0, 2.2, 0)
			actor.rotation = Vector3(0, PI, 0)
		"bruno":
			end_lift()
			actor.position = game.layout.BRUNO
			actor.rotation = Vector3(0, PI - .5, 0)
		"lili":
			actor.hide()
			actor.rotation = Vector3.ZERO
			actor.position = Vector3(game.layout.TRUNK.x, game.LILI_IN_TRUNK_Y, game.layout.TRUNK.z)
		"mordecai":
			actor.position = game.layout.ARENA_MORDECAI
			actor.rotation = Vector3(0, PI, 0)

# ---- Elsa: two swings under the dome, then the rig hauls her up into the dark.
func elsa_act(seconds: float) -> void:
	var elsa: Node3D = game.actors.elsa
	var swing := 2.6
	var tween := create_tween()
	tween.tween_method(func(p: float):
		elsa.position = Vector3(4.5 + sin(p) * 2.6, 9.0 - absf(cos(p)) * .6, 3.5)
		elsa.rotation.z = -sin(p) * .35, 0.0, PI * 2.5, swing)
	tween.tween_property(elsa, "position:y", 13.0, seconds - swing).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(elsa, "rotation:z", 0.0, .5)
	motion.append(tween)
	# Swing bottoms (fastest) at p = PI and 2 PI; the band hits the far apex at 1.5 PI.
	beats([
		[swing * .4 - .37, cue.bind("sfx_open_swish", NAN, .95)],
		[swing * .6, func(): cue("sfx_open_tada"); cheer(1.0, -37.0)],
		[swing * .8 - .37, cue.bind("sfx_open_swish", NAN, 1.08)],
		[swing, cue.bind("sfx_elsa_rig_creak_02", -40.0)],
	])

# ---- Bruno: one-handed press of a globe barbell, a show-off hop, walks off.
func build_barbell() -> void:
	if is_instance_valid(arm_pose): return
	var found: Array[Node] = game.actors.bruno.find_children("*", "Skeleton3D", true, false)
	if found.is_empty(): return
	var skeleton: Skeleton3D = found[0]
	var pose := ArmPose.new()
	pose.upper = skeleton.find_bone("upper_R")
	pose.fore = skeleton.find_bone("fore_R")
	if pose.upper < 0 or pose.fore < 0:
		pose.free()
		return
	pose.name = "OpeningArmPose"
	pose.influence = 0.0
	skeleton.add_child(pose)
	arm_pose = pose
	# Fist position and a bar across it, worked out on the rest pose and
	# carried by the forearm bone from then on.
	var elbow := skeleton.get_bone_global_rest(pose.fore)
	var along := (elbow.origin - skeleton.get_bone_global_rest(pose.upper).origin).normalized()
	var across := Vector3.BACK.cross(along).normalized()
	var grip := Transform3D(Basis(across.cross(Vector3.BACK), across, Vector3.BACK), elbow.origin + along * HAND_REACH)
	var attach := BoneAttachment3D.new()
	attach.name = "OpeningGrip"
	attach.bone_name = "fore_R"
	skeleton.add_child(attach)
	# Circus globe barbell, as low-poly as the rest of the props.
	barbell = Node3D.new()
	barbell.name = "GlobeBarbell"
	barbell.transform = elbow.affine_inverse() * grip
	attach.add_child(barbell)
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color("2f2b27")
	iron.roughness = .45
	iron.metallic = .5
	var bar_mesh := CylinderMesh.new()
	bar_mesh.top_radius = .028
	bar_mesh.bottom_radius = .028
	bar_mesh.height = 1.0
	bar_mesh.radial_segments = 6
	bar_mesh.rings = 1
	var globe_mesh := SphereMesh.new()
	globe_mesh.radius = .2
	globe_mesh.height = .4
	globe_mesh.radial_segments = 8
	globe_mesh.rings = 4
	var band_mesh := CylinderMesh.new()
	band_mesh.top_radius = .205
	band_mesh.bottom_radius = .205
	band_mesh.height = .06
	band_mesh.radial_segments = 8
	band_mesh.rings = 1
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color("a8843f")
	brass.roughness = .5
	brass.metallic = .4
	var parts := [[bar_mesh, iron, 0.0]]
	for side in [-1.0, 1.0]:
		parts.append([globe_mesh, iron, side * .5])
		parts.append([band_mesh, brass, side * .5])
	for part in parts:
		var piece := MeshInstance3D.new()
		piece.mesh = part[0]
		piece.material_override = part[1]
		piece.position.y = part[2]
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		barbell.add_child(piece)
	barbell.hide()

func end_lift() -> void:
	if is_instance_valid(arm_pose): arm_pose.influence = 0.0
	if is_instance_valid(barbell): barbell.hide()

func arm_to(tween: Tween, target: Vector2, seconds: float) -> void:
	tween.tween_property(arm_pose, "raise", target.x, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(arm_pose, "bend", target.y, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func bruno_act(viewer: Vector3) -> void:
	var bruno: Node3D = game.actors.bruno
	var ground := 1.55
	var to_viewer := viewer - bruno.position
	bruno.rotation = Vector3(0, atan2(to_viewer.x, to_viewer.z) + .3, 0)
	var tween := create_tween()
	motion.append(tween)
	if is_instance_valid(arm_pose):
		arm_pose.influence = 1.0
		arm_pose.raise = RACK.x
		arm_pose.bend = RACK.y
		barbell.show()
		# Gathers, then presses the weight up on one arm against the drum roll (0-1.4 s).
		tween.tween_property(bruno, "position:y", ground - .06, .3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		arm_to(tween, OVERHEAD, 1.1)
		tween.parallel().tween_property(bruno, "position:y", ground, .5).set_delay(.2)
		# Holds it locked out while the arm shakes under the load (1.4-1.9 s).
		tween.tween_method(func(t: float): arm_pose.raise = OVERHEAD.x + sin(t * 40.0) * .025 * (1.0 - t), 0.0, 1.0, .5)
	else:
		tween.tween_interval(1.9)
	# A short show-off hop, landing flat on the boards at 2.3 s; the knees take it.
	tween.tween_property(bruno, "position:y", ground + .22, .22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(bruno, "position:y", ground, .18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(bruno, "position:y", ground - .07, .07).set_ease(Tween.EASE_OUT)
	tween.tween_property(bruno, "position:y", ground, .15).set_trans(Tween.TRANS_SINE)
	if is_instance_valid(arm_pose): arm_to(tween, RACK, .4)
	else: tween.tween_interval(.4)
	# Turns away from the light and walks off with the weight on his shoulder (2.9-3.9 s).
	var away := ((bruno.position - viewer) * Vector3(1, 0, 1)).normalized().rotated(Vector3.UP, -.6)
	tween.tween_property(bruno, "rotation:y", atan2(away.x, away.z), .25).set_trans(Tween.TRANS_SINE)
	tween.tween_method(func(t: float):
		var stride := sin(t * PI * 3.0)
		bruno.position = Vector3(-3.2, ground, 2.6) + away * 1.1 * t + Vector3(0, absf(stride) * .05, 0)
		bruno.rotation.z = stride * .04, 0.0, 1.0, .8)
	beats([
		[1.4, func(): cue("sfx_open_tada"); cheer(1.2, -37.0)],
		[2.3, func(): cue("sfx_open_land"); cue("sfx_open_iron", NAN, .92)],
		[3.2, cue.bind("sfx_step_mordecai_01", -43.0, .78)],
		[3.47, cue.bind("sfx_step_mordecai_03", -43.0, .74)],
		[3.74, cue.bind("sfx_step_mordecai_02", -44.0, .78)],
	])

# ---- Lili: bursts out of the magic trunk, curtsies, dives back in, lid shuts.
func lili_act(viewer: Vector3) -> void:
	var lili: Node3D = game.actors.lili
	var inside := Vector3(game.layout.TRUNK.x, game.LILI_IN_TRUNK_Y, game.layout.TRUNK.z)
	var landing: Vector3 = game.layout.TRUNK + Vector3(-1.1, .35, 1.3)
	lili.position = inside
	lili.look_at(Vector3(viewer.x, inside.y, viewer.z), Vector3.UP, true)
	var yaw := lili.rotation.y
	var tween := create_tween()
	motion.append(tween)
	tween.tween_interval(.5)
	tween.tween_callback(func():
		lili.show()
		game.full_game.set_dressing.set_trunk_open(true, true)
		cue("sfx_box_bump_02", -36.0)
		cue("sfx_open_chime"))
	tween.tween_property(lili, "position", inside + Vector3(0, 1.75, 0), .35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_callback(cue.bind("sfx_lili_jump", -37.0)).set_delay(.2)
	tween.tween_property(lili, "position", landing, .4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(cheer.bind(.8, -38.0))
	# Curtsy to the house.
	tween.tween_property(lili, "rotation:x", .3, .22).set_trans(Tween.TRANS_SINE)
	tween.tween_property(lili, "rotation:x", 0.0, .25).set_trans(Tween.TRANS_SINE)
	# Back over the rim and down out of sight; the lid drops after her.
	tween.tween_property(lili, "position", inside + Vector3(0, 1.5, 0), .32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(lili, "rotation:y", yaw + PI, .32)
	tween.tween_property(lili, "position", inside - Vector3(0, .65, 0), .3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		game.full_game.set_dressing.set_trunk_open(false, true)
		cue("sfx_box_bump_01", -38.0))

# ---- Mordecai: spins, laughs, honks his horn, bows as the light goes.
func mordecai_act() -> void:
	var mordecai: Node3D = game.actors.mordecai
	var tween := create_tween()
	motion.append(tween)
	tween.tween_property(mordecai, "rotation:y", mordecai.rotation.y + TAU, 1.4).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(cue.bind("sfx_open_horn"))
	tween.tween_property(mordecai, "rotation:x", -.25, .3)
	tween.tween_property(mordecai, "rotation:x", 0.0, .3)
	tween.tween_callback(cheer.bind(.6, -39.0))
	tween.tween_property(mordecai, "rotation:x", .35, .3).set_trans(Tween.TRANS_SINE)
	game.audio.emote("mordecai_laugh")

func drum_roll() -> void:
	cue("sfx_open_roll")

func play() -> void:
	token += 1
	var own := token
	playing = true
	skipped = false
	visible = true
	caption.text = ""
	sepia.material.set_shader_parameter("amount", 1.0)
	sepia.show()
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
	# Skipped mid-act: put every performer where the story expects them.
	for id in ["elsa", "bruno", "lili", "mordecai"]: send_off(id)
	game.update_staging()
	# A skip during the lid animation would leave the trunk open; Lili is not out yet.
	game.full_game.set_dressing.set_trunk_open(false)
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
	if not await hold(5.0, own): return
	var open := create_tween()
	open.tween_property(title, "modulate:a", 0.0, .5)
	open.parallel().tween_property(subtitle, "modulate:a", 0.0, .5)
	open.tween_property(black, "modulate:a", 0.0, .9)
	motion.append(open)
	# The band keeps playing the show waltz throughout (chapter_audio sync);
	# the full house murmurs louder and greets the ringmaster.
	if is_instance_valid(game.audio): game.audio.opening_crowd(5.0, 2.0)
	cheer(2.2, -35.0)
	# First person: Richard turns from one side of the audience to the other.
	game.player.rotation.y = base_yaw - .95
	game.player.camera.rotation.x = .12
	pov(.95, .16, 4.0)
	raise_cane()
	say("РИЧАРД: Дамы и господа! Добро пожаловать на последнее представление сезона!")
	if not await hold(4.0, own): return
	pov(.2, .5, 1.0)
	say("РИЧАРД: Под самым куполом, без страховки, несравненная Эльза!")
	if not await hold(1.16, own): return
	drum_roll() # 2.2 s: ends on Elsa's far apex, 1.56 s into her shot
	if not await hold(.64, own): return
	cut_in()
	shot(Vector3(3.2, 5.6, 8.2), Vector3(4.5, 8.4, 3.5), Vector3(-.9, .5, -.7), 3.6)
	elsa_act(3.6)
	act_end("elsa", 3.6)
	if not await hold(3.6, own): return
	pov(-.45, .05, .6)
	lights_up()
	say("РИЧАРД: Сильнейший человек на свете! Бруно!")
	if not await hold(.8, own): return
	drum_roll() # ends as the weight locks out, 1.4 s into the shot
	if not await hold(.8, own): return
	cut_in()
	var bruno_view := Vector3(-1.0, 1.15, 6.9)
	shot(bruno_view, Vector3(-3.2, 2.1, 2.6), Vector3(.35, .05, -.45), 4.2)
	bruno_act(bruno_view)
	act_end("bruno", 4.2)
	if not await hold(4.2, own): return
	pov(0.0, -.08, .6)
	lights_up()
	say("РИЧАРД: Малышка Лили и волшебный сундук!")
	if not await hold(1.6, own): return
	cut_in()
	var lili_view := Vector3(2.6, 1.5, 3.4)
	shot(lili_view, game.layout.TRUNK + Vector3(-.5, .7, .4), Vector3(.4, .2, .5), 3.4)
	lili_act(lili_view)
	act_end("lili", 3.4)
	if not await hold(3.4, own): return
	pov(.5, .02, .6)
	lights_up()
	say("РИЧАРД: И, конечно, наш Мордекай!")
	if not await hold(1.5, own): return
	cut_in()
	shot(Vector3(6.4, 1.7, 2.6), Vector3(4.2, 1.6, -1.2), Vector3(-.6, 0, -.4), 3.0)
	mordecai_act()
	act_end("mordecai", 3.0)
	if not await hold(3.0, own): return
	# The ring is empty now: only the ringmaster is left in the light.
	pov(0.0, .02, .9)
	lights_up()
	raise_cane()
	say("РИЧАРД: Ваш ведущий, Ричард. Спасибо, что были с нами все эти годы!")
	cheer(1.6, -35.0)
	if not await hold(3.2, own): return
	# The old print fades back to the present as the scene hands over.
	var out := create_tween().set_parallel(true)
	out.tween_property(caption, "modulate:a", 0.0, .5)
	out.tween_method(func(v: float): sepia.material.set_shader_parameter("amount", v), 1.0, 0.0, .9)
	motion.append(out)
	if is_instance_valid(game.audio): game.audio.opening_crowd(0.0, 1.5)
	await hold(.9, own)
