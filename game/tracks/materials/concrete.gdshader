shader_type spatial;

// Beton des tribunes, ponts et piliers (2026-10-08, matieres) : projete en
// coordonnees monde sur la face dominante (les boites du decor n'ont pas
// d'UV utiles), en metres.
//   - banches de 2,4 x 1,2 m : joints fins en creux, trous de tiges aux
//     coins ;
//   - teinte qui varie par plaques, pores et grain fin (effaces au loin) ;
//   - coulures sur les faces verticales : trainees plus sombres qui
//     descendent ;
//   - `wetness` (nuit de pluie) : plus sombre et brillant, l'eau ruisselle dans
//     les coulures.

uniform vec3 tint : source_color = vec3(0.74, 0.72, 0.68);
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

#include "res://tracks/materials/asphalt.gdshaderinc"

varying vec3 world_pos;
varying vec3 world_n;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 an = abs(world_n);
	// face dominante : x -> (z, y), z -> (x, y), y -> (x, z) ; .y vertical
	// sur les faces verticales
	bool vertical = an.y < 0.7;
	vec2 p = an.x > an.z ? world_pos.zy : world_pos.xy;
	if (!vertical) {
		p = world_pos.xz;
	}
	// banches
	vec2 cell = p / vec2(2.4, 1.2);
	vec2 f = fract(cell);
	vec2 w = fwidth(cell) * 1.5 + 0.004;
	float seam = max(1.0 - smoothstep(0.0, w.x, min(f.x, 1.0 - f.x)),
		1.0 - smoothstep(0.0, w.y, min(f.y, 1.0 - f.y)));
	seam *= a_detail(p, 1.5);
	vec2 tie = abs(fract(cell * 2.0 + 0.5) - 0.5) * vec2(1.2, 0.6);
	float hole = (1.0 - smoothstep(0.025, 0.04, length(tie))) * a_detail(p, 6.0);
	// teinte par banche et par plaques, pores
	float panel = a_hash(floor(cell));
	float blotch = a_fbm(p * 0.35);
	float k = a_detail(p, 18.0);
	float pores = smoothstep(0.75, 0.9, a_noise(p * 18.0)) * k;
	float grain = a_noise(p * 7.0) * a_detail(p, 7.0) + 0.5 * (1.0 - a_detail(p, 7.0));
	vec3 col = tint * (0.9 + 0.12 * panel) * (0.84 + 0.3 * blotch) * (0.92 + 0.14 * grain);
	col *= 1.0 - 0.25 * pores - 0.22 * seam - 0.5 * hole;
	// coulures : sur les faces verticales, bandes etirees vers le bas
	float run = 0.0;
	if (vertical) {
		run = smoothstep(0.55, 0.85, a_fbm(vec2(p.x * 1.6, p.y * 0.12) + 5.0));
		run *= 0.6 + 0.4 * a_noise(vec2(p.x * 6.0, p.y * 0.5));
		col *= 1.0 - 0.28 * run;
	}
	// mouille : plus sombre, brillant, l'eau suit les coulures
	col *= mix(1.0, 0.7, wetness);
	float rough = mix(0.88, 0.95, grain) + 0.05 * pores;
	rough = mix(rough, mix(0.45, 0.18, run), wetness);
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = mix(0.35, 0.5, wetness);
	METALLIC = metallic;
	NORMAL = asphalt_bump(NORMAL, VERTEX, (grain * 0.4 - pores * 0.6 - seam * 1.2 - hole * 2.0) * 0.004, 1.0);
}
