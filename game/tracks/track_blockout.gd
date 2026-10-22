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
##   "pickups": [[m, "repair" | "power"], ...]  trois bonus de cette sorte
##                  (TrackPickup : reparation, recharge d'un pouvoir), places
##                  ensuite epars sur tout le tour (_scatter_pickups) : la
##                  distance ne sert plus.
##   "arch": m      arche lumineuse au-dessus de la piste a cette distance ;
##   "arch_label": texte de son enseigne.
##   "bridge": 1 | 2  pont en beton (1) ou en bois (2) : la ou la chaussee est
##                  a plus de bridge_min_height du sol, un tablier sur piles
##                  remplace les murs pleins jusqu'au sol (on voit dessous).
##
## L'habillage (materiaux, couleurs, sol) vient du theme (`theme_id`,
## TrackTheme) : Cyber City de nuit par defaut, Playa Del Sol (ile au
## soleil : le sol recoit un masque terre / mer calcule sur le trace, des
## talus rocheux portent les portions hautes) ou Sakura (Japon au printemps :
## arches en torii, murs de pierre sous les portions hautes).
##
## Trace qui se croise (circuit en 8, 2026-10-19) : au croisement, une
## branche passe sur un pont ("bridge") au-dessus de l'autre. Le generateur
## y veille : aucune pile de pont sur la route du dessous, pas de zone de
## reset qui deborde sur l'autre branche, checkpoints arretes sous le pont.
##
## Raccourcis (`branches`, 2026-10-20 : « des raccourcis qui ont un reel
## interet ») : une route droite, plus etroite, qui coupe un detour en
## creneau (la sortie du detour est dans l'axe de son entree). Elle a sa
## chaussee, ses murs, ses pieges ; les murs de la piste s'ouvrent la ou elle
## les traverse ; aucune zone de reset ne la couvre ; chaque checkpoint du
## detour a son double en travers du raccourci (meme numero : l'ordre tient) ;
## un camion dessus est sur la piste (on_branch) et sa progression suit le
## detour (closest_sample).
##
## Genere : Geometry (chaussee, sol), Walls (2 glissieres continues, bord haut
## colore : cyan a gauche, magenta a droite en ville), Arches (portiques), Pads
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
## Un camion percute le baril explosif `index`.
signal barrel_hit(truck: Truck, index: int)
## Un camion prend le bonus `index` (TrackPickup.Kind).
signal pickup_taken(truck: Truck, kind: int, index: int)

const ROAD_LAYER := 1          # couche 1 `world` (VEHICLE_SPEC §7)
const RESET_ZONE_LAYER := 4    # couche 4 `reset_zone`
const CHECKPOINT_LAYER := 3    # couche 3 `checkpoint`
const VEHICLE_LAYER := 2
const GROUND_Y := -0.05        # sol sous la chaussee (evite le z-fighting)
## Bonus par entree "pickups" d'un segment.
const PICKUPS_PER_ENTRY := 3
## Bonus epars : graine du generateur fixe, ecart minimal aux pieges (m),
## marge aux murs (m), tour libre apres la ligne (m).
const PICKUP_SEED := 7919
const PICKUP_CLEAR_M := 14.0
const PICKUP_EDGE_M := 3.5
const PICKUP_START_M := 60.0
## Arene : longueur (m) gardee libre de bonus de chaque cote d'une bosse.
const PICKUP_JUMP_RUN_M := 40.0
## En deca de cet ecart d'abscisse (m), deux echantillons sont la meme portion
## de piste ; au-dela, une autre (circuit en 8 : l'autre branche).
const SAME_SECTION_M := 160.0

@export var segments: Array[Dictionary] = []
## Largeur de chaussee entre les murs (METRICS.md §4 : 14 m minimum).
@export var width: float = 14.0
## Faux en arene (2026-10-21 : « pas de concept de tour, c'est juste une
## arène ») : pas de ligne d'arrivee peinte sur la route.
@export var race_markings: bool = true
## Vrai en arene (2026-10-21 : pas de sens de course) : chaque tremplin a
## une rampe jumelle dos a dos, il se saute dans les deux sens.
@export var jumps_both_ways: bool = false
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
## Habillage du circuit (TrackTheme.Id).
@export_enum("Cyber City", "Playa Del Sol", "Sakura") var theme_id: int = 0

@export_group("Raccourcis")
## Dictionary : "from" (segment ou il part, a son debut), "to" (segment ou il
## revient, a sa fin), "name", "width" (m, defaut branch_width), "lateral"
## (decalage de son axe, defaut : colle au bord oppose au detour), "puddles"
## [[u, decalage, rayon], ...] et "barrels" [[u, decalage], ...] (u de 0 a 1
## le long du raccourci).
@export var branches: Array[Dictionary] = []
@export var branch_width: float = 24.0
## Portique a l'entree d'un raccourci : la ou ses deux piliers sont sortis de
## la piste (cherche a partir de cette part de sa longueur).
const BRANCH_GATE_U := 0.08

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
## Flancs inclines (m de chaque cote, au sol ; 0 : flancs verticaux). En arene
## (2026-10-21), on aborde un tremplin de tous les cotes : un flanc vertical
## de 1,7 m arretait net un camion (ou sa remorque) qui le prenait de biais.
@export var jump_side_run: float = 0.0

@export_group("Ponts")
## Epaisseur du tablier sous le bord de la chaussee.
@export var bridge_deck_depth: float = 1.6
## Hauteur du bord bas de la chaussee au-dessus du sol a partir de laquelle un
## segment "bridge" devient un tablier sur piles.
@export var bridge_min_height: float = 3.0
@export var bridge_pillar_spacing: float = 44.0

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
## Couloirs des rangs suivants (vide : les memes). En quinconce, un camion du
## 2e rang a la voie libre devant lui, entre deux camions du 1er.
@export var grid_back_lateral: PackedFloat32Array = []

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
var _segment_ends: Dictionary = {}      # nom -> abscisse de la fin (m)
## Raccourcis resolus : {name, s0, s1, w, a, b, dir, right, len, pts}.
var _br: Array[Dictionary] = []
## Murs de la piste ouverts (1) par echantillon, gauche puis droite.
var _wall_open: Array[PackedByteArray] = [PackedByteArray(), PackedByteArray()]
## Pieges des raccourcis (indices apres ceux de la piste) : [repere, rayon].
var _branch_puddles: Array = []
var _branch_barrels: Array[Transform3D] = []
var _puddles: Array[Vector3] = []       # (s, decalage, rayon)
var _signs: Array[Vector2] = []         # (s, decalage)
var _barrels: Array[Vector2] = []       # (s, decalage)
var _pickups: Array[Vector3] = []       # (s, decalage, TrackPickup.Kind)
var _auto_lengths: PackedFloat32Array = []
## Habillage resolu a la construction.
var theme: TrackTheme
var _bridge: PackedByteArray = []       # par echantillon : 0, 1 (beton), 2 (bois)
var _deck: PackedByteArray = []         # par echantillon : 1 = tablier sur piles
## Masque terre / mer (theme cotier) : R = terre, V = interieur de la boucle.
var _coast_image: Image
var _coast_origin: Vector2
var _coast_size: float = 1.0


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
	theme = TrackTheme.of(theme_id)
	if not _build_centerline():
		return
	_build_branches()
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
		return _branch_mapped(p, best)
	for i in n:
		var d := _pos[i].distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = i
	return _branch_mapped(p, best)


## Sur un raccourci, hors de la chaussee de la piste : l'echantillon du detour
## a la meme part du chemin (sa progression suit le detour) ; sinon `best`.
func _branch_mapped(p: Vector3, best: int) -> int:
	if _br.is_empty():
		return best
	var k := on_branch(p, 2.0)
	if k < 0 or absf((p - _pos[best]).dot(_right[best])) <= width / 2.0 + 1.0:
		return best
	return index_at_s(branch_progress_s(k, p))


## Plus petite distance HORIZONTALE (m) entre `p` et la ligne centrale d'une
## autre portion de piste que celle de l'abscisse `s` (a plus de
## SAME_SECTION_M), INF s'il n'y en a pas. `out` (non vide) recoit en [0]
## l'indice de l'echantillon le plus proche. Un circuit en 8 se croise :
## c'est la qu'elle est petite.
func other_section_distance(p: Vector3, s: float, out: Array = []) -> float:
	_ensure_built()
	var n := _pos.size()
	var best := INF
	var best_i := -1
	for j in range(0, n, 2):
		var ds := absf(_s[j] - s)
		if minf(ds, _length - ds) < SAME_SECTION_M:
			continue
		var d := Vector2(_pos[j].x - p.x, _pos[j].z - p.z).length()
		if d < best:
			best = d
			best_i = j
	if not out.is_empty():
		out[0] = best_i
	return best


## Repere pose sur la chaussee a l'echantillon i, decale lateralement, oriente
## dans le sens de course (avant du camion en -Z), `lift` metres au-dessus.
func frame_at(i: int, lateral: float, lift: float) -> Transform3D:
	var r := sample_right(i)
	var u := sample_up(i)
	var f := sample_forward(i)
	return Transform3D(Basis(r, u, -f), sample_position(i) + r * lateral + u * lift)


## Case de depart `slot` (0 = pole) : rangs derriere la ligne, le 1er dans les
## couloirs `grid_lateral`, les suivants dans `grid_back_lateral`.
@warning_ignore("integer_division")
## Place `slot` de la grille : un rang de grid_lateral, puis, avec
## grid_back_lateral, un rang en quinconce et un rang plein en alternance
## (4, 2, 4, 2 : 12 camions en 4 rangs, 2026-10-22 ; avant, les places 6 et 7
## tombaient sur les 4 et 5).
func get_start_transform(slot: int) -> Transform3D:
	_ensure_built()
	var row := 0
	var col := slot
	while true:
		var width_row := grid_lateral.size()
		if row % 2 == 1 and not grid_back_lateral.is_empty():
			width_row = grid_back_lateral.size()
		if col < width_row:
			break
		col -= width_row
		row += 1
	var s := _length - grid_distance - row * grid_row_spacing
	var i := roundi(s / (_length / _pos.size()))
	var lateral := grid_lateral[col]
	if row % 2 == 1 and not grid_back_lateral.is_empty():
		lateral = grid_back_lateral[col]
	return frame_at(i, lateral, 0.0)


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
	if k >= _puddles.size():
		return _branch_puddles[k - _puddles.size()][0]
	return frame_at(index_at_s(_puddles[k].x), _puddles[k].y, 0.0)


func puddle_radius(k: int) -> float:
	if k >= _puddles.size():
		return float(_branch_puddles[k - _puddles.size()][1])
	return _puddles[k].z


func sign_count() -> int:
	_ensure_built()
	return _signs.size()


## Le panneau k (noeud RoadsideSign), ou null avant la construction.
func sign_node(k: int) -> RoadsideSign:
	return get_node_or_null("Signs/Sign%d" % k) as RoadsideSign


func pickup_count() -> int:
	_ensure_built()
	return _pickups.size()


func pickup_node(k: int) -> TrackPickup:
	return get_node_or_null("Pickups/Pickup%d" % k) as TrackPickup


func barrel_count() -> int:
	_ensure_built()
	return _barrels.size()


func barrel_node(k: int) -> ExplosiveBarrel:
	return get_node_or_null("Barrels/Barrel%d" % k) as ExplosiveBarrel


func barrel_transform(k: int) -> Transform3D:
	_ensure_built()
	return frame_at(index_at_s(_barrels[k].x), _barrels[k].y, 0.0)


func jump_pad_count() -> int:
	_ensure_built()
	return _jumps.size()


## Bord d'attaque de la rampe de saut k, au milieu, dans le sens de course.
func jump_pad_transform(k: int) -> Transform3D:
	_ensure_built()
	return frame_at(index_at_s(_jumps[k].x), _jumps[k].y, 0.0)


## Vrai si un camion pose en `p` est a `margin` m au moins (au sol) des
## tremplins (rampes jumelles comprises), barils, plaques de boost et flaques.
func clear_spot(p: Vector3, margin: float) -> bool:
	_ensure_built()
	for j in _jumps:
		var i := index_at_s(j.x)
		var a := _pos[i] + _right[i] * j.y
		var f := Vector2(_fwd[i].x, _fwd[i].z).normalized()
		var reach := (2.0 if jumps_both_ways else 1.0) * jump_length
		var t := clampf(Vector2(p.x - a.x, p.z - a.z).dot(f), 0.0, reach)
		if (Vector2(p.x - a.x, p.z - a.z) - f * t).length() < jump_width / 2.0 + jump_side_run + margin:
			return false
	for k in barrel_count():
		var q := barrel_transform(k).origin
		if Vector2(p.x - q.x, p.z - q.z).length() < ExplosiveBarrel.BARREL_RADIUS + margin:
			return false
	for k in boost_pad_count():
		var q := boost_pad_transform(k).origin
		if Vector2(p.x - q.x, p.z - q.z).length() < boost_pad_size.length() / 2.0 + margin:
			return false
	for k in puddle_count():
		var q := puddle_transform(k).origin
		if Vector2(p.x - q.x, p.z - q.z).length() < puddle_radius(k) + margin:
			return false
	return true


## Vrai si l'echantillon i est sur un tablier de pont (piles, vide dessous).
func is_bridge_deck(i: int) -> bool:
	_ensure_built()
	return _deck[posmod(i, _pos.size())] == 1


## Vrai si le sol est de l'eau a la verticale de `p` (theme cotier ; toujours
## faux ailleurs). Purement visuel : le sol physique est le meme partout.
func is_water(p: Vector3) -> bool:
	_ensure_built()
	if _coast_image == null:
		return false
	var u := (Vector2(p.x, p.z) - _coast_origin) / _coast_size
	if u.x < 0.0 or u.y < 0.0 or u.x >= 1.0 or u.y >= 1.0:
		return true
	var size := _coast_image.get_size()
	return _coast_image.get_pixel(int(u.x * size.x), int(u.y * size.y)).r < 0.5


## Reapparition au plus pres de `p` : sur la chaussee, dans le sens de course,
## ecart lateral conserve mais ramene a 2 m des murs (10 % de la largeur sur
## une piste large : un camion replace contre le mur s'y couchait), 1 m
## au-dessus du sol.
func get_respawn_transform(p: Vector3) -> Transform3D:
	_ensure_built()
	# tombe dans le vide d'un saut : apres le bord de reception
	for k in _br.size():
		var j: PackedFloat32Array = _br[k]["jump"]
		if j.is_empty():
			continue
		var c := _branch_coords(k, p)
		var length := float(_br[k]["len"])
		var half := float(_br[k]["w"]) / 2.0
		if c.x > j[0] - BRANCH_RAMP_M / length and c.x < j[1] and absf(c.y) < half + 8.0 \
				and p.y < _branch_center_y(k, c.x) - 1.5:
			return branch_frame(k, j[1] + BRANCH_JUMP_RESPAWN_M / length, clampf(c.y, -half + 3.0, half - 3.0), 1.0)
	var kb := on_branch(p, 4.0)
	if kb >= 0:
		var c := _branch_coords(kb, p)
		var lim := float(_br[kb]["w"]) / 2.0 - 3.0
		return branch_frame(kb, clampf(c.x, 0.02, 0.98), clampf(c.y, -lim, lim), 1.0)
	var i := closest_sample(p)
	var lateral := (p - sample_position(i)).dot(sample_right(i))
	var limit := width / 2.0 - maxf(2.0, width * 0.1)
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
	_segment_ends.clear()
	_puddles.clear()
	_signs.clear()
	_barrels.clear()
	_pickups.clear()
	var seg_start := 0.0
	for k in segments.size():
		var seg: Dictionary = segments[k]
		_segment_starts[String(seg.get("name", "%d" % k))] = seg_start
		_segment_ends[String(seg.get("name", "%d" % k))] = seg_start + lengths[k]
		if seg.has("jump"):
			_jumps.append(Vector2(seg_start + float(seg["jump"]), float(seg.get("jump_offset", jump_offset))))
		for b: Array in seg.get("boost", []):
			_boosts.append(Vector2(seg_start + float(b[0]), float(b[1])))
		for pd: Array in seg.get("puddle", []):
			_puddles.append(Vector3(seg_start + float(pd[0]), float(pd[1]), float(pd[2])))
		for sg: Array in seg.get("signs", []):
			_signs.append(Vector2(seg_start + float(sg[0]), float(sg[1])))
		for br: Array in seg.get("barrels", []):
			_barrels.append(Vector2(seg_start + float(br[0]), float(br[1])))
		for pk: Array in seg.get("pickups", []):
			var kind := TrackPickup.Kind.REPAIR if String(pk[1]) == "repair" else TrackPickup.Kind.POWER
			for _n in PICKUPS_PER_ENTRY:
				_pickups.append(Vector3(seg_start + float(pk[0]), 0.0, kind))
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
	_bridge.resize(count)
	_deck.resize(count)
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
		_bridge[i] = int(seg.get("bridge", 0))
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
	# tablier sur piles : segment "bridge" et bord bas de la chaussee assez haut
	for i in count:
		var low := _pos[i].y - absf(_right[i].y) * width / 2.0
		_deck[i] = 1 if _bridge[i] > 0 and low - GROUND_Y > bridge_min_height else 0
	# apres les reperes : en arene, les places se jugent au sol
	_scatter_pickups()
	return true


## Bonus epars (2026-10-21 : « pas des rangées sur la piste, plutôt répartis
## un peu aléatoirement, un peu comme les barils ») : autant de bonus que
## demandes par les segments, de sortes melangees, un par tranche egale du
## tour (de PICKUP_START_M a la grille de depart), a une abscisse et un
## decalage tires dans la tranche, loin des tremplins, plaques, flaques,
## barils et panneaux. Generateur fixe, comme les gouttes de pluie (CLAUDE.md
## §7) : le meme trace donne les memes places sur toutes les machines (en
## ligne, Ev.PICKUP designe un bonus par son numero).
func _scatter_pickups() -> void:
	var kinds: Array[int] = []
	for p in _pickups:
		kinds.append(int(p.z))
	_pickups.clear()
	var n := kinds.size()
	if n == 0:
		return
	var lcg := PICKUP_SEED + roundi(_length)
	# reparations et recharges melangees (Fisher-Yates)
	for k in range(n - 1, 0, -1):
		lcg = _lcg(lcg)
		var j := lcg % (k + 1)
		var tmp := kinds[k]
		kinds[k] = kinds[j]
		kinds[j] = tmp
	# grille de 6 camions (hors ligne ; en ligne jusqu'a 12, LocalRace.MAX_TRUCKS :
	# leurs 2 derniers rangs peuvent alors froler le dernier bonus du tour)
	var rows := ceili(6.0 / maxf(grid_lateral.size(), 1.0))
	var hi := _length - grid_distance - rows * grid_row_spacing - 20.0
	var span := (hi - PICKUP_START_M) / n
	var half := maxf(width / 2.0 - PICKUP_EDGE_M, 0.0)
	for k in n:
		var at := Vector2.ZERO
		for _try in 16:
			lcg = _lcg(lcg)
			at.x = PICKUP_START_M + span * (k + 0.1 + 0.8 * float(lcg % 10000) / 10000.0)
			lcg = _lcg(lcg)
			at.y = (float(lcg % 10000) / 5000.0 - 1.0) * half
			if pickup_clear(at.x, at.y):
				break
		_pickups.append(Vector3(at.x, at.y, kinds[k]))


## Une place de bonus (abscisse, decalage) loin des pieges ?
func pickup_clear(s: float, lateral: float) -> bool:
	for j in _jumps:
		if jumps_both_ways:
			# arene : la bosse (deux rampes dos a dos, en ligne droite) et les
			# envols des deux cotes, au sol (sur un anneau de 160 m, l'abscisse
			# ne mesure pas la distance loin du milieu)
			var i := index_at_s(j.x)
			var a := _pos[i] + _right[i] * j.y
			var p := frame_at(index_at_s(s), lateral, 0.0).origin
			var t := clampf((p - a).dot(_fwd[i]), -PICKUP_JUMP_RUN_M, 2.0 * jump_length + PICKUP_JUMP_RUN_M)
			if (p - (a + _fwd[i] * t)).length() < jump_width / 2.0 + jump_side_run + PICKUP_CLEAR_M:
				return false
		# la rampe, puis l'envol et la reception
		elif s > j.x - PICKUP_CLEAR_M and s < j.x + jump_length + 50.0:
			return false
	for b in _boosts + _barrels + _signs:
		if Vector2(s - b.x, lateral - b.y).length() < PICKUP_CLEAR_M:
			return false
	for pd in _puddles:
		if Vector2(s - pd.x, lateral - pd.y).length() < pd.z + PICKUP_CLEAR_M / 2.0:
			return false
	return true


## Pas du generateur congruentiel fixe (memes constantes que l'ambiance).
static func _lcg(v: int) -> int:
	return (v * 1103515245 + 12345) & 0x7fffffff


## Place du bonus `k` : (abscisse, decalage, TrackPickup.Kind).
func pickup_place(k: int) -> Vector3:
	_ensure_built()
	return _pickups[k]


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
		st.set_color(Color(_bridge[i] * 0.5, 0.0, 0.0))
		_quad(st, road_tris, l0, r0, r1, l1, Vector2(0, v0), Vector2(1, v0), Vector2(1, v1), Vector2(0, v1), _up[i])
	var road_mat := theme.road.duplicate() as ShaderMaterial
	road_mat.set_shader_parameter("road_width", width)
	road_mat.set_shader_parameter("finish_line", race_markings)
	var road := _static_body(geometry, "Road", st, road_tris, road_mat, 1.0)
	road.set_meta(&"surface", &"asphalt")

	# glissieres : profil vertical dans le monde (independant du devers),
	# face interieure penchee vers la piste, face exterieure jusqu'au sol
	for side: float in [-1.0, 1.0]:
		var wst := SurfaceTool.new()
		wst.begin(Mesh.PRIMITIVE_TRIANGLES)
		var wtris := PackedVector3Array()
		var opened := _wall_open[0 if side < 0.0 else 1]
		for i in n:
			var j := (i + 1) % n
			# un raccourci traverse le mur : ouvert
			if not opened.is_empty() and (opened[i] == 1 or opened[j] == 1):
				continue
			var a := _wall_profile(i, side)
			var b := _wall_profile(j, side)
			var v0 := _s[i]
			var v1 := _s[i] + _length / n
			wst.set_color(Color(_bridge[i] * 0.5, 0.0, 0.0))
			for k in 3:
				if side > 0.0:
					_quad(wst, wtris, a[k], b[k], b[k + 1], a[k + 1],
						Vector2(k, v0), Vector2(k, v1), Vector2(k + 1, v1), Vector2(k + 1, v0), Vector3.ZERO)
				else:
					_quad(wst, wtris, a[k], a[k + 1], b[k + 1], b[k],
						Vector2(k, v0), Vector2(k + 1, v0), Vector2(k + 1, v1), Vector2(k, v1), Vector3.ZERO)
		var wall := _static_body(walls, "WallLeft" if side < 0.0 else "WallRight", wst, wtris,
			theme.wall, wall_friction)
		wall.set_meta(&"surface", &"asphalt")
		_build_wall_neon(walls, side)

	_build_branch_roads(geometry, walls)

	# sol sous toute la piste et la ville (hors piste : lent, pas de vide)
	# sur une ile, la mer va jusqu'a l'horizon
	var span := _bounds_span() + (9000.0 if theme.coast else 2400.0)
	var gst := SurfaceTool.new()
	gst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gtris := PackedVector3Array()
	var c := _bounds_center()
	var h := span / 2.0
	_quad(gst, gtris, c + Vector3(-h, GROUND_Y, -h), c + Vector3(-h, GROUND_Y, h),
		c + Vector3(h, GROUND_Y, h), c + Vector3(h, GROUND_Y, -h),
		Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector3.UP)
	var ground_mat := theme.ground
	if theme.coast:
		_build_coast_mask()
		var coast_mat := theme.ground.duplicate() as ShaderMaterial
		coast_mat.set_shader_parameter("coast_mask", ImageTexture.create_from_image(_coast_image))
		coast_mat.set_shader_parameter("coast_origin", _coast_origin)
		coast_mat.set_shader_parameter("coast_size", _coast_size)
		ground_mat = coast_mat
	var ground := _static_body(geometry, "Ground", gst, gtris, ground_mat, 1.0)
	ground.set_meta(&"surface", &"grass")

	_build_bridges(_group("Bridges"))
	if theme.embankment != null:
		_build_embankments(_group("Embankments"))

	var arches := _group("Arches")
	for k in _arches.size():
		_build_arch(arches, float(_arches[k]["s"]), String(_arches[k]["label"]), k)

	var signs := _group("Signs")
	for k in _signs.size():
		_build_sign(signs, _signs[k].x, _signs[k].y, k)

	var barrels := _group("Barrels")
	for k in _barrels.size():
		_build_barrel(barrels, _barrels[k].x, _barrels[k].y, k)

	var pads := _group("Pads")
	for k in _jumps.size():
		_build_jump(pads, _jumps[k].x, _jumps[k].y, k)
		if jumps_both_ways:
			# rampe jumelle dos a dos, dans l'axe de la premiere, en ligne droite
			# (avant : a l'abscisse s + 2 L ; sur un arc, decalee vers l'interieur
			# elle chevauchait la premiere, vers l'exterieur elle s'en ecartait
			# de travers)
			var i := index_at_s(_jumps[k].x)
			_build_ramp(pads, _pos[i] + _right[i] * _jumps[k].y + _fwd[i] * (2.0 * jump_length), -_fwd[i],
				-_right[i], _up[i], jump_width / 2.0, jump_length, jump_length * tan(deg_to_rad(jump_angle_deg)),
				"JumpPad%dB" % k, "JumpTrigger%dB" % k, k)
	for k in _boosts.size():
		_build_boost_pad(pads, _boosts[k].x, _boosts[k].y, k)
	for k in _puddles.size():
		_build_puddle(pads, _puddles[k], k)
	_build_branch_hazards(pads, barrels)

	var pickups := _group("Pickups")
	for k in _pickups.size():
		var pk := TrackPickup.new()
		pk.name = "Pickup%d" % k
		pk.kind = int(_pickups[k].z) as TrackPickup.Kind
		pk.index = k
		pk.transform = frame_at(index_at_s(_pickups[k].x), _pickups[k].y, 0.0)
		pk.taken.connect(func(t: Truck, p: TrackPickup) -> void: pickup_taken.emit(t, int(p.kind), p.index))
		pickups.add_child(pk)

	_build_reset_zones(zones)
	_build_checkpoints(checkpoints)
	_build_branch_checkpoints(checkpoints)

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
	# sur un pont, le mur s'arrete sous le tablier : on voit dessous
	var bottom_y := edge.y - bridge_deck_depth if _deck[i] == 1 else minf(GROUND_Y - 0.1, edge.y - 0.3)
	var outer_bottom := Vector3(outer_top.x, bottom_y, outer_top.z)
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
	var opened := _wall_open[0 if side < 0.0 else 1]
	for i in n:
		if not opened.is_empty() and (opened[i] == 1 or opened[(i + 1) % n] == 1):
			continue
		var a := strip[i]
		var b := strip[(i + 1) % n]
		_quad(st, tris, a[0], b[0], b[1], a[1], z2, z2, z2, z2, Vector3.ZERO)
		_quad(st, tris, a[1], b[1], b[2], a[2], z2, z2, z2, z2, Vector3.ZERO)
	var mi := MeshInstance3D.new()
	mi.name = "NeonLeft" if side < 0.0 else "NeonRight"
	mi.mesh = st.commit()
	mi.material_override = theme.edge_left if side < 0.0 else theme.edge_right
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## Ponts : dessous du tablier (la ou les murs s'arretent sous la chaussee) et
## piles tous les bridge_pillar_spacing : deux futs de beton et leur chevetre,
## ou quatre pieux de bois. Purement visuel (la chaussee porte les camions).
func _build_bridges(parent: Node3D) -> void:
	var n := _pos.size()
	var z2 := Vector2.ZERO
	var dummy := PackedVector3Array()
	var under: Array[SurfaceTool] = [SurfaceTool.new(), SurfaceTool.new()]
	var used := [false, false]
	for st in under:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var next_pier := 0.0
	var piers := 0
	for i in n:
		if _deck[i] == 0:
			continue
		var j := (i + 1) % n
		var kind := clampi(_bridge[i], 1, 2) - 1
		var al := _wall_profile(i, -1.0)[3]
		var ar := _wall_profile(i, 1.0)[3]
		if _deck[j] == 1:
			var bl := _wall_profile(j, -1.0)[3]
			var br := _wall_profile(j, 1.0)[3]
			_quad(under[kind], dummy, al, bl, br, ar, z2, z2, z2, z2, Vector3.ZERO)
			used[kind] = true
		if _s[i] < next_pier:
			continue
		# au-dessus de l'autre branche (circuit en 8) : pas de pile, le tablier
		# franchit la route d'une seule portee
		if other_section_distance(Vector3(_pos[i].x, 0.0, _pos[i].z), _s[i]) \
				< width + wall_thickness + 6.0:
			continue
		next_pier = _s[i] + bridge_pillar_spacing
		var t := Vector3(_fwd[i].x, 0.0, _fwd[i].z).normalized()
		var r := t.cross(Vector3.UP).normalized()
		var pier := Node3D.new()
		pier.name = "Pier%d" % piers
		piers += 1
		var low := minf(al.y, ar.y)
		pier.transform = Transform3D(Basis(r, Vector3.UP, -t), Vector3(_pos[i].x, 0.0, _pos[i].z))
		parent.add_child(pier)
		var mat := theme.bridge_concrete if kind == 0 else theme.bridge_wood
		var foot := GROUND_Y - 3.0
		_box(pier, Vector3(width + 2.0, 1.2, 3.2 if kind == 0 else 1.0), Vector3(0.0, low - 0.6, 0.0), mat)
		var laterals: Array[float] = [-width / 2.0 + 8.0, width / 2.0 - 8.0]
		if kind == 1:
			laterals = [-width / 2.0 + 2.0, -width / 6.0, width / 6.0, width / 2.0 - 2.0]
		for x in laterals:
			var cm := CylinderMesh.new()
			cm.top_radius = 2.2 if kind == 0 else 0.75
			cm.bottom_radius = cm.top_radius * (1.15 if kind == 0 else 1.0)
			cm.height = low - 1.2 - foot
			cm.radial_segments = 16 if kind == 0 else 8
			var col := MeshInstance3D.new()
			col.mesh = cm
			col.material_override = mat
			col.position = Vector3(x, foot + cm.height / 2.0, 0.0)
			pier.add_child(col)
	for kind in 2:
		if not used[kind]:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "DeckUnderConcrete" if kind == 0 else "DeckUnderWood"
		under[kind].generate_normals()
		mi.mesh = under[kind].commit()
		mi.material_override = theme.bridge_concrete if kind == 0 else theme.bridge_wood
		parent.add_child(mi)


## Talus : sous les portions hautes (hors ponts), une pente de roche descend
## du haut exterieur du mur jusqu'au sol, plus large quand la route est plus
## haute : la route court sur une crete, pas sur un mur. Purement visuel.
func _build_embankments(parent: Node3D) -> void:
	var n := _pos.size()
	for side: float in [-1.0, 1.0]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var dummy := PackedVector3Array()
		var rows: Array[PackedVector3Array] = []
		var reach := PackedFloat32Array()
		for i in n:
			var prof := _wall_profile(i, side)
			var out := Vector3(_right[i].x, 0.0, _right[i].z).normalized() * side
			var top := prof[2] - Vector3(0.0, 0.2, 0.0)
			var h := top.y - GROUND_Y
			var d := 0.0
			if _deck[i] == 0 and h > wall_height + 1.0:
				# pente irreguliere (deterministe), plus longue quand c'est haut
				d = (h * 1.25 + 3.0) * (1.0 + 0.18 * sin(_s[i] * 0.05 + side) + 0.12 * sin(_s[i] * 0.017))
			var foot := Vector3(top.x, GROUND_Y + 0.02, top.z) + out * d
			var mid := top.lerp(foot, 0.42)
			mid.y = top.y - h * 0.3
			rows.append(PackedVector3Array([top, mid, foot]))
			reach.append(d)
		for i in n:
			var j := (i + 1) % n
			if reach[i] == 0.0 and reach[j] == 0.0:
				continue
			var a := rows[i]
			var b := rows[j]
			var v0 := _s[i]
			var v1 := _s[i] + _length / n
			for k in 2:
				if side > 0.0:
					_quad(st, dummy, a[k], b[k], b[k + 1], a[k + 1],
						Vector2(v0, k * 0.5), Vector2(v1, k * 0.5), Vector2(v1, k * 0.5 + 0.5), Vector2(v0, k * 0.5 + 0.5), Vector3.ZERO)
				else:
					_quad(st, dummy, a[k], a[k + 1], b[k + 1], b[k],
						Vector2(v0, k * 0.5), Vector2(v0, k * 0.5 + 0.5), Vector2(v1, k * 0.5 + 0.5), Vector2(v1, k * 0.5), Vector3.ZERO)
		var mi := MeshInstance3D.new()
		mi.name = "EmbankmentLeft" if side < 0.0 else "EmbankmentRight"
		st.generate_normals()
		mi.mesh = st.commit()
		mi.material_override = theme.embankment
		parent.add_child(mi)


## Masque terre / mer d'un circuit cotier, en image (256 x 256, le trace au
## centre) : de la terre dans un rayon coast_land_radius autour du trace (sauf
## sous les tabliers de pont), tout l'interieur de la boucle (remplissage
## depuis les bords : ce que l'eau n'atteint pas, la boucle entiere faisant
## barrage, est a l'interieur), puis une baie creusee sous chaque tablier ;
## bords adoucis (le shader y pose le rivage). Deterministe.
func _build_coast_mask() -> void:
	var res := 256
	var span := _bounds_span() + 900.0
	var c := _bounds_center()
	_coast_size = span
	_coast_origin = Vector2(c.x, c.z) - Vector2(span, span) / 2.0
	var texel := span / res
	var land := PackedByteArray()
	land.resize(res * res)
	var barrier := PackedByteArray()
	barrier.resize(res * res)
	var n := _pos.size()
	var every := maxi(1, roundi(10.0 / (_length / n)))
	# 1. terre autour du trace ; la boucle entiere (ponts compris) fait barrage
	for i in range(0, n, every):
		_stamp(barrier, res, texel, _pos[i], theme.coast_land_radius, 1)
		if _deck[i] == 0:
			_stamp(land, res, texel, _pos[i], theme.coast_land_radius, 1)
	# raccourcis : de la terre aussi
	for bd: Dictionary in _br:
		var pts: PackedVector3Array = bd["pts"]
		for q in range(0, pts.size(), maxi(1, every)):
			_stamp(barrier, res, texel, pts[q], theme.coast_land_radius * 0.6, 1)
			_stamp(land, res, texel, pts[q], theme.coast_land_radius * 0.6, 1)
	# 2. interieur de la boucle : ce que l'eau venue des bords n'atteint pas
	var outside := PackedByteArray()
	outside.resize(res * res)
	var stack := PackedInt32Array([0])
	outside[0] = 1
	while not stack.is_empty():
		var k := stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		var x := k % res
		@warning_ignore("integer_division")
		var y := k / res
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx := x + d.x
			var ny := y + d.y
			if nx < 0 or ny < 0 or nx >= res or ny >= res:
				continue
			var nk := ny * res + nx
			if outside[nk] == 0 and barrier[nk] == 0:
				outside[nk] = 1
				stack.append(nk)
	var inner := PackedByteArray()
	inner.resize(res * res)
	for k in res * res:
		if barrier[k] == 0 and outside[k] == 0:
			land[k] = 1
			inner[k] = 1
	# 3. baies sous les tabliers
	for i in range(0, n, every):
		if _deck[i] == 1:
			_stamp(land, res, texel, _pos[i], theme.coast_bay_radius, 0)
			_stamp(inner, res, texel, _pos[i], theme.coast_bay_radius + 40.0, 0)
	# 4. bords adoucis, puis image
	var soft := _blur(_blur(_blur(land, res), res), res)
	var soft_inner := _blur(_blur(_blur(inner, res), res), res)
	var data := PackedByteArray()
	data.resize(res * res * 3)
	for k in res * res:
		data[k * 3] = soft[k]
		data[k * 3 + 1] = soft_inner[k]
		data[k * 3 + 2] = 0
	_coast_image = Image.create_from_data(res, res, false, Image.FORMAT_RGB8, data)


## Disque de rayon `radius` (m) autour de `p`, pose a `value` dans la grille.
func _stamp(grid: PackedByteArray, res: int, texel: float, p: Vector3, radius: float, value: int) -> void:
	var cx := (p.x - _coast_origin.x) / texel
	var cy := (p.z - _coast_origin.y) / texel
	var r := radius / texel
	for y in range(maxi(0, floori(cy - r)), mini(res, ceili(cy + r) + 1)):
		for x in range(maxi(0, floori(cx - r)), mini(res, ceili(cx + r) + 1)):
			if (x + 0.5 - cx) * (x + 0.5 - cx) + (y + 0.5 - cy) * (y + 0.5 - cy) <= r * r:
				grid[y * res + x] = value


## Flou 3 x 3 d'une grille 0 / 1 (ou deja floue) : valeurs 0 .. 255 en sortie.
static func _blur(grid: PackedByteArray, res: int) -> PackedByteArray:
	var scale := 255 if grid.count(1) + grid.count(0) == grid.size() else 1
	var out := PackedByteArray()
	out.resize(res * res)
	for y in res:
		for x in res:
			var acc := 0
			for dy in range(-1, 2):
				var yy := clampi(y + dy, 0, res - 1)
				for dx in range(-1, 2):
					acc += grid[yy * res + clampi(x + dx, 0, res - 1)]
			@warning_ignore("integer_division")
			out[y * res + x] = acc * scale / 9
	return out


## Arche lumineuse : deux piliers au-dela des murs, une poutre au-dessus de la
## chaussee (arch_height de hauteur libre), tubes neon, enseigne tournee vers
## les camions qui arrivent, et une lumiere qui colore la piste dessous.
## Purement visuelle : aucune collision (ni camion, ni camera).
func _build_arch(parent: Node3D, s: float, label: String, index: int, at: Transform3D = Transform3D(),
		span: float = -1.0) -> void:
	if theme.arch_style == TrackTheme.ArchStyle.TORII:
		_build_torii(parent, s, label, index, at, span)
		return
	var i := index_at_s(s)
	var t := Vector3(_fwd[i].x, 0.0, _fwd[i].z).normalized()
	var r := t.cross(Vector3.UP).normalized()
	var arch_basis := Basis(r, Vector3.UP, -t)
	var base := _pos[i]
	var half := width / 2.0 + 3.0
	# pose donnee (entree d'un raccourci) : son repere, sa largeur
	if span > 0.0:
		arch_basis = at.basis
		base = at.origin
		half = span / 2.0 + 3.0
	var neon: Material = theme.arch_tubes[index % theme.arch_tubes.size()]
	var neon_color := theme.arch_colors[index % theme.arch_colors.size()]
	var root := Node3D.new()
	root.name = "Arch%d" % index
	root.transform = Transform3D(arch_basis, base)
	parent.add_child(root)
	var beam_y := arch_height + 1.2
	var ground := GROUND_Y - base.y
	for side: float in [-1.0, 1.0]:
		var h := beam_y + 1.2 - ground
		_box(root, Vector3(2.2, h, 2.2), Vector3(side * half, ground + h / 2.0, 0.0), theme.arch_frame)
		# tube neon sur la face du pilier tournee vers la piste
		_box(root, Vector3(0.25, h - 1.5, 0.25), Vector3(side * (half - 1.15), ground + h / 2.0, 0.0), neon)
	_box(root, Vector3(half * 2.0 + 2.2, 2.4, 2.6), Vector3(0.0, beam_y, 0.0), theme.arch_frame)
	for z: float in [-1.35, 1.35]:
		_box(root, Vector3(half * 2.0, 0.22, 0.22), Vector3(0.0, beam_y - 1.25, z), neon)
		_box(root, Vector3(half * 2.0, 0.22, 0.22), Vector3(0.0, beam_y + 1.25, z), neon)
	if label != "":
		var l := Label3D.new()
		l.name = "Sign"
		l.text = label
		l.font_size = 220
		l.pixel_size = 0.02
		l.outline_size = theme.arch_label_outline
		l.outline_modulate = Color(0.02, 0.06, 0.14)
		l.modulate = Color(neon_color.r * 2.2, neon_color.g * 2.2, neon_color.b * 2.2)
		l.double_sided = false
		# face avant vers les camions qui arrivent (-t = +Z local)
		l.position = Vector3(0.0, beam_y, 1.32)
		root.add_child(l)
	if theme.arch_light_energy > 0.0:
		var light := OmniLight3D.new()
		light.light_color = neon_color
		light.light_energy = theme.arch_light_energy
		light.omni_range = 34.0
		light.position = Vector3(0.0, beam_y - 2.0, 0.0)
		root.add_child(light)


## Torii (theme Sakura) : deux piliers vermillon sur socle noir au-dela des
## murs, linteau bas (nuki), double linteau haut (shimaki vermillon, kasagi
## noir aux extremites relevees), plaque centrale a l'enseigne, et deux
## grandes lanternes de papier rouges suspendues. Purement visuel.
func _build_torii(parent: Node3D, s: float, label: String, index: int, at: Transform3D = Transform3D(),
		span: float = -1.0) -> void:
	var i := index_at_s(s)
	var t := Vector3(_fwd[i].x, 0.0, _fwd[i].z).normalized()
	var r := t.cross(Vector3.UP).normalized()
	var base := _pos[i]
	var half := width / 2.0 + 4.0
	var torii_basis := Basis(r, Vector3.UP, -t)
	if span > 0.0:
		torii_basis = at.basis
		base = at.origin
		half = span / 2.0 + 4.0
	var root := Node3D.new()
	root.name = "Arch%d" % index
	root.transform = Transform3D(torii_basis, base)
	parent.add_child(root)
	var red: Material = theme.arch_tubes[0]
	var black: Material = theme.arch_frame
	var ground := GROUND_Y - base.y
	var nuki_y := arch_height + 1.0
	var top_y := arch_height + 7.5
	for side: float in [-1.0, 1.0]:
		var h := top_y - ground
		var col := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 1.25
		cm.bottom_radius = 1.45
		cm.height = h
		cm.radial_segments = 20
		col.mesh = cm
		col.material_override = red
		col.position = Vector3(side * half, ground + h / 2.0, 0.0)
		root.add_child(col)
		# socle noir (kamaki)
		var foot := MeshInstance3D.new()
		var fm := CylinderMesh.new()
		fm.top_radius = 1.6
		fm.bottom_radius = 1.7
		fm.height = 2.4
		fm.radial_segments = 20
		foot.mesh = fm
		foot.material_override = black
		foot.position = Vector3(side * half, ground + fm.height / 2.0, 0.0)
		root.add_child(foot)
	# nuki : linteau bas qui depasse un peu des piliers
	_box(root, Vector3(half * 2.0 + 7.0, 1.5, 1.3), Vector3(0.0, nuki_y, 0.0), red)
	# shimaki (vermillon) puis kasagi (noir), aux bouts releves
	_box(root, Vector3(half * 2.0 + 9.0, 1.3, 2.0), Vector3(0.0, top_y - 0.65, 0.0), red)
	_box(root, Vector3(half * 2.0 + 6.0, 1.2, 2.6), Vector3(0.0, top_y + 0.6, 0.0), black)
	for side: float in [-1.0, 1.0]:
		var tip := _box(root, Vector3(7.0, 1.1, 2.6), Vector3(side * (half + 5.6), top_y + 1.05, 0.0), black)
		tip.rotation.z = side * deg_to_rad(9.0)
	# gakuzuka : plaque verticale noire a liseré dore, kanji empiles
	var mid_y := (top_y + nuki_y) / 2.0 - 0.3
	_box(root, Vector3(3.6, 5.6, 0.5), Vector3(0.0, mid_y, 0.0), theme.arch_tubes[0])
	_box(root, Vector3(3.0, 5.0, 0.6), Vector3(0.0, mid_y, 0.0), black)
	if label != "":
		for face: float in [1.0, -1.0]:
			var l := Label3D.new()
			l.name = "Sign" if face > 0.0 else "SignBack"
			l.text = label
			l.font = TrackTheme.cjk_font()
			l.font_size = 110
			l.pixel_size = 0.0125
			l.line_spacing = -18.0
			l.outline_size = 0
			l.modulate = Color(1.0, 0.82, 0.35)
			l.double_sided = false
			l.position = Vector3(0.0, mid_y, 0.32 * face)
			if face < 0.0:
				l.rotation.y = PI
			root.add_child(l)
	# lanternes de papier suspendues sous le nuki, de chaque cote de la route
	for side: float in [-1.0, 1.0]:
		var x := side * (half - 9.0)
		_box(root, Vector3(0.12, 2.0, 0.12), Vector3(x, nuki_y - 1.75, 0.0), black)
		var lantern := MeshInstance3D.new()
		var lm := SphereMesh.new()
		lm.radius = 1.5
		lm.height = 4.2
		lm.radial_segments = 16
		lm.rings = 8
		lantern.mesh = lm
		lantern.material_override = theme.lantern
		lantern.position = Vector3(x, nuki_y - 4.6, 0.0)
		root.add_child(lantern)
		for cap_y: float in [-2.0, 2.0]:
			_box(root, Vector3(1.6, 0.35, 1.6), Vector3(x, nuki_y - 4.6 + cap_y, 0.0), black)


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
			# l'autre branche passe dans la zone (circuit en 8) : pas de zone ici,
			# AutoReset mesure la sortie de piste a la geometrie
			var zone_xf := Transform3D(zone_basis, center)
			if _box_hits_other_road(zone_xf, box.size, _s[mid]) or _box_hits_branch(zone_xf, box.size):
				area.free()
				continue
			area.transform = zone_xf
			area.body_entered.connect(_on_reset_zone_body_entered)
			area.body_exited.connect(_on_reset_zone_body_exited)
			parent.add_child(area)
		k += 1
		i += chunk


## Vrai si la boite `size` posee en `xf` touche la chaussee (murs compris)
## d'une autre portion de piste que celle de l'abscisse `s`.
func _box_hits_other_road(xf: Transform3D, size: Vector3, s: float) -> bool:
	var inv := xf.affine_inverse()
	var pad := width / 2.0 + wall_thickness + 2.0
	for j in range(0, _pos.size(), 2):
		var ds := absf(_s[j] - s)
		if minf(ds, _length - ds) < SAME_SECTION_M:
			continue
		var q := inv * _pos[j]
		if absf(q.x) < size.x / 2.0 + pad and absf(q.z) < size.z / 2.0 + pad and absf(q.y) < size.y / 2.0 + 3.0:
			return true
	return false


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
		# sous l'autre branche (circuit en 8) : la boite s'arrete sous son
		# tablier, un camion qui passe dessus ne la traverse pas
		var height := checkpoint_height
		var near := [-1]
		if other_section_distance(_pos[i], _s[i], near) < span / 2.0 + width / 2.0 + 4.0:
			var above := _pos[near[0]].y - bridge_deck_depth - 1.0 - _pos[i].y
			if above > 0.0:
				height = minf(height, above + 2.0)
		box.size = Vector3(span, height, checkpoint_depth)
		cs.shape = box
		cs.position = Vector3(0.0, height / 2.0 - 2.0, 0.0)
		area.add_child(cs)
		area.transform = frame_at(i, 0.0, 0.0)
		area.body_entered.connect(_on_checkpoint_body_entered.bind(k))
		parent.add_child(area)


## Doubles des checkpoints du detour, en travers de chaque raccourci : meme
## numero, a la meme part du chemin.
func _build_branch_checkpoints(parent: Node3D) -> void:
	for kb in _br.size():
		var bd := _br[kb]
		var s0 := float(bd["s0"])
		var s1 := float(bd["s1"])
		for k in checkpoint_count:
			var s := checkpoint_s(k)
			if s <= s0 or s >= s1:
				continue
			var area := Area3D.new()
			area.name = "CP%02dB%d" % [k, kb]
			area.collision_layer = 1 << (CHECKPOINT_LAYER - 1)
			area.collision_mask = 1 << (VEHICLE_LAYER - 1)
			area.monitorable = false
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(float(bd["w"]) + 2.0 * (wall_thickness + wall_lean + 1.0), checkpoint_height, checkpoint_depth)
			cs.shape = box
			cs.position = Vector3(0.0, checkpoint_height / 2.0 - 2.0, 0.0)
			area.add_child(cs)
			area.transform = branch_frame(kb, (s - s0) / (s1 - s0), 0.0, 0.0)
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


## Piege ralentisseur : disque irregulier (bord bruite, deterministe) pose
## sur la chaussee - flaque d'eau a ras du sol (miroir sombre aux rides
## animees) ou banc de sable legerement bombe, selon le theme ; zone de
## declenchement cylindrique. Aucune collision.
func _build_puddle(parent: Node3D, p: Vector3, index: int, at: Transform3D = Transform3D(), placed: bool = false) -> void:
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
		for v: Array in [[Vector3(0.0, 0.05 + theme.hazard_height, 0.0), Vector2(float(k) / n, 0.0)], [v1, Vector2(float(k + 1) / n, 1.0)],
				[v0, Vector2(float(k) / n, 1.0)]]:
			st.set_normal(Vector3.UP)
			st.set_uv(v[1])
			st.add_vertex(v[0])
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = st.commit()
	mi.material_override = theme.hazard
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	area.add_child(mi)
	area.transform = at if placed else frame_at(index_at_s(p.x), p.y, 0.0)
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


func _build_barrel(parent: Node3D, s: float, lateral: float, index: int, at: Transform3D = Transform3D(),
		placed: bool = false) -> void:
	var barrel := ExplosiveBarrel.new()
	barrel.name = "Barrel%d" % index
	barrel.apply_style(theme.barrel_style)
	barrel.transform = at if placed else frame_at(index_at_s(s), lateral, 0.0)
	barrel.exploded.connect(func(truck: Truck) -> void:
		barrel_hit.emit(truck, index))
	parent.add_child(barrel)


func _on_boost_pad_body_entered(body: Node3D, index: int) -> void:
	boost_pad_entered.emit(body, index)


func _on_jump_pad_body_entered(body: Node3D, index: int) -> void:
	jump_pad_entered.emit(body, index)


## Rampe de saut : prisme convexe, bord d'attaque au ras de la chaussee, face de
## roulement a chevrons bleus lumineux ; zone de declenchement au sommet.
func _build_jump(parent: Node3D, s: float, offset: float, index: int) -> void:
	var i := index_at_s(s)
	_build_ramp(parent, _pos[i] + _right[i] * offset, _fwd[i], _right[i], _up[i], jump_width / 2.0,
		jump_length, jump_length * tan(deg_to_rad(jump_angle_deg)), "JumpPad%d" % index, "JumpTrigger%d" % index,
		index)


## Rampe (corps convexe, face a chevrons) posee en `base` (milieu du bord
## d'attaque), vers `f`, demi-largeur `hw`, longueur `length`, sommet a
## `top` m ; sa zone de declenchement emet jump_pad_entered(`index`).
func _build_ramp(parent: Node3D, base: Vector3, f: Vector3, r: Vector3, u: Vector3, hw: float, length: float,
		top: float, body_name: String, trigger_name: String, index: int) -> void:
	var wide := hw + jump_side_run
	var p := PackedVector3Array([
		base - r * wide - u * 0.02, base + r * wide - u * 0.02,                        # attaque
		base - r * hw + f * length + u * top, base + r * hw + f * length + u * top,      # sommet
		base - r * wide + f * length - u * 0.3, base + r * wide + f * length - u * 0.3,  # pied arriere
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
	body.name = body_name
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
	area.name = trigger_name
	area.collision_layer = 0
	area.collision_mask = 1 << (VEHICLE_LAYER - 1)
	area.monitorable = false
	var acs := CollisionShape3D.new()
	var abox := BoxShape3D.new()
	abox.size = Vector3(hw * 2.0, 4.0, jump_trigger_depth)
	acs.shape = abox
	area.add_child(acs)
	area.transform = Transform3D(Basis(r, u, -f),
		base + f * (length - jump_trigger_depth / 2.0) + u * (top + 1.0))
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

# --- raccourcis -----------------------------------------------------------------

## Raccourci : distance (m) au-dela du bord de la piste sur laquelle sa
## chaussee passe de la hauteur de ce bord a son propre profil en long.
const BRANCH_BLEND_M := 30.0
## Pas (m) du trace fin d'un raccourci, avant reechantillonnage.
const BRANCH_FINE_M := 0.5
## Largeur maximale (m) d'une bande de sa chaussee en travers.
const BRANCH_CELL_M := 3.0
## Saut d'un raccourci (2026-10-21, « ou carrément un saut à faire avec une
## certaine vitesse » ; "jump" : {"u", "gap", "min_kmh"}) : sa chaussee monte
## de BRANCH_JUMP_LIFT_M sur BRANCH_JUMP_RISE_M vers un plateau
## (BRANCH_JUMP_FLAT_M avant le bord d'envol, autant apres celui de
## reception), le vide entre les deux ; tremplin de toute la largeur
## (BRANCH_RAMP_M, BRANCH_RAMP_DEG) au bord d'envol, signale par
## jump_pad_entered (indice BRANCH_JUMP_PAD + k). Tombe dans le vide : hors
## piste (chute) ; il reapparait BRANCH_JUMP_RESPAWN_M apres le bord de
## reception. Aucun checkpoint ne tombe entre le tremplin et ce point.
const BRANCH_JUMP_LIFT_M := 7.0
const BRANCH_JUMP_RISE_M := 90.0
const BRANCH_JUMP_FLAT_M := 25.0
const BRANCH_RAMP_M := 14.0
const BRANCH_RAMP_DEG := 9.0
const BRANCH_JUMP_PAD := 900
const BRANCH_JUMP_RESPAWN_M := 10.0
## Sa chaussee est coupee a cette distance sous le bord de la piste (m) et y
## passe 2 cm sous elle : pas de fente entre les deux maillages.
const BRANCH_TUCK_M := 0.2

## Resout les raccourcis : trace (droite entre leurs deux bouts sur la piste,
## deformee par leurs points de passage "path"), profil en long, et les
## ouvertures des murs de la piste.
func _build_branches() -> void:
	_br.clear()
	var n := _pos.size()
	for side in 2:
		_wall_open[side] = PackedByteArray()
	if branches.is_empty():
		return
	for spec: Dictionary in branches:
		var from := String(spec.get("from", ""))
		var to := String(spec.get("to", ""))
		if not _segment_starts.has(from) or not _segment_ends.has(to):
			push_warning("TrackBlockout : raccourci %s, segments inconnus" % spec.get("name", ""))
			continue
		var s0 := float(_segment_starts[from])
		var s1 := float(_segment_ends[to])
		var i0 := index_at_s(s0)
		var i1 := index_at_s(s1)
		var w := float(spec.get("width", branch_width))
		var turn := 0.0
		for seg: Dictionary in segments:
			if String(seg.get("name", "")) == from:
				turn = float(seg.get("angle", 0.0))
		# detour a droite (angle < 0) : le raccourci part colle au bord gauche,
		# il quitte la piste au plus tot (avant le 2026-10-21 : le signe etait
		# inverse, il longeait le bord interieur du virage sur ~135 m)
		var lat := float(spec.get("lateral", signf(turn) * (width / 2.0 - w / 2.0)))
		var a := _pos[i0] + _flat_right(i0) * lat
		var b := _pos[i1] + _flat_right(i1) * lat
		var axis := Vector3(b.x - a.x, 0.0, b.z - a.z)
		var straight := axis.length()
		axis = axis / maxf(straight, 1e-3)
		var across := axis.cross(Vector3.UP).normalized()
		# trace fin : l'avance le long de l'axe, l'ecart des points de passage
		var knots: Array[Vector2] = [Vector2.ZERO]
		for kn: Array in spec.get("path", []):
			knots.append(Vector2(float(kn[0]), float(kn[1])))
		knots.append(Vector2(1.0, 0.0))
		var fine := PackedVector3Array()
		var fine_x := PackedFloat32Array()
		var steps := maxi(2, ceili(straight / BRANCH_FINE_M))
		for k in steps + 1:
			var x := float(k) / steps
			fine.append(a + axis * (x * straight) + across * _knot_offset(knots, x))
			fine_x.append(x)
		var cum := PackedFloat32Array([0.0])
		for k in range(1, fine.size()):
			cum.append(cum[k - 1] + Vector2(fine[k].x - fine[k - 1].x, fine[k].z - fine[k - 1].z).length())
		# reechantillonne a pas constant le long du trace (u : part de sa longueur)
		var length := cum[cum.size() - 1]
		var count := maxi(2, roundi(length / sample_step))
		var pts := PackedVector3Array()
		var xs := PackedFloat32Array()
		var f := 0
		for q in count + 1:
			var d := length * q / count
			while f < fine.size() - 2 and cum[f + 1] < d:
				f += 1
			var t := clampf((d - cum[f]) / maxf(cum[f + 1] - cum[f], 1e-6), 0.0, 1.0)
			pts.append(fine[f].lerp(fine[f + 1], t))
			xs.append(lerpf(fine_x[f], fine_x[f + 1], t))
		var dirs := PackedVector3Array()
		var rights := PackedVector3Array()
		var curv := PackedFloat32Array()
		for q in count + 1:
			var p0 := pts[maxi(q - 1, 0)]
			var p1 := pts[mini(q + 1, count)]
			var dq := Vector3(p1.x - p0.x, 0.0, p1.z - p0.z).normalized()
			dirs.append(dq)
			rights.append(dq.cross(Vector3.UP).normalized())
			curv.append(_turn_curv(pts[maxi(q - 4, 0)], pts[q], pts[mini(q + 4, count)]))
		# chaque moitie juge la portion de piste qu'elle longe : de l'entree au
		# milieu du detour, puis du milieu a la sortie
		var span := posmod(i1 - i0, n)
		var bd := {"name": String(spec.get("name", "Raccourci %d" % _br.size())), "s0": s0, "s1": s1, "w": w,
			"lat": lat, "a": a, "b": b, "axis": axis, "straight": straight, "len": length, "pts": pts, "xs": xs,
			"dirs": dirs, "rights": rights, "curv": curv, "spec": spec,
			"win": PackedInt32Array([i0 - 40, i0 + span / 2, i0 + span / 2, i0 + span + 40]),
			"u_out": 0.0, "u_in": 1.0, "h_out": a.y, "h_in": b.y}
		_br.append(bd)
		# profil en long : de la hauteur du bord de la piste ou il la quitte a
		# celle du bord ou il la rejoint
		var kb := _br.size() - 1
		for q in count + 1:
			var m := _branch_main(kb, pts[q], float(q) / count)
			if m.x > 0.0:
				bd["u_out"] = float(q) / count
				bd["h_out"] = m.y
				break
		for q in range(count, -1, -1):
			var m := _branch_main(kb, pts[q], float(q) / count)
			if m.x > 0.0:
				bd["u_in"] = float(q) / count
				bd["h_in"] = m.y
				break
		bd["jump"] = _place_jump(spec.get("jump", {}), s0, s1, length, count)
		for q in count + 1:
			pts[q].y = _branch_y(kb, pts[q], float(q) / count)
		bd["pts"] = pts
	# mur de la piste dans le raccourci (a plus d'1 m de son bord) : ouvert
	for side in 2:
		_wall_open[side].resize(n)
	for i in n:
		for side in 2:
			var edge := _pos[i] + _right[i] * ((-1.0 if side == 0 else 1.0) * width / 2.0)
			_wall_open[side][i] = 1 if on_branch(edge, -1.0) >= 0 else 0


## Saut d'un raccourci : PackedFloat32Array([part du bord d'envol, part du
## bord de reception, vitesse conseillee km/h]), vide sans saut. Bords sur
## des rangees du maillage ; decale (au plus 0,15) pour qu'aucun checkpoint ne
## tombe entre le pied du tremplin et le point de reapparition.
func _place_jump(jump: Dictionary, s0: float, s1: float, length: float, count: int) -> PackedFloat32Array:
	if jump.is_empty():
		return PackedFloat32Array()
	var step := length / count
	var gap_rows := maxi(1, roundi(float(jump.get("gap", 40.0)) / step))
	var want := float(jump.get("u", 0.5))
	for k in 31:
		var u := want + (0.01 if k % 2 == 1 else -0.01) * ceili(k / 2.0)
		var qa := roundi(u * count)
		var ua := float(qa) / count
		var ub := float(qa + gap_rows) / count
		var lo := lerpf(s0, s1, ua - (BRANCH_RAMP_M + 4.0) / length)
		var hi := lerpf(s0, s1, ub + (BRANCH_JUMP_RESPAWN_M + 25.0) / length)
		var free := true
		for c in checkpoint_count:
			var s := checkpoint_s(c)
			if s > lo and s < hi:
				free = false
				break
		if free:
			return PackedFloat32Array([ua, ub, float(jump.get("min_kmh", 0.0))])
	push_warning("TrackBlockout : saut de raccourci sans place hors des checkpoints")
	return PackedFloat32Array()


## Surelevation (m) de la chaussee d'un raccourci a sa part u : le plateau de
## son saut.
func _jump_lift(bd: Dictionary, u: float) -> float:
	var j: PackedFloat32Array = bd["jump"]
	if j.is_empty():
		return 0.0
	var length := float(bd["len"])
	var a := j[0] - BRANCH_JUMP_FLAT_M / length
	var b := j[1] + BRANCH_JUMP_FLAT_M / length
	var rise := BRANCH_JUMP_RISE_M / length
	return BRANCH_JUMP_LIFT_M * smoothstep(a - rise, a, u) * (1.0 - smoothstep(b, b + rise, u))


## Le raccourci k est vide a sa part u (entre les bords de son saut).
func _in_gap(k: int, u: float) -> bool:
	var j: PackedFloat32Array = _br[k]["jump"]
	return not j.is_empty() and u > j[0] and u < j[1]


## Ecart a l'axe d'un raccourci a l'avance x (0 a 1) : d'un point de passage
## (x, ecart) au suivant en S doux (tangent a l'axe a chacun).
static func _knot_offset(knots: Array[Vector2], x: float) -> float:
	for k in knots.size() - 1:
		if x <= knots[k + 1].x:
			return lerpf(knots[k].y, knots[k + 1].y, smoothstep(knots[k].x, knots[k + 1].x, x))
	return knots[knots.size() - 1].y


## Courbure (1/m, > 0 a gauche) du cercle par trois points, a l'horizontale.
static func _turn_curv(a: Vector3, b: Vector3, c: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var bc := Vector2(c.x - b.x, c.z - b.z)
	var ac := Vector2(c.x - a.x, c.z - a.z)
	var den := ab.length() * bc.length() * ac.length()
	return -2.0 * ab.cross(ac) / den if den > 1e-3 else 0.0


## Lateral horizontal de la piste a l'echantillon i (sans devers).
func _flat_right(i: int) -> Vector3:
	return Vector3(_right[i].x, 0.0, _right[i].z).normalized()


## Echantillon de la piste le plus proche de `p` (a l'horizontale) parmi les
## indices lo a hi (pris modulo le nombre d'echantillons).
func _nearest_in(p: Vector3, lo: int, hi: int) -> int:
	var n := _pos.size()
	var best := lo
	var best_d := INF
	for i in range(lo, hi + 1, 4):
		var j := posmod(i, n)
		var d := Vector2(_pos[j].x - p.x, _pos[j].z - p.z).length_squared()
		if d < best_d:
			best_d = d
			best = i
	var coarse := best
	for i in range(maxi(coarse - 4, lo), mini(coarse + 4, hi) + 1):
		var j := posmod(i, n)
		var d := Vector2(_pos[j].x - p.x, _pos[j].z - p.z).length_squared()
		if d < best_d:
			best_d = d
			best = i
	return posmod(best, n)


## La piste (portion lo..hi) au droit de `p` : Vector2(distance de `p` au-dela
## de son bord, m, negative sur sa chaussee ; hauteur de sa chaussee au droit
## de `p`, ou de son bord au-dela). Interpolee entre deux echantillons, devers
## compris : c'est le bord de son maillage.
func _main_cross(p: Vector3, lo: int, hi: int) -> Vector2:
	var n := _pos.size()
	var i := _nearest_in(p, lo, hi)
	var fw := Vector2(_fwd[i].x, _fwd[i].z).normalized()
	var t := Vector2(p.x - _pos[i].x, p.z - _pos[i].z).dot(fw)
	var j := posmod(i + (1 if t >= 0.0 else -1), n)
	var seg := maxf(Vector2(_pos[j].x - _pos[i].x, _pos[j].z - _pos[i].z).length(), 1e-3)
	var k := clampf(absf(t) / seg, 0.0, 1.0)
	var c := _pos[i].lerp(_pos[j], k)
	var r := _right[i].lerp(_right[j], k).normalized()
	var rf := Vector2(r.x, r.z)
	var lat := Vector2(p.x - c.x, p.z - c.z).dot(rf) / maxf(rf.length_squared(), 1e-6)
	var lc := clampf(lat, -width / 2.0, width / 2.0)
	return Vector2(absf(lat) - width / 2.0, c.y + r.y * lc)


## _main_cross pour le raccourci k a sa part u (la portion de piste qu'il longe).
func _branch_main(k: int, p: Vector3, u: float) -> Vector2:
	var win: PackedInt32Array = _br[k]["win"]
	return _main_cross(p, win[0], win[1]) if u < 0.5 else _main_cross(p, win[2], win[3])


## Hauteur de la chaussee du raccourci k en `p` (a sa part u) : au bord de la
## piste, celle de ce bord ; au-dela, elle rejoint son profil en long sur
## BRANCH_BLEND_M (pas de marche, ni de chaussee posee sur la piste).
func _branch_y(k: int, p: Vector3, u: float) -> float:
	return _branch_y_from(k, _branch_main(k, p, u), u)


func _branch_y_from(k: int, main: Vector2, u: float) -> float:
	var bd := _br[k]
	var own := lerpf(float(bd["h_out"]), float(bd["h_in"]),
		smoothstep(float(bd["u_out"]), maxf(float(bd["u_in"]), float(bd["u_out"]) + 1e-3), u)) + _jump_lift(bd, u)
	return lerpf(main.y, own, smoothstep(0.0, BRANCH_BLEND_M, main.x))


## Position de `p` sur le raccourci k : Vector2(u, ecart a son axe, m, > 0 a
## droite) ; u hors de [0, 1] avant son entree ou apres sa sortie (prolonge
## en ligne droite).
func _branch_coords(k: int, p: Vector3) -> Vector2:
	var bd := _br[k]
	var pts: PackedVector3Array = bd["pts"]
	var dirs: PackedVector3Array = bd["dirs"]
	var rights: PackedVector3Array = bd["rights"]
	var count := pts.size() - 1
	var length := float(bd["len"])
	var a := bd["a"] as Vector3
	var axis := bd["axis"] as Vector3
	var x := ((p.x - a.x) * axis.x + (p.z - a.z) * axis.z) / float(bd["straight"])
	if x <= 0.0 or x >= 1.0:
		var e := 0 if x <= 0.0 else count
		var d := p - pts[e]
		return Vector2(float(e) / count + (d.x * dirs[e].x + d.z * dirs[e].z) / length,
			d.x * rights[e].x + d.z * rights[e].z)
	# l'echantillon de meme avance, puis le segment le plus proche autour
	var xs: PackedFloat32Array = bd["xs"]
	var q0 := clampi(xs.bsearch(x), 0, count)
	var reach := 24
	var best_d := INF
	var best_q := 0
	var best_t := 0.0
	for q in range(maxi(q0 - reach, 0), mini(q0 + reach, count)):
		var seg := Vector2(pts[q + 1].x - pts[q].x, pts[q + 1].z - pts[q].z)
		var rel := Vector2(p.x - pts[q].x, p.z - pts[q].z)
		var t := clampf(rel.dot(seg) / maxf(seg.length_squared(), 1e-6), 0.0, 1.0)
		var d := (rel - seg * t).length_squared()
		if d < best_d:
			best_d = d
			best_q = q
			best_t = t
	var c := pts[best_q].lerp(pts[best_q + 1], best_t)
	var r := rights[best_q].lerp(rights[best_q + 1], best_t).normalized()
	return Vector2((best_q + best_t) / count, (p.x - c.x) * r.x + (p.z - c.z) * r.z)


## Hauteur de l'axe du raccourci k a sa part u (dans [0, 1]).
func _branch_center_y(k: int, u: float) -> float:
	var pts: PackedVector3Array = _br[k]["pts"]
	var fq := clampf(u, 0.0, 1.0) * (pts.size() - 1)
	var q := mini(floori(fq), pts.size() - 2)
	return lerpf(pts[q].y, pts[q + 1].y, fq - q)


func branch_count() -> int:
	_ensure_built()
	return _br.size()


func branch_name(k: int) -> String:
	return String(_br[k]["name"])


## Longueur du raccourci k le long de son trace (m).
func branch_length(k: int) -> float:
	_ensure_built()
	return float(_br[k]["len"])


## Abscisses (m) de la piste ou le raccourci k part et revient.
func branch_span(k: int) -> Vector2:
	_ensure_built()
	return Vector2(float(_br[k]["s0"]), float(_br[k]["s1"]))


## Repere sur le raccourci k a la part `u` de sa longueur (0 a 1 ; au-dela,
## prolonge en ligne droite), decale lateralement de son axe, oriente dans le
## sens de course, `lift` m au-dessus de sa chaussee.
func branch_frame(k: int, u: float, lateral: float, lift: float) -> Transform3D:
	_ensure_built()
	var bd := _br[k]
	var pts: PackedVector3Array = bd["pts"]
	var dirs: PackedVector3Array = bd["dirs"]
	var count := pts.size() - 1
	var c: Vector3
	var dir: Vector3
	if u < 0.0 or u > 1.0:
		var e := 0 if u < 0.0 else count
		dir = dirs[e]
		c = pts[e] + dir * ((u - float(e) / count) * float(bd["len"]))
	else:
		var fq := u * count
		var q := mini(floori(fq), count - 1)
		c = pts[q].lerp(pts[q + 1], fq - q)
		dir = dirs[q].lerp(dirs[q + 1], fq - q).normalized()
	var right := dir.cross(Vector3.UP).normalized()
	var p := c + right * lateral
	p.y = _branch_y(k, p, clampf(u, 0.0, 1.0))
	return Transform3D(Basis(right, Vector3.UP, -dir), p + Vector3.UP * lift)


## Courbure (1/m, sans signe) de l'axe du raccourci k a sa part u.
func branch_curvature(k: int, u: float) -> float:
	return absf(branch_turn(k, u))


## Courbure signee (1/m, > 0 : virage a gauche) de l'axe du raccourci k a sa
## part u.
func branch_turn(k: int, u: float) -> float:
	_ensure_built()
	var curv: PackedFloat32Array = _br[k]["curv"]
	return curv[clampi(roundi(clampf(u, 0.0, 1.0) * (curv.size() - 1)), 0, curv.size() - 1)]


## Saut du raccourci k : Vector2(part du bord d'envol, part du bord de
## reception), Vector2(-1, -1) s'il n'en a pas.
func branch_jump(k: int) -> Vector2:
	_ensure_built()
	var j: PackedFloat32Array = _br[k]["jump"]
	return Vector2(j[0], j[1]) if not j.is_empty() else Vector2(-1.0, -1.0)


## Vitesse conseillee (km/h) pour franchir le saut du raccourci k (0 : pas de
## saut).
func branch_jump_min_kmh(k: int) -> float:
	_ensure_built()
	var j: PackedFloat32Array = _br[k]["jump"]
	return j[2] if not j.is_empty() else 0.0


## Decalage de l'axe du raccourci k par rapport a la ligne centrale de la
## piste, a ses deux bouts (m, > 0 a droite).
func branch_lateral(k: int) -> float:
	_ensure_built()
	return float(_br[k]["lat"])


## Largeur de la chaussee du raccourci k (m).
func branch_width_of(k: int) -> float:
	_ensure_built()
	return float(_br[k]["w"])


## Part du raccourci k ou se trouve `p` (0 : son entree, 1 : sa sortie ; hors
## de [0, 1] avant ou apres), a l'horizontale.
func branch_u(k: int, p: Vector3) -> float:
	return _branch_coords(k, p).x


## Ecart de `p` a l'axe du raccourci k (m, > 0 a droite dans le sens de course).
func branch_lateral_of(k: int, p: Vector3) -> float:
	return _branch_coords(k, p).y


## Flaques du raccourci k : [[u, decalage, rayon], ...] (comme "puddles").
func branch_puddles(k: int) -> Array:
	_ensure_built()
	return (_br[k]["spec"] as Dictionary).get("puddles", [])


## Barils du raccourci k (noeuds ; null pour un baril absent).
func branch_barrels(k: int) -> Array[ExplosiveBarrel]:
	_ensure_built()
	var out: Array[ExplosiveBarrel] = []
	var first := _barrels.size()
	for j in k:
		first += ((_br[j]["spec"] as Dictionary).get("barrels", []) as Array).size()
	for j in ((_br[k]["spec"] as Dictionary).get("barrels", []) as Array).size():
		out.append(barrel_node(first + j))
	return out


## Indice du raccourci sous `p` (sur sa chaussee, a `margin` m pres de ses
## bords, a hauteur de route), -1 sinon.
func on_branch(p: Vector3, margin: float = 0.0) -> int:
	for k in _br.size():
		var c := _branch_coords(k, p)
		if c.x < 0.0 or c.x > 1.0:
			continue
		if absf(c.y) > float(_br[k]["w"]) / 2.0 + margin:
			continue
		var y := _branch_center_y(k, c.x)
		if p.y < y - 8.0 or p.y > y + 30.0:
			continue
		# sous le bord d'un saut : il tombe
		if p.y < y - 1.5 and _in_gap(k, c.x):
			continue
		return k
	return -1


## Abscisse de la piste qui correspond a `p` sur le raccourci k (meme part du
## chemin que sur le detour).
func branch_progress_s(k: int, p: Vector3) -> float:
	var bd := _br[k]
	return lerpf(float(bd["s0"]), float(bd["s1"]), clampf(_branch_coords(k, p).x, 0.0, 1.0))


## Chaussee et murs des raccourcis. La chaussee est decoupee au bord de la
## piste (aucun recouvrement : pas de scintillement), a la hauteur de ce bord
## (pas de marche) ; murs et neons la ou leur bord est a plus d'1 m de la piste.
func _build_branch_roads(geometry: Node3D, walls: Node3D) -> void:
	for kb in _br.size():
		var bd := _br[kb]
		var pts: PackedVector3Array = bd["pts"]
		var rights: PackedVector3Array = bd["rights"]
		var count := pts.size() - 1
		var w := float(bd["w"])
		var step := float(bd["len"]) / count
		var cols := maxi(1, ceili(w / BRANCH_CELL_M))
		# grille : sommet a la hauteur de la chaussee, uv, distance au bord de la piste
		var verts := PackedVector3Array()
		var outs := PackedFloat32Array()
		var uvs := PackedVector2Array()
		for q in count + 1:
			var u := float(q) / count
			for c in cols + 1:
				var p := pts[q] + rights[q] * (-w / 2.0 + w * c / cols)
				var m := _branch_main(kb, p, u)
				p.y = _branch_y_from(kb, m, u) - (0.02 if m.x < 0.0 else 0.0)
				verts.append(p)
				outs.append(m.x)
				uvs.append(Vector2(float(c) / cols, q * step))
		# saut : rangees du vide (de qa a qb)
		var jump: PackedFloat32Array = bd["jump"]
		var qa := roundi(jump[0] * count) if not jump.is_empty() else count + 1
		var qb := roundi(jump[1] * count) if not jump.is_empty() else count + 1
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var tris := PackedVector3Array()
		for q in count:
			if q >= qa and q < qb:
				continue
			var u := (q + 0.5) / count
			for c in cols:
				var a := q * (cols + 1) + c
				var b := a + 1
				var d := a + cols + 1
				var e := d + 1
				for tri: PackedInt32Array in [PackedInt32Array([a, b, e]), PackedInt32Array([a, e, d])]:
					_clip_branch_tri(st, tris, kb, u, tri, verts, outs, uvs)
		if not tris.is_empty():
			var mat := theme.road.duplicate() as ShaderMaterial
			mat.set_shader_parameter("road_width", w)
			mat.set_shader_parameter("finish_line", false)
			var road := _static_body(geometry, "Branch%dRoad" % kb, st, tris, mat, 1.0)
			road.set_meta(&"surface", &"asphalt")
		for side: float in [-1.0, 1.0]:
			var col := 0 if side < 0.0 else cols
			var wst := SurfaceTool.new()
			wst.begin(Mesh.PRIMITIVE_TRIANGLES)
			var wtris := PackedVector3Array()
			var nst := SurfaceTool.new()
			nst.begin(Mesh.PRIMITIVE_TRIANGLES)
			var ntris := PackedVector3Array()
			for q in count:
				var i0 := q * (cols + 1) + col
				var i1 := i0 + cols + 1
				if outs[i0] < 1.0 or outs[i1] < 1.0 or (q >= qa and q < qb):
					continue
				var a := _branch_wall_profile(verts[i0], rights[q] * side)
				var b := _branch_wall_profile(verts[i1], rights[q + 1] * side)
				var v0 := q * step
				var v1 := v0 + step
				for k in 3:
					if side > 0.0:
						_quad(wst, wtris, a[k], b[k], b[k + 1], a[k + 1],
							Vector2(k, v0), Vector2(k, v1), Vector2(k + 1, v1), Vector2(k + 1, v0), Vector3.ZERO)
					else:
						_quad(wst, wtris, a[k], a[k + 1], b[k + 1], b[k],
							Vector2(k, v0), Vector2(k + 1, v0), Vector2(k + 1, v1), Vector2(k, v1), Vector3.ZERO)
				_branch_neon_quad(nst, ntris, a, b, rights[q] * side, rights[q + 1] * side)
			if not wtris.is_empty():
				var wall := _static_body(walls, "Branch%dWall%s" % [kb, "Left" if side < 0.0 else "Right"], wst, wtris,
					theme.wall, wall_friction)
				wall.set_meta(&"surface", &"asphalt")
				var mi := MeshInstance3D.new()
				mi.name = "Branch%dNeon%s" % [kb, "Left" if side < 0.0 else "Right"]
				mi.mesh = nst.commit()
				mi.material_override = theme.edge_left if side < 0.0 else theme.edge_right
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				walls.add_child(mi)
		if qb <= count:
			_build_branch_cliffs(walls, kb, verts, cols, qa, qb)
		# portique a l'entree : on voit le raccourci de loin
		var gate := _group("BranchArches") if kb == 0 else get_node("BranchArches") as Node3D
		var label := "近 道" if theme.arch_style == TrackTheme.ArchStyle.TORII else "RACCOURCI"
		_build_arch(gate, 0.0, label, 100 + kb, branch_frame(kb, _gate_u(kb), 0.0, 0.0), w)


## Bords du vide d'un saut : une paroi de la chaussee jusqu'au sol, en
## travers, aux rangees qa (envol) et qb (reception), tournee vers le vide
## (une face : deux faces dos a dos scintillaient).
func _build_branch_cliffs(walls: Node3D, kb: int, verts: PackedVector3Array, cols: int, qa: int, qb: int) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := PackedVector3Array()
	for row: int in [qa, qb]:
		for c in cols:
			var a := verts[row * (cols + 1) + c]
			var b := verts[row * (cols + 1) + c + 1]
			var a0 := Vector3(a.x, GROUND_Y - 0.1, a.z)
			var b0 := Vector3(b.x, GROUND_Y - 0.1, b.z)
			var h := a.y - a0.y
			# _quad : sens anti-horaire vu de la face visible
			if row == qa:
				_quad(st, tris, b0, a0, a, b, Vector2(0, h), Vector2(1, h), Vector2(1, 0), Vector2(0, 0), Vector3.ZERO)
			else:
				_quad(st, tris, a0, b0, b, a, Vector2(0, h), Vector2(1, h), Vector2(1, 0), Vector2(0, 0), Vector3.ZERO)
	var body := _static_body(walls, "Branch%dCliffs" % kb, st, tris, theme.wall, wall_friction)
	body.set_meta(&"surface", &"asphalt")


## Triangle `tri` (indices dans la grille) de la chaussee du raccourci k,
## decoupe a BRANCH_TUCK_M sous le bord de la piste : seule la partie hors de
## sa chaussee est emise ; un sommet du decoupage passe 2 cm sous elle.
func _clip_branch_tri(st: SurfaceTool, tris: PackedVector3Array, k: int, u: float, tri: PackedInt32Array,
		verts: PackedVector3Array, outs: PackedFloat32Array, uvs: PackedVector2Array) -> void:
	var poly := PackedVector3Array()
	var puv := PackedVector2Array()
	for e in 3:
		var ia := tri[e]
		var ib := tri[(e + 1) % 3]
		var oa := outs[ia] + BRANCH_TUCK_M
		var ob := outs[ib] + BRANCH_TUCK_M
		if oa >= 0.0:
			poly.append(verts[ia])
			puv.append(uvs[ia])
		if (oa >= 0.0) != (ob >= 0.0):
			var t := oa / (oa - ob)
			var p := verts[ia].lerp(verts[ib], t)
			p.y = _branch_main(k, p, u).y - 0.02
			poly.append(p)
			puv.append(uvs[ia].lerp(uvs[ib], t))
	# eventail, meme sens que _quad
	for j in range(1, poly.size() - 1):
		for v: int in [0, j + 1, j]:
			st.set_uv(puv[v])
			st.add_vertex(poly[v])
			tris.append(poly[v])


## Part du raccourci k ou poser son portique : la premiere ou ses deux
## piliers (a 4 m au-dela de ses bords) sont a plus de 3 m de la piste.
func _gate_u(k: int) -> float:
	var half := float(_br[k]["w"]) / 2.0 + 4.0
	var u := BRANCH_GATE_U
	while u < 0.5:
		var f := branch_frame(k, u, 0.0, 0.0)
		if _branch_main(k, f.origin - f.basis.x * half, u).x > 3.0 \
				and _branch_main(k, f.origin + f.basis.x * half, u).x > 3.0:
			return u
		u += 0.01
	return 0.5


## Neon du haut d'un mur de raccourci (comme _build_wall_neon), entre deux
## profils de mur.
func _branch_neon_quad(st: SurfaceTool, tris: PackedVector3Array, a: PackedVector3Array, b: PackedVector3Array,
		out_a: Vector3, out_b: Vector3) -> void:
	var z2 := Vector2.ZERO
	var strip: Array[PackedVector3Array] = []
	for k in 2:
		var prof := a if k == 0 else b
		var out := out_a if k == 0 else out_b
		var down := (prof[0] - prof[1]).normalized()
		var inward := -out * 0.04
		var lift := Vector3(0.0, 0.03, 0.0)
		strip.append(PackedVector3Array([prof[1] + down * 0.32 + inward, prof[1] + inward + lift, prof[2] + lift]))
	_quad(st, tris, strip[0][0], strip[1][0], strip[1][1], strip[0][1], z2, z2, z2, z2, Vector3.ZERO)
	_quad(st, tris, strip[0][1], strip[1][1], strip[1][2], strip[0][2], z2, z2, z2, z2, Vector3.ZERO)


## Profil d'un mur de raccourci (comme _wall_profile) au bord `edge`,
## exterieur `out` (horizontal).
func _branch_wall_profile(edge: Vector3, out: Vector3) -> PackedVector3Array:
	var top_y := edge.y + wall_height
	var inner_bottom := edge + Vector3(0.0, -0.3, 0.0)
	var inner_top := Vector3(edge.x, top_y, edge.z) - out * wall_lean
	var outer_top := inner_top + out * (wall_thickness + wall_lean * (1.0 + 0.3 / wall_height))
	var outer_bottom := Vector3(outer_top.x, minf(GROUND_Y - 0.1, edge.y - 0.3), outer_top.z)
	return PackedVector3Array([inner_bottom, inner_top, outer_top, outer_bottom])


## Flaques et barils des raccourcis (indices apres ceux de la piste).
func _build_branch_hazards(pads: Node3D, barrels: Node3D) -> void:
	_branch_puddles.clear()
	_branch_barrels.clear()
	for kb in _br.size():
		var spec: Dictionary = _br[kb]["spec"]
		for pd: Array in spec.get("puddles", []):
			var xf := branch_frame(kb, float(pd[0]), float(pd[1]), 0.0)
			var index := _puddles.size() + _branch_puddles.size()
			_branch_puddles.append([xf, float(pd[2])])
			_build_puddle(pads, Vector3(0.0, 0.0, float(pd[2])), index, xf, true)
		for br: Array in spec.get("barrels", []):
			var xf := branch_frame(kb, float(br[0]), float(br[1]), 0.0)
			var index := _barrels.size() + _branch_barrels.size()
			_branch_barrels.append(xf)
			_build_barrel(barrels, 0.0, 0.0, index, xf, true)
		var j: PackedFloat32Array = _br[kb]["jump"]
		if not j.is_empty():
			var f0 := branch_frame(kb, j[0] - BRANCH_RAMP_M / float(_br[kb]["len"]), 0.0, 0.0)
			_build_ramp(pads, f0.origin, -f0.basis.z, f0.basis.x, Vector3.UP, float(_br[kb]["w"]) / 2.0 - 0.3,
				BRANCH_RAMP_M, BRANCH_RAMP_M * tan(deg_to_rad(BRANCH_RAMP_DEG)), "BranchJump%d" % kb,
				"BranchJumpTrigger%d" % kb, BRANCH_JUMP_PAD + kb)


## Vrai si la boite `size` posee en `xf` touche un raccourci (murs compris).
func _box_hits_branch(xf: Transform3D, size: Vector3) -> bool:
	if _br.is_empty():
		return false
	var inv := xf.affine_inverse()
	for bd: Dictionary in _br:
		var pts: PackedVector3Array = bd["pts"]
		var pad := float(bd["w"]) / 2.0 + wall_thickness + 4.0
		for q in range(0, pts.size(), 2):
			var l := inv * pts[q]
			if absf(l.x) < size.x / 2.0 + pad and absf(l.z) < size.z / 2.0 + pad and absf(l.y) < size.y / 2.0 + 3.0:
				return true
	return false


## Retire du decor `root` ce qui tomberait sur un raccourci : maillages et
## instances de MultiMesh dont l'emprise touche sa chaussee (murs et 3 m de
## marge compris), sous 15 m au-dessus d'elle (un pont routier passe). Appele
## par les decors a la fin de leur generation.
func clear_branch_corridors(root: Node) -> void:
	if _br.is_empty() or root == null:
		return
	for n in root.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := n as MultiMeshInstance3D
		var mm := mmi.multimesh
		if mm == null or mm.mesh == null:
			continue
		var aabb := mm.mesh.get_aabb()
		var keep: Array[int] = []
		for k in mm.instance_count:
			var xf := mmi.global_transform * mm.get_instance_transform(k)
			var box := xf * aabb
			if not _blocks_branch(box):
				keep.append(k)
		if keep.size() == mm.instance_count:
			continue
		var xfs: Array[Transform3D] = []
		var colors: Array[Color] = []
		var custom: Array[Color] = []
		for k in keep:
			xfs.append(mm.get_instance_transform(k))
			if mm.use_colors:
				colors.append(mm.get_instance_color(k))
			if mm.use_custom_data:
				custom.append(mm.get_instance_custom_data(k))
		mm.instance_count = xfs.size()
		for k in xfs.size():
			mm.set_instance_transform(k, xfs[k])
			if mm.use_colors:
				mm.set_instance_color(k, colors[k])
			if mm.use_custom_data:
				mm.set_instance_custom_data(k, custom[k])
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		if _blocks_branch(mi.global_transform * mi.get_aabb()):
			mi.queue_free()


## L'emprise de `box` (monde) touche un raccourci, sous 15 m au-dessus de lui.
func _blocks_branch(box: AABB) -> bool:
	var c := box.get_center()
	var radius := maxf(box.size.x, box.size.z) / 2.0 + wall_thickness + wall_lean + 3.0
	# a plat (on_branch juge aussi la hauteur)
	for k in _br.size():
		var bc := _branch_coords(k, c)
		if bc.x < 0.0 or bc.x > 1.0 or absf(bc.y) > float(_br[k]["w"]) / 2.0 + radius:
			continue
		if box.position.y < _branch_center_y(k, bc.x) + 15.0:
			return true
	return false


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
