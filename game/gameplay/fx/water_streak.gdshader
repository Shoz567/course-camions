shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled, skip_vertex_transform;

// Trainee d'eau (2026-10-08, "des trainees dans l'eau" sur la route
// mouillee de Cyber City) : gouttes que les pneus arrachent a la chaussee,
// dessinees en traits fins comme la pluie (rain.gdshader) et lancees par
// spark_particles.gdshader (couleurs blanches, heat 1 : COLOR.r porte
// l'extinction en fin de vie). Translucides : on voit au travers, au
// contraire des bouffees de fumee qui bouchaient la vue du suivant.

uniform vec4 tint : source_color = vec4(0.72, 0.78, 0.88, 0.6);
// visibilite sans lumiere directe (ciel, ville)
uniform float ambient_glow = 0.14;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 axis = MODEL_MATRIX[1].xyz;
	float w = length(MODEL_MATRIX[0].xyz);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 side = cross(axis, center - cam);
	float sl = length(side);
	side = sl > 1e-6 ? side / sl * w : MODEL_MATRIX[0].xyz;
	vec3 wp = center + axis * VERTEX.y + side * VERTEX.x * 2.0;
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(cam - center, 0.0)).xyz);
}

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	// UV.y = 0 en tete (la goutte), la queue s'efface
	float a = across * mix(1.0, 0.2, UV.y);
	// rien en gros plan sur l'objectif
	float fade = smoothstep(0.8, 2.5, -VERTEX.z);
	ALBEDO = tint.rgb;
	ALPHA = tint.a * a * clamp(COLOR.r, 0.0, 1.0) * fade;
	EMISSION = tint.rgb * ambient_glow;
}

void light() {
	// comme la pluie : renvoyee de tous cotes, surtout vers l'avant
	float fwd = pow(clamp(dot(-LIGHT, VIEW), 0.0, 1.0), 6.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (0.6 + 3.0 * fwd) / PI;
}
