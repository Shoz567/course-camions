shader_type spatial;
render_mode cull_disabled;

// Murs de pierre de chateau (ishigaki) sous les portions hautes de Sakura :
// gros blocs de granit irreguliers, en rangs legerement ondules, joints
// sombres, mousse au pied et dans les joints. Coordonnees monde : le long du
// talus, x + z ; en hauteur, y.
varying vec3 world_pos;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash2(vec2 p) {
	return vec2(hash(p), hash(p + 19.19));
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
	vec2 p = vec2((world_pos.x + world_pos.z) * 0.7, world_pos.y);
	// cellules de Voronoi etirees : blocs plus larges que hauts
	vec2 q = p / vec2(1.7, 1.0);
	vec2 c = floor(q);
	vec2 f = fract(q);
	float d1 = 8.0;
	float d2 = 8.0;
	vec2 id = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash2(c + g) * 0.8 + 0.1;
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id = c + g;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	float joint = 1.0 - smoothstep(0.04, 0.12, d2 - d1);
	float tone = hash(id);
	vec3 granite = mix(vec3(0.5, 0.48, 0.44), vec3(0.66, 0.63, 0.57), tone);
	granite *= 0.85 + 0.25 * vnoise(p * 6.0);
	vec3 col = granite * (1.0 - 0.7 * joint);
	float moss = smoothstep(0.45, 0.8, vnoise(p * 0.3) + (1.0 - clamp(world_pos.y / 8.0, 0.0, 1.0)) * 0.35);
	col = mix(col, vec3(0.2, 0.3, 0.12), moss * (0.4 + 0.6 * joint) * 0.8);
	ALBEDO = col;
	ROUGHNESS = 0.9;
}
