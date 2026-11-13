shader_type canvas_item;
render_mode unshaded;
// Film grain, vignette and a darkening veil over the 3D picture only.
uniform float grain : hint_range(0.0, 1.0) = 0.0;
uniform float darkness : hint_range(0.0, 1.0) = 0.0;
uniform float vignette : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec2 centered = SCREEN_UV - 0.5;
	float edge = smoothstep(0.25, 0.85, length(centered * vec2(1.0, 0.85)) * 1.45);
	float veil = clamp(darkness + vignette * edge, 0.0, 0.92);
	// Chunky grain that changes 12 times a second, like scanned film.
	vec2 cell = floor(FRAGCOORD.xy / 1.6) + mod(floor(TIME * 12.0), 97.0) * vec2(37.0, 17.0);
	vec3 p3 = fract(vec3(cell.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	float n = fract((p3.x + p3.y) * p3.z) * 2.0 - 1.0;
	float grain_alpha = grain * abs(n);
	float alpha = grain_alpha + veil * (1.0 - grain_alpha);
	vec3 color = vec3(n > 0.0 ? 1.0 : 0.0) * grain_alpha / max(alpha, 0.0001);
	COLOR = vec4(color, alpha);
}
