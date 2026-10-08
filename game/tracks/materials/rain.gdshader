shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled, skip_vertex_transform;

// Goutte de pluie (2026-10-08, particules) : trait etire le long de la
// vitesse de la goutte RELATIVE a la camera (cam_velocity) - a l'arret elle
// tombe droit, lancee a fond elle fonce sur l'objectif en biais ; plus le
// trait est long, plus il est pale (la meme eau etalee). Les gouttes sont
// surtout vues dans la lumiere : phares, lampadaires, neons (diffusion
// vers l'avant quand la source est derriere elles), un rien sinon.
// Fondues pres de l'objectif (pas de grands traits sur l'ecran) et au loin.

uniform vec3 rain_velocity = vec3(1.5, -24.0, 0.6);
uniform vec3 cam_velocity = vec3(0.0);
// temps de pose du flou (s)
uniform float shutter = 0.018;
uniform float width = 0.011;
uniform vec4 tint : source_color = vec4(0.7, 0.75, 0.85, 0.32);
// visibilite sans lumiere directe (ciel, ville)
uniform float ambient_glow = 0.12;

varying float v_fade;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[1].xyz);
	vec3 rel = rain_velocity - cam_velocity;
	float sp = max(length(rel), 0.01);
	float len = clamp(sp * shutter * s, 0.2, 2.2);
	vec3 axis = rel / sp * len;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 side = cross(axis, center - cam);
	float sl = length(side);
	side = sl > 1e-6 ? side / sl * width * s : vec3(width, 0.0, 0.0);
	vec3 wp = center + axis * VERTEX.y + side * VERTEX.x * 2.0;
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(cam - center, 0.0)).xyz);
	v_fade = clamp(0.5 / len, 0.3, 1.0);
}

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float along = sin(UV.y * PI);
	float dist = -VERTEX.z;
	float fade = smoothstep(1.2, 4.0, dist) * (1.0 - smoothstep(28.0, 42.0, dist));
	ALBEDO = tint.rgb;
	ALPHA = tint.a * across * along * fade * v_fade;
	EMISSION = tint.rgb * ambient_glow;
}

void light() {
	// une goutte renvoie la lumiere de tous cotes, et surtout vers l'avant
	// (source derriere elle, face a la camera)
	float fwd = pow(clamp(dot(-LIGHT, VIEW), 0.0, 1.0), 6.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (0.6 + 3.0 * fwd) / PI;
}
