shader_type canvas_item;
render_mode unshaded;
uniform sampler2D silhouette : filter_linear, repeat_disable;
uniform vec4 mask_rect = vec4(0.0, 0.0, 1.0, 1.0);
void fragment() {
	vec2 mask_uv = mask_rect.xy + UV * mask_rect.zw;
	vec2 pixel = 1.0 / vec2(textureSize(silhouette, 0));
	float center = texture(silhouette, mask_uv).a;
	float edge = 0.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			edge = max(edge, texture(silhouette, mask_uv + vec2(float(x), float(y)) * pixel * 1.5).a);
		}
	}
	COLOR = vec4(1.0, 1.0, 1.0, max(0.0, edge - center));
}
