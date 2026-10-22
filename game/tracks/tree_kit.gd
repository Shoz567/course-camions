class_name TreeKit
extends RefCounted

## Arbres detailles de la qualite extreme (2026-10-22 : « les pauvres arbres
## de chaque map, detaille-les avec des branches crisp et des feuillages
## individuels, des vrais trucs ») :
##   - palmier : stipe annele (une cicatrice par palme tombee), couronne de
##     palmes pennees - une foliole de chaque cote tous les 3 % de la palme -,
##     palmes seches pendantes, noix de coco vertes ;
##   - cerisier : tronc evase et tordu, branches maitresses, secondaires et
##     rameaux (tubes effiles, alea a graine fixe), au bout des rameaux une
##     grappe : un pompon bossele et des fleurs a cinq petales, chacune sa
##     geometrie.
## Memes reperes que les arbres simples : palmier = tronc de hauteur 1
## (PlayaBackdrop._trunk_mesh) et couronne de rayon 1 posee au sommet ;
## cerisier = arbre entier de hauteur 1 (fleurs comprises), mis a l'echelle
## d'un bloc. Maillages construits une fois (caches) ; materiaux du palmier
## inclus, ceux du cerisier passes par l'appelant (bois, fleurs).

static var _palm_trunk: ArrayMesh
static var _palm_crown: ArrayMesh
static var _cherry: ArrayMesh
static var _seed: int = 1

## Cicatrices de palmes sur le stipe.
const PALM_SCARS := 24
const PALM_FRONDS := 16
const PALM_LEAFLETS := 30


static func _rand() -> float:
	_seed = (_seed * 1103515245 + 12345) & 0x7fffffff
	return float(_seed) / 2147483648.0


static func _range(a: float, b: float) -> float:
	return a + (b - a) * _rand()


# --- primitives -----------------------------------------------------------------

static func _v(st: SurfaceTool, p: Vector3, uv: Vector2, col: Color) -> void:
	st.set_color(col)
	st.set_uv(uv)
	st.add_vertex(p)


## Triangle a, b, c dont la face avant regarde `out` (face avant de Godot :
## sens horaire vue de devant).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, out: Vector3, ua: Vector2, ub: Vector2,
		uc: Vector2, col: Color) -> void:
	if (b - a).cross(c - a).dot(out) > 0.0:
		_v(st, a, ua, col)
		_v(st, c, uc, col)
		_v(st, b, ub, col)
	else:
		_v(st, a, ua, col)
		_v(st, b, ub, col)
		_v(st, c, uc, col)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, out: Vector3, ua: Vector2,
		ub: Vector2, uc: Vector2, ud: Vector2, col: Color) -> void:
	_tri(st, a, b, c, out, ua, ub, uc, col)
	_tri(st, a, c, d, out, ua, uc, ud, col)


## Tube effile le long de `pts` (rayons `radii`), `sides` pans tournes vers
## l'exterieur, bout ferme ; uv.y : longueur parcourue * `v_scale`. Reperes
## transportes le long du tube (pas de torsion).
static func _tube(st: SurfaceTool, pts: PackedVector3Array, radii: PackedFloat32Array, sides: int, col: Color,
		v_scale: float = 1.0) -> void:
	var n := pts.size()
	var rings: Array[PackedVector3Array] = []
	var dirs: Array[PackedVector3Array] = []
	var vs := PackedFloat32Array()
	var side := Vector3.ZERO
	var acc := 0.0
	for k in n:
		if k > 0:
			acc += pts[k].distance_to(pts[k - 1])
		vs.append(acc * v_scale)
		var dir := (pts[mini(k + 1, n - 1)] - pts[maxi(k - 1, 0)]).normalized()
		if side == Vector3.ZERO or absf(side.dot(dir)) > 0.98:
			side = dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
		else:
			side = (side - dir * side.dot(dir)).normalized()
		var up := side.cross(dir).normalized()
		var ring := PackedVector3Array()
		var nd := PackedVector3Array()
		for j in sides:
			var a := TAU * j / sides
			var d := side * cos(a) + up * sin(a)
			ring.append(pts[k] + d * radii[k])
			nd.append(d)
		rings.append(ring)
		dirs.append(nd)
	for k in n - 1:
		for j in sides:
			var j2 := (j + 1) % sides
			var u0 := float(j) / sides
			var u1 := float(j + 1) / sides
			_quad(st, rings[k][j], rings[k][j2], rings[k + 1][j2], rings[k + 1][j], dirs[k][j] + dirs[k][j2],
				Vector2(u0, vs[k]), Vector2(u1, vs[k]), Vector2(u1, vs[k + 1]), Vector2(u0, vs[k + 1]), col)
	var end_dir := (pts[n - 1] - pts[n - 2]).normalized()
	var tip := pts[n - 1] + end_dir * radii[n - 1] * 0.6
	for j in sides:
		_tri(st, rings[n - 1][j], rings[n - 1][(j + 1) % sides], tip, end_dir, Vector2(0, vs[n - 1]), Vector2(1, vs[n - 1]),
			Vector2(0.5, vs[n - 1]), col)


## Ellipsoide basse definition (pompon, noix de coco) de demi-axes `r`.
static func _blob(st: SurfaceTool, c: Vector3, r: Vector3, segs: int, rings: int, col: Color, uv: Vector2) -> void:
	for j in rings:
		var t0 := PI * j / rings
		var t1 := PI * (j + 1) / rings
		for k in segs:
			var a0 := TAU * k / segs
			var a1 := TAU * (k + 1) / segs
			var p0 := Vector3(sin(t0) * cos(a0), cos(t0), sin(t0) * sin(a0))
			var p1 := Vector3(sin(t0) * cos(a1), cos(t0), sin(t0) * sin(a1))
			var p2 := Vector3(sin(t1) * cos(a1), cos(t1), sin(t1) * sin(a1))
			var p3 := Vector3(sin(t1) * cos(a0), cos(t1), sin(t1) * sin(a0))
			var out := (p0 + p2) * 0.5
			if j == 0:
				_tri(st, c + p0 * r, c + p2 * r, c + p3 * r, out, uv, uv, uv, col)
			elif j == rings - 1:
				_tri(st, c + p0 * r, c + p1 * r, c + p2 * r, out, uv, uv, uv, col)
			else:
				_quad(st, c + p0 * r, c + p1 * r, c + p2 * r, c + p3 * r, out, uv, uv, uv, uv, col)


# --- palmier ------------------------------------------------------------------------

## Stipe : 12 pans, une cicatrice de palme tous les 1/PALM_SCARS (le rayon
## gonfle juste sous chaque cicatrice), courbe comme le palmier simple.
static func palm_trunk() -> ArrayMesh:
	if _palm_trunk != null:
		return _palm_trunk
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	for m in PALM_SCARS:
		for step: Array in [[0.0, 1.0], [0.55, 1.025], [0.9, 1.09]]:
			var u := (m + float(step[0])) / PALM_SCARS
			pts.append(Vector3(0.14 * u * u, u, 0.0))
			radii.append(lerpf(0.034, 0.02, u) * (1.0 + 0.25 * (1.0 - u) * (1.0 - u)) * float(step[1]))
	pts.append(Vector3(0.14, 1.0, 0.0))
	radii.append(0.019)
	_tube(st, pts, radii, 12, Color.WHITE, float(PALM_SCARS))
	st.generate_normals()
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://tracks/materials/playa_palm.gdshader")
	mat.set_shader_parameter("trunk", true)
	mat.set_shader_parameter("rings", 1.0)
	mesh.surface_set_material(0, mat)
	_palm_trunk = mesh
	return mesh


## Couronne de rayon 1 : PALM_FRONDS palmes pennees sur deux etages, deux
## palmes seches qui pendent, grappe de noix de coco sous le coeur.
static func palm_crown() -> ArrayMesh:
	if _palm_crown != null:
		return _palm_crown
	_seed = 1311
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in PALM_FRONDS:
		var upper := f % 2 == 0
		var a := TAU * f / PALM_FRONDS + _range(-0.12, 0.12)
		var lift := _range(0.35, 0.6) if upper else _range(-0.05, 0.2)
		_frond(st, a, lift, _range(0.85, 1.05), Color.WHITE)
	for f in 2:
		_frond(st, TAU * (f + 0.3) / 2.0, -1.1, 0.75, Color(0.52, 0.4, 0.22, 0.0))
	for k in 6:
		var a := TAU * k / 6.0 + 0.3
		var c := Vector3(cos(a) * 0.075, -0.07 - 0.03 * (k % 2), sin(a) * 0.075)
		var col := Color(0.34, 0.42, 0.12, 0.0) if k % 3 != 0 else Color(0.42, 0.3, 0.14, 0.0)
		_blob(st, c, Vector3(0.05, 0.055, 0.05), 8, 5, col, Vector2(0.5, 0.0))
	st.generate_normals()
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://tracks/materials/playa_palm.gdshader")
	mat.set_shader_parameter("trunk", false)
	mesh.surface_set_material(0, mat)
	_palm_crown = mesh
	return mesh


## Une palme : rachis (tube a trois pans) et PALM_LEAFLETS folioles par cote,
## inclinees vers la pointe et retombantes ; UV.y = place le long de la palme
## (le vent fait onduler la pointe), UV.x en travers de la foliole.
static func _frond(st: SurfaceTool, a: float, lift: float, length: float, col: Color) -> void:
	var dir := Vector3(cos(a), 0.0, sin(a))
	var across := Vector3(-dir.z, 0.0, dir.x)
	var spine := func(u: float) -> Vector3:
		return (dir * u + Vector3.UP * (lift * u - (0.75 + 0.3 * lift) * u * u)) * length
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	for k in 14:
		var u := k / 13.0
		pts.append(spine.call(u))
		radii.append(lerpf(0.014, 0.004, u))
	_tube(st, pts, radii, 3, col)
	for q in PALM_LEAFLETS:
		var u := lerpf(0.1, 0.98, float(q) / (PALM_LEAFLETS - 1))
		var p: Vector3 = spine.call(u)
		var t: Vector3 = (spine.call(minf(u + 0.01, 1.0)) - spine.call(maxf(u - 0.01, 0.0))).normalized()
		var reach := (0.3 * pow(sin(PI * clampf((u - 0.05) / 0.95, 0.0, 1.0)), 0.7) + 0.035) * length
		var w := 0.03 * length
		for s: float in [-1.0, 1.0]:
			var ld := (across * s * 0.85 + t * 0.4 - Vector3.UP * (0.3 + 0.25 * u)).normalized()
			var v0 := p - t * w * 0.5
			var v1 := p + t * w * 0.5
			var v2 := p + ld * reach * 0.55 + t * w * 0.3 - Vector3.UP * reach * 0.05
			var v3 := p + ld * reach - Vector3.UP * reach * 0.12
			var up := Vector3.UP + ld * 0.2
			_tri(st, v0, v1, v2, up, Vector2(0.0, u), Vector2(1.0, u), Vector2(0.75, u), col)
			_tri(st, v0, v2, v3, up, Vector2(0.0, u), Vector2(0.75, u), Vector2(0.5, u), col)


# --- cerisier -----------------------------------------------------------------------

## Cerisier entier de hauteur ~1 : surface 0 le bois (`wood`), surface 1 les
## fleurs (`blossom`, teinte de l'instance).
static func cherry(wood: Material, blossom: Material) -> ArrayMesh:
	if _cherry == null:
		_cherry = _build_cherry()
	_cherry.surface_set_material(0, wood)
	_cherry.surface_set_material(1, blossom)
	return _cherry


static func _build_cherry() -> ArrayMesh:
	_seed = 7919
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bloom := SurfaceTool.new()
	bloom.begin(Mesh.PRIMITIVE_TRIANGLES)
	# tronc : evase au pied, penche et un peu tordu jusqu'a la fourche ; la
	# couronne s'etale comme celle du cerisier simple (rayon ~1,1, sommet a
	# ~1,45 de la hauteur du tronc)
	var fork := Vector3(0.04, 0.42, 0.02)
	var trunk := PackedVector3Array()
	var tr := PackedFloat32Array()
	for k in 7:
		var u := k / 6.0
		trunk.append(Vector3(fork.x * u + 0.012 * sin(u * 5.0), fork.y * u, fork.z * u + 0.01 * sin(u * 3.0 + 1.0)))
		tr.append(lerpf(0.08, 0.052, u) * (1.0 + 0.55 * pow(1.0 - u, 6.0)))
	_tube(bark, trunk, tr, 10, Color.WHITE, 4.0)
	var tips: Array[Vector3] = []
	var inner: Array[Vector3] = []
	for k in 5:
		var az := TAU * k / 5.0 + _range(-0.3, 0.3)
		var tilt := deg_to_rad(_range(48.0, 62.0))
		var dir := Vector3(cos(az) * sin(tilt), cos(tilt), sin(az) * sin(tilt))
		var reach := _range(0.62, 0.75)
		_branch(bark, fork, dir, reach, 0.045, 0.018, 0, tips)
		inner.append(fork + dir * reach * 0.6 + Vector3(0, 0.12, 0))
	# grappes de fleurs au bout des rameaux et des branches secondaires, et un
	# gros pompon au coeur de chaque branche maitresse (couronne pleine)
	for c in tips:
		_cluster(bloom, c, _range(0.11, 0.16))
	for c in inner:
		_blob(bloom, c, Vector3(0.22, 0.16, 0.22), 8, 5, Color(0.8, 0.8, 0.8), Vector2.ZERO)
	bark.generate_normals()
	bloom.generate_normals()
	var mesh := ArrayMesh.new()
	bark.commit(mesh)
	bloom.commit(mesh)
	return mesh


## Branche de `from` dans la direction `dir`, longueur `length`, rayons r0 ->
## r1 ; profondeur 0 (maitresse) a 2 (rameau). Les bouts des niveaux 1 et 2
## recoivent une grappe (`tips`).
static func _branch(st: SurfaceTool, from: Vector3, dir: Vector3, length: float, r0: float, r1: float, depth: int,
		tips: Array[Vector3]) -> void:
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	var segs := 5 - depth
	var p := from
	var d := dir
	pts.append(p)
	radii.append(r0)
	for k in segs:
		# chaque troncon devie un peu et remonte vers la lumiere
		d = (d + Vector3(_range(-0.22, 0.22), _range(0.02, 0.12), _range(-0.22, 0.22))).normalized()
		p += d * length / segs
		pts.append(p)
		radii.append(lerpf(r0, r1, float(k + 1) / segs))
	_tube(st, pts, radii, [8, 6, 4][depth], Color.WHITE, 4.0)
	if depth >= 1:
		tips.append(p)
	if depth == 2:
		return
	var children := 3 if depth == 0 else 2
	for c in children:
		var at := clampi(segs - c - (1 if depth == 0 else 0), 1, segs)
		var base := pts[at]
		var az := TAU * c / children + _range(-0.6, 0.6)
		var side := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized().rotated(d, az)
		var cd := (d * 0.65 + side * _range(0.45, 0.8) + Vector3.UP * 0.15).normalized()
		var lr := 0.55 if depth == 0 else 0.5
		_branch(st, base, cd, length * lr * _range(0.85, 1.15), radii[at] * 0.7, r1 * 0.45, depth + 1, tips)


## Grappe : trois pompons bosseles (un peu plus sombres) et quatre fleurs
## a cinq petales posees sur sa surface, tournees vers l'exterieur.
static func _cluster(st: SurfaceTool, c: Vector3, r: float) -> void:
	# trois pompons de tailles differentes qui se chevauchent : une grappe
	# irreguliere, pas une boule
	for k in 3:
		var o := Vector3(_range(-0.5, 0.5), _range(-0.25, 0.35), _range(-0.5, 0.5)) * r
		var pr := r * _range(0.55, 0.78)
		_blob(st, c + o, Vector3(pr, pr * 0.82, pr), 6, 3, Color(0.86, 0.86, 0.86).lerp(Color.WHITE, _rand() * 0.6), Vector2.ZERO)
	for f in 4:
		var n := Vector3(_range(-1, 1), _range(-0.2, 1.0), _range(-1, 1)).normalized()
		var at := c + n * Vector3(r, r * 0.8, r) * 1.02
		_flower(st, at, n, r * _range(0.32, 0.42), _rand() * TAU)


## Fleur de cerisier : cinq petales (trois triangles chacun, bout coupe
## droit), dans le plan perpendiculaire a `n`.
static func _flower(st: SurfaceTool, at: Vector3, n: Vector3, radius: float, spin: float) -> void:
	var u := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := n.cross(u)
	for k in 5:
		var a := spin + TAU * k / 5.0
		var d := u * cos(a) + v * sin(a)
		var e := u * cos(a + PI / 2.0) + v * sin(a + PI / 2.0)
		var mid := at + d * radius * 0.55 + n * radius * 0.08
		var tip_l := at + d * radius + e * radius * 0.2 + n * radius * 0.12
		var tip_r := at + d * radius - e * radius * 0.2 + n * radius * 0.12
		var wl := mid + e * radius * 0.32
		var wr := mid - e * radius * 0.32
		_tri(st, at, wl, wr, n, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Color.WHITE)
		_quad(st, wr, wl, tip_l, tip_r, n, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Color.WHITE)


## Fleurs du cerisier detaille : le shader des couronnes, vu des deux
## cotes, bosses fines et serrees (pompons de quelques decimetres).
const BLOSSOM_BUMP := 0.04
const BLOSSOM_FREQ := 18.0


static func blossom_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://tracks/materials/sakura_blossom_hd.gdshader")
	m.set_shader_parameter("bump", BLOSSOM_BUMP)
	m.set_shader_parameter("bump_freq", BLOSSOM_FREQ)
	return m


## Nombre de triangles d'un maillage (tests, mesure).
static func triangle_count(mesh: Mesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		n += (idx.size() if not idx.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return n
