shader_type spatial;

// Toit du showroom : dalle sombre et brillante, quadrillage cyan fin tous les
// 4 m, deux anneaux neon autour du plateau tournant (rayons en m).

uniform float ring_a = 23.0;
uniform float ring_b = 26.5;
varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float line(float x, float w) {
	float f = fwidth(x);
	return 1.0 - smoothstep(w - f, w + f, abs(x));
}

void fragment() {
	vec2 g = wp.xz / 4.0;
	vec2 d = abs(fract(g - 0.5) - 0.5) / max(fwidth(g), vec2(1e-4));
	float grid = 1.0 - min(min(d.x, d.y), 1.0);
	float r = length(wp.xz);
	float rings = line(r - ring_a, 0.12) + line(r - ring_b, 0.08);
	ALBEDO = vec3(0.025, 0.027, 0.04);
	EMISSION = vec3(0.0, 0.45, 0.7) * grid * 0.35 + vec3(1.0, 0.15, 0.75) * rings * 3.0;
	METALLIC = 0.4;
	ROUGHNESS = 0.22;
}
