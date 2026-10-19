shader_type spatial;

// Murs des batiments de Sakura (JapanKit). UV en metres : x le long du mur,
// y en hauteur depuis le bas de la boite. COLOR.r choisit le motif :
//   0    machiya, rez-de-chaussee : bois sombre a lattis (koshi), lumiere
//        chaude entre les lattes, poteaux tous les 1,8 m, socle de pierre ;
//   0.25 machiya, etage : enduit, poteaux sombres, fenetre a lattis ;
//   0.5  chateau : enduit blanc, bardage noir en bas, fenetres a barreaux ;
//   0.75 temple : panneaux blancs entre poteaux et poutres vermillon ;
//   1    enduit uni.
// COLOR.g : variation de teinte d'un batiment a l'autre.

#include "res://tracks/materials/asphalt.gdshaderinc"

float pulse(float x, float w) {
	float f = fwidth(x) + 1e-4;
	return smoothstep(-f, f, w - abs(x));
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float style = COLOR.r;
	float tint = COLOR.g;
	vec2 p = vec2(u, v);
	float grain = a_noise(p * vec2(6.0, 40.0));
	vec3 plaster = mix(vec3(0.93, 0.9, 0.83), vec3(0.88, 0.8, 0.66), tint * 0.6) * (0.92 + 0.08 * a_noise(p * 3.0));
	vec3 wood = mix(vec3(0.17, 0.1, 0.06), vec3(0.3, 0.18, 0.1), tint) * (0.8 + 0.35 * grain);
	vec3 lacquer = vec3(0.78, 0.14, 0.06) * (0.9 + 0.1 * grain);
	vec3 col = plaster;
	vec3 emit = vec3(0.0);
	float rough = 0.88;

	if (style < 0.12) {
		// lattis vertical, poteaux, socle
		float slat = pulse(fract(u / 0.14) - 0.5, 0.2);
		float post = pulse(fract(u / 1.8 + 0.5) - 0.5, 0.06);
		vec3 gap = vec3(0.05, 0.03, 0.02);
		col = mix(gap, wood, max(slat, post));
		emit = vec3(1.0, 0.6, 0.3) * (1.0 - max(slat, post)) * smoothstep(0.6, 1.0, v) * (1.0 - smoothstep(2.6, 3.0, v)) * 0.35;
		col = mix(col, vec3(0.45, 0.44, 0.42) * (0.85 + 0.2 * grain), 1.0 - step(0.4, v));
		rough = 0.8;
	} else if (style < 0.37) {
		float post = pulse(fract(u / 1.8) - 0.5, 0.05);
		float beam = pulse(v - 0.12, 0.12) + pulse(v - 2.65, 0.15);
		float bay = floor(u / 1.8);
		float win = step(0.5, fract(bay * 0.5)) * pulse(fract(u / 1.8) - 0.5, 0.28) * pulse(v - 1.45, 0.45);
		float bars = pulse(fract(u / 0.1) - 0.5, 0.25);
		col = mix(plaster, wood, clamp(post + beam, 0.0, 1.0));
		col = mix(col, mix(vec3(0.06, 0.04, 0.03), wood, bars), win);
		emit = vec3(1.0, 0.65, 0.35) * win * (1.0 - bars) * 0.25;
	} else if (style < 0.62) {
		float skirt = 1.0 - step(1.6, mod(v, 7.0));
		float plank = pulse(fract(u / 0.3) - 0.5, 0.03);
		col = mix(plaster, mix(vec3(0.08, 0.08, 0.09), vec3(0.03), plank), skirt);
		float win = pulse(fract(u / 4.0) - 0.5, 0.11) * pulse(mod(v, 7.0) - 3.8, 0.7);
		float bars = pulse(fract(u / 0.15) - 0.5, 0.3);
		col = mix(col, mix(vec3(0.05), vec3(0.12, 0.1, 0.09), bars), win);
		rough = mix(0.9, 0.6, skirt);
	} else if (style < 0.87) {
		float post = pulse(fract(u / 3.0) - 0.5, 0.06);
		float beam = pulse(mod(v, 4.0) - 3.6, 0.16) + pulse(v - 0.15, 0.15);
		float lattice = step(2.6, mod(v, 4.0)) * (1.0 - step(3.45, mod(v, 4.0)))
			* max(pulse(fract(u / 0.25) - 0.5, 0.18), pulse(fract(v / 0.25) - 0.5, 0.18));
		col = mix(plaster, wood * 0.8, lattice);
		col = mix(col, lacquer, clamp(post + beam, 0.0, 1.0));
		rough = mix(0.88, 0.4, clamp(post + beam, 0.0, 1.0));
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
	EMISSION = emit;
}
