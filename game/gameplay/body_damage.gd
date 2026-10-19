class_name BodyDamage
extends RefCounted

## Carrosserie qui se deforme sous les chocs (2026-10-06 : « que la remorque se
## deforme quand elle prend des degats. Pareil pour la tete du camion. Que des
## bouts partent »). Purement visuel : la physique ne voit que ses boites.
##
##   - dent() : enfonce les sommets proches du point d'impact, dans le sens du
##     choc, avec une chute douce et un froissement irregulier ; la tole se
##     fatigue : un nouveau coup pres d'un creux deja la l'enfonce plus
##     profond et plus large (META_HITS) ; les normales
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
## Sommets candidats (creux) et sommets deplaces (normales) par tache d'un
## creux (DentJob) : en dessous, un seul lot, calcule sur place.
const JOB_VERTICES := 3000
const JOB_NORMALS := 500
## Deplacement maximal d'un sommet depuis le neuf : la tole plie, elle ne
## traverse pas le camion.
const MAX_DISPLACEMENT := 0.8
## Tableaux de surfaces de la copie propre a une instance (meta, liberee avec elle).
const META_ARRAYS := &"dent_arrays"
const META_BASE := &"dent_base"
## Tole fatiguee (2026-10-07 : « plus on tape sur une paroi, plus elle se
## deforme, en s'enfoncant ») : chaque coup deja recu au meme endroit (a moins
## du rayon du creux) enfonce le suivant de FATIGUE_PER_HIT de plus (au plus
## FATIGUE_MAX fois) et l'elargit de FATIGUE_SPREAD. Coups retenus par
## maillage : Array de Vector4 (point local, nombre).
const META_HITS := &"dent_hits"
const FATIGUE_PER_HIT := 0.5
const FATIGUE_MAX := 3.0
const FATIGUE_SPREAD := 0.12
const MAX_HIT_SPOTS := 24
## Bord lobe d'un creux : jusqu'a LOBE_MAX fois son rayon.
const LOBE_MAX := 1.4


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
		var p := inv * point
		var r := radius / s
		# tole fatiguee : chaque coup pres d'un creux deja la l'enfonce plus
		# (et sur une zone un peu plus large)
		var n_prev := _fatigue(mi, p, r)
		var k := minf(1.0 + FATIGUE_PER_HIT * n_prev, FATIGUE_MAX)
		moved += _dent_instance(mi, p, inv.basis * push * k, r * (1.0 + FATIGUE_SPREAD * minf(n_prev, 4.0)))
	return moved


## Coups deja recus par `mi` a moins de `r` du point local `p` (avant celui-
## ci), puis ce coup compte : le plus proche est renforce, sinon un nouveau.
static func _fatigue(mi: MeshInstance3D, p: Vector3, r: float) -> int:
	var hits: Array = mi.get_meta(META_HITS, [])
	var best := -1
	var best_d := INF
	for i in hits.size():
		var h: Vector4 = hits[i]
		var d := Vector3(h.x, h.y, h.z).distance_to(p)
		if d < r and d < best_d:
			best = i
			best_d = d
	var n := 0
	if best >= 0:
		var h: Vector4 = hits[best]
		n = int(h.w)
		hits[best] = Vector4(h.x, h.y, h.z, h.w + 1.0)
	elif hits.size() < MAX_HIT_SPOTS:
		hits.append(Vector4(p.x, p.y, p.z, 1.0))
	mi.set_meta(META_HITS, hits)
	return n


## Coups deja recus au meme endroit (au plus proche de `point`, monde) par la
## carrosserie sous `root` (tests).
static func hits_near(root: Node3D, point: Vector3) -> int:
	var best := 0
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var p := mi.global_transform.affine_inverse() * point
		for h: Vector4 in mi.get_meta(META_HITS, []):
			if Vector3(h.x, h.y, h.z).distance_to(p) < 1.0:
				best = maxi(best, int(h.w))
	return best


## Prepare a l'avance (subdivision, voisinage) toutes les carrosseries
## visibles sous `root` : sinon le premier choc sur chaque modele coute
## ~0,1 s (a-coup en pleine course). Une fois par modele et par partie.
## `own` (2026-10-17, tache 7.6) : prepare aussi la copie propre de CETTE
## instance (_own : ses tableaux de sommets) - le premier choc dur de chaque
## camion coutait encore ~50 ms a la copier ; son maillage affiche ne change
## pas.
static func prewarm(root: Node3D, own: bool = false) -> void:
	if root == null:
		return
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() or _skipped(mi, root):
			continue
		var src: Mesh = mi.get_meta(META_PRISTINE, mi.mesh)
		_topology(tessellated(src))
		if own:
			_own(mi)


## Carrosseries a preparer d'une copie HORS de l'arbre (gabarit d'un modele,
## ecran de chargement, 2026-10-17) : les caches de subdivision et de
## voisinage sont indexes par maillage, et toutes les instances du modele
## partagent ces maillages. Visibilite : celle des noeuds (pas d'arbre).
static func detached_meshes(root: Node3D) -> Array[Mesh]:
	var out: Array[Mesh] = []
	if root == null:
		return out
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or _skipped(mi, root):
			continue
		var v: Node = mi
		var shown := true
		while v != null and v != root:
			if v is Node3D and not (v as Node3D).visible:
				shown = false
				break
			v = v.get_parent()
		var m: Mesh = mi.get_meta(META_PRISTINE, mi.mesh)
		if shown and not out.has(m):
			out.append(m)
	return out


## Prepare un maillage (subdivision, voisinage) : une tranche de prewarm.
static func prewarm_mesh(mesh: Mesh) -> void:
	_topology(tessellated(mesh))

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
		if mi.has_meta(META_HITS):
			mi.remove_meta(META_HITS)
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
	# forme du creux (2026-10-07 : « des ronds trop parfaits ») : ovale couche
	# (le choc glisse, la tole s'enfonce en longueur), bord lobe et plis en
	# travers, tires d'apres le point d'impact - deux coups au meme endroit
	# creusent la meme forme. Repere : n (sens du choc), t1 (horizontal), t2.
	var n := push.normalized()
	var t1 := Vector3.UP.cross(n)
	if t1.length_squared() < 1e-3:
		t1 = Vector3.RIGHT.cross(n)
	t1 = t1.normalized()
	var t2 := n.cross(t1)
	var h := _hash3(p * 0.37)
	# aire voisine de celle du disque de rayon r : autant de sommets a deplacer
	# (le cout d'un choc en depend)
	var stretch := 1.1 + 0.4 * h
	var squash := 0.75 + 0.15 * _hash3(p * 0.53 + Vector3.ONE)
	var ph := Vector3(h * TAU, _hash3(p * 0.71) * TAU, _hash3(p * 0.29 + Vector3.UP) * TAU)
	var fold_a := _hash3(p * 0.91) * PI
	var fold := t1 * cos(fold_a) + t2 * sin(fold_a)
	var r2 := r * r
	# portee : l'ovale (lobes compris, jusqu'a LOBE_MAX fois r), boite alignee
	# sur les axes du maillage ; la forme se lit sur la tole au neuf (grille et
	# `rest`) : un coup sur un creux deja la le creuse a nouveau en entier
	var e1 := t1 * (r * stretch * LOBE_MAX)
	var e2 := t2 * (r * squash * LOBE_MAX)
	# le long du choc, portee reduite : la paroi d'en face reste intacte
	var e3 := n * (r * LOBE_MAX * 0.71)
	var reach := Vector3(Vector3(e1.x, e2.x, e3.x).length(), Vector3(e1.y, e2.y, e3.y).length(),
		Vector3(e1.z, e2.z, e3.z).length())
	var far2 := r2 * LOBE_MAX * LOBE_MAX
	# une cellule entiere hors de l'ovale est sautee : son centre en est trop
	# loin, meme a une demi-diagonale pres (etiree au plus de sqrt(2) dans le
	# repere de l'ovale, dont la plus forte compression est le long du choc)
	var far := sqrt(far2)
	var cell_reach := CELL * 0.5 * sqrt(3.0) * sqrt(2.0)
	var half_cell := Vector3.ONE * (CELL * 0.5)
	var lo := Vector3i(((p - reach) / CELL).floor())
	var hi := Vector3i(((p + reach) / CELL).floor())
	# sommets candidats : cellules de la grille (positions au neuf) a portee,
	# toutes surfaces confondues
	var job := DentJob.new()
	var cell_surf := PackedInt32Array()
	var cells: Array[PackedInt32Array] = []
	var total := 0
	for s in surfaces.size():
		var tp: Topo = topo[s]
		var arrays: Array = surfaces[s]
		job.rest.append(tp.rest)
		job.grain.append(tp.grain)
		job.verts.append(arrays[Mesh.ARRAY_VERTEX])
		job.idx.append(tp.idx)
		job.tri_start.append(tp.tri_start)
		job.tri_ids.append(tp.tri_ids)
		var normals = arrays[Mesh.ARRAY_NORMAL]
		job.nrm.append(normals if normals != null else PackedVector3Array())
		var grid := tp.grid
		for cx in range(lo.x, hi.x + 1):
			for cy in range(lo.y, hi.y + 1):
				for cz in range(lo.z, hi.z + 1):
					var key := Vector3i(cx, cy, cz)
					if not grid.has(key):
						continue
					var dc := Vector3(key) * CELL + half_cell - p
					var ca := dc.dot(t1) / stretch
					var cb := dc.dot(t2) / squash
					var cn := dc.dot(n)
					if sqrt(ca * ca + cb * cb + 2.0 * cn * cn) - cell_reach >= far:
						continue
					var cell: PackedInt32Array = grid[key]
					cell_surf.append(s)
					cells.append(cell)
					total += cell.size()
	if total == 0:
		return 0
	# lots de taille voisine, cellules voisines ensemble
	var lots := clampi(total / JOB_VERTICES, 1, maxi(OS.get_processor_count() - 1, 1))
	var lot_surf := PackedInt32Array()
	var lot_cells: Array[PackedInt32Array] = []
	var filled := 0
	for c in cells.size():
		lot_surf.append(cell_surf[c])
		lot_cells.append(cells[c])
		filled += cells[c].size()
		if filled * lots >= total * (job.lot_cells.size() + 1) and job.lot_cells.size() < lots - 1:
			job.lot_surf.append(lot_surf)
			job.lot_cells.append(lot_cells)
			lot_surf = PackedInt32Array()
			lot_cells = []
	job.lot_surf.append(lot_surf)
	job.lot_cells.append(lot_cells)
	job.resize_out(job.lot_cells.size())
	job.p = p
	job.push = push
	job.t1 = t1
	job.t2 = t2
	job.n = n
	job.fold = fold
	job.ph = ph
	job.stretch = stretch
	job.squash = squash
	job.r2 = r2
	job.far2 = far2
	job.run(job.dent_lot)
	var moved := job.apply(job.verts)
	if moved == 0:
		return 0
	job.split_moved(clampi(moved / JOB_NORMALS, 1, maxi(OS.get_processor_count() - 1, 1)))
	job.run(job.normal_lot)
	job.apply(job.nrm)
	for s in surfaces.size():
		var arrays: Array = surfaces[s]
		arrays[Mesh.ARRAY_VERTEX] = job.verts[s]
		if not job.nrm[s].is_empty():
			arrays[Mesh.ARRAY_NORMAL] = job.nrm[s]
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
	var topo := _topology(base)
	if topo.size() != surfaces.size():
		return []
	# maillage courant qui ne correspond plus a la grille (copie d'une instance
	# marquee mais jamais subdivisee, 2026-10-17 : indices hors limites dans
	# dent_lot) : on repart du neuf subdivise, sans ses anciens creux
	for s in surfaces.size():
		var verts: PackedVector3Array = surfaces[s][Mesh.ARRAY_VERTEX]
		if verts.size() != (topo[s] as Topo).rest.size():
			surfaces.clear()
			for k in base.get_surface_count():
				surfaces.append(base.surface_get_arrays(k))
			break
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


## Un creux reparti sur les coeurs (WorkerThreadPool, 2026-10-09) : la citerne
## compte 74 000 sommets, un choc a 15 m/s en deplace 6 000 et en eclaire 7 000
## de nouveau ; sur un seul coeur, 45 ms (a-coup en pleine course). Deux
## passes, chacune en un seul envoi au pool, lots de cellules de toutes les
## surfaces :
##   - dent_lot : sommets deplaces par le creux ;
##   - normal_lot : normales recalculees autour d'eux : faces qui touchent un
##     sommet deplace, puis sommets de ces faces, chacun depuis TOUTES ses
##     faces (table de voisinage : seule la zone touchee est parcourue).
## Chaque tache rend ses resultats (surface, indice, valeur) ; le thread
## principal les reporte. Les taches ne font que lire les tableaux partages.
## Un sommet ne depend que de sa position et de ses faces : le resultat ne
## depend pas du decoupage (un sommet au bord de deux lots est calcule deux
## fois, a l'identique).
class DentJob:
	## Par surface : tableaux lus par les taches.
	var rest: Array[PackedVector3Array] = []
	var grain: Array[PackedFloat32Array] = []
	var verts: Array[PackedVector3Array] = []
	var nrm: Array[PackedVector3Array] = []
	var idx: Array[PackedInt32Array] = []
	var tri_start: Array[PackedInt32Array] = []
	var tri_ids: Array[PackedInt32Array] = []
	## Par lot : cellules (indices de sommets) et leur surface, regroupees par
	## surface ; resultats de la derniere passe.
	var lot_surf: Array[PackedInt32Array] = []
	var lot_cells: Array[Array] = []
	var out_surf: Array[PackedInt32Array] = []
	var out_ids: Array[PackedInt32Array] = []
	var out_pos: Array[PackedVector3Array] = []
	var mutex := Mutex.new()
	var p: Vector3
	var push: Vector3
	var t1: Vector3
	var t2: Vector3
	var n: Vector3
	var fold: Vector3
	var ph: Vector3
	var stretch: float
	var squash: float
	var r2: float
	var far2: float

	## `task` sur chaque lot : sur place s'il n'y en a qu'un, sinon en parallele.
	func run(task: Callable) -> void:
		if out_ids.size() == 1:
			task.call(0)
			return
		var group := WorkerThreadPool.add_group_task(task, out_ids.size(), -1, true, "BodyDamage")
		WorkerThreadPool.wait_for_group_task_completion(group)

	func resize_out(count: int) -> void:
		out_surf.resize(count)
		out_ids.resize(count)
		out_pos.resize(count)

	## Sommets deplaces (resultats de dent_lot) redecoupes en `count` lots
	## egaux pour normal_lot : les lots du creux, egaux en candidats, ne le
	## sont pas en sommets deplaces. L'ordre (cellules voisines ensemble) est
	## garde.
	func split_moved(count: int) -> void:
		var all_s := PackedInt32Array()
		var all_i := PackedInt32Array()
		for k in out_ids.size():
			all_s.append_array(out_surf[k])
			all_i.append_array(out_ids[k])
		resize_out(count)
		var size := all_i.size()
		for k in count:
			var from := size * k / count
			var to := size * (k + 1) / count
			out_surf[k] = all_s.slice(from, to)
			out_ids[k] = all_i.slice(from, to)
			out_pos[k] = PackedVector3Array()

	## Reporte les resultats de la derniere passe dans `into` (un tableau par
	## surface). Renvoie le nombre de valeurs reportees.
	func apply(into: Array[PackedVector3Array]) -> int:
		var count := 0
		var s := -1
		var dst := PackedVector3Array()
		for k in out_ids.size():
			var surf := out_surf[k]
			var ids := out_ids[k]
			var values := out_pos[k]
			for m in ids.size():
				if surf[m] != s:
					if s >= 0:
						into[s] = dst
					s = surf[m]
					dst = into[s]
				dst[ids[m]] = values[m]
			count += ids.size()
		if s >= 0:
			into[s] = dst
		return count

	func _store(k: int, surf: PackedInt32Array, ids: PackedInt32Array, values: PackedVector3Array) -> void:
		mutex.lock()
		out_surf[k] = surf
		out_ids[k] = ids
		out_pos[k] = values
		mutex.unlock()

	## Sommets du lot k deplaces par le creux (positions apres le choc).
	func dent_lot(k: int) -> void:
		var p_l := p
		var t1_l := t1
		var t2_l := t2
		var n_l := n
		var fold_l := fold
		var ph_l := ph
		var push_l := push
		var stretch_l := stretch
		var squash_l := squash
		var r2_l := r2
		var far2_l := far2
		var surfs := lot_surf[k]
		var cells: Array = lot_cells[k]
		var out_s := PackedInt32Array()
		var ids := PackedInt32Array()
		var values := PackedVector3Array()
		var s := -1
		var rest_l := PackedVector3Array()
		var grain_l := PackedFloat32Array()
		var verts_l := PackedVector3Array()
		for c in cells.size():
			if surfs[c] != s:
				s = surfs[c]
				rest_l = rest[s]
				grain_l = grain[s]
				verts_l = verts[s]
			var cell: PackedInt32Array = cells[c]
			for i in cell:
				var ri := rest_l[i]
				var dv := ri - p_l
				var a := dv.dot(t1_l) / stretch_l
				var b := dv.dot(t2_l) / squash_l
				var cc := dv.dot(n_l)
				var q2 := a * a + b * b + 2.0 * cc * cc
				if q2 >= far2_l:
					continue
				var th := atan2(b, a)
				var lobe := 1.0 + 0.2 * sin(2.0 * th + ph_l.x) + 0.13 * sin(3.0 * th + ph_l.y) \
					+ 0.07 * sin(5.0 * th + ph_l.z)
				var d2 := q2 / (lobe * lobe)
				if d2 >= r2_l:
					continue
				var u := 1.0 - d2 / r2_l
				# froissement : profondeur irreguliere, fonction de la seule
				# position (deux sommets confondus bougent pareil : pas de
				# fente) ; plis en travers du creux, tous les ~0,9 m
				var crumple := (0.55 + 0.45 * grain_l[i]) * (0.7 + 0.3 * absf(sin(dv.dot(fold_l) * 3.5 + ph_l.x)))
				var was := verts_l[i]
				var v := was + push_l * (u * u * crumple)
				# la tole plie, elle ne traverse pas le camion
				var off := v - ri
				if off.length_squared() > MAX_DISPLACEMENT * MAX_DISPLACEMENT:
					v = ri + off.normalized() * MAX_DISPLACEMENT
				# un sommet a peine effleure (bord du creux) ne change pas l'eclairage
				if v.distance_squared_to(was) < 1e-6:
					continue
				out_s.append(s)
				ids.append(i)
				values.append(v)
		_store(k, out_s, ids, values)

	## Normales des sommets autour de ceux que le lot k a deplaces (resultats
	## de dent_lot, deja reportes dans verts).
	func normal_lot(k: int) -> void:
		mutex.lock()
		var moved_s: PackedInt32Array = out_surf[k]
		var moved: PackedInt32Array = out_ids[k]
		mutex.unlock()
		var out_s := PackedInt32Array()
		var ids := PackedInt32Array()
		var values := PackedVector3Array()
		var s := -1
		var verts_l := PackedVector3Array()
		var nrm_l := PackedVector3Array()
		var idx_l := PackedInt32Array()
		var start := PackedInt32Array()
		var tris := PackedInt32Array()
		var seen := PackedByteArray()
		for m in moved.size():
			if moved_s[m] != s:
				s = moved_s[m]
				verts_l = verts[s]
				nrm_l = nrm[s]
				idx_l = idx[s]
				start = tri_start[s]
				tris = tri_ids[s]
				seen = PackedByteArray()
				seen.resize(verts_l.size())
			if nrm_l.is_empty():
				continue
			var i := moved[m]
			for kk in range(start[i], start[i + 1]):
				var t := tris[kk] * 3
				for j in 3:
					var w := idx_l[t + j]
					if seen[w] != 0:
						continue
					seen[w] = 1
					var acc := Vector3.ZERO
					for f in range(start[w], start[w + 1]):
						var tw := tris[f] * 3
						var a := verts_l[idx_l[tw]]
						acc += (verts_l[idx_l[tw + 1]] - a).cross(verts_l[idx_l[tw + 2]] - a)
					if acc.length_squared() < 1e-12:
						continue
					var nw := acc.normalized()
					# sens des normales du modele, quel que soit l'ordre des sommets
					out_s.append(s)
					ids.append(w)
					values.append(-nw if nw.dot(nrm_l[w]) < 0.0 else nw)
		_store(k, out_s, ids, values)


## Donnees de voisinage d'une surface subdivisee, au neuf (partagees).
class Topo:
	var rest: PackedVector3Array
	var idx: PackedInt32Array
	## cellule (Vector3i, cote CELL) -> indices des sommets qui y sont au neuf
	## (PackedInt32Array)
	var grid: Dictionary = {}
	## froissement propre a chaque sommet, d'apres sa position au neuf (_hash3)
	var grain: PackedFloat32Array
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
		var grain := PackedFloat32Array()
		grain.resize(n)
		for i in n:
			var key := Vector3i((tp.rest[i] / CELL).floor())
			if not cells.has(key):
				cells[key] = []
			cells[key].append(i)
			grain[i] = _hash3(tp.rest[i])
		for key: Vector3i in cells:
			cells[key] = PackedInt32Array(cells[key])
		tp.grid = cells
		tp.grain = grain
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
## le nombre de pieces arrachees. Les `trails` premieres fument en volant
## (les 2 premieres brulent : explosion).
static func detach_parts(root: Node3D, world: Node, point: Vector3, radius: float, max_parts: int,
		velocity: Vector3, kick: float, trails: int = 0) -> int:
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
		var d := Debris.from_part(world, mi, velocity + (out + Vector3.UP * 0.6).normalized() * kick)
		if count < trails:
			d.add_trail(count < 2)
		# son ombre partait avec la silhouette de sa partie (ShadowProxy)
		ShadowProxy.release(mi)
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
