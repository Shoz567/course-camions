shader_type spatial;
render_mode shadows_disabled;

// Spectateurs des tribunes (MultiMesh d'une boite par personne) : couleur par
// instance (COLOR), chacun saute a son rythme (INSTANCE_CUSTOM.x : phase),
// une ola parcourt la tribune (INSTANCE_CUSTOM.y : position le long du rang),
// et des flashs d'appareils photo crepitent. Un peu lumineux : on les voit de
// nuit sous les projecteurs.
uniform float glow = 0.7;

varying float flash;

void vertex() {
	float phase = INSTANCE_CUSTOM.x * 6.2832;
	float along = INSTANCE_CUSTOM.y;
	float hop = max(0.0, sin(TIME * (3.0 + INSTANCE_CUSTOM.x * 2.0) + phase)) * 0.18;
	float ola = exp(-pow((fract(along - TIME * 0.12) - 0.5) * 9.0, 2.0)) * 0.55;
	VERTEX.y += (hop + ola) * step(0.0, VERTEX.y);
	float tick = floor(TIME * 6.0);
	flash = step(0.994, fract(sin(tick * 17.3 + INSTANCE_CUSTOM.x * 431.7) * 43758.5453));
}

void fragment() {
	ALBEDO = COLOR.rgb;
	EMISSION = COLOR.rgb * glow + vec3(1.0) * flash * 6.0;
	ROUGHNESS = 0.8;
}
