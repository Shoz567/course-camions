shader_type sky;
render_mode use_debanding;

// Ciel de plein jour (Playa Del Sol) : bleu profond au zenith, voile clair a
// l'horizon (diffusion de Rayleigh), halo autour du soleil (Mie), disque
// solaire, et cumulus de beau temps - sommets eclaires, bases grises,
// ombres propres du cote oppose au soleil. Sous l'horizon : le large.
// Statique (pas de TIME) : le reflet du ciel n'est calcule qu'une fois.
uniform vec3 zenith_color : source_color = vec3(0.09, 0.3, 0.78);
uniform vec3 horizon_color : source_color = vec3(0.62, 0.8, 0.96);
uniform vec3 sea_color : source_color = vec3(0.02, 0.16, 0.34);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.42;
uniform float cloud_scale = 0.55;
uniform float sun_size_deg = 0.55;

#include "res://tracks/materials/sky_common.gdshaderinc"

void sky() {
	vec3 d = EYEDIR;
	vec3 sun = LIGHT0_DIRECTION;
	vec3 sun_col = LIGHT0_COLOR * LIGHT0_ENERGY;
	float mu = dot(d, sun);
	float h = max(d.y, 0.0);
	vec3 col = mix(horizon_color, zenith_color, pow(h, 0.5));
	// voile d'horizon, plus chaud vers le soleil
	col += mix(horizon_color, sun_col * 0.6, 0.35 * max(mu, 0.0)) * 0.35 * exp(-h * 10.0);
	// halo de Mie
	col += sun_col * (0.05 * pow(max(mu, 0.0), 6.0) + 0.3 * pow(max(mu, 0.0), 120.0));
	if (d.y > 0.0) {
		vec2 uv = s_cloud_uv(d) * cloud_scale;
		int oct = AT_CUBEMAP_PASS ? 4 : 6;
		float n = s_fbm(uv, oct);
		float base = 1.0 - cloud_coverage;
		float dens = smoothstep(base, base + 0.22, n);
		// ombre propre : densite un peu plus loin vers le soleil
		float n2 = s_fbm(uv + normalize(sun.xz + vec2(1e-4)) * 0.12, oct);
		float lit = clamp(0.62 + (n - n2) * 5.0, 0.0, 1.0);
		vec3 shadow_col = mix(horizon_color, zenith_color, 0.25) * 0.55 + vec3(0.12);
		vec3 cloud = mix(shadow_col, vec3(1.0) * (0.65 + 0.35 * sun_col), lit);
		cloud += sun_col * 0.5 * pow(max(mu, 0.0), 8.0) * (1.0 - dens);   // bords translucides
		float fade = smoothstep(0.0, 0.12, d.y);
		col = mix(col, cloud * 1.15, dens * fade * 0.95);
	}
	// disque solaire (tres lumineux : il bave dans le glow)
	float disc = smoothstep(cos(radians(sun_size_deg)), cos(radians(sun_size_deg * 0.8)), mu);
	col += sun_col * disc * 30.0;
	// sous l'horizon : la mer au loin, en degrade doux sur ~25 deg
	// (2026-10-22) : les vaguelettes qui penchent le reflet sous l'horizon y
	// prenaient un bleu nuit a bord net - des taches sombres sur l'eau
	if (d.y < 0.0) {
		col = mix(horizon_color * 0.85, sea_color, smoothstep(0.0, 0.45, -d.y));
	}
	COLOR = col;
}
