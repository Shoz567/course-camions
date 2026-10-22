shader_type spatial;

// Tours de la ville (MultiMesh d'un cube unite, base a y = -0,5 en local).
// Donnees d'instance (INSTANCE_CUSTOM) : r = graine, g = couleur du neon de
// toit (quart de palette), b = part des fenetres allumees, a > 0,5 = neon de
// toit. Fenetres de 3,2 x 3,6 m allumees au hasard (graine + cellule), en
// teintes chaudes, cyan ou magenta ; au loin, le motif se fond en une lueur
// moyenne (pas de scintillement).
//
// Noir « OLED » dans toutes les qualites (2026-10-22, « en haute et extreme
// les batiments deviennent blancs ; bug de texture sur les carres de
// lumiere ») : facades mates, sans metal ni reflet (en haute, l'eclairage
// global et les reflets d'ecran y renvoyaient la lueur de milliers de
// fenetres : gris clair et grain dans les carres lumineux) ; fenetres
// allumees en emission pure ; hachage sans sinus (sin() d'un grand argument
// est imprecis sur certaines cartes : motifs au lieu du hasard) ; bords des
// fenetres lisses au pixel pres (plus de crenelage qui grouille).

varying vec3 lp;
varying vec3 ln;
varying vec3 sc;
varying vec4 cd;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 neon(float k) {
	if (k < 0.25) return vec3(0.08, 0.95, 1.0);
	if (k < 0.5) return vec3(1.0, 0.12, 0.78);
	if (k < 0.75) return vec3(0.55, 0.25, 1.0);
	return vec3(1.0, 0.8, 0.1);
}

// 1 entre a et b, 0 ailleurs, bords adoucis sur `w` (un pixel)
float band(float x, float a, float b, float w) {
	return smoothstep(a - w, a + w, x) * (1.0 - smoothstep(b - w, b + w, x));
}

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	cd = INSTANCE_CUSTOM;
}

void fragment() {
	vec3 base = vec3(0.012, 0.014, 0.022);
	vec3 e = vec3(0.0);
	float glass = 0.0;
	float h = (lp.y + 0.5) * sc.y;
	if (abs(ln.y) < 0.5) {
		float along = abs(ln.x) > 0.5 ? (lp.z + 0.5) * sc.z : (lp.x + 0.5) * sc.x;
		vec2 q = vec2(along / 3.2, h / 3.6);
		vec2 cell = floor(q);
		vec2 f = fract(q);
		vec2 w = fwidth(q);
		float win = band(f.x, 0.18, 0.82, w.x) * band(f.y, 0.25, 0.8, w.y) * step(4.0, h);
		// graine par tour et par face (cellules et graine bornees : hachage exact)
		vec2 seed = vec2(fract(cd.x * 7.31) * 97.0 + ln.x * 13.0, ln.z * 7.0 + fract(cd.x * 3.7) * 61.0);
		float r = hash(cell + seed);
		float lit = step(1.0 - cd.z, r) * win;
		float r2 = hash(cell * 1.7 + seed.yx + 0.37);
		vec3 warm = vec3(1.0, 0.72, 0.42);
		vec3 tint = r2 < 0.55 ? warm : (r2 < 0.8 ? vec3(0.3, 0.85, 1.0) : vec3(1.0, 0.35, 0.85));
		vec3 windows = tint * lit * (0.9 + 0.8 * hash(cell * 3.1 + seed.x));
		// au loin : lueur moyenne a la place du motif
		float detail = clamp(1.6 - max(w.x, w.y) * 2.0, 0.0, 1.0);
		// (un peu sous la moyenne exacte : une dalle uniforme parait plus claire
		// qu'une facade noire semee de points)
		e += mix(warm * cd.z * 0.24, windows, detail);
		// vitre eteinte : un peu plus claire que le mur, a peine brillante
		glass = win * (1.0 - lit) * detail;
		base += vec3(0.018, 0.022, 0.034) * glass;
		// bandeau neon en haut des facades
		e += neon(cd.y) * step(sc.y - 0.9, h) * step(0.5, cd.w) * 3.0;
	}
	ALBEDO = base;
	EMISSION = e;
	METALLIC = 0.0;
	// mat partout ; la vitre eteinte prend un leger reflet net (pas de grain)
	ROUGHNESS = mix(0.92, 0.18, glass);
	SPECULAR = mix(0.08, 0.3, glass);
}
