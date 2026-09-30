shader_type spatial;
render_mode cull_disabled;

// Banc de sable souffle sur la chaussee (piege ralentisseur de Playa Del
// Sol) : sable dore, rides concentriques irregulieres, et un lisere rouge et
// blanc au bord pour le reperer de loin sur le bitume.
// UV : x = angle (0 .. 1), y = rayon relatif (0 au centre, 1 au bord).

void fragment() {
	float r = UV.y;
	float ripple = sin(r * 24.0 + sin(UV.x * 6.2832 * 5.0) * 1.6) * 0.5 + 0.5;
	vec3 sand = mix(vec3(0.98, 0.8, 0.38), vec3(0.78, 0.56, 0.22), ripple * 0.6 + r * 0.2);
	float rim = smoothstep(0.86, 0.9, r);
	vec3 warn = mix(vec3(0.95), vec3(0.9, 0.1, 0.08), step(0.5, fract(UV.x * 14.0)));
	ALBEDO = mix(sand, warn, rim);
	ROUGHNESS = 0.96;
	SPECULAR = 0.2;
}
