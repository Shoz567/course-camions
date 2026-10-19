shader_type spatial;
// Aura du BOUCLIER (pouvoir, 2026-10-17 : « une aura bleue a moitie
// transparente autour de la tete du camion, qui epouse sa forme, une texture
// appliquee par-dessus ») : posee en material_overlay sur chaque piece de la
// tete. La piece est redessinee a peine gonflee le long de ses normales, en
// bleu translucide, plus dense sur les bords (Fresnel), avec des bandes qui
// montent et une pulsation douce.
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 color : source_color = vec4(0.25, 0.65, 1.0, 1.0);
// Gonflement le long des normales (m) : l'aura colle a la tole sans s'y fondre.
uniform float grow = 0.035;
uniform float base_alpha = 0.18;
uniform float rim_alpha = 0.55;
uniform float energy = 2.2;

void vertex() {
	VERTEX += NORMAL * grow;
}

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float bands = 0.5 + 0.5 * sin(world.y * 9.0 - TIME * 6.0);
	float pulse = 0.85 + 0.15 * sin(TIME * 5.0);
	ALBEDO = color.rgb * energy * (0.8 + 0.4 * bands);
	ALPHA = clamp((base_alpha + rim_alpha * rim) * pulse * (0.85 + 0.15 * bands), 0.0, 0.95);
}
