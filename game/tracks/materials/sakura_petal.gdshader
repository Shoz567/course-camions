shader_type spatial;
render_mode cull_disabled, shadows_disabled, depth_draw_opaque;

// Petale de cerisier qui vole (SakuraPetals) : petite ellipse a pointe
// echancree, blanc rose au pied, rose au bout. Elle tournoie : le quad
// bascule sur son axe long (flutter, phase propre a chaque particule) en plus
// de la rotation de la particule ; la lumiere la traverse (contre-jour).
// Fondu pres de l'objectif et au loin.

uniform vec3 pink : source_color = vec3(0.98, 0.66, 0.78);
uniform vec3 pale : source_color = vec3(1.0, 0.93, 0.95);

varying float v_tone;

// hachage sans sinus (un sin() de grand argument fait des motifs sur GPU)
float hash1(float n) {
	vec3 p3 = fract(vec3(n) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	float id = float(INSTANCE_ID);
	float ph = hash1(id) * 6.2831;
	v_tone = hash1(id + 7.0);
	// bascule autour de l'axe long (x) : le petale montre sa tranche puis sa face
	float a = sin(TIME * (2.2 + 1.6 * hash1(id + 3.0)) + ph) * 1.3;
	VERTEX = vec3(VERTEX.x, VERTEX.y * cos(a), VERTEX.y * sin(a));
	NORMAL = vec3(0.0, -sin(a), cos(a));
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	// ellipse allongee en x, echancrure a la pointe (x = 1)
	float e = length(q / vec2(1.0, 0.62));
	float notch = 1.0 - smoothstep(0.0, 0.22, length(q - vec2(1.0, 0.0)));
	float shape = (1.0 - step(1.0, e)) * (1.0 - step(0.5, notch));
	if (shape < 0.5) {
		discard;
	}
	float dist = -VERTEX.z;
	vec3 col = mix(pale, pink, smoothstep(-0.8, 0.9, q.x) * (0.6 + 0.4 * v_tone));
	ALBEDO = col;
	ROUGHNESS = 0.6;
	BACKLIGHT = col * 0.6;
	EMISSION = col * 0.12;
	// fondu de l'objectif et du lointain : les rares petales tout pres ne
	// barrent pas l'ecran
	float fade = smoothstep(0.8, 2.5, dist) * (1.0 - smoothstep(45.0, 60.0, dist));
	if (fade < hash2(FRAGCOORD.xy)) {
		discard;
	}
}
