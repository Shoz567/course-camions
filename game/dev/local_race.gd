extends Node3D

## Course locale de 3 tours sur la piste n°1, de 1 a 4 joueurs.
##
##   1 joueur    : plein ecran, n'importe quelle manette + tout le clavier.
##   2 joueurs   : ecran partage haut / bas (VBoxContainer).
##   3-4 joueurs : grille 2 x 2 (GridContainer). A 3, la 4e case suit le
##                 camion en tete (camera TV).
##
##   J1 camion bleu AZUR     manette 0 (+ fleches en ecran partage)
##   J2 camion rouge DURAND  manette 1 (+ ZQSD)
##   J3 camion jaune SOLEIL  manette 2
##   J4 camion vert          manette 3
##
## Chaque joueur a sa source d'input (sa manette, et AUCUNE autre : INPUT_SPEC
## §4), son camion, sa camera, son HUD. Compte a rebours commun, puis course :
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
]
const NAMES: PackedStringArray = ["J1 AZUR", "J2 DURAND", "J3 SOLEIL", "J4 VERT"]
## Couleur des boites quand le modele est absent (clone neuf).
const TINTS: Array[Color] = [Color(0.15, 0.35, 0.9), Color(0.85, 0.12, 0.1),
	Color(0.95, 0.8, 0.1), Color(0.15, 0.7, 0.25)]
const HELP_SOLO := "Manette (DualSense, facon Forza) : R2 accelerer, L2 freiner / reculer, Croix ou R1 drift, Carre nitro (recharge 6 s),\nTriangle remorque, L1 klaxon, R3 camera, Options reset.   Clavier : ZQSD ou fleches, Espace drift, Maj boost, E cargo, H klaxon, C camera, R reset.   Echap : menu"
const HELP_SPLIT: PackedStringArray = [
	"J1 : manette 1, ou fleches + Ctrl droit (drift), Maj droite (boost), ; (cargo), Retour arriere (reset)",
	"J2 : manette 2, ou ZQSD + Espace (drift), Maj gauche (boost), E (cargo), R (reset)",
	"J3 : manette 3",
	"J4 : manette 4",
]
## Echelle du HUD selon le nombre de joueurs (vues plus petites).
const HUD_SCALE: Array[float] = [1.0, 0.85, 0.6, 0.6]

enum State { COUNTDOWN, RACING, FINISHED }

class Player:
	var truck: Truck
	var input: LocalInputSource
	var camera: ChaseCamera
	var hud: RaceHud
	var viewport: SubViewport


@export_range(1, 4) var player_count: int = 2
## Vrai : le nombre de joueurs choisi dans le menu remplace `player_count`.
@export var players_from_menu: bool = false

@onready var track: TrackBlockout = $Track01
@onready var race: RaceLaps = $RaceLaps
@onready var auto_reset: AutoReset = $AutoReset

var players: Array[Player] = []
var state: State = State.COUNTDOWN
## Conteneur de l'ecran partage (VBoxContainer ou GridContainer), null en solo.
var split: Container
## Camera de la 4e case a 3 joueurs : suit le camion en tete.
var leader_camera: ChaseCamera
var _leader_label: Label
var _state_tick: int = 0
var _last_countdown_sec: int = -1
var _neutral: InputFrame = InputFrame.new()
var _finish_order: Array[Truck] = []
## Musique de course : demarre au GO, fondu a l'arrivee (inerte en headless).
var music: RaceMusic


func _ready() -> void:
	if players_from_menu and GameState.requested_players > 0:
		player_count = clampi(GameState.requested_players, 1, 4)
	# vue propre par defaut : F1 affiche les traces de debug
	DebugDraw.enabled = false
	auto_reset.respawn_provider = race.respawn_transform
	race.race_finished.connect(_on_race_finished)
	music = RaceMusic.new()
	music.name = "RaceMusic"
	add_child(music)
	RaceMusic.prepare()
	split = _build_split_screen()
	for i in player_count:
		players.append(_add_player(i))
	if player_count == 3:
		_add_leader_view()
	_state_tick = Engine.get_physics_frames()


## Ecran partage : haut / bas a 2, grille 2 x 2 a 3-4 (haut gauche = J1).
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
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 4)
		grid.add_theme_constant_override("v_separation", 4)
		box = grid
	box.name = "SplitScreen"
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(box)
	return box


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
	container.add_child(vp)
	return vp


func _add_player(i: int) -> Player:
	var p := Player.new()
	# camion : modele et couleur du joueur, case de depart i (centre de la grille)
	var t := (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
	t.name = "Truck%d" % (i + 1)
	var visual := t.get_node("Visual") as TruckVisual
	visual.external_model = MODELS[i]
	visual.mock_tint = TINTS[i]
	t.transform = track.get_start_transform(i)   # pose d'un camion immobile
	# categorie de vitesse du menu (Normal par defaut : le reglage mesure)
	t.tuning = GameStateNode.speed_tuning(t.tuning, GameState.speed_class)
	add_child(t)
	p.truck = t
	race.watch(t)
	auto_reset.watch(t)
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
	input.camera_toggle_requested.connect(cam.toggle_view)
	var hud := RaceHud.new()
	hud.truck = t
	hud.race = race
	hud.player_label = NAMES[i]
	hud.help_text = HELP_SOLO if player_count == 1 else HELP_SPLIT[i]
	hud.ui_scale = HUD_SCALE[player_count - 1]
	view_parent.add_child(hud)
	p.hud = hud
	return p


## 4e case a 3 joueurs : camera TV, plus haute et plus loin, sur le camion en
## tete.
func _add_leader_view() -> void:
	var vp := _new_view("View4", false)
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


func _physics_process(_delta: float) -> void:
	var tick := Engine.get_physics_frames()
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
			CountdownSound.play_go()
			music.play()
		return
	for p in players:
		var f := p.input.poll(tick)
		p.truck.set_input(f)
		if f.reset:
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
	for p in players:
		var r := race.racer(p.truck)
		p.hud.set_standings(standings)
		if state == State.COUNTDOWN:
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
