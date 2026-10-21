shader_type spatial;

// Chaussee de nuit (Cyber City) : bitume detrempe par la pluie (asphalt.
// gdshaderinc) - flaques dans les ornieres ou les neons se refletent, gouttes
// qui ricochent -, marquages blancs uses. UV.x : 0 (bord gauche) .. 1 (bord
// droit). UV.y : distance le long de la piste (m) ; ligne d'arrivee a 0.
uniform float road_width = 75.0;
// ligne d'arrivee peinte (faux en arene : pas de tours)
uniform bool finish_line = true;
// 0 : sec ; 1 : detrempe.
uniform float wetness : hint_range(0.0, 1.0) = 1.0;

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
	vec3 col;
	float rough;
	float h;
	float puddle;
	asphalt_surface(p, road_width, 4.0, 0.1, wetness, TIME, col, rough, h, puddle);

	float paint = 0.0;
	// lignes de bord continues, a 0,8 m des murs
	paint += band(x, 0.8, 1.15) + band(x, road_width - 1.15, road_width - 0.8);
	// voies : pointilles de 9 m, tous les quarts de largeur
	float dash = step(fract(s / 18.0), 0.5);
	for (int k = 1; k < 4; k++) {
		float c = road_width * float(k) / 4.0;
		paint += band(x, c - 0.14, c + 0.14) * dash;
	}
	// peinture usee : effacee par endroits, plus terne dans les ornieres
	paint = clamp(paint, 0.0, 1.0) * (0.55 + 0.45 * smoothstep(0.25, 0.6, a_fbm(p * vec2(1.5, 0.4))));
	// ligne d'arrivee : damier sur 3 m
	if (finish_line && s >= 0.0 && s < 3.0) {
		float c = mod(floor(UV.x * 28.0) + floor(s * 2.0), 2.0);
		col = mix(vec3(0.015), vec3(0.6), c);
		paint = 0.0;
	}
	col = mix(col, vec3(0.62) * mix(1.0, 0.7, wetness), paint);
	ALBEDO = col;
	ROUGHNESS = mix(rough, 0.45, paint * (1.0 - puddle));
	SPECULAR = 0.5;
	// peinture retroreflechissante : a peine lumineuse, lisible dans la nuit
	EMISSION = vec3(0.025) * paint;
	NORMAL = asphalt_bump(NORMAL, VERTEX, h * 0.012, 1.0);
}
