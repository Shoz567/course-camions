shader_type spatial;
render_mode cull_disabled;

// Glissiere de bord de mer : beton blanc en panneaux de 6 m, vibreur rouge et
// blanc au pied de la face interieure. Sur un pont en bois (COLOR.r = 1) :
// garde-corps de planches verticales. UV.x : 0 .. 1 face interieure (bas ->
// haut), 1 .. 2 dessus, 2 .. 3 face exterieure. UV.y en m.

// hachage sans sinus : reste precis loin de l'origine (a 2 km du depart, un
// sin() de grand argument donnait des blocs a bords nets au lieu d'un bruit)
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	float seam = smoothstep(0.93, 0.97, fract(UV.y / 6.0));
	vec3 concrete = vec3(0.86, 0.85, 0.8) * (1.0 - 0.3 * seam);
	float inner = step(UV.x, 1.0);
	float curb = step(fract(UV.x), 0.3) * inner;
	vec3 stripe = mix(vec3(0.92), vec3(0.85, 0.12, 0.1), step(0.5, fract(UV.y / 8.0)));
	vec3 col = mix(concrete, stripe, curb);

	float plank = floor(UV.y / 0.5);
	vec3 wood = mix(vec3(0.38, 0.25, 0.14), vec3(0.56, 0.4, 0.24), hash(vec2(plank, 3.0)));
	float fp = fract(UV.y / 0.5);
	wood *= 1.0 - 0.6 * (1.0 - smoothstep(0.0, 0.08, fp) * (1.0 - smoothstep(0.92, 1.0, fp)));
	col = mix(col, wood, smoothstep(0.7, 0.9, COLOR.r));

	ALBEDO = col;
	ROUGHNESS = 0.82;
	SPECULAR = 0.3;
}
