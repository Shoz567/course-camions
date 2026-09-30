shader_type spatial;
render_mode cull_disabled;

// Talus et falaises de Playa Del Sol : roche ocre en strates horizontales,
// vegetation par taches et vers le pied, sable tout en bas. En coordonnees
// monde : les strates restent horizontales quel que soit le maillage.
varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 w = world_pos.xz;
	float h = world_pos.y;
	float warp = vnoise(w * 0.04) * 4.0;
	float strata = vnoise(vec2((h + warp) * 1.4, 0.5));
	vec3 rock = mix(vec3(0.5, 0.38, 0.26), vec3(0.3, 0.23, 0.17), strata);
	rock *= 0.8 + 0.4 * vnoise(w * 0.3 + vec2(h, -h));
	float veg = smoothstep(0.5, 0.75, vnoise(w * 0.05) * 0.8 + (1.0 - clamp(h / 14.0, 0.0, 1.0)) * 0.3);
	vec3 green = mix(vec3(0.12, 0.34, 0.09), vec3(0.28, 0.5, 0.15), vnoise(w * 0.45));
	vec3 col = mix(rock, green, veg);
	vec3 sand = vec3(0.72, 0.62, 0.43);
	col = mix(sand, col, smoothstep(0.3, 2.2, h + vnoise(w * 0.2) * 1.2));
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
