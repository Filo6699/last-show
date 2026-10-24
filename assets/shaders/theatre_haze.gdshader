shader_type spatial;
render_mode unshaded, cull_front, blend_add, depth_draw_never, depth_test_disabled, fog_disabled;

uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 source_position;
uniform vec3 source_direction;
uniform vec3 beam_color : source_color = vec3(1.0, 0.72, 0.43);
uniform float reach = 17.0;
uniform float spread = 0.21;
uniform float density = 0.016;
uniform float strength = 1.0;
varying vec3 back_surface;

void vertex() {
	back_surface = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Compatibility uses OpenGL's -1..1 clip-space depth. Stop the haze at the
	// opaque scene surface so the shaft cannot shine through people or scenery.
	float z = texture(scene_depth, SCREEN_UV).r;
	vec4 view_point = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, z * 2.0 - 1.0, 1.0);
	view_point /= view_point.w;
	vec3 surface = (INV_VIEW_MATRIX * view_point).xyz;
	vec3 eye = INV_VIEW_MATRIX[3].xyz;
	vec3 ray = normalize(back_surface - eye);
	float end = min(length(back_surface - eye), length(surface - eye));
	float begin = max(0.0, dot(source_position - eye, ray) - reach);
	float stride = max(0.0, end - begin) / 12.0;
	float haze = 0.0;
	for (int i = 0; i < 12; i++) {
		vec3 p = eye + ray * (begin + (float(i) + 0.5) * stride) - source_position;
		float along = dot(p, source_direction);
		float radius = max(0.05, along * spread);
		float radial = length(p - source_direction * along) / radius;
		float edge = 1.0 - smoothstep(0.35, 1.0, radial);
		float ends = smoothstep(0.0, 0.4, along) * (1.0 - smoothstep(reach * 0.8, reach, along));
		haze += edge * ends * stride;
	}
	ALBEDO = beam_color;
	ALPHA = clamp(haze * density * strength, 0.0, 0.22);
}
