class_name RoadsideDressing
extends Node3D

## Decor proche de la piste parente (2026-10-22 : « rendre moins vide les
## graphismes proches des routes ou au-dessus des routes pour que ce soit tout
## le temps beau et immersif »), dans le style de son theme :
##   - AU-DESSUS de la route, tous les span_spacing m environ : deux mats et
##     un cable tendu en travers, au moins SPAN_CLEARANCE m au-dessus de la
##     chaussee (plus haut que les arches) - enseignes neon suspendues (Cyber
##     City), guirlandes de fanions et banderoles (Playa), guirlandes de
##     lanternes de papier ou corde sacree (Sakura) ;
##   - SUR le haut des murs, partout (ponts compris) : balises neon, fanions,
##     bannieres nobori ou lanternes ;
##   - SUR la face interieure des murs, comme les panneaux de bord de piste :
##     ecrans holographiques animes (Cyber City), panneaux de sponsors
##     (Playa), rideaux de fete rouges et blancs (Sakura) ;
##   - SUR les ponts (2026-10-22, « pont vide ») : un garde-corps sur le haut
##     des murs - laque vermillon a giboshi de bronze et lanternes bonbori
##     (Sakura), poteaux de bois flotte, cordages, bouees et reverberes
##     (Playa) ;
##   - aux bouts des murs ouverts par un raccourci : un pilier qui cache la
##     coupe (2026-10-22, « soucis de texture aux joints ») ;
##   - AU PIED des murs, la ou la route est au sol : distributeurs lumineux et
##     ecrans holographiques, planches de surf, tours de sauveteur, paillotes,
##     touffes d'herbe de dune et buissons, palissades de bambou et azalees.
## Rien sur la chaussee, rien sur un raccourci, ni aux arches, aux tribunes,
## sous un pont routier ou pres d'une autre partie de la piste (le 8 de
## Sakura). Purement visuel : aucune collision. Tout est fusionne par case
## de CELL m (un appel de rendu par materiau et par case), dessine jusqu'a
## VIEW_END m seulement, hors eclairage global. Placement deterministe. En
## headless (tests), rien n'est genere, sauf si un test le force.

## Hauteur libre minimale sous un cable, au-dessus du bord le plus haut de la
## chaussee (m) : les arches ont 13 m.
const SPAN_CLEARANCE := 14.5
const CELL := 240.0
const VIEW_END := 460.0
## Tribunes de RaceDecor autour de la ligne (m avant, m apres).
const STANDS_BEFORE := 118.0
const STANDS_AFTER := 125.0

@export var decor_seed: int = 13
@export var span_spacing: float = 95.0

static var generate_in_headless: bool = false

var _track: TrackBlockout
var _style: int = 0
var _half: float = 0.0
var _beyond: float = 0.0
var _state: int = 1
## Qualite extreme (GraphicsSettings.extreme_assets) : decor plus serre, vu de
## plus loin (EXTREME_DENSITY, EXTREME_VIEW).
var _x: bool = false
const EXTREME_DENSITY := 0.75
const EXTREME_VIEW := 1.5
var _batches: Dictionary = {}
var _labels: Array[Label3D] = []
var _blocked: Array[Vector2] = []
## Pour les tests : cables poses ({s, low, road_top, a, b}), pieds des objets
## poses au sol ou sur les murs.
var spans: Array[Dictionary] = []
var props: PackedVector3Array = PackedVector3Array()


func _ready() -> void:
	if DisplayServer.get_name() == "headless" and not generate_in_headless:
		return
	var track := get_parent() as TrackBlockout
	if track == null:
		return
	if track.is_node_ready():
		_generate(track)
	else:
		track.ready.connect(_generate.bind(track), CONNECT_ONE_SHOT)


func _rand() -> float:
	_state = (_state * 1103515245 + 12345) & 0x7fffffff
	return float(_state) / 2147483648.0


func _range(a: float, b: float) -> float:
	return a + (b - a) * _rand()


# --- placement -------------------------------------------------------------------

func _generate(track: TrackBlockout) -> void:
	_track = track
	_style = track.theme_id
	_state = maxi(decor_seed, 1)
	_x = GraphicsSettings.extreme_assets()
	_half = track.width / 2.0
	_beyond = _half + track.wall_thickness + track.wall_lean
	_blocked.clear()
	spans.clear()
	props.clear()
	var L := track.length()
	# arches, ponts routiers (RaceDecor) : rien au-dessus de la route autour
	# (assez loin pour que leurs enseignes ne se chevauchent pas a l'image)
	for k in track.arch_count():
		_blocked.append(Vector2(track.arch_s(k), 75.0))
	var decor := track.get_node_or_null(^"RaceDecor")
	if decor != null:
		for spec: Dictionary in decor.get("overpasses"):
			var s0 := track.segment_start_s(String(spec.get("segment", "")))
			if s0 >= 0.0:
				_blocked.append(Vector2(s0 + float(spec.get("at", 0.0)), 60.0))
	var s := 70.0
	while s < L - STANDS_BEFORE:
		_try_span(s)
		s += span_spacing * _dense() + _range(-15.0, 15.0)
	_wall_props(L)
	_bridge_rails(L)
	_wall_ends()
	_wall_boards(L)
	_ground_props(L)
	_commit()
	set_meta(&"spans", spans)
	set_meta(&"props", props)


## Part du pas entre deux objets : moins en qualite extreme (plus d'objets).
func _dense() -> float:
	return EXTREME_DENSITY if _x else 1.0


func _circ(a: float, b: float) -> float:
	var d := absf(a - b)
	return minf(d, _track.length() - d)


func _in_stands(s: float) -> bool:
	return s < STANDS_AFTER or s > _track.length() - STANDS_BEFORE


func _is_blocked(s: float) -> bool:
	for b in _blocked:
		if _circ(s, b.x) < b.y:
			return true
	return _in_stands(s)


func _wall_open(i: int, side: float) -> bool:
	var opened: PackedByteArray = _track._wall_open[0 if side < 0.0 else 1]
	if opened.is_empty():
		return false
	for d in range(-6, 7):
		if opened[posmod(i + d, opened.size())] == 1:
			return true
	return false


func _clear_box(center: Vector3, half_size: Vector3) -> bool:
	return not _track._blocks_branch(AABB(center - half_size, half_size * 2.0))


## Repere a l'abscisse s : centre, avant et droite horizontaux, bords de la
## chaussee, route basse (au sol, pas de tablier).
func _frame(s: float) -> Dictionary:
	var i := _track.index_at_s(s)
	var p := _track.sample_position(i)
	var t := (_track.sample_forward(i) * Vector3(1, 0, 1)).normalized()
	var r := t.cross(Vector3.UP).normalized()
	var rb := _track.sample_right(i)
	var el := p - rb * _half
	var er := p + rb * _half
	return {"i": i, "s": s, "p": p, "t": t, "r": r, "edge_l": el, "edge_r": er,
		"top": maxf(el.y, er.y), "low": maxf(el.y, er.y) < 1.5 and not _track.is_bridge_deck(i)}


## Pied d'un mat a cote de la route, cote `side`, `out` m au-dela du mur :
## au sol si la route est basse, sinon sur le haut du mur.
func _pole_foot(f: Dictionary, side: float, out: float) -> Vector3:
	if f["low"]:
		var c: Vector3 = f["p"] + (f["r"] as Vector3) * side * (_beyond + out)
		c.y = TrackBlockout.GROUND_Y
		return c
	var prof: PackedVector3Array = _track._wall_profile(f["i"], side)
	return (prof[1] + prof[2]) / 2.0


func _try_span(s: float) -> void:
	if _is_blocked(s):
		return
	var f := _frame(s)
	var i: int = f["i"]
	var p: Vector3 = f["p"]
	# une autre partie de la piste a cote (croisement du 8, echangeur)
	if _track.other_section_distance(p, s) < _track.width + 40.0:
		return
	if _wall_open(i, -1.0) or _wall_open(i, 1.0):
		return
	var a := _pole_foot(f, -1.0, 3.5)
	var b := _pole_foot(f, 1.0, 3.5)
	if not _clear_box(a + Vector3(0, 8, 0), Vector3(1, 8, 1)) or not _clear_box(b + Vector3(0, 8, 0), Vector3(1, 8, 1)):
		return
	var sag := 2.6
	var low := float(f["top"]) + SPAN_CLEARANCE
	var top_y := low + sag
	var ta := Vector3(a.x, top_y, a.z)
	var tb := Vector3(b.x, top_y, b.z)
	var batch := _batch(p)
	match _style:
		TrackTheme.Id.PLAYA_DEL_SOL: _span_playa(batch, f, a, b, ta, tb, sag)
		TrackTheme.Id.SAKURA: _span_sakura(batch, f, a, b, ta, tb, sag)
		_: _span_cyber(batch, f, a, b, ta, tb, sag)
	spans.append({"s": s, "low": low, "road_top": f["top"], "a": a, "b": b})


## Point du cable a la fraction u (0 : mat gauche, 1 : mat droit), flechi.
static func _cable(ta: Vector3, tb: Vector3, sag: float, u: float) -> Vector3:
	return ta.lerp(tb, u) - Vector3(0.0, sag * 4.0 * u * (1.0 - u), 0.0)


func _draw_cable(batch: Batch, ta: Vector3, tb: Vector3, sag: float, r: float, col: Color, key: String = "solid") -> void:
	var n := 12
	for k in n:
		batch.tube(key, _cable(ta, tb, sag, float(k) / n), _cable(ta, tb, sag, float(k + 1) / n), r, 6, col)


## Haut des murs, sur toute la piste.
func _wall_props(L: float) -> void:
	var step := (20.0 if _style != TrackTheme.Id.PLAYA_DEL_SOL else 24.0) * _dense()
	var s := 10.0
	var k := 0
	while s < L:
		k += 1
		var side := 1.0 if k % 2 == 0 else -1.0
		var f := _frame(s)
		var i: int = f["i"]
		var railed := _track.is_bridge_deck(i) and _style != TrackTheme.Id.CYBER_CITY
		if not _wall_open(i, side) and not railed and not (_in_stands(s) and _style == TrackTheme.Id.CYBER_CITY):
			var prof: PackedVector3Array = _track._wall_profile(i, side)
			var foot := (prof[1] + prof[2]) / 2.0
			if _clear_box(foot + Vector3(0, 2.5, 0), Vector3(0.6, 2.5, 0.6)):
				var batch := _batch(foot)
				match _style:
					TrackTheme.Id.PLAYA_DEL_SOL: _flag_pole(batch, foot, f, side, k)
					TrackTheme.Id.SAKURA:
						# fete par troncons : bannieres nobori, sinon lanternes
						if int(s / 320.0) % 2 == 0:
							_nobori(batch, foot, f, side, k)
						elif k % 2 == 0:
							_lantern_post(batch, foot, f, side)
					_: _neon_bollard(batch, foot, f, side, k)
				props.append(foot)
		s += step


## Garde-corps des tabliers de pont (Sakura, Playa ; Cyber City n'en a pas) :
## un poteau tous les RAIL_STEP m sur le haut de chaque mur, relie au
## precedent.
const RAIL_STEP := 4.0
const LACQUER := Color(0.78, 0.16, 0.07)
const BRONZE := Color(0.36, 0.45, 0.33)
const SUMI := Color(0.08, 0.06, 0.05)
const DRIFTWOOD := Color(0.62, 0.52, 0.4)
const ROPE := Color(0.84, 0.74, 0.54)
const CORAL := Color(1.0, 0.42, 0.3)
const SHELL_WHITE := Color(0.98, 0.97, 0.93)


func _bridge_rails(L: float) -> void:
	if _style == TrackTheme.Id.CYBER_CITY:
		return
	var step := RAIL_STEP if _style == TrackTheme.Id.SAKURA else 3.0
	for side: float in [-1.0, 1.0]:
		var prev := Vector3.INF
		var k := 0
		var s := 0.0
		while s < L:
			var i := _track.index_at_s(s)
			if not _track.is_bridge_deck(i) or _wall_open(i, side):
				prev = Vector3.INF
				s += step
				continue
			var prof: PackedVector3Array = _track._wall_profile(i, side)
			var foot := (prof[1] + prof[2]) / 2.0
			var f := _frame(s)
			var batch := _batch(foot)
			if _style == TrackTheme.Id.SAKURA:
				_rail_sakura(batch, foot, prev, f, side, k)
			else:
				_rail_playa(batch, foot, prev, f, side, k)
			props.append(foot)
			prev = foot
			k += 1
			s += step


## Poutre de section w x h de a a b (lisse de garde-corps).
func _beam(batch: Batch, a: Vector3, b: Vector3, w: float, h: float, col: Color) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.01:
		return
	var z := d / length
	var x := Vector3.UP.cross(z).normalized()
	var y := z.cross(x)
	batch.box("solid", Transform3D(Basis(x, y, z), (a + b) / 2.0), Vector3(w, h, length), col)


## Garde-corps de Sakura (pont de Kintai, de Shinkyo) : poteaux de laque
## vermillon sur socle noir, giboshi de bronze patine un poteau sur deux,
## main courante, lisse du milieu, lisse basse noire ; une lanterne bonbori
## sur un poteau sur huit.
func _rail_sakura(batch: Batch, foot: Vector3, prev: Vector3, f: Dictionary, _side: float, k: int) -> void:
	var h := 1.25
	var t: Vector3 = f["t"]
	var b := Basis(t.cross(Vector3.UP).normalized(), Vector3.UP, t)
	batch.box("solid", Transform3D(b, foot + Vector3(0, h / 2.0, 0)), Vector3(0.26, h, 0.26), LACQUER)
	batch.box("solid", Transform3D(b, foot + Vector3(0, 0.06, 0)), Vector3(0.38, 0.12, 0.38), SUMI)
	if k % 2 == 0:
		batch.box("solid", Transform3D(b, foot + Vector3(0, h + 0.04, 0)), Vector3(0.3, 0.08, 0.3), BRONZE)
		batch.blob("solid", foot + Vector3(0, h + 0.25, 0), Basis.from_scale(Vector3(0.19, 0.2, 0.19)), BRONZE, 8, 5)
		batch.cone("solid", foot + Vector3(0, h + 0.4, 0), 0.07, 0.24, 8, BRONZE)
	else:
		batch.box("solid", Transform3D(b, foot + Vector3(0, h + 0.03, 0)), Vector3(0.32, 0.06, 0.32), SUMI)
	if prev != Vector3.INF:
		_beam(batch, prev + Vector3(0, h - 0.1, 0), foot + Vector3(0, h - 0.1, 0), 0.17, 0.14, LACQUER)
		_beam(batch, prev + Vector3(0, 0.66, 0), foot + Vector3(0, 0.66, 0), 0.1, 0.1, LACQUER)
		_beam(batch, prev + Vector3(0, 0.2, 0), foot + Vector3(0, 0.2, 0), 0.12, 0.08, SUMI)
	if k % 8 == 3:
		var top := foot + Vector3(0, h, 0)
		batch.box("solid", Transform3D(b, top + Vector3(0, 0.5, 0)), Vector3(0.12, 1.0, 0.12), SUMI)
		batch.box("glow", Transform3D(b, top + Vector3(0, 1.32, 0)), Vector3(0.46, 0.62, 0.46),
			Color(PAPER_WHITE if k % 16 == 3 else PAPER_RED, 0.75))
		batch.box("solid", Transform3D(b, top + Vector3(0, 1.66, 0)), Vector3(0.6, 0.08, 0.6), SUMI)
		batch.cone("solid", top + Vector3(0, 1.7, 0), 0.4, 0.24, 6, SUMI)


## Garde-corps de Playa (promenade de bord de mer) : poteaux de bois flotte,
## deux cordages qui pendent entre eux, une bouee un poteau sur dix, un
## reverbere blanc un poteau sur quatorze.
func _rail_playa(batch: Batch, foot: Vector3, prev: Vector3, f: Dictionary, side: float, k: int) -> void:
	var h := 1.15
	var t: Vector3 = f["t"]
	var inward := -(f["r"] as Vector3) * side
	batch.tube("solid", foot, foot + Vector3(0, h, 0), 0.11, 6, DRIFTWOOD)
	batch.cone("solid", foot + Vector3(0, h, 0), 0.11, 0.07, 6, DRIFTWOOD.darkened(0.2))
	if prev != Vector3.INF:
		for hy: float in [h - 0.12, 0.6]:
			var a := prev + Vector3(0, hy, 0)
			var b := foot + Vector3(0, hy, 0)
			for q in 4:
				batch.tube("solid", _cable(a, b, 0.14, q / 4.0), _cable(a, b, 0.14, (q + 1) / 4.0), 0.035, 5, ROPE)
	if k % 10 == 5:
		_life_ring(batch, foot + Vector3(0, 0.62, 0) + inward * 0.2, t)
	if k % 14 == 0:
		var top := foot + Vector3(0, 4.2, 0)
		var white := Color(0.95, 0.95, 0.92)
		batch.tube("solid", foot, top, 0.07, 6, white)
		batch.tube("solid", top, top + inward * 0.7, 0.04, 4, white)
		var lamp := top + inward * 0.7
		batch.box("glow", Transform3D(Basis.IDENTITY, lamp - Vector3(0, 0.28, 0)), Vector3(0.28, 0.38, 0.28), Color(1.0, 0.9, 0.65, 0.8))
		batch.cone("solid", lamp - Vector3(0, 0.08, 0), 0.26, 0.18, 6, Color(0.05, 0.4, 0.46))


## Bouee de sauvetage (anneau corail et blanc) dans le plan vertical de la
## piste, en `c`.
func _life_ring(batch: Batch, c: Vector3, t: Vector3) -> void:
	var n := 12
	for q in n:
		var a0 := TAU * q / n
		var a1 := TAU * (q + 1) / n
		var p0 := c + (t * cos(a0) + Vector3.UP * sin(a0)) * 0.32
		var p1 := c + (t * cos(a1) + Vector3.UP * sin(a1)) * 0.32
		batch.tube("solid", p0, p1, 0.08, 6, CORAL if int(q / 3.0) % 2 == 0 else SHELL_WHITE)


## Piliers aux bouts des murs ouverts par un raccourci : la coupe du mur
## ne se voit plus. Acier a bandeau neon (Cyber City), beton blanc a tete
## rouge (Playa), poteau de bois sombre a giboshi (Sakura).
func _wall_ends() -> void:
	for side: float in [-1.0, 1.0]:
		var opened: PackedByteArray = _track._wall_open[0 if side < 0.0 else 1]
		if opened.is_empty():
			continue
		var n := opened.size()
		for i in n:
			var built_before := opened[posmod(i - 1, n)] == 0 and opened[i] == 0
			var built_after := opened[i] == 0 and opened[(i + 1) % n] == 0
			if built_before == built_after:
				continue
			var prof: PackedVector3Array = _track._wall_profile(i, side)
			var top := (prof[1] + prof[2]) / 2.0
			var bottom := minf(prof[0].y, prof[3].y)
			var t := (_track.sample_forward(i) * Vector3(1, 0, 1)).normalized()
			var b := Basis(t.cross(Vector3.UP).normalized(), Vector3.UP, t)
			var width := prof[1].distance_to(prof[2]) + 0.5
			var h := top.y + 0.45 - bottom
			var c := Vector3(top.x, bottom + h / 2.0, top.z)
			var batch := _batch(c)
			match _style:
				TrackTheme.Id.PLAYA_DEL_SOL:
					batch.box("solid", Transform3D(b, c), Vector3(width, h, 0.9), Color(0.92, 0.91, 0.88))
					batch.box("solid", Transform3D(b, Vector3(c.x, top.y + 0.2, c.z)), Vector3(width + 0.04, 0.5, 0.94), CORAL)
					batch.box("solid", Transform3D(b, Vector3(c.x, top.y + 0.5, c.z)), Vector3(width + 0.1, 0.1, 1.0),
						Color(0.05, 0.75, 0.8))
				TrackTheme.Id.SAKURA:
					batch.box("solid", Transform3D(b, c + Vector3(0, 0.3, 0)), Vector3(0.7, h + 0.6, 0.7), Color(0.2, 0.12, 0.07))
					var cap := Vector3(c.x, bottom + h + 0.6, c.z)
					batch.box("solid", Transform3D(b, cap + Vector3(0, 0.05, 0)), Vector3(0.78, 0.1, 0.78), BRONZE)
					batch.blob("solid", cap + Vector3(0, 0.36, 0), Basis.from_scale(Vector3(0.36, 0.34, 0.36)), BRONZE, 8, 5)
					batch.cone("solid", cap + Vector3(0, 0.62, 0), 0.12, 0.4, 8, BRONZE)
				_:
					batch.box("solid", Transform3D(b, c), Vector3(width, h, 0.9), Color(0.1, 0.11, 0.14))
					var neon := NEON[0] if side < 0.0 else NEON[1]
					batch.box("glow", Transform3D(b, Vector3(c.x, top.y + 0.1, c.z)), Vector3(width + 0.06, 0.16, 0.96), neon)
			props.append(top)


## Panneaux sur la face interieure des murs, le long de la courbe du mur.
func _wall_boards(L: float) -> void:
	var spacing := 52.0
	var length := 11.0
	match _style:
		TrackTheme.Id.PLAYA_DEL_SOL:
			spacing = 46.0
			length = 9.0
		TrackTheme.Id.SAKURA:
			spacing = 40.0
			length = 16.0
	var s := 30.0
	var k := 0
	while s < L:
		k += 1
		var side := 1.0 if k % 2 == 0 else -1.0
		# Sakura : rideaux de fete dans les troncons de fete (avec les nobori)
		var skip := _style == TrackTheme.Id.SAKURA and int(s / 320.0) % 2 == 1
		var i0 := _track.index_at_s(s)
		var i1 := _track.index_at_s(s + length)
		if not skip and not _wall_open(i0, side) and not _wall_open(i1, side):
			_board(s, length, side, k)
		s += spacing * _dense() + _range(-6.0, 6.0)


func _board(s: float, length: float, side: float, k: int) -> void:
	var n := maxi(2, roundi(length / 2.0))
	var lo := 0.35
	var hi := 2.35 if _style != TrackTheme.Id.SAKURA else 2.55
	var pts_lo: Array[Vector3] = []
	var pts_hi: Array[Vector3] = []
	var inward := Vector3.ZERO
	for j in n + 1:
		var f := _frame(s + length * j / n)
		var prof: PackedVector3Array = _track._wall_profile(f["i"], side)
		var span := prof[1] - prof[0]
		var h := span.y
		var into := -(f["r"] as Vector3) * side
		inward = into
		pts_lo.append(prof[0] + span * ((lo + 0.3) / h) + into * 0.06)
		pts_hi.append(prof[0] + span * ((hi + 0.3) / h) + into * 0.06)
	var batch := _batch(pts_lo[n / 2])
	var key := "holo"
	var col := Color.WHITE
	match _style:
		TrackTheme.Id.PLAYA_DEL_SOL:
			key = "solid"
			col = BUNTING[k % BUNTING.size()]
		TrackTheme.Id.SAKURA:
			key = "maku"
	var dist := 0.0
	for j in n:
		var u0 := float(j) / n
		var u1 := float(j + 1) / n
		var uv := [Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0), Vector2(u0, 0)]
		if key == "maku":
			var seg := pts_lo[j].distance_to(pts_lo[j + 1])
			uv = [Vector2(dist, 0), Vector2(dist + seg, 0), Vector2(dist + seg, 1), Vector2(dist, 1)]
			dist += seg
		batch.quad(key, pts_lo[j], pts_lo[j + 1], pts_hi[j + 1], pts_hi[j], col, uv, inward)
	if _style == TrackTheme.Id.PLAYA_DEL_SOL:
		# bandeau blanc et nom du sponsor, un panneau sur deux
		for j in n:
			var a := pts_hi[j].lerp(pts_lo[j], 0.12)
			var b := pts_hi[j + 1].lerp(pts_lo[j + 1], 0.12)
			batch.quad("solid", a + inward * 0.01, b + inward * 0.01, pts_hi[j + 1] + inward * 0.01, pts_hi[j] + inward * 0.01,
				Color(0.98, 0.98, 0.95), [], inward)
		if k % 2 == 0:
			var mid := (pts_lo[n / 2] + pts_hi[n / 2]) / 2.0 + inward * 0.03 - Vector3(0, 0.15, 0)
			var z := inward.normalized()
			var word := SPONSORS[int(_rand() * SPONSORS.size()) % SPONSORS.size()]
			_label(word, mid, Basis(Vector3.UP.cross(z), Vector3.UP, z), Color(0.98, 0.98, 0.95), 120, 0.012)
	props.append(pts_lo[n / 2])


## Pied des murs, la ou la route est au sol.
func _ground_props(L: float) -> void:
	var s := 20.0
	while s < L:
		var f := _frame(s)
		var i: int = f["i"]
		var step := 12.0 * _dense()
		# une autre partie de la piste a cote (croisement, echangeur) : rien
		if f["low"] and not _in_stands(s) and _track.other_section_distance(f["p"], s) > _track.width + 30.0:
			for side: float in [-1.0, 1.0]:
				if _wall_open(i, side):
					continue
				match _style:
					TrackTheme.Id.PLAYA_DEL_SOL: _ground_playa(f, side)
					TrackTheme.Id.SAKURA: _ground_sakura(f, side)
					_: _ground_cyber(f, side)
		s += step


func _ground_spot(f: Dictionary, side: float, out: float, along: float = 0.0) -> Vector3:
	var c: Vector3 = f["p"] + (f["r"] as Vector3) * side * (_beyond + out) + (f["t"] as Vector3) * along
	c.y = TrackBlockout.GROUND_Y
	return c


func _ok_ground(c: Vector3, radius: float, _s: float) -> bool:
	return _clear_box(c + Vector3(0, 2, 0), Vector3(radius, 2, radius))


# --- Cyber City ------------------------------------------------------------------

const NEON: Array[Color] = [Color(0.1, 0.95, 1.0), Color(1.0, 0.15, 0.75), Color(0.6, 0.3, 1.0), Color(1.0, 0.85, 0.15)]
const CYBER_WORDS: PackedStringArray = ["RAMEN", "HOTEL", "24/7", "ARCADE", "ネオン", "ラーメン", "サイバー", "KARAOKE", "NOODLE"]


func _span_cyber(batch: Batch, f: Dictionary, a: Vector3, b: Vector3, ta: Vector3, tb: Vector3, sag: float) -> void:
	var steel := Color(0.12, 0.13, 0.16)
	var c1: Color = NEON[int(_rand() * 4.0) % 4]
	var c2: Color = NEON[int(_rand() * 4.0) % 4]
	for pair: Array in [[a, ta, c1], [b, tb, c2]]:
		var foot: Vector3 = pair[0]
		var top: Vector3 = pair[1]
		batch.box("solid", Transform3D(Basis.IDENTITY, (foot + top + Vector3(0, 0.6, 0)) / 2.0),
			Vector3(0.45, top.y + 0.6 - foot.y, 0.45), steel)
		# tube neon sur le mat, face a la route
		var inward := (Vector3((f["p"] as Vector3).x, foot.y, (f["p"] as Vector3).z) - foot).normalized()
		batch.box("glow", Transform3D(Basis.IDENTITY, (foot + top) / 2.0 + inward * 0.26 + Vector3(0, 0.5, 0)),
			Vector3(0.1, top.y - foot.y - 1.0, 0.1), Color(pair[2], 1.0))
	_draw_cable(batch, ta, tb, sag, 0.06, steel)
	# barres neon suspendues le long du cable, et une grande enseigne au milieu
	var n := 9
	for k in range(1, n):
		var u := float(k) / n
		if absf(u - 0.5) < 0.12:
			continue
		var at := _cable(ta, tb, sag, u)
		batch.tube("solid", at, at - Vector3(0, 0.6, 0), 0.02, 4, steel)
		batch.box("glow", Transform3D(Basis.IDENTITY, at - Vector3(0, 1.45, 0)), Vector3(0.16, 1.7, 0.16),
			Color(NEON[k % 4], 1.0))
	var mid := _cable(ta, tb, sag, 0.5)
	var t: Vector3 = f["t"]
	var r: Vector3 = f["r"]
	var sign_basis := Basis(r, Vector3.UP, -t)
	var center := mid - Vector3(0, 2.4, 0)
	batch.box("solid", Transform3D(sign_basis, center), Vector3(5.4, 2.6, 0.25), Color(0.04, 0.04, 0.07))
	var col: Color = NEON[int(_rand() * 4.0) % 4]
	for edge: Array in [[Vector3(0, 1.3, 0), Vector3(5.4, 0.12, 0.3)], [Vector3(0, -1.3, 0), Vector3(5.4, 0.12, 0.3)],
			[Vector3(2.7, 0, 0), Vector3(0.12, 2.6, 0.3)], [Vector3(-2.7, 0, 0), Vector3(0.12, 2.6, 0.3)]]:
		batch.box("glow", Transform3D(sign_basis, center + sign_basis * (edge[0] as Vector3)), edge[1], Color(col, 1.0))
	for side: float in [-1.0, 1.0]:
		batch.tube("solid", mid + r * side * 2.4, center + r * side * 2.4 + Vector3(0, 1.3, 0), 0.03, 4, steel)
	var word := CYBER_WORDS[int(_rand() * CYBER_WORDS.size()) % CYBER_WORDS.size()]
	_label(word, center - t * 0.16, Basis(r, Vector3.UP, -t), col, 110, 0.016)
	_label(word, center + t * 0.16, Basis(-r, Vector3.UP, t), col, 110, 0.016)


func _neon_bollard(batch: Batch, foot: Vector3, _f: Dictionary, _side: float, k: int) -> void:
	batch.box("solid", Transform3D(Basis.IDENTITY, foot + Vector3(0, 0.35, 0)), Vector3(0.3, 0.7, 0.3), Color(0.1, 0.1, 0.13))
	batch.box("glow", Transform3D(Basis.IDENTITY, foot + Vector3(0, 1.05, 0)), Vector3(0.22, 0.7, 0.22), Color(NEON[k % 2], 1.0))


func _ground_cyber(f: Dictionary, side: float) -> void:
	var s: float = f["s"]
	var t: Vector3 = f["t"]
	var r: Vector3 = f["r"]
	# distributeurs lumineux au pied du mur, par grappes
	if _rand() < 0.22:
		var c := _ground_spot(f, side, 1.4, _range(-4, 4))
		if _ok_ground(c, 3.0, s):
			var batch := _batch(c)
			var face := Basis(t * side, Vector3.UP, -r * side)
			var count := 2 + int(_rand() * 2.0)
			for k in count:
				var at := c + t * (k * 1.3 - count * 0.65)
				var col: Color = NEON[int(_rand() * 4.0) % 4]
				batch.box("solid", Transform3D(face, at + Vector3(0, 1.0, 0)), Vector3(1.15, 2.0, 0.85), Color(0.75, 0.76, 0.8))
				batch.box("glow", Transform3D(face, at + Vector3(0, 1.15, 0) - r * side * 0.44), Vector3(0.95, 1.3, 0.04),
					Color(col.lerp(Color.WHITE, 0.35), 0.8))
			props.append(c)
	# ecrans holographiques sur mats, tournes vers les camions qui arrivent
	if _rand() < 0.1:
		var c := _ground_spot(f, side, 6.0)
		if _ok_ground(c, 4.0, s):
			var batch := _batch(c)
			batch.box("solid", Transform3D(Basis.IDENTITY, c + Vector3(0, 4.5, 0)), Vector3(0.5, 9.0, 0.5), Color(0.12, 0.13, 0.16))
			var face := Basis(Vector3.UP, side * deg_to_rad(28.0)) * Basis(r, Vector3.UP, -t)
			var center := c + Vector3(0, 11.0, 0)
			var hw := face.x * 5.0
			var hh := Vector3(0, 2.8, 0)
			batch.quad("holo", center - hw - hh, center + hw - hh, center + hw + hh, center - hw + hh, Color.WHITE,
				[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], face.z, true)
			props.append(c)


# --- Playa Del Sol ---------------------------------------------------------------

const BUNTING: Array[Color] = [Color(0.95, 0.2, 0.2), Color(1.0, 0.8, 0.1), Color(0.1, 0.7, 0.85), Color(0.98, 0.98, 0.95),
	Color(1.0, 0.5, 0.15), Color(1.0, 0.45, 0.7), Color(0.2, 0.75, 0.45)]
const PLAYA_WORDS: PackedStringArray = ["PLAYA DEL SOL", "SURF CUP", "¡VAMOS!", "FIESTA", "BEACH RACE"]
const SPONSORS: PackedStringArray = ["COCO LOCO", "SURF SHOP", "HELADOS", "TACO TRUCK", "PLAYA DEL SOL", "OLA!", "SOL Y MAR"]


func _span_playa(batch: Batch, f: Dictionary, a: Vector3, b: Vector3, ta: Vector3, tb: Vector3, sag: float) -> void:
	var wood := Color(0.45, 0.32, 0.2)
	for pair: Array in [[a, ta], [b, tb]]:
		batch.tube("solid", pair[0], (pair[1] as Vector3) + Vector3(0, 0.8, 0), 0.22, 8, wood)
	var t: Vector3 = f["t"]
	# deux guirlandes de fanions, flechies differemment
	for g in 2:
		var sg := sag * (1.0 + 0.35 * g)
		var off := t * (0.5 * (g * 2 - 1))
		var ga := ta + off - Vector3(0, 0.4 * g, 0)
		var gb := tb + off - Vector3(0, 0.4 * g, 0)
		_draw_cable(batch, ga, gb, sg, 0.025, Color(0.9, 0.88, 0.8))
		var width := ga.distance_to(gb)
		var n := int(width / 1.3)
		for k in n:
			var u0 := (k + 0.15) / n
			var u1 := (k + 0.85) / n
			var p0 := _cable(ga, gb, sg, u0)
			var p1 := _cable(ga, gb, sg, u1)
			var tip := (p0 + p1) / 2.0 - Vector3(0, 1.05, 0)
			batch.tri("cloth", p0, p1, tip, BUNTING[(k + g * 3) % BUNTING.size()], t, true)
	# une banderole sur trois
	if _rand() < 0.35:
		var mid := _cable(ta, tb, sag, 0.5)
		var r: Vector3 = f["r"]
		var hw := r * 4.2
		var top := mid - Vector3(0, 0.6, 0)
		var bot := top - Vector3(0, 1.7, 0)
		var col: Color = BUNTING[int(_rand() * 3.0) % 3]
		batch.quad("cloth", bot - hw, bot + hw, top + hw, top - hw, Color(0.98, 0.97, 0.92), [], -t, true)
		batch.quad("cloth", bot - hw - Vector3(0, 0.2, 0), bot + hw - Vector3(0, 0.2, 0), bot + hw, bot - hw, col, [], -t, true)
		var word := PLAYA_WORDS[int(_rand() * PLAYA_WORDS.size()) % PLAYA_WORDS.size()]
		var center := (top + bot) / 2.0
		_label(word, center - t * 0.05, Basis(r, Vector3.UP, -t), col.darkened(0.2), 90, 0.016)
		_label(word, center + t * 0.05, Basis(-r, Vector3.UP, t), col.darkened(0.2), 90, 0.016)


func _flag_pole(batch: Batch, foot: Vector3, f: Dictionary, side: float, k: int) -> void:
	var top := foot + Vector3(0, 5.0, 0)
	batch.tube("solid", foot, top, 0.06, 6, Color(0.92, 0.92, 0.9))
	var t: Vector3 = f["t"]
	var col: Color = BUNTING[k % BUNTING.size()]
	# fanion qui flotte vers l'arriere (le vent de la course)
	batch.tri("cloth", top, top - Vector3(0, 0.9, 0), top - t * 1.8 - Vector3(0, 0.35, 0) + (f["r"] as Vector3) * side * 0.1,
		col, f["r"], true)


func _ground_playa(f: Dictionary, side: float) -> void:
	var s: float = f["s"]
	var t: Vector3 = f["t"]
	var r: Vector3 = f["r"]
	# touffes d'herbe de dune et buissons au pied du mur
	if _rand() < 0.75:
		var c := _ground_spot(f, side, _range(0.8, 4.0), _range(-4, 4))
		if _ok_ground(c, 2.0, s):
			var batch := _batch(c)
			for q in 3 + int(_rand() * 3.0):
				var at := c + t * _range(-2.0, 2.0) + r * side * _range(-0.8, 1.5)
				_tuft(batch, at, _range(0.6, 1.1))
			if _rand() < 0.4:
				var green := Color(0.22, 0.45, 0.18).lerp(Color(0.4, 0.55, 0.2), _rand())
				batch.blob("bush", c + r * side * 2.0 + Vector3(0, 0.45, 0), Basis.from_scale(Vector3(1.2, 0.7, 1.0)), green, 6, 4)
	var roll := _rand()
	if roll < 0.3:
		# planches de surf plantees dans le sable
		var c := _ground_spot(f, side, _range(3.0, 6.0), _range(-3, 3))
		if _ok_ground(c, 2.5, s):
			var batch := _batch(c)
			var count := 2 + int(_rand() * 3.0)
			for k in count:
				var at := c + t * (k * 0.75 - count * 0.37)
				var tilt := Basis(t, _range(-0.2, 0.2)) * Basis(Vector3.UP, _range(-0.5, 0.5))
				var col: Color = BUNTING[int(_rand() * BUNTING.size()) % BUNTING.size()]
				batch.blob("solid", at + Vector3(0, 1.05, 0), tilt * Basis.from_scale(Vector3(0.32, 1.25, 0.07)), col)
			props.append(c)
	elif roll < 0.36:
		# tour de sauveteur
		var c := _ground_spot(f, side, 9.0)
		if _ok_ground(c, 3.5, s):
			var batch := _batch(c)
			for dx: float in [-1.0, 1.0]:
				for dz: float in [-1.0, 1.0]:
					var leg := c + t * dx * 1.1 + r * dz * 1.1
					batch.tube("solid", leg, leg + Vector3(0, 3.2, 0) - t * dx * 0.2 - r * dz * 0.2, 0.09, 6, Color(0.95, 0.95, 0.92))
			var cabin := c + Vector3(0, 4.0, 0)
			var face := Basis(t, Vector3.UP, -r * side) if side > 0.0 else Basis(-t, Vector3.UP, r)
			batch.box("solid", Transform3D(face, cabin), Vector3(2.4, 1.6, 2.4), Color(0.9, 0.18, 0.15))
			batch.box("solid", Transform3D(face, cabin + Vector3(0, 0.15, 0)), Vector3(2.45, 0.35, 2.45), Color(0.97, 0.97, 0.95))
			batch.box("solid", Transform3D(face, cabin + Vector3(0, 1.05, 0)), Vector3(3.0, 0.2, 3.0), Color(0.97, 0.97, 0.95))
			var mast := cabin + Vector3(0, 1.1, 0)
			batch.tube("solid", mast, mast + Vector3(0, 2.2, 0), 0.04, 4, Color(0.9, 0.9, 0.9))
			batch.tri("cloth", mast + Vector3(0, 2.2, 0), mast + Vector3(0, 1.5, 0), mast + Vector3(0, 1.85, 0) - t * 1.1,
				Color(0.95, 0.2, 0.15), r, true)
			props.append(c)
	elif roll < 0.4:
		# paillote : quatre poteaux, comptoir, toit de paille
		var c := _ground_spot(f, side, 8.0)
		if _ok_ground(c, 4.0, s):
			var batch := _batch(c)
			var wood := Color(0.48, 0.34, 0.2)
			for dx: float in [-1.0, 1.0]:
				for dz: float in [-1.0, 1.0]:
					var post := c + t * dx * 1.8 + r * dz * 1.8
					batch.tube("solid", post, post + Vector3(0, 2.6, 0), 0.12, 6, wood)
			batch.box("solid", Transform3D(Basis(r, Vector3.UP, -t), c + Vector3(0, 0.55, 0)), Vector3(3.4, 1.1, 1.0), wood)
			batch.cone("solid", c + Vector3(0, 2.5, 0), 3.4, 2.2, 10, Color(0.82, 0.7, 0.42))
			props.append(c)


## Touffe d'herbe de dune : quelques brins (triangles fins) en eventail.
func _tuft(batch: Batch, at: Vector3, h: float) -> void:
	var col := Color(0.55, 0.62, 0.28).lerp(Color(0.78, 0.74, 0.42), _rand())
	for q in 5:
		var a := _rand() * TAU
		var d := Vector3(cos(a), 0, sin(a))
		var lean := d * h * 0.45
		var w := Vector3(-d.z, 0, d.x) * 0.06
		batch.tri("cloth", at - w, at + w, at + lean + Vector3(0, h, 0), col, d, true)


# --- Sakura ----------------------------------------------------------------------

const PAPER_RED := Color(0.95, 0.18, 0.1)
const AZALEA: Array[Color] = [Color(0.92, 0.32, 0.58), Color(0.98, 0.55, 0.72), Color(0.82, 0.2, 0.4), Color(0.2, 0.38, 0.17),
	Color(0.26, 0.45, 0.2)]
const PAPER_WHITE := Color(1.0, 0.92, 0.78)
const NOBORI: Array[Color] = [Color(0.12, 0.16, 0.38), Color(0.82, 0.14, 0.08), Color(0.97, 0.95, 0.9), Color(1.0, 0.6, 0.72)]


func _span_sakura(batch: Batch, f: Dictionary, a: Vector3, b: Vector3, ta: Vector3, tb: Vector3, sag: float) -> void:
	var wood := Color(0.16, 0.09, 0.05)
	for pair: Array in [[a, ta], [b, tb]]:
		batch.tube("solid", pair[0], (pair[1] as Vector3) + Vector3(0, 0.7, 0), 0.24, 8, wood)
		batch.box("solid", Transform3D(Basis.IDENTITY, (pair[1] as Vector3) + Vector3(0, 0.75, 0)), Vector3(0.7, 0.18, 0.7), wood)
	var t: Vector3 = f["t"]
	if _rand() < 0.25:
		# shimenawa : grosse corde de paille et zigzags de papier blanc
		var straw := Color(0.84, 0.74, 0.46)
		_draw_cable(batch, ta, tb, sag, 0.28, straw)
		var n := 10
		for k in range(1, n):
			var at := _cable(ta, tb, sag, float(k) / n) - Vector3(0, 0.3, 0)
			var w := (f["r"] as Vector3) * 0.18
			for z in 3:
				var y := at - Vector3(0, 0.35 * z, 0)
				var dx := w * (1.0 if z % 2 == 0 else -1.0)
				batch.quad("cloth", y - Vector3(0, 0.35, 0) - dx, y - Vector3(0, 0.35, 0) + dx, y + dx, y - dx, Color(0.99, 0.99, 0.97),
					[], -t, true)
		return
	_draw_cable(batch, ta, tb, sag, 0.03, Color(0.1, 0.07, 0.05))
	var width := ta.distance_to(tb)
	var n := int(width / 2.3)
	for k in range(1, n):
		var at := _cable(ta, tb, sag, float(k) / n)
		var col := PAPER_RED if k % 3 != 0 else PAPER_WHITE
		batch.tube("solid", at, at - Vector3(0, 0.45, 0), 0.015, 4, Color(0.05, 0.04, 0.03))
		var c := at - Vector3(0, 1.0, 0)
		batch.blob("glow", c, Basis.from_scale(Vector3(0.36, 0.52, 0.36)), Color(col, 0.75))
		batch.box("solid", Transform3D(Basis.IDENTITY, c + Vector3(0, 0.5, 0)), Vector3(0.36, 0.08, 0.36), Color(0.05, 0.04, 0.03))
		batch.box("solid", Transform3D(Basis.IDENTITY, c - Vector3(0, 0.5, 0)), Vector3(0.36, 0.08, 0.36), Color(0.05, 0.04, 0.03))


## Banniere nobori : mat, traverse, toile verticale le long de la piste.
func _nobori(batch: Batch, foot: Vector3, f: Dictionary, side: float, k: int) -> void:
	var t: Vector3 = f["t"]
	var top := foot + Vector3(0, 5.4, 0)
	batch.tube("solid", foot, top, 0.05, 6, Color(0.2, 0.12, 0.07))
	batch.tube("solid", top - Vector3(0, 0.1, 0), top - Vector3(0, 0.1, 0) - t * 0.85, 0.03, 4, Color(0.2, 0.12, 0.07))
	var col: Color = NOBORI[k % NOBORI.size()]
	var x0 := top - Vector3(0, 0.12, 0) - t * 0.05
	var x1 := x0 - t * 0.8
	var bottom := Vector3(0, 3.7, 0)
	var r: Vector3 = f["r"]
	batch.quad("cloth", x0 - bottom, x1 - bottom, x1, x0, col, [], r * side, true)
	# disque contrastant (blason) au tiers haut
	var c := (x0 + x1) / 2.0 - Vector3(0, 1.1, 0) - r * side * 0.01
	var disc := col.inverted() if col.v < 0.5 else Color(0.82, 0.14, 0.08)
	if col.is_equal_approx(NOBORI[1]):
		disc = Color(0.98, 0.96, 0.9)
	for q in 8:
		var a0 := TAU * q / 8.0
		var a1 := TAU * (q + 1) / 8.0
		batch.tri("cloth", c, c + (t * cos(a0) + Vector3.UP * sin(a0)) * 0.28, c + (t * cos(a1) + Vector3.UP * sin(a1)) * 0.28,
			disc, r * side, true)


func _lantern_post(batch: Batch, foot: Vector3, _f: Dictionary, _side: float) -> void:
	batch.box("solid", Transform3D(Basis.IDENTITY, foot + Vector3(0, 0.6, 0)), Vector3(0.18, 1.2, 0.18), Color(0.2, 0.12, 0.07))
	batch.box("glow", Transform3D(Basis.IDENTITY, foot + Vector3(0, 1.45, 0)), Vector3(0.5, 0.55, 0.5), Color(PAPER_WHITE, 0.7))
	batch.box("solid", Transform3D(Basis.IDENTITY, foot + Vector3(0, 1.8, 0)), Vector3(0.7, 0.12, 0.7), Color(0.12, 0.08, 0.05))


func _ground_sakura(f: Dictionary, side: float) -> void:
	var s: float = f["s"]
	# azalees taillees en boules (fleuries ou vertes), au pied du mur
	if _rand() < 0.7:
		var c := _ground_spot(f, side, _range(2.2, 4.5), _range(-4, 4))
		if _ok_ground(c, 2.0, s):
			var batch := _batch(c)
			for q in 2 + int(_rand() * 2.0):
				var at := c + (f["t"] as Vector3) * _range(-2.0, 2.0) + (f["r"] as Vector3) * side * _range(-0.6, 0.8)
				var col: Color = AZALEA[int(_rand() * AZALEA.size()) % AZALEA.size()]
				var sz := _range(0.7, 1.2)
				batch.blob("bush", at + Vector3(0, sz * 0.55, 0), Basis.from_scale(Vector3(sz * 1.2, sz * 0.75, sz * 1.1)), col, 6, 4)
	# palissade de bambou au pied du mur, par troncons
	if int(s / 210.0 + side * 0.5) % 3 == 2:
		return
	var t: Vector3 = f["t"]
	var c := _ground_spot(f, side, 0.7)
	var half_len := 6.0
	if not _ok_ground(c, half_len, s):
		return
	var batch := _batch(c)
	var a := c - t * half_len
	var b := c + t * half_len
	var h := Vector3(0, 1.8, 0)
	batch.quad("fence", a, b, b + h, a + h, Color.WHITE, [Vector2(0, 0), Vector2(half_len * 2.0, 0),
		Vector2(half_len * 2.0, 1.8), Vector2(0, 1.8)], -(f["r"] as Vector3) * side, true)
	props.append(c)


# --- lots, materiaux, textes -----------------------------------------------------

func _batch(at: Vector3) -> Batch:
	var key := Vector2i(floori(at.x / CELL), floori(at.z / CELL))
	if not _batches.has(key):
		_batches[key] = Batch.new(Vector3((key.x + 0.5) * CELL, 0.0, (key.y + 0.5) * CELL))
	return _batches[key]


func _label(text: String, at: Vector3, basis: Basis, color: Color, size: int, pixel: float) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = TrackTheme.cjk_font()
	l.font_size = size
	l.pixel_size = pixel
	l.outline_size = 0
	l.modulate = Color(color.r * 1.6, color.g * 1.6, color.b * 1.6) if _style == TrackTheme.Id.CYBER_CITY else color
	l.shaded = _style != TrackTheme.Id.CYBER_CITY
	l.double_sided = false
	l.transform = Transform3D(basis, at)
	l.visibility_range_end = VIEW_END * (EXTREME_VIEW if _x else 1.0)
	_labels.append(l)


func _materials() -> Dictionary:
	var solid := StandardMaterial3D.new()
	solid.vertex_color_use_as_albedo = true
	solid.roughness = 0.7
	var cloth := StandardMaterial3D.new()
	cloth.vertex_color_use_as_albedo = true
	cloth.roughness = 0.9
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	cloth.backlight_enabled = true
	cloth.backlight = Color(0.35, 0.35, 0.35)
	var glow := ShaderMaterial.new()
	glow.shader = preload("res://tracks/materials/dress_glow.gdshader")
	glow.set_shader_parameter("glow", 2.6 if _style == TrackTheme.Id.CYBER_CITY else 1.2)
	var holo := ShaderMaterial.new()
	holo.shader = preload("res://tracks/materials/holo_screen.gdshader")
	holo.set_shader_parameter("strength", 0.8)
	var fence := ShaderMaterial.new()
	fence.shader = preload("res://tracks/materials/bamboo_fence.gdshader")
	var bush := ShaderMaterial.new()
	bush.shader = preload("res://tracks/materials/sakura_blossom.gdshader")
	var maku := ShaderMaterial.new()
	maku.shader = preload("res://tracks/materials/festival_maku.gdshader")
	return {"solid": solid, "cloth": cloth, "glow": glow, "holo": holo, "fence": fence, "bush": bush, "maku": maku}


func _commit() -> void:
	var root := Node3D.new()
	root.name = "Dressing"
	add_child(root)
	var mats := _materials()
	var n := 0
	for key: Vector2i in _batches:
		var batch: Batch = _batches[key]
		var mi := MeshInstance3D.new()
		mi.name = "Cell%d" % n
		mi.mesh = batch.commit(mats)
		mi.position = batch.origin
		mi.visibility_range_end = VIEW_END * (EXTREME_VIEW if _x else 1.0)
		mi.visibility_range_end_margin = 60.0
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		root.add_child(mi)
		n += 1
	for l in _labels:
		root.add_child(l)


## Lot de geometrie d'une case : une SurfaceTool par materiau, sommets
## relatifs a `origin` (le noeud est pose la : la portee de vue se mesure
## depuis la case). Couleur de sommet ; faces orientees vers `hint` (les
## toiles : des deux cotes).
class Batch:
	var origin: Vector3
	var _st: Dictionary = {}

	func _init(at: Vector3) -> void:
		origin = at

	func _tool(key: String) -> SurfaceTool:
		if not _st.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			_st[key] = st
		return _st[key]

	func _emit(st: SurfaceTool, v: Array, uv: Array, col: Color) -> void:
		for k in v.size():
			st.set_color(col)
			st.set_uv(uv[k] if not uv.is_empty() else Vector2.ZERO)
			st.add_vertex((v[k] as Vector3) - origin)

	## Triangle visible du cote `hint` (et de l'autre si `two_sided`).
	func tri(key: String, a: Vector3, b: Vector3, c: Vector3, col: Color, hint: Vector3, two_sided: bool = false) -> void:
		var st := _tool(key)
		# Godot : face avant = sens horaire vu de face
		var n := (b - a).cross(c - a)
		if n.dot(hint) > 0.0:
			_emit(st, [a, c, b], [], col)
		else:
			_emit(st, [a, b, c], [], col)
		if two_sided:
			if n.dot(hint) > 0.0:
				_emit(st, [a, b, c], [], col)
			else:
				_emit(st, [a, c, b], [], col)

	## Quadrilatere a, b, c, d (dans l'ordre du pourtour).
	func quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, uv: Array, hint: Vector3,
			two_sided: bool = false) -> void:
		var st := _tool(key)
		var n := (b - a).cross(c - a)
		var flip := n.dot(hint) > 0.0
		var uva: Array = uv if not uv.is_empty() else [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
		for pass_k in (2 if two_sided else 1):
			var front := flip if pass_k == 0 else not flip
			if front:
				_emit(st, [a, c, b, a, d, c], [uva[0], uva[2], uva[1], uva[0], uva[3], uva[2]], col)
			else:
				_emit(st, [a, b, c, a, c, d], [uva[0], uva[1], uva[2], uva[0], uva[2], uva[3]], col)

	## Boite centree en `xf`.
	func box(key: String, xf: Transform3D, size: Vector3, col: Color) -> void:
		var h := size / 2.0
		for axis in 3:
			for sgn: float in [-1.0, 1.0]:
				var n := Vector3.ZERO
				n[axis] = sgn
				var u := Vector3.ZERO
				u[(axis + 1) % 3] = 1.0
				var v := Vector3.ZERO
				v[(axis + 2) % 3] = 1.0
				var fc := n * h
				var du := u * h
				var dv := v * h
				var pts := [fc - du - dv, fc + du - dv, fc + du + dv, fc - du + dv]
				var w: Array = []
				for p: Vector3 in pts:
					w.append(xf * p)
				quad(key, w[0], w[1], w[2], w[3], col, [], xf.basis * n)

	## Tube ouvert de a a b, rayon r.
	func tube(key: String, a: Vector3, b: Vector3, r: float, segs: int, col: Color) -> void:
		var axis := (b - a)
		if axis.length() < 1e-4:
			return
		axis = axis.normalized()
		var side := axis.cross(Vector3.UP)
		if side.length() < 1e-3:
			side = axis.cross(Vector3.RIGHT)
		side = side.normalized()
		var up := side.cross(axis).normalized()
		for k in segs:
			var a0 := TAU * k / segs
			var a1 := TAU * (k + 1) / segs
			var d0 := side * cos(a0) + up * sin(a0)
			var d1 := side * cos(a1) + up * sin(a1)
			quad(key, a + d0 * r, a + d1 * r, b + d1 * r, b + d0 * r, col, [], d0 + d1)

	## Cone plein (toit de paille) : base de rayon r en `base`, pointe h au-dessus.
	func cone(key: String, base: Vector3, r: float, h: float, segs: int, col: Color) -> void:
		var tip := base + Vector3(0, h, 0)
		for k in segs:
			var a0 := TAU * k / segs
			var a1 := TAU * (k + 1) / segs
			var p0 := base + Vector3(cos(a0), 0, sin(a0)) * r
			var p1 := base + Vector3(cos(a1), 0, sin(a1)) * r
			tri(key, p0, p1, tip, col, (p0 + p1) / 2.0 - base + Vector3(0, r * 0.5, 0))
			tri(key, p0, p1, base, col, Vector3.DOWN)

	## Ellipsoide (lanterne, planche) : sphere basse definition deformee par `basis`.
	func blob(key: String, c: Vector3, basis: Basis, col: Color, segs: int = 8, rings: int = 5) -> void:
		for j in rings:
			var t0 := PI * j / rings
			var t1 := PI * (j + 1) / rings
			for k in segs:
				var a0 := TAU * k / segs
				var a1 := TAU * (k + 1) / segs
				var p := [Vector3(sin(t0) * cos(a0), cos(t0), sin(t0) * sin(a0)), Vector3(sin(t0) * cos(a1), cos(t0), sin(t0) * sin(a1)),
					Vector3(sin(t1) * cos(a1), cos(t1), sin(t1) * sin(a1)), Vector3(sin(t1) * cos(a0), cos(t1), sin(t1) * sin(a0))]
				var mid := ((p[0] as Vector3) + (p[2] as Vector3)) / 2.0
				quad(key, c + basis * (p[0] as Vector3), c + basis * (p[1] as Vector3), c + basis * (p[2] as Vector3),
					c + basis * (p[3] as Vector3), col, [], basis * mid)

	func is_empty() -> bool:
		return _st.is_empty()

	func commit(materials: Dictionary) -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for key: String in _st:
			var st: SurfaceTool = _st[key]
			st.generate_normals()
			st.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, materials[key])
		return mesh
