shader_type spatial;

// Sol de Playa Del Sol : une ile. Le masque (calcule sur le trace par
// TrackBlockout) dit ou est la terre (R) et l'interieur de la boucle (V).
// Terre : sable clair, mouille au bord de l'eau, herbe a l'interieur.
// Mer : turquoise sur les hauts-fonds, bleu profond au large, ecume qui
// avance et recule sur le rivage, vaguelettes (normale animee : le soleil y
// scintille). En coordonnees monde : le sol physique reste un plan.
uniform sampler2D coast_mask : filter_linear, repeat_disable;
uniform vec2 coast_origin = vec2(0.0);
uniform float coast_size = 1.0;

varying vec3 world_pos;

// hachage sans sinus : reste precis loin de l'origine (a 2 km du depart, un
// sin() de grand argument donnait des blocs a bords nets au lieu d'un bruit)
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 w = world_pos.xz;
	vec2 uv = (w - coast_origin) / coast_size;
	vec4 m = texture(coast_mask, uv);
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	// rivage irregulier : le masque, bruite
	float land = m.r * inside + (vnoise(w * 0.018) - 0.5) * 0.16 + (vnoise(w * 0.09) - 0.5) * 0.05;
	// la ligne d'eau avance et recule
	float tide = sin(TIME * 0.7 + vnoise(w * 0.03) * 6.0) * 0.012;
	float shore = land - 0.5 + tide;              // > 0 : au sec
	float water = 1.0 - smoothstep(-0.004, 0.004, shore);

	// terre
	float grain = vnoise(w * 1.3) * 0.5 + vnoise(w * 7.0) * 0.5;
	vec3 sand = mix(vec3(0.72, 0.58, 0.36), vec3(0.6, 0.47, 0.28), grain);
	sand *= 0.92 + 0.08 * sin(w.x * 0.9 + vnoise(w * 0.2) * 5.0);      // rides du vent
	float wet = smoothstep(0.07, 0.0, shore);
	sand = mix(sand, sand * vec3(0.6, 0.58, 0.55), wet);
	float green = smoothstep(0.55, 0.85, m.g * inside + (vnoise(w * 0.012) - 0.5) * 0.35);
	vec3 grass = mix(vec3(0.09, 0.3, 0.07), vec3(0.22, 0.44, 0.12), vnoise(w * 0.35));
	vec3 ground = mix(sand, grass, green);

	// mer : l'eau est sombre, sa couleur vient surtout du ciel qu'elle reflete
	// (Fresnel : miroir a l'horizon, transparente a la verticale) ; sur les
	// hauts-fonds, le sable clair remonte en turquoise.
	float depth = clamp(-shore / 0.45, 0.0, 1.0);  // 0 au bord, 1 au large
	vec3 shallow = vec3(0.03, 0.42, 0.4);
	vec3 deep = vec3(0.0, 0.05, 0.12);
	vec3 sea = mix(shallow, deep, smoothstep(0.03, 0.7, depth));
	sea = mix(mix(sand * 0.75, shallow, 0.6), sea, smoothstep(0.0, 0.1, depth));
	float swell = vnoise(w * 0.05 + TIME * vec2(0.05, 0.03));
	// rouleaux : lignes d'ecume paralleles au rivage, qui avancent vers lui
	float roll = sin(depth * 70.0 + TIME * 1.4 + swell * 7.0);
	float foam = smoothstep(0.8, 1.0, roll) * smoothstep(0.45, 0.02, depth) * (0.4 + 0.6 * vnoise(w * 0.4));
	foam += smoothstep(0.02, 0.0, abs(shore)) * 0.9;
	// moutons au large, rares
	foam += smoothstep(0.78, 0.86, vnoise(w * 0.06 + TIME * vec2(0.03, -0.02))) * smoothstep(0.3, 0.8, depth)
		* smoothstep(0.6, 0.9, vnoise(w * 0.7 + TIME * 0.4)) * 0.5;
	foam = clamp(foam, 0.0, 1.0);
	sea = mix(sea, vec3(0.92), foam);

	ALBEDO = mix(ground, sea, water);
	ROUGHNESS = mix(0.92, 0.04 + 0.6 * foam, water);
	SPECULAR = mix(0.25, 0.5, water);
	// houle et clapot : quatre trains d'ondes de longueurs differentes, plus
	// du bruit ; les plus courtes s'effacent au loin (plus fines qu'un pixel),
	// la houle longue reste jusqu'a l'horizon
	float dist = length(VERTEX);
	vec2 q = w + (vec2(vnoise(w * 0.02), vnoise(w * 0.02 + 31.0)) - 0.5) * 40.0;
	vec2 slope = vec2(0.0);
	// x, y : direction ; z : nombre d'onde (rad/m) ; w : pulsation (rad/s)
	vec4 dirs[4] = vec4[](vec4(0.8, 0.6, 0.045, 0.9), vec4(-0.5, 0.86, 0.11, 1.6),
		vec4(0.96, -0.28, 0.29, 2.6), vec4(0.2, 0.98, 0.7, 4.1));
	for (int k = 0; k < 4; k++) {
		vec2 dk = dirs[k].xy;
		float kk = dirs[k].z;            // nombre d'onde (rad/m)
		float fade = smoothstep(3.0 / kk * 60.0, 3.0 / kk * 8.0, dist);
		float ph = dot(dk, q) * kk + TIME * dirs[k].w;
		// pente : la houle longue est douce, le clapot plus raide
		slope += dk * cos(ph) * (0.05 + 0.03 * float(k)) * fade;
	}
	float nf = smoothstep(120.0, 20.0, dist);
	slope += (vec2(vnoise(w * 1.3 + TIME * 0.6), vnoise(w * 1.3 - TIME * 0.6 + 7.0)) - 0.5) * 0.3 * nf;
	slope *= water * (1.0 - foam * 0.7);
	vec3 n_world = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
}
