shader_type spatial;

// Panneau de virage a chevrons (RoadDecor, 2026-10-22) sur la face interieure
// du mur exterieur d'un virage serre : fleches « > » qui pointent dans le
// sens de la course. UV.x : metres le long du mur (sens de course), UV.y : 0
// en bas, 1 en haut. COLOR : fond ; `arrow_color` : chevrons ; `glow` :
// lumineux (Cyber City, la nuit).
uniform vec3 arrow_color : source_color = vec3(1.0);
uniform float glow = 0.0;

void fragment() {
	float u = UV.x / 1.5;
	float f = fract(u);
	// 0 au milieu de la hauteur, 1 en haut et en bas : la pointe est au milieu
	float y = abs(UV.y - 0.5) * 2.0;
	float x_c = 0.64 - 0.34 * y;
	float aw = fwidth(u) * 1.5;
	float arrow = 1.0 - smoothstep(0.12, 0.12 + aw, abs(f - x_c));
	arrow *= smoothstep(0.08, 0.1, UV.y) * (1.0 - smoothstep(0.9, 0.92, UV.y));
	// liseré du bord
	float frame = 1.0 - smoothstep(0.03, 0.05, min(UV.y, 1.0 - UV.y));
	vec3 col = mix(COLOR.rgb, arrow_color, max(arrow, frame * 0.8));
	ALBEDO = col;
	EMISSION = col * glow * max(arrow, frame);
	ROUGHNESS = 0.55;
}
