shader_type spatial;

// Sol de Sakura : herbe tendre et mousse de jardin japonais, allees de
// gravier ratisse par endroits, et tapis de petales roses sous les
// cerisiers (taches de bruit), semis de petales partout. Coordonnees monde.
varying vec3 world_pos;

// hachage sans sinus : precis loin de l'origine
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * vnoise(p);
		p = p * 2.03 + 17.0;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 w = world_pos.xz;
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float near = 1.0 - smoothstep(30.0, 90.0, dist);
	// herbe : deux verts, tachee, brins au pres
	float g = fbm(w * 0.05);
	vec3 grass = mix(vec3(0.22, 0.4, 0.1), vec3(0.45, 0.6, 0.18), g);
	grass = mix(grass, vec3(0.18, 0.3, 0.14), smoothstep(0.55, 0.8, fbm(w * 0.013 + 4.0)) * 0.6);
	grass *= 0.85 + 0.3 * mix(0.5, vnoise(w * 3.0), near);
	// gravier ratisse : grandes taches claires, sillons paralleles
	float gravel_k = smoothstep(0.74, 0.77, fbm(w * 0.006 + 31.0));
	float rake = 0.5 + 0.5 * sin(w.x * 6.0 + vnoise(w * 0.05) * 9.0);
	vec3 gravel = vec3(0.74, 0.66, 0.54) * (0.88 + 0.12 * mix(0.5, rake, near));
	vec3 col = mix(grass, gravel, gravel_k);
	// tapis de petales sous les cerisiers et semis
	float carpet = smoothstep(0.55, 0.72, fbm(w * 0.02 + 9.0));
	float speck = step(0.82, hash(floor(w / 0.12))) * near;
	float petals = clamp(carpet * 0.85 + speck * 0.6 + (1.0 - near) * 0.05, 0.0, 1.0);
	vec3 pink = mix(vec3(0.95, 0.6, 0.72), vec3(0.99, 0.85, 0.9), hash(floor(w / 0.12) + 3.0));
	col = mix(col, pink, petals * (1.0 - 0.6 * gravel_k));
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.85, petals);
	SPECULAR = 0.25;
}
