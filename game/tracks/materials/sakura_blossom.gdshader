shader_type spatial;

// Couronne de cerisier en fleur (MultiMesh de SakuraBackdrop) : boules
// bosselees (bruit sur la normale), teinte de l'instance (rose pale a soutenu,
// blanc, ou vert pour les pins), mouchetee de fleurs claires et de coeurs
// plus soutenus, plus sombre dessous ; la lumiere la traverse (contre-jour)
// et elle ondule doucement au vent. COLOR : teinte de l'instance.

varying vec3 v_col;
varying vec3 world_pos;
varying float v_under;

float hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	v_col = COLOR.rgb;
	vec3 inst = MODEL_MATRIX[3].xyz;
	// bosses : bruit sur la position locale, decale par arbre
	float b = vnoise(VERTEX * 2.2 + inst * 0.37) - 0.5;
	VERTEX += NORMAL * b * 0.28;
	// ondulation au vent (plus en haut)
	float sway = sin(TIME * 1.1 + inst.x * 0.05 + inst.z * 0.03) * 0.04 * max(VERTEX.y, 0.0);
	VERTEX.x += sway;
	v_under = clamp(-NORMAL.y, 0.0, 1.0);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float bloom = clamp((v_col.r - v_col.g) * 2.5, 0.0, 1.0);
	float speck = vnoise(world_pos * 9.0);
	float speck2 = vnoise(world_pos * 23.0 + 5.0);
	vec3 col = v_col * (0.82 + 0.3 * speck);
	// fleurs claires et coeurs roses (seulement sur les cerisiers)
	col = mix(col, vec3(1.0, 0.96, 0.97), smoothstep(0.62, 0.8, speck2) * 0.6 * bloom);
	col = mix(col, v_col * vec3(0.92, 0.6, 0.7), smoothstep(0.7, 0.85, speck) * 0.5 * bloom);
	col *= 1.0 - 0.35 * v_under;
	ALBEDO = col;
	ROUGHNESS = 0.8;
	SPECULAR = 0.25;
	BACKLIGHT = col * 0.45;
}
