class_name GameStateNode
extends Node

## Etat global de la partie : joueurs, mapping device -> joueur, camion et
## couleur choisis.
##
## Autoload. Detient le mapping `device_id -> player_slot`, qui persiste
## pendant toute la course (cf. docs/INPUT_SPEC.md §5). Ne reattribue jamais
## un slot en cours de course.
##
## Pour l'instant : le nombre de joueurs, la categorie de vitesse et le
## circuit choisis dans le menu principal, lus par la course locale. Le mapping device -> slot
## est fixe (joueur i = manette i).

## Categorie de vitesse, facon cylindree de Mario Kart.
enum SpeedClass { SLOW, NORMAL, FAST, ULTRA }

## Par categorie : nom, cylindree, vitesse max (km/h), multiplicateurs
## d'acceleration, d'adherence laterale (plus d'appui aux grandes vitesses) et
## de nervosite de la direction, et de courbe du drift (drift_carve_g) : le
## rayon croit comme le carre de la vitesse, sans elle le drift 200cc decrivait
## 175 m et sortait des virages de 140 m (truck_drift_line_test).
## NORMAL = le reglage mesure (baseline.json).
const SPEED_CLASSES: Array[Dictionary] = [
	{"name": "Lent", "cc": "50cc", "top_kmh": 110.0, "accel": 0.75, "grip": 1.0, "steer": 0.9, "drift": 1.0},
	{"name": "Normal", "cc": "100cc", "top_kmh": 150.0, "accel": 1.0, "grip": 1.0, "steer": 1.0, "drift": 1.0},
	{"name": "Rapide", "cc": "150cc", "top_kmh": 185.0, "accel": 1.25, "grip": 1.06, "steer": 1.12, "drift": 1.4},
	{"name": "Ultrasonique", "cc": "200cc", "top_kmh": 225.0, "accel": 1.55, "grip": 1.12, "steer": 1.25, "drift": 2.0},
]

## Circuits : nom, ambiance (sous-titre du menu) et scene de course.
const TRACKS: Array[Dictionary] = [
	{"name": "Cyber City", "tagline": "nuit pluvieuse, néons, mégalopole", "scene": "res://dev/race.tscn"},
	{"name": "Playa Del Sol", "tagline": "plage tropicale, plein soleil, océan", "scene": "res://dev/race_playa.tscn"},
]

## Circuit choisi dans le menu (garde entre deux courses).
var selected_track: int = 0

## Qualite graphique choisie dans les parametres (GraphicsSettings.Quality).
var graphics_quality: int = GraphicsSettings.Quality.HIGH

## Categorie choisie dans le menu (garde entre deux courses).
var speed_class: int = SpeedClass.NORMAL

## Nombre de joueurs demande par le menu (1 a 6). 0 = rien de demande : la
## scene de course garde sa propre valeur (tests, lancement direct).
var requested_players: int = 0

## Remorque choisie par chaque joueur dans le sas READY (index dans
## TrailerCatalog), gardee d'une course a l'autre. 0 = Classique.
var trailer_choice: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0])


## Scene de course du circuit `index` (borne aux circuits connus).
static func track_scene(index: int) -> String:
	return TRACKS[clampi(index, 0, TRACKS.size() - 1)]["scene"]


## Reglage d'un camion pour une categorie de vitesse : copie du reglage de
## base (jamais modifie), vitesse max, poussee, adherence, direction, drift.
static func speed_tuning(base: VehicleTuning, speed_class_index: int) -> VehicleTuning:
	var c: Dictionary = SPEED_CLASSES[clampi(speed_class_index, 0, SPEED_CLASSES.size() - 1)]
	var t := base.duplicate() as VehicleTuning
	t.top_speed_kmh = float(c["top_kmh"])
	t.engine_accel_ms2 = base.engine_accel_ms2 * float(c["accel"])
	t.boost_accel_ms2 = base.boost_accel_ms2 * float(c["accel"])
	t.lateral_grip_g = base.lateral_grip_g * float(c["grip"])
	t.steer_rate_deg_per_tick = base.steer_rate_deg_per_tick * float(c["steer"])
	t.drift_carve_g = base.drift_carve_g * float(c["drift"])
	t.reverse_top_speed_kmh = minf(base.reverse_top_speed_kmh, t.top_speed_kmh * 0.5)
	return t
