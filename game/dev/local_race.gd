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
const COUNTDOWN_TICKS := 180      # 3 s
const GO_TICKS := 60              # "GO !" reste 1 s
const MODELS: PackedStringArray = [
	"../Assets_Visuels/Camion/Camions_Course_Export/Camion_Bleu.glb",
	"../Assets_Visuels/Camion/Camions_Course_Export/Camion_Rouge.glb",
	"../Assets_Visuels/Camion/Camions_Course_Export/Camion_Jaune.glb",
	"../Assets_Visuels/Camion/Camions_Course_Export/Camion_Vert.glb",
	# J5 et J6 : pas de modele a eux (aucun .glb dans le depot) ; ils
	# reprennent un modele existant, repeint par leur livree (LIVERIES)
	"../Assets_Visuels/Camion/Camions_Course_Export/Camion_Bleu.glb",
	"../Assets_Visuels/Camion/Camions_Course_Export/Camion_Rouge.glb",
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
const HELP_SOLO := "Manette (DualSense, facon Forza) : R2 accelerer, L2 freiner / reculer, Croix ou R1 drift, Carre nitro (recharge 6 s),\nTriangle remorque, L1 klaxon, R3 camera, Options reset.   Clavier : ZQSD ou fleches, Espace drift, Maj boost, E cargo, H klaxon, C camera, R reset.   Echap : menu"
const HELP_SPLIT: PackedStringArray = [
	"J1 : manette 1, ou fleches + Ctrl droit (drift), Maj droite (boost), ; (cargo), Retour arriere (reset)",
	"J2 : manette 2, ou ZQSD + Espace (drift), Maj gauche (boost), E (cargo), R (reset)",
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
	var input: LocalInputSource
	var camera: ChaseCamera
	var hud: RaceHud
	var viewport: SubViewport
	## Reglage ajuste a la categorie de vitesse, avant la remorque.
	var base_tuning: VehicleTuning
	## Remorque choisie (index dans TrailerCatalog).
	var trailer: int = 0

## Stick ou fleches au-dela de ce seuil : remorque suivante / precedente.
const TRAILER_STEER_THRESHOLD := 0.6


@export_range(1, 6) var player_count: int = 2
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
var state: State = State.COUNTDOWN
## Conteneur de l'ecran partage (VBoxContainer ou GridContainer), null en solo.
var split: Container
## Camera de la case libre (la 4e a 3 joueurs, la 6e a 5) : suit le camion en
## tete.
var leader_camera: ChaseCamera
var _leader_label: Label
var _state_tick: int = 0
var _last_countdown_sec: int = -1
var _neutral: InputFrame = InputFrame.new()
var _finish_order: Array[Truck] = []
## Sas READY : joueur pret, Carre (boost) enfonce au tick precedent.
var ready_flags: Array[bool] = []
var _square_was: Array[bool] = []
## Sas READY : direction du stick au tick precedent (-1, 0, 1), pour ne
## changer de remorque qu'une fois par poussee.
var _steer_was: Array[int] = []
## Musique de course : demarre au GO, fondu a l'arrivee (inerte en headless).
var music: RaceMusic


func _ready() -> void:
	if players_from_menu and GameState.requested_players > 0:
		player_count = clampi(GameState.requested_players, 1, MAX_PLAYERS)
	# vue propre par defaut : F1 affiche les traces de debug
	DebugDraw.enabled = false
	_apply_graphics()
	# de nuit, les phares des camions eclairent la route
	TruckLights.night = track.theme_id == TrackTheme.Id.CYBER_CITY
	auto_reset.respawn_provider = race.respawn_transform
	race.race_finished.connect(_on_race_finished)
	music = RaceMusic.new()
	music.name = "RaceMusic"
	add_child(music)
	RaceMusic.prepare()
	split = _build_split_screen()
	for i in player_count:
		players.append(_add_player(i))
	if player_count == 3 or player_count == 5:
		_add_leader_view()
	for i in player_count:
		ready_flags.append(false)
		_square_was.append(false)
		_steer_was.append(0)
	state = State.LOBBY if ready_gate else State.COUNTDOWN
	_state_tick = Engine.get_physics_frames()


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
	var views := player_count + (1 if player_count == 3 or player_count == 5 else 0)
	var world := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world != null:
		GraphicsSettings.apply_environment(world.environment, GameState.graphics_quality, views)
	GraphicsSettings.apply_viewport(get_viewport(), GameState.graphics_quality)


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
	GraphicsSettings.apply_viewport(vp, GameState.graphics_quality)
	container.add_child(vp)
	return vp


func _add_player(i: int) -> Player:
	var p := Player.new()
	# camion : modele et couleur du joueur, case de depart i (centre de la grille)
	var t := (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
	t.name = "Truck%d" % (i + 1)
	dress(t.get_node("Visual") as TruckVisual, i)
	t.transform = track.get_start_transform(i)   # pose d'un camion immobile
	# categorie de vitesse du menu (Normal par defaut : le reglage mesure)
	p.base_tuning = GameStateNode.speed_tuning(t.tuning, GameState.speed_class)
	t.tuning = p.base_tuning
	add_child(t)
	p.truck = t
	# remorque choisie a la course precedente (Conteneur la premiere fois)
	set_trailer(p, GameState.trailer_choice[i] if i < GameState.trailer_choice.size() else 0)
	race.watch(t)
	auto_reset.watch(t)
	# 0 PV : epave 3 s, puis reapparition sur la piste (jamais un checkpoint
	# saute : RaceLaps.respawn_transform)
	var health := TruckHealth.of(t)
	if health != null:
		health.respawn_provider = race.respawn_transform
	# input : sa manette seulement en ecran partage ; son jeu de touches
	# (fleches pour J1, ZQSD pour J2, aucun au-dela)
	var input := LocalInputSource.new()
	input.name = "Input%d" % (i + 1)
	if player_count > 1:
		input.device = i
		match i:
			0: input.keyboard_layout = KeyboardInputSource.Layout.ARROWS
			1: input.keyboard_layout = KeyboardInputSource.Layout.ZQSD
			_: input.keyboard_layout = KeyboardInputSource.Layout.NONE
	add_child(input)
	p.input = input
	# vue : plein ecran, ou une case de l'ecran partage (son 3D : J1)
	var view_parent: Node = self
	if split != null:
		p.viewport = _new_view("View%d" % (i + 1), i == 0)
		view_parent = p.viewport
	var cam := ChaseCamera.new()
	cam.name = "Camera%d" % (i + 1)
	cam.target = t
	view_parent.add_child(cam)
	cam.snap()
	p.camera = cam
	# nuit pluvieuse : la pluie tombe autour de chaque camera
	if track.theme_id == TrackTheme.Id.CYBER_CITY and DisplayServer.get_name() != "headless":
		view_parent.add_child(RainFx.make(cam.get_camera()))
	input.camera_toggle_requested.connect(cam.toggle_view)
	if health != null:
		health.respawned.connect(cam.snap)
	var hud := RaceHud.new()
	hud.truck = t
	hud.race = race
	hud.player_label = NAMES[i]
	hud.help_text = HELP_SOLO if player_count == 1 else HELP_SPLIT[i]
	hud.ui_scale = HUD_SCALE[player_count - 1]
	view_parent.add_child(hud)
	p.hud = hud
	return p


## Joueur et manette, pour le sas READY : « J1 - BLEU (Manette 1 / fleches) ».
func player_tag(i: int) -> String:
	var device := "manette ou clavier"
	if player_count > 1:
		device = "Manette %d" % (i + 1)
		if i == 0:
			device += " / flèches"
		elif i == 1:
			device += " / ZQSD"
	return "J%d - %s (%s)" % [i + 1, COLOR_NAMES[i], device]


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
	if i < GameState.trailer_choice.size():
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
		get_tree().change_scene_to_file(MENU_SCENE)
		return
	if restart and state == State.FINISHED:
		get_tree().reload_current_scene()
		return
	if key_down and key.physical_keycode == KEY_F1:
		DebugDraw.enabled = not DebugDraw.enabled
	if key_down and key.physical_keycode == KEY_F11:
		GraphicsSettings.toggle_fullscreen()


func _physics_process(_delta: float) -> void:
	var tick := Engine.get_physics_frames()
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
			if dir != 0 and dir != _steer_was[i] and not ready_flags[i]:
				set_trailer(players[i], players[i].trailer + dir)
				MenuSound.play_select()
			_steer_was[i] = dir
			if f.boost and not _square_was[i] and not ready_flags[i]:
				ready_flags[i] = true
				MenuSound.play_confirm()
			_square_was[i] = f.boost
		if all_ready():
			# carrosseries deformables preparees maintenant, pas au premier choc
			for p in players:
				BodyDamage.prewarm(p.truck.get_node_or_null(^"Visual") as Node3D)
			state = State.COUNTDOWN
			_state_tick = tick
			_last_countdown_sec = -1
		return
	if state == State.COUNTDOWN:
		# camions immobilises jusqu'au depart
		_neutral.tick = tick
		for p in players:
			p.input.poll(tick)
			p.truck.set_input(_neutral)
		var elapsed := tick - _state_tick
		var sec := 3 - floori(float(elapsed) / 60.0)
		if sec != _last_countdown_sec and sec >= 1 and sec <= 3:
			_last_countdown_sec = sec
			CountdownSound.play_tick()
		if elapsed >= COUNTDOWN_TICKS:
			race.start()
			state = State.RACING
			_state_tick = tick
			# pas de largage pendant les premieres secondes (bouchon au depart)
			for p in players:
				var cargo := p.truck.get_node_or_null(^"Cargo") as TruckCargo
				if cargo != null:
					cargo.start_race_lock()
			CountdownSound.play_go()
			music.play()
		return
	for p in players:
		var f := p.input.poll(tick)
		p.truck.set_input(f)
		if f.reset and not p.truck.is_wrecked():
			p.truck.reset_to(race.respawn_transform(p.truck))
			p.camera.snap()


## Joueurs par position courante (1er d'abord).
func ranking() -> Array[Player]:
	var order := players.duplicate()
	order.sort_custom(func(a: Player, b: Player) -> bool:
		return race.progress(a.truck) > race.progress(b.truck))
	var typed: Array[Player] = []
	typed.assign(order)
	return typed


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
		lines.append("%d. %s   %s" % [rank, NAMES[players.find(p)], time])
		rank += 1
	return "\n".join(lines)


func _process(_delta: float) -> void:
	var elapsed := Engine.get_physics_frames() - _state_tick
	var standings := standings_text()
	for i in players.size():
		var p := players[i]
		var r := race.racer(p.truck)
		p.hud.set_standings(standings)
		if state == State.LOBBY:
			if ready_flags[i]:
				p.hud.set_center_message("%s\nREADY !  remorque %s\nen attente des autres (%d/%d)" % [
					player_tag(i), TrailerCatalog.at(p.trailer).display_name,
					ready_flags.count(true), players.size()], Color(0.3, 1.0, 0.25))
			else:
				# invite clignotante (2 fois par seconde) ; la remorque reste lisible
				var on := int(Time.get_ticks_msec() / 400) % 2 == 0
				p.hud.set_center_message("%s\n%s\nAPPUYER SUR [CARRÉ] POUR ÊTRE READY" % [player_tag(i),
					trailer_text(p.trailer)], Color(1.0, 0.85, 0.2, 1.0 if on else 0.6))
		elif state == State.COUNTDOWN:
			var c: Dictionary = GameStateNode.SPEED_CLASSES[GameState.speed_class]
			p.hud.set_center_message("%d\n%s %s" % [maxi(3 - floori(elapsed / 60.0), 1),
				String(c["name"]).to_upper(), c["cc"]], Color(1.0, 0.85, 0.2))
		elif r != null and r.finished:
			var rank := _finish_order.find(p.truck) + 1
			var more := "\nOptions / Entree : rejouer   Create / Echap : menu" if state == State.FINISHED \
					else "\nen attente des autres"
			var place := ("%de" % rank) if player_count > 1 else "ARRIVEE"
			if player_count > 1 and rank == 1:
				place = "1er !"
			p.hud.set_center_message("%s\n%s   meilleur tour %s%s" % [place,
				RaceHud.chrono(r.finish_ticks), RaceHud.chrono(r.best_lap), more], Color.WHITE)
		else:
			p.hud.set_center_message("GO !" if elapsed < GO_TICKS and state == State.RACING else "",
				Color(0.4, 1.0, 0.4))
	if leader_camera != null:
		var leader := ranking()[0]
		leader_camera.target = leader.truck
		_leader_label.text = "EN TETE : %s" % NAMES[players.find(leader)]
		if standings != "":
			_leader_label.text = standings


func _on_race_finished(truck: Truck, _total: int) -> void:
	_finish_order.append(truck)
	if _finish_order.size() == players.size():
		state = State.FINISHED
		music.fade_out()
