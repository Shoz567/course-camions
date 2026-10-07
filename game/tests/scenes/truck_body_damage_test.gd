extends PhysicsTest

## Carrosserie qui se cabosse et pieces qui partent (2026-10-06 : « que la
## remorque se deforme quand elle prend des degats. Pareil pour la tete du
## camion. Que des bouts partent »). SAUTE si les modeles sont absents (clone
## sans Git LFS).
##
##   A. de face dans un mur a 20 m/s : la calandre s'enfonce d'au moins
##      MIN_DENT, des pieces avant s'arrachent (cachees sur le camion, debris
##      sur la route) ;
##   B. en marche arriere a 12 m/s, la citerne frappe le mur : elle se
##      cabosse aussi (maillage subdivise : aucune arete > MAX_EDGE) ;
##   C. le creux ne fend pas la tole : deux sommets confondus avant le choc
##      (aretes vives, coutures) le restent apres ;
##   D. reapparition : camion neuf, aucune bosse, toutes ses pieces ;
##   E. cout : un choc de plus sur une carrosserie deja copiee reste sous
##      MAX_DENT_MS (pas d'a-coup en course) ;
##   F. tole fatiguee (2026-10-07, « plus on tape sur une paroi, plus elle se
##      deforme, en s'enfoncant ») : quatre coups identiques au meme endroit
##      de la citerne - chacun creuse plus que le precedent, le quatrieme au
##      moins 1,5 fois plus que le premier.

const MIN_DENT := 0.15
const MAX_DENT_MS := 25.0

var _a: Truck
var _b: Truck
var _ok: bool = false
var _a_dent: float = 0.0
var _a_hidden: int = 0
var _a_debris: int = 0
var _b_dent: float = 0.0
var _b_long_edge: float = 0.0
var _b_crack: float = 0.0
var _restored: Array = []
var _ms: float = 0.0
var _first_ms: float = 0.0
var _prewarm_ms: float = 0.0
## F : profondeur du creux apres chaque coup (m).
var _steps: PackedFloat32Array = []


func _test_setup() -> void:
	duration_ticks = 150
	TruckVisual.load_external_in_headless = true
	add_floor(600.0)
	_a = _spawn(Vector3(0.0, 0.0, 0.0), 20.0)
	_wall(Vector3(30.0, 6.0, 2.0), Vector3(0.0, 3.0, -30.0))
	_b = _spawn(Vector3(60.0, 0.0, 0.0), -12.0)
	_wall(Vector3(30.0, 6.0, 2.0), Vector3(60.0, 3.0, 30.0))
	for t: Truck in [_a, _b]:
		var v := t.get_node("Visual") as TruckVisual
		if not v.model_loaded:
			skip("modele externe absent (%s)" % v.external_model)
			return
		var type := load("res://vehicles/trailers/citerne.tres") as TrailerType
		t.set_trailer_type(type)
		v.set_trailer_type(type)
		if v.get_trailer_skin() == null:
			skip("modele de remorque absent (%s)" % type.model)
			return
	var t0 := Time.get_ticks_usec()
	for t: Truck in [_a, _b]:
		BodyDamage.prewarm(t.get_node("Visual") as Node3D)
	_prewarm_ms = (Time.get_ticks_usec() - t0) / 1000.0
	_ok = true


func _spawn(pos: Vector3, speed: float) -> Truck:
	var t := TruckTestUtil.spawn_truck(self, pos)
	t.linear_velocity = -t.global_basis.z * speed
	return t


func _wall(size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	body.position = pos
	add_child(body)


func _test_tick(t: int) -> void:
	if not _ok or t != 120:
		return
	var va := _a.get_node("Visual") as TruckVisual
	var vb := _b.get_node("Visual") as TruckVisual
	_a_dent = _max_dent(va.mark_parent(false))
	for n in va.find_children("*", "MeshInstance3D", true, false):
		if n.has_meta(BodyDamage.META_DETACHED) and not (n as MeshInstance3D).visible:
			_a_hidden += 1
	_a_debris = Debris.alive_count()
	var tank := vb.get_trailer_skin()
	_b_dent = _max_dent(tank)
	_b_long_edge = _longest_dented_edge(tank)
	_b_crack = _crack(tank)
	# E : un choc de plus, carrosserie deja copiee
	var fx := _b.get_node("DamageFx") as TruckDamageFx
	var at := _b.global_transform * Vector3(1.5, 3.0, 9.0)
	var t_first := Time.get_ticks_usec()
	fx.crush(at, -_b.global_basis.x, 15.0, true)
	_first_ms = (Time.get_ticks_usec() - t_first) / 1000.0
	var t0 := Time.get_ticks_usec()
	fx.crush(at, -_b.global_basis.x, 15.0, true)
	_ms = (Time.get_ticks_usec() - t0) / 1000.0
	# F : quatre coups identiques au meme endroit, cote gauche de la citerne
	var spot := _b.global_transform * Vector3(-1.5, 3.2, 6.0)
	for k in 4:
		fx.crush(spot, _b.global_basis.x, 4.0, true)
		_steps.append(_dent_near(tank, spot, 1.2))
	# D : reapparition
	(_a.get_node("DamageFx") as TruckDamageFx).clear_all()
	var hidden := 0
	for n in va.find_children("*", "MeshInstance3D", true, false):
		if not (n as MeshInstance3D).visible and n.has_meta(BodyDamage.META_DETACHED):
			hidden += 1
	_restored = [BodyDamage.dented_instances(va), hidden]


## Plus grand deplacement d'un sommet depuis le neuf, sous `root` (m, monde).
func _max_dent(root: Node3D) -> float:
	var best := 0.0
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.has_meta(BodyDamage.META_PRISTINE):
			continue
		var ref := BodyDamage.tessellated(mi.get_meta(BodyDamage.META_PRISTINE) as Mesh)
		var s := absf(mi.global_basis.get_scale().x)
		for k in mi.mesh.get_surface_count():
			var now: PackedVector3Array = mi.mesh.surface_get_arrays(k)[Mesh.ARRAY_VERTEX]
			var was: PackedVector3Array = ref.surface_get_arrays(k)[Mesh.ARRAY_VERTEX]
			for i in mini(now.size(), was.size()):
				best = maxf(best, now[i].distance_to(was[i]) * s)
	return best


## Plus grand deplacement d'un sommet a moins de `reach` de `point` (m, monde).
func _dent_near(root: Node3D, point: Vector3, reach: float) -> float:
	var best := 0.0
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.has_meta(BodyDamage.META_PRISTINE):
			continue
		var ref := BodyDamage.tessellated(mi.get_meta(BodyDamage.META_PRISTINE) as Mesh)
		var xf := mi.global_transform
		for k in mi.mesh.get_surface_count():
			var now: PackedVector3Array = mi.mesh.surface_get_arrays(k)[Mesh.ARRAY_VERTEX]
			var was: PackedVector3Array = ref.surface_get_arrays(k)[Mesh.ARRAY_VERTEX]
			for i in mini(now.size(), was.size()):
				var w := xf * was[i]
				if w.distance_to(point) < reach:
					best = maxf(best, w.distance_to(xf * now[i]))
	return best


## Plus longue arete (non deformee) des maillages cabosses sous `root`.
func _longest_dented_edge(root: Node3D) -> float:
	var best := 0.0
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.has_meta(BodyDamage.META_PRISTINE):
			continue
		var ref := BodyDamage.tessellated(mi.get_meta(BodyDamage.META_PRISTINE) as Mesh)
		for k in ref.get_surface_count():
			var arr := ref.surface_get_arrays(k)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			for t in idx.size() / 3:
				for e in 3:
					best = maxf(best, v[idx[t * 3 + e]].distance_to(v[idx[t * 3 + (e + 1) % 3]]))
	return best


## Plus grand ecart entre deux sommets confondus avant le choc (m) : une fente.
func _crack(root: Node3D) -> float:
	var worst := 0.0
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.has_meta(BodyDamage.META_PRISTINE):
			continue
		var ref := BodyDamage.tessellated(mi.get_meta(BodyDamage.META_PRISTINE) as Mesh)
		var groups: Dictionary = {}
		var positions: Array[PackedVector3Array] = []
		for k in ref.get_surface_count():
			var was: PackedVector3Array = ref.surface_get_arrays(k)[Mesh.ARRAY_VERTEX]
			positions.append(mi.mesh.surface_get_arrays(k)[Mesh.ARRAY_VERTEX])
			for i in was.size():
				var key := Vector3i(roundi(was[i].x * 1e4), roundi(was[i].y * 1e4), roundi(was[i].z * 1e4))
				if groups.has(key):
					var first: Vector2i = groups[key]
					worst = maxf(worst, positions[first.x][first.y].distance_to(positions[k][i]))
				else:
					groups[key] = Vector2i(k, i)
	return worst


func _test_finish() -> void:
	TruckVisual.load_external_in_headless = false
	if not _ok:
		return
	print("  INFO   A : creux %.2f m, %d pieces arrachees, %d debris ; B : creux %.2f m, arete max %.2f m, fente %.4f m ; preparation %.0f ms, premier choc %.1f ms, choc de plus %.1f ms"
		% [_a_dent, _a_hidden, _a_debris, _b_dent, _b_long_edge, _b_crack, _prewarm_ms, _first_ms, _ms])
	check_above("A la tete se cabosse (m)", _a_dent, MIN_DENT)
	check_above("A des pieces s'arrachent", _a_hidden, 0)
	check_above("A des debris sur la route", _a_debris, 0)
	check_above("B la remorque se cabosse (m)", _b_dent, MIN_DENT)
	check_below("B maillage subdivise : arete max (m)", _b_long_edge, BodyDamage.MAX_EDGE + 0.001)
	check_below("C aucune fente (m)", _b_crack, 0.001)
	check("D reapparition : aucune bosse, aucune piece manquante", _restored == [0, 0], str(_restored))
	check_below("E choc de plus (ms)", _ms, MAX_DENT_MS)
	var gains := PackedFloat32Array()
	var prev := 0.0
	for d in _steps:
		gains.append(d - prev)
		prev = d
	var deeper := gains.size() == 4
	for k in range(1, gains.size()):
		deeper = deeper and gains[k] > gains[k - 1]
	check("F tole fatiguee : chaque coup au meme endroit creuse plus que le precedent", deeper
		and gains[3] > gains[0] * 1.5, "creux %s m" % [_steps])
