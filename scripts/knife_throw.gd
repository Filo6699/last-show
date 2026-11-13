extends "res://scripts/scene_parts.gd"
## Optional knife-throwing stand in the arena hall. Usable once Richard has the
## story knife. One finger: hold to steady the drifting reticle, release to
## throw. Three knives, then the score. A bullseye briefly puts Richard's own
## childhood face on the host's photo.
## Nothing here is saved: pause, load, main menu and new game close it.
signal closed(score: int)

const STAND := Vector3(-19.6, 0, 11.0)
const BOARD_SCALE := 1.25
const THROW_DISTANCE := 3.6
const THROWS := 3
# Board-local centre of the target face (the model faces +Z).
const FACE := Vector3(0, 1.38, .07)
const FACE_RADIUS := .38
const PORTRAIT_SURFACE := 5
const RICHARD_FACE := preload("res://assets/story/photos/richard_child_portrait.png")

var stand: Node3D
var station: StaticBody3D
var board_mesh: MeshInstance3D
var host_photo: Material
var richard_photo: StandardMaterial3D
var active := false
var holding := false
var flying := false
var hold_time := 0.0
var sway_time := 0.0
var aim := Vector2.ZERO
var throws_left := 0
var score := 0
var results: Array = []
var stuck: Array = []
var tweens: Array = []
var token := 0
var ui: CanvasLayer
var marks: Control
var status: Label
var caption: Label
var rng := RandomNumberGenerator.new()
var saved_fov := -1.0

func setup(owner_game) -> void:
	game = owner_game
	name = "KnifeThrow"
	set_meta("dynamic_set", true)
	stand = asset("dartboard_mordecai", STAND, 0.0, BOARD_SCALE, true)
	stand.name = "KnifeThrowBoard"
	var out := -Vector3(STAND.x, 0, STAND.z).normalized()
	stand.rotation.y = atan2(out.x, out.z)
	for mesh in stand.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh.get_surface_count() > PORTRAIT_SURFACE:
			board_mesh = mesh
			host_photo = mesh.mesh.surface_get_material(PORTRAIT_SURFACE)
	richard_photo = StandardMaterial3D.new()
	richard_photo.albedo_texture = RICHARD_FACE
	richard_photo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	richard_photo.albedo_color = Color(.85, .8, .78)
	station = target("knife_throw", stand.position + Vector3(0, 1.3, 0), Vector3(1.3, 2.4, 1.0), "Метнуть нож")
	station.rotation.y = stand.rotation.y
	station.set_meta("focus_range", 4.5)
	station.collision_layer = 0
	# A small work lamp so the board reads in the dim hall.
	point_light(board_center() + normal() * 1.2 + Vector3(0, .9, 0), "f0c890", .9, 4.5)
	rng.randomize()

func board_center() -> Vector3:
	return stand.global_transform * FACE if stand.is_inside_tree() else stand.transform * FACE

func normal() -> Vector3:
	return (stand.transform.basis * Vector3.BACK).normalized()

func board_axes() -> Array:
	var b: Basis = stand.transform.basis.orthonormalized()
	return [b.x, b.y]

func radius() -> float:
	return FACE_RADIUS * BOARD_SCALE

func throw_spot() -> Vector3:
	var at := STAND + normal() * THROW_DISTANCE
	return Vector3(at.x, .05, at.z)

func available() -> bool:
	return game.flags.get("knife", false) and game.room_at(game.player.position) == "arena"

func is_open() -> bool:
	return active

func _process(delta: float) -> void:
	if not game: return
	var layer := 16 if available() and not active else 0
	if station.collision_layer != layer: station.collision_layer = layer
	if not active: return
	if game.hud.menu.visible:
		close()
		return
	sway_time += delta
	if holding: hold_time += delta
	aim = sway(sway_time, hold_time if holding else -1.0)
	marks.queue_redraw()

# Wide lazy drift at rest; holding steadies it for about a second, then the
# arm tires and it widens again.
func sway(t: float, held: float) -> Vector2:
	var spread := .95
	if held >= 0:
		spread = lerpf(.95, .22, clampf(held / 1.0, 0, 1))
		if held > 1.6: spread = minf(1.1, .22 + (held - 1.6) * .6)
	var drift := Vector2(sin(t * 1.35) + .35 * sin(t * 3.1 + .7), sin(t * 1.9 + 1.2) + .3 * cos(t * 2.6))
	return drift / 1.35 * spread

func start() -> void:
	if active or not available() or game.player.locked: return
	token += 1
	active = true
	holding = false
	flying = false
	hold_time = 0
	sway_time = rng.randf() * 10
	throws_left = THROWS
	score = 0
	results.clear()
	clear_knives()
	game.place_player(throw_spot(), board_center())
	game.player.set_locked(true)
	# Narrow the view onto the board, like squinting along the blade.
	saved_fov = game.player.camera.fov
	track(create_tween()).tween_property(game.player.camera, "fov", 30.0, .35)
	game.hud.touch.hide()
	game.hud.crosshair.hide()
	game.hud.hint.hide()
	build_ui()
	refresh_status()

func build_ui() -> void:
	if is_instance_valid(ui): ui.queue_free()
	ui = CanvasLayer.new()
	ui.layer = 30
	add_child(ui)
	marks = Control.new()
	marks.set_anchors_preset(Control.PRESET_FULL_RECT)
	marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marks.draw.connect(draw_reticle)
	ui.add_child(marks)
	status = make_label(Control.PRESET_TOP_WIDE, 24, Color("e4d6bf"))
	status.offset_top = 22
	status.offset_bottom = 60
	caption = make_label(Control.PRESET_BOTTOM_WIDE, 21, Color("cdbf9f"))
	caption.offset_top = -140
	caption.offset_bottom = -80
	caption.text = "Держи палец, чтобы унять дрожь. Отпусти, чтобы метнуть."
	var back := Button.new()
	back.name = "BackButton"
	back.text = "Уйти"
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(200, 54)
	back.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	back.offset_left = -100
	back.offset_right = 100
	back.offset_top = -70
	back.offset_bottom = -16
	back.pressed.connect(close)
	ui.add_child(back)

func make_label(preset: int, size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.set_anchors_preset(preset)
	label.offset_left = 40
	label.offset_right = -40
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, .8))
	ui.add_child(label)
	return label

func refresh_status() -> void:
	if not is_instance_valid(status): return
	status.text = "Ножей: %d   Очки: %d" % [throws_left, score]

func aim_point(at: Vector2) -> Vector3:
	var axes := board_axes()
	return board_center() + (axes[0] * at.x + axes[1] * at.y) * radius()

func draw_reticle() -> void:
	if not active or flying or throws_left <= 0: return
	var camera: Camera3D = game.player.camera
	var p := camera.unproject_position(aim_point(aim))
	var edge := camera.unproject_position(aim_point(aim + Vector2(.12, 0)))
	var r := maxf(10.0, p.distance_to(edge))
	var color := Color(1, .86, .6, .95) if holding else Color(1, .95, .85, .7)
	marks.draw_arc(p, r, 0, TAU, 32, color, 2.0, true)
	for dir in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		marks.draw_line(p + dir * r * .45, p + dir * r * 1.5, color, 2.0, true)

func _input(event: InputEvent) -> void:
	if not active or flying or throws_left <= 0 or game.hud.menu.visible: return
	var press := false
	var release := false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if over_back(event.position): return
		press = event.pressed; release = not event.pressed
	elif event is InputEventScreenTouch:
		if over_back(event.position): return
		press = event.pressed; release = not event.pressed
	elif event is InputEventKey and not event.echo and event.keycode in [KEY_SPACE, KEY_E, KEY_ENTER]:
		press = event.pressed; release = not event.pressed
	else:
		return
	if press:
		holding = true
		hold_time = 0
	elif release and holding:
		holding = false
		throw_knife(aim)
	get_viewport().set_input_as_handled()

func over_back(at: Vector2) -> bool:
	var button: Control = ui.get_node_or_null("BackButton") if is_instance_valid(ui) else null
	return button != null and button.get_global_rect().has_point(at)

func points(distance: float) -> int:
	if distance <= .14: return 50
	if distance <= .42: return 25
	if distance <= .72: return 10
	if distance <= 1.0: return 5
	return 0

func throw_knife(at: Vector2) -> void:
	if not active or flying or throws_left <= 0: return
	flying = true
	holding = false
	var hit := at + Vector2(rng.randf_range(-.04, .04), rng.randf_range(-.04, .04))
	var value := points(hit.length())
	throws_left -= 1
	score += value
	results.append(value)
	var knife := make_knife()
	var camera: Camera3D = game.player.camera
	var cb := camera.global_basis
	knife.global_position = camera.global_position - cb.z * .5 + cb.x * .22 - cb.y * .18
	var goal := aim_point(hit)
	var n := normal()
	var miss := value == 0
	if miss: goal = goal - n * 4.0
	else: goal += n * .17
	knife.look_at(goal, Vector3.UP)
	var spin := knife.rotation
	var tween := track(create_tween())
	var flight := knife.global_position.distance_to(goal) / 14.0
	tween.tween_property(knife, "global_position", goal, flight)
	tween.parallel().tween_property(knife, "rotation:z", spin.z + TAU * 2, flight)
	var mine := token
	tween.tween_callback(func(): landed(knife, value, mine))

func landed(knife: Node3D, value: int, mine: int) -> void:
	if mine != token or not active: return
	if value == 0:
		knife.queue_free()
		stuck.erase(knife)
		game.audio.play("sfx_box_rustle_01", -14, knife.global_position)
		say("Мимо")
	else:
		# Stuck at a slight tilt, like a real throw.
		knife.rotation.z = rng.randf_range(-.4, .4)
		knife.rotate_object_local(Vector3.RIGHT, rng.randf_range(-.12, .12))
		var thunk = game.audio.play("sfx_box_bump_01", -3, knife.global_position)
		if thunk: thunk.pitch_scale = 1.45
		say("Яблочко! +50" if value == 50 else "+%d" % value)
		if value == 50: payoff(mine)
	flying = false
	refresh_status()
	if throws_left <= 0:
		var tween := track(create_tween())
		tween.tween_interval(1.0)
		tween.tween_callback(func():
			if mine == token and active: say("Итог: %d из %d" % [score, THROWS * 50]))
		tween.tween_interval(2.4)
		tween.tween_callback(func(): if mine == token: close())

func say(text: String) -> void:
	if is_instance_valid(caption): caption.text = text

# The host's photo turns into Richard's childhood face for a moment.
func payoff(mine: int) -> void:
	if not is_instance_valid(board_mesh): return
	board_mesh.set_surface_override_material(PORTRAIT_SURFACE, richard_photo)
	game.audio.play("sfx_whisper", -12)
	game.hud.show_notice("Это было моё лицо.")
	var tween := track(create_tween())
	tween.tween_interval(1.1)
	tween.tween_callback(func(): if mine == token: restore_photo())

func restore_photo() -> void:
	if is_instance_valid(board_mesh): board_mesh.set_surface_override_material(PORTRAIT_SURFACE, null)

func photo_swapped() -> bool:
	return is_instance_valid(board_mesh) and board_mesh.get_surface_override_material(PORTRAIT_SURFACE) == richard_photo

# Same colours as the story knife on the trunk: black grip, steel blade.
func make_knife() -> Node3D:
	var knife := Node3D.new()
	knife.name = "ThrownKnife"
	add_child(knife)
	var parts := [
		[Vector3(0, 0, .1), Vector3(.04, .03, .16), "1e1d22", 0.0],
		[Vector3(0, 0, -.1), Vector3(.04, .012, .2), "aeb2bc", .8],
		[Vector3(0, 0, .015), Vector3(.09, .028, .018), "8e9099", .8],
	]
	for part in parts:
		var mesh := BoxMesh.new()
		mesh.size = part[1]
		var obj := MeshInstance3D.new()
		obj.mesh = mesh
		obj.material_override = material(part[2], part[3])
		obj.position = part[0]
		obj.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		knife.add_child(obj)
	stuck.append(knife)
	return knife

func track(tween: Tween) -> Tween:
	tweens.append(tween)
	return tween

func clear_knives() -> void:
	for knife in stuck:
		if is_instance_valid(knife): knife.queue_free()
	stuck.clear()

func close() -> void:
	if not active: return
	token += 1
	active = false
	holding = false
	flying = false
	for tween in tweens:
		if tween and tween.is_valid(): tween.kill()
	tweens.clear()
	if saved_fov > 0: game.player.camera.fov = saved_fov
	saved_fov = -1.0
	restore_photo()
	clear_knives()
	if is_instance_valid(ui): ui.queue_free()
	ui = null
	var hud = game.hud
	game.player.set_locked(hud.menu.visible or not game.sequence_id.is_empty() or game.transitioning)
	hud.touch.visible = hud.touch_enabled and not hud.menu.visible and not hud.dialog.visible
	hud.crosshair.show()
	closed.emit(score)
