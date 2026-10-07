shader_type spatial;
render_mode shadows_disabled;

// Spectateurs des tribunes (MultiMesh d'un cylindre par personne) : une
// silhouette - tete couleur peau (plus etroite : epaules), buste de la couleur
// du vetement (COLOR, par instance), jambes en pantalon sombre. Chacun saute a
// son rythme (INSTANCE_CUSTOM.x : phase), une ola parcourt la tribune
// (INSTANCE_CUSTOM.y : position le long du rang), et des flashs d'appareils
// photo crepitent. `glow` : a peine visibles de nuit sous les projecteurs.
uniform float glow = 0.1;

varying float flash;
varying float ly;
varying float seed;

void vertex() {
	float phase = INSTANCE_CUSTOM.x * 6.2832;
	float along = INSTANCE_CUSTOM.y;
	ly = VERTEX.y;
	seed = INSTANCE_CUSTOM.x;
	// tete : plus etroite que les epaules
	float head = smoothstep(0.22, 0.3, VERTEX.y);
	VERTEX.xz *= mix(1.0, 0.5, head);
	float hop = max(0.0, sin(TIME * (3.0 + INSTANCE_CUSTOM.x * 2.0) + phase)) * 0.18;
	float ola = exp(-pow((fract(along - TIME * 0.12) - 0.5) * 9.0, 2.0)) * 0.55;
	VERTEX.y += hop + ola;
	float tick = floor(TIME * 6.0);
	flash = step(0.994, fract(sin(tick * 17.3 + INSTANCE_CUSTOM.x * 431.7) * 43758.5453));
}

void fragment() {
	// teintes de peau, pantalons (jean, noir, beige)
	vec3 skin = mix(vec3(0.36, 0.2, 0.12), vec3(0.85, 0.62, 0.48), fract(seed * 7.13));
	float t = fract(seed * 3.71);
	vec3 legs = t < 0.45 ? vec3(0.06, 0.09, 0.16) : (t < 0.8 ? vec3(0.04) : vec3(0.42, 0.36, 0.26));
	vec3 col = mix(legs, COLOR.rgb, smoothstep(-0.12, -0.08, ly));
	col = mix(col, skin, smoothstep(0.26, 0.29, ly));
	ALBEDO = col;
	EMISSION = col * glow + vec3(1.0) * flash * 6.0;
	ROUGHNESS = 0.85;
}
