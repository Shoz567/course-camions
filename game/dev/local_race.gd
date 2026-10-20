extends Node3D

## Course locale de 4 tours, de 1 a 6 joueurs, sur le circuit de la scene.
##
##   1 joueur    : plein ecran, n'importe quelle manette + tout le clavier.
##   2 joueurs   : ecran partage haut / bas (VBoxContainer).
##   3-4 joueurs : grille 2 x 2 (GridContainer). A 3, la 4e case suit le
##                 camion en tete (camera TV).
##   5-6 joueurs : grille 3 x 2. A 5, la 6e case suit le camion en tete.
##
##   J1 camion bleu AZUR          manette 0 (+ fleches en ecran partage)
##   J2 camion rouge DURAND       manette 1 (+ ZQSD)
##   J3 camion jaune SOLEIL       manette 2
##   J4 camion vert               manette 3
##   J5 violet NEO-TOKYO          manette 4 (livree : amethyste, neons magenta)
##   J6 orange CARBO              manette 5 (livree : lave, carbone, cuivre)
##
## Chaque joueur a sa source d'input (sa manette, et AUCUNE autre : INPUT_SPEC
## §4), son camion, sa camera, son HUD. Sas « READY ? » (2026-10-02) : chaque
## vue montre le joueur et sa manette, et l'invite a appuyer sur CARRE (Maj au
## clavier : la touche du boost, lue sur SA source d'input). Avant, chacun
## choisit sa semi-remorque (2026-10-06) : gauche / droite de SA source font
## defiler TrailerCatalog sur son camion (modele, caisse, stats) ; le choix est
## fige une fois READY et garde pour la course suivante. Des que tous
## sont READY, le compte a rebours commun demarre, puis la course (largage de
## remorque verrouille les 5 premieres secondes, TruckCargo) :
## RaceLaps compte les tours, AutoReset replace hors piste ou retourne. Le
## classement s'affiche pour tous des la premiere arrivee. Quand tous sont
## arrives : Options / Entree relance, Create / Echap revient au menu (Echap a tout
## moment). Musique de course (RaceMusic) du GO jusqu'a l'arrivee de tous ;
## elle disparait avec la scene (menu, rejouer).
##
## Le nombre de joueurs vient du menu principal (GameState.requested_players)
## quand `players_from_menu` est vrai (dev/race.tscn) ; les scenes a nombre
## fixe (race_2p, track_drive) gardent le leur.
##
## Le compte a rebours et l'enchainement migreront dans RaceManager (tache 3.1).

const MENU_SCENE := "res://ui/main_menu.tscn"
const COUNTDOWN_TICKS := RaceManagerNode.COUNTDOWN_TICKS      # 3 s
const GO_TICKS := 60              # "GO !" reste 1 s
const MODELS: PackedStringArray = [
	"../Assets_Visuels/Camion/Camions_Course_Export/Realiste/Camion_Bleu.glb",
	"../Assets_Visuels/Camion/Camions_Course_Export/Realiste/Camion_Rouge.glb",
	"../Assets_Visuels/Camion/Camions_Course_Export/Realiste/Camion_Jaune.glb",
	"../Assets_Visuels/Camion/Camions_Course_Export/Realiste/Camion_Vert.glb",
	# J5 et J6 : pas de modele a eux (aucun .glb dans le depot) ; ils
	# reprennent un modele existant, repeint par leur livree (LIVERIES)
	"../Assets_Visuels/Camion/Camions_Course_Export/Realiste/Camion_Bleu.glb",
	"../Assets_Visuels/Camion/Camions_Course_Export/Realiste/Camion_Rouge.glb",
]
const NAMES: PackedStringArray = ["J1 AZUR", "J2 DURAND", "J3 SOLEIL", "J4 VERT",
	"J5 VIOLET NÉO-TOKYO", "J6 ORANGE CARBO"]
## Couleur des boites quand le modele est absent (clone neuf).
const TINTS: Array[Color] = [Color(0.15, 0.35, 0.9), Color(0.85, 0.12, 0.1),
	Color(0.95, 0.8, 0.1), Color(0.15, 0.7, 0.25),
	Color(0.55, 0.16, 0.95), Color(1.0, 0.38, 0.04)]
## Livree par joueur (TruckVisual.livery) : par prefixe de nom de materiau du
## modele, les proprietes repeintes. Vide : le modele garde ses couleurs.
const LIVERIES: Array[Dictionary] = [{}, {}, {}, {},
	# J5 VIOLET NEO-TOKYO : amethyste electrique brillante, neons magenta
	{
		"Peinture_Cabine": {"albedo": Color(0.42, 0.1, 0.9), "metallic": 0.65, "roughness": 0.14,
			"clearcoat": 1.0, "emission": Color(0.35, 0.05, 0.8), "emission_energy": 0.25},
		"Peinture_Caisse": {"albedo": Color(0.16, 0.05, 0.34), "metallic": 0.55, "roughness": 0.2,
			"clearcoat": 1.0},
		"Bande_Deco": {"albedo": Color(1.0, 0.1, 0.75), "emission": Color(1.0, 0.08, 0.75),
			"emission_energy": 3.5},
		"Texte_Logo": {"albedo": Color(1.0, 0.1, 0.75), "emission": Color(1.0, 0.08, 0.75),
			"emission_energy": 3.0},
		"Flamme": {"albedo": Color(1.0, 0.1, 0.75), "emission": Color(1.0, 0.08, 0.75),
			"emission_energy": 4.0},
		"Jante": {"albedo": Color(0.75, 0.6, 1.0), "metallic": 1.0, "roughness": 0.18},
	},
	# J6 ORANGE CARBO : orange lave metallise, carbone noir mat, jantes cuivre
	{
		"Peinture_Cabine": {"albedo": Color(1.0, 0.3, 0.02), "metallic": 0.8, "roughness": 0.2,
			"clearcoat": 0.8, "emission": Color(1.0, 0.22, 0.0), "emission_energy": 0.35},
		"Peinture_Caisse": {"albedo": Color(0.035, 0.035, 0.04), "metallic": 0.1, "roughness": 0.85},
		"Bande_Deco": {"albedo": Color(0.03, 0.03, 0.035), "metallic": 0.1, "roughness": 0.8},
		"Carbone": {"albedo": Color(0.03, 0.03, 0.035), "metallic": 0.1, "roughness": 0.8},
		"Texte_Logo": {"albedo": Color(1.0, 0.35, 0.02), "emission": Color(1.0, 0.3, 0.0),
			"emission_energy": 2.0},
		"Jante": {"albedo": Color(0.85, 0.42, 0.22), "metallic": 1.0, "roughness": 0.22},
		"Chrome": {"albedo": Color(0.8, 0.45, 0.28), "metallic": 1.0, "roughness": 0.15},
	},
]
const HELP_SOLO := "Manette (DualSense, facon Forza) : R2 accelerer, L2 freiner / reculer, Croix ou R1 drift, Carre nitro (recharge 6 s),\nTriangle remorque, L3 klaxon, stick droit regard, L1 derriere, R3 camera, Options reset, croix gauche / droite pouvoirs, croix haut cible.   Clavier : ZQSD ou fleches, Espace drift, Maj boost, E cargo, H klaxon, C camera, B derriere, R reset, F / G pouvoirs, T cible.   Echap : menu"
const HELP_SPLIT: PackedStringArray = [
	"J1 : manette 1, ou fleches + Ctrl droit (drift), Maj droite (boost), ; (cargo), Retour arriere (reset), K / L (pouvoirs)",
	"J2 : manette 2, ou ZQSD + Espace (drift), Maj gauche (boost), E (cargo), R (reset), F / G (pouvoirs)",
	"J3 : manette 3",
	"J4 : manette 4",
	"J5 : manette 5",
	"J6 : manette 6",
]
const MAX_PLAYERS := 6
## Couleur de chaque joueur, pour le sas READY.
const COLOR_NAMES: PackedStringArray = ["BLEU", "ROUGE", "JAUNE", "VERT", "VIOLET", "ORANGE"]
## Echelle du HUD selon le nombre de joueurs (vues plus petites).
const HUD_SCALE: Array[float] = [1.0, 0.85, 0.6, 0.6, 0.5, 0.5]

## LOBBY (sas READY) en dernier : les valeurs des autres etats ne changent pas.
enum State { COUNTDOWN, RACING, FINISHED, LOBBY }

class Player:
	var truck: Truck
	## Locale (LocalInputSource) ; en ligne, cote host, RemoteInputSource pour
	## un joueur distant ; cote client, neutre pour les autres (marionnettes).
	var input: InputSource
	## Seulement pour un joueur de cette machine (null sinon, en ligne).
	var camera: ChaseCamera
	var hud: RaceHud
	var viewport: SubViewport
	## Reglage ajuste a la categorie de vitesse, avant la remorque.
	var base_tuning: VehicleTuning
	## Remorque choisie (index dans TrailerCatalog).
	var trailer: int = 0
	## Pouvoirs choisis au menu, croix gauche / droite (PowerCatalog, -1 = aucun).
	var power_left: int = -1
	var power_right: int = -1

## Stick ou fleches au-dela de ce seuil : remorque suivante / precedente.
const TRAILER_STEER_THRESHOLD := 0.6


@export_range(1, 6) var player_count: int = 2
## Bots hors ligne, apres les joueurs (BotInputSource) : ni vue ni HUD.
@export_range(0, 5) var bot_count: int = 0
@export_range(0, 2) var bot_level: int = 1
## Vrai : le nombre de joueurs choisi dans le menu remplace `player_count`.
@export var players_from_menu: bool = false
## Sas READY avant le compte a rebours. Faux : compte a rebours tout de suite
## (tests qui ne portent pas sur le sas).
@export var ready_gate: bool = true

## Le circuit de la scene (Track01 en ville, Track02 a la plage).
@export var track_path: NodePath = ^"Track01"

@onready var track: TrackBlockout = get_node(track_path) as TrackBlockout
@onready var race: RaceLaps = $RaceLaps
@onready var auto_reset: AutoReset = $AutoReset

var players: Array[Player] = []
## Prechauffe des effets en cours (FxWarmup) ; depart retenu sous l'ecran de
## chargement, et ce qu'il deviendra (sas READY ou compte a rebours).
var _warmup: FxWarmup
var _held: bool = false
var _held_gate: bool = false
## Qualite appliquee a cette course (choisie, ou budget de l'ecran partage).
var quality: int = GraphicsSettings.Quality.MEDIUM
## Etat de la course : celui de RaceManager (tache 3.1), memes valeurs.
var state: State:
	get:
		return int(RaceManager.state) as State
	set(value):
		RaceManager.enter(int(value) as RaceManagerNode.State, Engine.get_physics_frames())
## Conteneur de l'ecran partage (VBoxContainer ou GridContainer), null en solo.
var split: Container
## Camera de la case libre (la 4e a 3 joueurs, la 6e a 5) : suit le camion en
## tete.
var leader_camera: ChaseCamera
var _leader_label: Label
## Tick d'entree dans l'etat courant, ordre d'arrivee : ceux de RaceManager.
var _state_tick: int:
	get:
		return RaceManager.state_tick
	set(value):
		RaceManager.state_tick = value
var _last_countdown_sec: int = -1
var _neutral: InputFrame = InputFrame.new()
var _finish_order: Array[Truck]:
	get:
		return RaceManager.finish_order
## Sas READY : joueur pret, Carre (boost) enfonce au tick precedent.
var ready_flags: Array[bool] = []
var _square_was: Array[bool] = []
## Sas READY : direction du stick au tick precedent (-1, 0, 1), pour ne
## changer de remorque qu'une fois par poussee.
var _steer_was: Array[int] = []
## Musique de course : demarre au GO, fondu a l'arrivee (inerte en headless).
var music: RaceMusic
## Course en ligne (NetSession, phase 6) : un joueur par machine, dans l'ordre
## des cases du lobby ; null hors ligne.
var net: NetRace
## En ligne : joueurs partis en cours de route (classes « abandon »).
var _abandoned: Array[int] = []
## Annonce passagere (« X a quitte la partie »), jusqu'au tick indique.
var _notice: String = ""
var _notice_until: int = 0
## Client : partie perdue (host parti, coupure) ; la raison reste affichee
## LOST_TICKS avant le retour au menu.
var _lost_reason: String = ""
var _lost_tick: int = 0
const LOST_TICKS := 180
const NOTICE_TICKS := 240
## Sans snapshot depuis ce nombre de ticks : « connexion instable ».
const UNSTABLE_TICKS := 90


func _ready() -> void:
	if NetSession.is_online():
		player_count = clampi(NetSession.members.size(), 1, MAX_PLAYERS)
		ready_gate = true
	elif players_from_menu and GameState.requested_players > 0:
		player_count = clampi(GameState.requested_players, 1, MAX_PLAYERS)
		bot_count = GameState.bot_count
		bot_level = GameState.bot_level
	bot_count = 0 if NetSession.is_online() else clampi(bot_count, 0, MAX_PLAYERS - player_count)
	# vue propre par defaut : F1 affiche les traces de debug
	DebugDraw.enabled = false
	_apply_graphics()
	# HUD et ecrans a l'habillage du circuit (le meme qu'au menu)
	UiKit.apply_skin(UiKit.skin_for_track(track.theme_id))
	# de nuit, les phares des camions eclairent la route
	TruckLights.night = track.theme_id == TrackTheme.Id.CYBER_CITY
	# projections des roues : gerbes d'eau sous la pluie, sable a la plage
	TruckWheelFx.spray = TruckWheelFx.Spray.WATER if TruckLights.night else TruckWheelFx.Spray.DUST
	# brume de chaleur sur la route de jour (post-traitement des cameras) ;
	# legere au printemps
	ScreenFx.haze = 0.0 if TruckLights.night else (0.35 if track.theme_id == TrackTheme.Id.SAKURA else 1.0)
	# camions sales de la route : poussiere claire au bord de mer, crasse
	# sombre et carrosseries mouillees sous la pluie
	if TruckLights.night:
		TruckMaterials.set_weather(TruckMaterials.CITY_GRIME, 0.85)
	else:
		TruckMaterials.set_weather(TruckMaterials.BEACH_GRIME, 0.0)
	auto_reset.respawn_provider = race.respawn_transform
	race.race_finished.connect(_on_race_finished)
	race.lap_completed.connect(_on_lap_completed)
	# pluie et ville, ou vagues et vent, sous la musique
	var ambience := AmbienceSound.new()
	ambience.name = "Ambience"
	ambience.theme_id = track.theme_id
	add_child(ambience)
	music = RaceMusic.new()
	music.name = "RaceMusic"
	add_child(music)
	RaceMusic.prepare()
	split = null if NetSession.is_online() else _build_split_screen()
	for i in player_count + bot_count:
		players.append(_add_player(i))
	if split != null and (player_count == 3 or player_count == 5):
		_add_leader_view()
	for i in players.size():
		# un bot est toujours pret
		ready_flags.append(is_bot(i))
		_square_was.append(false)
		_steer_was.append(0)
	# carrosseries deformables preparees pendant le chargement (~0,5 s par
	# modele) : le sas READY ne prepare plus que les remorques changees, sans
	# figer la course (en ligne, un client fige n'envoie plus ses inputs)
	_prewarm_bodies()
	# creux de carrosserie calcules sans figer l'image (pas en headless : les
	# tests lisent le creux des le retour de dent)
	BodyDamage.async_dents = DisplayServer.get_name() != "headless"
	# shaders des explosions, etincelles, fumees compiles avant le depart
	# (tache 7.6 : la premiere explosion figeait l'image 370 ms a 4 joueurs)
	_warmup = FxWarmup.start(self, quality)
	# hors ligne, remorques et pouvoirs deja choisis au menu (page de selection) :
	# pas de sas, compte a rebours tout de suite. En ligne, le sas READY reste
	var gate := ready_gate and (NetSession.is_online() or not GameState.loadout_locked)
	# sous l'ecran de chargement (hors ligne) : rien ne part avant qu'il
	# s'efface (release_start) ; la grille attend, camions immobiles
	_held = LoadingScreen.covering() and not NetSession.is_online()
	_held_gate = gate
	RaceManager.begin(true if _held else gate, Engine.get_physics_frames())
	if NetSession.is_online():
		race.mirror = NetSession.is_client()
		net = NetRace.new()
		add_child(net)
		net.setup(self, players, race)
		NetSession.connection_lost.connect(_on_connection_lost)


## Machine qui simule la course : hors ligne, ou host en ligne.
func is_authority() -> bool:
	return not NetSession.is_client()


## Case du lobby du joueur `i` (sa couleur) : `i` hors ligne.
func slot_of(i: int) -> int:
	if NetSession.is_online() and i < NetSession.members.size():
		return int(NetSession.members[i]["slot"])
	return i


## Le joueur `i` joue-t-il sur cette machine ?
func is_local(i: int) -> bool:
	if is_bot(i):
		return false
	return not NetSession.is_online() or slot_of(i) == NetSession.local_slot()


## Le joueur `i` est-il un bot (hors ligne, apres les joueurs) ?
func is_bot(i: int) -> bool:
	return i >= player_count and not NetSession.is_online()


## Nom affiche : J1 AZUR... hors ligne, nom du lobby en ligne.
func player_name(i: int) -> String:
	if NetSession.is_online():
		return NetSession.name_of_slot(slot_of(i))
	if is_bot(i):
		return "BOT %d %s" % [i - player_count + 1, COLOR_NAMES[i]]
	return NAMES[i]


## Ecran partage : haut / bas a 2, grille 2 x 2 a 3-4, 3 x 2 a 5-6 (haut
## gauche = J1).
func _build_split_screen() -> Container:
	if player_count == 1:
		return null
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	# fond noir : les separations entre vues sont des traits noirs
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var box: Container
	if player_count == 2:
		box = VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
	else:
		var grid := GridContainer.new()
		grid.columns = 2 if player_count <= 4 else 3
		grid.add_theme_constant_override("h_separation", 4)
		grid.add_theme_constant_override("v_separation", 4)
		box = grid
	box.name = "SplitScreen"
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(box)
	return box


## Effets de l'environnement et anticrenelage selon la qualite choisie et le
## nombre de vues (la case de la camera TV compte).
func _apply_graphics() -> void:
	# en ligne : une seule vue, celle du joueur de cette machine
	var views := 1 if NetSession.is_online() else player_count + (1 if player_count == 3 or player_count == 5 else 0)
	# ecran partage sur puce integree : budget du spike V3
	quality = GraphicsSettings.split_quality(GameState.graphics_quality, views)
	var world := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world != null:
		GraphicsSettings.apply_environment(world.environment, quality, views)
	for n in find_children("*", "DirectionalLight3D", false, false):
		GraphicsSettings.apply_sun(n as DirectionalLight3D, views, quality)
	GraphicsSettings.apply_viewport(get_viewport(), quality)


## Une case de l'ecran partage : SubViewportContainer etire + SubViewport.
func _new_view(view_name: String, listener: bool) -> SubViewport:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(container)
	var vp := SubViewport.new()
	vp.name = view_name
	vp.audio_listener_enable_3d = listener
	GraphicsSettings.apply_viewport(vp, quality)
	container.add_child(vp)
	return vp


func _add_player(i: int) -> Player:
	var p := Player.new()
	var online := NetSession.is_online()
	var mine := is_local(i)
	# camion : modele et couleur du joueur (de sa case en ligne), case de
	# depart i (centre de la grille)
	var t := (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
	t.name = "Truck%d" % (i + 1)
	dress(t.get_node("Visual") as TruckVisual, slot_of(i))
	t.transform = track.get_start_transform(i)   # pose d'un camion immobile
	# categorie de vitesse du menu (Normal par defaut : le reglage mesure)
	p.base_tuning = GameStateNode.speed_tuning(t.tuning, GameState.speed_class)
	t.tuning = p.base_tuning
	add_child(t)
	p.truck = t
	# remorque et pouvoirs choisis sur la page de selection du menu ; en ligne,
	# ceux que chaque joueur a envoyes au lobby (NetSession.set_loadout)
	var choice := 0
	if online:
		var m := NetSession.member_of_slot(slot_of(i))
		choice = int(m.get("trailer", GameState.trailer_choice[0] if mine else 0))
		p.power_left = int(m.get("power_left", -1))
		p.power_right = int(m.get("power_right", -1))
	elif is_bot(i):
		# bot : remorque et pouvoirs selon son numero (deterministe)
		var b := i - player_count
		choice = posmod(3 * b + 1, TrailerCatalog.count())
		p.power_left = posmod(b + 1, PowerCatalog.count())
		p.power_right = posmod(b + 2, PowerCatalog.count())
	else:
		if i < GameState.trailer_choice.size():
			choice = GameState.trailer_choice[i]
		p.power_left = GameState.power_left[i] if i < GameState.power_left.size() else -1
		p.power_right = GameState.power_right[i] if i < GameState.power_right.size() else -1
	set_trailer(p, choice)
	# cibles des pouvoirs : tous les camions de la course ; pouvoirs choisis
	# sur la page de selection (hors ligne), simules sur la machine qui fait foi
	t.add_to_group(TruckPowers.TARGETS)
	# client en ligne : pouvoirs en miroir (effets et recharges du host)
	var tp := TruckPowers.setup(t, p.power_left, p.power_right, not is_authority())
	# son propre camion : le tir part a l'appui, sans attendre le host
	if tp != null and tp.mirror and mine:
		tp.predict = true
	race.watch(t)
	# client en ligne : NetRace predit le camion de ce PC et pose les autres sur
	# l'etat du host ; la remise en piste et les PV sont l'affaire du host
	if is_authority():
		auto_reset.watch(t)
	# 0 PV : epave 3 s, puis reapparition sur la piste (jamais un checkpoint
	# saute : RaceLaps.respawn_transform)
	var health := TruckHealth.of(t)
	if health != null and is_authority():
		health.respawn_provider = race.respawn_transform
	if is_bot(i):
		# bot : il conduit seul, sans camera ni HUD
		var bot := BotInputSource.new()
		bot.name = "Bot%d" % (i - player_count + 1)
		bot.setup(track, t, bot_level, i - player_count)
		add_child(bot)
		p.input = bot
		return p
	if online and not mine:
		# joueur d'une autre machine : ses inputs arrivent par le reseau (host),
		# ou ne servent pas (client) ; ni camera ni HUD ici
		var remote := RemoteInputSource.new() if is_authority() else InputSource.new()
		remote.name = "Input%d" % (i + 1)
		add_child(remote)
		p.input = remote
		return p
	# input : sa manette seulement en ecran partage ; son jeu de touches
	# (fleches pour J1, ZQSD pour J2, aucun au-dela)
	var input := LocalInputSource.new()
	input.name = "Input%d" % (i + 1)
	var joined := joined_device(i)
	if joined != NO_JOIN:
		# salle d'attente du menu : l'appareil avec lequel ce joueur a rejoint,
		# et lui seul (INPUT_SPEC §4)
		if joined >= 0:
			input.device = joined
			if split != null:
				input.keyboard_layout = KeyboardInputSource.Layout.NONE
		else:
			input.use_pad = false
			input.keyboard_layout = KeyboardInputSource.Layout.ARROWS if joined == GameStateNode.JOIN_ARROWS \
					else KeyboardInputSource.Layout.ZQSD
	elif split != null:
		input.device = i
		match i:
			0: input.keyboard_layout = KeyboardInputSource.Layout.ARROWS
			1: input.keyboard_layout = KeyboardInputSource.Layout.ZQSD
			_: input.keyboard_layout = KeyboardInputSource.Layout.NONE
	add_child(input)
	p.input = input
	# vue : plein ecran, ou une case de l'ecran partage (son 3D : J1)
	var view := i if split != null else 0
	var view_parent: Node = self
	if split != null:
		p.viewport = _new_view("View%d" % (i + 1), i == 0)
		view_parent = p.viewport
	var cam := ChaseCamera.new()
	cam.name = "Camera%d" % (i + 1)
	cam.target = t
	cam.quality = quality
	view_parent.add_child(cam)
	cam.snap()
	p.camera = cam
	# nuit pluvieuse : la pluie tombe autour de chaque camera, et chaque vue
	# ne voit que la sienne
	cam.get_camera().cull_mask = RainFx.cull_mask_for(cam.get_camera().cull_mask, view)
	if track.theme_id == TrackTheme.Id.CYBER_CITY and DisplayServer.get_name() != "headless":
		view_parent.add_child(RainFx.make(cam.get_camera(), view))
	# Sakura : petales de cerisier qui volent autour de chaque camera
	if track.theme_id == TrackTheme.Id.SAKURA and DisplayServer.get_name() != "headless":
		view_parent.add_child(SakuraPetals.make(cam.get_camera(), view))
	input.camera_toggle_requested.connect(cam.toggle_view)
	cam.look_source = input
	if health != null:
		health.respawned.connect(cam.snap)
	# secousse de camera aux chocs de SON camion (tache 3.5)
	t.wall_impact_at.connect(func(v: float, _r: bool, _at: Vector3, _n: Vector3) -> void:
		cam.shake(IMPACT_SHAKE * shake_for(v)))
	t.body_impact.connect(func(v: float, _r: bool, _at: Vector3, _n: Vector3) -> void:
		cam.shake(IMPACT_SHAKE * shake_for(v)))
	var hud := RaceHud.new()
	hud.truck = t
	hud.race = race
	hud.player_label = player_name(i)
	hud.accent = UiKit.PLAYER_COLORS[slot_of(i)]
	hud.help_text = HELP_SOLO if split == null else HELP_SPLIT[i]
	hud.ui_scale = HUD_SCALE[0 if split == null else player_count - 1]
	hud.camera = cam.get_camera()
	view_parent.add_child(hud)
	p.hud = hud
	return p

## Secousse de camera (0 .. 1) pour un choc a cette vitesse (m/s) : rien sous
## 4 m/s (frottement), pleine a 22 m/s (~80 km/h de face).
static func shake_for(speed_ms: float) -> float:
	return clampf((speed_ms - 4.0) / 18.0, 0.0, 1.0)


## Part de la secousse d'un choc dans celle de la camera (ChaseCamera.shake : 1
## = explosion a bout portant, 0,9 m et 2,5 deg pendant 0,7 s) : un choc de
## face plein pot secoue d'environ 0,2 m, eteint en 0,3 s.
const IMPACT_SHAKE := 0.45


## Dernier bruitage de course joue pour un joueur de cet ecran (RaceSound.Cue).
var last_cue: int = RaceSound.Cue.NONE


## Appareil du joueur `i` choisi dans la salle d'attente du menu (id de
## manette, GameState.JOIN_ARROWS / JOIN_ZQSD), ou NO_JOIN.
const NO_JOIN := -1000


func joined_device(i: int) -> int:
	if NetSession.is_online() or not players_from_menu or GameState.join_devices.size() != player_count:
		return NO_JOIN
	return GameState.join_devices[i]


## Joueur et manette, pour le sas READY : « J1 - BLEU (Manette 1 / fleches) ».
func player_tag(i: int) -> String:
	if NetSession.is_online():
		return "%s - %s" % [player_name(i), COLOR_NAMES[slot_of(i)]]
	var joined := joined_device(i)
	if joined != NO_JOIN:
		var how := "Manette %d" % (joined + 1) if joined >= 0 else \
				("flèches" if joined == GameStateNode.JOIN_ARROWS else "ZQSD")
		return "J%d - %s (%s)" % [i + 1, COLOR_NAMES[i], how]
	var device := "manette ou clavier"
	if player_count > 1:
		device = "Manette %d" % (i + 1)
		if i == 0:
			device += " / flèches"
		elif i == 1:
			device += " / ZQSD"
	return "J%d - %s (%s)" % [i + 1, COLOR_NAMES[i], device]


## Carrosseries deformables preparees avant le depart, pas au premier choc.
## Avec la copie propre de chaque camion (BodyDamage.prewarm `own` : ~70 ms et
## 15 Mo par camion au chargement, -45 ms au premier gros choc) ; pas en
## headless (tests : rien a l'ecran, chargement plus court).
## Course prete a etre montree (LoadingScreen) : modeles et carrosseries le
## sont des _ready ; reste la prechauffe des effets.
func loading_done() -> bool:
	return _warmup == null or not is_instance_valid(_warmup)


## L'ecran de chargement s'efface : la course demarre (sas READY ou compte a
## rebours, comme sans ecran).
func release_start() -> void:
	if not _held:
		return
	_held = false
	RaceManager.begin(_held_gate, Engine.get_physics_frames())


func _prewarm_bodies() -> void:
	var own := DisplayServer.get_name() != "headless"
	for p in players:
		var visual := p.truck.get_node_or_null(^"Visual") as TruckVisual
		BodyDamage.prewarm(visual, own)
		if visual != null:
			# pieces deformables de la tete et de la remorque (recherche d'un creux)
			BodyDamage.warm_candidates(visual.mark_parent(false))
			BodyDamage.warm_candidates(visual.mark_parent(true))


func all_ready() -> bool:
	return not ready_flags.has(false)


## Remorque `index` (TrailerCatalog, bouclee) pour le joueur : caisse de
## collision, modele et reglage de son camion ; choix garde pour la course
## suivante. Camions immobiles (sas READY, ou avant).
func set_trailer(p: Player, index: int) -> void:
	p.trailer = posmod(index, TrailerCatalog.count())
	var type := TrailerCatalog.at(p.trailer)
	p.truck.set_trailer_type(type)
	(p.truck.get_node("Visual") as TruckVisual).set_trailer_type(type)
	p.truck.tuning = type.apply_to(p.base_tuning)
	p.truck.apply_tuning()
	var i := players.find(p)
	if i < 0:
		i = players.size()   # en cours d'ajout (_add_player)
	# en ligne, ce PC ne garde que le choix de son joueur (case 0 du choix)
	if NetSession.is_online():
		if is_local(i):
			GameState.trailer_choice[0] = p.trailer
	elif i < GameState.trailer_choice.size():
		GameState.trailer_choice[i] = p.trailer


## Ligne du sas READY : « ◄ CITERNE ►  2/9 » puis ses stats.
static func trailer_text(index: int) -> String:
	var t := TrailerCatalog.at(index)
	return "◄  REMORQUE : %s  ►   (%d/%d)\n%s\nvitesse %s   accélération %s   adhérence %s   PV larguée %d" % [
		t.display_name, posmod(index, TrailerCatalog.count()) + 1, TrailerCatalog.count(), t.tagline,
		_pct(t.top_speed_mult), _pct(t.accel_mult), _pct(t.grip_mult), roundi(t.dropped_hp)]


static func _pct(mult: float) -> String:
	var d := roundi((mult - 1.0) * 100.0)
	return "=" if d == 0 else "%+d %%" % d


## Modele, couleur de repli et livree du joueur `i` (course et showroom).
static func dress(visual: TruckVisual, i: int) -> void:
	visual.external_model = MODELS[i]
	visual.mock_tint = TINTS[i]
	visual.livery = LIVERIES[i]


## Case libre (4e a 3 joueurs, 6e a 5) : camera TV, plus haute et plus loin,
## sur le camion en tete.
func _add_leader_view() -> void:
	var vp := _new_view("View%d" % (player_count + 1), false)
	var cam := ChaseCamera.new()
	cam.name = "LeaderCamera"
	cam.quality = quality
	cam.distance = 45.0
	cam.focus_height = 6.0
	cam.pitch_deg = 20.0
	cam.target = players[0].truck
	vp.add_child(cam)
	cam.snap()
	leader_camera = cam
	var layer := CanvasLayer.new()
	vp.add_child(layer)
	_leader_label = Label.new()
	_leader_label.position = Vector2(16, 10)
	_leader_label.add_theme_font_size_override("font_size", 24)
	_leader_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_leader_label.add_theme_constant_override("outline_size", 5)
	layer.add_child(_leader_label)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	var pad := event as InputEventJoypadButton
	var key_down := key != null and key.pressed and not key.echo
	var pad_down := pad != null and pad.pressed
	var restart := (key_down and key.physical_keycode == KEY_ENTER) \
			or (pad_down and pad.button_index == JOY_BUTTON_START)
	var to_menu := (key_down and key.physical_keycode == KEY_ESCAPE) \
			or (pad_down and pad.button_index == JOY_BUTTON_BACK and state == State.FINISHED)
	if to_menu:
		# en ligne : quitter la course, c'est quitter la partie (le host la ferme)
		NetSession.leave()
		get_tree().change_scene_to_file(MENU_SCENE)
		return
	if restart and state == State.FINISHED:
		# en ligne, seul le host relance, pour tout le monde
		if NetSession.is_host():
			NetSession.launch_race()
		elif not NetSession.is_online():
			# rejouer : meme course, derriere l'ecran de chargement
			LoadingScreen.go(get_tree(), scene_file_path)
		return
	if key_down and key.physical_keycode == KEY_F1:
		DebugDraw.enabled = not DebugDraw.enabled
	if key_down and key.physical_keycode == KEY_F11:
		GraphicsSettings.toggle_fullscreen()


func _physics_process(_delta: float) -> void:
	var tick := Engine.get_physics_frames()
	if _lost_reason != "":
		# partie perdue : course figee, message, puis menu
		if tick - _lost_tick >= LOST_TICKS:
			get_tree().change_scene_to_file(MENU_SCENE)
		return
	if not is_authority():
		_client_tick(tick)
		return
	_simulate(tick)
	if net != null:
		net.host_tick(tick)


## Le deroule de la course, sur la machine qui fait foi (hors ligne, host).
func _simulate(tick: int) -> void:
	if _held:
		_neutral.tick = tick
		for p in players:
			p.input.poll(tick)
			p.truck.set_input(_neutral)
		return
	if state == State.LOBBY:
		# sas READY : camions immobiles ; gauche / droite (SA source) = remorque
		# precedente / suivante, Carre (le boost de SA source) = pret
		_neutral.tick = tick
		for i in players.size():
			var f := players[i].input.poll(tick)
			players[i].truck.set_input(_neutral)
			var dir := 0
			if f.steer > TRAILER_STEER_THRESHOLD:
				dir = 1
			elif f.steer < -TRAILER_STEER_THRESHOLD:
				dir = -1
			# en ligne, la remorque est deja choisie au menu (page de selection)
			if dir != 0 and dir != _steer_was[i] and not ready_flags[i] and not NetSession.is_online():
				set_trailer(players[i], players[i].trailer + dir)
				if is_local(i):
					MenuSound.play_select()
			_steer_was[i] = dir
			if f.boost and not _square_was[i] and not ready_flags[i]:
				ready_flags[i] = true
				if is_local(i):
					MenuSound.play_confirm()
			_square_was[i] = f.boost
		if all_ready():
			# carrosseries deformables preparees maintenant, pas au premier choc
			for p in players:
				BodyDamage.prewarm(p.truck.get_node_or_null(^"Visual") as Node3D)
			_enter_countdown(tick)
		return
	if state == State.COUNTDOWN:
		# camions immobilises jusqu'au depart
		_neutral.tick = tick
		for p in players:
			p.input.poll(tick)
			p.truck.set_input(_neutral)
		_countdown_beeps(tick)
		if tick - _state_tick >= COUNTDOWN_TICKS:
			race.start()
			_enter_racing(tick)
			# pas de largage pendant les premieres secondes (bouchon au depart)
			for p in players:
				var cargo := p.truck.get_node_or_null(^"Cargo") as TruckCargo
				if cargo != null:
					cargo.start_race_lock()
					# largages de la course, choisis au menu (en ligne : ceux du host)
					cargo.drops_left = GameState.trailer_drops
		return
	# temps limite apres la premiere arrivee (une course se termine toujours)
	_check_all_finished()
	for p in players:
		var f := p.input.poll(tick)
		p.truck.set_input(f)
		if f.reset and not p.truck.is_wrecked():
			p.truck.reset_to(race.respawn_transform(p.truck))
			if p.camera != null:
				p.camera.snap()


func _enter_countdown(tick: int) -> void:
	state = State.COUNTDOWN
	_state_tick = tick
	_last_countdown_sec = -1


func _enter_racing(tick: int) -> void:
	state = State.RACING
	_state_tick = tick
	CountdownSound.play_go()
	music.play()


## Bips du compte a rebours (3, 2, 1), une fois par seconde.
func _countdown_beeps(tick: int) -> void:
	var sec := 3 - floori(float(tick - _state_tick) / 60.0)
	if sec != _last_countdown_sec and sec >= 1 and sec <= 3:
		_last_countdown_sec = sec
		CountdownSound.play_tick()


# --- course en ligne (NetRace) ----------------------------------------------------

## Client : le camion de cette machine est predit (sa frame lui est appliquee
## tout de suite, sans attendre le host), les autres sont poses sur les
## snapshots ; l'input part au host, qui fait foi.
func _client_tick(tick: int) -> void:
	var local := _local_player()
	var f := local.input.poll(tick) if local != null else _neutral
	if local != null:
		_neutral.tick = tick
		# sas READY et compte a rebours : camion immobile, comme chez le host
		local.truck.set_input(f if state == State.RACING or state == State.FINISHED else _neutral)
		if state == State.RACING and f.reset and not local.truck.is_wrecked() and not local.truck.is_net_puppet():
			local.truck.reset_to(race.respawn_transform(local.truck))
			local.camera.snap()
	net.client_tick(tick, f)
	if state == State.COUNTDOWN:
		_countdown_beeps(tick)


func _local_player() -> Player:
	for i in players.size():
		if is_local(i):
			return players[i]
	return null


## Etat de la course que le host diffuse (NetRace) : etat, tick d'entree
## (horloge du host), sas READY, remorques, tick du depart des chronos.
func net_state() -> Array:
	var trailers := PackedInt32Array()
	for p in players:
		trailers.append(p.trailer)
	return [int(state), _state_tick, ready_flags.duplicate(), trailers, race.start_tick]


## Client : applique l'etat recu du host (net_state). Les ticks du host sont
## ramenes a l'horloge de cette machine.
func apply_net_state(s: Array) -> void:
	if s.size() != 5:
		return
	var trailers := s[3] as PackedInt32Array
	for i in mini(players.size(), trailers.size()):
		if players[i].trailer != trailers[i]:
			set_trailer(players[i], trailers[i])
	var flags := s[2] as Array
	for i in mini(ready_flags.size(), flags.size()):
		if bool(flags[i]) and not ready_flags[i] and is_local(i):
			MenuSound.play_confirm()
		ready_flags[i] = bool(flags[i])
	var start := int(s[4])
	if start >= 0:
		race.start_tick = net.to_local_tick(start)
	var next: int = clampi(int(s[0]), 0, State.size() - 1)
	if next == int(state):
		return
	var now := Engine.get_physics_frames()
	if next == State.COUNTDOWN:
		# comme chez le host : carrosserie de NOTRE camion (predit, il se cabosse
		# ici) preparee maintenant, pas au premier choc (~0,5 s d'a-coup)
		var mine := _local_player()
		if mine != null:
			BodyDamage.prewarm(mine.truck.get_node_or_null(^"Visual") as Node3D)
		_enter_countdown(now)
	elif next == State.RACING:
		# depart manque (connexion en cours) : on part tout de suite
		_enter_racing(mini(net.to_local_tick(int(s[1])), now))
	elif next == State.FINISHED:
		state = State.FINISHED
		music.fade_out()
	else:
		state = State.LOBBY


## Host : le joueur `i` a quitte la partie ; il ne bloque ni le sas READY ni
## la fin de course.
func mark_abandoned(i: int) -> void:
	if _abandoned.has(i):
		return
	_abandoned.append(i)
	ready_flags[i] = true
	_check_all_finished()


## Client : la partie est perdue (host parti) ; le menu affiche la raison
## (NetSession.last_error).
func _on_connection_lost(reason: String) -> void:
	if _lost_reason == "":
		_lost_reason = reason if reason != "" else "Connexion perdue"
		_lost_tick = Engine.get_physics_frames()
		music.fade_out()

## Joueurs par position courante (1er d'abord).
func ranking() -> Array[Player]:
	var order := players.duplicate()
	order.sort_custom(func(a: Player, b: Player) -> bool:
		return race.progress(a.truck) > race.progress(b.truck))
	var typed: Array[Player] = []
	typed.assign(order)
	return typed


## Joueur encore en course alors qu'un autre a deja fini (bandeau du haut).
func still_racing(r: RaceLaps.Racer) -> bool:
	return state == State.RACING and r != null and not r.finished and not _finish_order.is_empty()


## Bandeau des joueurs encore en course : premier arrive, temps limite, et
## l'annonce du moment (un joueur parti).
func ticker_text() -> String:
	var parts := PackedStringArray()
	if _notice != "" and Engine.get_physics_frames() < _notice_until:
		parts.append(_notice.replace("\n", "  "))
	if not _finish_order.is_empty():
		parts.append("1er : %s  ·  %d/%d arrivés" % [player_name(players.find(_find_player(_finish_order[0]))),
			_finish_order.size(), players.size()])
	var left := RaceManager.deadline_left(Engine.get_physics_frames())
	if left >= 0:
		parts.append("FIN DANS %d s" % ceili(left / 60.0))
	return "  ·  ".join(parts)


func _find_player(truck: Truck) -> Player:
	for p in players:
		if p.truck == truck:
			return p
	return null


## Classement affiche a tous des la premiere arrivee : rang, nom, temps
## (ou "en course").
func standings_text() -> String:
	if players.size() < 2 or _finish_order.is_empty():
		return ""
	var lines := PackedStringArray(["CLASSEMENT"])
	var rank := 1
	for p in ranking():
		var r := race.racer(p.truck)
		var time := RaceHud.chrono(r.finish_ticks) if r.finished else "en course"
		if _abandoned.has(players.find(p)) and not r.finished:
			time = "abandon"
		elif state == State.FINISHED and not r.finished:
			time = "non classé"
		lines.append("%d. %s   %s" % [rank, player_name(players.find(p)), time])
		rank += 1
	return "\n".join(lines)


## Ralenti d'arrivee (tache 7.4) : quand le dernier camion passe la ligne,
## hors ligne et pas au temps limite, le temps du jeu tombe a SLOWMO_SCALE
## pendant SLOWMO_HOLD_S puis revient en douceur a 1 a SLOWMO_TOTAL_S
## (secondes REELLES). Presentation seulement : la simulation compte toujours
## ses ticks, il y en a juste moins par seconde. En ligne, jamais (le host
## ralentirait tout le monde).
const SLOWMO_SCALE := 0.3
const SLOWMO_HOLD_S := 0.7
const SLOWMO_TOTAL_S := 1.8
var _slowmo_t: float = -1.0


static func slowmo_scale(t: float) -> float:
	if t < 0.0 or t >= SLOWMO_TOTAL_S:
		return 1.0
	if t < SLOWMO_HOLD_S:
		return SLOWMO_SCALE
	var u := (t - SLOWMO_HOLD_S) / (SLOWMO_TOTAL_S - SLOWMO_HOLD_S)
	return lerpf(SLOWMO_SCALE, 1.0, u * u * (3.0 - 2.0 * u))


func slowmo_active() -> bool:
	return _slowmo_t >= 0.0


func _start_slowmo() -> void:
	_slowmo_t = 0.0
	Engine.time_scale = SLOWMO_SCALE


## delta est deja ralenti par time_scale : on avance en temps reel.
func _update_slowmo(delta: float) -> void:
	if _slowmo_t < 0.0:
		return
	_slowmo_t += delta / maxf(Engine.time_scale, 0.01)
	Engine.time_scale = slowmo_scale(_slowmo_t)
	if _slowmo_t >= SLOWMO_TOTAL_S:
		_slowmo_t = -1.0
		Engine.time_scale = 1.0


func _exit_tree() -> void:
	# menu ou rejouer en plein ralenti : le jeu repart a vitesse normale
	Engine.time_scale = 1.0


func _process(delta: float) -> void:
	_update_slowmo(delta)
	var elapsed := Engine.get_physics_frames() - _state_tick
	var standings := standings_text()
	if _notice != "" and Engine.get_physics_frames() < _notice_until:
		standings = _notice + ("\n\n" + standings if standings != "" else "")
	var unstable := net != null and not net.is_host() and net.host_ready and _lost_reason == "" \
			and net.ticks_since_snapshot() > UNSTABLE_TICKS
	for i in players.size():
		var p := players[i]
		if p.hud == null:
			continue   # joueur d'une autre machine (en ligne)
		var r := race.racer(p.truck)
		# encore en course apres la premiere arrivee : pas de carte au milieu
		# de sa route, un bandeau en haut (le classement complet attend la fin)
		var still := still_racing(r)
		p.hud.set_standings("" if still else standings)
		p.hud.set_ticker(ticker_text() if still else "")
		if _lost_reason != "":
			p.hud.set_center_message("CONNEXION PERDUE\n%s\nretour au menu..." % _lost_reason, Color(1.0, 0.4, 0.3))
			continue
		if unstable:
			p.hud.set_center_message("CONNEXION INSTABLE...\nplus de nouvelles du host depuis %.1f s" % (net.ticks_since_snapshot() / 60.0),
				Color(1.0, 0.75, 0.3))
			continue
		var local_in := p.input as LocalInputSource
		if local_in != null and local_in.use_pad and local_in.pad != null and local_in.pad.unplugged:
			# sa manette debranchee : roue libre, jamais de pause (INPUT_SPEC §6)
			p.hud.set_center_message("MANETTE DÉCONNECTÉE\nrebranchez-la pour reprendre votre camion",
				Color(1.0, 0.6, 0.3))
			continue
		if state == State.LOBBY and net != null and not net.is_host() and not net.host_ready:
			# client : le host charge encore la course, l'invite READY attendra
			p.hud.set_center_message("%s\nCONNEXION AU HOST..." % player_tag(i), Color(1.0, 0.85, 0.2))
		elif state == State.LOBBY:
			if ready_flags[i]:
				p.hud.set_center_message("%s\nREADY !  remorque %s\nen attente des autres (%d/%d)" % [
					player_tag(i), TrailerCatalog.at(p.trailer).display_name,
					ready_flags.count(true), players.size()], Color(0.3, 1.0, 0.25))
			else:
				# invite clignotante (2 fois par seconde) ; la remorque reste lisible
				var on := int(Time.get_ticks_msec() / 400) % 2 == 0
				# en ligne, convoi deja choisi au menu : il reste affiche, sans fleches
				var convoy := ("REMORQUE : %s" % TrailerCatalog.at(p.trailer).display_name) \
						if NetSession.is_online() else trailer_text(p.trailer)
				p.hud.set_center_message("%s\n%s\nAPPUYER SUR [CARRÉ] POUR ÊTRE READY" % [player_tag(i),
					convoy], Color(1.0, 0.85, 0.2, 1.0 if on else 0.6))
		elif state == State.COUNTDOWN:
			var c: Dictionary = GameStateNode.SPEED_CLASSES[GameState.speed_class]
			p.hud.set_center_message("%d\n%s %s" % [maxi(3 - floori(elapsed / 60.0), 1),
				String(c["name"]).to_upper(), c["cc"]], Color(1.0, 0.85, 0.2))
		elif r != null and r.finished:
			var rank := _finish_order.find(p.truck) + 1
			var more := "\nOptions / Entree : rejouer   Create / Echap : menu" if state == State.FINISHED \
					else "\nen attente des autres"
			if state == State.FINISHED and NetSession.is_client():
				more = "\nle host relance la course   Create / Echap : quitter la partie"
			var place := ("%de" % rank) if players.size() > 1 else "ARRIVEE"
			if players.size() > 1 and rank == 1:
				place = "1er !"
			p.hud.set_center_message("%s\n%s   meilleur tour %s%s" % [place,
				RaceHud.chrono(r.finish_ticks), RaceHud.chrono(r.best_lap), more], Color.WHITE)
		elif state == State.FINISHED:
			# temps limite ecoule avant son arrivee
			var again := "le host relance la course" if NetSession.is_client() else "Options / Entree : rejouer"
			p.hud.set_center_message("NON CLASSÉ\ntemps limite écoulé\n%s   Create / Échap : menu" % again,
				Color(1.0, 0.6, 0.35))
		elif still:
			p.hud.set_center_message("")    # le temps limite est dans le bandeau
		else:
			p.hud.set_center_message("GO !" if elapsed < GO_TICKS and state == State.RACING else "",
				Color(0.4, 1.0, 0.4))
	if leader_camera != null:
		var leader := ranking()[0]
		leader_camera.target = leader.truck
		_leader_label.text = "EN TETE : %s" % player_name(players.find(leader))
		if standings != "":
			_leader_label.text = standings


func _on_race_finished(truck: Truck, _total: int) -> void:
	RaceManager.record_finish(truck, Engine.get_physics_frames())
	_check_all_finished()


## Tour boucle par un joueur de cet ecran : carillon, dernier tour, arrivee
## (RaceSound). Les camions des autres joueurs en ligne ne sonnent pas ici.
func _on_lap_completed(truck: Truck, lap: int, _lap_ticks: int) -> void:
	for i in players.size():
		if players[i].truck == truck and is_local(i):
			last_cue = RaceSound.cue_for(lap, race.total_laps)
			RaceSound.play(last_cue)
			return


## Tous arrives (ou partis, en ligne), ou temps limite ecoule apres la
## premiere arrivee : resultats. Le client attend le host (apply_net_state).
func _check_all_finished() -> void:
	var tick := Engine.get_physics_frames()
	if is_authority() and RaceManager.should_finish(tick, players.size(), _abandoned.size()):
		RaceManager.finish(tick, RaceManager.deadline_left(tick) == 0 \
				and _finish_order.size() + _abandoned.size() < players.size())
		music.fade_out()
		if not NetSession.is_online() and not RaceManager.ended_by_timeout:
			_start_slowmo()
