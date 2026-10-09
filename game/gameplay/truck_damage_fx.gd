class_name TruckDamageFx
extends Node3D

## Degats visibles du camion (enfant « DamageFx », purement visuel) :
##   - traces de choc localisees : a chaque impact (mur, camion, remorque
##     larguee), un decalque (DamageFx.make_mark) au point touche - calandre
##     sur un choc frontal, flanc sur un frottement, remorque sur un choc
##     arriere (il suit alors l'articulation, et part avec la remorque si elle
##     est larguee). Au plus MAX_MARKS sur le tracteur, MAX_TRAILER_MARKS sur
##     la remorque : les plus anciennes s'effacent ;
##   - fumee moteur selon les PV (TruckHealth) : rien au-dessus de 70 PV,
##     grise legere de 70 a 30, noire epaisse et etincelles sous 30, fumee
##     d'epave pendant les 3 s avant la reapparition ;
##   - un camion qui reapparait est neuf (traces effacees) ; une nouvelle
##     remorque aussi.

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


func _on_body_impact(speed: float, on_trailer: bool, point: Vector3, normal: Vector3) -> void:
	if speed >= MIN_BODY_MARK_SPEED:
		add_mark(point, -normal, clampf((speed - 1.0) / 16.0, 0.15, 1.0), on_trailer)


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


## Destruction : la cabine est noircie de toutes parts.
func _on_destroyed() -> void:
	var xf := _truck.global_transform
	for side: Vector3 in [Vector3(0.0, 0.0, -1.0), Vector3(1.0, 0.0, 0.0), Vector3(-1.0, 0.0, 0.0), Vector3.UP]:
		var at := TruckSpec.CAB_CENTER + side * (TruckSpec.CAB_SIZE / 2.0)
		add_mark(xf * at, xf.basis * side, 1.0, false)
	refresh()


func clear_trailer_marks() -> void:
	for d in _trailer_marks:
		if is_instance_valid(d):
			d.queue_free()
	_trailer_marks.clear()


## Camion neuf (reapparition) : plus aucune trace, plus de fumee.
func clear_all() -> void:
	for d in _marks:
		if is_instance_valid(d):
			d.queue_free()
	_marks.clear()
	clear_trailer_marks()
	refresh()
