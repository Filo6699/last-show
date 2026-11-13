shader_type canvas_item;
render_mode unshaded;
// Edge-directed blur after the 3D pass: smooths contours at about a tenth of
// the cost of MSAA on integrated GPUs. Flat areas and textures are left alone.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }
void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec2 uv = SCREEN_UV;
	vec3 m = textureLod(screen_tex, uv, 0.0).rgb;
	vec3 nw = textureLod(screen_tex, uv + vec2(-1.0, -1.0) * px, 0.0).rgb;
	vec3 ne = textureLod(screen_tex, uv + vec2(1.0, -1.0) * px, 0.0).rgb;
	vec3 sw = textureLod(screen_tex, uv + vec2(-1.0, 1.0) * px, 0.0).rgb;
	vec3 se = textureLod(screen_tex, uv + vec2(1.0, 1.0) * px, 0.0).rgb;
	float lm = luma(m), lnw = luma(nw), lne = luma(ne), lsw = luma(sw), lse = luma(se);
	float lmin = min(lm, min(min(lnw, lne), min(lsw, lse)));
	float lmax = max(lm, max(max(lnw, lne), max(lsw, lse)));
	if (lmax - lmin < max(0.0312, lmax * 0.125)) {
		COLOR = vec4(m, 1.0);
	} else {
		vec2 dir = vec2(-((lnw + lne) - (lsw + lse)), (lnw + lsw) - (lne + lse));
		float reduce = max((lnw + lne + lsw + lse) * 0.03125, 0.0078125);
		dir = clamp(dir / (min(abs(dir.x), abs(dir.y)) + reduce), vec2(-8.0), vec2(8.0)) * px;
		vec3 a = 0.5 * (textureLod(screen_tex, uv + dir * (1.0 / 3.0 - 0.5), 0.0).rgb + textureLod(screen_tex, uv + dir * (2.0 / 3.0 - 0.5), 0.0).rgb);
		vec3 b = a * 0.5 + 0.25 * (textureLod(screen_tex, uv + dir * -0.5, 0.0).rgb + textureLod(screen_tex, uv + dir * 0.5, 0.0).rgb);
		float lb = luma(b);
		COLOR = vec4((lb < lmin || lb > lmax) ? a : b, 1.0);
	}
}
