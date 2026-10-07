shader_type spatial;

// Carrosserie realiste des camions et remorques (TruckMaterials) : la matiere
// d'origine (couleur, metal, rugosite, vernis) vieillie par la route -
//   - boue et poussiere : epaisses au ras du sol, elles s'eclaircissent en
//     montant (projections des roues), en plaques irregulieres ;
//   - coulures verticales sous les aretes (pluie, lavage) ;
//   - poussiere fine sur les surfaces horizontales (toit, capot, plateau) ;
//   - pluie (truck_wetness) : tout est plus sombre et brillant, la boue
//     devient noire ;
//   - micro-relief (peau d'orange, grain, metal brosse) par bump mapping ;
//   - cicatrices des chocs (BodyScars, scar0..scar7) : peinture arrachee a
//     bord dechiquete (appret, tole nue rayee), eraflures et vernis terni
//     autour, tole froissee, suie au centre des gros chocs.
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
// cicatrices sur cette matiere (pneus : non)
uniform float scars = 1.0;

global uniform vec3 truck_grime_color;
global uniform float truck_wetness;

instance uniform vec4 height_row = vec4(0.0, 1.0, 0.0, 0.0);
// cicatrices (BodyScars) : centre (repere du maillage), w = gravite * 8 + rayon ;
// remplies dans l'ordre (scar0 vide : aucune)
instance uniform vec4 scar0 = vec4(0.0);
instance uniform vec4 scar1 = vec4(0.0);
instance uniform vec4 scar2 = vec4(0.0);
instance uniform vec4 scar3 = vec4(0.0);
instance uniform vec4 scar4 = vec4(0.0);
instance uniform vec4 scar5 = vec4(0.0);
instance uniform vec4 scar6 = vec4(0.0);
instance uniform vec4 scar7 = vec4(0.0);

varying vec3 obj_pos;
varying vec3 obj_n;
varying float h_ground;

void vertex() {
	obj_pos = VERTEX;
	obj_n = NORMAL;
	h_ground = dot(height_row.xyz, VERTEX) + height_row.w;
}

// gravite (0 .. 1) de la cicatrice `sc` au point p de normale n : disque au
// bord irregulier ; l'ecart le long de la normale compte peu (la tole touchee
// s'est enfoncee, le point de contact est sur la boite de collision)
float scar_at(vec4 sc, vec3 p, vec3 n, float wobble) {
	if (sc.w <= 0.0) {
		return 0.0;
	}
	float r = mod(sc.w, 8.0);
	float sev = floor(sc.w / 8.0) / 255.0;
	vec3 dv = p - sc.xyz;
	float dn = dot(dv, n);
	float d = sqrt(max(dot(dv, dv) - 0.85 * dn * dn, 0.0)) / r + (wobble - 0.5) * 0.45;
	return sev * (1.0 - smoothstep(0.2, 1.0, d));
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

	// cicatrices des chocs : peinture eraflee puis arrachee, tole nue rayee,
	// pliee, noircie
	float scar_h = 0.0;
	if (scar0.w > 0.0 && scars > 0.0) {
		float wob = tri(grime_tex, obj_pos * 2.3, obj_n, 0.35, vec2(1.0));
		vec3 nf = normalize(obj_n);
		float m = scar_at(scar0, obj_pos, nf, wob);
		m = max(m, scar_at(scar1, obj_pos, nf, wob));
		m = max(m, scar_at(scar2, obj_pos, nf, wob));
		m = max(m, scar_at(scar3, obj_pos, nf, wob));
		m = max(m, scar_at(scar4, obj_pos, nf, wob));
		m = max(m, scar_at(scar5, obj_pos, nf, wob));
		m = max(m, scar_at(scar6, obj_pos, nf, wob));
		m = max(m, scar_at(scar7, obj_pos, nf, wob));
		m *= scars;
		if (m > 0.001) {
			// repere du frottement, fixe (jamais la normale du pixel : sur une
			// face arrondie les rayures se tordraient) : hauteur, et l'un des
			// deux axes horizontaux du maillage selon la face (melange doux)
			vec3 up_obj = normalize(height_row.xyz + vec3(0.0, 1e-5, 0.0));
			vec3 h1 = abs(up_obj.x) < 0.9 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 0.0, 1.0);
			h1 = normalize(h1 - up_obj * dot(h1, up_obj));
			vec3 h2 = cross(up_obj, h1);
			float face2 = smoothstep(0.3, 0.7, abs(dot(nf, h1)) / (abs(dot(nf, h1)) + abs(dot(nf, h2)) + 1e-4));
			float along = mix(dot(obj_pos, h1), dot(obj_pos, h2), face2);
			float across = dot(obj_pos, up_obj);
			// rayures : lignes de niveau d'un bruit tres etire dans le sens du
			// frottement, fines et anti-crenelees
			float sn = texture(grime_tex, vec2(along * 0.06, across * 2.2)).r;
			float sn2 = texture(detail_tex, vec2(along * 0.03, across * 1.1)).r;
			float l1 = 1.0 - smoothstep(0.0, fwidth(sn) * 1.1 + 0.0015, abs(sn - 0.5));
			float l2 = 1.0 - smoothstep(0.0, fwidth(sn2) * 1.1 + 0.0015, abs(sn2 - 0.5));
			float lines = clamp(l1 + 0.5 * l2, 0.0, 1.0) * smoothstep(0.35, 0.6, texture(detail_tex, vec2(along * 0.15, across * 0.4)).r + 0.2);
			// traces noires laissees par l'autre (gomme, crasse), en trainees
			float smear = smoothstep(0.52, 0.7, texture(grime_tex, vec2(along * 0.1, across * 0.9)).r);
			// eclats de peinture : seuil bruite (bord dechiquete, 5 a 10 cm)
			float chip = tri(detail_tex, obj_pos, obj_n, 0.8, vec2(1.0)) * 0.7
				+ tri(detail_tex, obj_pos, obj_n, 2.6, vec2(1.0)) * 0.3;
			float bare = smoothstep(0.42, 0.46, m + (chip - 0.5) * 0.45);
			float scuff = smoothstep(0.02, 0.25, m);
			// autour : peinture eraflee, ternie, plus de vernis, traces noires
			col = mix(col, col * 0.8 + vec3(0.02), scuff * 0.6);
			col = mix(col, vec3(0.03), smear * scuff * (1.0 - bare) * 0.6);
			rough = mix(rough, 0.6, scuff * 0.8);
			coat *= 1.0 - scuff;
			// rayures fines sur la peinture : le metal apparait en filets
			float scratch = lines * smoothstep(0.08, 0.3, m) * (1.0 - bare);
			col = mix(col, vec3(0.3, 0.3, 0.31), scratch * 0.45);
			metal = mix(metal, 0.6, scratch * 0.45);
			rough = mix(rough, 0.45, scratch * 0.45);
			// coeur : appret gris mat et tole nue rayee, bord d'appret clair
			float edge = 1.0 - smoothstep(0.0, 0.12, m + (chip - 0.5) * 0.45 - 0.44);
			vec3 primer = mix(vec3(0.22, 0.22, 0.21), vec3(0.32, 0.31, 0.29), edge) * (0.85 + 0.3 * chip);
			float steel_amt = clamp(lines * 0.7 + smoothstep(0.6, 0.95, m) * 0.5, 0.0, 1.0);
			col = mix(col, mix(primer, vec3(0.5, 0.5, 0.51), steel_amt), bare);
			metal = mix(metal, steel_amt * 0.75, bare);
			rough = mix(rough, mix(0.75, 0.4, steel_amt), bare);
			// gros choc : suie et peinture brulee au centre
			float soot = smoothstep(0.62, 0.95, m) * (0.5 + 0.5 * wob);
			col = mix(col, vec3(0.025, 0.022, 0.02), soot * 0.85);
			rough = mix(rough, 0.85, soot * 0.8);
			metal *= 1.0 - soot * 0.8;
			// relief : ondulations de la tole froissee (les plis eux-memes sont
			// dans la geometrie, BodyDamage), sillons des rayures, marche de
			// l'epaisseur de peinture au bord des eclats
			float crease = tri(detail_tex, obj_pos, obj_n, 0.6, vec2(1.0));
			scar_h = (crease - 0.5) * 0.004 * smoothstep(0.15, 0.8, m)
				- (scratch + lines * bare) * 0.00015 - bare * 0.0003;
		}
	}

	ALBEDO = col;
	METALLIC = metal;
	ROUGHNESS = rough;
	SPECULAR = specular;
	CLEARCOAT = coat;
	CLEARCOAT_ROUGHNESS = clearcoat_roughness;
	EMISSION = emission * emission_energy;
	float h = detail * bump_strength * (1.0 - dirt * 0.5) + fine * 0.0006 * dirt + scar_h;
	NORMAL = bump(NORMAL, VERTEX, h);
}
