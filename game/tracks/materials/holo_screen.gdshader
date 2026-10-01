shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Mega-ecran holographique publicitaire (additif, translucide) : bandes de
// couleur qui defilent, grand balayage lumineux en diagonale, lignes de
// balayage, scintillement et lignes de parasites ; cadre lumineux. Le texte
// de la publicite est un Label3D pose devant.
uniform vec4 color_a : source_color = vec4(0.1, 0.9, 1.0, 1.0);
uniform vec4 color_b : source_color = vec4(1.0, 0.15, 0.8, 1.0);
uniform float seed = 0.0;
uniform float strength = 0.9;

void fragment() {
	vec2 uv = UV;
	float t = TIME + seed * 7.3;
	float bars = smoothstep(0.3, 0.7, sin(uv.x * 11.0 - t * 1.3 + sin(uv.y * 3.0 + t) * 0.8) * 0.5 + 0.5);
	float sweep_pos = fract(t * 0.13);
	float sweep = exp(-pow((uv.x + uv.y * 0.35 - sweep_pos * 1.6) * 7.0, 2.0));
	vec3 col = mix(color_a.rgb, color_b.rgb, bars) * (0.22 + 0.5 * sweep);
	// damier de pixels geants qui s'allument par vagues (mur de LED)
	vec2 cell = floor(uv * vec2(48.0, 12.0));
	float led = step(0.55, fract(sin(cell.x * 12.9898 + cell.y * 78.233 + floor(t * 2.0) * 3.1) * 43758.5453));
	col += mix(color_b.rgb, color_a.rgb, bars) * led * 0.12;
	float scan = 0.7 + 0.3 * sin(uv.y * 180.0 + t * 5.0);
	float flicker = 0.9 + 0.1 * sin(t * 31.0) * sin(t * 12.7);
	float glitch = step(0.97, fract(sin(floor(t * 9.0) * 12.9898 + floor(uv.y * 20.0) * 4.1) * 43758.5453));
	float inside = smoothstep(0.0, 0.012, uv.x) * smoothstep(0.0, 0.012, 1.0 - uv.x)
		* smoothstep(0.0, 0.05, uv.y) * smoothstep(0.0, 0.05, 1.0 - uv.y);
	vec3 frame = color_a.rgb * (1.0 - inside) * 1.6;
	ALBEDO = (col * scan * flicker * (1.0 + 1.5 * glitch) * inside + frame) * strength;
}
