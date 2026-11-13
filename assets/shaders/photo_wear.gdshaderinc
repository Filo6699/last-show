// Worn, torn photograph look shared by the wall pieces and the puzzle board.
// wear 1 = scuffed sepia scrap with ragged edges, wear 0 = the clean original.
float pw_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float pw_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(pw_hash(i), pw_hash(i + vec2(1.0, 0.0)), f.x), mix(pw_hash(i + vec2(0.0, 1.0)), pw_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float pw_fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * pw_noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

// uv is piece-local 0..1; returns rgb and alpha (0 where the paper is torn away).
vec4 photo_wear(sampler2D photo, vec2 uv, vec4 region, float wear, float seed, vec2 aspect, vec3 tint) {
	vec3 col = texture(photo, region.xy + uv * region.zw).rgb;
	if (wear <= 0.001) {
		return vec4(col * tint, 1.0);
	}
	float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	float n = pw_fbm(uv * 8.0 + seed * 3.1);
	float cutoff = wear * (0.012 + 0.07 * n * n * 3.0);
	// A bitten-off corner on some pieces.
	vec2 dir = vec2(pw_hash(vec2(seed, 2.0)) > 0.5 ? 1.0 : -1.0, pw_hash(vec2(seed, 3.0)) > 0.5 ? 1.0 : -1.0);
	float bite = step(0.45, pw_hash(vec2(seed, 1.0)));
	float corner = length(uv - (0.5 + 0.5 * dir));
	float hole = step(corner, wear * bite * (0.13 + 0.09 * n));
	// Pin holes and flaked-off spots.
	hole = max(hole, step(0.8, pw_fbm(uv * 13.0 + seed * 7.0)) * step(0.4, wear));
	if (edge < cutoff || hole > 0.5) {
		return vec4(0.0);
	}
	// Pale torn paper fibre along the rim.
	float rim = smoothstep(cutoff, cutoff + 0.03, edge);
	float grey = dot(col, vec3(0.3, 0.59, 0.11));
	vec3 sepia = grey * vec3(1.12, 0.92, 0.68);
	col = mix(col, sepia, 0.8 * wear);
	col = mix(vec3(0.5), col, 1.0 - 0.3 * wear) * (1.0 - 0.3 * wear);
	float stain = pw_fbm(uv * 3.0 + seed * 5.0);
	col = mix(col, col * vec3(0.5, 0.38, 0.25), smoothstep(0.5, 0.78, stain) * 0.85 * wear);
	float edge_burn = 1.0 - smoothstep(0.0, 0.12, edge);
	col *= 1.0 - edge_burn * 0.35 * wear;
	col += (pw_hash(floor(uv * 190.0) + seed) - 0.5) * 0.2 * wear;
	vec2 q = uv * aspect;
	for (int k = 0; k < 4; k++) {
		float fk = float(k);
		float a = pw_hash(vec2(seed, fk + 10.0)) * 3.14159;
		vec2 d = vec2(cos(a), sin(a));
		vec2 o = vec2(pw_hash(vec2(seed, fk + 20.0)), pw_hash(vec2(seed, fk + 30.0))) * aspect;
		float dist = abs(dot(q - o, vec2(-d.y, d.x)));
		float broken = step(0.35, pw_noise(vec2(dot(q, d) * 14.0, fk + seed)));
		col += vec3(0.3) * smoothstep(0.008, 0.0, dist) * broken * wear;
	}
	col = mix(vec3(0.84, 0.8, 0.7), col, rim * 0.8 + 0.2 * (1.0 - wear));
	return vec4(col * tint, 1.0);
}
