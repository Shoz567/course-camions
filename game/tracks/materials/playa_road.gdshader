shader_type spatial;

// Chaussee de jour (Playa Del Sol) : bitume sec et clair (asphalt.
// gdshaderinc : gravillons, ornieres, rustines, fissures), sable souffle sur
// les bords, marquages blancs uses. Sur un pont en bois (COLOR.r = 1) :
// platelage de planches en travers. UV.x : 0 (bord gauche) .. 1 (bord droit).
// UV.y : distance le long de la piste (m) ; ligne d'arrivee a 0.
uniform float road_width = 75.0;

#include "res://tracks/materials/asphalt.gdshaderinc"

// 1 sur une bande [a, b] (m), bords adoucis sur un pixel
float band(float x, float a, float b) {
	float w = fwidth(x);
	return smoothstep(a - w, a + w, x) * (1.0 - smoothstep(b - w, b + w, x));
}

void fragment() {
	float x = UV.x * road_width;
	float s = UV.y;
	vec2 p = vec2(x, s);
	vec3 asphalt;
	float rough;
	float h;
	float puddle;
	asphalt_surface(p, road_width, 4.0, 0.13, 0.0, TIME, asphalt, rough, h, puddle);
	float grain = a_noise(p * 6.0) * a_detail(p, 6.0) + 0.5 * (1.0 - a_detail(p, 6.0));
	// sable souffle par le vent le long des murs, en trainees
	float edge = min(x, road_width - x);
	float drift = smoothstep(7.0, 0.5, edge + (a_fbm(p * vec2(0.12, 0.05)) - 0.5) * 9.0);
	drift *= 0.6 + 0.4 * a_noise(p * vec2(0.8, 0.15));
	// pas de sable sur les ponts (COLOR.r > 0) : il ne vole pas jusque-la
	drift *= 1.0 - smoothstep(0.1, 0.4, COLOR.r);
	vec3 sand = vec3(0.74, 0.63, 0.43) * (0.88 + 0.24 * grain);
	asphalt = mix(asphalt, sand, drift * 0.85);
	rough = mix(rough, 0.95, drift);
	h = mix(h, grain * 0.4, drift);

	// platelage : planches de 0,6 m, lames de 9 m decalees d'un rang sur deux
	float row = floor(s / 0.6);
	float board = floor((x + 4.5 * mod(row, 2.0)) / 9.0);
	float tone = a_hash(vec2(row, board));
	vec3 wood = mix(vec3(0.3, 0.19, 0.11), vec3(0.5, 0.35, 0.21), tone);
	// veinage le long de la planche (en travers de la piste), grisaille du sel
	float vein = a_noise(vec2(x * 0.6, s * 14.0 + tone * 50.0));
	wood *= 0.8 + 0.35 * vein;
	wood = mix(wood, vec3(0.45, 0.42, 0.38), 0.25 * a_noise(p * 0.3));
	float fs = fract(s / 0.6);
	float gap = 1.0 - smoothstep(0.0, 0.06, fs) * (1.0 - smoothstep(0.94, 1.0, fs));
	wood *= 1.0 - 0.75 * gap;
	float wood_k = smoothstep(0.7, 0.9, COLOR.r);
	vec3 col = mix(asphalt, wood, wood_k);
	rough = mix(rough, 0.8 + 0.1 * vein, wood_k);
	h = mix(h, vein * 0.5 - gap * 1.5, wood_k);

	float paint = 0.0;
	// lignes de bord continues, a 0,8 m des murs
	paint += band(x, 0.8, 1.15) + band(x, road_width - 1.15, road_width - 0.8);
	// voies : pointilles de 9 m, tous les quarts de largeur
	float dash = step(fract(s / 18.0), 0.5);
	for (int k = 1; k < 4; k++) {
		float c = road_width * float(k) / 4.0;
		paint += band(x, c - 0.14, c + 0.14) * dash;
	}
	// peinture usee, a demi recouverte par le sable
	paint = clamp(paint, 0.0, 1.0) * mix(1.0, 0.75, wood_k)
		* (0.6 + 0.4 * smoothstep(0.25, 0.6, a_fbm(p * vec2(1.5, 0.4)))) * (1.0 - 0.7 * drift);
	col = mix(col, vec3(0.8, 0.8, 0.78), paint);
	// ligne d'arrivee : damier sur 3 m
	if (s >= 0.0 && s < 3.0) {
		float c = mod(floor(UV.x * 28.0) + floor(s * 2.0), 2.0);
		col = mix(vec3(0.03), vec3(0.8), c);
	}
	ALBEDO = col;
	ROUGHNESS = mix(rough, 0.55, paint);
	SPECULAR = 0.4;
	NORMAL = asphalt_bump(NORMAL, VERTEX, h * 0.012, 1.0);
}
