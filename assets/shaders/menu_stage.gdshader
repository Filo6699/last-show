shader_type canvas_item;
render_mode unshaded;

// Procedural velvet over the existing live scene. No generated image assets.
uniform bool curtains = true;

void fragment() {
	vec2 uv = UV;
	float left_shade = 1.0 - smoothstep(0.30, 0.74, uv.x);
	float edge = smoothstep(0.28, 0.78, length((uv - vec2(0.56, 0.43)) * vec2(1.0, 0.8)));
	vec3 shade = vec3(0.025, 0.013, 0.023);
	float opacity = max(left_shade * 0.97, 0.70 + edge * 0.20);
	if (curtains) {
		float right_edge = 0.78 + 0.18 * pow(uv.y, 0.65);
		float curtain = smoothstep(right_edge - 0.012, right_edge + 0.008, uv.x);
		float left_edge = 0.045 + 0.025 * cos(uv.y * 3.0);
		curtain = max(curtain, 1.0 - smoothstep(left_edge - 0.008, left_edge + 0.012, uv.x));
		float fold = 0.34 + 0.66 * pow(0.5 + 0.5 * sin(uv.x * 122.0 + uv.y * 8.0), 2.0);
		float weave = 0.95 + 0.05 * sin(uv.x * 1800.0) * sin(uv.y * 1400.0);
		vec3 velvet = vec3(0.24, 0.024, 0.035) * fold * weave;
		shade = mix(shade, velvet, curtain);
		opacity = mix(opacity, 0.98, curtain);
	}
	COLOR = vec4(shade, opacity);
}
