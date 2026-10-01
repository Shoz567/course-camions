shader_type spatial;

// Chaussee de jour (Playa Del Sol) : bitume clair et sec, marquages blancs,
// sable souffle sur les bords. Sur un pont en bois (COLOR.r = 1) : platelage
// de planches en travers. UV.x : 0 (bord gauche) .. 1 (bord droit). UV.y :
// distance le long de la piste (m) ; ligne d'arrivee a 0.
uniform float road_width = 75.0;

// hachage sans sinus : reste precis loin de l'origine (a 2 km du depart, un
// sin() de grand argument donnait des blocs a bords nets au lieu d'un bruit)
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

// 1 sur une bande [a, b] (m), bords adoucis sur un pixel
float band(float x, float a, float b) {
	float w = fwidth(x);
	return smoothstep(a - w, a + w, x) * (1.0 - smoothstep(b - w, b + w, x));
}

void fragment() {
	float x = UV.x * road_width;
	float s = UV.y;
	vec2 p = vec2(x, s);
	float grain = vnoise(p * 1.7) * 0.6 + vnoise(p * 7.0) * 0.4;
	float patch = vnoise(p * 0.05);
	vec3 asphalt = vec3(0.115, 0.115, 0.12) * (0.85 + 0.3 * grain) * (0.9 + 0.2 * patch);
	// sable souffle par le vent le long des murs
	float edge = min(x, road_width - x);
	float drift = smoothstep(7.0, 0.5, edge + (vnoise(p * 0.12) - 0.5) * 7.0);
	// pas de sable sur les ponts (COLOR.r > 0) : il ne vole pas jusque-la
	drift *= 1.0 - smoothstep(0.1, 0.4, COLOR.r);
	asphalt = mix(asphalt, vec3(0.8, 0.7, 0.48) * (0.9 + 0.2 * grain), drift * 0.85);

	// platelage : planches de 0,6 m, lames de 9 m decalees d'un rang sur deux
	float row = floor(s / 0.6);
	float board = floor((x + 4.5 * mod(row, 2.0)) / 9.0);
	float tone = hash(vec2(row, board));
	vec3 wood = mix(vec3(0.36, 0.23, 0.13), vec3(0.55, 0.39, 0.23), tone);
	wood *= 0.85 + 0.3 * vnoise(vec2(x * 0.5, s * 9.0));
	float fs = fract(s / 0.6);
	float gap = 1.0 - smoothstep(0.0, 0.06, fs) * (1.0 - smoothstep(0.94, 1.0, fs));
	wood *= 1.0 - 0.7 * gap;
	float wood_k = smoothstep(0.7, 0.9, COLOR.r);
	vec3 col = mix(asphalt, wood, wood_k);

	float paint = 0.0;
	// lignes de bord continues, a 0,8 m des murs
	paint += band(x, 0.8, 1.15) + band(x, road_width - 1.15, road_width - 0.8);
	// voies : pointilles de 9 m, tous les quarts de largeur
	float dash = step(fract(s / 18.0), 0.5);
	for (int k = 1; k < 4; k++) {
		float c = road_width * float(k) / 4.0;
		paint += band(x, c - 0.14, c + 0.14) * dash;
	}
	paint = clamp(paint, 0.0, 1.0) * mix(1.0, 0.75, wood_k);
	col = mix(col, vec3(0.93), paint);
	// ligne d'arrivee : damier sur 3 m
	if (s >= 0.0 && s < 3.0) {
		float c = mod(floor(UV.x * 28.0) + floor(s * 2.0), 2.0);
		col = mix(vec3(0.03), vec3(0.95), c);
	}
	ALBEDO = col;
	ROUGHNESS = mix(0.72, 0.92, grain);
	SPECULAR = 0.35;
}
