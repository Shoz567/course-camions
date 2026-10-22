class_name RoadDecor
extends RefCounted

## Decor SUR la route (2026-10-22 : « add des decors sur la route, comme des
## fences, des objets qui montent et descendent, des panneaux ; on a trouve
## que les routes faisaient trop vides »), pose par RoadsideDressing, dans le
## style du circuit. Rien qui change la conduite : aucune collision, rien a
## hauteur de camion.
##   - vibreurs (kerbs) a la corde des virages, au ras de la chaussee ;
##   - panneaux a chevrons sur le mur exterieur des virages serres (a la
##     place des panneaux de sponsors) ;
##   - fleches peintes dans chaque voie : droites sur les lignes droites,
##     coudees vers le virage avant chaque virage serre ; passages pietons en
##     travers ; nom du circuit peint en grand ;
##   - Cyber City : plots lumineux sur les lignes de voie ;
##   - au-dessus, a SKY_MIN m au moins de la chaussee, des objets qui montent
##     et descendent : drones a enseigne neon (Cyber City), mouettes qui
##     planent en cercle (Playa), lanternes flottantes (Sakura). Un MultiMesh,
##     anime dans le shader (float_decor.gdshader).
## Au sol : lots plats sans ombre de RoadsideDressing (une case, un appel de
## rendu par materiau).

## Virage : rayon sous lequel on pose des vibreurs, des chevrons (m).
const KERB_RADIUS := 230.0
const CHEVRON_RADIUS := 150.0
const KERB_WIDTH := 1.9
## Hauteur libre minimale sous un objet volant, au-dessus du bord le plus haut
## de la chaussee (m) ; un camion fait 4,5 m.
const SKY_MIN := 9.0

var d: RoadsideDressing
var track: TrackBlockout
var style: int = 0
var half: float = 0.0
## Zones de chevrons : [s0, s1, cote].
var chevron_zones: Array[Vector3] = []
## Pour les tests et la mesure : pieds des vibreurs, fleches, objets volants.
var kerbs: PackedVector3Array = PackedVector3Array()
var arrows: PackedVector3Array = PackedVector3Array()
var flyers: PackedVector3Array = PackedVector3Array()
## Ecart entre l'origine d'un objet volant et son point le plus bas, au creux
## de sa descente (m) : enseigne du drone, gland de la lanterne.
var flyer_drop: float = 0.0
var chevrons: int = 0

var _avoid: PackedFloat32Array = PackedFloat32Array()
var _jumps: Array[Vector2] = []


func _init(dressing: RoadsideDressing) -> void:
	d = dressing
	track = dressing._track
	style = dressing._style
	half = track.width / 2.0
	# plaques, flaques, bonus, tremplins : rien de peint dessus
	for k in track.boost_pad_count():
		_avoid.append(track.sample_s(track.closest_sample(track.boost_pad_transform(k).origin)))
	for k in track.puddle_count():
		_avoid.append(track.sample_s(track.closest_sample(track.puddle_transform(k).origin)))
	for k in track.pickup_count():
		var pk := track.pickup_node(k)
		if pk != null:
			_avoid.append(track.sample_s(track.closest_sample(pk.global_position if pk.is_inside_tree() else pk.position)))
	for k in track.jump_pad_count():
		var js := track.sample_s(track.closest_sample(track.jump_pad_transform(k).origin))
		_avoid.append(js)
		# en l'air apres un tremplin : rien au-dessus
		_jumps.append(Vector2(js - 30.0, js + 170.0))


## Virage a l'abscisse s : changement de cap par metre (rad/m), positif a
## gauche (mesure sur 24 m).
func turn(s: float) -> float:
	var a := (track.sample_forward(track.index_at_s(s - 12.0)) * Vector3(1, 0, 1)).normalized()
	var b := (track.sample_forward(track.index_at_s(s + 12.0)) * Vector3(1, 0, 1)).normalized()
	return atan2(a.cross(b).y, a.dot(b)) / 24.0


func _near_avoid(s: float, margin: float) -> bool:
	for a in _avoid:
		if d._circ(s, a) < margin:
			return true
	return false


## Point de la chaussee a l'abscisse s, `lateral` m a droite, `lift` au-dessus
## (suit le devers).
func road_point(s: float, lateral: float, lift: float) -> Vector3:
	return track.frame_at(track.index_at_s(s), lateral, lift).origin


## Les zones de chevrons d'abord : les panneaux de sponsors les evitent.
func plan(L: float) -> void:
	var s := 0.0
	var z := Vector3(-1, -1, 0)
	while s < L:
		var tr := turn(s)
		var tight := absf(tr) > 1.0 / CHEVRON_RADIUS
		# exterieur du virage : a droite quand on tourne a gauche
		var side := 1.0 if tr > 0.0 else -1.0
		if tight and z.x < 0.0:
			z = Vector3(s, s, side)
		elif tight and side == z.z:
			z.y = s
		else:
			if z.x >= 0.0 and z.y - z.x > 20.0:
				chevron_zones.append(z)
			z = Vector3(-1, -1, 0)
			if tight:
				z = Vector3(s, s, side)
		s += 4.0
	if z.x >= 0.0 and z.y - z.x > 20.0:
		chevron_zones.append(z)


func in_chevron_zone(s0: float, s1: float, side: float) -> bool:
	for z in chevron_zones:
		if z.z == side and s1 > z.x - 6.0 and s0 < z.y + 6.0:
			return true
	return false


func build(L: float) -> void:
	_kerbs(L)
	_chevrons()
	_lane_arrows(L)
	_turn_arrows()
	_crosswalks(L)
	_road_names(L)
	if style == TrackTheme.Id.CYBER_CITY:
		_studs(L)
	_flyers(L)


# --- vibreurs -----------------------------------------------------------------

func _kerb_colors() -> Array[Color]:
	match style:
		TrackTheme.Id.PLAYA_DEL_SOL:
			return [Color(0.92, 0.16, 0.12), Color(0.97, 0.96, 0.92)]
		TrackTheme.Id.SAKURA:
			return [RoadsideDressing.LACQUER, Color(0.97, 0.94, 0.88)]
	return [Color(1.0, 0.12, 0.6), Color(0.88, 0.9, 0.98)]


## Bande de 1,9 m au bord interieur du virage, bombee (10 cm cote mur), en
## segments alternes de 2,4 m.
func _kerbs(L: float) -> void:
	var cols := _kerb_colors()
	var step := 1.2
	var s := 0.0
	while s < L:
		var tr := turn(s)
		if absf(tr) > 1.0 / KERB_RADIUS:
			var side := -1.0 if tr > 0.0 else 1.0
			var i := track.index_at_s(s)
			if not d._wall_open(i, side) and not track.is_bridge_deck(i):
				var col: Color = cols[int(s / 2.4) % 2]
				var lat_out := side * (half - 0.05)
				var lat_in := side * (half - KERB_WIDTH)
				var a0 := road_point(s, lat_out, 0.1)
				var a1 := road_point(s, lat_in, 0.035)
				var b0 := road_point(s + step, lat_out, 0.1)
				var b1 := road_point(s + step, lat_in, 0.035)
				var up := track.sample_up(i)
				var batch := d._flat_batch(a0)
				batch.quad("solid", a0, b0, b1, a1, col, [], up)
				# petite face cote route
				batch.quad("solid", a1, b1, b1 - up * 0.05, a1 - up * 0.05, col.darkened(0.25), [], -track.sample_right(i) * side)
				if int(s / step) % 6 == 0:
					kerbs.append(a1)
		s += step


# --- chevrons -----------------------------------------------------------------

func _chevrons() -> void:
	for z in chevron_zones:
		var s := z.x
		while s + 6.0 <= z.y + 4.0:
			var i0 := track.index_at_s(s)
			var i1 := track.index_at_s(s + 6.0)
			if not d._wall_open(i0, z.z) and not d._wall_open(i1, z.z):
				d._board_strip(s, 6.0, z.z, "chevron", _chevron_color())
				chevrons += 1
			s += 7.0


func _chevron_color() -> Color:
	match style:
		TrackTheme.Id.PLAYA_DEL_SOL:
			return Color(0.9, 0.14, 0.1)
		TrackTheme.Id.SAKURA:
			return Color(0.72, 0.12, 0.06)
	return Color(0.03, 0.03, 0.05)


# --- marquages ----------------------------------------------------------------

func _paint() -> Array:
	if style == TrackTheme.Id.CYBER_CITY:
		return ["glow", Color(0.15, 0.95, 1.0, 0.55)]
	return ["solid", Color(0.93, 0.93, 0.9)]


## Fleche dans chaque voie (4 voies), sur les lignes droites, tous les ~140 m.
func _lane_arrows(L: float) -> void:
	var key: String = _paint()[0]
	var col: Color = _paint()[1]
	var s := 160.0
	while s < L - 160.0:
		var straight := absf(turn(s)) < 1.0 / 350.0 and absf(turn(s + 8.0)) < 1.0 / 350.0
		if straight and not _near_avoid(s, 22.0) and not d._in_stands(s) \
				and track.other_section_distance(track.sample_position(track.index_at_s(s)), s) > track.width:
			for lane in 4:
				var lc := -half + track.width * (lane + 0.5) / 4.0
				if not d._clear_box(road_point(s + 4.0, lc, 1.0), Vector3(2, 1, 5)):
					continue
				_arrow(s, lc, key, col)
				arrows.append(road_point(s, lc, 0.0))
		s += 140.0 * d._dense()


## Avant chaque virage serre, dans chaque voie : une fleche coudee vers
## l'interieur du virage, 30 m avant son entree.
func _turn_arrows() -> void:
	var key: String = _paint()[0]
	var col: Color = _paint()[1]
	for z in chevron_zones:
		var s := z.x - 32.0
		if s < 60.0 or _near_avoid(s, 18.0) or d._in_stands(s) \
				or track.other_section_distance(track.sample_position(track.index_at_s(s)), s) < track.width:
			continue
		# vers l'interieur : a gauche quand l'exterieur est a droite
		var bend := -z.z
		for lane in 4:
			var lc := -half + track.width * (lane + 0.5) / 4.0
			if not d._clear_box(road_point(s + 4.0, lc, 1.0), Vector3(2, 1, 5)):
				continue
			_bent_arrow(s, lc, bend, key, col)
			arrows.append(road_point(s, lc, 0.0))


## Fleche coudee de 7 m : hampe droite, puis pointe deportee de 1,3 m vers
## `bend` (-1 gauche, 1 droite).
func _bent_arrow(s: float, lc: float, bend: float, key: String, col: Color) -> void:
	var lift := 0.06
	var up := track.sample_up(track.index_at_s(s))
	var batch := d._flat_batch(road_point(s, lc, 0.0))
	var w := 0.32
	batch.quad(key, road_point(s, lc - w, lift), road_point(s, lc + w, lift), road_point(s + 3.0, lc + w, lift),
		road_point(s + 3.0, lc - w, lift), col, [], up)
	var o := bend * 1.3
	batch.quad(key, road_point(s + 3.0, lc - w, lift), road_point(s + 3.0, lc + w, lift),
		road_point(s + 4.8, lc + o * 0.6 + w, lift), road_point(s + 4.8, lc + o * 0.6 - w, lift), col, [], up)
	batch.tri(key, road_point(s + 4.4, lc + o * 0.5 - 1.05, lift), road_point(s + 4.4, lc + o * 0.5 + 1.05, lift),
		road_point(s + 7.0, lc + o, lift), col, up)


## Passages pietons (bandes de 5 m le long de la route, 0,6 m de large, tous
## les 1,2 m) en travers de toute la chaussee, sur deux lignes droites.
func _crosswalks(L: float) -> void:
	var key: String = _paint()[0]
	var col: Color = _paint()[1]
	for target: float in [L * 0.15, L * 0.55]:
		var s := target
		while s < target + 400.0:
			if absf(turn(s)) < 1.0 / 400.0 and absf(turn(s + 6.0)) < 1.0 / 400.0 and not _near_avoid(s, 25.0) \
					and not d._in_stands(s) \
					and track.other_section_distance(track.sample_position(track.index_at_s(s)), s) > track.width \
					and d._clear_box(road_point(s + 2.5, 0.0, 1.0), Vector3(half, 1, 4)):
				var up := track.sample_up(track.index_at_s(s))
				var batch := d._flat_batch(road_point(s, 0.0, 0.0))
				var lat := -half + 2.0
				while lat < half - 2.0:
					batch.quad(key, road_point(s, lat, 0.06), road_point(s, lat + 0.6, 0.06),
						road_point(s + 5.0, lat + 0.6, 0.06), road_point(s + 5.0, lat, 0.06), col, [], up)
					lat += 1.2
				arrows.append(road_point(s, 0.0, 0.0))
				break
			s += 15.0


## Fleche peinte de 7 m : hampe, puis pointe ; suit la chaussee.
func _arrow(s: float, lc: float, key: String, col: Color) -> void:
	var lift := 0.06
	var up := track.sample_up(track.index_at_s(s))
	var batch := d._flat_batch(road_point(s, lc, 0.0))
	var stations := [[0.0, 0.32], [2.4, 0.32], [4.6, 0.32]]
	for q in 2:
		var s0: float = s + float(stations[q][0])
		var s1: float = s + float(stations[q + 1][0])
		var w: float = stations[q][1]
		batch.quad(key, road_point(s0, lc - w, lift), road_point(s0, lc + w, lift), road_point(s1, lc + w, lift),
			road_point(s1, lc - w, lift), col, [], up)
	batch.tri(key, road_point(s + 4.6, lc - 1.05, lift), road_point(s + 4.6, lc + 1.05, lift), road_point(s + 7.2, lc, lift),
		col, up)


## Nom du circuit peint en grand en travers de la route, deux fois par tour.
func _road_names(L: float) -> void:
	var word := "CYBER CITY"
	var col := Color(0.15, 0.95, 1.0)
	match style:
		TrackTheme.Id.PLAYA_DEL_SOL:
			word = "PLAYA DEL SOL"
			col = Color(0.96, 0.95, 0.9)
		TrackTheme.Id.SAKURA:
			word = "桜  SAKURA"
			col = Color(0.97, 0.93, 0.9)
	for target: float in [L * 0.3, L * 0.72]:
		var s := target
		while s < target + 400.0:
			if absf(turn(s)) < 1.0 / 800.0 and absf(turn(s + 20.0)) < 1.0 / 800.0 and not _near_avoid(s, 30.0) \
					and track.other_section_distance(track.sample_position(track.index_at_s(s)), s) > track.width \
					and d._clear_box(road_point(s, 0.0, 1.0), Vector3(half, 1, 6)):
				var f := track.frame_at(track.index_at_s(s), 0.0, 0.07)
				# couche sur la chaussee, lisible en arrivant : haut des lettres
				# vers l'avant
				var basis := Basis(f.basis.x, -f.basis.z, f.basis.y)
				var l := Label3D.new()
				l.text = word
				l.font = TrackTheme.cjk_font()
				l.font_size = 200
				l.pixel_size = 0.03
				l.outline_size = 0
				l.modulate = Color(col.r * 1.4, col.g * 1.4, col.b * 1.4) if style == TrackTheme.Id.CYBER_CITY else Color(col, 0.92)
				l.shaded = style != TrackTheme.Id.CYBER_CITY
				l.double_sided = false
				l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
				l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				l.transform = Transform3D(basis, f.origin)
				l.visibility_range_end = RoadsideDressing.VIEW_END
				# pas plus large que la route
				var w := l.font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size).x * l.pixel_size
				if w > track.width - 10.0:
					l.pixel_size *= (track.width - 10.0) / w
				d._labels.append(l)
				break
			s += 20.0


## Plots lumineux (Cyber City) sur les trois lignes de voie, au milieu des
## espaces entre les tirets (tirets de 9 m tous les 18 m, road.gdshader).
func _studs(L: float) -> void:
	var s := 13.5
	var k := 0
	while s < L:
		if not _near_avoid(s, 10.0):
			for line in range(1, 4):
				var lat := -half + track.width * line / 4.0
				var p := road_point(s, lat, 0.03)
				var f := track.frame_at(track.index_at_s(s), lat, 0.03)
				var col := Color(0.15, 0.95, 1.0, 0.7) if (k + line) % 2 == 0 else Color(1.0, 0.75, 0.2, 0.7)
				d._flat_batch(p).box("glow", Transform3D(f.basis, p), Vector3(0.3, 0.06, 0.18), col)
		s += 18.0
		k += 1


# --- au-dessus : ce qui monte et descend ----------------------------------------

func _flyers(L: float) -> void:
	var xfs: Array[Transform3D] = []
	var custom := PackedColorArray()
	var spans: PackedFloat32Array = PackedFloat32Array()
	for sp: Dictionary in d.spans:
		spans.append(float(sp["s"]))
	var mesh := _flyer_mesh()
	var box := mesh.get_aabb()
	flyer_drop = maxf(0.0, -box.position.y) + _flyer_amp()
	var s := 140.0
	while s < L - 120.0:
		s += (80.0 + d._range(-15.0, 20.0)) * d._dense()
		if d._is_blocked(s) or _in_jump(s):
			continue
		var i := track.index_at_s(s)
		var p := track.sample_position(i)
		if track.other_section_distance(p, s) < track.width + 60.0:
			continue
		var count := 2 + int(d._rand() * 3.0)
		for q in count:
			var sq := s + d._range(-20.0, 20.0)
			# pas sous un cable (les cables sont a 14,5 m)
			var near_span := false
			for ss in spans:
				near_span = near_span or d._circ(sq, ss) < 18.0
			if near_span:
				continue
			var lat := d._range(-half + 8.0, half - 8.0)
			var f: Dictionary = d._frame(sq)
			var top: float = f["top"]
			var h := _flyer_height(box)
			var at := road_point(sq, lat, 0.0)
			at.y = top + h
			if not d._clear_box(at, Vector3(8, 6, 8)):
				continue
			var yaw := d._rand() * TAU
			xfs.append(Transform3D(Basis(Vector3.UP, yaw), at))
			var radius := d._range(6.0, 12.0) if style == TrackTheme.Id.PLAYA_DEL_SOL else (1.0 if d._rand() < 0.5 else 0.0)
			custom.append(Color(d._rand(), _flyer_amp(), d._range(0.45, 0.8), radius))
			flyers.append(at)
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for k in xfs.size():
		mm.set_instance_transform(k, xfs[k])
		mm.set_instance_custom_data(k, custom[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Flyers"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# mouvement dans le shader (cercle, montee) : boite elargie
	mmi.extra_cull_margin = 16.0
	d._extra_nodes.append(mmi)


func _in_jump(s: float) -> bool:
	for j in _jumps:
		if (s >= j.x and s <= j.y) or (s + track.length() >= j.x and s + track.length() <= j.y):
			return true
	return false


## Hauteur de l'origine au-dessus de la chaussee : son point le plus bas (au
## creux de la descente) reste a SKY_MIN m au moins, avec une marge.
func _flyer_height(box: AABB) -> float:
	var lo := SKY_MIN + flyer_drop + 0.6
	return d._range(lo, lo + (8.0 if style == TrackTheme.Id.PLAYA_DEL_SOL else 4.0))


## Montee et descente (m) : la plus basse position reste au-dessus de SKY_MIN.
func _flyer_amp() -> float:
	return 0.9 if style == TrackTheme.Id.PLAYA_DEL_SOL else 0.8


## Maillage de l'objet volant du circuit, en couleurs de sommet (alpha 0 :
## lumineux).
func _flyer_mesh() -> ArrayMesh:
	var b := RoadsideDressing.Batch.new(Vector3.ZERO)
	match style:
		TrackTheme.Id.PLAYA_DEL_SOL:
			_gull(b)
		TrackTheme.Id.SAKURA:
			_sky_lantern(b)
		_:
			_drone(b)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://tracks/materials/float_decor.gdshader")
	match style:
		TrackTheme.Id.PLAYA_DEL_SOL:
			mat.set_shader_parameter("circle", true)
			mat.set_shader_parameter("flap", 0.22)
			mat.set_shader_parameter("glow", 0.0)
		TrackTheme.Id.SAKURA:
			mat.set_shader_parameter("glow", 1.4)
			mat.set_shader_parameter("alt_color", RoadsideDressing.PAPER_RED)
		_:
			mat.set_shader_parameter("spin", 0.25)
			mat.set_shader_parameter("glow", 3.0)
			mat.set_shader_parameter("alt_color", Color(1.0, 0.15, 0.75))
	return b.commit({"solid": mat})


## Drone de livraison : corps sombre, quatre bras et rotors cercles de neon,
## lumiere dessous, enseigne neon suspendue sous lui.
func _drone(b: RoadsideDressing.Batch) -> void:
	var dark := Color(0.08, 0.09, 0.12)
	var cyan := Color(0.1, 0.95, 1.0, 0.0)
	b.box("solid", Transform3D(Basis.IDENTITY, Vector3.ZERO), Vector3(1.3, 0.35, 1.3), dark)
	for k in 4:
		var a := PI / 4.0 + k * PI / 2.0
		var dir := Vector3(cos(a), 0.0, sin(a))
		b.box("solid", Transform3D(Basis(Vector3.UP, -a), dir * 0.95), Vector3(1.0, 0.1, 0.12), dark)
		b.blob("solid", dir * 1.5 + Vector3(0, 0.12, 0), Basis.from_scale(Vector3(0.5, 0.03, 0.5)), cyan, 10, 2)
	b.box("solid", Transform3D(Basis.IDENTITY, Vector3(0, -0.2, 0)), Vector3(0.5, 0.06, 0.5), Color(1.0, 0.15, 0.75, 0.0))
	# enseigne pendue (couleur melangee vers alt_color selon l'instance)
	for x: float in [-0.9, 0.9]:
		b.tube("solid", Vector3(x * 0.5, -0.2, 0), Vector3(x, -1.5, 0), 0.02, 4, dark)
	b.box("solid", Transform3D(Basis.IDENTITY, Vector3(0, -2.1, 0)), Vector3(2.6, 1.2, 0.14), dark)
	b.box("solid", Transform3D(Basis.IDENTITY, Vector3(0, -2.1, 0)), Vector3(2.3, 0.9, 0.2), Color(0.1, 0.95, 1.0, 0.0))


## Mouette : corps, tete, bec, ailes en deux pans (bouts gris), queue ; face
## vers -Z, envergure 2,4 m.
func _gull(b: RoadsideDressing.Batch) -> void:
	var white := Color(0.97, 0.97, 0.96)
	var grey := Color(0.55, 0.58, 0.62)
	b.blob("solid", Vector3.ZERO, Basis.from_scale(Vector3(0.16, 0.15, 0.42)), white, 8, 5)
	b.blob("solid", Vector3(0, 0.08, -0.42), Basis.from_scale(Vector3(0.11, 0.11, 0.13)), white, 8, 4)
	b.tube("solid", Vector3(0, 0.07, -0.53), Vector3(0, 0.05, -0.68), 0.025, 4, Color(1.0, 0.65, 0.1))
	for side: float in [-1.0, 1.0]:
		var root_f := Vector3(side * 0.1, 0.05, -0.15)
		var root_b := Vector3(side * 0.1, 0.05, 0.12)
		var elbow_f := Vector3(side * 0.62, 0.16, -0.1)
		var elbow_b := Vector3(side * 0.62, 0.16, 0.18)
		var tip := Vector3(side * 1.2, 0.02, 0.22)
		b.quad("solid", root_f, elbow_f, elbow_b, root_b, white, [], Vector3.UP, true)
		b.tri("solid", elbow_f, tip, elbow_b, grey, Vector3.UP, true)
	b.tri("solid", Vector3(-0.12, 0.02, 0.35), Vector3(0.12, 0.02, 0.35), Vector3(0, 0.0, 0.62), white, Vector3.UP, true)


## Lanterne de papier flottante : corps lumineux (blanc ou rouge selon
## l'instance), cerclages et chapeau sombres, gland.
func _sky_lantern(b: RoadsideDressing.Batch) -> void:
	var paper := Color(1.0, 0.92, 0.78, 0.0)
	var sumi := RoadsideDressing.SUMI
	b.blob("solid", Vector3.ZERO, Basis.from_scale(Vector3(0.55, 0.75, 0.55)), paper, 12, 7)
	for y: float in [-0.68, 0.68]:
		b.blob("solid", Vector3(0, y, 0), Basis.from_scale(Vector3(0.36, 0.06, 0.36)), sumi, 10, 2)
	b.tube("solid", Vector3(0, 0.72, 0), Vector3(0, 1.0, 0), 0.03, 4, sumi)
	b.tube("solid", Vector3(0, -0.72, 0), Vector3(0, -1.05, 0), 0.04, 4, Color(0.85, 0.15, 0.1))
