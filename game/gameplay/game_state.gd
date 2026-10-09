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

## Qualite graphique choisie dans les parametres (GraphicsSettings.Quality) ;
## au lancement, celle que propose la carte graphique (default_quality).
var graphics_quality: int = GraphicsSettings.default_quality()

## Compteur d'images par seconde en haut a droite (parametres du menu,
## 2026-10-09). Affiche par-dessus tout : menu, course, ecran partage.
var show_fps: bool = false:
	set(value):
		show_fps = value
		if _fps_label != null:
			_fps_label.visible = value

## Resolution dynamique de la 3D (parametres du menu, DynamicResolution) :
## active par defaut, sans effet tant que la carte tient 60 images/s.
var dynamic_resolution: bool = true

## Regle l'echelle 3D de toutes les vues (enfant de l'autoload).
var resolution: DynamicResolution

var _fps_label: Label
var _fps_wait: float = 0.0

## Categorie choisie dans le menu (garde entre deux courses).
var speed_class: int = SpeedClass.NORMAL

## Nombre de joueurs demande par le menu (1 a 6). 0 = rien de demande : la
## scene de course garde sa propre valeur (tests, lancement direct).
var requested_players: int = 0

## Remorque choisie par chaque joueur dans le sas READY (index dans
## TrailerCatalog), gardee d'une course a l'autre. 0 = Conteneur (defaut).
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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	resolution = DynamicResolution.new()
	resolution.name = "DynamicResolution"
	add_child(resolution)
	var layer := CanvasLayer.new()
	layer.name = "FpsCounter"
	layer.layer = 128
	add_child(layer)
	_fps_label = Label.new()
	_fps_label.name = "Fps"
	_fps_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_fps_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_fps_label.position += Vector2(-16.0, 10.0)
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.add_theme_font_size_override("font_size", 22)
	_fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_fps_label.add_theme_constant_override("outline_size", 6)
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_label.visible = show_fps
	layer.add_child(_fps_label)


## Compteur : rafraichi 4 fois par seconde (lisible), vert a 55 images/s et
## plus, jaune a 30, rouge en dessous.
func _process(delta: float) -> void:
	if not show_fps or _fps_label == null:
		return
	_fps_wait -= delta
	if _fps_wait > 0.0:
		return
	_fps_wait = 0.25
	var fps := Engine.get_frames_per_second()
	_fps_label.text = fps_text(fps, resolution.scale)
	_fps_label.modulate = Color(0.45, 1.0, 0.5) if fps >= 55.0 else (Color(1.0, 0.85, 0.3) if fps >= 30.0 \
		else Color(1.0, 0.4, 0.35))


## Texte du compteur : images par seconde, duree d'une image et, quand la
## resolution dynamique l'a baissee, la resolution de la 3D.
static func fps_text(fps: float, scale: float = 1.0) -> String:
	var text := "%d FPS  (%.1f ms)" % [roundi(fps), 1000.0 / maxf(fps, 1.0)]
	if scale < 0.999:
		text += "\n3D %d %%" % roundi(scale * 100.0)
	return text
