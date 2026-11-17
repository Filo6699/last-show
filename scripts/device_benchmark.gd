extends Node
## On-device performance probe, the main scene of the "perf" build only
## (scenes/device_benchmark.tscn is excluded from every normal export).
## v8 is a frame-cost diagnosis, not just an fps table. For each view it measures
## the base frame, then switches one piece of work off at a time and records how
## many milliseconds the frame loses. The phone gives no GPU timer, so the cost
## of a piece is read as the drop in frame time when it is gone.
## Every line is appended to user://device-benchmark.txt as soon as it is
## measured, so a run cut short still leaves its results.
var game
var label: Label
var copy_button: Button
var report := ""
var lines: Array[String] = []
var WARMUP := 40
var SAMPLES := 120
const VERSION := "perf v8 diag"
var out_path := "user://device-benchmark.txt"
var base_scale := 1.0
var started_ms := 0

func _ready() -> void:
	var layer := CanvasLayer.new(); layer.layer = 100; add_child(layer)
	var panel := ColorRect.new(); panel.color = Color(0, 0, 0, .78)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(panel); panel.hide(); panel.name = "Backdrop"
	label = Label.new(); label.position = Vector2(24, 24)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(label)
	copy_button = Button.new(); copy_button.text = "Скопировать результат"
	copy_button.add_theme_font_size_override("font_size", 34)
	copy_button.custom_minimum_size = Vector2(560, 110)
	copy_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	copy_button.position -= Vector2(40, 40)
	copy_button.hide(); layer.add_child(copy_button)
	copy_button.pressed.connect(func():
		DisplayServer.clipboard_set(report)
		copy_button.text = "Скопировано ✓")
	run.call_deferred()

func status(text: String) -> void:
	label.text = text

func emit(line: String) -> void:
	lines.append(line)
	print("DIAG ", line)
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file: file.store_string("\n".join(lines)); file.close()

func frame() -> void:
	if is_instance_valid(game):
		game.hud.menu.hide(); game.hud.story_backdrop.hide(); game.hud.fade.hide()
		game.hud.close_dialog()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

func median(values: Array) -> float:
	var sorted := values.duplicate(); sorted.sort()
	return float(sorted[sorted.size() / 2])

func percentile(values: Array, fraction: float) -> float:
	var sorted := values.duplicate(); sorted.sort()
	return float(sorted[clampi(int(ceil(fraction * sorted.size())) - 1, 0, sorted.size() - 1)])

func stage(phase: String, at: Vector3, facing: Vector3) -> void:
	game.stop_effects(); game.sequence_id = ""; game.node_id = ""; game.phase = phase
	game.flags = {"reflection_restored": true, "dressing_open": true, "service_open": true}
	game.hud.hide_menu(); game.hud.close_dialog(); game.hud.set_story_mode("")
	game.player.set_locked(false); game.update_staging(); game.place_player(at, facing)

func set_scale(mult: float) -> void:
	get_viewport().scaling_3d_scale = base_scale * mult

# Measures the current state. Returns the median frame in ms.
func sample(tag: String, view: Array, base_ms: float, count := -1) -> float:
	if count < 0: count = SAMPLES
	var rid := get_viewport().get_viewport_rid()
	for i in WARMUP:
		game.place_player(view[0], view[1]); await frame()
	var frames: Array = []; var cpu: Array = []; var proc: Array = []; var phys: Array = []
	var calls: Array = []; var tris: Array = []; var objs: Array = []
	var previous := Time.get_ticks_usec()
	for i in count:
		game.place_player(view[0], view[1])
		await frame()
		var now := Time.get_ticks_usec()
		frames.append((now - previous) / 1000.0); previous = now
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
		proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		tris.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		objs.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var ms := median(frames)
	var delta := "" if base_ms <= 0.0 else ("%+6.1f" % (ms - base_ms))
	emit("%-34s %5.1f fps | кадр %5.1f %s p95 %5.1f | рендер-cpu %4.1f скрипты %4.1f физика %4.1f | вызовы %4d объекты %4d треуг %4dk | 3D %3d%%" % [
		tag, 1000.0 / ms, ms, delta, percentile(frames, .95), median(cpu), median(proc), median(phys),
		int(median(calls)), int(median(objs)), int(median(tris) / 1000.0), roundi(get_viewport().scaling_3d_scale * 100.0)])
	return ms

func lights_where(test: Callable) -> Array:
	var found: Array = []
	for light in game.find_children("*", "Light3D", true, false):
		if light is DirectionalLight3D or not light.visible: continue
		if test.call(light): found.append(light)
	return found

func reach(light: Light3D) -> float:
	return light.spot_range if light is SpotLight3D else light.omni_range

func hide_all(nodes: Array) -> Callable:
	var hidden: Array = []
	for n in nodes:
		if is_instance_valid(n) and n.visible: n.visible = false; hidden.append(n)
	return func():
		for n in hidden: if is_instance_valid(n): n.visible = true

func culling() -> Node:
	for child in game.get_children():
		if child.get_script() == preload("res://scripts/render_culling.gd"): return child
	return null

func outline_node() -> Node:
	for child in game.get_children():
		if child.get_script() == preload("res://scripts/focus_outline.gd"): return child
	return null

func actor_meshes() -> Array:
	var found: Array = []
	for id in game.actors:
		var actor = game.actors[id]
		if is_instance_valid(actor) and actor.visible: found.append(actor)
	return found

func static_geometry() -> Array:
	# Everything drawn in the world that is not a character, a light or the player.
	var actors := actor_meshes()
	var found: Array = []
	for n in game.world.find_children("*", "GeometryInstance3D", true, false):
		if not n.visible: continue
		var inside_actor := false
		for a in actors:
			if a.is_ancestor_of(n): inside_actor = true; break
		if not inside_actor: found.append(n)
	return found

# Each entry switches one piece off and returns a callable that restores it.
func ablations() -> Array:
	var env: Environment = game.get_node("World/WorldEnvironment").environment
	var graphics = game.graphics
	var eye: Vector3 = game.player.camera.global_position
	return [
		["3D 70% пикселей", func(): set_scale(sqrt(.7)); return func(): set_scale(1.0)],
		["3D 50% пикселей", func(): set_scale(sqrt(.5)); return func(): set_scale(1.0)],
		["3D 25% пикселей", func(): set_scale(.5); return func(): set_scale(1.0)],
		["тени 1 вместо 2", func():
			var was: int = graphics.shadows; graphics.shadows = 1; graphics.apply(); culling().update_shadows(true)
			return func(): graphics.shadows = was; graphics.apply(); culling().update_shadows(true)],
		["тени 0", func():
			var was: int = graphics.shadows; graphics.shadows = 0; graphics.apply(); culling().update_shadows(true)
			return func(): graphics.shadows = was; graphics.apply(); culling().update_shadows(true)],
		["все точечные/прожекторы выкл", func(): return hide_all(lights_where(func(l): return true))],
		["омни без тени выкл", func(): return hide_all(lights_where(func(l): return l is OmniLight3D and not l.shadow_enabled))],
		["прожекторы без тени выкл", func(): return hide_all(lights_where(func(l): return l is SpotLight3D and not l.shadow_enabled))],
		["свет с радиусом >=15 м без тени выкл", func(): return hide_all(lights_where(func(l): return reach(l) >= 15.0 and not l.shadow_enabled))],
		["свет дальше радиуса от камеры выкл", func(): return hide_all(lights_where(func(l): return l.global_position.distance_to(eye) > reach(l) and not l.shadow_enabled))],
		["туман выкл", func():
			var was := env.fog_enabled; env.fog_enabled = false
			return func(): env.fog_enabled = was],
		["цветокоррекция выкл", func():
			var was := env.adjustment_enabled; env.adjustment_enabled = false
			return func(): env.adjustment_enabled = was],
		["вуаль/зерно выкл", func():
			graphics.process_mode = Node.PROCESS_MODE_DISABLED; graphics.fxaa_layer.visible = false
			return func(): graphics.process_mode = Node.PROCESS_MODE_INHERIT],
		["обводка выкл", func():
			var o := outline_node()
			if o == null: return func(): pass
			var was: int = o.process_mode; o.process_mode = Node.PROCESS_MODE_DISABLED
			var hidden: Array = []
			for c in o.find_children("*", "CanvasItem", true, false):
				if c.visible: c.visible = false; hidden.append(c)
			var vps: Array = []
			for v in o.find_children("*", "SubViewport", true, false):
				vps.append([v, v.render_target_update_mode]); v.render_target_update_mode = SubViewport.UPDATE_DISABLED
			return func():
				o.process_mode = was
				for c in hidden: c.visible = true
				for p in vps: p[0].render_target_update_mode = p[1]],
		["зеркала выкл", func():
			var vps: Array = []
			if game.mirror_system:
				for m in game.mirror_system.mirrors:
					vps.append([m.viewport, m.viewport.render_target_update_mode]); m.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			return func():
				for p in vps: p[0].render_target_update_mode = p[1]],
		["персонажи скрыты", func(): return hide_all(actor_meshes())],
		["статика скрыта (только персонажи)", func(): return hide_all(static_geometry())],
		["дальность камеры 25 м", func():
			var cam: Camera3D = game.player.camera; var was := cam.far; cam.far = 25.0
			return func(): cam.far = was],
		["скрипты игры на паузе", func():
			var was: int = game.process_mode; game.process_mode = Node.PROCESS_MODE_DISABLED
			return func(): game.process_mode = was],
		["3D выкл (только UI)", func():
			get_viewport().disable_3d = true
			culling().process_mode = Node.PROCESS_MODE_DISABLED
			return func(): culling().process_mode = Node.PROCESS_MODE_INHERIT; get_viewport().disable_3d = false],
	]

func diagnose(tag: String, view: Array) -> void:
	stage(view[2], view[0], view[1])
	for i in 30: game.place_player(view[0], view[1]); await frame()
	var base := await sample("%s: база" % tag, view, 0.0)
	var list := ablations()
	for i in list.size():
		var entry: Array = list[i]
		status("Диагностика: %s\n%s (%d из %d)\n%d мин. Не трогайте экран." % [tag, entry[0], i + 1, list.size(), (Time.get_ticks_msec() - started_ms) / 60000])
		var restore: Callable = entry[1].call()
		await sample("  " + entry[0], view, base)
		restore.call()
		for f in 10: game.place_player(view[0], view[1]); await frame()
	await sample("%s: база повтор" % tag, view, base)

# Opening only: one light at a time, so a single expensive light shows up.
func per_light(view: Array) -> void:
	stage(view[2], view[0], view[1])
	for i in 30: game.place_player(view[0], view[1]); await frame()
	var eye: Vector3 = view[0]
	var near := lights_where(func(l): return l.global_position.distance_to(eye) < reach(l) + 40.0)
	var base := await sample("начало: база (по одному свету)", view, 0.0, 90)
	var costs: Array = []
	for i in near.size():
		var light: Light3D = near[i]
		status("Свет по одному: %d из %d" % [i + 1, near.size()])
		light.visible = false
		for f in 6: await frame()
		var frames: Array = []
		var previous := Time.get_ticks_usec()
		for s in mini(60, SAMPLES):
			game.place_player(view[0], view[1]); await frame()
			var now := Time.get_ticks_usec(); frames.append((now - previous) / 1000.0); previous = now
		light.visible = true
		costs.append([base - median(frames), light])
	costs.sort_custom(func(a, b): return a[0] > b[0])
	for c in costs.slice(0, 15):
		var l: Light3D = c[1]
		emit("  свет %-28s %-6s тень=%s радиус %4.1f  экономия %+5.1f мс" % [
			String(l.name).left(28), "spot" if l is SpotLight3D else "omni", "да" if l.shadow_enabled else "нет", reach(l), c[0]])


# ---------- Variant mode ----------
# user://variant.json switches the build from diagnosis to an A/B sweep:
# {"runs": [{"tag": "base", "tweaks": {}}, {"tag": "fade", "tweaks": {"light_fade": [30, 10]}}],
#  "stops": [0, 1, ...] (indices into TOUR, default all), "yaws": 4, "samples": 60, "shots": true}
# Each run applies its tweaks, measures every stop and yaw, saves a screenshot per
# view to user://shots/<tag>_<stop>_<yaw>.png, then restores the tweaks.
const TOUR := [
	["начало", Vector3(0, .36, -5.8), Vector3(0, 1.35, 6.6), "intro"],
	["арена", Vector3(-8, .05, 18), Vector3(-8, 1.6, 30), "news"],
	["Мордекай", Vector3(-12, .05, 26), Vector3(-12, 1.25, 29), "news"],
	["гримёрка", Vector3(-46, .05, 33.6), Vector3(-46.7, 1.45, 31.45), "elsa_dressing"],
	["коридор", Vector3(-20, .05, 40), Vector3(-20, 1.6, 50), "to_technical"],
	["клиника", Vector3(-19.6, .05, 57), Vector3(-16.75, 1.6, 57), "photos"],
	["крыша", Vector3(-10, 40.02, -18), Vector3(-7.85, 41.05, -10), "roof"],
	["дом", Vector3(155, .05, 1.8), Vector3(151.9, .95, 2.6), "home"],
	["проход", Vector3(-30, .05, 36.5), Vector3(-40, 1.6, 34.5), "elsa_dressing"],
	["закулисье", Vector3(-8, .05, 30), Vector3(-8, 1.6, 40), "news"],
]

func tweak(key: String, value) -> Callable:
	var env: Environment = game.get_node("World/WorldEnvironment").environment
	var graphics = game.graphics
	match key:
		"scale":
			set_scale(float(value)); return func(): set_scale(1.0)
		"shadows":
			var was: int = graphics.shadows; graphics.shadows = int(value); graphics.apply(); culling().update_shadows(true)
			return func(): graphics.shadows = was; graphics.apply(); culling().update_shadows(true)
		"far":
			var cam: Camera3D = game.player.camera; var was := cam.far; cam.far = float(value)
			return func(): cam.far = was
		"light_fade":
			# [begin, length]: unshadowed lights fade out with distance from the camera.
			var touched: Array = []
			for l in game.find_children("*", "Light3D", true, false):
				if l is DirectionalLight3D or l.shadow_enabled: continue
				touched.append([l, l.distance_fade_enabled, l.distance_fade_begin, l.distance_fade_length])
				l.distance_fade_enabled = true; l.distance_fade_begin = float(value[0]); l.distance_fade_length = float(value[1])
			return func():
				for t in touched:
					t[0].distance_fade_enabled = t[1]; t[0].distance_fade_begin = t[2]; t[0].distance_fade_length = t[3]
		"geo_range":
			# Geometry is not drawn beyond this distance (visibility range, per object).
			var touched: Array = []
			for g in game.world.find_children("*", "GeometryInstance3D", true, false):
				if g.visibility_range_end > 0.0: continue
				touched.append(g); g.visibility_range_end = float(value)
			return func():
				for g in touched: g.visibility_range_end = 0.0
		"specular_off", "lambert", "vertex":
			var touched: Array = []
			var seen := {}
			for g in game.world.find_children("*", "MeshInstance3D", true, false):
				var mats: Array = [g.material_override]
				if g.mesh:
					for i in g.mesh.get_surface_count(): mats.append(g.get_active_material(i))
				for m in mats:
					if not m is BaseMaterial3D or seen.has(m): continue
					seen[m] = true
					if m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED: continue
					if key == "specular_off":
						touched.append([m, "specular_mode", m.specular_mode]); m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
					elif key == "lambert":
						touched.append([m, "diffuse_mode", m.diffuse_mode]); m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
					else:
						touched.append([m, "shading_mode", m.shading_mode]); m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
			return func():
				for t in touched: t[0].set(t[1], t[2])
		"light_range":
			var touched: Array = []
			for l in game.find_children("*", "Light3D", true, false):
				if l is DirectionalLight3D: continue
				var prop := "spot_range" if l is SpotLight3D else "omni_range"
				touched.append([l, prop, l.get(prop)]); l.set(prop, l.get(prop) * float(value))
			return func():
				for t in touched: t[0].set(t[1], t[2])
		"fade_game":
			# What phones get at start-up (the benchmark loads the game outside "mobile" on desktop).
			var faded: Array = preload("res://scripts/light_split.gd").fade_far_lights(game)
			return func():
				for l in faded: l.distance_fade_enabled = false
		"nofade":
			var faded: Array = []
			for l in game.find_children("*", "Light3D", true, false):
				if l.distance_fade_enabled and not l.shadow_enabled: l.distance_fade_enabled = false; faded.append(l)
			return func():
				for l in faded: l.distance_fade_enabled = true
		"nosplit":
			var LS := preload("res://scripts/light_split.gd")
			var undone: Array = []
			for n in game.world.find_children("*", "MeshInstance3D", true, false):
				if is_instance_valid(n) and n.has_meta("light_split") and not n.get_parent().has_meta("light_split"):
					LS.undo(n); undone.append(n)
			return func(): LS.split_world(game.world)
		"split":
			var t0 := Time.get_ticks_msec()
			var cell := float(value[0]) if value is Array else float(value)
			var span := float(value[1]) if value is Array else 26.0
			var done: Array = preload("res://scripts/light_split.gd").split_world(game.world, cell, span)
			var total := 0
			for d in done: total += d[1]
			emit("нарезка: %d объектов → %d плиток за %d мс" % [done.size(), total, Time.get_ticks_msec() - t0])
			return func():
				for d in done: preload("res://scripts/light_split.gd").undo(d[0])
		"atlas":
			var vp := get_viewport(); var was := vp.positional_shadow_atlas_size
			vp.positional_shadow_atlas_size = int(value)
			return func(): vp.positional_shadow_atlas_size = was
		"filter":
			RenderingServer.positional_soft_shadow_filter_set_quality(int(value))
			return func(): game.graphics.apply()
		"fog_off":
			var was := env.fog_enabled; env.fog_enabled = false
			return func(): env.fog_enabled = was
		"adaptive":
			graphics.adaptive = true; graphics.dynamic_scale = 1.0
			return func(): graphics.adaptive = false; graphics.dynamic_scale = 1.0; graphics.apply_scale()
	emit("неизвестная правка " + key)
	return func(): pass

func sweep_view(tag: String, stop: Array, yaw_i: int, yaws: int, count: int, shot_name: String) -> Array:
	var at: Vector3 = stop[1]
	var dir: Vector3 = (stop[2] - at).rotated(Vector3.UP, TAU * yaw_i / yaws)
	var view := [at, at + dir, stop[3]]
	if game.phase != stop[3]: stage(stop[3], at, at + dir)
	for i in 25: game.place_player(view[0], view[1]); await frame()
	var frames: Array = []
	var previous := Time.get_ticks_usec()
	for i in count:
		game.place_player(view[0], view[1]); await frame()
		var now := Time.get_ticks_usec(); frames.append((now - previous) / 1000.0); previous = now
	var calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	if shot_name != "":
		# Grain is animated noise; without it two shots of the same view match.
		var veil: ShaderMaterial = game.graphics.veil.material
		var grain = veil.get_shader_parameter("grain")
		veil.set_shader_parameter("grain", 0.0)
		label.hide(); game.place_player(view[0], view[1]); await frame(); await frame()
		var img := get_viewport().get_texture().get_image()
		img.resize(img.get_width() / 2, img.get_height() / 2)
		img.save_png("user://shots/%s.png" % shot_name)
		label.show(); veil.set_shader_parameter("grain", grain)
	return [median(frames), percentile(frames, .95), calls]

func run_variants(config: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute("user://shots")
	var stops: Array = config.get("stops", range(TOUR.size()))
	var yaws := int(config.get("yaws", 4))
	var count := int(config.get("samples", 60))
	var shots: bool = config.get("shots", true)
	for run in config.runs:
		var restores: Array = []
		for key in run.get("tweaks", {}):
			restores.append(tweak(key, run.tweaks[key]))
		if run.get("tweaks", {}).has("adaptive"):
			# Let the controller settle at the opening before the sweep.
			stage("intro", TOUR[0][1], TOUR[0][2])
			var t0 := Time.get_ticks_msec()
			while Time.get_ticks_msec() - t0 < 20000: await frame()
		var worst := 0.0; var total := 0.0; var n := 0; var parts: Array = []
		for s in stops:
			var stop: Array = TOUR[int(s)]
			var row: Array = []
			for y in yaws:
				status("Вариант %s\n%s, взгляд %d\n%d мин." % [run.tag, stop[0], y + 1, (Time.get_ticks_msec() - started_ms) / 60000])
				var r := await sweep_view(run.tag, stop, y, yaws, count, ("%s_%d_%d" % [run.tag, int(s), y]) if shots else "")
				row.append("%4.1f/%4.1f" % [r[0], r[1]])
				worst = maxf(worst, r[1]); total += r[0]; n += 1
			parts.append("%s %s" % [stop[0], " ".join(row)])
		emit("ВАРИАНТ %s | средний кадр %.1f мс | худший p95 %.1f мс | 3D %d%%" % [run.tag, total / n, worst, roundi(get_viewport().scaling_3d_scale * 100.0)])
		for p in parts: emit("  " + p)
		restores.reverse()
		for r in restores: r.call()

func run() -> void:
	started_ms = Time.get_ticks_msec()
	if "--quick" in OS.get_cmdline_user_args(): WARMUP = 2; SAMPLES = 4
	status("Загрузка игры…")
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = "user://device-benchmark-save.json"
	get_tree().root.add_child.call_deferred(game)
	await get_tree().process_frame
	for i in 30: await frame()
	if game.graphics.changed.is_connected(game.save_settings): game.graphics.changed.disconnect(game.save_settings)
	game.graphics.show_fps = false
	emit("Last Show %s | %s | %s | %s | экран %s | без ограничения fps" % [VERSION,
		OS.get_model_name(), RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_method(),
		str(DisplayServer.window_get_size())])
	var graphics = game.graphics
	graphics.set_preset("high")
	graphics.adaptive = false
	graphics.dynamic_scale = 1.0
	graphics.fps_limit = 0
	graphics.apply()
	Engine.max_fps = 0
	base_scale = get_viewport().scaling_3d_scale
	var layout = game.layout
	var views := [
		["начало", [Vector3(0, .36, -5.8), Vector3(0, 1.35, 6.6), "intro"]],
		["Мордекай", [Vector3(-12, .05, 26), layout.ARENA_MORDECAI, "news"]],
		["Зеркало", [Vector3(-46, .05, 33.6), layout.MIRROR, "elsa_dressing"]],
		["Клиника", [layout.CLINIC_CENTER + Vector3(.4, 0, 0), layout.PHOTOS, "photos"]],
	]
	var config_file := FileAccess.open("user://variant.json", FileAccess.READ)
	if config_file:
		var config = JSON.parse_string(config_file.get_as_text())
		emit("режим вариантов: " + JSON.stringify(config))
		await run_variants(config)
	else:
		for v in views:
			await diagnose(v[0], v[1])
		await per_light(views[0][1])
	emit("всего %.1f мин" % ((Time.get_ticks_msec() - started_ms) / 60000.0))
	report = "\n".join(lines)
	game.process_mode = Node.PROCESS_MODE_DISABLED
	get_viewport().disable_3d = true
	for child in get_children():
		if child is CanvasLayer: child.get_node("Backdrop").show()
	label.add_theme_font_size_override("font_size", 12)
	status("Готово.\n\n" + report)
	copy_button.show()
	print("DIAG_DONE")
	# Desktop smoke runs: godot res://scenes/device_benchmark.tscn -- --quit
	if "--quit" in OS.get_cmdline_user_args(): get_tree().quit()
