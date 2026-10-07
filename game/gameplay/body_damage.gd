class_name BodyDamage
extends RefCounted

## Carrosserie qui se deforme sous les chocs (2026-10-06 : « que la remorque se
## deforme quand elle prend des degats. Pareil pour la tete du camion. Que des
## bouts partent »). Purement visuel : la physique ne voit que ses boites.
##
##   - dent() : enfonce les sommets proches du point d'impact, dans le sens du
##     choc, avec une chute douce et un froissement irregulier ; les normales
##     des faces touchees sont recalculees (le creux accroche la lumiere). Les
##     aretes vives restent vives : un sommet n'additionne que les faces qui le
##     partagent par son indice, et les modeles dupliquent les sommets aux
##     aretes vives.
##   - Les grands panneaux (flancs de remorque : 4 sommets sur 16 m) ne peuvent
##     pas se creuser : au premier choc, chaque maillage touche est subdivise
##     (aretes de plus de MAX_EDGE coupees en deux, partout de la meme facon,
##     donc sans fente), une fois par maillage source pour toute la partie.
##   - Le maillage d'origine, partage par tous les camions, n'est jamais
##     modifie : chaque MeshInstance3D touchee recoit sa copie, et restore()
##     la remet a neuf (reapparition, nouvelle remorque).
##   - detach_parts() : les petites pieces exterieures du tracteur (retros,
##     phares, klaxons, echappements, pare-chocs, garde-boue...) proches du
##     choc s'arrachent et deviennent des debris (Debris) ; shards() projette
##     des morceaux de tole de la couleur de la carrosserie touchee.

## Arete plus longue : coupee avant de creuser (m, repere du maillage).
const MAX_EDGE := 0.35
const MAX_PASSES := 8
## Noeuds jamais deformes (ils tournent : roues du tracteur, essieux de la
## remorque) ni arraches.
const SKIP_PREFIXES: PackedStringArray = ["WheelPivot_", "Wheel_", "Gen_Essieu_"]
## Pieces du tracteur qui peuvent s'arracher (prefixe du nom).
const LOOSE_PREFIXES: PackedStringArray = ["Retro_", "Phare", "Feu_", "Clignotant", "Klaxon", "Echappement",
	"Pare_Choc", "Lame_Avant", "Garde_Boue", "Marchepied", "Calandre", "Embleme", "Poignee", "Plaque_",
	"Diffuseur", "Rampe_Phares", "Essuie_Glace", "Flamme", "Support_Marche", "Logo", "Remorque_Feu",
	"Remorque_Bavette", "Remorque_Poignee", "Protection_Laterale", "Aileron", "Derive_Aileron", "Bavette_",
	"Detail_"]
const META_PRISTINE := &"dent_pristine"
const META_OWNER := &"dent_owner"
const META_DETACHED := &"dent_detached"

## Mesh source -> version subdivisee (partagee, jamais modifiee).
static var _tessellated: Dictionary = {}
## Maillage subdivise -> Array[Topo] (voisinage, grille), partage.
static var _topologies: Dictionary = {}
## Cote des cellules de la grille de recherche (repere du maillage).
const CELL := 0.75
## Deplacement maximal d'un sommet depuis le neuf : la tole plie, elle ne
## traverse pas le camion.
const MAX_DISPLACEMENT := 0.8
## Tableaux de surfaces de la copie propre a une instance (meta, liberee avec elle).
const META_ARRAYS := &"dent_arrays"
const META_BASE := &"dent_base"


## Enfonce la carrosserie sous `root` autour de `point` (monde) : sommets a
## moins de `radius` deplaces de `push` (monde, sens et profondeur du creux
## au centre). Renvoie le nombre de sommets deplaces.
static func dent(root: Node3D, point: Vector3, push: Vector3, radius: float) -> int:
	if root == null or radius <= 0.0 or push.length_squared() < 1e-6:
		return 0
	var moved := 0
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() or _skipped(mi, root):
			continue
		var xf := mi.global_transform
		var box := (xf * mi.get_aabb()).grow(radius)
		if not box.has_point(point):
			continue
		var inv := xf.affine_inverse()
		var s := absf(xf.basis.get_scale().x)
		if s < 1e-4:
			continue
		moved += _dent_instance(mi, inv * point, inv.basis * push, radius / s)
	return moved


## Prepare a l'avance (subdivision, voisinage) toutes les carrosseries
## visibles sous `root` : sinon le premier choc sur chaque modele coute
## ~0,1 s (a-coup en pleine course). Une fois par modele et par partie.
static func prewarm(root: Node3D) -> void:
	if root == null:
		return
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() or _skipped(mi, root):
			continue
		var src: Mesh = mi.get_meta(META_PRISTINE, mi.mesh)
		_topology(tessellated(src))


## Remet a neuf toutes les carrosseries sous `root` (copies abandonnees,
## cicatrices effacees, pieces arrachees remises).
static func restore(root: Node3D) -> void:
	if root == null:
		return
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.has_meta(META_PRISTINE):
			mi.mesh = mi.get_meta(META_PRISTINE)
			mi.remove_meta(META_PRISTINE)
			mi.remove_meta(META_OWNER)
			mi.remove_meta(META_ARRAYS)
			mi.remove_meta(META_BASE)
		if mi.has_meta(META_DETACHED):
			mi.remove_meta(META_DETACHED)
			mi.visible = true
	BodyScars.clear(root)


## Nombre de sommets deplaces depuis le neuf, sous `root` (tests).
static func dented_instances(root: Node3D) -> int:
	var count := 0
	for n in root.find_children("*", "MeshInstance3D", true, false):
		if n.has_meta(META_PRISTINE):
			count += 1
	return count


static func _skipped(node: Node, root: Node) -> bool:
	var n := node
	while n != null and n != root:
		for p in SKIP_PREFIXES:
			if String(n.name).begins_with(p):
				return true
		n = n.get_parent()
	return false


static func _dent_instance(mi: MeshInstance3D, p: Vector3, push: Vector3, r: float) -> int:
	var surfaces := _own(mi)
	if surfaces.is_empty():
		return 0
	var topo: Array = _topology(mi.get_meta(META_BASE) as Mesh)
	var r2 := r * r
	var reach := r + MAX_DISPLACEMENT
	var moved := 0
	var changed := false
	for s in surfaces.size():
		var tp: Topo = topo[s]
		var arrays: Array = surfaces[s]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var hit := PackedInt32Array()
		var rest := tp.rest
		var grid := tp.grid
		# sommets candidats : cellules de la grille (positions au neuf) a portee
		var lo := Vector3i(((p - Vector3.ONE * reach) / CELL).floor())
		var hi := Vector3i(((p + Vector3.ONE * reach) / CELL).floor())
		for cx in range(lo.x, hi.x + 1):
			for cy in range(lo.y, hi.y + 1):
				for cz in range(lo.z, hi.z + 1):
					var cell = grid.get(Vector3i(cx, cy, cz))
					if cell == null:
						continue
					for i: int in cell:
						var d2 := verts[i].distance_squared_to(p)
						if d2 >= r2:
							continue
						var u := 1.0 - d2 / r2
						# froissement : profondeur irreguliere, fonction de la seule
						# position (deux sommets confondus bougent pareil : pas de fente)
						var crumple := 0.55 + 0.45 * _hash3(verts[i])
						var v := verts[i] + push * (u * u * crumple)
						# la tole plie, elle ne traverse pas le camion
						var off := v - rest[i]
						if off.length_squared() > MAX_DISPLACEMENT * MAX_DISPLACEMENT:
							v = rest[i] + off.normalized() * MAX_DISPLACEMENT
						# un sommet a peine effleure (bord du creux) ne change pas l'eclairage
						if v.distance_squared_to(verts[i]) < 1e-6:
							continue
						verts[i] = v
						hit.append(i)
		if hit.is_empty():
			continue
		arrays[Mesh.ARRAY_VERTEX] = verts
		_renormal(arrays, tp, hit)
		moved += hit.size()
		changed = true
	if changed:
		_commit(mi, surfaces)
	return moved


## Copie propre de l'instance (subdivisee), tableaux de surfaces en cache.
static func _own(mi: MeshInstance3D) -> Array:
	var id := mi.get_instance_id()
	if mi.get_meta(META_OWNER, 0) == id and mi.has_meta(META_ARRAYS):
		return mi.get_meta(META_ARRAYS)
	# premiere fois pour cette instance (ou copie d'une carrosserie deja
	# cabossee : la remorque larguee) : on part de son maillage actuel
	var src := mi.mesh
	if not mi.has_meta(META_PRISTINE):
		mi.set_meta(META_PRISTINE, src)
		src = tessellated(src)
	var base := tessellated(mi.get_meta(META_PRISTINE) as Mesh)
	if base.get_surface_count() != src.get_surface_count():
		return []
	var surfaces: Array = []
	for s in src.get_surface_count():
		if _primitive(src, s) != Mesh.PRIMITIVE_TRIANGLES:
			return []
		surfaces.append(src.surface_get_arrays(s))
	if _topology(base).size() != surfaces.size():
		return []
	mi.set_meta(META_OWNER, id)
	mi.set_meta(META_BASE, base)
	mi.set_meta(META_ARRAYS, surfaces)
	return surfaces


static func _commit(mi: MeshInstance3D, surfaces: Array) -> void:
	var src := mi.mesh
	var out := ArrayMesh.new()
	for s in surfaces.size():
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surfaces[s])
		if s < src.get_surface_count():
			out.surface_set_material(s, src.surface_get_material(s))
			if src is ArrayMesh:
				out.surface_set_name(s, (src as ArrayMesh).surface_get_name(s))
	mi.mesh = out


## Normales recalculees autour des sommets `hit` : faces qui touchent un
## sommet deplace, puis sommets de ces faces, chacun depuis TOUTES ses faces
## (table de voisinage : seule la zone touchee est parcourue).
static func _renormal(arrays: Array, tp: Topo, hit: PackedInt32Array) -> void:
	var normals = arrays[Mesh.ARRAY_NORMAL]
	if normals == null or (normals as PackedVector3Array).is_empty():
		return
	var nrm := normals as PackedVector3Array
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx := tp.idx
	var start := tp.tri_start
	var tris := tp.tri_ids
	var seen := PackedByteArray()
	seen.resize(verts.size())
	var touched := PackedInt32Array()
	for i in hit:
		for k in range(start[i], start[i + 1]):
			var t := tris[k] * 3
			for j in 3:
				var w := idx[t + j]
				if seen[w] == 0:
					seen[w] = 1
					touched.append(w)
	for i in touched:
		var acc := Vector3.ZERO
		for k in range(start[i], start[i + 1]):
			var t := tris[k] * 3
			var a := verts[idx[t]]
			acc += (verts[idx[t + 1]] - a).cross(verts[idx[t + 2]] - a)
		if acc.length_squared() < 1e-12:
			continue
		var n := acc.normalized()
		# sens des normales du modele, quel que soit l'ordre des sommets
		nrm[i] = -n if n.dot(nrm[i]) < 0.0 else n
	arrays[Mesh.ARRAY_NORMAL] = nrm


## Donnees de voisinage d'une surface subdivisee, au neuf (partagees).
class Topo:
	var rest: PackedVector3Array
	var idx: PackedInt32Array
	## cellule (Vector3i, cote CELL) -> indices des sommets qui y sont au neuf
	var grid: Dictionary = {}
	## faces de chaque sommet : tri_ids[tri_start[i] .. tri_start[i + 1]]
	var tri_start: PackedInt32Array
	var tri_ids: PackedInt32Array


## Topologie de chaque surface de `base` (maillage subdivise), une fois.
static func _topology(base: Mesh) -> Array:
	if _topologies.has(base):
		return _topologies[base]
	var out: Array = []
	for s in base.get_surface_count():
		var arrays := base.surface_get_arrays(s)
		var tp := Topo.new()
		tp.rest = arrays[Mesh.ARRAY_VERTEX]
		var n := tp.rest.size()
		if arrays[Mesh.ARRAY_INDEX] != null:
			tp.idx = arrays[Mesh.ARRAY_INDEX]
		else:
			tp.idx.resize(n)
			for i in n:
				tp.idx[i] = i
		var cells: Dictionary = {}
		for i in n:
			var key := Vector3i((tp.rest[i] / CELL).floor())
			if not cells.has(key):
				cells[key] = []
			cells[key].append(i)
		tp.grid = cells
		var count := PackedInt32Array()
		count.resize(n + 1)
		for k in tp.idx.size():
			count[tp.idx[k] + 1] += 1
		for i in n:
			count[i + 1] += count[i]
		tp.tri_start = count.duplicate()
		var fill := count
		tp.tri_ids.resize(tp.idx.size())
		for k in tp.idx.size():
			var v := tp.idx[k]
			tp.tri_ids[fill[v]] = k / 3
			fill[v] += 1
		out.append(tp)
	_topologies[base] = out
	return out


static func _hash3(v: Vector3) -> float:
	var h := int(floorf(v.x * 37.0)) * 73856093 ^ int(floorf(v.y * 37.0)) * 19349663 ^ int(floorf(v.z * 37.0)) * 83492791
	h = (h ^ (h >> 13)) * 1274126177
	return float((h >> 8) & 0xffff) / 65535.0


# --- subdivision -----------------------------------------------------------------

## Version subdivisee de `mesh` (aucune arete > MAX_EDGE), calculee une fois.
static func tessellated(mesh: Mesh) -> Mesh:
	if _tessellated.has(mesh):
		return _tessellated[mesh]
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		if _primitive(mesh, s) == Mesh.PRIMITIVE_TRIANGLES:
			arrays = _subdivide(arrays)
		out.add_surface_from_arrays(_primitive(mesh, s), arrays)
		out.surface_set_material(s, mesh.surface_get_material(s))
	_tessellated[mesh] = out
	return out


## Coupe en deux toute arete plus longue que MAX_EDGE, jusqu'a ce qu'il n'en
## reste plus. Une arete est coupee selon sa seule longueur : les deux faces
## qui la partagent la coupent au meme milieu (aucune fente).
static func _subdivide(arrays: Array) -> Array:
	if arrays[Mesh.ARRAY_BONES] != null or arrays[Mesh.ARRAY_WEIGHTS] != null:
		return arrays
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n0 := verts.size()
	var nrm := _attr3(arrays, Mesh.ARRAY_NORMAL, n0)
	var uv := _attr2(arrays, Mesh.ARRAY_TEX_UV, n0)
	var uv2 := _attr2(arrays, Mesh.ARRAY_TEX_UV2, n0)
	var col := PackedColorArray()
	if arrays[Mesh.ARRAY_COLOR] != null and (arrays[Mesh.ARRAY_COLOR] as PackedColorArray).size() == n0:
		col = arrays[Mesh.ARRAY_COLOR]
	var tan := PackedFloat32Array()
	if arrays[Mesh.ARRAY_TANGENT] != null and (arrays[Mesh.ARRAY_TANGENT] as PackedFloat32Array).size() == n0 * 4:
		tan = arrays[Mesh.ARRAY_TANGENT]
	# plus de reference dans `arrays` : les ajouts ci-dessous ne copient pas
	for k in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR, Mesh.ARRAY_TANGENT]:
		arrays[k] = null
	var idx := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		idx = arrays[Mesh.ARRAY_INDEX]
	else:
		idx.resize(n0)
		for i in n0:
			idx[i] = i
	var l2 := MAX_EDGE * MAX_EDGE
	var v := PackedInt32Array([0, 0, 0])
	var m := PackedInt32Array([0, 0, 0])
	for pass_i in MAX_PASSES:
		var mids: Dictionary = {}
		var out := PackedInt32Array()
		var any := false
		for t in idx.size() / 3:
			v[0] = idx[t * 3]
			v[1] = idx[t * 3 + 1]
			v[2] = idx[t * 3 + 2]
			var count := 0
			var cut := -1
			var keep := -1
			for k in 3:
				var a := v[k]
				var b := v[(k + 1) % 3]
				m[k] = -1
				if verts[a].distance_squared_to(verts[b]) <= l2:
					keep = k
					continue
				var key := (mini(a, b) << 32) | maxi(a, b)
				if not mids.has(key):
					var i := verts.size()
					verts.append((verts[a] + verts[b]) * 0.5)
					if not nrm.is_empty():
						var s := nrm[a] + nrm[b]
						nrm.append(s.normalized() if s.length_squared() > 1e-8 else nrm[a])
					if not uv.is_empty():
						uv.append((uv[a] + uv[b]) * 0.5)
					if not uv2.is_empty():
						uv2.append((uv2[a] + uv2[b]) * 0.5)
					if not col.is_empty():
						col.append(col[a].lerp(col[b], 0.5))
					if not tan.is_empty():
						var ta := Vector3(tan[a * 4], tan[a * 4 + 1], tan[a * 4 + 2])
						var tb := Vector3(tan[b * 4], tan[b * 4 + 1], tan[b * 4 + 2])
						var tm := (ta + tb).normalized() if (ta + tb).length_squared() > 1e-8 else ta
						tan.append_array([tm.x, tm.y, tm.z, tan[a * 4 + 3]])
					mids[key] = i
				m[k] = mids[key]
				cut = k
				count += 1
			if count == 0:
				out.append_array(v)
				continue
			any = true
			if count == 3:
				out.append_array([v[0], m[0], m[2], m[0], v[1], m[1], m[2], m[1], v[2], m[0], m[1], m[2]])
				continue
			# rotation : l'arete coupee (1 coupe) ou l'arete intacte (2 coupes)
			# devient la troisieme, w2 -> w0
			var r := (cut + 1) % 3 if count == 1 else (keep + 1) % 3
			var w0 := v[r]
			var w1 := v[(r + 1) % 3]
			var w2 := v[(r + 2) % 3]
			if count == 1:
				var c := m[(r + 2) % 3]
				out.append_array([w0, w1, c, c, w1, w2])
			else:
				var c0 := m[r]
				var c1 := m[(r + 1) % 3]
				out.append_array([c0, w1, c1, w0, c0, c1, w0, c1, w2])
		idx = out
		if not any:
			break
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = nrm if not nrm.is_empty() else null
	arrays[Mesh.ARRAY_TEX_UV] = uv if not uv.is_empty() else null
	arrays[Mesh.ARRAY_TEX_UV2] = uv2 if not uv2.is_empty() else null
	arrays[Mesh.ARRAY_COLOR] = col if not col.is_empty() else null
	arrays[Mesh.ARRAY_TANGENT] = tan if not tan.is_empty() else null
	arrays[Mesh.ARRAY_INDEX] = idx
	return arrays


static func _attr3(arrays: Array, k: int, n: int) -> PackedVector3Array:
	if arrays[k] != null and (arrays[k] as PackedVector3Array).size() == n:
		return arrays[k]
	return PackedVector3Array()


static func _attr2(arrays: Array, k: int, n: int) -> PackedVector2Array:
	if arrays[k] != null and (arrays[k] as PackedVector2Array).size() == n:
		return arrays[k]
	return PackedVector2Array()


# --- pieces arrachees, eclats ----------------------------------------------------

## Arrache jusqu'a `max_parts` petites pieces exterieures sous `root`, a moins
## de `radius` de `point` (monde) : cachees sur le camion, relancees en debris
## avec `velocity` (monde) plus une poussee `kick` vers l'exterieur. Renvoie
## le nombre de pieces arrachees.
static func detach_parts(root: Node3D, world: Node, point: Vector3, radius: float, max_parts: int,
		velocity: Vector3, kick: float) -> int:
	if root == null or world == null or max_parts <= 0:
		return 0
	var found: Array[MeshInstance3D] = []
	var dist: Array[float] = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() or not _loose(mi.name) or _skipped(mi, root):
			continue
		var c := mi.global_transform * mi.get_aabb().get_center()
		var d := c.distance_to(point)
		if d < radius:
			found.append(mi)
			dist.append(d)
	# les plus proches d'abord
	var order := range(found.size())
	order.sort_custom(func(i: int, j: int) -> bool: return dist[i] < dist[j])
	var count := 0
	for i: int in order:
		if count >= max_parts:
			break
		var mi := found[i]
		var c := mi.global_transform * mi.get_aabb().get_center()
		var out := c - point
		out = out.normalized() if out.length_squared() > 1e-4 else Vector3.UP
		Debris.from_part(world, mi, velocity + (out + Vector3.UP * 0.6).normalized() * kick)
		mi.visible = false
		mi.set_meta(META_DETACHED, true)
		count += 1
	return count


static func _loose(node_name: StringName) -> bool:
	var s := String(node_name)
	for p in LOOSE_PREFIXES:
		if s.begins_with(p):
			return true
	return false


## Materiau de la carrosserie la plus proche de `point` sous `root` (pour les
## eclats de tole) ; null si aucune.
static func nearest_material(root: Node3D, point: Vector3) -> Material:
	if root == null:
		return null
	var best: Material = null
	var best_d := INF
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() or _skipped(mi, root):
			continue
		var box := mi.global_transform * mi.get_aabb()
		var d := box.get_center().distance_to(point) - box.size.length() * 0.5
		if d < best_d and mi.mesh.get_surface_count() > 0:
			best_d = d
			best = mi.get_active_material(0)
	return best


## `count` eclats de tole projetes depuis `point` (monde), autour de `out`.
static func shards(world: Node, point: Vector3, out: Vector3, count: int, velocity: Vector3, speed: float,
		material: Material, seed_value: int = 0) -> void:
	if world == null:
		return
	for k in count:
		var h := _hash3(point + Vector3(k * 1.37, seed_value * 0.71, k * 0.53))
		var h2 := _hash3(point + Vector3(seed_value * 0.33, k * 2.11, k * 0.91))
		var dir := (out + Vector3(h - 0.5, 0.6 + h2, h2 - 0.5) * 1.4).normalized()
		var size := Vector3(lerpf(0.25, 0.9, h), lerpf(0.03, 0.06, h2), lerpf(0.2, 0.7, h2))
		Debris.shard(world, point + dir * 0.4, size, material, velocity + dir * speed * lerpf(0.6, 1.2, h))


## Type de primitive d'une surface (les maillages primitifs, boites de
## blockout comprises, sont toujours en triangles).
static func _primitive(mesh: Mesh, s: int) -> Mesh.PrimitiveType:
	if mesh is ArrayMesh:
		return (mesh as ArrayMesh).surface_get_primitive_type(s)
	return Mesh.PRIMITIVE_TRIANGLES
