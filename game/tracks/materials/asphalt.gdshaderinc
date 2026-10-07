// Bitume realiste, partage par les chaussees des circuits (road.gdshader,
// playa_road.gdshader). Tout est procedural, en metres, dans le repere de la
// piste : p.x a travers (0 au bord gauche), p.y le long (distance parcourue).
//
//   - enrobe : teinte de fond qui varie par grandes plaques, gravillons
//     clairs (effaces au loin : pas de scintillement), micro-relief ;
//   - usure : deux ornieres par voie (passage des roues), plus sombres
//     (gomme) et plus lisses, taches d'huile au milieu des voies ;
//   - reparations : rustines rectangulaires plus noires, fissures colmatees
//     au goudron ;
//   - salissures le long des murs ;
//   - mouille (wet > 0) : bitume assombri et brillant, l'eau stagne dans les
//     ornieres et les creux (flaques miroir), gouttes de pluie qui ricochent.
//
// asphalt_surface() renvoie l'albedo, la rugosite, une hauteur (relief, pour
// asphalt_bump) et le masque de flaque.

float a_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 a_hash2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float a_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(a_hash(i), a_hash(i + vec2(1.0, 0.0)), f.x),
		mix(a_hash(i + vec2(0.0, 1.0)), a_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float a_fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * a_noise(p);
		p = p * 2.03 + vec2(17.1, 9.7);
		a *= 0.5;
	}
	return v;
}

// 0 quand un motif de cette frequence (cycles par metre) est plus fin qu'un
// pixel : on le remplace par sa moyenne au lieu de le laisser scintiller.
float a_detail(vec2 p, float freq) {
	vec2 w = fwidth(p) * freq;
	return 1.0 - smoothstep(0.35, 0.9, max(w.x, w.y));
}

// Gravillons : cellules de 1 / freq m, un caillou clair dans certaines.
float a_stones(vec2 p, float freq, float density) {
	vec2 c = floor(p * freq);
	vec2 f = fract(p * freq);
	vec2 o = a_hash2(c) * 0.6 + 0.2;
	float d = length(f - o);
	float present = step(1.0 - density, a_hash(c + 13.7));
	return present * (1.0 - smoothstep(0.12, 0.32, d));
}

void asphalt_surface(vec2 p, float rw, float lane_count, float base_tone, float wet, float time,
		out vec3 albedo, out float rough, out float height, out float puddle) {
	// teinte de fond : plaques de 20 a 60 m, legerement chaudes ou froides
	float big = a_fbm(p * vec2(0.035, 0.012));
	float mid = a_fbm(p * 0.25);
	vec3 col = vec3(base_tone) * (0.82 + 0.36 * big) * (0.9 + 0.2 * mid);
	col *= mix(vec3(1.0, 0.98, 0.95), vec3(0.95, 0.97, 1.0), a_noise(p * 0.02));

	// gravillons (deux tailles), effaces au loin
	float k1 = a_detail(p, 9.0);
	float k2 = a_detail(p, 22.0);
	float st = a_stones(p, 9.0, 0.45) * k1 + a_stones(p + 3.3, 22.0, 0.55) * 0.7 * k2;
	float st_mean = 0.06 * (1.0 - k1) + 0.05 * (1.0 - k2);
	float stones = st + st_mean;
	col *= 1.0 + 0.55 * stones;
	float grain = a_noise(p * 6.0) * k1 + 0.5 * (1.0 - k1);
	col *= 0.92 + 0.16 * grain;

	// ornieres : deux bandes par voie (roues), gomme sombre et polie
	float lane_w = rw / lane_count;
	float lx = mod(p.x, lane_w) - lane_w * 0.5;
	float wander = (a_noise(vec2(p.y * 0.02, floor(p.x / lane_w))) - 0.5) * 0.6;
	float rut = 0.0;
	for (int side = -1; side <= 1; side += 2) {
		float d = abs(lx - float(side) * 1.0 - wander);
		rut = max(rut, 1.0 - smoothstep(0.25, 0.75, d));
	}
	rut *= 0.65 + 0.35 * a_noise(p * vec2(0.6, 0.05));
	col *= 1.0 - 0.2 * rut;
	// taches d'huile au milieu des voies
	float oil = smoothstep(0.62, 0.8, a_fbm(p * vec2(0.9, 0.25) + 7.0)) * (1.0 - smoothstep(0.3, 0.9, abs(lx - wander)));
	col *= 1.0 - 0.35 * oil;

	// rustines : rectangles de 3 x 8 m, une case sur six
	vec2 pc = floor(p / vec2(5.0, 14.0));
	vec2 pf = fract(p / vec2(5.0, 14.0));
	vec2 ps = a_hash2(pc + 41.0) * 0.35 + 0.35;
	vec2 pe = abs(pf - 0.5) - ps * 0.5;
	float patch = step(0.96, a_hash(pc + 5.1)) * (1.0 - smoothstep(-0.01, 0.0, max(pe.x, pe.y) + (a_noise(p * 1.5) - 0.5) * 0.04));
	col = mix(col, col * 0.86, patch);

	// fissures colmatees : isolignes d'un bruit, dans certaines zones
	float cn = a_fbm(p * 0.3 + 31.0);
	float cw = fwidth(cn) * 1.2 + 0.004;
	float crack = (1.0 - smoothstep(0.0, cw, abs(cn - 0.5))) * smoothstep(0.66, 0.8, a_noise(p * 0.03 + 3.0));
	col = mix(col, vec3(base_tone * 0.45), crack * 0.6);

	// salissures le long des murs (2,5 m)
	float edge = min(p.x, rw - p.x);
	float grime = 1.0 - smoothstep(0.3, 2.5 + 1.5 * a_noise(p * 0.2), edge);
	col *= 1.0 - 0.3 * grime;

	rough = mix(0.86, 0.95, grain) - 0.14 * rut - 0.2 * oil - 0.1 * patch;
	height = stones * 0.3 + grain * 0.2 - crack * 0.8 - rut * 0.15;

	// mouille : l'eau remplit d'abord les ornieres et les creux
	puddle = 0.0;
	if (wet > 0.0) {
		float low = a_fbm(p * vec2(0.12, 0.05) + 11.0);
		float pool = smoothstep(0.52, 0.6, low + rut * 0.22 + grime * 0.1);
		puddle = pool * wet;
		col *= mix(1.0, 0.55, wet);           // bitume mouille : plus sombre
		col *= 1.0 - 0.25 * puddle;
		rough = mix(rough, 0.4 - 0.15 * rut + 0.1 * stones, wet);
		rough = mix(rough, 0.03, puddle);
		height *= 1.0 - puddle;
		// gouttes : anneaux qui s'elargissent, cellules de 0,6 m, effaces au loin
		float kd = a_detail(p, 2.0);
		if (kd > 0.0) {
			vec2 c = floor(p / 0.6);
			vec2 f = fract(p / 0.6);
			vec2 o = a_hash2(c + 3.0) * 0.6 + 0.2;
			float t = fract(time * 1.3 + a_hash(c + 9.0));
			float r = t * 0.45;
			float ring = 1.0 - smoothstep(0.0, 0.04, abs(length(f - o) - r));
			height += ring * (1.0 - t) * 0.5 * kd * max(puddle, 0.15 * wet);
		}
	}
	albedo = col;
}

// Normale perturbee par une hauteur (bump mapping par derivees d'ecran,
// Mikkelsen 2010) : sans tangentes ni texture.
vec3 asphalt_bump(vec3 n, vec3 pos, float h, float strength) {
	vec3 dpdx = dFdx(pos);
	vec3 dpdy = dFdy(pos);
	float dhx = dFdx(h) * strength;
	float dhy = dFdy(h) * strength;
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	return normalize(abs(det) * n - grad);
}
