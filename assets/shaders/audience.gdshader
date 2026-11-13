shader_type spatial;
render_mode cull_back;
// One mesh per spectator. UV.x holds the body part id; INSTANCE_CUSTOM
// picks coat (r), skin (g) and hair (b) from the palettes and stretches the torso (a).
// Palettes are sRGB colours converted like StandardMaterial3D albedo (source_color).
// Separate uniforms, not arrays: vec3 uniform arrays arrive empty in Compatibility.
uniform vec3 coat0 : source_color; uniform vec3 coat1 : source_color; uniform vec3 coat2 : source_color; uniform vec3 coat3 : source_color; uniform vec3 coat4 : source_color;
uniform vec3 skin0 : source_color; uniform vec3 skin1 : source_color; uniform vec3 skin2 : source_color;
uniform vec3 hair0 : source_color; uniform vec3 hair1 : source_color; uniform vec3 hair2 : source_color;
uniform vec3 trousers : source_color;
uniform vec3 shoes : source_color;
varying vec3 tint;
vec3 pick3(float index, vec3 a, vec3 b, vec3 c) {
	return index < 0.5 ? a : (index < 1.5 ? b : c);
}
void vertex() {
	int part = int(UV.x + 0.5);
	if (part == 0) {
		VERTEX.y = 0.38 + (VERTEX.y - 0.38) * INSTANCE_CUSTOM.a;
	}
	float coat = INSTANCE_CUSTOM.r;
	if (part <= 1) {
		tint = coat < 2.5 ? pick3(coat, coat0, coat1, coat2) : (coat < 3.5 ? coat3 : coat4);
	} else if (part == 2) {
		tint = pick3(INSTANCE_CUSTOM.g, skin0, skin1, skin2);
	} else if (part == 3) {
		tint = pick3(INSTANCE_CUSTOM.b, hair0, hair1, hair2);
	} else if (part == 4) {
		tint = trousers;
	} else {
		tint = shoes;
	}
}
void fragment() {
	ALBEDO = tint;
	ROUGHNESS = 0.86;
}
