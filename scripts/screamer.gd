extends CanvasLayer
## Full-screen 2D jump scare. The face rushes at the camera with RGB split,
## frame tearing, film noise and a red pulse, then cuts to black.
## Shared by Lili's glimpses, the locker and the dark on the way to the roof.
signal finished

const SHADER := """
shader_type canvas_item;
uniform float split = 0.0;
uniform float tear = 0.0;
uniform float red = 0.0;
uniform float seed = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233)) + seed) * 43758.5453); }
void fragment() {
	vec2 uv = UV;
	float band = floor(uv.y * 26.0);
	uv.x += (hash(vec2(band, floor(TIME * 30.0))) - .5) * tear * step(.72, hash(vec2(band, seed)));
	vec4 c;
	c.r = texture(TEXTURE, uv + vec2(split, 0)).r;
	c.g = texture(TEXTURE, uv).g;
	c.b = texture(TEXTURE, uv - vec2(split, split * .4)).b;
	c.a = 1.0;
	float grain = hash(uv * 900.0 + TIME) - .5;
	c.rgb += grain * .22;
	c.rgb = mix(c.rgb, vec3(c.r * 1.4, c.g * .25, c.b * .2), red);
	float flick = step(.93, hash(vec2(floor(TIME * 24.0), seed)));
	c.rgb *= 1.0 - flick * .7;
	COLOR = c;
}
"""

var face: TextureRect
var black: ColorRect
var material := ShaderMaterial.new()
var tween: Tween
var playing := false

func _ready() -> void:
	layer = 45
	var shader := Shader.new()
	shader.code = SHADER
	material.shader = shader
	black = ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)
	face = TextureRect.new()
	face.texture = load("res://assets/ui/lili_scream.png")
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	face.material = material
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(face)
	visible = false

func _fit(scale_factor: float, jitter: Vector2) -> void:
	var vp := get_viewport().get_visible_rect().size
	var side := maxf(vp.x, vp.y) * scale_factor
	face.size = Vector2(side, side)
	face.position = (vp - face.size) * .5 + jitter

# Length stays under a second so it reads as a hit, not a slideshow.
func play(strength := 1.0) -> void:
	if tween and tween.is_valid(): tween.kill()
	playing = true
	visible = true
	black.color.a = 1.0
	face.modulate.a = 1.0
	face.show()
	material.set_shader_parameter("seed", randf() * 100.0)
	tween = create_tween()
	# A held breath of black, then the face slams in.
	tween.tween_interval(.07)
	tween.tween_method(func(t: float):
		var shake := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 40.0 * strength * (1.0 - t * .5)
		_fit(lerpf(.6, 1.12, ease(t, .35)), shake)
		material.set_shader_parameter("split", .006 * strength * (1.0 - t * .5))
		material.set_shader_parameter("tear", .05 * strength)
		material.set_shader_parameter("red", .3 * absf(sin(t * 18.0)) * strength), 0.0, 1.0, .62)
	tween.tween_callback(face.hide)
	tween.tween_property(black, "color:a", 0.0, .45)
	tween.tween_callback(func():
		visible = false
		playing = false
		finished.emit())
	if OS.has_feature("mobile"): Input.vibrate_handheld(400)

func stop() -> void:
	if tween and tween.is_valid(): tween.kill()
	visible = false
	playing = false
