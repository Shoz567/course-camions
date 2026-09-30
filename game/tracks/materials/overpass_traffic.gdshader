shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

// Circulation sur un pont routier, vue de loin : des points de lumiere qui
// filent le long du tablier. UV.x : le long du pont (0 .. 1) ; UV.y : en
// travers, decoupe en `lanes` voies. Sur la chaussee (4 voies) : phares
// blancs dans un sens, feux rouges dans l'autre. Sur le bandeau du bord du
// tablier (1 voie) : `tail_lights` choisit le sens et la couleur.
uniform float length_m = 300.0;
uniform float speed = 22.0;
uniform float lanes = 4.0;
uniform bool tail_lights = false;

float lights(float x, float lane_seed, float dir) {
	float pos = x * length_m / 14.0 + dir * TIME * speed / 14.0 + lane_seed;
	float id = floor(pos);
	// une voiture sur deux environ (deterministe par emplacement)
	float on = step(0.45, fract(sin(id * 91.7 + lane_seed * 13.1) * 43758.5453));
	float d = abs(fract(pos) - 0.5);
	return on * smoothstep(0.16, 0.02, d);
}

void fragment() {
	float lane = floor(UV.y * lanes);
	float in_lane = smoothstep(0.5, 0.2, abs(fract(UV.y * lanes) - 0.5));
	float forward = lanes > 1.5 ? step(lane, lanes / 2.0 - 0.5) : (tail_lights ? 0.0 : 1.0);
	float l = lights(UV.x, lane * 3.7 + (tail_lights ? 1.9 : 0.0), mix(1.0, -1.0, forward)) * in_lane;
	vec3 col = mix(vec3(1.0, 0.08, 0.05), vec3(1.0, 0.95, 0.8), forward);
	ALBEDO = vec3(0.015, 0.016, 0.02) + col * l * 4.0;
}
