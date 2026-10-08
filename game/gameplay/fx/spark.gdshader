shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform, fog_disabled;

// Trait d'etincelle (2026-10-08, particules) : quad etire le long de l'axe Y
// de la particule (spark_particles.gdshader y met la vitesse et la longueur),
// tourne vers la camera autour de cet axe. Tete eclatante, queue qui
// s'efface ; couleur HDR (le glow de l'environnement la fait rayonner).

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 axis = MODEL_MATRIX[1].xyz;
	float w = length(MODEL_MATRIX[0].xyz);
	vec3 side = cross(axis, center - INV_VIEW_MATRIX[3].xyz);
	float sl = length(side);
	side = sl > 1e-6 ? side / sl * w : MODEL_MATRIX[0].xyz;
	vec3 wp = center + axis * VERTEX.y + side * VERTEX.x * 2.0;
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	// UV.y = 0 en tete (+Y, le sens de la vitesse)
	float a = across * across * mix(1.0, 0.15, UV.y);
	ALBEDO = COLOR.rgb * a;
}
