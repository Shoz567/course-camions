shader_type particles;

// Etincelles et braises (2026-10-08, particules) : jaillissent dans un cone,
// gardent une part de la vitesse de l'emetteur, tombent, rebondissent sur
// le sol et refroidissent (blanc-jaune -> orange -> rouge sombre). Le sol est
// un plan sous l'emetteur, perpendiculaire a son axe Y, a floor_below m : la
// route sous une jante, sous un moteur, sous une explosion. Chaque etincelle
// est etiree le long de sa vitesse par rapport a l'emetteur (le flou de
// mouvement vu d'une camera qui le suit) ; spark.gdshader la dessine.
// Purement visuel (alea du GPU, hors logique de jeu).

uniform vec3 direction = vec3(0.0, 1.0, 0.0);
// demi-angle du cone (rad)
uniform float spread = 0.6;
uniform float speed_min = 4.0;
uniform float speed_max = 9.0;
// part de la vitesse de l'emetteur gardee au depart
uniform float inherit = 0.9;
uniform vec3 box_extents = vec3(0.05);
uniform float gravity = 16.0;
uniform float drag = 0.8;
uniform float bounce = 0.35;
uniform float floor_below = 1000.0;
// duree de vie : de life_min a 1 fois LIFETIME
uniform float life_min = 0.5;
// trait : longueur = vitesse relative x stretch (s), bornee
uniform float stretch = 0.03;
uniform float max_len = 0.6;
uniform float width = 0.02;
// part de la vitesse de l'emetteur retiree pour le trait (1 : camion suivi)
uniform float streak_follow = 1.0;
uniform float heat = 5.0;
// couleurs : depart blanc-jaune, puis orange, fin rouge sombre
uniform vec3 hot_color = vec3(1.0, 0.85, 0.55);
uniform vec3 warm_color = vec3(1.0, 0.42, 0.08);
uniform vec3 cold_color = vec3(0.55, 0.06, 0.01);

float hash(uint x) {
	x ^= x >> 16u;
	x *= 0x7feb352du;
	x ^= x >> 15u;
	x *= 0x846ca68bu;
	x ^= x >> 16u;
	return float(x) / 4294967295.0;
}

void start() {
	uint s = NUMBER * 747796405u + RANDOM_SEED * 2891336453u + INDEX * 277803737u;
	if (RESTART_POSITION) {
		vec3 off = (vec3(hash(s), hash(s + 1u), hash(s + 2u)) * 2.0 - 1.0) * box_extents;
		// axe Y nul : process() lit la tete du trait en TRANSFORM[3] + Y/2
		TRANSFORM = mat4(vec4(1.0, 0.0, 0.0, 0.0), vec4(0.0), vec4(0.0, 0.0, 1.0, 0.0),
			vec4((EMISSION_TRANSFORM * vec4(off, 1.0)).xyz, 1.0));
	}
	if (RESTART_VELOCITY) {
		vec3 d = normalize(mat3(EMISSION_TRANSFORM) * direction);
		vec3 t = normalize(cross(d, abs(d.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
		vec3 b = cross(d, t);
		float a = hash(s + 3u) * 6.2831853;
		// uniforme sur la calotte du cone
		float c = mix(cos(spread), 1.0, hash(s + 4u));
		float sn = sqrt(max(1.0 - c * c, 0.0));
		vec3 dir = d * c + (t * cos(a) + b * sin(a)) * sn;
		VELOCITY = dir * mix(speed_min, speed_max, hash(s + 5u)) + EMITTER_VELOCITY * inherit;
	}
	CUSTOM = vec4(0.0, 0.0, mix(life_min, 1.0, hash(s + 6u)), hash(s + 7u));
}

void process() {
	CUSTOM.y += DELTA / max(LIFETIME * CUSTOM.z, 0.001);
	if (CUSTOM.y >= 1.0) {
		ACTIVE = false;
	}
	VELOCITY.y -= gravity * DELTA;
	VELOCITY -= VELOCITY * min(drag * DELTA, 1.0);
	vec3 pos = TRANSFORM[3].xyz + TRANSFORM[1].xyz * 0.5;
	// sol : rebond amorti, glissade freinee
	vec3 n = normalize(EMISSION_TRANSFORM[1].xyz);
	vec3 o = EMISSION_TRANSFORM[3].xyz - n * floor_below;
	float h = dot(pos + VELOCITY * DELTA - o, n);
	float vn = dot(VELOCITY, n);
	if (h < 0.0 && vn < 0.0) {
		VELOCITY -= n * vn * (1.0 + bounce);
		VELOCITY -= (VELOCITY - n * dot(VELOCITY, n)) * 0.25;
		pos -= n * min(dot(pos - o, n), 0.0);
	}
	// trait le long de la vitesse relative, la tete en avant : TRANSFORM
	// garde le milieu du trait, la tete (la vraie position) est a +Y/2
	vec3 rel = VELOCITY - EMITTER_VELOCITY * streak_follow;
	float sp = length(rel);
	vec3 axis = sp > 0.01 ? rel / sp : n;
	float t = CUSTOM.y;
	float w = width * (1.0 - 0.4 * t);
	float len = clamp(sp * stretch, w * 2.0, max_len);
	vec3 side = normalize(cross(axis, abs(axis.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
	vec3 up2 = cross(side, axis);
	TRANSFORM = mat4(vec4(side * w, 0.0), vec4(axis * len, 0.0), vec4(up2 * w, 0.0),
		vec4(pos - axis * len * 0.5, 1.0));
	// refroidissement, scintillement
	vec3 c = mix(hot_color, warm_color, smoothstep(0.05, 0.45, t));
	c = mix(c, cold_color, smoothstep(0.45, 1.0, t));
	float flick = 0.7 + 0.3 * sin(TIME * 55.0 + CUSTOM.w * 40.0);
	COLOR = vec4(c * heat * (1.0 - smoothstep(0.65, 1.0, t)) * flick, 1.0);
}
