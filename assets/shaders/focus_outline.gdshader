shader_type canvas_item;
render_mode unshaded;
uniform sampler2D silhouette : filter_linear, repeat_disable;
void fragment() {
	vec2 pixel = 1.0 / vec2(textureSize(silhouette, 0));
	float center = texture(silhouette, UV).a;
	float edge = 0.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			edge = max(edge, texture(silhouette, UV + vec2(float(x), float(y)) * pixel * 1.5).a);
		}
	}
	COLOR = vec4(1.0, 1.0, 1.0, max(0.0, edge - center));
}
