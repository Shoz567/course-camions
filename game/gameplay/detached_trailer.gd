class_name DetachedTrailer
extends RigidBody3D

## Remorque larguee (pouvoir cargo, Triangle) : la remorque entiere reste sur
## la route et fait barrage, sans limite de temps (2026-10-02 : plus de
## disparition au bout de 60 s). Corps lourd et freine (il glisse un peu, puis
## tient la place), boite pleine hauteur posee au sol, sur la couche 5
## `hazard` (VEHICLE_SPEC §7) : les camions la percutent, les rayons de
## suspension et les zones de la piste l'ignorent.
##
## 50 PV : chaque choc d'un camion lui en retire selon l'energie du choc
## (carre de la vitesse d'approche, le long de la normale de contact) ; a 0,
## elle explose et disparait. Un camion adverse qui la percute est ralenti et
## deporte (Truck.cargo_hit) ; un nouveau choc compte apres hit_gap_ticks sans
## contact avec ce camion. Le camion qui l'a larguee la traverse pendant
## owner_pass_ticks (le temps de s'en eloigner), puis elle devient un obstacle
## pour lui aussi - qui l'abime et s'y blesse comme les autres (TruckHealth,
## 2026-10-07), sans etre ralenti (2026-10-01, « je passe a
## travers ma propre remorque ») ; jamais tant qu'il est dedans : le solveur
## les separerait d'un coup. Durees en ticks physiques (CLAUDE.md §7).
##
## Degats visibles (2026-10-02, purement visuels) : chaque choc qui l'abime
## laisse une trace au point touche ; sous 60 % de ses PV, elle fume (gris) et
## ses flancs noircissent ; sous 30 %, fumee noire epaisse, etincelles, toit
## noirci ; a 0, elle explose.
##
## Repere : origine a la sellette (comme le pivot visuel de la remorque),
## avant du camion en -Z, remorque vers +Z.

## Un camion vient de la percuter (adversaire, ou son proprietaire plus tard).
signal truck_hit(truck: Truck)
## Elle vient de perdre `amount` PV (il lui en reste `hp`).
signal damaged(amount: float, hp: float)
## A 0 PV : elle explose et disparait.
signal destroyed
## Un choc qui l'abime : point et normale (monde), PV retires, vitesse
## d'approche (pour rejouer ses effets ailleurs : NetRace).
signal struck(at: Vector3, normal: Vector3, amount: float, approach_ms: float)

const HAZARD_LAYER := 5

@export var trailer_mass: float = 9000.0
## Ticks pendant lesquels le camion qui l'a larguee la traverse (~1 s).
@export var owner_pass_ticks: int = 60
@export var max_hp: float = 50.0
## Choc qui retire tous les PV d'un coup (vitesse d'approche le long de la
## normale, m/s) : 33 m/s, ~120 km/h de face. Les degats suivent le carre de
## la vitesse (l'energie) : de face a 100 km/h, ~35 PV ; a 60 km/h, ~13.
@export var full_damage_speed_ms: float = 33.0
## En dessous, un contact ne l'abime pas (pousser, frotter).
@export var min_damage_speed_ms: float = 4.0
## Sans contact avec un camion pendant ce temps, son prochain contact est un
## nouveau choc.
@export var hit_gap_ticks: int = 20

## Caisse de la remorque, repere du camion (TrailerType ; defaut : TruckSpec).
var box_size: Vector3 = TruckSpec.TRAILER_SIZE
var box_center: Vector3 = TruckSpec.TRAILER_CENTER
## Camion qui l'a larguee : jamais penalise ; ne la heurte pas au debut.
var dropped_by: Truck
var age_ticks: int = 0
var hp: float = 50.0
## PV au moment ou elle arrive sur la route (< 0 : max_hp). Une remorque deja
## abimee sur le camion le reste une fois larguee.
var initial_hp: float = -1.0
var _visual: Node3D
var _shape: CollisionShape3D
var _owner_query: PhysicsShapeQueryParameters3D
## Camion -> dernier tick de contact ; chocs releves pendant le pas (vitesse
## d'approche), traites au tick suivant.
var _last_contact: Dictionary = {}
var _pending: Dictionary = {}
## Vitesses de la remorque au debut des trois derniers pas, la plus recente en
## tete (comme Truck.get_recent_velocities) : avant le choc, elle etait
## immobile ; apres, elle file deja avec le camion qui l'a poussee.
var _vel_hist: PackedVector3Array = PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
## Point et normale (monde) du contact le plus violent de chaque choc en attente.
var _pending_at: Dictionary = {}
var _smoke: GPUParticles3D
var _sparks: GPUParticles3D
## Etat visible : 0 neuve, 1 abimee (< 60 %), 2 en ruine (< 30 %).
var damage_stage: int = 0
var _marks: Array[Node3D] = []
## En ligne, chez un client (NetRace) : posee par le host, qui fait foi. Gelee
## en cinematique (sa pose arrive par les snapshots), elle ne compte aucun
## choc ; chocs et explosion du host sont rejoues (net_hit, net_destroy).
var net_mirror: bool = false:
	set(value):
		net_mirror = value
		if value:
			freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			freeze = true
const MAX_MARKS := 10


func _init() -> void:
	name = "DetachedTrailer"
	mass = trailer_mass
	collision_layer = 1 << (HAZARD_LAYER - 1)
	collision_mask = (1 << (TruckSpec.LAYER_WORLD - 1)) | (1 << (TruckSpec.LAYER_VEHICLE - 1))
	contact_monitor = true
	max_contacts_reported = 8
	# jamais endormie : un choc doit toujours etre releve (_integrate_forces)
	can_sleep = false
	continuous_cd = true
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 1.2
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 3.0
	var pm := PhysicsMaterial.new()
	pm.friction = 1.0
	pm.bounce = 0.0
	physics_material_override = pm
	var cs := CollisionShape3D.new()
	cs.shape = BoxShape3D.new()
	add_child(cs)
	_shape = cs
	_shape_box()


## Remorque choisie par le joueur : caisse, PV et masse. Avant add_child.
func configure(type: TrailerType) -> void:
	if type == null:
		return
	box_size = type.box_size
	box_center = type.box_center
	trailer_mass = type.dropped_mass_kg
	max_hp = type.dropped_hp
	_shape_box()


## Boite pleine hauteur : du sol (roues comprises) au toit de la caisse.
func _shape_box() -> void:
	var top := box_center.y + box_size.y / 2.0
	var box := _shape.shape as BoxShape3D
	box.size = Vector3(box_size.x, top, box_size.z)
	_shape.position = Vector3(0.0, top / 2.0 - TruckSpec.KINGPIN.y, box_center.z - TruckSpec.KINGPIN.z)


## Visuel de la remorque (copie du camion, repere de la sellette).
func set_visual(v: Node3D) -> void:
	if v == null:
		return
	_visual = v
	add_child(v)


## Obstacles laisses sur la route (remorques larguees, carcasses) : les bots
## les evitent (BotInputSource).
const OBSTACLES := &"road_obstacles"


func _ready() -> void:
	add_to_group(OBSTACLES)
	mass = trailer_mass
	hp = max_hp if initial_hp < 0.0 else clampf(initial_hp, 1.0, max_hp)
	var center := _shape.position
	_smoke = DamageFx.make_smoke()
	_smoke.position = center + Vector3(0.0, 2.0, 0.0)
	add_child(_smoke)
	# origine au ras du sol : les etincelles rebondissent sur la route
	_sparks = DamageFx.make_sparks(maxf(center.y - 0.5, 0.2))
	_sparks.position = center + Vector3(0.0, -0.5, 0.0)
	add_child(_sparks)
	if dropped_by != null:
		add_collision_exception_with(dropped_by)
		_owner_query = PhysicsShapeQueryParameters3D.new()
		_owner_query.shape = _shape.shape
		_owner_query.collision_mask = 1 << (TruckSpec.LAYER_VEHICLE - 1)
		_owner_query.exclude = [get_rid()]


## Degats d'un choc a cette vitesse d'approche (m/s).
func damage_for(approach_ms: float) -> float:
	if approach_ms < min_damage_speed_ms:
		return 0.0
	return max_hp * pow(approach_ms / full_damage_speed_ms, 2.0)


## Contacts du pas : pour chaque camion qui la touche, vitesse d'approche le
## long de la normale, AVANT le choc : vitesses des deux corps au debut d'un
## meme pas recent (la plus forte des trois).
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var now := Engine.get_physics_frames()
	for i in state.get_contact_count():
		var truck := state.get_contact_collider_object(i) as Truck
		if truck == null:
			continue
		var n := state.get_contact_local_normal(i)
		var approach := 0.0
		var truck_hist := truck.get_recent_velocities()
		for k in 3:
			approach = maxf(approach, absf((truck_hist[k] - _vel_hist[k]).dot(n)))
		var last: int = _last_contact.get(truck, -100000)
		if now - last > hit_gap_ticks and approach >= float(_pending.get(truck, -1.0)):
			_pending[truck] = approach
			_pending_at[truck] = [state.get_contact_local_position(i), n]
		_last_contact[truck] = now


func _physics_process(_delta: float) -> void:
	age_ticks += 1
	_vel_hist[2] = _vel_hist[1]
	_vel_hist[1] = _vel_hist[0]
	_vel_hist[0] = linear_velocity
	if _owner_query != null and age_ticks >= owner_pass_ticks:
		_update_owner_collision()
	for key: Variant in _pending:
		if is_instance_valid(key):
			_on_truck_hit(key as Truck, float(_pending[key]), _pending_at.get(key, []))
	_pending.clear()
	_pending_at.clear()
	if hp <= 0.0 and not net_mirror:
		_explode()


func _explode() -> void:
	ExplosionFx.spawn(get_parent(), _shape.global_position, 9.0)
	BodyDamage.shards(get_parent(), _shape.global_position, Vector3.UP, 14, linear_velocity, 14.0,
		BodyDamage.nearest_material(_visual, _shape.global_position), get_instance_id())
	destroyed.emit()
	queue_free()


## Client en ligne : choc decide par le host (PV restants left).
func net_hit(at: Vector3, normal: Vector3, amount: float, approach_ms: float, left: float) -> void:
	hp = left
	damaged.emit(amount, hp)
	_hit_effects(at, normal, amount, approach_ms)


## Client en ligne : detruite chez le host.
func net_destroy() -> void:
	if not is_queued_for_deletion():
		_explode()


## Choc d'un camion : PV retires selon l'energie ; un adversaire est penalise ;
## trace au point touche, fumee et suie selon les PV restants.
func _on_truck_hit(truck: Truck, approach_ms: float, contact: Array) -> void:
	truck_hit.emit(truck)
	if truck != dropped_by:
		truck.cargo_hit(global_position)
	var amount := damage_for(approach_ms)
	if amount <= 0.0 or hp <= 0.0:
		return
	hp = maxf(0.0, hp - amount)
	damaged.emit(amount, hp)
	if contact.size() == 2:
		var at: Vector3 = contact[0]
		var n: Vector3 = contact[1]
		# normale sortante de la remorque : vers le camion qui l'a frappee
		if n.dot(truck.global_position - at) < 0.0:
			n = -n
		struck.emit(at, n, amount, approach_ms)
		_hit_effects(at, n, amount, approach_ms)
	else:
		_update_damage_stage()


## Trace au point touche, tole enfoncee, eclats, fumee selon les PV (visuel).
func _hit_effects(at: Vector3, n: Vector3, amount: float, approach_ms: float) -> void:
	_add_mark(at, n, clampf(amount / 25.0, 0.2, 1.0))
	# la tole s'enfonce, des eclats volent (purement visuel)
	var severity := clampf(approach_ms / full_damage_speed_ms, 0.0, 1.0)
	BodyDamage.dent(_visual, at, -n * lerpf(0.12, 0.7, severity), lerpf(0.9, 2.4, severity))
	if severity > 0.35:
		BodyDamage.shards(get_parent(), at, n, roundi(severity * 6.0), linear_velocity, 6.0 + 8.0 * severity,
			BodyDamage.nearest_material(_visual, at), age_ticks)
	_update_damage_stage()


## Trace de choc au point monde `at`, la carrosserie regardant vers `outward`.
func _add_mark(at: Vector3, outward: Vector3, severity: float) -> void:
	var parent: Node3D = _visual if _visual != null else self
	_marks.append(DamageFx.scar(parent, at, outward, severity))
	if _marks.size() > MAX_MARKS:
		var old: Node3D = _marks.pop_front()
		if is_instance_valid(old):
			old.queue_free()


## Fumee et suie selon les PV : abimee sous 60 %, en ruine sous 30 %.
func _update_damage_stage() -> void:
	var ratio := hp / maxf(max_hp, 1.0)
	var stage := 2 if ratio < 0.3 else (1 if ratio < 0.6 else 0)
	if stage <= damage_stage:
		return
	var c := _shape.global_position
	var b := _shape.global_basis
	var half := box_size / 2.0
	if stage >= 1 and damage_stage < 1:
		# flancs noircis
		for side: float in [-1.0, 1.0]:
			_add_mark(c + b.x * side * half.x, b.x * side, 0.9)
	if stage >= 2:
		_add_mark(c + b.y * half.y, b.y, 1.0)
		_add_mark(c - b.z * half.z * 0.5 + b.x * half.x, b.x, 1.0)
	damage_stage = stage
	DamageFx.set_smoke(_smoke, DamageFx.Smoke.LIGHT if stage == 1 else DamageFx.Smoke.HEAVY)
	_sparks.emitting = stage == 2


func is_smoking() -> bool:
	return _smoke != null and _smoke.emitting


func mark_count() -> int:
	return _marks.size()


## Le camion qui l'a larguee la percute desormais, une fois sorti de son
## volume (sinon : nouvel essai au tick suivant).
func _update_owner_collision() -> void:
	if not is_instance_valid(dropped_by):
		_owner_query = null
		return
	_owner_query.transform = _shape.global_transform
	for h: Dictionary in get_world_3d().direct_space_state.intersect_shape(_owner_query, 8):
		if h["collider"] == dropped_by:
			return
	remove_collision_exception_with(dropped_by)
	_owner_query = null


## Vrai quand elle fait obstacle aussi au camion qui l'a larguee.
func is_solid_for_owner() -> bool:
	return dropped_by != null and _owner_query == null and is_instance_valid(dropped_by)
