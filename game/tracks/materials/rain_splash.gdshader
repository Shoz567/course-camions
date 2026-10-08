shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled;

// Eclaboussure d'une goutte sur la route (2026-10-08, particules) : petite
// couronne qui s'ouvre et retombe en quelques centiemes de seconde, dressee
// face a la camera (axe Y du monde), posee sur le sol par sa base. Eclairee
// comme les gouttes (rain.gdshader). Les anneaux dans les flaques restent
// l'affaire de la chaussee (asphalt.gdshaderinc).

uniform vec4 tint : source_color = vec4(0.75, 0.8, 0.9, 0.28);
uniform float ambient_glow = 0.12;

varying float v_age;
varying float v_seed;

void vertex() {
	vec3 y = vec3(0.0, 1.0, 0.0);
	vec3 to_cam = INV_VIEW_MATRIX[3].xyz - MODEL_MATRIX[3].xyz;
	vec3 x = cross(y, to_cam);
	x = length(x) > 1e-5 ? normalize(x) : vec3(1.0, 0.0, 0.0);
	vec3 z = cross(x, y);
	float sc = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(x * sc, 0.0), vec4(y * sc, 0.0), vec4(z * sc, 0.0), MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	v_age = INSTANCE_CUSTOM.y / max(INSTANCE_CUSTOM.w, 0.001);
	v_seed = INSTANCE_CUSTOM.z;
}

void fragment() {
	// base de la couronne en bas du quad (UV.y = 1)
	vec2 q = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y);
	float open = mix(0.25, 0.85, sqrt(v_age));
	// deux bras qui s'ecartent en V, plus quelques gouttelettes au-dessus
	float arm = abs(abs(q.x) - q.y * open * 1.1);
	// bras flous, qui s'effilent vers le haut
	float top = 0.7 * (1.0 - v_age * 0.6);
	float rim = (1.0 - smoothstep(0.02, 0.16, arm)) * (1.0 - smoothstep(top * 0.5, top, q.y)) * smoothstep(0.0, 0.06, q.y);
	float drops = 0.0;
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		vec2 c = vec2((fract(v_seed * 7.3 + fi * 0.37) - 0.5) * 1.4 * open,
			0.55 + 0.35 * fract(v_seed * 3.1 + fi * 0.61) - v_age * v_age * 0.6);
		drops += (1.0 - smoothstep(0.015, 0.06, length(q - c))) * 0.7;
	}
	float a = clamp(rim + drops, 0.0, 1.0) * (1.0 - v_age);
	float dist = -VERTEX.z;
	a *= smoothstep(0.8, 2.5, dist) * (1.0 - smoothstep(18.0, 26.0, dist));
	ALBEDO = tint.rgb;
	ALPHA = tint.a * a;
	EMISSION = tint.rgb * ambient_glow;
}

void light() {
	float fwd = pow(clamp(dot(-LIGHT, VIEW), 0.0, 1.0), 6.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (0.7 + 2.0 * fwd) / PI;
}
