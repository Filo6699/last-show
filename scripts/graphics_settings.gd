extends Node
## Player-facing picture options. Presets only bundle the individual options;
## changing any of them by hand turns the preset into "custom".
signal changed
const PRESETS := {
	"low": {"aa": 0, "scale": .75, "shadows": 0},
	"medium": {"aa": 2, "scale": 1.0, "shadows": 1},
	"high": {"aa": 2, "scale": 1.0, "shadows": 2}}
# On a Mali-G615 MSAA 2x alone took the opening from 27 to 40 ms per frame
# (tile GPUs resolve it through memory), so phone presets render without it.
# Players can still pick MSAA by hand.
const MOBILE_PRESETS := {
	"low": {"aa": 0, "scale": .75, "shadows": 0},
	"medium": {"aa": 0, "scale": 1.0, "shadows": 1},
	"high": {"aa": 0, "scale": 1.0, "shadows": 2}}
# Off, FXAA (post-process, cheap), MSAA 2×, MSAA 4×.
const AA_MSAA := [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X]
const SCALES := [.5, .7, .85, 1.0]
const FPS_LIMITS := [30, 60, 0]
# Shadows: off, the nearest key only (soft), the two nearest keys (smoother).
# Each shadowed light redraws every object it reaches, so the count matters far
# more than the filter.
const SHADOW_LIGHTS := [0, 1, 2]
const SHADOW_FILTERS := [RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM]
const SHADOW_ATLAS := [2048, 2048, 4096]
const MOBILE_SHADOW_ATLAS := [1024, 2048, 4096]
var game
var mobile := OS.has_feature("mobile")
# Phones limit 3D pixels to 1280×720; benchmarks can request the same budget.
var limit_budget := mobile
var preset := "medium"
var aa := 2
var scale := 1.0
var shadows := 1
var fps_limit := 60
var show_fps := false
var fps_label: Label
# Atmosphere sits outside the quality presets: grain and darkness are mood,
# haze rescales each environment's fog from its authored distances.
var grain := 1
var darkness := 0
var haze := 1
var veil: ColorRect
const GRAIN_AMOUNT := [0.0, 0.075, 0.16]
const DARKNESS_AMOUNT := [0.0, 0.24, 0.42]
const VIGNETTE_AMOUNT := [0.0, 0.34, 0.55]
# Fog start/end multipliers for off, as authored, thick.
const HAZE_NEAR := [1.0, 1.0, 0.42]
const HAZE_FAR := [1.0, 1.0, 0.58]
var fxaa_layer: CanvasLayer
var fps_clock := 0.0

func setup(owner_game) -> void:
	game = owner_game
	# MSAA costs fill rate; start at 2× everywhere and let players raise it.
	var defaults: Dictionary = presets()["medium"]
	preset = "medium"
	aa = defaults.aa; scale = defaults.scale; shadows = defaults.shadows
	get_window().size_changed.connect(apply_scale)
	# Below the outline (layer 0) and the HUD, so only the 3D picture is filtered.
	fxaa_layer = CanvasLayer.new()
	fxaa_layer.layer = -1
	add_child(fxaa_layer)
	var filter := ColorRect.new()
	filter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	filter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/shaders/fxaa.gdshader")
	filter.material = material
	fxaa_layer.add_child(filter)
	veil = ColorRect.new()
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.material = ShaderMaterial.new()
	veil.material.shader = preload("res://assets/shaders/atmosphere.gdshader")
	fxaa_layer.add_child(veil)
	fxaa_layer.visible = false
	fps_label = Label.new()
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fps_label.position = Vector2(24, 56)
	fps_label.add_theme_font_size_override("font_size", 17)
	fps_label.add_theme_color_override("font_color", Color("c9b99e"))
	fps_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	fps_label.add_theme_constant_override("shadow_offset_y", 1)
	game.hud.root.add_child(fps_label)
	fps_label.hide()

func to_dict() -> Dictionary:
	return {"preset": preset, "aa": aa, "scale": scale, "shadows": shadows, "fps_limit": fps_limit, "show_fps": show_fps, "grain": grain, "darkness": darkness, "haze": haze}

func load_dict(values: Dictionary) -> void:
	preset = String(values.get("preset", preset))
	if not preset in PRESETS and preset != "custom": preset = "custom"
	aa = clampi(int(values.get("aa", aa)), 0, AA_MSAA.size() - 1)
	scale = clampf(float(values.get("scale", scale)), SCALES[0], 1.0)
	shadows = clampi(int(values.get("shadows", shadows)), 0, SHADOW_ATLAS.size() - 1)
	fps_limit = int(values.get("fps_limit", fps_limit))
	if not fps_limit in FPS_LIMITS: fps_limit = 60
	show_fps = bool(values.get("show_fps", show_fps))
	grain = clampi(int(values.get("grain", grain)), 0, 2)
	darkness = clampi(int(values.get("darkness", darkness)), 0, 2)
	haze = clampi(int(values.get("haze", haze)), 0, 2)
	# A named preset follows the current table, so saves made before the phone
	# presets dropped MSAA pick up the change.
	if preset != "custom":
		var table := presets()
		aa = table[preset].aa; scale = table[preset].scale; shadows = table[preset].shadows
	apply()

func set_preset(id: String) -> void:
	var table := presets()
	if not table.has(id): return
	preset = id
	aa = table[id].aa; scale = table[id].scale; shadows = table[id].shadows
	apply()

func set_option(option: String, value) -> void:
	set(option, value)
	if option in ["aa", "scale", "shadows"]:
		preset = "custom"
		var table := presets()
		for id in table:
			if table[id].aa == aa and is_equal_approx(table[id].scale, scale) and table[id].shadows == shadows: preset = id
	apply()

func apply() -> void:
	var view := get_viewport()
	view.msaa_3d = AA_MSAA[aa]
	# The reflection is part of the picture, so it gets the same edge smoothing.
	if is_instance_valid(game) and is_instance_valid(game.mirror_system):
		for mirror in game.mirror_system.mirrors: mirror.viewport.msaa_3d = AA_MSAA[aa]
	RenderingServer.positional_soft_shadow_filter_set_quality(SHADOW_FILTERS[shadows])
	view.positional_shadow_atlas_size = (MOBILE_SHADOW_ATLAS if mobile else SHADOW_ATLAS)[shadows]
	Engine.max_fps = fps_limit
	fps_label.visible = show_fps
	veil.material.set_shader_parameter("grain", GRAIN_AMOUNT[grain])
	veil.material.set_shader_parameter("darkness", DARKNESS_AMOUNT[darkness])
	veil.material.set_shader_parameter("vignette", VIGNETTE_AMOUNT[darkness])
	apply_scale()
	changed.emit()

func presets() -> Dictionary:
	return MOBILE_PRESETS if mobile else PRESETS

func shadow_light_count() -> int:
	return SHADOW_LIGHTS[shadows]

func apply_scale() -> void:
	# Phones keep their 3D work within a 1280×720 budget; dialogue, touch UI and
	# the outline stay at native display resolution.
	var budget := 1.0
	if limit_budget:
		var pixels := Vector2(get_window().size)
		budget = minf(1.0, minf(1280.0 / maxf(1.0, pixels.x), 720.0 / maxf(1.0, pixels.y)))
	var view := get_viewport()
	view.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	view.scaling_3d_scale = budget * scale

func _process(delta: float) -> void:
	var drawn := not get_viewport().disable_3d
	fxaa_layer.visible = drawn and (grain > 0 or darkness > 0)
	# The screen-texture FXAA rect rendered half the frame white on some GPUs; it stays off.
	fxaa_layer.get_child(0).visible = false
	veil.visible = grain > 0 or darkness > 0
	apply_haze()
	if not show_fps: return
	fps_clock += delta
	if fps_clock < .5: return
	fps_clock = 0.0
	fps_label.text = "%d FPS" % Engine.get_frames_per_second()

# Scenes swap whole Environment resources, so each one is rescaled the first
# time the camera shows it, and again whenever the haze option changes.
func apply_haze() -> void:
	if not is_instance_valid(game) or not is_instance_valid(game.player): return
	var env: Environment = game.player.camera.environment
	if env == null: env = game.get_node("World/WorldEnvironment").environment
	if env == null or env.get_meta("haze_applied", -1) == haze: return
	if not env.has_meta("haze_base"):
		env.set_meta("haze_base", [env.fog_enabled, env.fog_depth_begin, env.fog_depth_end])
	var base: Array = env.get_meta("haze_base")
	env.set_meta("haze_applied", haze)
	if not base[0]: return
	env.fog_enabled = haze > 0
	env.fog_depth_begin = base[1] * HAZE_NEAR[haze]
	env.fog_depth_end = base[2] * HAZE_FAR[haze]
