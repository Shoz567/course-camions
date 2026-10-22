shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_disabled;

// Bouffee de fumee (2026-10-08, particules) : billboard qui tourne
// (INSTANCE_CUSTOM.x), contour dechiquete par un bruit propre a chaque
// bouffee (INSTANCE_CUSTOM.z, tire au hasard a l'emission) qui roule avec
// l'age ; eclairee comme une boule (le haut prend la lumiere, le soleil
// traverse les bords), fondue contre le decor et pres de la camera.
// `glow` : lueur orange par-dessous (feu, explosion) qui s'eteint avec l'age.
// Style du jeu (2026-10-22, « la fumee noire fait tache ») : bouffees rondes a
// bord net, eclairage en deux tons (dessus clair, dessous ombre, comme un
// dessin anime), et la couleur s'eclaircit en montant (`age_lighten`) : une
// fumee sombre reste sombre pres du moteur, puis grise en se dispersant.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float soft_m = 1.2;
uniform vec3 glow = vec3(0.0);
uniform float glow_until = 0.3;
// nuit : la fumee renvoie la lueur de la ville (sinon noire sur le ciel noir)
uniform float self_light = 0.0;
// gris vers lequel la bouffee tend en vieillissant, et de combien
uniform vec3 age_tint = vec3(0.68, 0.68, 0.7);
uniform float age_lighten = 0.7;

varying vec3 v_center;
varying float v_radius;
varying float v_seed;
varying float v_age;

void vertex() {
	float ang = INSTANCE_CUSTOM.x;
	mat4 m = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]),
		normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	m = m * mat4(vec4(cos(ang), -sin(ang), 0.0, 0.0), vec4(sin(ang), cos(ang), 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	float sc = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * m * mat4(vec4(sc, 0.0, 0.0, 0.0), vec4(0.0, sc, 0.0, 0.0),
		vec4(0.0, 0.0, sc, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	v_center = (VIEW_MATRIX * MODEL_MATRIX[3]).xyz;
	v_radius = max(sc * 0.5, 0.01);
	v_seed = INSTANCE_CUSTOM.z;
	v_age = INSTANCE_CUSTOM.y / max(INSTANCE_CUSTOM.w, 0.001);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	vec2 o = vec2(v_seed * 17.31, v_seed * 9.73);
	float n1 = texture(noise_tex, UV * 0.45 + o + vec2(0.0, v_age * 0.12)).r;
	float n2 = texture(noise_tex, UV * 1.1 + o * 1.7 - vec2(v_age * 0.18, 0.0)).r;
	// bord de bouffee net et bossele (chou-fleur), pas un brouillard dechiquete
	float edge = r + (n1 - 0.5) * 0.5 + (n2 - 0.5) * 0.16;
	float shape = 1.0 - smoothstep(0.52, 0.7, edge);
	float dens = shape * mix(0.85, 1.15, n1);
	// fondu contre le decor (pas de coupe nette dans la route, la caisse)
	float d = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	vp.xyz /= vp.w;
	float soft = clamp((VERTEX.z - vp.z) / soft_m, 0.0, 1.0);
	soft *= smoothstep(0.4, 2.0, -VERTEX.z);
	ALPHA = clamp(dens * COLOR.a * soft, 0.0, 1.0);
	vec3 base = mix(COLOR.rgb, age_tint, smoothstep(0.08, 0.85, v_age) * age_lighten);
	ALBEDO = base * mix(0.88, 1.08, n2);
	// normale de boule : le relief des volutes prend la lumiere
	vec2 q = (VERTEX.xy - v_center.xy) / v_radius;
	NORMAL = normalize(vec3(q + (vec2(n1, n2) - 0.5) * 0.8, 0.9));
	ROUGHNESS = 1.0;
	EMISSION = glow * (1.0 - smoothstep(0.0, glow_until, v_age)) * mix(0.5, 1.4, n1) + ALBEDO * self_light;
}

void light() {
	// deux tons : face au soleil claire, a l'ombre plus sombre, transition
	// courte (le cote a l'ombre recoit quand meme : la fumee diffuse)
	float wrap = clamp(dot(NORMAL, LIGHT) * 0.6 + 0.4, 0.0, 1.0);
	wrap = mix(0.42, 1.0, smoothstep(0.42, 0.58, wrap));
	// contre-jour : le soleil traverse les bords
	float back = pow(clamp(dot(-LIGHT, VIEW), 0.0, 1.0), 4.0) * 0.6;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (wrap + back) / PI;
}
