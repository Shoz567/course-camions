shader_type spatial;
render_mode cull_disabled;

// Flaque d'eau : miroir sombre (faible rugosite : les neons s'y refletent),
// rides concentriques animees, lisere cyan discret pour la reperer de nuit.
// UV : x = angle (0 .. 1), y = rayon relatif (0 au centre, 1 au bord).

void fragment() {
	float r = UV.y;
	float ripple = sin(r * 38.0 - TIME * 4.0) * 0.5 + 0.5;
	ALBEDO = vec3(0.01, 0.02, 0.04);
	ROUGHNESS = 0.03 + 0.05 * ripple;
	METALLIC = 0.2;
	SPECULAR = 0.9;
	EMISSION = vec3(0.0, 0.35, 0.55) * smoothstep(0.8, 0.98, r) * 0.9;
}
