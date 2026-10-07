shader_type spatial;
render_mode cull_disabled;

// Glissiere de bord de mer : beton blanc en panneaux de 6 m (joints, grain,
// taches d'humidite, salissures et traces de gomme au pied), vibreur rouge et
// blanc au pied de la face interieure. Sur un pont en bois (COLOR.r = 1) :
// garde-corps de planches verticales. UV.x : 0 .. 1 face interieure (bas ->
// haut), 1 .. 2 dessus, 2 .. 3 face exterieure. UV.y en m.

#include "res://tracks/materials/asphalt.gdshaderinc"

void fragment() {
	vec2 p = vec2(UV.x * 1.1, UV.y);
	float seam = smoothstep(0.93, 0.97, fract(UV.y / 6.0));
	float k = a_detail(p, 8.0);
	float grain = a_noise(p * 8.0) * k + 0.5 * (1.0 - k);
	float blotch = a_fbm(p * vec2(0.6, 0.25));
	vec3 concrete = vec3(0.78, 0.77, 0.73) * (0.86 + 0.14 * grain) * (0.88 + 0.2 * blotch) * (1.0 - 0.35 * seam);
	// coulures sous le dessus, salissures et gomme au pied (face interieure)
	float face = fract(UV.x);
	float inner = step(UV.x, 1.0);
	float streak = smoothstep(0.55, 0.9, a_noise(vec2(UV.y * 3.0, 0.0))) * smoothstep(0.4, 1.0, face) * 0.25;
	float foot = (1.0 - smoothstep(0.0, 0.45, face)) * (0.5 + 0.5 * a_fbm(p * vec2(1.0, 0.3)));
	float rubber = inner * smoothstep(0.75, 0.9, a_fbm(vec2(UV.y * 0.08, 3.0))) * (1.0 - smoothstep(0.2, 0.45, face));
	concrete *= 1.0 - streak - 0.3 * foot * (1.0 - step(2.0, UV.x));
	concrete = mix(concrete, vec3(0.05), rubber * 0.7);
	float curb = step(face, 0.3) * inner;
	vec3 stripe = mix(vec3(0.85), vec3(0.75, 0.1, 0.08), step(0.5, fract(UV.y / 8.0)));
	stripe *= 0.85 + 0.15 * grain;
	vec3 col = mix(concrete, stripe, curb);

	float plank = floor(UV.y / 0.5);
	vec3 wood = mix(vec3(0.33, 0.21, 0.12), vec3(0.5, 0.36, 0.22), a_hash(vec2(plank, 3.0)));
	wood *= 0.8 + 0.3 * a_noise(vec2(UV.y * 8.0 + plank * 13.0, UV.x * 40.0));
	float fp = fract(UV.y / 0.5);
	wood *= 1.0 - 0.6 * (1.0 - smoothstep(0.0, 0.08, fp) * (1.0 - smoothstep(0.92, 1.0, fp)));
	float wood_k = smoothstep(0.7, 0.9, COLOR.r);
	col = mix(col, wood, wood_k);

	ALBEDO = col;
	ROUGHNESS = mix(0.88, 0.7, curb) - 0.1 * rubber;
	SPECULAR = 0.35;
	NORMAL = asphalt_bump(NORMAL, VERTEX, (grain * 0.5 - seam) * 0.004, 1.0);
}
