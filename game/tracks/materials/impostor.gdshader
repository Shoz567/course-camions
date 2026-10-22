shader_type spatial;
render_mode cull_disabled, skip_vertex_transform, depth_draw_opaque;

// Sprite d'arbre lointain (FarLod) : la photo du modele 3D (bake_impostors.gd)
// sur un quad qui tourne autour de la verticale pour faire face a la camera
// (« 2D tourne »), pied au sol. Couleur de l'instance sur la couronne (les
// pixels clairs), tronc intact. Il apparait au-dela de fade_begin m, en
// fondu trame sur fade_length m (pas de transparence a trier) ; plus pres,
// l'arbre 3D le remplace. Eclaire comme le reste (soleil, ciel, brume), la
// lumiere le traverse (contre-jour).

uniform sampler2D albedo : source_color, filter_linear_mipmap, repeat_disable;
uniform float fade_begin = 170.0;
uniform float fade_length = 60.0;

varying vec3 v_tint;
varying float v_dist;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 to_cam = cam - center;
	to_cam.y = 0.0;
	to_cam = length(to_cam) > 1e-4 ? normalize(to_cam) : vec3(0.0, 0.0, 1.0);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
	v_dist = distance(cam, center);
	// avant le fondu, quad ecrase en un point : aucun pixel a calculer (un
	// sprite proche couvrirait l'ecran pour etre jete pixel par pixel)
	float on = step(fade_begin, v_dist);
	vec3 world = center + (right * VERTEX.x * sx + vec3(0.0, 1.0, 0.0) * VERTEX.y * sy) * on;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	// normale : vers la camera, relevee (eclairee comme une couronne)
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(to_cam + vec3(0.0, 0.9, 0.0)), 0.0)).xyz);
	v_tint = COLOR.rgb;
}

void fragment() {
	vec4 tex = texture(albedo, UV);
	if (tex.a < 0.45) {
		discard;
	}
	// fondu trame a l'entree (l'arbre 3D est encore la plus pres)
	float fade = smoothstep(fade_begin, fade_begin + fade_length, v_dist);
	if (fade < hash(FRAGCOORD.xy)) {
		discard;
	}
	float leaf = smoothstep(0.25, 0.45, dot(tex.rgb, vec3(0.333)));
	ALBEDO = tex.rgb * mix(vec3(1.0), v_tint, leaf);
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	BACKLIGHT = ALBEDO * 0.3 * leaf;
}
