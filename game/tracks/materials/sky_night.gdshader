shader_type sky;
render_mode use_debanding;

// Ciel de nuit pluvieuse (Cyber City) : couverture nuageuse basse eclairee par
// en dessous par la ville (pollution lumineuse violette et orangee, plus forte
// a l'horizon), rares etoiles dans les trouees. Statique : le reflet du ciel
// n'est calcule qu'une fois.
uniform vec3 zenith_color : source_color = vec3(0.004, 0.004, 0.014);
uniform vec3 glow_color : source_color = vec3(0.3, 0.08, 0.34);
uniform vec3 glow_warm : source_color = vec3(0.4, 0.16, 0.08);
uniform vec3 ground_color : source_color = vec3(0.006, 0.006, 0.02);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.7;

#include "res://tracks/materials/sky_common.gdshaderinc"

void sky() {
	vec3 d = EYEDIR;
	float h = max(d.y, 0.0);
	// lueur de la ville : forte a l'horizon, chaude par endroits
	float warm = s_noise(vec2(atan(d.x, d.z) * 3.0, 0.0));
	vec3 glow = mix(glow_color, glow_warm, warm * 0.6);
	vec3 col = zenith_color + glow * exp(-h * 5.0);
	if (d.y > 0.0) {
		vec2 uv = s_cloud_uv(d) * 0.9;
		int oct = AT_CUBEMAP_PASS ? 4 : 6;
		float n = s_fbm(uv, oct);
		float base = 1.0 - cloud_coverage;
		float dens = smoothstep(base - 0.1, base + 0.25, n);
		// dessous des nuages eclaire par la ville, plus fort pres de l'horizon
		vec3 under = glow * (0.18 + 0.55 * exp(-h * 2.5)) * (0.7 + 0.6 * n);
		// etoiles dans les trouees
		vec2 sp = d.xz / (d.y + 1.0) * 420.0;
		float star = step(0.9975, s_hash(floor(sp))) * (1.0 - smoothstep(0.05, 0.35, length(fract(sp) - 0.5)));
		col += vec3(0.5, 0.55, 0.7) * star * smoothstep(0.15, 0.5, h) * (1.0 - dens);
		col = mix(col, under, dens * smoothstep(0.0, 0.06, d.y));
	} else {
		col = mix(glow * 0.9 + zenith_color, ground_color, smoothstep(0.0, 0.1, -d.y));
	}
	COLOR = col;
}
