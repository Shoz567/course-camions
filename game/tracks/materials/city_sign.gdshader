shader_type spatial;
render_mode cull_disabled;

// Enseignes de toit (MultiMesh d'un cube unite aplati) : panneau neon avec des
// barres de « texte » de longueurs variees, liseré, balayage lumineux et
// rares clignotements. INSTANCE_CUSTOM : r = graine, g = couleur.

varying vec3 lp;
varying vec3 ln;
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
	cd = INSTANCE_CUSTOM;
}

void fragment() {
	vec3 col = neon(cd.g);
	vec2 uv = vec2(lp.x + 0.5, lp.y + 0.5);
	float face = step(0.5, abs(ln.z));
	// deux ou trois lignes de « texte »
	float rows = 2.0 + step(0.5, hash(vec2(cd.r, 1.0)));
	float row = floor(uv.y * rows);
	float fy = fract(uv.y * rows);
	float len = 0.45 + 0.45 * hash(vec2(row, cd.r * 50.0));
	float start = (1.0 - len) * 0.5;
	float glyphs = step(0.3, fract(uv.x * 14.0 + hash(vec2(row, cd.r)) * 3.0));
	float text = step(start, uv.x) * step(uv.x, start + len) * step(0.25, fy) * step(fy, 0.75) * glyphs;
	float frame = 1.0 - step(0.04, uv.x) * step(uv.x, 0.96) * step(0.06, uv.y) * step(uv.y, 0.94);
	float sweep = smoothstep(0.1, 0.0, abs(fract(TIME * 0.25 + cd.r) - uv.x)) * 0.6;
	float flicker = step(0.04, hash(vec2(floor(TIME * 9.0), cd.r * 70.0)));
	float m = max(text, frame) * face;
	ALBEDO = vec3(0.02) + col * 0.1;
	EMISSION = col * (m * 3.2 + sweep * face) * flicker;
	ROUGHNESS = 0.4;
}
