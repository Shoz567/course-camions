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
## pour lui aussi - qui l'abime, sans etre penalise (2026-10-01, « je passe a
## travers ma propre remorque ») ; jamais tant qu'il est dedans : le solveur
## les separerait d'un coup. Durees en ticks physiques (CLAUDE.md §7).
##
## Repere : origine a la sellette (comme le pivot visuel de la remorque),
## avant du camion en -Z, remorque vers +Z.

## Un camion vient de la percuter (adversaire, ou son proprietaire plus tard).
signal truck_hit(truck: Truck)
## Elle vient de perdre `amount` PV (il lui en reste `hp`).
signal damaged(amount: float, hp: float)
## A 0 PV : elle explose et disparait.
signal destroyed

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

## Camion qui l'a larguee : jamais penalise ; ne la heurte pas au debut.
var dropped_by: Truck
var age_ticks: int = 0
var hp: float = 50.0
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
	# boite pleine hauteur : du sol (roues comprises) au toit de la caisse
	var top := TruckSpec.TRAILER_CENTER.y + TruckSpec.TRAILER_SIZE.y / 2.0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(TruckSpec.TRAILER_SIZE.x, top, TruckSpec.TRAILER_SIZE.z)
	cs.shape = box
	cs.position = Vector3(0.0, top / 2.0 - TruckSpec.KINGPIN.y, TruckSpec.TRAILER_CENTER.z - TruckSpec.KINGPIN.z)
	add_child(cs)
	_shape = cs


## Visuel de la remorque (copie du camion, repere de la sellette).
func set_visual(v: Node3D) -> void:
	if v == null:
		return
	_visual = v
	add_child(v)


func _ready() -> void:
	mass = trailer_mass
	hp = max_hp
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
		if now - last > hit_gap_ticks:
			_pending[truck] = maxf(float(_pending.get(truck, 0.0)), approach)
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
			_on_truck_hit(key as Truck, float(_pending[key]))
	_pending.clear()
	if hp <= 0.0:
		ExplosionFx.spawn(get_parent(), _shape.global_position, 9.0)
		destroyed.emit()
		queue_free()


## Choc d'un camion : PV retires selon l'energie ; un adversaire est penalise.
func _on_truck_hit(truck: Truck, approach_ms: float) -> void:
	truck_hit.emit(truck)
	if truck != dropped_by:
		truck.cargo_hit(global_position)
	var amount := damage_for(approach_ms)
	if amount <= 0.0 or hp <= 0.0:
		return
	hp = maxf(0.0, hp - amount)
	damaged.emit(amount, hp)


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
