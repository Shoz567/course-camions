shader_type spatial;
render_mode cull_disabled;

// Palissade de bambou (takegaki) de Sakura sur un simple panneau : chaumes
// verticaux de 7 cm, noeuds, teintes vert-ble, deux traverses liees de corde
// noire. UV : x le long de la palissade (m), y en hauteur (m).

float hash(float n) {
	vec3 p3 = fract(vec3(n) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	float u = UV.x / 0.075;
	float id = floor(u);
	float f = fract(u);
	float round_cane = sin(f * 3.14159);
	float tone = hash(id);
	vec3 cane = mix(vec3(0.62, 0.58, 0.32), vec3(0.42, 0.5, 0.24), tone) * (0.55 + 0.5 * round_cane);
	// noeuds a hauteur variable
	float node_y = fract(UV.y / 0.42 + tone);
	cane *= 1.0 - 0.35 * (1.0 - smoothstep(0.0, 0.05, abs(node_y - 0.5)));
	// fente sombre entre deux chaumes
	cane *= smoothstep(0.0, 0.12, f) * smoothstep(1.0, 0.88, f) * 0.85 + 0.15;
	// traverses et liens
	float rail = 0.0;
	for (int k = 0; k < 2; k++) {
		float y = 0.45 + float(k) * 0.8;
		rail = max(rail, 1.0 - smoothstep(0.03, 0.05, abs(UV.y - y)));
	}
	vec3 col = mix(cane, vec3(0.32, 0.36, 0.18), rail);
	float tie = rail * step(0.8, fract(UV.x / 0.6));
	col = mix(col, vec3(0.04, 0.03, 0.02), tie);
	ALBEDO = col;
	ROUGHNESS = 0.6;
	SPECULAR = 0.35;
}
