shader_type spatial;

// Carrosserie realiste des camions et remorques (TruckMaterials) : la matiere
// d'origine (couleur, metal, rugosite, vernis) vieillie par la route -
//   - boue et poussiere : epaisses au ras du sol, elles s'eclaircissent en
//     montant (projections des roues), en plaques irregulieres ;
//   - coulures verticales sous les aretes (pluie, lavage) ;
//   - poussiere fine sur les surfaces horizontales (toit, capot, plateau) ;
//   - pluie (truck_wetness) : tout est plus sombre et brillant, la boue
//     devient noire ;
//   - micro-relief (peau d'orange, grain, metal brosse) par bump mapping.
// Couleur de la salissure et pluie : parametres globaux du circuit
// (truck_grime_color, truck_wetness, LocalRace). Hauteur au-dessus du sol :
// height_row, pose par maillage (repere du camion, sol a 0).

uniform vec4 albedo : source_color = vec4(1.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.5;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
uniform float clearcoat : hint_range(0.0, 1.0) = 0.0;
uniform float clearcoat_roughness : hint_range(0.0, 1.0) = 0.05;
uniform vec3 emission : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
// relief : bruit (R) plaque en triplanaire dans le repere de l'objet
uniform sampler2D detail_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float detail_scale = 2.0;
uniform vec2 detail_stretch = vec2(1.0, 1.0);
uniform float bump_strength = 0.0;
// variation de rugosite (0 : uniforme)
uniform float rough_variation = 0.2;
// quantite de salissure de cette matiere (pneus, chassis : beaucoup)
uniform float grime = 1.0;
uniform sampler2D grime_tex : filter_linear_mipmap_anisotropic, repeat_enable;

global uniform vec3 truck_grime_color;
global uniform float truck_wetness;

instance uniform vec4 height_row = vec4(0.0, 1.0, 0.0, 0.0);

varying vec3 obj_pos;
varying vec3 obj_n;
varying float h_ground;

void vertex() {
	obj_pos = VERTEX;
	obj_n = NORMAL;
	h_ground = dot(height_row.xyz, VERTEX) + height_row.w;
}

float tri(sampler2D t, vec3 p, vec3 n, float scale, vec2 stretch) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z + 1e-5);
	float a = texture(t, p.zy * scale * stretch).r;
	float b = texture(t, p.xz * scale * stretch.yx).r;
	float c = texture(t, p.xy * scale * stretch).r;
	return a * w.x + b * w.y + c * w.z;
}

vec3 bump(vec3 n, vec3 pos, float h) {
	vec3 dpdx = dFdx(pos);
	vec3 dpdy = dFdy(pos);
	float dhx = dFdx(h);
	float dhy = dFdy(h);
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	return normalize(abs(det) * n - grad);
}

void fragment() {
	vec3 col = albedo.rgb;
	float rough = roughness;
	float metal = metallic;
	float coat = clearcoat;
	float detail = tri(detail_tex, obj_pos, obj_n, detail_scale, detail_stretch);
	rough = clamp(rough + (detail - 0.5) * rough_variation, 0.02, 1.0);

	// salissure : basse, en plaques ; coulures ; poussiere sur le dessus
	float patches = tri(grime_tex, obj_pos, obj_n, 0.35, vec2(1.0));
	float fine = tri(grime_tex, obj_pos * 3.1, obj_n, 0.35, vec2(1.0));
	float low = (1.0 - smoothstep(0.05, 1.3, h_ground + (patches - 0.5) * 0.4)) * 0.75;
	vec3 n_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float vertical = 1.0 - abs(n_world.y);
	float streak = smoothstep(0.6, 0.9, tri(grime_tex, obj_pos * vec3(3.5, 0.3, 3.5), obj_n, 0.35, vec2(1.0)))
		* vertical * 0.12;
	float top = smoothstep(0.6, 0.95, n_world.y) * smoothstep(0.35, 0.75, patches) * 0.35;
	// voile d'usure general, leger : rien n'est neuf
	float age = 0.08 + 0.1 * smoothstep(0.4, 0.8, patches);
	float dirt = clamp((low * (0.8 + 0.25 * fine) + streak + top + age) * grime, 0.0, 1.0);
	float wet = truck_wetness;
	vec3 grime_col = mix(truck_grime_color, truck_grime_color * 0.35, wet) * (0.9 + 0.2 * fine);
	col = mix(col, grime_col, dirt * 0.6);
	rough = mix(rough, 0.92, dirt);
	metal *= 1.0 - dirt * 0.8;
	coat *= 1.0 - dirt;

	// pluie : la matiere s'assombrit et brille (film d'eau)
	col *= mix(1.0, 0.72, wet * (0.4 + 0.6 * dirt));
	rough = mix(rough, rough * 0.35, wet);
	coat = max(coat, wet * 0.6);

	ALBEDO = col;
	METALLIC = metal;
	ROUGHNESS = rough;
	SPECULAR = specular;
	CLEARCOAT = coat;
	CLEARCOAT_ROUGHNESS = clearcoat_roughness;
	EMISSION = emission * emission_energy;
	float h = detail * bump_strength * (1.0 - dirt * 0.5) + fine * 0.0006 * dirt;
	NORMAL = bump(NORMAL, VERTEX, h);
}
