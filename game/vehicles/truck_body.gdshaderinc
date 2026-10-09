// Inclus par truck_body.gdshader (carrosserie) et truck_body_hollow.gdshader
// (coque creuse des remorques, HOLLOW : trous au coeur des chocs graves,
// interieur de la coque visible).
//
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
// relief de la matiere (2026-10-07, « plus lisses et realistes, avec du
// relief ») : 0 aucun, 1 tole ondulee (conteneur), 2 sculptures de pneu,
// 3 viroles soudees (citerne), 4 lames nervurees (betaillere), 5 bache ;
// tete du camion (2026-10-09, « les textures avec plus de relief ») :
// 6 tole larmee (marchepieds, plateau), 7 tole perforee (pare-chaleur),
// 8 nid d'abeille (calandre, prise d'air), 9 longeron perce et boulonne.
// Pas et profondeur en metres ; axes par maillage (relief_axis, relief_center,
// poses par TruckMaterials.upgrade).
uniform int relief = 0;
uniform float relief_pitch = 0.28;
uniform float relief_depth = 0.03;

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
// relief : axe principal du maillage (unitaire ; w : rayon exterieur d'un
// pneu) et centre (pneu : axe de la roue)
instance uniform vec4 relief_axis = vec4(0.0);
instance uniform vec4 relief_center = vec4(0.0);
// pneu eclate (TruckVisual.set_tyre_burst) : ecrasement en fraction du rayon
// (0 : neuf). Le bas du pneu, toujours vers le sol meme quand la roue tourne,
// s'aplatit et ses flancs gonflent ; la gomme est dechiree.
instance uniform float tyre_burst = 0.0;
// cote creve d'un maillage d'essieu entier (remorque : les deux pneus dans un
// maillage) : 0 tout le maillage, 1 / -1 seulement le cote x > 0 / x < 0 le
// long de relief_axis
instance uniform float tyre_side = 0.0;

varying vec3 obj_pos;
varying vec3 obj_n;
varying float h_ground;

// Fut de la jante, en fraction du rayon du pneu (modeles du tracteur et
// catalogue des remorques ; TruckTires.RIM_RATIO).
const float RIM_RATIO = 0.6;

void vertex() {
	obj_pos = VERTEX;
	obj_n = NORMAL;
	h_ground = dot(height_row.xyz, VERTEX) + height_row.w;
	vec3 ax = normalize(relief_axis.xyz + vec3(1e-6));
	vec3 d = VERTEX - relief_center.xyz;
	float burst = tyre_burst * (tyre_side == 0.0 ? 1.0 : step(0.0, dot(d, ax) * tyre_side));
	if (relief == 2 && burst > 0.0 && relief_axis.w > 0.0) {
		// pneu explose (2026-10-08 : « qu'on voie vraiment la jante », « pas
		// de debris de pneu sur les roues, la gomme explose ») : la gomme est
		// partie en morceaux (TruckTires), plus rien sur la roue - le maillage
		// du pneu se reduit a un point (aucun triangle dessine) ; la jante a
		// nu pose sur la route (TruckVisual, FLAT_TYRE)
		VERTEX = relief_center.xyz;
	}
}

// tirage fixe (0 .. 1) propre a une cicatrice, d'apres son centre
float scar_hash(vec3 c) {
	return fract(sin(dot(c, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

// Forme d'un choc (2026-10-07 : « des ronds trop parfaits, pas realiste ») :
// distance au centre de la cicatrice `sc`, dans le plan de la paroi (normale
// n, haut up), rapportee a son rayon (1 = bord). Un ovale couche (le camion
// glisse le long de ce qu'il touche, la trace s'etire a l'horizontale), au
// bord lobe ; allongement et lobes tires d'apres le centre, propres a chaque
// choc. dn : ecart le long de la normale. th : angle autour du centre.
float scar_dist(vec4 sc, vec3 p, vec3 n, vec3 up, out float dn, out float th) {
	float r = mod(sc.w, 8.0);
	vec3 dv = p - sc.xyz;
	dn = dot(dv, n);
	vec3 t1 = cross(up, n);
	float l = dot(t1, t1);
	// toit, plancher : l'axe de la caisse
	t1 = l > 1e-3 ? t1 * inversesqrt(l) : normalize(cross(vec3(1.0, 0.0, 0.0), n) + vec3(0.0, 0.0, 1e-5));
	vec3 t2 = cross(n, t1);
	float h = scar_hash(sc.xyz);
	float a = dot(dv, t1) / (1.2 + 0.55 * h);
	float b = dot(dv, t2) / (0.9 + 0.2 * fract(h * 7.0));
	th = atan(b, a);
	float lobe = 1.0 + 0.2 * sin(2.0 * th + h * 6.28) + 0.13 * sin(3.0 * th + h * 19.0)
		+ 0.07 * sin(5.0 * th + h * 37.0);
	return sqrt(a * a + b * b) / (r * lobe);
}

// gravite (0 .. 1) de la cicatrice `sc` au point p de normale n : tache de
// forme irreguliere (scar_dist), bord ronge (wobble) ; l'ecart le long de la
// normale compte peu (la tole touchee s'est enfoncee, le point de contact est
// sur la boite de collision)
float scar_at(vec4 sc, vec3 p, vec3 n, vec3 up, float wobble) {
	if (sc.w <= 0.0) {
		return 0.0;
	}
	float sev = floor(sc.w / 8.0) / 255.0;
	float dn;
	float th;
	float d = scar_dist(sc, p, n, up, dn, th);
	d = sqrt(d * d + 0.15 * dn * dn / (mod(sc.w, 8.0) * mod(sc.w, 8.0))) + (wobble - 0.5) * 0.45;
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


// Trous et larmes de la tete (reliefs 6 a 9) au point p, normale n : hauteur
// (m), creux (0 .. 1) et trou (0 .. 1 : on voit le noir derriere la tole).
// Repere : `a1` le long de la piece (relief_axis), `up` le haut ; centre de
// la piece en relief_center. Au loin (une maille sous ~4 pixels), le motif
// s'efface vers sa teinte moyenne (pas de crenelage).
vec2 head_relief(vec3 p, vec3 n, vec3 up, vec3 axis, out float hole) {
	hole = 0.0;
	float upn = dot(n, up);
	if (relief == 6) {
		// tole larmee : larmes allongees a 45 degres, alternees d'une case a
		// l'autre, sur les faces du dessus seulement
		if (upn < 0.6) {
			return vec2(0.0);
		}
		vec3 a1 = normalize(axis - up * dot(axis, up) + vec3(1e-5));
		vec3 a2 = cross(up, a1);
		vec2 q = vec2(dot(p, a1), dot(p, a2)) / relief_pitch;
		vec2 f = fract(q) - 0.5;
		vec2 cell = floor(q);
		float flip = mod(cell.x + cell.y, 2.0) < 0.5 ? 1.0 : -1.0;
		vec2 r = vec2(f.x + flip * f.y, f.y - flip * f.x) * 0.7071;
		float e = length(r / vec2(0.36, 0.11));
		float tear = 1.0 - smoothstep(0.55, 1.0, e);
		float fade = (1.0 - smoothstep(0.12, 0.3, fwidth(q.x))) * smoothstep(0.6, 0.8, upn);
		return vec2(tear * relief_depth * fade, (0.35 - tear * 0.6) * fade);
	}
	vec3 d = p - relief_center.xyz;
	vec2 q;
	float rad;
	if (relief == 7) {
		// pare-chaleur : tole roulee autour du pot, trous en quinconce
		// (coordonnees cylindriques autour de l'axe vertical de la piece)
		vec3 hz = d - up * dot(d, up);
		float rr = max(length(hz), 0.02);
		vec3 a1 = normalize(axis - up * dot(axis, up) + vec3(1e-5));
		float ang = atan(dot(hz, cross(up, a1)), dot(hz, a1));
		q = vec2(ang * rr, dot(d, up)) / relief_pitch;
		q.x += mod(floor(q.y), 2.0) * 0.5;
		rad = 0.3;
	} else if (relief == 8) {
		// nid d'abeille : alveoles hexagonales, faces avant et cotes
		if (abs(upn) > 0.5) {
			return vec2(0.0);
		}
		vec3 a1 = normalize(cross(up, n) + vec3(1e-5));
		q = vec2(dot(p, a1), dot(p, up)) / relief_pitch;
		vec2 s = vec2(1.0, 1.7320508);
		vec2 ga = mod(q, s) - s * 0.5;
		vec2 gb = mod(q - s * 0.5, s) - s * 0.5;
		vec2 g = dot(ga, ga) < dot(gb, gb) ? ga : gb;
		vec2 ag = abs(g);
		float hx = max(dot(ag, vec2(0.5, 0.8660254)), ag.x);
		float cellh = 1.0 - smoothstep(0.38, 0.44, hx);
		float fade = 1.0 - smoothstep(0.12, 0.3, fwidth(q.x));
		hole = mix(0.62, cellh, fade);
		return vec2(-cellh * relief_depth * fade, hole * 0.4);
	} else {
		// longeron : rangees de trous (gabarit de percage du chassis), par
		// groupes irreguliers, et quelques boulons a tete ronde ; flancs
		// verticaux seulement
		vec3 a1 = normalize(axis - up * dot(axis, up) + vec3(1e-5));
		if (abs(upn) > 0.4 || abs(dot(n, a1)) > 0.5) {
			return vec2(0.0);
		}
		q = vec2(dot(d, a1), dot(d, up)) / relief_pitch;
		// deux rangees, au-dessus et au-dessous de l'axe du longeron
		if (abs(q.y) > 1.0) {
			return vec2(0.0);
		}
		rad = 0.17;
	}
	vec2 cell = floor(q);
	vec2 f = fract(q) - 0.5;
	float dist = length(f);
	float bolt = 0.0;
	float present = 1.0;
	if (relief == 9) {
		float hsh = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
		present = step(0.3, hsh);
		bolt = step(0.86, hsh);
	}
	float fade = 1.0 - smoothstep(0.12, 0.3, fwidth(q.x));
	float disk = 1.0 - smoothstep(rad * 0.75, rad, dist);
	float avg = 3.1416 * rad * rad * 0.8 * (relief == 9 ? 0.55 : 1.0);
	hole = mix(avg, disk * present * (1.0 - bolt), fade);
	// tete de boulon : dome, plus large que le trou
	float dome = bolt * present * (1.0 - smoothstep(rad * 0.9, rad * 1.5, dist)) * fade;
	return vec2((dome * 0.6 - hole * 0.4) * relief_depth, hole * 0.5 - dome * 0.3);
}


// Relief de la matiere au point p (repere du maillage), normale n : hauteur
// (m, a ajouter au bump) et creux (0 .. 1, assombri et sali) ; `hole` : trou
// (reliefs de la tete, head_relief).
vec2 relief_at(vec3 p, vec3 n, vec3 up, out float hole) {
	hole = 0.0;
	vec3 axis = relief_axis.xyz;
	if (relief == 0 || dot(axis, axis) < 0.5) {
		return vec2(0.0);
	}
	if (relief >= 6) {
		return head_relief(p, n, up, axis, hole);
	}
	float h = 0.0;
	if (relief == 1 || relief == 4) {
		// tole ondulee : trapezes verticaux le long de la caisse (et en travers
		// sur les faces avant et arriere) ; toit : ondes larges et plates.
		// lames nervurees : arrondis horizontaux sur les flancs.
		float up_n = abs(dot(n, up));
		vec3 side = normalize(cross(up, axis));
		float s;
		float pitch = relief_pitch;
		float depth = relief_depth;
		if (relief == 4) {
			if (up_n > 0.5) {
				return vec2(0.0);
			}
			s = dot(p, up);
		} else if (up_n > 0.7) {
			s = dot(p, axis);
			pitch *= 2.2;
			depth *= 0.4;
		} else if (up_n < 0.35) {
			s = abs(dot(n, axis)) > 0.7 ? dot(p, side) : dot(p, axis);
		} else {
			return vec2(0.0);
		}
		float u = s / pitch;
		// au loin, une onde tient dans moins de 6 pixels : effacee (crenelage)
		float fade = 1.0 - smoothstep(0.05, 0.16, fwidth(u));
		float f = fract(u);
		float prof;
		if (relief == 4) {
			prof = 0.5 + 0.5 * cos(f * 6.2832);
		} else {
			// crete 0 .. 0,3, flanc, creux 0,5 .. 0,8, flanc
			prof = 1.0 - smoothstep(0.3, 0.5, f) + smoothstep(0.8, 1.0, f);
		}
		h = prof * depth * fade;
		return vec2(h, (1.0 - prof) * fade * (relief == 4 ? 0.5 : 1.0));
	}
	if (relief == 2) {
		// pneu : bande de roulement (rainures en zigzag, lamelles en
		// quinconce), flanc a peine nervure
		vec3 d = p - relief_center.xyz;
		float x = dot(d, axis);
		vec3 rv = d - axis * x;
		float r = length(rv);
		float rad = relief_axis.w;
		if (rad <= 0.0) {
			return vec2(0.0);
		}
		float tread = (1.0 - smoothstep(0.35, 0.6, abs(dot(n, axis)))) * smoothstep(0.86, 0.94, r / rad);
		vec3 b1 = normalize(cross(axis, abs(axis.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
		vec3 b2 = cross(axis, b1);
		float c = atan(dot(rv, b1), dot(rv, b2)) * rad;
		float zig = (abs(fract(c / 0.055) - 0.5) * 2.0 - 0.5) * 0.012;
		float gx = (x + zig) / relief_pitch;
		float row = floor(gx);
		float groove = 1.0 - smoothstep(0.1, 0.18, abs(fract(gx) - 0.5));
		float sipe = 1.0 - smoothstep(0.05, 0.12, abs(fract(c / 0.05 + row * 0.5) - 0.5));
		float fade = 1.0 - smoothstep(0.08, 0.25, fwidth(c / 0.05));
		float cut = max(groove, sipe * 0.6) * tread * fade;
		// flanc : anneaux concentriques fins
		float wall = smoothstep(0.6, 0.8, abs(dot(n, axis))) * (1.0 - smoothstep(0.15, 0.4, fwidth(r / 0.012)));
		float ring = (0.5 + 0.5 * cos(r / 0.012 * 6.2832)) * wall * smoothstep(0.6, 0.7, r / rad)
			* (1.0 - smoothstep(0.82, 0.88, r / rad));
		return vec2(-cut * relief_depth + ring * 0.0008, cut);
	}
	if (relief == 3) {
		// citerne : cordon de soudure entre deux viroles, tous les relief_pitch
		if (abs(dot(n, axis)) > 0.5) {
			return vec2(0.0);
		}
		float s = dot(p, axis);
		float dist = (fract(s / relief_pitch + 0.5) - 0.5) * relief_pitch;
		float bead = exp(-dist * dist / (0.009 * 0.009));
		float fade = 1.0 - smoothstep(0.2, 0.5, fwidth(s / 0.02));
		return vec2(bead * relief_depth * fade, -bead * 0.6 * fade);
	}
	// bache : plis verticaux irreguliers et sangles tendues
	float s = dot(p, axis);
	float fold = sin(s / relief_pitch * 6.2832 + sin(dot(p, up) * 1.7) * 1.4);
	float strap = 1.0 - smoothstep(0.02, 0.035, abs(fract(s / (relief_pitch * 3.0)) - 0.5) * relief_pitch * 3.0);
	float fade = 1.0 - smoothstep(0.2, 0.5, fwidth(s / relief_pitch));
	return vec2((fold * 0.5 + 0.5) * relief_depth * fade + strap * 0.004, (0.5 - 0.5 * fold) * 0.6 * fade);
}

#ifdef HOLLOW
// Seuil de la gravite locale au-dela duquel la coque est percee : la tole
// s'enfonce d'abord (BodyDamage), seuls les chocs tres violents ou repetes
// au meme endroit (BodyScars les aggrave) finissent par la dechirer.
const float HOLE_AT = 0.74;

// gravite de la cicatrice `sc` au point p (normale n) pour la dechirure :
// meme forme que scar_at, dans le plan de la paroi - la tole enfoncee par
// les coups repetes (BodyDamage) s'eloigne du point d'impact, elle doit
// pouvoir se dechirer - mais rien au-dela de HOLE_DEPTH le long de la
// normale : la paroi d'en face, a 3 m, n'est jamais percee par le meme choc.
// La tole percee se fend en etoile : quelques fentes etroites partent du
// trou, a des angles propres a chaque choc.
const float HOLE_DEPTH = 1.2;

float hole_at(vec4 sc, vec3 p, vec3 n, vec3 up) {
	if (sc.w <= 0.0) {
		return 0.0;
	}
	float sev = floor(sc.w / 8.0) / 255.0;
	float dn;
	float th;
	float d = scar_dist(sc, p, n, up, dn, th);
	float h = scar_hash(sc.xyz + vec3(3.1));
	// fentes : jusqu'a ~1,6 fois le rayon du trou, pas plus (la tole voisine
	// tient)
	float rays = pow(max(sin(3.0 * th + h * 6.28), 0.0), 14.0) * 0.28
		+ pow(max(sin(5.0 * th + h * 23.0), 0.0), 22.0) * 0.16;
	d *= 1.0 - rays * smoothstep(0.85, 1.0, sev);
	return sev * (1.0 - smoothstep(0.1, 1.0, d)) * (1.0 - smoothstep(HOLE_DEPTH * 0.7, HOLE_DEPTH, abs(dn)));
}
#endif

void fragment() {
	vec3 col = albedo.rgb;
	float rough = roughness;
	float metal = metallic;
	float coat = clearcoat;
#ifdef HOLLOW
	// trou : bord dechiquete (bruit), tole dechiree autour ; l'interieur de la
	// coque (faces arriere) est un appret sombre, sans salissure ni relief
	float tear = 0.0;
	float lip = 0.0;
	if (scar0.w > 0.0 && scars > 0.0) {
		vec3 hn = normalize(obj_n);
		vec3 hu = normalize(height_row.xyz + vec3(0.0, 1e-5, 0.0));
		float hm = max(max(max(hole_at(scar0, obj_pos, hn, hu), hole_at(scar1, obj_pos, hn, hu)),
			max(hole_at(scar2, obj_pos, hn, hu), hole_at(scar3, obj_pos, hn, hu))),
			max(max(hole_at(scar4, obj_pos, hn, hu), hole_at(scar5, obj_pos, hn, hu)),
			max(hole_at(scar6, obj_pos, hn, hu), hole_at(scar7, obj_pos, hn, hu))));
		// bord dechire : grandes echancrures (bruit lent), dents de tole
		// arrachee (bruit fin, etire en travers des ondes)
		float jag = tri(grime_tex, obj_pos * 1.4, obj_n, 0.6, vec2(1.0)) * 0.55
			+ tri(detail_tex, obj_pos, obj_n, 1.6, vec2(1.0)) * 0.3
			+ tri(detail_tex, obj_pos, obj_n, 7.0, vec2(1.0, 0.35)) * 0.15;
		float v = hm * scars + (jag - 0.5) * 0.55;
		if (v > HOLE_AT) {
			discard;
		}
		tear = smoothstep(HOLE_AT - 0.06, HOLE_AT, v);
		lip = smoothstep(HOLE_AT - 0.14, HOLE_AT - 0.07, v) * (1.0 - tear);
	}
#endif
	float detail = tri(detail_tex, obj_pos, obj_n, detail_scale, detail_stretch);
	rough = clamp(rough + (detail - 0.5) * rough_variation, 0.02, 1.0);

	// relief de la matiere : ondes, sculptures, soudures ; la crasse se loge
	// dans les creux
	vec3 up_m = normalize(height_row.xyz + vec3(0.0, 1e-5, 0.0));
	float hole;
	vec2 rel = relief_at(obj_pos, normalize(obj_n), up_m, hole);
	col *= 1.0 - 0.1 * max(rel.y, 0.0);
	col = mix(col, col * 1.08, max(-rel.y, 0.0));
	// trou dans la tole : le noir de derriere, mat
	col = mix(col, vec3(0.012), hole * 0.9);
	rough = mix(rough, 0.95, hole);
	metal *= 1.0 - hole;
	coat *= 1.0 - hole;

	// salissure : basse, en plaques ; coulures ; poussiere sur le dessus
	float patches = tri(grime_tex, obj_pos, obj_n, 0.35, vec2(1.0));
	float fine = tri(grime_tex, obj_pos * 3.1, obj_n, 0.35, vec2(1.0));
	float low = (1.0 - smoothstep(0.05, 1.3, h_ground + (patches - 0.5) * 0.4)) * 0.75;
	vec3 n_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float vertical = 1.0 - abs(n_world.y);
	float streak = smoothstep(0.6, 0.9, tri(grime_tex, obj_pos * vec3(3.5, 0.3, 3.5), obj_n, 0.35, vec2(1.0)))
		* vertical * 0.12;
	// poussiere sur le dessus et voile d'usure : un film presque uniforme au
	// grain fin. Sur les grandes plaques (3 m), mat et brillant alternaient en
	// nuages : un camouflage sur les toits et les toles d'alu.
	float top = smoothstep(0.6, 0.95, n_world.y) * (0.16 + 0.06 * smoothstep(0.3, 0.8, fine));
	// voile d'usure general, leger : rien n'est neuf
	float age = 0.09 + 0.03 * smoothstep(0.4, 0.8, fine);
	float dirt = clamp((low * (0.8 + 0.25 * fine) + streak + top + age + max(rel.y, 0.0) * 0.25) * grime, 0.0, 1.0);
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
		float m = scar_at(scar0, obj_pos, nf, up_m, wob);
		m = max(m, scar_at(scar1, obj_pos, nf, up_m, wob));
		m = max(m, scar_at(scar2, obj_pos, nf, up_m, wob));
		m = max(m, scar_at(scar3, obj_pos, nf, up_m, wob));
		m = max(m, scar_at(scar4, obj_pos, nf, up_m, wob));
		m = max(m, scar_at(scar5, obj_pos, nf, up_m, wob));
		m = max(m, scar_at(scar6, obj_pos, nf, up_m, wob));
		m = max(m, scar_at(scar7, obj_pos, nf, up_m, wob));
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

#ifdef HOLLOW
	// bord du trou : tole nue arrachee (levre claire), puis noircie et
	// tordue au ras de la dechirure
	col = mix(col, vec3(0.42, 0.42, 0.43), lip * 0.8);
	metal = mix(metal, 0.7, lip * 0.8);
	rough = mix(rough, 0.45, lip * 0.8);
	col = mix(col, vec3(0.035, 0.032, 0.03), tear);
	rough = mix(rough, 0.8, tear);
	metal *= 1.0 - tear * 0.7;
	scar_h += (lip - tear) * 0.006;
#endif
	ALBEDO = col;
	METALLIC = metal;
	ROUGHNESS = rough;
	SPECULAR = specular;
	CLEARCOAT = coat;
	CLEARCOAT_ROUGHNESS = clearcoat_roughness;
	EMISSION = emission * emission_energy;
	float h = detail * bump_strength * (1.0 - dirt * 0.5) + fine * 0.0006 * dirt + scar_h + rel.x;
#ifdef HOLLOW
	// interieur de la coque (faces arriere, vues par un trou) : appret sombre,
	// sans salissure, sans relief, sans vernis
	if (!FRONT_FACING) {
		ALBEDO = vec3(0.075, 0.073, 0.07) * (0.75 + 0.5 * detail);
		METALLIC = 0.15;
		ROUGHNESS = 0.85;
		SPECULAR = 0.3;
		CLEARCOAT = 0.0;
		EMISSION = vec3(0.0);
		h = 0.0;
	}
#endif
	NORMAL = bump(NORMAL, VERTEX, h);
}
