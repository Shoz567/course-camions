shader_type spatial;
render_mode cull_disabled;

// Toits de tuiles japonais (JapanKit.hip_roof) : tuiles rondes (kawara) en
// rangees qui descendent la pente, rangs horizontaux, gris-bleu luisant ;
// sous-face (COLOR.b = 0) en chevrons de bois sombre. UV : x le long de
// l'egout, y le long de la pente (m). COLOR.g : teinte (chateau plus vert).

#include "res://tracks/materials/asphalt.gdshaderinc"

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float under = 1.0 - step(0.5, COLOR.b);
	// canaux de tuiles tous les 0,32 m, rangs tous les 0,3 m
	float ch = fract(u / 0.32);
	float round_tile = sin(ch * 3.14159);
	float row = fract(v / 0.3);
	float lip = smoothstep(0.8, 1.0, row);
	float h = round_tile * 0.8 - lip * 0.3;
	vec3 base = mix(vec3(0.16, 0.18, 0.22), vec3(0.22, 0.3, 0.27), smoothstep(0.3, 0.4, COLOR.g) * (1.0 - smoothstep(0.4, 0.45, COLOR.g)));
	base *= 0.75 + 0.45 * round_tile;
	base *= 0.9 + 0.15 * a_noise(vec2(floor(u / 0.32), floor(v / 0.3)) * 3.7);
	base *= 1.0 - 0.25 * lip;
	// chevrons sous l'avancee
	vec3 rafters = vec3(0.16, 0.09, 0.05) * (0.7 + 0.5 * step(0.5, fract(u / 0.6)));
	ALBEDO = mix(base, rafters, under);
	ROUGHNESS = mix(0.42 - 0.12 * round_tile, 0.85, under);
	METALLIC = mix(0.15, 0.0, under);
	SPECULAR = 0.5;
	NORMAL = asphalt_bump(NORMAL, VERTEX, h * 0.05 * (1.0 - under), 1.0);
}
