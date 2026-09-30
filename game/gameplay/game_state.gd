class_name GameStateNode
extends Node

## Etat global de la partie : joueurs, mapping device -> joueur, camion et
## couleur choisis.
##
## Autoload. Detient le mapping `device_id -> player_slot`, qui persiste
## pendant toute la course (cf. docs/INPUT_SPEC.md §5). Ne reattribue jamais
## un slot en cours de course.
##
## Pour l'instant : le nombre de joueurs et la categorie de vitesse choisis
## dans le menu principal, lus par la course locale. Le mapping device -> slot
## est fixe (joueur i = manette i).

## Categorie de vitesse, facon cylindree de Mario Kart.
enum SpeedClass { SLOW, NORMAL, FAST, ULTRA }

## Par categorie : nom, cylindree, vitesse max (km/h), multiplicateurs
## d'acceleration, d'adherence laterale (plus d'appui aux grandes vitesses) et
## de nervosite de la direction. NORMAL = le reglage mesure (baseline.json).
const SPEED_CLASSES: Array[Dictionary] = [
	{"name": "Lent", "cc": "50cc", "top_kmh": 110.0, "accel": 0.75, "grip": 1.0, "steer": 0.9},
	{"name": "Normal", "cc": "100cc", "top_kmh": 150.0, "accel": 1.0, "grip": 1.0, "steer": 1.0},
	{"name": "Rapide", "cc": "150cc", "top_kmh": 185.0, "accel": 1.25, "grip": 1.06, "steer": 1.12},
	{"name": "Ultrasonique", "cc": "200cc", "top_kmh": 225.0, "accel": 1.55, "grip": 1.12, "steer": 1.25},
]

## Categorie choisie dans le menu (garde entre deux courses).
var speed_class: int = SpeedClass.NORMAL

## Nombre de joueurs demande par le menu (1 a 6). 0 = rien de demande : la
## scene de course garde sa propre valeur (tests, lancement direct).
var requested_players: int = 0


## Reglage d'un camion pour une categorie de vitesse : copie du reglage de
## base (jamais modifie), vitesse max, poussee, adherence, direction.
static func speed_tuning(base: VehicleTuning, speed_class_index: int) -> VehicleTuning:
	var c: Dictionary = SPEED_CLASSES[clampi(speed_class_index, 0, SPEED_CLASSES.size() - 1)]
	var t := base.duplicate() as VehicleTuning
	t.top_speed_kmh = float(c["top_kmh"])
	t.engine_accel_ms2 = base.engine_accel_ms2 * float(c["accel"])
	t.boost_accel_ms2 = base.boost_accel_ms2 * float(c["accel"])
	t.lateral_grip_g = base.lateral_grip_g * float(c["grip"])
	t.steer_rate_deg_per_tick = base.steer_rate_deg_per_tick * float(c["steer"])
	t.reverse_top_speed_kmh = minf(base.reverse_top_speed_kmh, t.top_speed_kmh * 0.5)
	return t
