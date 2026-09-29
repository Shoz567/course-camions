class_name DetachedTrailer
extends RigidBody3D

## Remorque larguee (pouvoir cargo, Triangle) : la remorque entiere reste sur
## la route pendant lifetime_ticks (10 s) et fait barrage. Corps lourd et
## freine (il glisse un peu, puis tient la place), boite pleine hauteur posee
## au sol, sur la couche 5 `hazard` (VEHICLE_SPEC §7) : les camions la
## percutent, les rayons de suspension et les zones de la piste l'ignorent.
## Un camion adverse qui la percute est ralenti et deporte (Truck.cargo_hit),
## une fois ; le camion qui l'a larguee la traverse. Elle clignote pendant les
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

## Camion qui l'a larguee : jamais penalise, ne la heurte pas.
var dropped_by: Truck
var age_ticks: int = 0
var _visual: Node3D
var _hit: Dictionary = {}


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
	body_entered.connect(_on_body_entered)


func _physics_process(_delta: float) -> void:
	age_ticks += 1
	if age_ticks >= lifetime_ticks:
		expired.emit()
		queue_free()
		return
	var left := lifetime_ticks - age_ticks
	if _visual != null and left <= blink_ticks:
		var period := 4 if left <= 40 else 8
		_visual.visible = (left / period) % 2 == 0


func is_blinking() -> bool:
	return lifetime_ticks - age_ticks <= blink_ticks


func _on_body_entered(body: Node) -> void:
	var truck := body as Truck
	if truck == null or truck == dropped_by or _hit.has(truck):
		return
	_hit[truck] = true
	truck.cargo_hit(global_position)
	truck_hit.emit(truck)
