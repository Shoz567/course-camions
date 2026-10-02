class_name DetachedTrailer
extends RigidBody3D

## Remorque larguee (pouvoir cargo, Triangle) : la remorque entiere reste sur
## la route pendant lifetime_ticks (60 s) et fait barrage. Corps lourd et
## freine (il glisse un peu, puis tient la place), boite pleine hauteur posee
## au sol, sur la couche 5 `hazard` (VEHICLE_SPEC §7) : les camions la
## percutent, les rayons de suspension et les zones de la piste l'ignorent.
## Un camion adverse qui la percute est ralenti et deporte (Truck.cargo_hit),
## une fois. Le camion qui l'a larguee la traverse pendant owner_pass_ticks
## (le temps de s'en eloigner), puis elle devient un obstacle pour lui aussi,
## sans le penaliser (2026-10-01, « je passe a travers ma propre remorque ») ;
## jamais tant qu'il est dedans : le solveur les separerait d'un coup. Elle clignote pendant les
## deux dernieres secondes puis disparait : la remorque se raccroche alors au
## tracteur (TruckCargo). Duree comptee en ticks physiques (CLAUDE.md §7).
##
## Repere : origine a la sellette (comme le pivot visuel de la remorque),
## avant du camion en -Z, remorque vers +Z.

## Un camion adverse vient de la percuter.
signal truck_hit(truck: Truck)
## Fin de vie : elle va disparaitre.
signal expired

const HAZARD_LAYER := 5

@export var lifetime_ticks: int = 600
## Clignotement pendant les dernieres secondes, plus rapide a la fin.
@export var blink_ticks: int = 120
@export var trailer_mass: float = 9000.0
## Ticks pendant lesquels le camion qui l'a larguee la traverse (~1 s).
@export var owner_pass_ticks: int = 60

## Camion qui l'a larguee : jamais penalise, ne la heurte pas.
var dropped_by: Truck
var age_ticks: int = 0
var _visual: Node3D
var _hit: Dictionary = {}
var _shape: CollisionShape3D
var _owner_query: PhysicsShapeQueryParameters3D


func _init() -> void:
	name = "DetachedTrailer"
	mass = trailer_mass
	collision_layer = 1 << (HAZARD_LAYER - 1)
	collision_mask = (1 << (TruckSpec.LAYER_WORLD - 1)) | (1 << (TruckSpec.LAYER_VEHICLE - 1))
	contact_monitor = true
	max_contacts_reported = 4
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
	if dropped_by != null:
		add_collision_exception_with(dropped_by)
		_owner_query = PhysicsShapeQueryParameters3D.new()
		_owner_query.shape = _shape.shape
		_owner_query.collision_mask = 1 << (TruckSpec.LAYER_VEHICLE - 1)
		_owner_query.exclude = [get_rid()]
	body_entered.connect(_on_body_entered)


func _physics_process(_delta: float) -> void:
	age_ticks += 1
	if age_ticks >= lifetime_ticks:
		expired.emit()
		queue_free()
		return
	if _owner_query != null and age_ticks >= owner_pass_ticks:
		_update_owner_collision()
	var left := lifetime_ticks - age_ticks
	if _visual != null and left <= blink_ticks:
		var period := 4 if left <= 40 else 8
		_visual.visible = (left / period) % 2 == 0


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


func is_blinking() -> bool:
	return lifetime_ticks - age_ticks <= blink_ticks


func _on_body_entered(body: Node) -> void:
	var truck := body as Truck
	if truck == null or truck == dropped_by or _hit.has(truck):
		return
	_hit[truck] = true
	truck.cargo_hit(global_position)
	truck_hit.emit(truck)
