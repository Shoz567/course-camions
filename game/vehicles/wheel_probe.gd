class_name WheelProbe
extends RayCast3D

## Une roue : un rayon tire vers le bas depuis l'ancrage de VEHICLE_SPEC §4.
## La roue n'est pas un corps physique : ce noeud mesure le contact, le camion
## applique les forces (truck.gd).
##
## Le rayon ne vise que la couche 1 `world` (VEHICLE_SPEC §7) : une roue ne
## roule ni sur un autre camion ni sur un checkpoint.

var in_contact: bool = false
## Distance ancrage -> moyeu, le long du rayon. TRAVEL quand la roue pend.
var hub_distance: float = TruckSpec.SUSPENSION_TRAVEL
var contact_point: Vector3 = Vector3.ZERO
var contact_normal: Vector3 = Vector3.UP
## Multiplicateur d'adherence de la surface touchee (VEHICLE_SPEC §8).
var surface_grip: float = 1.0
## Force de suspension transmise ce tick (N) : c'est la charge de la roue.
var load_n: float = 0.0
## Vitesse du point de contact le long de l'axe avant de la roue (m/s).
var long_speed: float = 0.0
## Rayon perdu par un pneu eclate (m) : la roue porte sur sa jante, le moyeu
## descend d'autant vers le sol (Truck.burst_tire).
var radius_loss: float = 0.0


func _ready() -> void:
	target_position = Vector3(0.0, -TruckSpec.RAY_LENGTH, 0.0)
	collision_mask = 1 << (TruckSpec.LAYER_WORLD - 1)
	exclude_parent = true
	enabled = true


## Relance le rayon et met a jour l'etat de contact. Appele par le camion,
## une fois par tick, avant de calculer les forces.
func probe() -> void:
	force_raycast_update()
	in_contact = is_colliding()
	if not in_contact:
		hub_distance = TruckSpec.SUSPENSION_TRAVEL
		load_n = 0.0
		long_speed = 0.0
		return
	contact_point = get_collision_point()
	contact_normal = get_collision_normal()
	hub_distance = global_position.distance_to(contact_point) - (TruckSpec.WHEEL_RADIUS - radius_loss)
	surface_grip = 1.0
	var c := get_collider()
	if c != null and c.has_meta(&"surface"):
		surface_grip = TruckSpec.SURFACE_GRIP.get(c.get_meta(&"surface"), 1.0)
