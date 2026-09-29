@tool
class_name TrackBlockout
extends Node3D

## Piste de blockout generee a partir d'une liste de segments (tache 2.2).
##
## Le trace est une suite de droites et d'arcs de rayon choisi : chaque rayon se
## derive des metriques mesurees (baseline.json, docs/METRICS.md). Deux droites
## marquees "auto" voient leur longueur CALCULEE pour que la boucle se referme
## exactement : on peut modifier un virage sans recoudre le trace a la main.
##
## Segment (Dictionary) :
##   {"type": "straight", "length": m}           ou  {"type": "straight", "auto": true}
##   {"type": "arc", "radius": m, "angle": deg}  (angle > 0 : a gauche)
## Options de segment :
##   "bank": deg    devers : > 0 leve le bord DROIT (virage a gauche releve,
##                  ou virage a droite en devers inverse). Raccord progressif
##                  sur bank_blend_length. La chaussee pivote sur son bord BAS :
##                  il reste a la hauteur du trace, jamais sous le sol.
##   "climb": m     denivele sur le segment. Par defaut, raccord en S sur le
##                  segment (plat a ses deux bouts). Avec climb_blend_length > 0 :
##                  pente constante sur le segment, raccords lisses sur toute la
##                  boucle (plusieurs segments enchaines font une seule longue
##                  cote ou descente ; crêtes et creux sur climb_blend_length).
##   "line": m      decalage lateral de la ligne de course (> 0 a droite).
##   "jump": m      rampe de saut a cette distance du debut du segment ;
##   "jump_offset": m  son decalage lateral (defaut : jump_offset).
##   "boost": [[m, lateral], ...]  plaques de boost (distance, decalage).
##   "puddle": [[m, lateral, rayon], ...]  flaques d'eau (ralentissement).
##   "signs": [[m, lateral], ...]  panneaux ejectables (vitesse / 2).
##   "arch": m      arche lumineuse au-dessus de la piste a cette distance ;
##   "arch_label": texte de son enseigne.
##
## Genere : Geometry (chaussee, sol), Walls (2 glissieres continues, bord haut
## en neon : cyan a gauche, magenta a droite), Arches (portiques neon), Pads
## (plaques de boost et rampes de saut a chevrons lumineux, avec leur Area3D),
## ResetZones (Area3D au-dela des murs, tout autour), Checkpoints (Area3D
## ordonnees, la n°0 est la ligne d'arrivee), StartGrid, RacingLine.
##
## La piste ne decide rien (track-designer.md) : elle EMET un signal quand un
## camion entre dans une zone de reset ou en sort ; le gameplay (AutoReset,
## puis RaceManager) decide de le replacer.

signal truck_entered_reset_zone(truck: Node3D)
signal truck_exited_reset_zone(truck: Node3D)
## Un camion entre dans le checkpoint `index` (0 = ligne d'arrivee). L'ordre et
## les tours sont l'affaire du gameplay (RaceLaps).
signal checkpoint_passed(truck: Node3D, index: int)
## Un camion roule sur la plaque de boost `index` (ordre du trace). L'effet
## est l'affaire du gameplay (PadEffects).
signal boost_pad_entered(truck: Node3D, index: int)
## Un camion atteint le haut de la rampe de saut `index`.
signal jump_pad_entered(truck: Node3D, index: int)
## Un camion roule dans la flaque d'eau `index`.
signal puddle_entered(truck: Node3D, index: int)
## Un camion percute le panneau `index` (qui s'envole).
signal sign_hit(truck: Node3D, index: int)

const ROAD_LAYER := 1          # couche 1 `world` (VEHICLE_SPEC §7)
const RESET_ZONE_LAYER := 4    # couche 4 `reset_zone`
const CHECKPOINT_LAYER := 3    # couche 3 `checkpoint`
const VEHICLE_LAYER := 2
const GROUND_Y := -0.05        # sol sous la chaussee (evite le z-fighting)

@export var segments: Array[Dictionary] = []
## Largeur de chaussee entre les murs (METRICS.md §4 : 14 m minimum).
@export var width: float = 14.0
## Pas d'echantillonnage de la ligne centrale.
@export var sample_step: float = 2.0
## Longueur des raccords de ligne de course.
@export var blend_length: float = 30.0
## Longueur des raccords de devers : sur une piste large, le bord haut monte de
## (largeur / 2) x sin(devers) ; un raccord long garde des pentes douces.
@export var bank_blend_length: float = 30.0
## 0 : chaque montee en S sur son segment. > 0 : pentes constantes par segment,
## raccordees sur cette longueur (plus court = crete et compression plus
## franches).
@export var climb_blend_length: float = 0.0

@export_group("Glissieres")
## Epaisseur a hauteur de chaussee (METRICS.md §4 : 0,3 m minimum).
@export var wall_thickness: float = 0.3
@export var wall_height: float = 1.4
## Porte-a-faux du haut du mur vers la piste : la face interieure penche vers
## la chaussee, le contact pousse le camion vers le bas, jamais vers le haut.
@export var wall_lean: float = 0.15
## Frottement nul : un camion qui touche le mur glisse le long, il ne s'y
## accroche pas.
@export var wall_friction: float = 0.0

@export_group("Tremplin")
@export var jump_length: float = 10.0
@export var jump_angle_deg: float = 8.0
@export var jump_width: float = 4.8
## Decalage lateral du centre du tremplin (> 0 : a droite).
@export var jump_offset: float = 4.2
## Profondeur de la zone de declenchement, au sommet de la rampe.
@export var jump_trigger_depth: float = 3.0

@export_group("Arches")
## Hauteur libre sous la poutre, au-dessus de la chaussee.
@export var arch_height: float = 13.0

@export_group("Plaques de boost")
## Largeur (en travers) et longueur (le long de la piste).
@export var boost_pad_size: Vector2 = Vector2(8.0, 6.0)
## Hauteur de la zone de declenchement au-dessus de la chaussee.
@export var boost_pad_height: float = 3.0

@export_group("Zones de reset")
## Longueur d'une zone le long de la piste (courte : suit les courbes).
@export var reset_zone_length: float = 20.0
## Ecart entre le haut exterieur du mur et le bord interieur de la zone : une
## remorque qui frotte le mur ne doit jamais y entrer.
@export var reset_zone_margin: float = 2.0
@export var reset_zone_depth: float = 60.0
@export var reset_zone_height: float = 40.0

@export_group("Checkpoints")
## Nombre de checkpoints, repartis regulierement ; le n°0 est la ligne.
@export var checkpoint_count: int = 20
@export var checkpoint_depth: float = 4.0
## Haut : un camion en plein saut passe quand meme dedans.
@export var checkpoint_height: float = 20.0

@export_group("Grille")
@export var grid_distance: float = 12.0
@export var grid_row_spacing: float = 9.0
@export var grid_lateral: PackedFloat32Array = [-4.5, -1.5, 1.5, 4.5]

@export_tool_button("Reconstruire") var _rebuild_button: Callable = rebuild

## Echantillons de la ligne centrale (boucle fermee : le dernier rejoint le premier).
var _pos: PackedVector3Array = []
var _right: PackedVector3Array = []     # lateral, devers applique
var _up: PackedVector3Array = []        # normale de chaussee, devers applique
var _fwd: PackedVector3Array = []       # tangente (sens de course)
var _s: PackedFloat32Array = []
var _curv: PackedFloat32Array = []      # courbure signee (1/m), > 0 a gauche
var _line: PackedFloat32Array = []
var _length: float = 0.0
var _jumps: Array[Vector2] = []         # (s du tremplin, decalage)
var _boosts: Array[Vector2] = []        # (s de la plaque, decalage)
var _arches: Array[Dictionary] = []     # {s, label}
var _segment_starts: Dictionary = {}    # nom -> abscisse du debut (m)
var _puddles: Array[Vector3] = []       # (s, decalage, rayon)
var _signs: Array[Vector2] = []         # (s, decalage)
var _auto_lengths: PackedFloat32Array = []


func _ready() -> void:
	if _pos.is_empty():
		rebuild()


## Construit la piste si ce n'est pas deja fait : l'interface marche avant
## _ready (ordre d'initialisation indifferent).
func _ensure_built() -> void:
	if _pos.is_empty() and not segments.is_empty():
		rebuild()


func rebuild() -> void:
	for c in get_children():
		if c.has_meta(&"generated"):
			remove_child(c)
			c.queue_free()
	if segments.is_empty():
		return
	if not _build_centerline():
		return
	_build_geometry()


# --- interface (gameplay, tests, IA) --------------------------------------------

func length() -> float:
	_ensure_built()
	return _length


func sample_count() -> int:
	_ensure_built()
	return _pos.size()


func sample_position(i: int) -> Vector3:
	return _pos[posmod(i, _pos.size())]


func sample_right(i: int) -> Vector3:
	return _right[posmod(i, _pos.size())]


func sample_up(i: int) -> Vector3:
	return _up[posmod(i, _pos.size())]


func sample_forward(i: int) -> Vector3:
	return _fwd[posmod(i, _pos.size())]


func sample_s(i: int) -> float:
	return _s[posmod(i, _pos.size())]


func curvature(i: int) -> float:
	return _curv[posmod(i, _pos.size())]


func line_offset(i: int) -> float:
	return _line[posmod(i, _pos.size())]


## Indice de l'echantillon situe `distance` metres plus loin (sens de course).
func sample_ahead(i: int, distance: float) -> int:
	return posmod(i + roundi(distance / (_length / _pos.size())), _pos.size())


## Indice de l'echantillon a l'abscisse curviligne `s` (m, modulo la longueur).
func index_at_s(s: float) -> int:
	_ensure_built()
	return posmod(roundi(fposmod(s, _length) / (_length / _pos.size())), _pos.size())


## Abscisse curviligne (m) du checkpoint k : ils sont repartis regulierement.
func checkpoint_s(k: int) -> float:
	_ensure_built()
	return _length * posmod(k, checkpoint_count) / checkpoint_count


## Echantillon le plus proche. Avec `hint` >= 0, recherche locale (+/- 40 m) :
## c'est le cas d'un camion suivi tick apres tick.
func closest_sample(p: Vector3, hint: int = -1) -> int:
	_ensure_built()
	var n := _pos.size()
	var best := 0
	var best_d := INF
	if hint >= 0:
		var span := ceili(40.0 / (_length / n))
		for k in range(-span, span + 1):
			var i := posmod(hint + k, n)
			var d := _pos[i].distance_squared_to(p)
			if d < best_d:
				best_d = d
				best = i
		return best
	for i in n:
		var d := _pos[i].distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = i
	return best


## Repere pose sur la chaussee a l'echantillon i, decale lateralement, oriente
## dans le sens de course (avant du camion en -Z), `lift` metres au-dessus.
func frame_at(i: int, lateral: float, lift: float) -> Transform3D:
	var r := sample_right(i)
	var u := sample_up(i)
	var f := sample_forward(i)
	return Transform3D(Basis(r, u, -f), sample_position(i) + r * lateral + u * lift)


## Case de depart `slot` (0 = pole) : rangs de 4 derriere la ligne.
@warning_ignore("integer_division")
func get_start_transform(slot: int) -> Transform3D:
	_ensure_built()
	var row := slot / grid_lateral.size()
	var col := slot % grid_lateral.size()
	var s := _length - grid_distance - row * grid_row_spacing
	var i := roundi(s / (_length / _pos.size()))
	return frame_at(i, grid_lateral[col], 0.0)


func boost_pad_count() -> int:
	_ensure_built()
	return _boosts.size()


## Centre de la plaque de boost k, pose sur la chaussee, dans le sens de course.
func boost_pad_transform(k: int) -> Transform3D:
	_ensure_built()
	return frame_at(index_at_s(_boosts[k].x), _boosts[k].y, 0.0)


## Abscisse (m) du debut du segment nomme ("name"), -1 s'il n'existe pas.
func segment_start_s(seg_name: String) -> float:
	_ensure_built()
	return float(_segment_starts.get(seg_name, -1.0))


func arch_count() -> int:
	_ensure_built()
	return _arches.size()


## Abscisse (m) de l'arche k.
func arch_s(k: int) -> float:
	_ensure_built()
	return float(_arches[k]["s"])


func puddle_count() -> int:
	_ensure_built()
	return _puddles.size()


## Centre de la flaque k, pose sur la chaussee ; rayon dans `puddle_radius`.
func puddle_transform(k: int) -> Transform3D:
	_ensure_built()
	return frame_at(index_at_s(_puddles[k].x), _puddles[k].y, 0.0)


func puddle_radius(k: int) -> float:
	return _puddles[k].z


func sign_count() -> int:
	_ensure_built()
	return _signs.size()


## Le panneau k (noeud RoadsideSign), ou null avant la construction.
func sign_node(k: int) -> RoadsideSign:
	return get_node_or_null("Signs/Sign%d" % k) as RoadsideSign


func jump_pad_count() -> int:
	_ensure_built()
	return _jumps.size()


## Bord d'attaque de la rampe de saut k, au milieu, dans le sens de course.
func jump_pad_transform(k: int) -> Transform3D:
	_ensure_built()
	return frame_at(index_at_s(_jumps[k].x), _jumps[k].y, 0.0)


## Reapparition au plus pres de `p` : sur la chaussee, dans le sens de course,
## ecart lateral conserve mais ramene a 2 m des murs, 1 m au-dessus du sol.
func get_respawn_transform(p: Vector3) -> Transform3D:
	_ensure_built()
	var i := closest_sample(p)
	var lateral := (p - sample_position(i)).dot(sample_right(i))
	var limit := width / 2.0 - 2.0
	return frame_at(i, clampf(lateral, -limit, limit), 1.0)


# --- ligne centrale -------------------------------------------------------------

## Integre le trace, resout les droites "auto", reechantillonne, calcule les
## reperes (devers compris). Faux si le trace ne se referme pas.
func _build_centerline() -> bool:
	var autos: Array[int] = []
	for k in segments.size():
		if segments[k].get("auto", false):
			autos.append(k)
	var lengths := PackedFloat32Array()
	lengths.resize(segments.size())
	for k in segments.size():
		lengths[k] = _segment_length(segments[k], 0.0)
	if autos.size() == 2:
		# fermeture lineaire en fonction des deux longueurs libres
		var e0 := _endpoint(lengths)
		lengths[autos[0]] = 1.0
		var e1 := _endpoint(lengths)
		lengths[autos[0]] = 0.0
		lengths[autos[1]] = 1.0
		var e2 := _endpoint(lengths)
		var a := e1 - e0
		var b := e2 - e0
		var det := a.x * b.y - b.x * a.y
		var l1 := (-e0.x * b.y + b.x * e0.y) / det
		var l2 := (-a.x * e0.y + a.y * e0.x) / det
		if l1 <= 0.0 or l2 <= 0.0:
			push_error("TrackBlockout : fermeture impossible (droites auto %.1f / %.1f m)" % [l1, l2])
			return false
		lengths[autos[0]] = l1
		lengths[autos[1]] = l2
		_auto_lengths = [l1, l2]
	var end := _endpoint(lengths)
	if end.length() > 0.05:
		push_warning("TrackBlockout : la boucle ne se referme pas (ecart %.2f m)" % end.length())
	# plaques et rampes : abscisse = debut du segment + distance demandee
	_jumps.clear()
	_boosts.clear()
	_arches.clear()
	_segment_starts.clear()
	_puddles.clear()
	_signs.clear()
	var seg_start := 0.0
	for k in segments.size():
		var seg: Dictionary = segments[k]
		_segment_starts[String(seg.get("name", "%d" % k))] = seg_start
		if seg.has("jump"):
			_jumps.append(Vector2(seg_start + float(seg["jump"]), float(seg.get("jump_offset", jump_offset))))
		for b: Array in seg.get("boost", []):
			_boosts.append(Vector2(seg_start + float(b[0]), float(b[1])))
		for pd: Array in seg.get("puddle", []):
			_puddles.append(Vector3(seg_start + float(pd[0]), float(pd[1]), float(pd[2])))
		for sg: Array in seg.get("signs", []):
			_signs.append(Vector2(seg_start + float(sg[0]), float(sg[1])))
		if seg.has("arch"):
			_arches.append({"s": seg_start + float(seg["arch"]), "label": String(seg.get("arch_label", ""))})
		seg_start += lengths[k]

	# integration fine, puis reechantillonnage a pas regulier
	var fine_p: Array[Vector2] = []
	var fine_s := PackedFloat32Array()
	var fine_seg := PackedInt32Array()
	var fine_u := PackedFloat32Array()
	var x := 0.0
	var z := 0.0
	var th := 0.0
	var s := 0.0
	fine_p.append(Vector2.ZERO)
	fine_s.append(0.0)
	fine_seg.append(0)
	fine_u.append(0.0)
	for k in segments.size():
		var seg: Dictionary = segments[k]
		var L := lengths[k]
		var n := maxi(1, ceili(L / 0.25))
		var h := L / n
		var turn := 0.0
		if seg.get("type", "straight") == "arc":
			turn = signf(float(seg["angle"])) / float(seg["radius"])
		for j in n:
			th += turn * h
			x += -sin(th) * h
			z += -cos(th) * h
			s += h
			fine_p.append(Vector2(x, z))
			fine_s.append(s)
			fine_seg.append(k)
			fine_u.append(float(j + 1) / n)
	_length = s
	var count := maxi(8, roundi(_length / sample_step))
	var ds := _length / count
	_pos.resize(count)
	_s.resize(count)
	_curv.resize(count)
	var raw_bank := PackedFloat32Array()
	raw_bank.resize(count)
	var raw_line := PackedFloat32Array()
	raw_line.resize(count)
	var seg_of := PackedInt32Array()
	seg_of.resize(count)
	var climb_base := PackedFloat32Array()
	climb_base.resize(segments.size())
	var yb := 0.0
	for k in segments.size():
		climb_base[k] = yb
		yb += float(segments[k].get("climb", 0.0))
	if absf(yb) > 0.01:
		push_warning("TrackBlockout : le denivele total n'est pas nul (%.2f m)" % yb)
	var f := 0
	for i in count:
		var si := i * ds
		while f < fine_s.size() - 2 and fine_s[f + 1] < si:
			f += 1
		var w := clampf((si - fine_s[f]) / maxf(fine_s[f + 1] - fine_s[f], 1e-6), 0.0, 1.0)
		var p2 := fine_p[f].lerp(fine_p[f + 1], w)
		var k := fine_seg[f + 1]
		var seg: Dictionary = segments[k]
		var u := lerpf(fine_u[f], fine_u[f + 1], w) if fine_seg[f] == k else w * fine_u[f + 1]
		var rise := u if climb_blend_length > 0.0 else smoothstep(0.0, 1.0, u)
		var y := climb_base[k] + float(seg.get("climb", 0.0)) * rise
		_pos[i] = Vector3(p2.x, y, p2.y)
		_s[i] = si
		seg_of[i] = k
		_curv[i] = 0.0
		if seg.get("type", "straight") == "arc":
			_curv[i] = signf(float(seg["angle"])) / float(seg["radius"])
		raw_bank[i] = float(seg.get("bank", 0.0))
		raw_line[i] = float(seg.get("line", 0.0))
	if climb_blend_length > 0.0:
		# pentes constantes par segment, raccordees sur toute la boucle
		var ys := PackedFloat32Array()
		ys.resize(count)
		for i in count:
			ys[i] = _pos[i].y
		var rc := climb_blend_length / ds / 2.0
		ys = _smooth_loop(_smooth_loop(ys, rc), rc)
		for i in count:
			_pos[i].y = ys[i]
	var bank := _smooth_loop(_smooth_loop(raw_bank, bank_blend_length / ds / 2.0), bank_blend_length / ds / 2.0)
	_line = _smooth_loop(_smooth_loop(raw_line, blend_length / ds), blend_length / ds)
	# devers pivote sur le bord bas : le trace monte d'autant, le bord bas reste
	# a sa hauteur (sinon, sur 75 m de large, il plonge sous le sol d'herbe)
	for i in count:
		_pos[i].y += width / 2.0 * sin(absf(deg_to_rad(bank[i])))

	# reperes : tangente, lateral horizontal, puis devers autour de la tangente
	_fwd.resize(count)
	_right.resize(count)
	_up.resize(count)
	for i in count:
		var t := (_pos[(i + 1) % count] - _pos[(i - 1 + count) % count]).normalized()
		var r := t.cross(Vector3.UP).normalized()
		var up := r.cross(t).normalized()
		var b := deg_to_rad(bank[i])
		_fwd[i] = t
		_right[i] = r * cos(b) + up * sin(b)
		_up[i] = up * cos(b) - r * sin(b)
	return true


func _segment_length(seg: Dictionary, auto_value: float) -> float:
	if seg.get("type", "straight") == "arc":
		return float(seg["radius"]) * deg_to_rad(absf(float(seg["angle"])))
	if seg.get("auto", false):
		return auto_value
	return float(seg.get("length", 0.0))


## Point d'arrivee (x, z) du trace pour ces longueurs de segments.
func _endpoint(lengths: PackedFloat32Array) -> Vector2:
	var x := 0.0
	var z := 0.0
	var th := 0.0
	for k in segments.size():
		var seg: Dictionary = segments[k]
		var L := lengths[k]
		if seg.get("type", "straight") == "arc":
			var sgn := signf(float(seg["angle"]))
			var R := float(seg["radius"])
			var n := maxi(1, ceili(L / 0.25))
			var h := L / n
			for j in n:
				th += sgn * h / R
				x += -sin(th) * h
				z += -cos(th) * h
		else:
			x += -sin(th) * L
			z += -cos(th) * L
	return Vector2(x, z)


## Moyenne glissante circulaire (rayon en echantillons) : transforme un profil en
## marches en raccords progressifs.
static func _smooth_loop(v: PackedFloat32Array, radius: float) -> PackedFloat32Array:
	var n := v.size()
	var r := maxi(1, roundi(radius))
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var acc := 0.0
		for k in range(-r, r + 1):
			acc += v[posmod(i + k, n)]
		out[i] = acc / (2 * r + 1)
	return out


# --- geometrie ------------------------------------------------------------------

func _build_geometry() -> void:
	var geometry := _group("Geometry")
	var walls := _group("Walls")
	var zones := _group("ResetZones")
	var checkpoints := _group("Checkpoints")
	var grid := _group("StartGrid")

	# chaussee
	var n := _pos.size()
	var road_tris := PackedVector3Array()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		var j := (i + 1) % n
		var v0 := _s[i]
		var v1 := _s[i] + _length / n
		var l0 := _pos[i] - _right[i] * width / 2.0
		var r0 := _pos[i] + _right[i] * width / 2.0
		var l1 := _pos[j] - _right[j] * width / 2.0
		var r1 := _pos[j] + _right[j] * width / 2.0
		_quad(st, road_tris, l0, r0, r1, l1, Vector2(0, v0), Vector2(1, v0), Vector2(1, v1), Vector2(0, v1), _up[i])
	var road_mat := preload("res://tracks/materials/road.tres").duplicate() as ShaderMaterial
	road_mat.set_shader_parameter("road_width", width)
	var road := _static_body(geometry, "Road", st, road_tris, road_mat, 1.0)
	road.set_meta(&"surface", &"asphalt")

	# glissieres : profil vertical dans le monde (independant du devers),
	# face interieure penchee vers la piste, face exterieure jusqu'au sol
	for side: float in [-1.0, 1.0]:
		var wst := SurfaceTool.new()
		wst.begin(Mesh.PRIMITIVE_TRIANGLES)
		var wtris := PackedVector3Array()
		for i in n:
			var j := (i + 1) % n
			var a := _wall_profile(i, side)
			var b := _wall_profile(j, side)
			var v0 := _s[i]
			var v1 := _s[i] + _length / n
			for k in 3:
				if side > 0.0:
					_quad(wst, wtris, a[k], b[k], b[k + 1], a[k + 1],
						Vector2(k, v0), Vector2(k, v1), Vector2(k + 1, v1), Vector2(k + 1, v0), Vector3.ZERO)
				else:
					_quad(wst, wtris, a[k], a[k + 1], b[k + 1], b[k],
						Vector2(k, v0), Vector2(k + 1, v0), Vector2(k + 1, v1), Vector2(k, v1), Vector3.ZERO)
		var wall := _static_body(walls, "WallLeft" if side < 0.0 else "WallRight", wst, wtris,
			preload("res://tracks/materials/wall.tres"), wall_friction)
		wall.set_meta(&"surface", &"asphalt")
		_build_wall_neon(walls, side)

	# sol sous toute la piste et la ville (hors piste : lent, pas de vide)
	var span := _bounds_span() + 2400.0
	var gst := SurfaceTool.new()
	gst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gtris := PackedVector3Array()
	var c := _bounds_center()
	var h := span / 2.0
	_quad(gst, gtris, c + Vector3(-h, GROUND_Y, -h), c + Vector3(-h, GROUND_Y, h),
		c + Vector3(h, GROUND_Y, h), c + Vector3(h, GROUND_Y, -h),
		Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector3.UP)
	var ground := _static_body(geometry, "Ground", gst, gtris, preload("res://tracks/materials/grass.tres"), 1.0)
	ground.set_meta(&"surface", &"grass")

	var arches := _group("Arches")
	for k in _arches.size():
		_build_arch(arches, float(_arches[k]["s"]), String(_arches[k]["label"]), k)

	var signs := _group("Signs")
	for k in _signs.size():
		_build_sign(signs, _signs[k].x, _signs[k].y, k)

	var pads := _group("Pads")
	for k in _jumps.size():
		_build_jump(pads, _jumps[k].x, _jumps[k].y, k)
	for k in _boosts.size():
		_build_boost_pad(pads, _boosts[k].x, _boosts[k].y, k)
	for k in _puddles.size():
		_build_puddle(pads, _puddles[k], k)

	_build_reset_zones(zones)
	_build_checkpoints(checkpoints)

	for slot in grid_lateral.size():
		var m := Marker3D.new()
		m.name = "Slot%d" % slot
		m.transform = get_start_transform(slot)
		grid.add_child(m)

	var path := Path3D.new()
	path.name = "RacingLine"
	path.set_meta(&"generated", true)
	var curve := Curve3D.new()
	for i in n + 1:
		curve.add_point(_pos[i % n])
	path.curve = curve
	add_child(path)


## Profil d'un mur en 4 points : bas interieur (sous la chaussee), haut
## interieur (penche vers la piste), haut exterieur, bas exterieur (au sol).
func _wall_profile(i: int, side: float) -> PackedVector3Array:
	var edge := _pos[i] + _right[i] * (side * width / 2.0)
	var out := Vector3(_right[i].x, 0.0, _right[i].z).normalized() * side
	var top_y := edge.y + wall_height
	var inner_bottom := edge + Vector3(0.0, -0.3, 0.0)
	var inner_top := Vector3(edge.x, top_y, edge.z) - out * wall_lean
	var thick_top := wall_thickness + wall_lean * (1.0 + 0.3 / wall_height)
	var outer_top := inner_top + out * thick_top
	var outer_bottom := Vector3(outer_top.x, minf(GROUND_Y - 0.1, edge.y - 0.3), outer_top.z)
	return PackedVector3Array([inner_bottom, inner_top, outer_top, outer_bottom])


## Neon du bord haut de la glissiere : bandeau de 0,3 m en haut de la face
## interieure, et tout le dessus du mur. Purement visuel (aucune collision).
func _build_wall_neon(parent: Node3D, side: float) -> void:
	var n := _pos.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := PackedVector3Array()
	var z2 := Vector2.ZERO
	var strip: Array[PackedVector3Array] = []
	for i in n:
		var prof := _wall_profile(i, side)
		var down := (prof[0] - prof[1]).normalized()
		var inward := -Vector3(_right[i].x, 0.0, _right[i].z).normalized() * side * 0.04
		var lift := Vector3(0.0, 0.03, 0.0)
		strip.append(PackedVector3Array([prof[1] + down * 0.32 + inward, prof[1] + inward + lift, prof[2] + lift]))
	for i in n:
		var a := strip[i]
		var b := strip[(i + 1) % n]
		_quad(st, tris, a[0], b[0], b[1], a[1], z2, z2, z2, z2, Vector3.ZERO)
		_quad(st, tris, a[1], b[1], b[2], a[2], z2, z2, z2, z2, Vector3.ZERO)
	var mi := MeshInstance3D.new()
	mi.name = "NeonLeft" if side < 0.0 else "NeonRight"
	mi.mesh = st.commit()
	mi.material_override = preload("res://tracks/materials/neon_cyan.tres") if side < 0.0 \
			else preload("res://tracks/materials/neon_magenta.tres")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## Arche lumineuse : deux piliers au-dela des murs, une poutre au-dessus de la
## chaussee (arch_height de hauteur libre), tubes neon, enseigne tournee vers
## les camions qui arrivent, et une lumiere qui colore la piste dessous.
## Purement visuelle : aucune collision (ni camion, ni camera).
func _build_arch(parent: Node3D, s: float, label: String, index: int) -> void:
	var i := index_at_s(s)
	var t := Vector3(_fwd[i].x, 0.0, _fwd[i].z).normalized()
	var r := t.cross(Vector3.UP).normalized()
	var arch_basis := Basis(r, Vector3.UP, -t)
	var base := _pos[i]
	var half := width / 2.0 + 3.0
	var neon: Material = preload("res://tracks/materials/neon_magenta.tres") if index % 2 == 0 \
			else preload("res://tracks/materials/neon_cyan.tres")
	var neon_color := Color(1.0, 0.12, 0.78) if index % 2 == 0 else Color(0.08, 0.95, 1.0)
	var root := Node3D.new()
	root.name = "Arch%d" % index
	root.transform = Transform3D(arch_basis, base)
	parent.add_child(root)
	var beam_y := arch_height + 1.2
	var ground := GROUND_Y - base.y
	for side: float in [-1.0, 1.0]:
		var h := beam_y + 1.2 - ground
		_box(root, Vector3(2.2, h, 2.2), Vector3(side * half, ground + h / 2.0, 0.0), _arch_metal())
		# tube neon sur la face du pilier tournee vers la piste
		_box(root, Vector3(0.25, h - 1.5, 0.25), Vector3(side * (half - 1.15), ground + h / 2.0, 0.0), neon)
	_box(root, Vector3(half * 2.0 + 2.2, 2.4, 2.6), Vector3(0.0, beam_y, 0.0), _arch_metal())
	for z: float in [-1.35, 1.35]:
		_box(root, Vector3(half * 2.0, 0.22, 0.22), Vector3(0.0, beam_y - 1.25, z), neon)
		_box(root, Vector3(half * 2.0, 0.22, 0.22), Vector3(0.0, beam_y + 1.25, z), neon)
	if label != "":
		var l := Label3D.new()
		l.name = "Sign"
		l.text = label
		l.font_size = 220
		l.pixel_size = 0.02
		l.outline_size = 0
		l.modulate = Color(neon_color.r * 2.2, neon_color.g * 2.2, neon_color.b * 2.2)
		l.double_sided = false
		# face avant vers les camions qui arrivent (-t = +Z local)
		l.position = Vector3(0.0, beam_y, 1.32)
		root.add_child(l)
	var light := OmniLight3D.new()
	light.light_color = neon_color
	light.light_energy = 3.0
	light.omni_range = 34.0
	light.position = Vector3(0.0, beam_y - 2.0, 0.0)
	root.add_child(light)


static var _metal: StandardMaterial3D


static func _arch_metal() -> StandardMaterial3D:
	if _metal == null:
		_metal = StandardMaterial3D.new()
		_metal.albedo_color = Color(0.05, 0.055, 0.07)
		_metal.metallic = 0.7
		_metal.roughness = 0.35
	return _metal


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## Zones de reset : une boite par troncon de piste et par cote, au-dela du mur,
## orientee le long de la piste (courtes, pour suivre les virages sans jamais
## deborder sur la chaussee). Du sol jusqu'a reset_zone_height au-dessus.
func _build_reset_zones(parent: Node3D) -> void:
	var n := _pos.size()
	var step := _length / n
	var chunk := maxi(1, roundi(reset_zone_length / step))
	var inner := width / 2.0 + wall_thickness + wall_lean + reset_zone_margin
	var k := 0
	var i := 0
	while i < n:
		var mid := (i + floori(chunk / 2.0)) % n
		var t := Vector3(_fwd[mid].x, 0.0, _fwd[mid].z).normalized()
		var r := t.cross(Vector3.UP).normalized()
		var zone_basis := Basis(r, Vector3.UP, -t)
		for side: float in [-1.0, 1.0]:
			var area := Area3D.new()
			area.name = "Zone%03d%s" % [k, "L" if side < 0.0 else "R"]
			area.collision_layer = 1 << (RESET_ZONE_LAYER - 1)
			area.collision_mask = 1 << (VEHICLE_LAYER - 1)
			area.monitorable = false
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(reset_zone_depth, reset_zone_height, chunk * step + 2.0)
			cs.shape = box
			area.add_child(cs)
			var center := _pos[mid] + r * side * (inner + reset_zone_depth / 2.0)
			center.y = GROUND_Y - 2.0 + reset_zone_height / 2.0
			area.transform = Transform3D(zone_basis, center)
			area.body_entered.connect(_on_reset_zone_body_entered)
			area.body_exited.connect(_on_reset_zone_body_exited)
			parent.add_child(area)
		k += 1
		i += chunk


## Checkpoints : une boite en travers de la piste, murs compris, orientee avec
## la chaussee (devers), haute pour les sauts.
func _build_checkpoints(parent: Node3D) -> void:
	var span := width + 2.0 * (wall_thickness + wall_lean + 1.0)
	for k in checkpoint_count:
		var i := index_at_s(checkpoint_s(k))
		var area := Area3D.new()
		area.name = "CP%02d" % k
		area.collision_layer = 1 << (CHECKPOINT_LAYER - 1)
		area.collision_mask = 1 << (VEHICLE_LAYER - 1)
		area.monitorable = false
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(span, checkpoint_height, checkpoint_depth)
		cs.shape = box
		cs.position = Vector3(0.0, checkpoint_height / 2.0 - 2.0, 0.0)
		area.add_child(cs)
		area.transform = frame_at(i, 0.0, 0.0)
		area.body_entered.connect(_on_checkpoint_body_entered.bind(k))
		parent.add_child(area)


func _on_checkpoint_body_entered(body: Node3D, index: int) -> void:
	checkpoint_passed.emit(body, index)


func _on_reset_zone_body_entered(body: Node3D) -> void:
	truck_entered_reset_zone.emit(body)


func _on_reset_zone_body_exited(body: Node3D) -> void:
	truck_exited_reset_zone.emit(body)


func _on_puddle_body_entered(body: Node3D, index: int) -> void:
	puddle_entered.emit(body, index)


func _on_sign_hit(truck: Truck, index: int) -> void:
	sign_hit.emit(truck, index)


## Flaque d'eau : disque irregulier (bord bruite, deterministe) a ras de la
## chaussee, miroir sombre aux rides animees ; zone de declenchement
## cylindrique. Aucune collision.
func _build_puddle(parent: Node3D, p: Vector3, index: int) -> void:
	var area := Area3D.new()
	area.name = "Puddle%d" % index
	area.collision_layer = 0
	area.collision_mask = 1 << (VEHICLE_LAYER - 1)
	area.monitorable = false
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = p.z
	cyl.height = 3.0
	cs.shape = cyl
	cs.position = Vector3(0.0, 1.0, 0.0)
	area.add_child(cs)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 28
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		var r0 := p.z * (1.0 + 0.12 * sin(a0 * 3.0 + index) + 0.06 * sin(a0 * 7.0 + index * 2.0))
		var r1 := p.z * (1.0 + 0.12 * sin(a1 * 3.0 + index) + 0.06 * sin(a1 * 7.0 + index * 2.0))
		# ellipse allongee le long de la piste
		var v0 := Vector3(cos(a0) * r0 * 0.75, 0.05, sin(a0) * r0 * 1.2)
		var v1 := Vector3(cos(a1) * r1 * 0.75, 0.05, sin(a1) * r1 * 1.2)
		for v: Array in [[Vector3(0.0, 0.05, 0.0), Vector2(float(k) / n, 0.0)], [v1, Vector2(float(k + 1) / n, 1.0)],
				[v0, Vector2(float(k) / n, 1.0)]]:
			st.set_normal(Vector3.UP)
			st.set_uv(v[1])
			st.add_vertex(v[0])
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = st.commit()
	mi.material_override = preload("res://tracks/materials/puddle.tres")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	area.add_child(mi)
	area.transform = frame_at(index_at_s(p.x), p.y, 0.0)
	area.body_entered.connect(_on_puddle_body_entered.bind(index))
	parent.add_child(area)


## Panneau ejectable au bord de la piste, face aux camions qui arrivent,
## fleches vers le centre de la piste (le virage).
func _build_sign(parent: Node3D, s: float, lateral: float, index: int) -> void:
	var i := index_at_s(s)
	var t := Vector3(_fwd[i].x, 0.0, _fwd[i].z).normalized()
	var r := t.cross(Vector3.UP).normalized()
	var board := RoadsideSign.new()
	board.name = "Sign%d" % index
	# fleches vers le centre : a droite de la piste, elles pointent a gauche
	# (vu de face, la gauche du panneau est la droite de la piste)
	board.arrows_right = lateral < 0.0
	var pos := _pos[i] + _right[i] * lateral
	board.transform = Transform3D(Basis(r, Vector3.UP, -t), pos)
	board.hit.connect(_on_sign_hit.bind(index))
	parent.add_child(board)


func _on_boost_pad_body_entered(body: Node3D, index: int) -> void:
	boost_pad_entered.emit(body, index)


func _on_jump_pad_body_entered(body: Node3D, index: int) -> void:
	jump_pad_entered.emit(body, index)


## Rampe de saut : prisme convexe, bord d'attaque au ras de la chaussee, face de
## roulement a chevrons bleus lumineux ; zone de declenchement au sommet.
func _build_jump(parent: Node3D, s: float, offset: float, index: int) -> void:
	var i := index_at_s(s)
	var f := _fwd[i]
	var r := _right[i]
	var u := _up[i]
	var base := _pos[i] + r * offset
	var hw := jump_width / 2.0
	var top := jump_length * tan(deg_to_rad(jump_angle_deg))
	var p := PackedVector3Array([
		base - r * hw - u * 0.02, base + r * hw - u * 0.02,                              # attaque
		base - r * hw + f * jump_length + u * top, base + r * hw + f * jump_length + u * top,  # sommet
		base - r * hw + f * jump_length - u * 0.3, base + r * hw + f * jump_length - u * 0.3,  # pied arriere
	])
	var face := SurfaceTool.new()
	face.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := PackedVector3Array()
	var z2 := Vector2.ZERO
	_quad(face, tris, p[0], p[1], p[3], p[2],                                 # rampe
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector3.ZERO)
	_quad(st, tris, p[2], p[3], p[5], p[4], z2, z2, z2, z2, Vector3.ZERO)   # dos
	_tri(st, tris, p[0], p[2], p[4])                                        # flancs
	_tri(st, tris, p[1], p[5], p[3])
	var body := StaticBody3D.new()
	body.name = "JumpPad%d" % index
	body.collision_layer = 1 << (ROAD_LAYER - 1)
	body.collision_mask = 0
	body.set_meta(&"surface", &"asphalt")
	var cs := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = p
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	st.generate_normals()
	mi.mesh = st.commit()
	mi.material_override = preload("res://tracks/materials/jump.tres")
	body.add_child(mi)
	var fmi := MeshInstance3D.new()
	fmi.name = "Chevrons"
	face.generate_normals()
	fmi.mesh = face.commit()
	fmi.material_override = preload("res://tracks/materials/jump_pad.tres")
	body.add_child(fmi)
	parent.add_child(body)
	# declenchement : les derniers metres de la rampe, jusqu'a 3 m au-dessus
	var area := Area3D.new()
	area.name = "JumpTrigger%d" % index
	area.collision_layer = 0
	area.collision_mask = 1 << (VEHICLE_LAYER - 1)
	area.monitorable = false
	var acs := CollisionShape3D.new()
	var abox := BoxShape3D.new()
	abox.size = Vector3(jump_width, 4.0, jump_trigger_depth)
	acs.shape = abox
	area.add_child(acs)
	area.transform = Transform3D(Basis(r, u, -f),
		base + f * (jump_length - jump_trigger_depth / 2.0) + u * (top + 1.0))
	area.body_entered.connect(_on_jump_pad_body_entered.bind(index))
	parent.add_child(area)


## Plaque de boost : dalle a chevrons orange et jaunes lumineux, a ras de la
## chaussee (aucune collision), et sa zone de declenchement.
func _build_boost_pad(parent: Node3D, s: float, lateral: float, index: int) -> void:
	var area := Area3D.new()
	area.name = "BoostPad%d" % index
	area.collision_layer = 0
	area.collision_mask = 1 << (VEHICLE_LAYER - 1)
	area.monitorable = false
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(boost_pad_size.x, boost_pad_height, boost_pad_size.y)
	cs.shape = box
	cs.position = Vector3(0.0, boost_pad_height / 2.0 - 0.5, 0.0)
	area.add_child(cs)
	# dalle dans le repere de la plaque : x en travers, avant en -Z
	var hw := boost_pad_size.x / 2.0
	var hl := boost_pad_size.y / 2.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := PackedVector3Array()
	_quad(st, tris, Vector3(-hw, 0.04, hl), Vector3(hw, 0.04, hl), Vector3(hw, 0.04, -hl), Vector3(-hw, 0.04, -hl),
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector3.UP)
	var mi := MeshInstance3D.new()
	mi.name = "Chevrons"
	st.generate_normals()
	mi.mesh = st.commit()
	mi.material_override = preload("res://tracks/materials/boost_pad.tres")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	area.add_child(mi)
	area.transform = frame_at(index_at_s(s), lateral, 0.0)
	area.body_entered.connect(_on_boost_pad_body_entered.bind(index))
	parent.add_child(area)


# --- utilitaires ------------------------------------------------------------------

func _group(group_name: String) -> Node3D:
	var g := Node3D.new()
	g.name = group_name
	g.set_meta(&"generated", true)
	add_child(g)
	return g


func _static_body(parent: Node3D, body_name: String, st: SurfaceTool, tris: PackedVector3Array,
		mat: Material, friction: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = 1 << (ROAD_LAYER - 1)
	body.collision_mask = 0
	var pm := PhysicsMaterial.new()
	pm.friction = friction
	pm.bounce = 0.0
	body.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(tris)
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	st.generate_normals()
	st.generate_tangents()
	mi.mesh = st.commit()
	mi.material_override = mat
	body.add_child(mi)
	parent.add_child(body)
	return body


## Quadrilatere a, b, c, d (sens anti-horaire vu de la face visible).
func _quad(st: SurfaceTool, tris: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, _n: Vector3) -> void:
	var vs: Array[Vector3] = [a, c, b, a, d, c]
	var us: Array[Vector2] = [ua, uc, ub, ua, ud, uc]
	for k in 6:
		st.set_uv(us[k])
		st.add_vertex(vs[k])
		tris.append(vs[k])


func _tri(st: SurfaceTool, tris: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	var vs: Array[Vector3] = [a, c, b]
	for v in vs:
		st.set_uv(Vector2.ZERO)
		st.add_vertex(v)
		tris.append(v)


func _bounds_center() -> Vector3:
	var lo := _pos[0]
	var hi := _pos[0]
	for p in _pos:
		lo = lo.min(p)
		hi = hi.max(p)
	return Vector3((lo.x + hi.x) / 2.0, 0.0, (lo.z + hi.z) / 2.0)


func _bounds_span() -> float:
	var lo := _pos[0]
	var hi := _pos[0]
	for p in _pos:
		lo = lo.min(p)
		hi = hi.max(p)
	return maxf(hi.x - lo.x, hi.z - lo.z)
