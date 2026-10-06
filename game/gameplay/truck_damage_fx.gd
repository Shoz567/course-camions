class_name TruckDamageFx
extends Node3D

## Degats visibles du camion (enfant « DamageFx », purement visuel) :
##   - traces de choc localisees : a chaque impact (mur, camion, remorque
##     larguee), un decalque (DamageFx.make_mark) au point touche - calandre
##     sur un choc frontal, flanc sur un frottement, remorque sur un choc
##     arriere (il suit alors l'articulation, et part avec la remorque si elle
##     est larguee). Au plus MAX_MARKS sur le tracteur, MAX_TRAILER_MARKS sur
##     la remorque : les plus anciennes s'effacent ;
##   - carrosserie cabossee (BodyDamage, 2026-10-06) : la tole s'enfonce au
##     point touche, d'autant plus que le choc est violent ; au-dela de
##     PART_SPEED, les pieces exterieures proches s'arrachent (retros, phares,
##     pare-chocs...) et des eclats de tole volent. A l'explosion de la tete ou
##     de la remorque, tout ce qui depasse part ;
##   - fumee moteur selon les PV (TruckHealth) : rien au-dessus de 70 PV,
##     grise legere de 70 a 30, noire epaisse et etincelles sous 30, fumee
##     d'epave pendant les 3 s avant la reapparition ;
##   - un camion qui reapparait est neuf (traces et bosses effacees, pieces
##     remises) ; une nouvelle remorque aussi.

const MAX_MARKS := 10
const MAX_TRAILER_MARKS := 8
## Seuils de la fumee moteur (PV).
const LIGHT_SMOKE_HP := 70.0
const HEAVY_SMOKE_HP := 30.0
## Compartiment moteur, sous la cabine : la fumee sort de la calandre et
## monte devant le pare-brise (repere du camion).
const ENGINE_POS := Vector3(0.0, 1.5, -3.7)
## En dessous, un contact avec un autre corps ne laisse pas de trace (m/s).
const MIN_BODY_MARK_SPEED := 3.0
## Bosses : a partir de DENT_SPEED (m/s vers l'obstacle), pleines a HARD_SPEED ;
## pieces arrachees et eclats au-dela de PART_SPEED.
const DENT_SPEED := 2.5
const HARD_SPEED := 20.0
const PART_SPEED := 9.0
## Pieces exterieures arrachees par une explosion.
const EXPLOSION_PARTS := 24

var _truck: Truck
var _health: TruckHealth
var _visual: TruckVisual
var _marks: Array[Decal] = []
var _trailer_marks: Array[Decal] = []
var _smoke: CPUParticles3D
var _sparks: CPUParticles3D
var _level: int = DamageFx.Smoke.NONE


## Niveau de fumee pour ces PV (DamageFx.Smoke).
static func smoke_level_for(hp: float, wrecked: bool) -> int:
	if wrecked:
		return DamageFx.Smoke.WRECK
	if hp > LIGHT_SMOKE_HP:
		return DamageFx.Smoke.NONE
	if hp >= HEAVY_SMOKE_HP:
		return DamageFx.Smoke.LIGHT
	return DamageFx.Smoke.HEAVY


func _ready() -> void:
	_truck = get_parent() as Truck
	if _truck == null:
		return
	_health = TruckHealth.of(_truck)
	_visual = _truck.get_node_or_null(^"Visual") as TruckVisual
	_smoke = DamageFx.make_smoke()
	_smoke.position = ENGINE_POS
	add_child(_smoke)
	_sparks = DamageFx.make_sparks()
	_sparks.position = ENGINE_POS + Vector3(0.0, -0.6, -0.2)
	add_child(_sparks)
	_truck.wall_impact_at.connect(_on_impact)
	_truck.body_impact.connect(_on_body_impact)
	_truck.trailer_reattached.connect(clear_trailer_marks)
	if _health != null:
		_health.damaged.connect(_on_damaged)
		_health.destroyed.connect(_on_destroyed)
		_health.trailer_destroyed.connect(_on_trailer_destroyed)
		_health.respawned.connect(clear_all)


func _process(_delta: float) -> void:
	refresh()


## Met la fumee au niveau des PV courants.
func refresh() -> void:
	if _health == null:
		return
	var level := smoke_level_for(_health.hp, _health.is_wrecked())
	if level == _level:
		return
	_level = level
	DamageFx.set_smoke(_smoke, level)
	_sparks.emitting = level == DamageFx.Smoke.HEAVY or level == DamageFx.Smoke.WRECK


func smoke_level() -> int:
	return _level


func is_smoking() -> bool:
	return _smoke != null and _smoke.emitting


func is_sparking() -> bool:
	return _sparks != null and _sparks.emitting


## Traces de choc posees (tracteur, ou remorque attachee).
func marks(on_trailer: bool = false) -> Array[Decal]:
	return _trailer_marks if on_trailer else _marks


func _on_impact(speed: float, on_trailer: bool, point: Vector3, normal: Vector3) -> void:
	add_mark(point, -normal, clampf((speed - 1.0) / 16.0, 0.1, 1.0), on_trailer)
	crush(point, normal, speed, on_trailer)


func _on_body_impact(speed: float, on_trailer: bool, point: Vector3, normal: Vector3) -> void:
	if speed >= MIN_BODY_MARK_SPEED:
		add_mark(point, -normal, clampf((speed - 1.0) / 16.0, 0.15, 1.0), on_trailer)
		crush(point, normal, speed, on_trailer)


## Choc a `speed` (m/s) au point `point`, `normal` tournee vers le camion :
## la tole s'enfonce dans le sens du choc (creux de 3 a 45 cm, sur 0,7 a
## 1,9 m), et au-dela de PART_SPEED les pieces proches s'arrachent et des
## eclats volent. Purement visuel.
func crush(point: Vector3, normal: Vector3, speed: float, on_trailer: bool) -> void:
	if _visual == null or speed < DENT_SPEED:
		return
	var root := _visual.mark_parent(on_trailer)
	point = _on_body(point, normal, on_trailer)
	var sev := clampf((speed - DENT_SPEED) / (HARD_SPEED - DENT_SPEED), 0.0, 1.0)
	BodyDamage.dent(root, point, normal * lerpf(0.03, 0.45, sev), lerpf(0.7, 1.9, sev))
	if speed < PART_SPEED:
		return
	var world := _truck.get_parent()
	BodyDamage.detach_parts(root, world, point, lerpf(1.2, 2.2, sev), 1 + roundi(sev * 2.0),
		_truck.linear_velocity * 0.85, 3.0 + 5.0 * sev)
	BodyDamage.shards(world, point, -normal, 2 + roundi(sev * 4.0), _truck.linear_velocity * 0.85,
		4.0 + 6.0 * sev, BodyDamage.nearest_material(root, point), Engine.get_physics_frames())


## Point de contact ramene sur la carrosserie : une boite de collision touche
## un mur plat par ses coins (au ras du sol, ou au bord du toit), loin de la
## tole. Il glisse vers le milieu de la face touchee, dans le repere de la
## caisse (tracteur, ou remorque articulee).
func _on_body(point: Vector3, normal: Vector3, on_trailer: bool) -> Vector3:
	var frame := _truck.global_transform
	var half := Vector3(1.35, 0.0, 0.0)
	var y_range := Vector2(1.0, 3.4)
	if on_trailer:
		frame = frame * Truck.trailer_local_transform(_truck.get_trailer_angle(), _truck.trailer_box_center)
		half = _truck.trailer_box_size / 2.0
		# caisse ronde ou ajouree (citerne, plateau) : vers le coeur de la face
		y_range = Vector2(-half.y, half.y) * 0.3
		half.x *= 0.5
	var p := frame.affine_inverse() * point
	# la face touchee garde sa profondeur : seules les deux autres directions
	# sont ramenees vers le milieu
	var n := (frame.basis.inverse() * normal).abs()
	if n.x < maxf(n.y, n.z):
		p.x = clampf(p.x, -half.x, half.x)
	if n.y < maxf(n.x, n.z):
		p.y = clampf(p.y, y_range.x, y_range.y)
	return frame * p


## Pose une trace au point monde `point`, la carrosserie regardant vers
## `outward` (monde). Sur la remorque : accrochee a son pivot.
func add_mark(point: Vector3, outward: Vector3, severity: float, on_trailer: bool) -> Decal:
	var parent: Node3D = self
	if _visual != null:
		parent = _visual.mark_parent(on_trailer)
	var d := DamageFx.make_mark(severity)
	var inv := parent.global_transform.affine_inverse()
	DamageFx.place_mark(d, inv * point, inv.basis * outward)
	parent.add_child(d)
	var list := _trailer_marks if on_trailer else _marks
	list.append(d)
	if list.size() > (MAX_TRAILER_MARKS if on_trailer else MAX_MARKS):
		var old: Decal = list.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	return d


## Baril : brulure sur le bas de caisse avant.
func _on_damaged(_amount: float, source: StringName) -> void:
	if source == &"baril":
		var xf := _truck.global_transform
		add_mark(xf * Vector3(0.0, 1.0, -3.6), xf.basis * Vector3(0.0, -0.2, -1.0), 0.8, false)


## Destruction : la cabine est noircie de toutes parts, enfoncee, et les
## pieces exterieures volent avec des eclats de tole.
func _on_destroyed() -> void:
	var xf := _truck.global_transform
	for side: Vector3 in [Vector3(0.0, 0.0, -1.0), Vector3(1.0, 0.0, 0.0), Vector3(-1.0, 0.0, 0.0), Vector3.UP]:
		var at := TruckSpec.CAB_CENTER + side * (TruckSpec.CAB_SIZE / 2.0)
		add_mark(xf * at, xf.basis * side, 1.0, false)
		if _visual != null:
			BodyDamage.dent(_visual.mark_parent(false), xf * at, xf.basis * -side * 0.35, 1.6)
	if _visual != null:
		var world := _truck.get_parent()
		var c := xf * TruckSpec.CAB_CENTER
		BodyDamage.detach_parts(_visual.mark_parent(false), world, c, 8.0, EXPLOSION_PARTS,
			_truck.linear_velocity, 11.0)
		BodyDamage.shards(world, c, Vector3.UP, 10, _truck.linear_velocity, 13.0,
			BodyDamage.nearest_material(_visual.mark_parent(false), c), Engine.get_physics_frames())
	refresh()


## Remorque attelee detruite (TruckHealth) : elle vole en eclats - ses pieces
## exterieures et des plaques de tole de sa couleur.
func _on_trailer_destroyed(at: Vector3) -> void:
	if _visual == null:
		return
	var root := _visual.mark_parent(true)
	var world := _truck.get_parent()
	var mat := BodyDamage.nearest_material(root, at)
	BodyDamage.detach_parts(root, world, at, 12.0, EXPLOSION_PARTS, _truck.linear_velocity, 12.0)
	BodyDamage.shards(world, at, Vector3.UP, 18, _truck.linear_velocity, 15.0, mat, Engine.get_physics_frames())


## Nouvelle remorque : neuve (ni traces, ni bosses).
func clear_trailer_marks() -> void:
	for d in _trailer_marks:
		if is_instance_valid(d):
			d.queue_free()
	_trailer_marks.clear()
	if _visual != null:
		BodyDamage.restore(_visual.mark_parent(true))


## Camion neuf (reapparition) : plus aucune trace, aucune bosse, toutes ses
## pieces, plus de fumee.
func clear_all() -> void:
	for d in _marks:
		if is_instance_valid(d):
			d.queue_free()
	_marks.clear()
	clear_trailer_marks()
	if _visual != null:
		BodyDamage.restore(_visual)
	refresh()
