shader_type spatial;
render_mode cull_disabled;

// Mur de Sakura, facon mur de temple (tsuiji-bei) : soubassement de pierre,
// enduit blanc casse entre des poteaux de bois sombre tous les 3 m, poutre
// haute, chaperon de tuiles gris-bleu sur le dessus. Sur un pont en bois
// (COLOR.r = 1) : garde-corps laque vermillon a poteaux et lisses, chapeaux
// noirs. Sur un pont de pierre (COLOR.r = 0,5) : granit. UV.x : 0 .. 1 face
// interieure (bas -> haut), 1 .. 2 dessus, 2 .. 3 face exterieure. UV.y en m.

#include "res://tracks/materials/asphalt.gdshaderinc"

void fragment() {
	vec2 p = vec2(UV.x * 1.1, UV.y);
	float face = fract(UV.x);
	float top = step(1.0, UV.x) * (1.0 - step(2.0, UV.x));
	float k = a_detail(p, 8.0);
	float grain = a_noise(p * 8.0) * k + 0.5 * (1.0 - k);

	// enduit : blanc chaud, nuages d'humidite, coulures sous le chaperon
	float blotch = a_fbm(p * vec2(0.5, 0.2));
	vec3 plaster = vec3(0.9, 0.87, 0.8) * (0.9 + 0.1 * grain) * (0.9 + 0.12 * blotch);
	plaster *= 1.0 - 0.18 * smoothstep(0.6, 0.95, face) * smoothstep(0.5, 0.9, a_noise(vec2(UV.y * 2.5, 1.0)));
	// soubassement de pierre (pierres de 0,6 m a joints sombres)
	vec2 sp = vec2(UV.y / 0.9, face / 0.12);
	float srow = floor(sp.y);
	vec2 sf = fract(vec2(sp.x + 0.5 * mod(srow, 2.0), sp.y));
	float joint = 1.0 - smoothstep(0.0, 0.06, min(min(sf.x, 1.0 - sf.x), min(sf.y, 1.0 - sf.y)));
	vec3 stone = vec3(0.52, 0.5, 0.46) * (0.82 + 0.3 * a_hash(floor(vec2(sp.x + 0.5 * mod(srow, 2.0), srow)))) * (1.0 - 0.55 * joint);
	float base = 1.0 - step(0.24, face);
	// poteaux de bois tous les 3 m et poutre haute
	float post_x = abs(fract(UV.y / 3.0) - 0.5) * 3.0;
	float post = 1.0 - smoothstep(0.16, 0.2, post_x);
	float beam = smoothstep(0.82, 0.84, face);
	vec3 wood = vec3(0.2, 0.12, 0.07) * (0.85 + 0.3 * a_noise(vec2(UV.y * 3.0, face * 40.0)));
	vec3 col = mix(plaster, wood, max(post, beam) * (1.0 - base));
	col = mix(col, stone, base);
	// chaperon de tuiles : rangs de 0,3 m le long du mur
	float tile = fract(UV.y / 0.3);
	vec3 roof = vec3(0.24, 0.26, 0.3) * (0.7 + 0.4 * smoothstep(0.0, 0.5, tile) * (1.0 - smoothstep(0.5, 1.0, tile)));
	col = mix(col, roof, top);

	// pont de bois : garde-corps laque vermillon
	float red_k = smoothstep(0.7, 0.9, COLOR.r);
	float rpost = 1.0 - smoothstep(0.1, 0.14, abs(fract(UV.y / 2.5) - 0.5) * 2.5);
	vec3 lacquer = vec3(0.78, 0.13, 0.06) * (0.9 + 0.15 * grain);
	float rail = smoothstep(0.42, 0.45, face) * (1.0 - smoothstep(0.55, 0.58, face));
	vec3 rcol = mix(lacquer, lacquer * 0.7, rail);
	rcol = mix(rcol, vec3(0.06, 0.05, 0.05), top * 0.9 + rpost * smoothstep(0.85, 0.9, face));
	col = mix(col, rcol, red_k);
	// pont de pierre : granit
	float stone_k = smoothstep(0.3, 0.45, COLOR.r) * (1.0 - red_k);
	col = mix(col, vec3(0.55, 0.53, 0.5) * (0.85 + 0.25 * grain), stone_k);

	ALBEDO = col;
	ROUGHNESS = mix(mix(0.85, 0.5, max(post, beam)), 0.35, red_k);
	SPECULAR = mix(0.3, 0.5, red_k);
	NORMAL = asphalt_bump(NORMAL, VERTEX, (grain * 0.4 - joint * base) * 0.004, 1.0);
}
