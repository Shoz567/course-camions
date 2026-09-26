class_name Truck
extends RigidBody3D

## Le camion : un seul RigidBody3D, 4 rayons de suspension (spike V1).
##
## Phase 1.2 : scene, masse, centre de masse, formes de collision, ancrages.
## Les forces (suspension, traction, adherence, direction, aides) arrivent aux
## taches 1.3 a 1.6, chacune derriere son interrupteur de debug (CLAUDE.md §6).
##
## Interface avec le gameplay (gameplay-engineer.md), la seule autorisee :
##   set_input(frame), get_speed_kmh(), is_upside_down(), wheels_on_ground()
## Le camion ne lit jamais Input.* : il recoit une InputFrame.

@export var tuning: VehicleTuning

## Derniere consigne recue. Copiee, jamais partagee avec la source.
var _input: InputFrame = InputFrame.new()
var _probes: Array[Node3D] = []


func _ready() -> void:
	if tuning == null:
		push_error("Truck '%s' : aucun VehicleTuning" % name)
		set_physics_process(false)
		return
	var errors := tuning.validate()
	if not errors.is_empty():
		push_error("Truck '%s' : VehicleTuning invalide :\n  %s" % [name, "\n  ".join(errors)])
		set_physics_process(false)
		return
	for n in TruckSpec.PROBE_NAMES:
		_probes.append(get_node(NodePath(n)) as Node3D)


## Consigne du tick courant. Appelee a chaque tick par le proprietaire de la
## source d'input, avant la physique.
func set_input(frame: InputFrame) -> void:
	_input.copy_from(frame)


func get_input() -> InputFrame:
	return _input


## Vitesse le long de l'axe avant (-Z), pas la norme du vecteur (METRICS.md).
func get_speed_kmh() -> float:
	return linear_velocity.dot(-global_transform.basis.z) * 3.6


func is_upside_down() -> bool:
	return global_transform.basis.y.y < 0.0


## Nombre de roues au sol. 0 tant que la suspension (tache 1.3) n'existe pas.
func wheels_on_ground() -> int:
	return 0
