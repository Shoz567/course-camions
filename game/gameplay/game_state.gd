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
## circuit choisis dans le menu principal, lus par la course locale. Le mapping
## device -> slot : celui de la salle d'attente (join_devices), sinon joueur
## i = manette i.

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

## Circuits : nom, ambiance (sous-titre du menu), scene de course, image de
## l'ecran de chargement.
const TRACKS: Array[Dictionary] = [
	{"name": "Cyber City", "tagline": "nuit pluvieuse, néons, mégalopole", "scene": "res://dev/race.tscn",
		"image": "res://ui/loading/cyber_city.jpg"},
	{"name": "Playa Del Sol", "tagline": "plage tropicale, plein soleil, océan", "scene": "res://dev/race_playa.tscn",
		"image": "res://ui/loading/playa_del_sol.jpg"},
	{"name": "Sakura", "tagline": "Japon au printemps, cerisiers, circuit en 8 et pont vermillon", "scene": "res://dev/race_sakura.tscn",
		"image": "res://ui/loading/sakura.jpg"},
]

## Arenes stock-car (2026-10-20), une par habillage de circuit.
const ARENAS: PackedStringArray = ["res://dev/arena.tscn", "res://dev/arena_playa.tscn", "res://dev/arena_sakura.tscn"]

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

## Salle d'attente du menu (« appuyez sur Croix pour rejoindre », tache 4.2) :
## appareil de chaque joueur, dans l'ordre d'arrivee (id de manette, ou
## JOIN_ARROWS / JOIN_ZQSD pour un joueur au clavier). Vide : joueur N =
## manette N (choix du nombre de joueurs au menu).
var join_devices: PackedInt32Array = PackedInt32Array()
const JOIN_ARROWS := -1
const JOIN_ZQSD := -2

## Remorque choisie par chaque joueur dans le sas READY (index dans
## TrailerCatalog), gardee d'une course a l'autre. 0 = Conteneur (defaut).
var trailer_choice: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0])

## Boutons de chaque action de la manette (PadBindings, reaffectables dans les
## parametres), pour toutes les manettes.
var pad_bindings: Dictionary = PadBindings.defaults()

## Options gardees d'un lancement a l'autre (tache 7.1) : son, volume,
## qualite, compteur, resolution dynamique, circuit, vitesse, remorques,
## boutons. Jamais en headless : les tests partent toujours des defauts.
const SETTINGS_PATH := "user://settings.cfg"
var persist: bool = DisplayServer.get_name() != "headless"

## Pouvoirs choisis par chaque joueur sur la page de selection du menu
## (index dans PowerCatalog, -1 = aucun), places sur la croix directionnelle :
## gauche et droite. Aucun pouvoir n'existe encore (2026-10-16).
var power_left: PackedInt32Array = PackedInt32Array([-1, -1, -1, -1, -1, -1])
var power_right: PackedInt32Array = PackedInt32Array([-1, -1, -1, -1, -1, -1])

## Vrai quand la page de selection du menu a fixe remorques et pouvoirs : la
## course part directement au compte a rebours, sans le sas READY (« rejouer »
## garde le meme choix). Faux au lancement direct d'une scene de course.
var loadout_locked: bool = false
## Bots de la course hors ligne (menu principal, 2026-10-19) : nombre (le
## total joueurs + bots ne depasse pas LocalRace.MAX_PLAYERS) et niveau
## (BotInputSource.Level).
var bot_count: int = 0
var bot_level: int = 1
## Largages de remorque par joueur et par course (2026-10-20 : de 0 a 5,
## choisi au menu ; TruckCargo.drops_left).
const MAX_TRAILER_DROPS := 5
var trailer_drops: int = 3
## Mode de jeu (2026-10-20) : course, elimination (le dernier saute toutes les
## 20 s), contre-la-montre (seul, fantome du meilleur tour), arene (stock-car,
## le dernier debout gagne).
enum GameMode { RACE, ELIMINATION, TIME_TRIAL, ARENA }
const MODE_NAMES: PackedStringArray = ["COURSE", "ÉLIMINATION", "CONTRE-LA-MONTRE", "ARÈNE"]
var game_mode: int = GameMode.RACE


## Scene de course du circuit `index` (borne aux circuits connus).
static func track_scene(index: int) -> String:
	# arene : celle de l'habillage du circuit choisi
	if GameState != null and GameState.game_mode == GameMode.ARENA:
		return ARENAS[clampi(index, 0, ARENAS.size() - 1)]
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
	# bus Effets / Ambiance / Musique et limiteur, avant le premier son
	SoundMix.setup()
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
	if persist:
		read_settings(SETTINGS_PATH)


## Sauvegarde les options (sauf en headless) ; appele a chaque changement.
func save_settings() -> void:
	if persist:
		write_settings(SETTINGS_PATH)


func write_settings(path: String) -> Error:
	var cfg := ConfigFile.new()
	var bus := AudioServer.get_bus_index("Master")
	cfg.set_value("audio", "on", not AudioServer.is_bus_mute(bus))
	cfg.set_value("audio", "volume", db_to_linear(AudioServer.get_bus_volume_db(bus)))
	cfg.set_value("video", "quality", graphics_quality)
	cfg.set_value("video", "show_fps", show_fps)
	cfg.set_value("video", "dynamic_resolution", dynamic_resolution)
	cfg.set_value("race", "track", selected_track)
	cfg.set_value("race", "speed_class", speed_class)
	cfg.set_value("race", "trailers", trailer_choice)
	cfg.set_value("race", "bots", bot_count)
	cfg.set_value("race", "trailer_drops", trailer_drops)
	cfg.set_value("race", "mode", game_mode)
	cfg.set_value("race", "bot_level", bot_level)
	for a: String in PadBindings.ACTIONS:
		cfg.set_value("pad", a, pad_bindings[a])
	return cfg.save(path)


## Relit les options ; un fichier absent ou abime laisse les defauts, une
## valeur hors bornes est ramenee dedans.
func read_settings(path: String) -> Error:
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		return err
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(bus, not bool(cfg.get_value("audio", "on", true)))
	var vol := clampf(float(cfg.get_value("audio", "volume", 1.0)), 0.0, 1.0)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(vol, 0.00001)))
	graphics_quality = clampi(int(cfg.get_value("video", "quality", graphics_quality)), 0, GraphicsSettings.NAMES.size() - 1)
	show_fps = bool(cfg.get_value("video", "show_fps", show_fps))
	dynamic_resolution = bool(cfg.get_value("video", "dynamic_resolution", dynamic_resolution))
	selected_track = clampi(int(cfg.get_value("race", "track", selected_track)), 0, TRACKS.size() - 1)
	speed_class = clampi(int(cfg.get_value("race", "speed_class", speed_class)), 0, SPEED_CLASSES.size() - 1)
	bot_count = clampi(int(cfg.get_value("race", "bots", bot_count)), 0, 5)
	trailer_drops = clampi(int(cfg.get_value("race", "trailer_drops", trailer_drops)), 0, MAX_TRAILER_DROPS)
	game_mode = clampi(int(cfg.get_value("race", "mode", game_mode)), 0, MODE_NAMES.size() - 1)
	bot_level = clampi(int(cfg.get_value("race", "bot_level", bot_level)), 0, 2)
	var trailers: Variant = cfg.get_value("race", "trailers", trailer_choice)
	if trailers is PackedInt32Array and (trailers as PackedInt32Array).size() == trailer_choice.size():
		trailer_choice = trailers
	var loaded := {}
	for a: String in PadBindings.ACTIONS:
		loaded[a] = cfg.get_value("pad", a, PackedInt32Array())
	pad_bindings = PadBindings.sanitized(loaded)
	return OK


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
