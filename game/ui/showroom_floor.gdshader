shader_type spatial;

// Toit du showroom : dalles de beton de 4 m mouillees par la pluie (joints
// sombres, flaques miroir ou se refletent les neons), deux anneaux neon autour
// du plateau tournant (rayons en m).

uniform float ring_a = 23.0;
uniform float ring_b = 26.5;
varying vec3 wp;

#include "res://tracks/materials/asphalt.gdshaderinc"

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float line(float x, float w) {
	float f = fwidth(x);
	return 1.0 - smoothstep(w - f, w + f, abs(x));
}

void fragment() {
	vec2 p = wp.xz;
	vec2 g = p / 4.0;
	vec2 d = abs(fract(g - 0.5) - 0.5) * 4.0;
	float jw = max(fwidth(p.x), fwidth(p.y));
	float joint = 1.0 - smoothstep(0.03, 0.03 + jw * 1.5, min(d.x, d.y));
	float slab = a_hash(floor(g));
	float pool = smoothstep(0.55, 0.62, a_fbm(p * 0.09 + 5.0) + 0.1 * joint);
	vec3 col = vec3(0.05, 0.05, 0.056) * (0.8 + 0.35 * slab) * (0.8 + 0.4 * a_fbm(p * 0.05));
	col *= (1.0 - 0.6 * joint) * (1.0 - 0.3 * pool);
	float r = length(p);
	float rings = line(r - ring_a, 0.12) + line(r - ring_b, 0.08);
	ALBEDO = col;
	EMISSION = vec3(1.0, 0.15, 0.75) * rings * 3.0;
	ROUGHNESS = mix(0.45 + 0.15 * a_noise(p * 2.0), 0.03, pool);
	SPECULAR = 0.5;
	float k = a_detail(p, 4.0);
	NORMAL = asphalt_bump(NORMAL, VERTEX, (a_noise(p * 4.0) * 0.5 * k - joint) * (1.0 - pool) * 0.008, 1.0);
}
