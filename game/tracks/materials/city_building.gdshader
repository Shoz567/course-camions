shader_type spatial;

// Tours de la ville (MultiMesh d'un cube unite, base a y = -0,5 en local).
// Donnees d'instance (INSTANCE_CUSTOM) : r = graine, g = couleur du neon de
// toit (quart de palette), b = part des fenetres allumees, a > 0,5 = neon de
// toit. Fenetres de 3,2 x 3,6 m allumees au hasard (graine + cellule), en
// teintes chaudes, cyan ou magenta ; au loin, le motif se fond en une lueur
// moyenne (pas de scintillement).

varying vec3 lp;
varying vec3 ln;
varying vec3 sc;
varying vec4 cd;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 neon(float k) {
	if (k < 0.25) return vec3(0.08, 0.95, 1.0);
	if (k < 0.5) return vec3(1.0, 0.12, 0.78);
	if (k < 0.75) return vec3(0.55, 0.25, 1.0);
	return vec3(1.0, 0.8, 0.1);
}

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	cd = INSTANCE_CUSTOM;
}

void fragment() {
	vec3 base = vec3(0.02, 0.024, 0.036);
	vec3 e = vec3(0.0);
	float h = (lp.y + 0.5) * sc.y;
	if (abs(ln.y) < 0.5) {
		float along = abs(ln.x) > 0.5 ? (lp.z + 0.5) * sc.z : (lp.x + 0.5) * sc.x;
		vec2 q = vec2(along / 3.2, h / 3.6);
		vec2 cell = floor(q);
		vec2 f = fract(q);
		float win = step(0.18, f.x) * step(f.x, 0.82) * step(0.25, f.y) * step(f.y, 0.8) * step(4.0, h);
		float r = hash(cell + vec2(cd.x * 97.0 + ln.x * 13.0, ln.z * 7.0));
		float lit = step(1.0 - cd.z, r) * win;
		float r2 = hash(cell * 1.7 + cd.x * 31.0);
		vec3 warm = vec3(1.0, 0.72, 0.42);
		vec3 tint = r2 < 0.55 ? warm : (r2 < 0.8 ? vec3(0.3, 0.85, 1.0) : vec3(1.0, 0.35, 0.85));
		vec3 windows = tint * lit * (0.9 + 0.8 * hash(cell * 3.1 + cd.x));
		// au loin : lueur moyenne a la place du motif
		float detail = clamp(1.6 - max(fwidth(q.x), fwidth(q.y)) * 2.0, 0.0, 1.0);
		e += mix(warm * cd.z * 0.35, windows, detail);
		base += vec3(0.025, 0.03, 0.045) * win * (1.0 - lit) * detail;
		// bandeau neon en haut des facades
		e += neon(cd.y) * step(sc.y - 0.9, h) * step(0.5, cd.w) * 3.0;
	}
	ALBEDO = base;
	EMISSION = e;
	METALLIC = 0.35;
	ROUGHNESS = 0.45;
}
