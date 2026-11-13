shader_type canvas_item;
#include "res://assets/shaders/photo_wear.gdshaderinc"

uniform sampler2D photo : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 region = vec4(0.0, 0.0, 1.0, 1.0);
uniform float wear : hint_range(0.0, 1.0) = 1.0;
uniform float seed = 0.0;
uniform vec2 aspect = vec2(1.0, 1.0);
uniform vec3 tint : source_color = vec3(1.0);

void fragment() {
	COLOR = photo_wear(photo, UV, region, wear, seed, aspect, tint);
}
