shader_type spatial;
render_mode cull_disabled;

// Plaques de la piste (boost, saut) : chevrons lumineux qui defilent dans le
// sens de course, pointe vers l'avant, lisibles de loin. UV : x en travers
// (0 .. 1, gauche -> droite), y le long de la plaque (0 = entree, 1 = sortie).

uniform vec4 color_center : source_color = vec4(1.0, 0.95, 0.15, 1.0);
uniform vec4 color_edge : source_color = vec4(1.0, 0.45, 0.0, 1.0);
uniform vec4 base_color : source_color = vec4(0.05, 0.05, 0.08, 1.0);
uniform float chevron_count = 3.0;
uniform float slope = 1.1;
uniform float speed = 1.6;
uniform float glow = 2.2;
uniform float border = 0.05;

void fragment() {
	float x = abs(UV.x - 0.5) * 2.0;
	// pointe vers l'avant : au centre, la bande est plus loin qu'au bord
	float p = fract(UV.y * chevron_count + x * slope - TIME * speed);
	float stripe = smoothstep(0.40, 0.46, p) * (1.0 - smoothstep(0.86, 0.92, p));
	float frame = max(step(1.0 - border, x), max(step(UV.y, border * 0.6), step(1.0 - border * 0.6, UV.y)));
	float m = max(stripe, frame);
	vec3 c = mix(color_center.rgb, color_edge.rgb, x);
	ALBEDO = mix(base_color.rgb, c, m);
	EMISSION = c * m * glow;
	ROUGHNESS = 0.45;
}
