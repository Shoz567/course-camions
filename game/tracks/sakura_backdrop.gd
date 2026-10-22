@tool
class_name SakuraBackdrop
extends Node3D

## Decor de Sakura (Japon au printemps, 2026-10-19) autour de la piste
## parente :
##   - cerisiers en fleur : avenue le long de la ligne droite de depart,
##     rangees en bord de piste, bosquets dans les boucles du 8, quelques pins ;
##   - rangees de machiya (maisons de ville en bois et enduit) a l'exterieur
##     des virages, face a la piste ;
##   - monuments : donjon de chateau sur murs de pierre au centre de
##     l'epingle, pagode a cinq etages au centre de la grande courbe, pavillon
##     de temple ;
##   - lanternes de pierre en bord de piste, guirlandes de lanternes de papier
##     rouges sur l'avenue ;
##   - a l'horizon, le mont Fuji enneige et une chaine de montagnes.
## Purement visuel : aucune collision. Rien ne touche la chaussee ni les murs
## de pierre des portions hautes, rien sous le pont (les deux branches du 8
## sont evitees), rien sur les tribunes. Placement deterministe (generateur a
## graine fixe, CLAUDE.md §7). Lots fusionnes par case de 320 m (un appel de
## rendu par materiau et par case, coupes hors champ) ; arbres en MultiMesh
## 3D pres de la camera, en sprites tournes au loin (FarLod, 2026-10-22).
## En headless (tests), rien n'est genere, sauf si un test le force.

@export var decor_seed: int = 7
## Arbres au total : les bosquets completent les rangees de bord de piste
## jusqu'a ce nombre. Au loin ce ne sont plus que des sprites (FarLod) : 1700
## au lieu de 760, pour moins de triangles qu'avant.
@export var tree_target: int = 1700
## Qualite extreme : arbres en plus (part de tree_target).
const EXTREME_TREES := 1.35

## Un test peut forcer la generation en headless.
static var generate_in_headless: bool = false

const CHUNK := 320.0
const CELL := 40.0
const VISIBILITY_END := 1500.0
const BLOSSOMS: Array[Color] = [Color(1.0, 0.6, 0.76), Color(0.96, 0.52, 0.7), Color(1.0, 0.7, 0.83),
	Color(0.92, 0.46, 0.66), Color(1.0, 0.82, 0.88), Color(0.98, 0.58, 0.74)]
const PINE := Color(0.16, 0.32, 0.16)

var _state: int = 1
var _track: TrackBlockout
## Echantillons de piste (un sur deux) et leur marge en plus (talus de pierre
## sous les portions hautes), indexes par case de CELL m.
var _pts: PackedVector3Array = []
var _extra: PackedFloat32Array = []
var _s: PackedFloat32Array = []
var _grid: Dictionary = {}
## Emprises deja prises (x, z, rayon) : batiments, monuments.
var _taken: Array[Vector3] = []
var _kits: Dictionary = {}
var _trees: Array[Transform3D] = []
var _crowns: Array[Transform3D] = []
var _crown_colors := PackedColorArray()
var _chochin: Array[Transform3D] = []


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


# --- reperes ---------------------------------------------------------------------

func _index(track: TrackBlockout) -> void:
	_track = track
	_pts.clear()
	_extra.clear()
	_s.clear()
	_grid.clear()
	var n := track.sample_count()
	for i in range(0, n, 2):
		var p := track.sample_position(i)
		_pts.append(p)
		# portion haute sans pont : le mur de pierre descend en talus
		var h := p.y + track.wall_height
		_extra.append((h * 1.25 + 4.0) if h > track.wall_height + 1.0 and not track.is_bridge_deck(i) else 0.0)
		_s.append(track.sample_s(i))
		var key := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
		# Array (reference) : un PackedInt32Array sorti du dictionnaire est une
		# copie, l'ajout s'y perdrait
		if not _grid.has(key):
			_grid[key] = []
		(_grid[key] as Array).append(_pts.size() - 1)


## Vrai si `c` (au sol) est a plus de `margin` (+ le talus) de toute portion
## de piste, et hors des emprises prises.
func _clear(c: Vector3, margin: float, radius: float = 0.0) -> bool:
	var reach := margin + 40.0
	var k0 := Vector2i(floori((c.x - reach) / CELL), floori((c.z - reach) / CELL))
	var k1 := Vector2i(floori((c.x + reach) / CELL), floori((c.z + reach) / CELL))
	for kx in range(k0.x, k1.x + 1):
		for kz in range(k0.y, k1.y + 1):
			var key := Vector2i(kx, kz)
			if not _grid.has(key):
				continue
			for j: int in _grid[key]:
				var p := _pts[j]
				if Vector2(p.x - c.x, p.z - c.z).length() < margin + _extra[j]:
					return false
	for t in _taken:
		if Vector2(t.x - c.x, t.y - c.z).length() < t.z + radius:
			return false
	return true


## Distance horizontale a la piste (approchee : echantillons un sur deux).
func _track_distance(c: Vector3) -> float:
	var best := INF
	for p in _pts:
		best = minf(best, Vector2(p.x - c.x, p.z - c.z).length())
	return best


## Tribunes de part et d'autre de la ligne de depart (RaceDecor).
func _in_stands(s: float) -> bool:
	return s < 130.0 or s > _track.length() - 120.0


func _kit(at: Vector3) -> JapanKit:
	var key := Vector2i(floori(at.x / CHUNK), floori(at.z / CHUNK))
	if not _kits.has(key):
		var kit := JapanKit.new()
		kit.detail = GraphicsSettings.extreme_assets()
		_kits[key] = kit
	return _kits[key]


# --- generation ------------------------------------------------------------------

func _generate(track: TrackBlockout) -> void:
	_state = maxi(decor_seed, 1)
	_index(track)
	_taken.clear()
	_kits.clear()
	_trees.clear()
	_crowns.clear()
	_crown_colors.clear()
	_chochin.clear()
	var root := Node3D.new()
	root.name = "Sakura"
	add_child(root)
	var landmarks := _landmarks(track)
	var houses := _houses(track)
	_lanterns(track)
	_roadside_trees(track)
	_groves(track)
	var mats := _materials(track)
	var k := 0
	for key: Vector2i in _kits:
		var kit: JapanKit = _kits[key]
		if kit.is_empty():
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Buildings%d" % k
		mi.mesh = kit.commit(mats)
		mi.visibility_range_end = VISIBILITY_END
		mi.visibility_range_end_margin = 120.0
		root.add_child(mi)
		k += 1
	_add_trees(root)
	_add_chochin(root, track)
	root.add_child(_mountains(track))
	# donnees gardees pour les tests (le rendu factice du headless ne relit pas
	# les MultiMesh)
	root.set_meta(&"trees", _trees.duplicate())
	root.set_meta(&"houses", houses)
	root.set_meta(&"landmarks", landmarks)
	# rien sur un raccourci (2026-10-20)
	track.clear_branch_corridors(self)


## Monuments au centre des virages : donjon (epingle), pagode (grande
## courbe), temple (virage du sanctuaire). Un monument n'est pose que si sa
## place est libre.
func _landmarks(track: TrackBlockout) -> Dictionary:
	var out := {}
	var spec := [["castle", "Epingle du chateau", 123.0, 30.0], ["pagoda", "Grande courbe des cerisiers", 145.0, 16.0],
		["temple", "Virage du sanctuaire", 168.0, 26.0], ["pagoda_small", "Courbe de la pagode", 158.0, 12.0]]
	for sp: Array in spec:
		var s0 := track.segment_start_s(sp[1])
		if s0 < 0.0:
			continue
		var seg := _segment(track, sp[1])
		var L := float(seg["radius"]) * deg_to_rad(absf(float(seg["angle"])))
		var i := track.index_at_s(s0 + L / 2.0)
		var p := track.sample_position(i)
		var t := (track.sample_forward(i) * Vector3(1, 0, 1)).normalized()
		var r := t.cross(Vector3.UP).normalized()
		var inward := -r if float(seg["angle"]) > 0.0 else r
		var c := p + inward * float(sp[2])
		c.y = TrackBlockout.GROUND_Y
		var radius: float = sp[3]
		if not _clear(c, track.width / 2.0 + radius + 8.0, radius):
			continue
		# facade vers le point de la piste le plus proche
		var face := Basis.looking_at((p - c) * Vector3(1, 0, 1), Vector3.UP)
		var xf := Transform3D(face, c)
		match sp[0]:
			"castle": _kit(c).castle(xf)
			"pagoda": _kit(c).pagoda(xf, 5, 11.0)
			"pagoda_small": _kit(c).pagoda(xf, 3, 8.0)
			"temple": _kit(c).temple(xf, 30.0, 20.0)
		_taken.append(Vector3(c.x, c.z, radius))
		out[sp[0]] = c
	return out


func _segment(track: TrackBlockout, seg_name: String) -> Dictionary:
	for seg: Dictionary in track.segments:
		if String(seg.get("name", "")) == seg_name:
			return seg
	return {}


## Rangees de machiya a l'exterieur des virages et le long des droites
## basses, facade vers la piste.
func _houses(track: TrackBlockout) -> Array:
	var out := []
	var half := track.width / 2.0
	var beyond := half + track.wall_thickness + track.wall_lean
	var length := track.length()
	var s := 60.0
	while s < length:
		var i := track.index_at_s(s)
		var p := track.sample_position(i)
		var t := (track.sample_forward(i) * Vector3(1, 0, 1)).normalized()
		var r := t.cross(Vector3.UP).normalized()
		var curv := track.curvature(i)
		for side: float in [-1.0, 1.0]:
			# exterieur du virage seulement (une droite : des deux cotes)
			if absf(curv) > 1e-4 and signf(curv) == -side:
				continue
			if _rand() > 0.55 or _in_stands(s):
				continue
			var lat := beyond + _range(26.0, 34.0)
			var count := 3 + int(_rand() * 3.0)
			var along := -float(count) * 6.0
			var z := r * side
			var x := Vector3.UP.cross(z).normalized()
			for h in count:
				var w := _range(8.5, 12.0)
				var d := _range(10.0, 13.0)
				var c := p + z * lat + t * (along + w / 2.0)
				c.y = TrackBlockout.GROUND_Y
				along += w + _range(0.6, 2.0)
				if not _clear(c, beyond + d / 2.0 + 8.0, maxf(w, d) / 2.0):
					continue
				_kit(c).machiya(Transform3D(Basis(x, Vector3.UP, z), c), w, d, _rand())
				_taken.append(Vector3(c.x, c.z, maxf(w, d) * 0.6))
				out.append(c)
		s += 46.0
	return out


## Lanternes de pierre le long des droites basses, au pied du mur.
func _lanterns(track: TrackBlockout) -> void:
	var beyond := track.width / 2.0 + track.wall_thickness + track.wall_lean
	var length := track.length()
	var s := 12.0
	while s < length:
		var i := track.index_at_s(s)
		var p := track.sample_position(i)
		if absf(track.curvature(i)) < 1e-4 and p.y < 1.5 and not track.is_bridge_deck(i) and not _in_stands(s):
			var t := (track.sample_forward(i) * Vector3(1, 0, 1)).normalized()
			var r := t.cross(Vector3.UP).normalized()
			for side: float in [-1.0, 1.0]:
				var c := p + r * side * (beyond + 2.6)
				c.y = TrackBlockout.GROUND_Y
				if _clear(c, beyond + 1.5, 1.0):
					_kit(c).stone_lantern(Transform3D(Basis(Vector3.UP, _rand() * 0.3), c))
					_taken.append(Vector3(c.x, c.z, 1.2))
		s += 24.0


## Cerisiers en bord de piste : rangee pres du mur (au pied du talus si la
## route est haute), puis d'autres plus loin. Avenue dense le long de la
## droite de depart.
func _roadside_trees(track: TrackBlockout) -> void:
	var beyond := track.width / 2.0 + track.wall_thickness + track.wall_lean
	var length := track.length()
	var avenue_end := track.segment_start_s("Virage du sanctuaire")
	var s := 0.0
	while s < length:
		var i := track.index_at_s(s)
		var p := track.sample_position(i)
		var t := (track.sample_forward(i) * Vector3(1, 0, 1)).normalized()
		var r := t.cross(Vector3.UP).normalized()
		var avenue := s < avenue_end
		var stands := _in_stands(s)
		for side: float in [-1.0, 1.0]:
			# portion haute sans pont : les rangees passent au pied du talus
			# (sinon un pre vide le long des rampes du pont), et la plaine
			# qu'on domine de la-haut se remplit de bosquets plus loin
			var foot := track.embankment_reach(i, side)
			var high := foot > 0.0
			for row in 4:
				var lat := beyond
				var chance := 0.0
				match row:
					0:
						lat += foot + _range(6.0, 9.0)
						chance = 0.0 if (stands or track.is_bridge_deck(i)) else (0.95 if avenue else 0.85)
					1:
						lat += foot + _range(15.0, 24.0) + (40.0 if stands else 0.0)
						chance = 0.8 if avenue else 0.62
					2:
						lat += foot + _range(36.0, 80.0) + (30.0 if stands else 0.0)
						chance = 0.7 if high else 0.35
					3:
						lat += foot + _range(80.0, 150.0)
						chance = 0.6 if high else 0.0
				if _rand() > chance:
					continue
				var c := p + r * side * lat + t * _range(-4.0, 4.0)
				c.y = TrackBlockout.GROUND_Y
				if _clear(c, beyond + 4.0, 3.0):
					_add_tree(c, _rand() < 0.08 and not avenue)
		s += 11.0


## Bosquets : dans les boucles du 8 et autour, la ou il reste de la place.
func _groves(track: TrackBlockout) -> void:
	var beyond := track.width / 2.0 + track.wall_thickness + track.wall_lean
	var lo := Vector3(INF, 0, INF)
	var hi := Vector3(-INF, 0, -INF)
	for p in _pts:
		lo = lo.min(p)
		hi = hi.max(p)
	lo -= Vector3(220, 0, 220)
	hi += Vector3(220, 0, 220)
	var tries := 0
	# qualite extreme : un tiers d'arbres en plus (detailles, TreeKit)
	var target := roundi(tree_target * (EXTREME_TREES if GraphicsSettings.extreme_assets() else 1.0))
	while _trees.size() < target and tries < 9000:
		tries += 1
		var c := Vector3(_range(lo.x, hi.x), TrackBlockout.GROUND_Y, _range(lo.z, hi.z))
		if not _clear(c, beyond + 10.0, 3.5):
			continue
		if _track_distance(c) > 260.0:
			continue
		# par touffes : quelques voisins autour
		var n := 1 + int(_rand() * 4.0)
		for k in n:
			var q := c + Vector3(_range(-9.0, 9.0), 0.0, _range(-9.0, 9.0))
			if _clear(q, beyond + 10.0, 3.0):
				_add_tree(q, _rand() < 0.2)


func _add_tree(at: Vector3, pine: bool) -> void:
	var h := _range(4.0, 6.5)
	var b := Basis(Vector3.UP, _rand() * TAU)
	_trees.append(Transform3D(b.scaled(Vector3(h * 0.1, h, h * 0.1)), at))
	var cs := h * _range(0.95, 1.25) * (0.8 if pine else 1.0)
	var crown := Basis(Vector3.UP, _rand() * TAU).scaled(Vector3(cs, cs * (0.55 if pine else 0.75), cs))
	_crowns.append(Transform3D(crown, at + Vector3(0, h * 0.92, 0)))
	_crown_colors.append(PINE if pine else BLOSSOMS[int(_rand() * BLOSSOMS.size()) % BLOSSOMS.size()])
	_taken.append(Vector3(at.x, at.z, 2.5))


## Arbres : 3D pres de la camera, sprites tournes au loin (FarLod).
func _add_trees(root: Node3D) -> void:
	var trunk := _trunk_mesh()
	var crown := _crown_mesh()
	var blossom := ShaderMaterial.new()
	blossom.shader = preload("res://tracks/materials/sakura_blossom.gdshader")
	crown.surface_set_material(0, blossom)
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.2, 0.13, 0.1)
	bark.roughness = 0.95
	trunk.surface_set_material(0, bark)
	var bases := PackedVector3Array()
	var scales := PackedFloat32Array()
	for xf in _trees:
		bases.append(xf.origin)
		scales.append(xf.basis.y.length() / float(FarLod.KINDS["cherry"]["ref"]))
	if GraphicsSettings.extreme_assets():
		# qualite extreme : l'arbre detaille entier (tronc, branches, grappes
		# de fleurs), a l'echelle de son tronc, aussi large que sa couronne
		var xfs: Array[Transform3D] = []
		for k in _trees.size():
			var h := _trees[k].basis.y.length()
			var spread := _crowns[k].basis.x.length() / (h * 1.1)
			xfs.append(Transform3D(_trees[k].basis.orthonormalized() * Basis.from_scale(Vector3(spread, 1.0, spread) * h),
				_trees[k].origin))
		FarLod.add(root, "Trees", [{"name": "Crowns", "mesh": TreeKit.cherry(bark, TreeKit.blossom_material()), "xfs": xfs,
			"colors": _crown_colors}], "cherry_hd", bases, scales, _crown_colors)
		return
	FarLod.add(root, "Trees", [
		{"name": "Trunks", "mesh": trunk, "xfs": _trees},
		{"name": "Crowns", "mesh": crown, "xfs": _crowns, "colors": _crown_colors}], "cherry", bases, scales, _crown_colors)


## Guirlandes de lanternes de papier rouges sur l'avenue de depart : un mat
## tous les 16 m de chaque cote, potence, deux lanternes.
func _add_chochin(root: Node3D, track: TrackBlockout) -> void:
	var beyond := track.width / 2.0 + track.wall_thickness + track.wall_lean
	var s := 140.0
	var end := track.segment_start_s("Virage du sanctuaire") - 20.0
	var poles := JapanKit.new()
	while s < end:
		var i := track.index_at_s(s)
		var p := track.sample_position(i)
		var t := (track.sample_forward(i) * Vector3(1, 0, 1)).normalized()
		var r := t.cross(Vector3.UP).normalized()
		for side: float in [-1.0, 1.0]:
			var c := p + r * side * (beyond + 1.4)
			c.y = TrackBlockout.GROUND_Y
			if _track.other_section_distance(c, track.sample_s(i)) < track.width:
				continue
			var xf := Transform3D(Basis(t, Vector3.UP, r * side), c)
			poles.box(JapanKit.Mat.WOOD, xf, Vector3(0.35, 7.5, 0.35), Color.WHITE)
			poles.box(JapanKit.Mat.WOOD, xf * Transform3D(Basis.IDENTITY, Vector3(0, 7.2, -1.6)), Vector3(0.2, 0.25, 3.6), Color.WHITE)
			for k in 2:
				_chochin.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.5, 0.7, 0.5)),
					xf * Vector3(0.0, 6.1 - k * 1.5, -2.4 - k * 0.6)))
		s += 16.0
	if not poles.is_empty():
		var mi := MeshInstance3D.new()
		mi.name = "ChochinPoles"
		mi.mesh = poles.commit({JapanKit.Mat.WOOD: _wood()})
		root.add_child(mi)
	if _chochin.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	sphere.material = track.theme.lantern
	mm.mesh = sphere
	mm.instance_count = _chochin.size()
	for k in _chochin.size():
		mm.set_instance_transform(k, _chochin[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Chochin"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)


## Le mont Fuji au loin, droit devant la ligne de depart, et une chaine de
## montagnes tout autour (bleuies par la perspective aerienne).
func _mountains(track: TrackBlockout) -> MeshInstance3D:
	var c := Vector3.ZERO
	for p in _pts:
		c += p
	c /= _pts.size()
	c.y = 0.0
	return build_mountains(c, (track.sample_forward(0) * Vector3(1, 0, 1)).normalized())


## Fuji a 3,3 km de `c` dans la direction `fwd`, chaine de montagnes autour
## de `c` (aussi le decor du menu, Showroom).
static func build_mountains(c: Vector3, fwd: Vector3) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Fuji : cone a flancs concaves, sommet tronque, neige aux bords dentes
	var fuji := c + fwd * 3300.0
	var R := 1600.0
	var H := 640.0
	var segs := 72
	var rings := 14
	for k in segs:
		for j in rings:
			var a0 := TAU * k / segs
			var a1 := TAU * (k + 1) / segs
			var quad: Array[Vector3] = []
			var cols: Array[Color] = []
			for corner: Array in [[a1, j], [a0, j], [a0, j + 1], [a1, j + 1]]:
				var u := float(corner[1]) / rings
				var rr := R * (1.0 - u * 0.93)
				var y := H * pow(u, 1.9)
				var jag := 0.06 * sin(float(corner[0]) * 9.0) + 0.04 * sin(float(corner[0]) * 23.0)
				var snow := smoothstep(0.6 + jag, 0.66 + jag, u)
				cols.append(Color(0.33, 0.4, 0.46).lerp(Color(0.97, 0.97, 1.0), snow))
				quad.append(fuji + Vector3(cos(float(corner[0])) * rr, y - 20.0, sin(float(corner[0])) * rr))
			_quad(st, quad, cols)
	# chaine de montagnes, sauf devant le Fuji
	var fuji_az := atan2(fwd.z, fwd.x)
	var n := 160
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		var pts: Array[Vector3] = []
		var cols: Array[Color] = []
		for a: float in [a0, a1]:
			var gap := absf(wrapf(a - fuji_az, -PI, PI))
			var h := (160.0 + 120.0 * sin(a * 5.0 + 1.3) + 70.0 * sin(a * 13.0 + 0.4) + 40.0 * sin(a * 29.0)) \
					* smoothstep(0.18, 0.45, gap)
			var r := 2300.0 + 220.0 * sin(a * 3.0 + 2.0)
			pts.append(c + Vector3(cos(a) * (r - 500.0), -10.0, sin(a) * (r - 500.0)))
			pts.append(c + Vector3(cos(a) * r, maxf(h, 0.0), sin(a) * r))
			pts.append(c + Vector3(cos(a) * (r + 600.0), -10.0, sin(a) * (r + 600.0)))
			cols.append_array([Color(0.3, 0.42, 0.32), Color(0.42, 0.5, 0.58), Color(0.42, 0.5, 0.58)])
		_quad(st, [pts[0], pts[3], pts[4], pts[1]], [cols[0], cols[3], cols[4], cols[1]])
		_quad(st, [pts[1], pts[4], pts[5], pts[2]], [cols[1], cols[4], cols[5], cols[2]])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Mountains"
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta(&"fuji", fuji)
	return mi


static func _quad(st: SurfaceTool, p: Array, c: Array) -> void:
	for k: int in [0, 2, 1, 0, 3, 2]:
		st.set_color(c[k])
		st.add_vertex(p[k])


# --- maillages et materiaux ------------------------------------------------------

func _materials(track: TrackBlockout) -> Dictionary:
	var house := ShaderMaterial.new()
	house.shader = preload("res://tracks/materials/sakura_house.gdshader")
	var roof := ShaderMaterial.new()
	roof.shader = preload("res://tracks/materials/sakura_roof.gdshader")
	var stone := ShaderMaterial.new()
	stone.shader = preload("res://tracks/materials/sakura_stone.gdshader")
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.95, 0.72, 0.25)
	gold.metallic = 1.0
	gold.roughness = 0.25
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(1.0, 0.92, 0.75)
	paper.emission_enabled = true
	paper.emission = Color(1.0, 0.75, 0.4)
	paper.emission_energy_multiplier = 1.4
	# tissu des noren (details de la qualite extreme) : couleur de sommet
	var cloth := StandardMaterial3D.new()
	cloth.vertex_color_use_as_albedo = true
	cloth.roughness = 0.9
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	return {JapanKit.Mat.PLASTER: house, JapanKit.Mat.WOOD: _wood(), JapanKit.Mat.LACQUER: track.theme.arch_tubes[0],
		JapanKit.Mat.ROOF: roof, JapanKit.Mat.STONE: stone, JapanKit.Mat.GOLD: gold, JapanKit.Mat.PAPER: paper,
		JapanKit.Mat.CLOTH: cloth}


static func _wood() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.12, 0.07)
	m.roughness = 0.85
	return m


## Tronc de cerisier : fut penche et tordu, trois branches maitresses (haut
## de 1, rayon ~1 : mis a l'echelle).
static func _trunk_mesh() -> ArrayMesh:
	var kit := JapanKit.new()
	var seg := Transform3D.IDENTITY
	kit.cylinder(JapanKit.Mat.WOOD, seg, 1.0, 0.75, 0.55, 7, Color.WHITE, false)
	var lean := Transform3D(Basis(Vector3.FORWARD, 0.18), Vector3(0, 0.55, 0))
	kit.cylinder(JapanKit.Mat.WOOD, lean, 0.75, 0.55, 0.35, 7, Color.WHITE, false)
	for k in 3:
		var a := TAU * k / 3.0 + 0.4
		var b := Basis(Vector3.UP, a) * Basis(Vector3.FORWARD, 0.75)
		kit.cylinder(JapanKit.Mat.WOOD, Transform3D(b, Vector3(0.06, 0.82, 0)), 0.5, 0.2, 0.32, 6, Color.WHITE)
	var mesh := kit.commit({JapanKit.Mat.WOOD: _wood()})
	return mesh


## Couronne : sept boules aplaties qui se chevauchent (rayon ~1 : mise a
## l'echelle), le dessous plus plat.
static func _crown_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 0.85
	sphere.radial_segments = 8
	sphere.rings = 4
	var blobs := [Vector3(0, 0.18, 0), Vector3(0.55, 0.0, 0.1), Vector3(-0.5, 0.05, 0.25), Vector3(0.1, 0.05, -0.55),
		Vector3(-0.2, 0.0, 0.55), Vector3(-0.1, 0.38, -0.2)]
	var sizes := [1.2, 0.85, 0.9, 0.85, 0.8, 0.75]
	for k in blobs.size():
		var sz: float = sizes[k]
		st.append_from(sphere, 0, Transform3D(Basis.IDENTITY.scaled(Vector3(sz, sz, sz)), blobs[k]))
	return st.commit()
