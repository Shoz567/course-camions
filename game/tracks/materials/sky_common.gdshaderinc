// Bruits partages par les ciels (sky_day, sky_night) : sans sinus, precis.
float s_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float s_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(s_hash(i), s_hash(i + vec2(1.0, 0.0)), f.x),
		mix(s_hash(i + vec2(0.0, 1.0)), s_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float s_fbm(vec2 p, int octaves) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < octaves; k++) {
		v += a * s_noise(p);
		p = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6)) * p + vec2(3.1, 1.7);
		a *= 0.5;
	}
	return v;
}

// Point de la couche nuageuse vu dans la direction `d` (plan a l'altitude 1,
// rapproche a l'horizon : la couche s'aplatit au loin).
vec2 s_cloud_uv(vec3 d) {
	return d.xz / (d.y + 0.06);
}
