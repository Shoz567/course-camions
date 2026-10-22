shader_type spatial;
render_mode cull_disabled;

// Rideau de fete japonais (kohaku-maku) tendu sur la face interieure des murs
// de Sakura : bandes verticales rouges et blanches de 0,45 m, corde noire en
// haut, plis (ombre ondulee) ; la lumiere traverse le tissu. UV : x le long
// du mur (m), y de 0 (bas) a 1 (haut).

void fragment() {
	float band = step(0.5, fract(UV.x / 0.9));
	vec3 col = mix(vec3(0.97, 0.95, 0.9), vec3(0.8, 0.08, 0.06), band);
	float fold = 0.82 + 0.18 * sin(UV.x * 21.0);
	col *= fold;
	float rope = smoothstep(0.9, 0.93, UV.y);
	col = mix(col, vec3(0.06, 0.04, 0.03), rope);
	ALBEDO = col;
	ROUGHNESS = 0.9;
	BACKLIGHT = col * 0.35;
}
