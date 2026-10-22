shader_type spatial;
render_mode cull_disabled;

// Objets qui montent et descendent au-dessus de la route (RoadDecor,
// 2026-10-22) : drones a enseigne (Cyber City), mouettes (Playa), lanternes
// flottantes (Sakura). Un MultiMesh par circuit ; tout le mouvement est ici
// (aucun calcul par image cote CPU).
// INSTANCE_CUSTOM : x phase (0..1), y amplitude de la montee (m), z vitesse
// (rad/s), w : rayon du vol en cercle (m) si `circle`, sinon melange vers
// `alt_color` des parties lumineuses.
// COLOR : couleur du sommet ; alpha 0 = partie lumineuse.
uniform bool circle = false;
uniform float flap = 0.0;
uniform float spin = 0.0;
uniform float glow = 1.5;
uniform vec3 alt_color : source_color = vec3(1.0);

varying float v_glow;
varying vec3 v_col;

void vertex() {
	float ph = INSTANCE_CUSTOM.x * 6.2832;
	float t = TIME * INSTANCE_CUSTOM.z + ph;
	vec3 v = VERTEX;
	// battement d'ailes : les bouts montent et descendent
	v.y += sin(TIME * 6.5 + ph * 3.0) * abs(v.x) * flap;
	if (circle) {
		// vol en cercle de rayon w, tourne face a sa trajectoire
		float a = t * 0.3;
		float ca = cos(a);
		float sa = sin(a);
		v = vec3(v.x * ca + v.z * sa, v.y, -v.x * sa + v.z * ca);
		v += vec3(ca, 0.0, -sa) * INSTANCE_CUSTOM.w;
	} else if (spin != 0.0) {
		float a = TIME * spin + ph;
		float ca = cos(a);
		float sa = sin(a);
		v = vec3(v.x * ca + v.z * sa, v.y, -v.x * sa + v.z * ca);
	}
	v.y += sin(t) * INSTANCE_CUSTOM.y;
	VERTEX = v;
	v_glow = 1.0 - COLOR.a;
	v_col = circle ? COLOR.rgb : mix(COLOR.rgb, alt_color, INSTANCE_CUSTOM.w * v_glow);
}

void fragment() {
	ALBEDO = v_col;
	EMISSION = v_col * glow * v_glow;
	ROUGHNESS = 0.6;
	BACKLIGHT = v_col * 0.3 * v_glow;
}
