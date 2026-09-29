class_name TruckSpec
extends RefCounted

## Miroir de docs/VEHICLE_SPEC.md, le contrat partage avec tools/blender/ et
## game/tracks/. On ne change pas un chiffre ici sans changer le document dans
## le meme commit (CLAUDE.md §8). truck_scene_test verifie que truck.tscn s'y
## conforme.

# §2 Gabarit, §3 centre de masse
const MASS_KG := 5000.0
const CENTER_OF_MASS := Vector3(0.0, 0.80, -0.30)

# §4 Roues : ordre FL, FR, RL, RR partout dans le code du camion
const WHEEL_NAMES: Array[StringName] = [&"Wheel_FL", &"Wheel_FR", &"Wheel_RL", &"Wheel_RR"]
const PROBE_NAMES: Array[StringName] = [&"Probe_FL", &"Probe_FR", &"Probe_RL", &"Probe_RR"]
const ANCHORS: Array[Vector3] = [
	Vector3(-1.05, 1.00, -1.90),
	Vector3(1.05, 1.00, -1.90),
	Vector3(-1.05, 1.00, 1.90),
	Vector3(1.05, 1.00, 1.90),
]
const WHEEL_RADIUS := 0.55
const WHEEL_WIDTH := 0.40
const SUSPENSION_TRAVEL := 0.60      # ancrage -> moyeu, debattement max
const HUB_REST_HEIGHT := 0.55        # hauteur du moyeu au repos
const RAY_LENGTH := SUSPENSION_TRAVEL + WHEEL_RADIUS   # 1,15 m

# §5 Formes de collision
const CHASSIS_SIZE := Vector3(2.4, 1.00, 5.8)
const CHASSIS_CENTER := Vector3(0.0, 1.25, 0.0)
const CAB_SIZE := Vector3(2.4, 1.40, 2.2)
const CAB_CENTER := Vector3(0.0, 2.45, -1.8)
# §5 bis Semi-remorque articulee (caisse du modele de l'equipe, a l'echelle du
# tracteur) : au repos de z = 0,4 a 13,4 m, de y = 1,8 a 4,9 m. Elle pivote en
# lacet autour de la sellette (KINGPIN), angle borne par VehicleTuning.
const TRAILER_SIZE := Vector3(3.0, 3.1, 13.0)
const TRAILER_CENTER := Vector3(0.0, 3.35, 6.9)
const KINGPIN := Vector3(0.0, 1.8, 1.2)

# §7 Couches (numeros de couche, 1 = bit 0)
const LAYER_WORLD := 1
const LAYER_VEHICLE := 2

const GRAVITY := 9.81

# §6 Cibles de conduite (les tests mesurent l'ecart)
const TARGET_TOP_SPEED_KMH := 150.0
const TARGET_ACCEL_0_100_S := 6.0
const TARGET_TOLERANCE := 0.05          # +/- 5 %
const TARGET_BRAKING_100_0_M := 45.0
const TARGET_LATERAL_G := 0.9

# §8 Surfaces : multiplicateur d'adherence, lu dans la metadonnee `surface`
const SURFACE_GRIP := {&"asphalt": 1.0, &"dirt": 0.75, &"grass": 0.6, &"ice": 0.3}


## Distance ancrage -> moyeu au repos (0,45 m).
static func rest_hub_distance() -> float:
	return ANCHORS[0].y - HUB_REST_HEIGHT


## Position du moyeu au repos, dans le repere du camion.
static func hub_rest_position(i: int) -> Vector3:
	return ANCHORS[i] - Vector3(0.0, rest_hub_distance(), 0.0)


## Part de la masse portee par l'essieu de la roue i (§4 : 57,9 % a l'avant).
static func axle_share(i: int) -> float:
	var wheelbase := ANCHORS[2].z - ANCHORS[0].z
	var front := (ANCHORS[2].z - CENTER_OF_MASS.z) / wheelbase
	return front if i < 2 else 1.0 - front


## Charge statique d'une roue (N).
static func static_wheel_load(i: int) -> float:
	return MASS_KG * GRAVITY * axle_share(i) / 2.0


## Longueur libre du ressort de la roue i pour une raideur k (N/m) : deduite de
## la hauteur de repos imposee et de la charge de SON essieu (§4).
static func spring_free_length(i: int, k: float) -> float:
	return rest_hub_distance() + static_wheel_load(i) / k
