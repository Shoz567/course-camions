shader_type spatial;
render_mode cull_disabled;

// Flaque de Sakura : eau claire et sombre de bassin (le ciel rose s'y
// reflete), petales qui flottent et derivent lentement, rides concentriques,
// lisere de petales echoues sur le bord - bien visible a la lumiere du jour.
// UV : x = angle (0 .. 1), y = rayon relatif (0 au centre, 1 au bord).
varying vec3 local_pos;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float r = UV.y;
	float ripple = sin(r * 34.0 - TIME * 3.0) * 0.5 + 0.5;
	vec3 water = mix(vec3(0.02, 0.07, 0.08), vec3(0.04, 0.12, 0.13), r);
	// petales qui flottent : cellules de 0,7 m qui derivent avec le vent
	vec2 q = local_pos.xz + vec2(TIME * 0.12, TIME * 0.05);
	vec2 c = floor(q / 0.7);
	vec2 f = fract(q / 0.7) - 0.5;
	vec2 o = vec2(hash(c), hash(c + 7.1)) * 0.5 - 0.25;
	float a = hash(c + 3.3) * 6.2831 + TIME * 0.2;
	vec2 d = f - o;
	d = vec2(d.x * cos(a) - d.y * sin(a), d.x * sin(a) + d.y * cos(a));
	float petal = step(0.45, hash(c + 11.0)) * (1.0 - smoothstep(0.8, 1.0, length(d / vec2(0.22, 0.14))));
	// lisere de petales echoues sur le bord
	float rim = smoothstep(0.74, 0.95, r);
	vec3 pink = mix(vec3(0.95, 0.5, 0.68), vec3(1.0, 0.84, 0.9), hash(c + 5.0));
	float cover = clamp(petal + rim * 0.85, 0.0, 1.0);
	ALBEDO = mix(water, pink, cover);
	ROUGHNESS = mix(0.03 + 0.05 * ripple, 0.7, cover);
	METALLIC = mix(0.15, 0.0, cover);
	SPECULAR = mix(0.9, 0.4, cover);
	EMISSION = vec3(0.18, 0.08, 0.1) * rim * 0.4;
}
