extends Node
## On-device performance probe, the main scene of the "perf" export only.
## Runs the real game through fixed views and variants that separate the
## bottlenecks, then shows a copyable report:
## v5: light tiles and narrowed fill lamps against the v4 state, per preset.
## "прочее" is frame time minus render CPU time: scripts, physics, waiting.
var game
var label: Label
var copy_button: Button
var report := ""
var lines: Array[String] = []
const WARMUP := 60
const SAMPLES := 180
const TOTAL := 8

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

func measure(tag: String, phase: String, at: Vector3, facing: Vector3) -> void:
	status("Замер: %s\n%d из %d\nНе трогайте экран." % [tag, lines.size() + 1, TOTAL])
	stage(phase, at, facing)
	var rid := get_viewport().get_viewport_rid()
	for i in WARMUP:
		game.place_player(at, facing); await frame()
	var frames: Array = []; var cpu: Array = []; var gpu: Array = []
	var previous := Time.get_ticks_usec()
	for i in SAMPLES:
		game.place_player(at, facing)
		await frame()
		var now := Time.get_ticks_usec()
		frames.append((now - previous) / 1000.0); previous = now
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
	var ms := median(frames)
	var gpu_ms := median(gpu)
	lines.append("%-22s %5.1f fps | кадр %5.1f p95 %5.1f | cpu-рендер %5.1f | gpu %s | прочее %4.1f | вызовы %4d | треуг %6dk" % [
		tag, 1000.0 / ms, ms, percentile(frames, .95), median(cpu),
		("%5.1f" % gpu_ms) if gpu_ms > .01 else "  н/д", maxf(0.0, ms - median(cpu)),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000)])

func lights(on: bool) -> void:  # unused in v5, kept for quick probes
	for light in game.find_children("*", "Light3D", true, false):
		if light is DirectionalLight3D: continue
		RenderingServer.instance_set_visible(light.get_instance(), on and light.is_visible_in_tree())

# v5 compares the light tiles and the narrowed fill lamps with the v4 state.
func tiles(on: bool) -> void:
	for node in game.world.find_children("*", "MeshInstance3D", true, false):
		if node.has_meta("light_tile"): node.visible = on
		elif node.has_meta("light_tiled"): node.layers = 0 if on else int(node.get_meta("light_tiled"))

const OLD_RANGES := {"Practical0": 38.0, "RingAmber": 38.0, "RingIvory": 38.0, "RingCoolRim": 50.0, "GalleryEast": 56.0, "GalleryWest": 56.0, "EntranceBlue": 38.0, "CurtainUplight": 32.0}
var new_ranges := {}
func fills(new: bool) -> void:
	for light in game.find_children("*", "Light3D", true, false):
		if not OLD_RANGES.has(String(light.name)): continue
		if not new_ranges.has(light.name): new_ranges[light.name] = light.spot_range if light is SpotLight3D else light.omni_range
		var reach: float = new_ranges[light.name] if new else OLD_RANGES[String(light.name)]
		if light is SpotLight3D: light.spot_range = reach
		else: light.omni_range = reach
	var env: Environment = game.get_node("World/WorldEnvironment").environment
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY if new else Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = .27 if new else .24

func run() -> void:
	status("Загрузка игры…")
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	game = load("res://scenes/main.tscn").instantiate()
	game.save_path = "user://device-benchmark-save.json"
	get_tree().root.add_child.call_deferred(game)
	await get_tree().process_frame
	for i in 30: await frame()
	var slicer := get_tree().root.find_child("LightTiles", true, false)
	while slicer and (not slicer.done or slicer.task >= 0 or not slicer.jobs.is_empty()): await frame()
	for i in 10: await frame()
	if game.graphics.changed.is_connected(game.save_settings): game.graphics.changed.disconnect(game.save_settings)
	game.graphics.fps_limit = 0; game.graphics.show_fps = false
	var layout = game.layout
	var opening := [Vector3(0, .36, -5.8), Vector3(0, 1.35, 6.6), "intro"]
	var mordecai := [Vector3(-12, .05, 26), layout.ARENA_MORDECAI, "news"]
	# [tag, view, preset, tiles, new fills]
	var runs := [
		["начало high v4", opening, "high", false, false],
		["начало high плитки", opening, "high", true, false],
		["начало high плитки+залив", opening, "high", true, true],
		["начало medium новое", opening, "medium", true, true],
		["начало low новое", opening, "low", true, true],
		["Мордекай high v4", mordecai, "high", false, false],
		["Мордекай high новое", mordecai, "high", true, true],
		["начало high v4 повтор", opening, "high", false, false],
	]
	for entry in runs:
		game.graphics.set_preset(entry[2]); game.graphics.fps_limit = 0; game.graphics.apply()
		tiles(entry[3]); fills(entry[4])
		var view: Array = entry[1]
		await measure(entry[0], view[2], view[0], view[1])
	tiles(true); fills(true)
	var culling := get_tree().root.find_child("ZoneCulling", true, false)
	var header := "Last Show perf v5 | %s | %s | %s | экран %s | 3D %.2f | зональное отсечение: %s" % [
		OS.get_model_name(), RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_method(),
		str(DisplayServer.window_get_size()), get_viewport().scaling_3d_scale, "да" if culling else "нет"]
	report = header + "\n" + "\n".join(lines)
	var file := FileAccess.open("user://device-benchmark.txt", FileAccess.WRITE)
	if file: file.store_string(report); file.close()
	game.process_mode = Node.PROCESS_MODE_DISABLED
	get_viewport().disable_3d = true
	for child in get_children():
		if child is CanvasLayer: child.get_node("Backdrop").show()
	label.add_theme_font_size_override("font_size", 17)
	status("Готово. Нажмите кнопку и вставьте текст в чат.\n\n" + report)
	copy_button.show()
	print(report)
	# Desktop smoke runs: godot res://scenes/device_benchmark.tscn -- --quit
	if "--quit" in OS.get_cmdline_user_args(): get_tree().quit()
