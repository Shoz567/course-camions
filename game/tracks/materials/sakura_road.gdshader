shader_type spatial;

// Chaussee de Sakura (Japon au printemps) : bitume clair et chaud
// (asphalt.gdshaderinc), petales de cerisier tombes - semes partout, en
// tapis le long des murs, et en trainees que le vent fait courir en travers.
// Sur un pont en bois (COLOR.r = 1) : platelage laque brun-rouge. Marquages
// blancs, ligne d'arrivee en damier. UV.x : 0 (bord gauche) .. 1 (bord
// droit). UV.y : distance le long de la piste (m) ; ligne d'arrivee a 0.
uniform float road_width = 70.0;
// ligne d'arrivee peinte (faux en arene : pas de tours)
uniform bool finish_line = true;

#include "res://tracks/materials/asphalt.gdshaderinc"

float band(float x, float a, float b) {
	float w = fwidth(x);
	return smoothstep(a - w, a + w, x) * (1.0 - smoothstep(b - w, b + w, x));
}

// Un petale par cellule de `cell` m (au plus), pose au hasard, oriente au
// hasard : ellipse de 5 x 3 cm a pointe echancree. `dens` : part des cellules
// occupees. Renvoie la couverture (0..1), `tone` sa teinte (0 blanc .. 1 rose).
float petal_layer(vec2 p, float cell, float dens, float seed, out float tone) {
	vec2 c = floor(p / cell);
	vec2 f = fract(p / cell);
	tone = a_hash(c + seed + 3.7);
	if (a_hash(c + seed) > dens) {
		return 0.0;
	}
	vec2 o = a_hash2(c + seed + 1.3) * 0.5 + 0.25;
	float ang = a_hash(c + seed + 9.1) * 6.2831;
	vec2 d = (f - o) * cell;
	d = vec2(d.x * cos(ang) - d.y * sin(ang), d.x * sin(ang) + d.y * cos(ang));
	float e = length(d / vec2(0.028, 0.017));
	// echancrure a la pointe
	float notch = 1.0 - smoothstep(0.0, 0.006, length(d - vec2(0.028, 0.0)));
	float aa = fwidth(e) + 0.05;
	return (1.0 - smoothstep(1.0 - aa, 1.0, e)) * (1.0 - notch);
}

void fragment() {
	float x = UV.x * road_width;
	float s = UV.y;
	vec2 p = vec2(x, s);
	vec3 asphalt;
	float rough;
	float h;
	float puddle;
	asphalt_surface(p, road_width, 4.0, 0.2, 0.0, TIME, asphalt, rough, h, puddle);
	asphalt *= vec3(1.08, 1.0, 0.92);

	// densite des petales : tapis le long des murs, semis au milieu, et
	// trainees que les rafales poussent en travers de la piste
	float edge = min(x, road_width - x);
	float carpet = smoothstep(9.0, 0.5, edge + (a_fbm(p * vec2(0.14, 0.05)) - 0.5) * 9.0);
	vec2 wp = vec2(x - TIME * 1.8, s);
	float ribbon = smoothstep(0.6, 0.78, a_fbm(vec2(wp.x * 0.2, wp.y * 1.4) + 17.0));
	ribbon *= smoothstep(0.35, 0.7, a_noise(vec2(s * 0.02 + 2.0, x * 0.03 - TIME * 0.06)));
	float dens = clamp(0.12 + 0.75 * carpet + 0.45 * ribbon, 0.0, 0.95);
	// pas de petales sur le pont : le vent les chasse
	float wood_k = smoothstep(0.7, 0.9, COLOR.r);
	dens *= 1.0 - 0.7 * wood_k;

	vec3 pink = vec3(0.96, 0.52, 0.68);
	vec3 white = vec3(0.99, 0.84, 0.89);
	// au loin, plus de petales a l'unite : leur teinte moyenne
	float k = a_detail(p, 18.0);
	float t1;
	float t2;
	float pa = petal_layer(p, 0.12, dens, 0.0, t1);
	float pb = petal_layer(p + 0.05, 0.09, dens * 0.8, 31.0, t2);
	vec3 petal_col = mix(white, pink, max(t1, t2) * 0.9);
	float cover = max(pa, pb) * k + dens * 0.7 * (1.0 - k);
	vec3 far_col = mix(white, pink, 0.55);

	// platelage du pont : bois de hinoki patine, gris-brun (2026-10-22 : le
	// laque brun-rouge virait au saumon sous le ciel rose, et la laque
	// vermillon est au garde-corps), planches de 0,6 m, lames de 9 m
	// decalees ; une poutre sombre tous les 6 m, cloutee de fer
	float row = floor(s / 0.6);
	float board = floor((x + 4.5 * mod(row, 2.0)) / 9.0);
	float tone = a_hash(vec2(row, board));
	vec3 wood = mix(vec3(0.3, 0.22, 0.16), vec3(0.47, 0.36, 0.26), tone);
	float vein = a_noise(vec2(x * 0.6, s * 14.0 + tone * 50.0));
	wood *= 0.82 + 0.3 * vein;
	float fs = fract(s / 0.6);
	float gap = 1.0 - smoothstep(0.0, 0.06, fs) * (1.0 - smoothstep(0.94, 1.0, fs));
	wood *= 1.0 - 0.7 * gap;
	float bs = abs(fract(s / 6.0 + 0.5) - 0.5) * 6.0;
	float beam = 1.0 - smoothstep(0.16, 0.2, bs);
	// clous : un rond de 4 cm tous les 0,9 m sur l'axe de la poutre
	float stud = 1.0 - smoothstep(0.03, 0.045, length(vec2((fract(x / 0.9) - 0.5) * 0.9, bs)));
	wood = mix(wood, vec3(0.14, 0.1, 0.08), beam * 0.85);
	wood = mix(wood, vec3(0.32, 0.31, 0.3), stud);
	vec3 col = mix(asphalt, wood, wood_k);
	rough = mix(rough, 0.55 + 0.1 * vein, wood_k);
	h = mix(h, vein * 0.5 - gap * 1.5, wood_k);

	float paint = 0.0;
	paint += band(x, 0.8, 1.15) + band(x, road_width - 1.15, road_width - 0.8);
	float dash = step(fract(s / 18.0), 0.5);
	for (int lane = 1; lane < 4; lane++) {
		float c = road_width * float(lane) / 4.0;
		paint += band(x, c - 0.14, c + 0.14) * dash;
	}
	paint = clamp(paint, 0.0, 1.0) * (0.65 + 0.35 * smoothstep(0.25, 0.6, a_fbm(p * vec2(1.5, 0.4))));
	col = mix(col, vec3(0.86, 0.85, 0.82), paint * (1.0 - 0.6 * wood_k));
	col = mix(col, mix(far_col, petal_col, k), clamp(cover, 0.0, 1.0));
	if (finish_line && s >= 0.0 && s < 3.0) {
		float c = mod(floor(UV.x * 28.0) + floor(s * 2.0), 2.0);
		col = mix(vec3(0.03), vec3(0.85), c);
	}
	ALBEDO = col;
	ROUGHNESS = mix(mix(rough, 0.55, paint), 0.75, cover);
	SPECULAR = 0.15;
	NORMAL = asphalt_bump(NORMAL, VERTEX, (h + cover * 0.6) * 0.012, 1.0);
}
