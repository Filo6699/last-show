shader_type spatial;
render_mode cull_disabled;
#include "res://assets/shaders/photo_wear.gdshaderinc"

uniform sampler2D photo : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 region = vec4(0.0, 0.0, 1.0, 1.0);
uniform float wear : hint_range(0.0, 1.0) = 1.0;
uniform float seed = 0.0;
uniform vec2 aspect = vec2(1.0, 1.0);
uniform vec3 tint : source_color = vec3(0.85, 0.83, 0.78);

void fragment() {
	vec4 c = photo_wear(photo, UV, region, wear, seed, aspect, tint);
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb;
	ROUGHNESS = 0.95;
}
