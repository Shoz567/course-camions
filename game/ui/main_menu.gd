class_name MainMenu
extends Node3D

## Ecran d'accueil (tache 4.2, partiel) : titre anime, choix du circuit (Cyber
## City ou Playa Del Sol), du nombre de joueurs (1 a 6), de la categorie de
## vitesse, PRET, son on / off, parametres. Charte arcade neon (UiKit,
## 2026-10-16). PRET ouvre la page de selection (LoadoutSelect) : chaque
## joueur y choisit remorque et pouvoirs, puis la course part. Decor dedie
## (Showroom) : les camions des joueurs choisis exposes sur un plateau tournant,
## sur le toit d'une tour de Cyber City, sous les projecteurs ; camera en orbite
## lente, decalee pour montrer les camions a droite, le menu a gauche.
## Ambiance du circuit choisi (2026-10-19) : le decor du showroom, le ciel et
## la lumiere (Cyber City de nuit, Playa au soleil, jardin japonais), et toute
## l'interface (UiKit : neon, plage, bois et laque) changent avec lui ;
## l'interface se reconstruit (_restyle) et retrouve son etat.
##
## Manette (PlayStation, positions SDL) : croix directionnelle ou stick pour
## naviguer, Croix pour valider, Rond ou Create pour fermer les parametres,
## L1 / R1 pour changer le nombre de joueurs, Triangle pour changer de circuit,
## Options pour PRET.
## Clavier et souris : fleches + Entree, touches 1 a 6, T (circuit), clic ;
## F11 : plein ecran / fenetre ; Echap ferme les parametres, sinon quitte le
## jeu.
##
## Une fois tout le monde pret (LoadoutSelect), start_race ecrit le choix dans
## GameState (requested_players, selected_track, loadout_locked) puis charge la
## scene de course du circuit (LocalRace le lit, sans son sas READY). Le menu ne touche pas a la physique : les
## camions de decor sont geles.

signal launch_requested(players: int)

const LocalRace := preload("res://dev/local_race.gd")
## Ciel et brume de chaque circuit (les memes que ses courses).
const ENVIRONMENTS: Array[Environment] = [preload("res://tracks/cyber_night.tres"),
	preload("res://tracks/playa_sun.tres"), preload("res://tracks/sakura_day.tres")]

## Faux pour les tests : le depart emet `launch_requested` sans changer de scene.
@export var auto_change_scene: bool = true
@export var orbit_speed: float = 0.06        # rad/s
@export var orbit_radius: float = 46.0
@export var orbit_height: float = 9.0
## Decalage lateral de l'image (m) : les camions a droite, le menu a gauche.
@export var frame_offset: float = -20.0
## Champ de la camera : normal, et elargi quand 5 ou 6 camions sont exposes.
@export var fov_deg: float = 55.0
@export var fov_wide_deg: float = 72.0

@onready var showroom: Showroom = $Showroom
@onready var camera: Camera3D = $OrbitCamera

var selected_players: int = 1
var trucks: Array[Truck] = []
var player_buttons: Array[Button] = []
## Bots hors ligne : nombre (0 a 5) et niveau (facile, moyen, dur).
var bot_buttons: Array[Button] = []
var bot_level_buttons: Array[Button] = []
const BOT_LEVELS: PackedStringArray = ["FACILE", "MOYEN", "DUR"]
var speed_buttons: Array[Button] = []
var track_buttons: Array[Button] = []
var subtitle: Label
var title: Label
var start_button: Button
var sound_button: Button
var settings_button: Button
var settings: Control
## Ecran des parametres : case du son (miroir du bouton du menu), volume.
var sound_check: CheckButton
var volume_slider: HSlider
var quality_option: OptionButton
## Compteur d'images par seconde (GameState.show_fps).
var fps_check: CheckButton
## Resolution dynamique de la 3D (GameState.dynamic_resolution).
var dynres_check: CheckButton
## Panneau EN LIGNE (NetSession, phase 6) : pseudo, heberger, rejoindre par IP,
## lobby, lancement de la course par le host.
var online_button: Button
var online_panel: Control
var name_edit: LineEdit
var ip_edit: LineEdit
var host_button: Button
var join_button: Button
var launch_button: Button
var leave_button: Button
## En ligne : ouvre la page de selection (remorque, pouvoirs) de ce PC.
var convoy_button: Button
var online_status: Label
var lobby_label: Label
## Host : connexion qui envoie peu (snapshots a 20 Hz au lieu de 60).
var slow_check: CheckButton
## Salle d'attente (« appuyez sur Croix pour rejoindre », tache 4.2) :
## appareils inscrits, dans l'ordre d'arrivee (GameState.join_devices).
var waiting_button: Button
var join_panel: Control
var join_list: PackedInt32Array = PackedInt32Array()
var _join_slots: Array[Label] = []
## Reaffectation de la manette (tache 7.1) : panneau, bouton de chaque
## action, action qui attend son bouton ("" : aucune).
var remap_panel: Control
var _remap_buttons: Dictionary = {}
var remap_waiting: String = ""
var _gear: GearIcon
## Accueil (tout sauf les parametres et la page de selection).
var home: Control
## Page de selection, ouverte par PRET.
var loadout: LoadoutSelect
var _player_dots: HBoxContainer
var _pads_label: Label
var _orbit_center: Vector3
var _orbit_angle: float = 0.0
var _time: float = 0.0
var _fov_target: float = 55.0
## Lune de Cyber City (main_menu.tscn) : retrouvee en revenant de la plage.
var _moon_xf: Transform3D
var _ambiance: int = -1


func _ready() -> void:
	DebugDraw.enabled = false
	_setup_menu_input()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.current = true
	_moon_xf = ($Moon as DirectionalLight3D).transform
	showroom.camera = camera
	apply_ambiance(GameState.selected_track)
	_spawn_trucks()
	_build_ui()
	set_quality(GameState.graphics_quality)
	set_sound(not AudioServer.is_bus_mute(_master_bus()))
	# musique de course rendue en fond pendant le menu (sans effet en headless)
	RaceMusic.prepare()
	# on retrouve le dernier choix en revenant d'une course
	select_players(GameState.requested_players if GameState.requested_players > 0 else 1, false)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	for sig: Signal in [NetSession.lobby_changed, NetSession.joined, NetSession.race_launched]:
		sig.connect(_refresh_online)
	NetSession.join_failed.connect(func(_r: String) -> void: _refresh_online())
	NetSession.connection_lost.connect(func(_r: String) -> void: _refresh_online())
	_refresh_online()
	# retour de course : circuit, vitesse et remorques choisis sont gardes
	GameState.save_settings()
	start_button.grab_focus()
	# retour d'une partie en ligne (perdue ou en cours) : le panneau la montre
	if NetSession.is_online() or NetSession.last_error != "":
		toggle_online()
	_place_camera()



## Les 6 camions sur le plateau tournant, geles : du decor, pas de physique.
func _spawn_trucks() -> void:
	for i in LocalRace.MAX_PLAYERS:
		var t := (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
		t.name = "Truck%d" % (i + 1)
		LocalRace.dress(t.get_node("Visual") as TruckVisual, i)
		t.transform = Showroom.slot(i, LocalRace.MAX_PLAYERS)
		t.freeze = true
		showroom.turntable.add_child(t)
		# remorque choisie par ce joueur (sas READY), jamais celle d'origine
		(t.get_node("Visual") as TruckVisual).set_trailer_type(TrailerCatalog.at(GameState.trailer_choice[i]))
		trucks.append(t)
	_orbit_center = showroom.focus
	camera.h_offset = frame_offset


func _process(delta: float) -> void:
	if not is_node_ready() or settings == null or title == null or _gear == null or camera == null or start_button == null or settings_button == null:
		return
	_time += delta
	_orbit_angle = fmod(_orbit_angle + orbit_speed * delta, TAU)
	_place_camera()
	camera.fov = lerpf(camera.fov, _fov_target, 1.0 - exp(-5.0 * delta))
	# titre : respiration lente, ancree a gauche (le panneau reste aligne)
	title.pivot_offset = Vector2(0.0, title.size.y / 2.0)
	var s := 1.0 + 0.015 * sin(_time * 2.0)
	title.scale = Vector2(s, s)
	start_button.modulate = Color(1, 1, 1).lerp(Color(1.15, 1.12, 1.05), 0.5 + 0.5 * sin(_time * 4.0)) \
			if start_button.has_focus() else Color.WHITE
	_gear.fast = settings_button.has_focus() or settings_button.is_hovered() or settings.visible
	# PRET respire quand il a le focus
	start_button.pivot_offset = start_button.size / 2.0
	var k := 1.0 + (0.025 * sin(_time * 5.0) if start_button.has_focus() else 0.0)
	start_button.scale = Vector2(k, k)


func _place_camera() -> void:
	var offset := Vector3(sin(_orbit_angle), 0.0, cos(_orbit_angle)) * orbit_radius
	camera.global_position = _orbit_center + offset + Vector3.UP * orbit_height
	camera.look_at(_orbit_center, Vector3.UP)


## Godot 4.7 ne met aucun bouton de manette dans ui_accept / ui_cancel : le
## menu ajoute Croix (bas, JOY_BUTTON_A) pour valider et Rond (droite,
## JOY_BUTTON_B) pour revenir, comme sur PlayStation.
static func _setup_menu_input() -> void:
	for pair: Array in [["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B]]:
		var e := InputEventJoypadButton.new()
		e.device = -1
		e.button_index = pair[1]
		if not InputMap.action_has_event(pair[0], e):
			InputMap.action_add_event(pair[0], e)


func _unhandled_input(event: InputEvent) -> void:
	if loadout != null and loadout.visible:
		return    # la page de selection lit ses entrees elle-meme
	var key := event as InputEventKey
	var pad := event as InputEventJoypadButton
	if key != null and key.pressed and not key.echo:
		match key.physical_keycode:
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
				select_players(key.physical_keycode - KEY_0)
			KEY_T:
				if not settings.visible:
					select_track((GameState.selected_track + 1) % GameStateNode.TRACKS.size())
			KEY_F11:
				GraphicsSettings.toggle_fullscreen()
			KEY_ESCAPE:
				if settings.visible:
					toggle_settings()
				elif online_panel.visible:
					toggle_online()
				else:
					get_tree().quit()
			_:
				return
		get_viewport().set_input_as_handled()
	elif pad != null and pad.pressed:
		# Rond (ui_cancel par defaut de Godot) : ferme les parametres
		if event.is_action_pressed("ui_cancel") and settings.visible:
			toggle_settings()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("ui_cancel") and online_panel.visible:
			toggle_online()
			get_viewport().set_input_as_handled()
			return
		match pad.button_index:
			JOY_BUTTON_LEFT_SHOULDER:
				select_players(selected_players - 1)
			JOY_BUTTON_RIGHT_SHOULDER:
				select_players(selected_players + 1)
			JOY_BUTTON_Y:
				if not settings.visible:
					select_track((GameState.selected_track + 1) % GameStateNode.TRACKS.size())
			JOY_BUTTON_START:
				if not settings.visible:
					open_selection()
			JOY_BUTTON_BACK:
				if settings.visible:
					toggle_settings()
			_:
				return
		get_viewport().set_input_as_handled()


## Circuit (GameState.TRACKS), garde dans GameState pour la course et les
## suivantes ; le sous-titre, sous les boutons, annonce son ambiance.
func select_track(k: int) -> void:
	var prev := GameState.selected_track
	GameState.selected_track = clampi(k, 0, GameStateNode.TRACKS.size() - 1)
	if is_node_ready() and GameState.selected_track != prev:
		MenuSound.play_select()
		GameState.save_settings()
	for i in track_buttons.size():
		track_buttons[i].set_pressed_no_signal(i == GameState.selected_track)
	# ambiance du circuit : decor et ciel tout de suite, interface a la fin de
	# l'image (le bouton clique ne se libere pas pendant son propre signal)
	if is_node_ready() and GameState.selected_track != _ambiance:
		apply_ambiance(GameState.selected_track)
		call_deferred(&"_restyle")
	if subtitle != null:
		var t: Dictionary = GameStateNode.TRACKS[GameState.selected_track]
		var tag := String(t["tagline"])
		subtitle.text = "%s  ·  4 tours" % (tag.left(1).to_upper() + tag.substr(1))


## Ambiance du circuit `track` : habillage de l'interface (UiKit, pour les
## controles construits ensuite), decor du showroom, ciel, lumiere.
func apply_ambiance(track: int) -> void:
	_ambiance = clampi(track, 0, ENVIRONMENTS.size() - 1)
	UiKit.apply_skin(UiKit.skin_for_track(_ambiance))
	showroom.set_theme(_ambiance)
	var world := get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	if world != null:
		world.environment = ENVIRONMENTS[_ambiance]
		GraphicsSettings.apply_environment(world.environment, GameState.graphics_quality, 1)
	var sun := get_node_or_null(^"Moon") as DirectionalLight3D
	if sun == null:
		return
	match _ambiance:
		TrackTheme.Id.PLAYA_DEL_SOL:
			sun.transform = Transform3D(Basis(Vector3(0.819, 0.0, -0.574), Vector3(-0.383, 0.744, -0.547),
				Vector3(0.427, 0.668, 0.609)), _moon_xf.origin)
			sun.light_color = Color(1.0, 0.93, 0.78)
			sun.light_energy = 1.1
			sun.shadow_enabled = true
		TrackTheme.Id.SAKURA:
			sun.transform = Transform3D(Basis(Vector3(0.819, 0.0, -0.574), Vector3(-0.369, 0.766, -0.527),
				Vector3(0.439, 0.643, 0.628)), _moon_xf.origin)
			sun.light_color = Color(1.0, 0.86, 0.7)
			sun.light_energy = 1.25
			sun.shadow_enabled = true
		_:
			sun.transform = _moon_xf
			sun.light_color = Color(0.55, 0.62, 1.0)
			sun.light_energy = 0.3
			sun.shadow_enabled = false


## Reconstruit l'interface dans l'habillage courant et retrouve son etat :
## choix, panneau ouvert, focus sur le circuit.
func _restyle() -> void:
	var ui := get_node_or_null(^"UI")
	if ui == null:
		return
	var open := [settings.visible, online_panel.visible, join_panel.visible, remap_panel.visible]
	remove_child(ui)
	ui.queue_free()
	player_buttons.clear()
	bot_buttons.clear()
	bot_level_buttons.clear()
	speed_buttons.clear()
	track_buttons.clear()
	_join_slots.clear()
	_remap_buttons.clear()
	_build_ui()
	var on := not AudioServer.is_bus_mute(_master_bus())
	sound_button.set_pressed_no_signal(on)
	sound_button.text = "SON : ON" if on else "SON : OFF"
	sound_check.set_pressed_no_signal(on)
	select_players(selected_players, false)
	_refresh_online()
	settings.visible = open[0]
	online_panel.visible = open[1]
	join_panel.visible = open[2]
	remap_panel.visible = open[3]
	if join_panel.visible:
		_refresh_join()
	_update_home()
	if home.visible:
		track_buttons[GameState.selected_track].grab_focus()


## Scene de course du circuit choisi.
func race_scene() -> String:
	return GameStateNode.track_scene(GameState.selected_track)


## Categorie de vitesse (0 = Lent .. 3 = Ultrasonique), gardee dans GameState
## pour la course et les suivantes.
func select_speed(k: int) -> void:
	GameState.speed_class = clampi(k, 0, GameStateNode.SPEED_CLASSES.size() - 1)
	if is_node_ready():
		GameState.save_settings()
	for i in speed_buttons.size():
		speed_buttons[i].set_pressed_no_signal(i == GameState.speed_class)


## Bouton du joueur `i` : allume (dans le compte choisi) a la couleur de sa
## pastille (2026-10-19 : « 3 joueurs : 1, 2 et 3 colories, chacun de la
## couleur juste en dessous »), sinon tuile sombre ; le nombre choisi a en
## plus un liseré blanc et un halo.
static func paint_player_button(b: Button, i: int, lit: bool) -> void:
	var c := UiKit.PLAYER_COLORS[i]
	UiKit.style_choice(b, b.get_theme_font_size("font_size"), c)
	# habillage a tuiles (bois de Playa, de Sakura) : la tuile est gardee,
	# teintee a la couleur du joueur ; neon : aplat de sa couleur
	var tile := b.get_theme_stylebox("normal") as StyleBoxTexture
	if tile != null:
		if lit:
			for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
				var t := (b.get_theme_stylebox(state) as StyleBox).duplicate() as StyleBox
				if t is StyleBoxTexture:
					(t as StyleBoxTexture).modulate_color = c.lightened(0.2 if state.begins_with("hover") else 0.0)
				b.add_theme_stylebox_override(state, t)
		return
	b.add_theme_stylebox_override("pressed", UiKit.box(c, Color(1, 1, 1, 0.95), 3, UiKit.SKEW, 3, Color(c, 0.7), 14))
	b.add_theme_stylebox_override("hover_pressed", UiKit.box(c.lightened(0.1), Color.WHITE, 3, UiKit.SKEW, 3, Color(c, 0.8), 16))
	if not lit:
		return
	b.add_theme_stylebox_override("normal", UiKit.box(Color(c, 0.85), Color(1, 1, 1, 0.2), 1, UiKit.SKEW, 3, Color(c, 0.35), 8))
	b.add_theme_stylebox_override("hover", UiKit.box(c, Color(UiKit.CYAN, 0.6), 1, UiKit.SKEW, 3, Color(c, 0.45), 10))
	# texte sombre sur les couleurs claires (jaune, vert, orange)
	var ink := UiKit.NIGHT if c.get_luminance() > 0.55 else UiKit.TEXT
	for k: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, ink)


## Nombre de bots (borne pour que joueurs + bots ne depassent pas 6) ; les
## nombres trop grands sont grises.
func select_bots(n: int, save: bool = true) -> void:
	var room := LocalRace.MAX_PLAYERS - selected_players
	GameState.bot_count = clampi(n, 0, room)
	if save and is_node_ready():
		GameState.save_settings()
		MenuSound.play_select()
	for k in bot_buttons.size():
		bot_buttons[k].set_pressed_no_signal(k == GameState.bot_count)
		bot_buttons[k].disabled = k > room
	for k in bot_level_buttons.size():
		bot_level_buttons[k].disabled = GameState.bot_count == 0


func select_bot_level(k: int, save: bool = true) -> void:
	GameState.bot_level = clampi(k, 0, BOT_LEVELS.size() - 1)
	if save and is_node_ready():
		GameState.save_settings()
		MenuSound.play_select()
	for i in bot_level_buttons.size():
		bot_level_buttons[i].set_pressed_no_signal(i == GameState.bot_level)


## Nombre de joueurs (borne a 1..6) : bouton enfonce, camions montres. Choisi
## a la main (`manual`) : on revient a joueur N = manette N (la salle
## d'attente est oubliee).
func select_players(n: int, manual: bool = true) -> void:
	if manual:
		GameState.join_devices = PackedInt32Array()
	var prev := selected_players
	selected_players = clampi(n, 1, LocalRace.MAX_PLAYERS)
	if is_node_ready() and selected_players != prev:
		MenuSound.play_select()
	for i in player_buttons.size():
		player_buttons[i].set_pressed_no_signal(i == selected_players - 1)
		paint_player_button(player_buttons[i], i, i < selected_players)
	_fov_target = fov_deg if selected_players <= 4 else fov_wide_deg
	# joueurs + bots : 6 au plus
	if not bot_buttons.is_empty():
		select_bots(GameState.bot_count, false)
	if _player_dots != null:
		for i in _player_dots.get_child_count():
			(_player_dots.get_child(i) as Control).modulate.a = 1.0 if i < selected_players else 0.12
	for i in trucks.size():
		trucks[i].visible = i < selected_players
		# les camions exposes restent centres sur le plateau
		if i < selected_players:
			trucks[i].transform = Showroom.slot(i, selected_players)
	_update_pads_label()


## PRET : la page de selection (une carte par joueur), l'accueil se cache.
func open_selection() -> void:
	MenuSound.play_confirm()
	if NetSession.is_online():
		# en ligne : la meme page, pour le seul joueur de ce PC ; son choix part
		# au lobby (start_race), puis le host lance quand tout le monde est PRET
		online_panel.visible = false
		home.visible = false
		loadout.open(1)
		return
	GameState.requested_players = selected_players
	home.visible = false
	loadout.open(selected_players)


## Retour de la page de selection vers l'accueil (en ligne : vers le lobby).
func close_selection() -> void:
	loadout.close()
	MenuSound.play_toggle()
	if NetSession.is_online():
		_show_lobby()
		return
	home.visible = true
	start_button.grab_focus()


## En ligne : le panneau de la partie, de nouveau au premier plan.
func _show_lobby() -> void:
	online_panel.visible = true
	_update_home()
	_refresh_online()
	(launch_button if NetSession.is_host() and not launch_button.disabled else convoy_button).grab_focus()


## Tout le monde est pret : la course part, sans sas READY.
func start_race() -> void:
	if LoadingScreen.covering():
		return    # deja en route (une manette qui insiste sous l'ecran)
	if NetSession.is_online():
		# en ligne : convoi de ce PC envoye au lobby (PRET) ; le host lance
		# ensuite la course de la partie (LANCER), le client l'attend
		if loadout.visible:
			NetSession.set_loadout(GameState.trailer_choice[0], GameState.power_left[0], GameState.power_right[0])
			loadout.close()
			MenuSound.play_confirm()
		_show_lobby()
		return
	MenuSound.play_confirm()
	GameState.requested_players = selected_players
	GameState.loadout_locked = true
	launch_requested.emit(selected_players)
	if auto_change_scene:
		LoadingScreen.go(get_tree(), race_scene())


## Remorque changee sur la page de selection : le camion expose la prend.
func _on_trailer_changed(player: int, index: int) -> void:
	if player < trucks.size():
		(trucks[player].get_node("Visual") as TruckVisual).set_trailer_type(TrailerCatalog.at(index))


func set_sound(on: bool) -> void:
	AudioServer.set_bus_mute(_master_bus(), not on)
	sound_button.set_pressed_no_signal(on)
	sound_button.text = "SON : ON" if on else "SON : OFF"
	if sound_check != null:
		sound_check.set_pressed_no_signal(on)
	if is_node_ready():
		MenuSound.play_toggle()
		GameState.save_settings()


## Compteur d'images par seconde, garde dans GameState (menu et courses).
func set_show_fps(on: bool) -> void:
	GameState.show_fps = on
	if fps_check != null:
		fps_check.set_pressed_no_signal(on)
	GameState.save_settings()


## Resolution dynamique, gardee dans GameState (DynamicResolution).
func set_dynamic_resolution(on: bool) -> void:
	GameState.dynamic_resolution = on
	if dynres_check != null:
		dynres_check.set_pressed_no_signal(on)
	GameState.save_settings()


## Qualite graphique (GraphicsSettings.Quality), gardee dans GameState pour les
## courses ; appliquee tout de suite au decor du menu (une seule vue).
func set_quality(q: int) -> void:
	GameState.graphics_quality = clampi(q, 0, GraphicsSettings.NAMES.size() - 1)
	if quality_option != null:
		quality_option.select(GameState.graphics_quality)
	var world := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world != null:
		GraphicsSettings.apply_environment(world.environment, GameState.graphics_quality, 1)
	GraphicsSettings.apply_viewport(get_viewport(), GameState.graphics_quality)
	if is_node_ready():
		GameState.save_settings()


## Volume general (0 a 100 %), sur le bus Master.
func set_volume(percent: float) -> void:
	AudioServer.set_bus_volume_db(_master_bus(), linear_to_db(maxf(percent, 0.001) / 100.0))
	if is_node_ready():
		GameState.save_settings()


# --- salle d'attente (tache 4.2) ------------------------------------------------

## Ouvre ou ferme la salle d'attente ; a l'ouverture, elle repart de la liste
## de la course precedente.
func toggle_join() -> void:
	join_panel.visible = not join_panel.visible
	_update_home()
	if is_node_ready():
		MenuSound.play_toggle()
	if join_panel.visible:
		join_list = GameState.join_devices.duplicate()
		_refresh_join()
	else:
		waiting_button.grab_focus()


## Un appareil rejoint (id de manette, GameState.JOIN_ARROWS / JOIN_ZQSD) :
## premiere case libre. Deja inscrit, ou plus de place : rien.
func join_device(device: int) -> bool:
	if join_list.has(device) or join_list.size() >= LocalRace.MAX_PLAYERS:
		return false
	join_list.append(device)
	MenuSound.play_confirm()
	_refresh_join()
	return true


## Un appareil inscrit repart ; les suivants remontent d'une case.
func leave_device(device: int) -> bool:
	var k := join_list.find(device)
	if k < 0:
		return false
	join_list.remove_at(k)
	MenuSound.play_toggle()
	_refresh_join()
	return true


## Les inscrits passent a la page de selection (remorque, pouvoirs), chacun
## sur son appareil ; elle lance la course quand tous sont prets.
func launch_join() -> void:
	if join_list.is_empty():
		return
	GameState.join_devices = join_list.duplicate()
	select_players(join_list.size(), false)
	join_panel.visible = false
	open_selection()


## Manettes et clavier dans la salle d'attente, avant les boutons du menu :
## Croix rejoint, Rond repart (ferme si on n'etait pas inscrit), Options du
## joueur 1 lance ; clavier : Entree (fleches) et Espace (ZQSD) rejoignent, Retour
## arriere fait repartir le dernier, Echap ferme.
func _input(event: InputEvent) -> void:
	if remap_panel != null and remap_panel.visible:
		_remap_input(event)
		return
	if join_panel == null or not join_panel.visible:
		return
	var pad := event as InputEventJoypadButton
	var key := event as InputEventKey
	if pad != null and pad.pressed:
		match pad.button_index:
			JOY_BUTTON_A:
				join_device(pad.device)
			JOY_BUTTON_B:
				if not leave_device(pad.device):
					toggle_join()
			JOY_BUTTON_START:
				# le joueur 1 lance (INPUT_SPEC §5)
				if not join_list.is_empty() and pad.device == join_list[0]:
					launch_join()
		get_viewport().set_input_as_handled()
	elif key != null and key.pressed and not key.echo:
		match key.physical_keycode:
			KEY_ENTER, KEY_KP_ENTER:
				if not join_device(GameStateNode.JOIN_ARROWS):
					launch_join()
			KEY_SPACE:
				join_device(GameStateNode.JOIN_ZQSD)
			KEY_BACKSPACE:
				if not join_list.is_empty():
					leave_device(join_list[join_list.size() - 1])
			KEY_ESCAPE:
				toggle_join()
			_:
				return
		get_viewport().set_input_as_handled()


## Nom de l'appareil d'un inscrit.
static func device_label(device: int) -> String:
	if device == GameStateNode.JOIN_ARROWS:
		return "clavier : flèches"
	if device == GameStateNode.JOIN_ZQSD:
		return "clavier : ZQSD"
	var pad_name := Input.get_joy_name(device)
	return "manette %d%s" % [device + 1, (" — " + pad_name) if pad_name != "" else ""]


func _refresh_join() -> void:
	for k in _join_slots.size():
		var l := _join_slots[k]
		var tile := l.get_parent().get_parent() as Control
		if k < join_list.size():
			l.text = "%s   ·   %s" % [LocalRace.COLOR_NAMES[k], device_label(join_list[k]).to_upper()]
			tile.modulate = Color.WHITE
		else:
			l.text = "APPUYEZ SUR CROIX POUR REJOINDRE"
			tile.modulate = Color(1, 1, 1, 0.38)
	select_players(maxi(join_list.size(), 1), false)


## Panneau : six cases, aide des commandes, COMMENCER et RETOUR.
func _build_join() -> Control:
	var layer := UiKit.page("JoinPanel", "SALLE D'ATTENTE", "CHACUN SA MANETTE",
		[["cross", "Rejoindre"], ["circle", "Repartir"], ["options", "Commencer"],
		["key:Entrée", "flèches"], ["key:Espace", "ZQSD"], ["key:Retour arrière", "repartir"], ["key:Échap", "Accueil"]])
	var panel := UiKit.card(UiKit.PINK, 980)
	UiKit.page_content(layer).add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(UiKit.section("Joueurs"))
	# une tuile par joueur : pastille J1..J6 a sa couleur (comme les cartes de
	# la page de selection), puis couleur et appareil ; vide, elle s'eteint
	for k in LocalRace.MAX_PLAYERS:
		var tile := PanelContainer.new()
		tile.name = "Tile%d" % (k + 1)
		var tsb := UiKit.box(UiKit.TILE, Color(UiKit.PLAYER_COLORS[k], 0.55), 1, UiKit.SKEW, 3)
		tsb.content_margin_top = 6
		tsb.content_margin_bottom = 6
		tile.add_theme_stylebox_override("panel", tsb)
		box.add_child(tile)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		tile.add_child(row)
		var tag := PanelContainer.new()
		var gsb := UiKit.box(UiKit.PLAYER_COLORS[k], Color(1, 1, 1, 0.3), 1, UiKit.SKEW, 3, Color(UiKit.PLAYER_COLORS[k], 0.4), 8)
		gsb.content_margin_left = 16
		gsb.content_margin_right = 16
		gsb.content_margin_top = 2
		gsb.content_margin_bottom = 2
		tag.add_theme_stylebox_override("panel", gsb)
		tag.custom_minimum_size = Vector2(76, 0)
		var tl := UiKit.label("J%d" % (k + 1), 28, UiKit.TEXT, 900, true, 4)
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.add_child(tl)
		row.add_child(tag)
		var l := UiKit.label("", 24, UiKit.TEXT, 800)
		l.name = "Slot%d" % (k + 1)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
		_join_slots.append(l)
	box.add_child(UiKit.gap(8))
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 16)
	box.add_child(bottom)
	var go := Button.new()
	go.name = "Start"
	go.text = "COMMENCER"
	go.custom_minimum_size = Vector2(300, 64)
	UiKit.style_primary(go, 26)
	go.focus_mode = Control.FOCUS_NONE   # manettes et clavier : voir _input
	go.pressed.connect(launch_join)
	bottom.add_child(go)
	var back := Button.new()
	back.name = "Back"
	back.text = "RETOUR"
	back.custom_minimum_size = Vector2(220, 64)
	UiKit.style_choice(back, 22)
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(toggle_join)
	bottom.add_child(back)
	return layer


# --- reaffectation de la manette (tache 7.1) ------------------------------------

func toggle_remap() -> void:
	remap_panel.visible = not remap_panel.visible
	# ouverte depuis les parametres : ils se cachent dessous, et reviennent
	settings.visible = not remap_panel.visible
	_update_home()
	remap_waiting = ""
	if is_node_ready():
		MenuSound.play_toggle()
	if remap_panel.visible:
		_refresh_remap()
		(_remap_buttons[PadBindings.ACTIONS[0]] as Button).grab_focus()
	else:
		(settings.find_child("Remap", true, false) as Button).grab_focus()


## L'action attend son nouveau bouton : la prochaine pression d'une manette.
func begin_remap(action: String) -> void:
	remap_waiting = action
	MenuSound.play_select()
	_refresh_remap()


## Donne `button` a `action` (PadBindings.assign), sauvegarde.
func finish_remap(button: int) -> void:
	if remap_waiting == "":
		return
	GameState.pad_bindings = PadBindings.assign(GameState.pad_bindings, remap_waiting, button)
	remap_waiting = ""
	GameState.save_settings()
	MenuSound.play_confirm()
	_refresh_remap()


func reset_remap() -> void:
	GameState.pad_bindings = PadBindings.defaults()
	remap_waiting = ""
	GameState.save_settings()
	MenuSound.play_confirm()
	_refresh_remap()


## En attente : la pression suivante d'une manette est le nouveau bouton
## (PS refuse), Echap annule ; rien d'autre n'atteint le menu. Sinon, Rond ou
## Echap ferment le panneau.
func _remap_input(event: InputEvent) -> void:
	var pad := event as InputEventJoypadButton
	var key := event as InputEventKey
	if remap_waiting != "":
		if pad != null and pad.pressed and not PadBindings.RESERVED.has(pad.button_index):
			finish_remap(pad.button_index)
		elif key != null and key.pressed and key.physical_keycode == KEY_ESCAPE:
			remap_waiting = ""
			MenuSound.play_toggle()
			_refresh_remap()
		if pad != null or key != null or event is InputEventJoypadMotion:
			get_viewport().set_input_as_handled()
		return
	if (pad != null and pad.pressed and pad.button_index == JOY_BUTTON_B) \
			or (key != null and key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE):
		toggle_remap()
		get_viewport().set_input_as_handled()


func _refresh_remap() -> void:
	for a: String in PadBindings.ACTIONS:
		var b := _remap_buttons[a] as Button
		if a == remap_waiting:
			b.text = "appuyez sur un bouton…  (Échap : annuler)"
		else:
			b.text = PadBindings.list_name(GameState.pad_bindings[a])


## Panneau : une ligne par action (nom, boutons actuels a cliquer), PAR
## DEFAUT, RETOUR.
func _build_remap() -> Control:
	var layer := UiKit.page("RemapPanel", "RÉAFFECTER LA MANETTE", "TOUTES LES MANETTES",
		[["cross", "Choisir l'action"], ["circle", "Retour"], ["key:Échap", "Annuler / retour"]])
	var panel := UiKit.card(UiKit.CYAN, 1100)
	UiKit.page_content(layer).add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var help := UiKit.label("Choisissez une action, puis appuyez sur son nouveau bouton. Un bouton ne sert qu'à une action :\n"
		+ "pris ailleurs, il y est échangé. R2, L2 et le stick gauche ne changent pas.", 18, UiKit.DIM, 600, false)
	box.add_child(help)
	box.add_child(UiKit.gap(6))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for a: String in PadBindings.ACTIONS:
		var l := _label(String(PadBindings.LABELS[a]), 21, 0)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(l)
		var b := Button.new()
		b.name = "Bind_" + a
		b.custom_minimum_size = Vector2(420, 48)
		UiKit.style_choice(b, 19)
		b.pressed.connect(begin_remap.bind(a))
		grid.add_child(b)
		_remap_buttons[a] = b
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 16)
	box.add_child(bottom)
	var def := Button.new()
	def.name = "Defaults"
	def.text = "PAR DÉFAUT"
	def.custom_minimum_size = Vector2(260, 58)
	UiKit.style_choice(def, 22)
	def.pressed.connect(reset_remap)
	bottom.add_child(def)
	var back := Button.new()
	back.name = "Back"
	back.text = "RETOUR"
	back.custom_minimum_size = Vector2(220, 58)
	UiKit.style_choice(back, 22)
	back.pressed.connect(toggle_remap)
	bottom.add_child(back)
	return layer


func toggle_online() -> void:
	online_panel.visible = not online_panel.visible
	_update_home()
	if is_node_ready():
		MenuSound.play_toggle()
	if online_panel.visible:
		_refresh_online()
		if NetSession.is_online():
			_show_lobby()
		else:
			host_button.grab_focus()
	else:
		online_button.grab_focus()


func host_game() -> void:
	NetSession.player_name = NetSessionNode.clean_name(name_edit.text)
	NetSession.host()
	MenuSound.play_confirm()
	_refresh_online()


func join_game() -> void:
	NetSession.player_name = NetSessionNode.clean_name(name_edit.text)
	if NetSession.join(ip_edit.text) == OK:
		MenuSound.play_confirm()
	_refresh_online()


func leave_game() -> void:
	NetSession.leave()
	NetSession.last_error = ""
	MenuSound.play_toggle()
	_refresh_online()


## Host : la course de la partie, sur le circuit et la categorie de ce menu.
func launch_online() -> void:
	if not NetSession.is_host():
		return
	MenuSound.play_confirm()
	NetSession.launch_race()


## Etat de la partie dans le panneau EN LIGNE (et le bouton du menu).
func _refresh_online() -> void:
	if online_panel == null:
		return
	var online := NetSession.is_online()
	var host := NetSession.is_host()
	host_button.disabled = online
	join_button.disabled = online
	name_edit.editable = not online
	ip_edit.editable = not online
	launch_button.visible = host
	slow_check.visible = not NetSession.is_client()
	launch_button.disabled = not NetSession.all_ready()
	leave_button.visible = online
	convoy_button.visible = online and NetSession.local_slot() >= 0
	var status := ""
	if host:
		var ips := NetSessionNode.local_addresses()
		status = "Partie ouverte. Les autres joueurs tapent : %s  (port %d)" % [
			" ou ".join(ips) if not ips.is_empty() else "l'adresse IP de ce PC", NetSessionNode.DEFAULT_PORT]
		status += "\nCircuit et vitesse : ceux choisis dans le menu. Chacun choisit son convoi ; LANCER quand tout le monde est PRÊT."
	elif NetSession.is_client():
		if NetSession.local_slot() < 0:
			status = "Connexion à %s..." % ip_edit.text
		elif bool(NetSession.member_of_slot(NetSession.local_slot()).get("ready", false)):
			status = "Convoi choisi : en attente du lancement par le host."
		else:
			status = "Connecté. Choisissez votre convoi (remorque et pouvoirs) : CHOISIR MON CONVOI."
	elif NetSession.last_error != "":
		status = NetSession.last_error
	else:
		status = "Héberger : ce PC fait tourner la course. Rejoindre : l'adresse IP du PC qui héberge.\n" \
				+ "Par Internet : le host ouvre le port UDP %d de sa box, ou passez par un VPN (Tailscale, ZeroTier)." \
				% NetSessionNode.DEFAULT_PORT
	online_status.text = status
	online_status.modulate = Color(1.0, 0.6, 0.45) if not online and NetSession.last_error != "" else TEXT_DIM
	var lines := PackedStringArray()
	for m in NetSession.members:
		var slot := int(m["slot"])
		lines.append("J%d  %s  (%s)%s%s   %s" % [slot + 1, String(m["name"]), LocalRace.COLOR_NAMES[slot],
			"  · host" if int(m["peer"]) == 1 else "", "  · vous" if slot == NetSession.local_slot() else "",
			lobby_convoy(m)])
	lobby_label.text = "\n".join(lines) if not lines.is_empty() else "Personne pour l'instant."
	if online_button != null:
		online_button.text = ("EN LIGNE : %d JOUEUR%s" % [NetSession.members.size(),
			"S" if NetSession.members.size() > 1 else ""]) if online else "EN LIGNE / RÉSEAU LOCAL"


## Convoi d'un membre du lobby : « PRÊT · CITERNE · MISSILE + LASER », ou
## « choisit son convoi... ».
static func lobby_convoy(m: Dictionary) -> String:
	if not bool(m.get("ready", false)):
		return "· choisit son convoi..."
	return "· PRÊT  %s  ·  %s + %s" % [TrailerCatalog.at(int(m["trailer"])).display_name.to_upper(),
		PowerCatalog.display_name(int(m["power_left"])), PowerCatalog.display_name(int(m["power_right"]))]


func toggle_settings() -> void:
	settings.visible = not settings.visible
	_update_home()
	MenuSound.play_toggle()
	if settings.visible:
		(settings.find_child("Back", true, false) as Button).grab_focus()
	else:
		settings_button.grab_focus()


## Une page plein ecran ouverte cache l'accueil (son texte transparaissait
## sous le voile).
func _update_home() -> void:
	if home == null:
		return
	home.visible = not (settings.visible or online_panel.visible or join_panel.visible
		or remap_panel.visible or (loadout != null and loadout.visible))


static func _master_bus() -> int:
	return AudioServer.get_bus_index("Master")


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	_update_pads_label()


func _update_pads_label() -> void:
	if _pads_label == null:
		return
	var pads := Input.get_connected_joypads().size()
	var plural := "s" if pads > 1 else ""
	var text := "%d manette%s détectée%s" % [pads, plural, plural]
	var warn := selected_players > 2 and pads < selected_players
	if warn:
		text += "  ·  il en faut %d (J1 et J2 peuvent jouer au clavier)" % selected_players
	elif selected_players > 1:
		text += "  ·  joueur N = manette N (clavier : J1 flèches, J2 ZQSD)"
	_pads_label.text = text
	_pads_label.add_theme_color_override("font_color", UiKit.GOLD if warn else TEXT_DIM)


# --- interface ------------------------------------------------------------------

## Charte : UiKit, habillage du circuit choisi (neon, plage, Japon). En
## neon : rose = choisi, cyan = focus, or = PRET.
var ACCENT: Color:
	get:
		return UiKit.PINK
var TEXT_DIM: Color:
	get:
		return UiKit.DIM
## Colonne de gauche (px, ecran de reference 1920 x 1080).
const COLUMN_X := 84
const COLUMN_W := 700
## Fond des cartes de circuit (Cyber City : nuit violette ; Playa : lagon).
const TRACK_TINTS: Array[Color] = [Color(0.36, 0.1, 0.62), Color(0.0, 0.5, 0.58), Color(0.86, 0.3, 0.48)]


## Accueil (2026-10-16 : « fait une vraie belle UI de jeu video ») : voile
## degrade a gauche sur le showroom, onglets de mode (LOCAL ; EN LIGNE a
## venir), logo, puis CIRCUIT (cartes), JOUEURS, VITESSE et le gros bouton
## PRET qui ouvre la page de selection (LoadoutSelect). Barre d'aide des
## commandes en bas, son et parametres en haut a droite.
func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	home = Control.new()
	home.name = "Home"
	home.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	home.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(home)

	# voile : nuit opaque a gauche, transparente vers les camions
	var veil := TextureRect.new()
	veil.name = "Veil"
	var tex := GradientTexture2D.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	g.colors = PackedColorArray([Color(UiKit.NIGHT, 0.95), Color(UiKit.NIGHT, 0.82), Color(UiKit.NIGHT, 0.0)])
	tex.gradient = g
	tex.fill_to = Vector2(1, 0)
	veil.texture = tex
	veil.stretch_mode = TextureRect.STRETCH_SCALE
	veil.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	veil.offset_right = 1120
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	home.add_child(veil)
	# filet rose incline le long du voile
	var stripe := Panel.new()
	stripe.add_theme_stylebox_override("panel", UiKit.box(Color(ACCENT, 0.75), Color(0, 0, 0, 0), 0, -0.6 * UiKit.SKEW, 1,
		Color(ACCENT, 0.4), 10))
	stripe.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	stripe.offset_left = COLUMN_X + COLUMN_W + 64
	stripe.offset_right = COLUMN_X + COLUMN_W + 68
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	home.add_child(stripe)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.position = Vector2(COLUMN_X, 40)
	column.size = Vector2(COLUMN_W, 960)
	column.add_theme_constant_override("separation", 0)
	home.add_child(column)

	# onglets de mode
	var tabs := HBoxContainer.new()
	tabs.name = "Modes"
	tabs.add_theme_constant_override("separation", 10)
	column.add_child(tabs)
	var local_tab := Button.new()
	local_tab.name = "ModeLocal"
	local_tab.text = "LOCAL"
	local_tab.toggle_mode = true
	local_tab.button_pressed = true
	local_tab.custom_minimum_size = Vector2(170, 44)
	local_tab.focus_mode = Control.FOCUS_NONE
	UiKit.style_choice(local_tab, 19)
	tabs.add_child(local_tab)
	var online_tab := Button.new()
	online_tab.name = "ModeOnline"
	online_tab.text = "EN LIGNE / RÉSEAU LOCAL"
	online_tab.custom_minimum_size = Vector2(330, 44)
	online_tab.tooltip_text = "Un PC héberge la partie, les autres le rejoignent par son adresse."
	UiKit.style_choice(online_tab, 19)
	# en ligne / reseau local : ouvre le panneau EN LIGNE (pseudo, heberger,
	# rejoindre) ; son texte suit la partie (_refresh_online)
	online_tab.pressed.connect(toggle_online)
	online_button = online_tab
	tabs.add_child(online_tab)
	column.add_child(UiKit.gap(26))

	# logo : CRAZY en blanc, WHEELS en or dessous ; ombre rose decalee. Le
	# titre s'anime (echelle) : hors conteneur, qui la remettrait a zero
	var title_box := Control.new()
	title_box.custom_minimum_size = Vector2(0, 214)
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title_box)
	title = UiKit.label("CRAZY", 112, UiKit.LOGO_TOP, 900)
	title.name = "Title"
	title.add_theme_color_override("font_shadow_color", Color(UiKit.LOGO_SHADOW, 0.9))
	title.add_theme_constant_override("shadow_offset_x", 6)
	title.add_theme_constant_override("shadow_offset_y", 6)
	title.position = Vector2(-4, -10)
	title_box.add_child(title)
	var wheels := UiKit.label("WHEELS", 112, UiKit.LOGO_BOTTOM, 900)
	wheels.name = "Title2"
	wheels.add_theme_color_override("font_shadow_color", Color(UiKit.LOGO_SHADOW, 0.9))
	wheels.add_theme_constant_override("shadow_offset_x", 6)
	wheels.add_theme_constant_override("shadow_offset_y", 6)
	wheels.position = Vector2(64, 92)
	title.add_child(wheels)
	var tag_row := HBoxContainer.new()
	tag_row.add_theme_constant_override("separation", 14)
	tag_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(tag_row)
	for w: int in [46, 26, 12]:
		var dash := Panel.new()
		dash.custom_minimum_size = Vector2(w, 6)
		dash.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dash.add_theme_stylebox_override("panel", UiKit.box(UiKit.CYAN, Color(0, 0, 0, 0), 0, UiKit.SKEW * 2.5, 1))
		dash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag_row.add_child(dash)
	tag_row.add_child(UiKit.label("COURSE DE CAMIONS ARCADE", 20, UiKit.CYAN, 800))
	column.add_child(UiKit.gap(18))

	# circuit : une carte par circuit
	column.add_child(_section("Circuit"))
	column.add_child(UiKit.gap(8))
	var track_row := _row("Tracks")
	track_row.add_theme_constant_override("separation", 16)
	column.add_child(track_row)
	var track_group := ButtonGroup.new()
	for k in GameStateNode.TRACKS.size():
		var tb := _track_card(k, track_group)
		tb.pressed.connect(select_track.bind(k))
		track_row.add_child(tb)
		track_buttons.append(tb)
	subtitle = UiKit.label("", 17, TEXT_DIM, 600, false)
	column.add_child(UiKit.gap(10))
	column.add_child(subtitle)
	select_track(GameState.selected_track)
	column.add_child(UiKit.gap(18))

	# joueurs
	column.add_child(_section("Joueurs"))
	column.add_child(UiKit.gap(8))
	var row := _row("Players")
	column.add_child(row)
	var group := ButtonGroup.new()
	for i in LocalRace.MAX_PLAYERS:
		var b := _choice("Players%d" % (i + 1), str(i + 1), group, 30)
		b.tooltip_text = "%d joueur%s" % [i + 1, "s" if i > 0 else ""]
		b.pressed.connect(select_players.bind(i + 1))
		row.add_child(b)
		player_buttons.append(b)
	# pastilles des couleurs des joueurs, sous leur numero
	_player_dots = HBoxContainer.new()
	_player_dots.name = "PlayerDots"
	_player_dots.add_theme_constant_override("separation", 10)
	_player_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in LocalRace.MAX_PLAYERS:
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(0, 6)
		dot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dot.add_theme_stylebox_override("panel", UiKit.box(UiKit.PLAYER_COLORS[i], Color(0, 0, 0, 0), 0, UiKit.SKEW, 1,
			Color(UiKit.PLAYER_COLORS[i], 0.5), 4))
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_player_dots.add_child(dot)
	column.add_child(UiKit.gap(8))
	column.add_child(_player_dots)
	# bots (hors ligne) : nombre et niveau, sur une ligne
	column.add_child(UiKit.gap(6))
	var bots_row := _row("Bots")
	var bots_label := _label("BOTS", 18, 0)
	bots_label.custom_minimum_size.x = 72
	bots_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bots_row.add_child(bots_label)
	var bots_group := ButtonGroup.new()
	for k in LocalRace.MAX_PLAYERS:
		var bb := _choice("Bots%d" % k, str(k), bots_group, 20)
		bb.custom_minimum_size.y = 44
		bb.tooltip_text = "Aucun bot" if k == 0 else "%d bot%s pilote%s par l'ordinateur" % [k, "s" if k > 1 else "", "s" if k > 1 else ""]
		bb.pressed.connect(select_bots.bind(k))
		bots_row.add_child(bb)
		bot_buttons.append(bb)
	bots_row.add_child(UiKit.gap(0))
	var level_group := ButtonGroup.new()
	for k in BOT_LEVELS.size():
		var lb := _choice("BotLevel%d" % k, BOT_LEVELS[k], level_group, 16)
		lb.custom_minimum_size = Vector2(96, 44)
		lb.size_flags_horizontal = Control.SIZE_FILL
		lb.pressed.connect(select_bot_level.bind(k))
		bots_row.add_child(lb)
		bot_level_buttons.append(lb)
	column.add_child(bots_row)
	select_bots(GameState.bot_count, false)
	select_bot_level(GameState.bot_level, false)
	# manettes detectees a gauche ; salle d'attente (chacun rejoint avec SA
	# manette ou son jeu de touches) a droite, sur la meme ligne
	var pads_row := HBoxContainer.new()
	pads_row.add_theme_constant_override("separation", 14)
	_pads_label = UiKit.label("", 16, TEXT_DIM, 600, false)
	_pads_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pads_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pads_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pads_row.add_child(_pads_label)
	waiting_button = Button.new()
	waiting_button.name = "WaitingRoom"
	waiting_button.text = "SALLE D'ATTENTE"
	waiting_button.tooltip_text = "Chacun sa manette : chaque joueur appuie sur Croix (ou Entrée / Espace au clavier) pour rejoindre."
	waiting_button.custom_minimum_size = Vector2(250, 40)
	UiKit.style_choice(waiting_button, 16)
	waiting_button.pressed.connect(toggle_join)
	pads_row.add_child(waiting_button)
	column.add_child(UiKit.gap(8))
	column.add_child(pads_row)
	column.add_child(UiKit.gap(16))

	# categorie de vitesse, facon cylindree : chevrons de 1 a 4
	column.add_child(_section("Vitesse"))
	column.add_child(UiKit.gap(8))
	var speed_row := _row("Speeds")
	column.add_child(speed_row)
	var speed_group := ButtonGroup.new()
	for k in GameStateNode.SPEED_CLASSES.size():
		var c: Dictionary = GameStateNode.SPEED_CLASSES[k]
		var sbtn := _choice("Speed%d" % k, "%s  %s\n%s" % [c["cc"], ">".repeat(k + 1), String(c["name"]).to_upper()],
			speed_group, 18)
		sbtn.custom_minimum_size.y = 78
		sbtn.tooltip_text = "%s : %d km/h" % [c["name"], int(c["top_kmh"])]
		sbtn.pressed.connect(select_speed.bind(k))
		speed_row.add_child(sbtn)
		speed_buttons.append(sbtn)
	select_speed(GameState.speed_class)

	# PRET : ouvre la page de selection
	var push := Control.new()
	push.size_flags_vertical = Control.SIZE_EXPAND_FILL
	push.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(push)
	start_button = Button.new()
	start_button.name = "Start"
	start_button.text = "PRÊT"
	start_button.custom_minimum_size = Vector2(0, 88)
	UiKit.style_primary(start_button, 52)
	start_button.pressed.connect(open_selection)
	column.add_child(start_button)
	column.add_child(UiKit.gap(8))
	var next := UiKit.label("ensuite : remorque et pouvoirs de chaque joueur", 16, TEXT_DIM, 600, false)
	next.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(next)

	# barre d'aide en bas, sur toute la largeur
	var bar := PanelContainer.new()
	bar.name = "HelpBar"
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -64
	var bsb := UiKit.box(Color(UiKit.NIGHT, 0.88), Color(0, 0, 0, 0), 0, 0.0, 0)
	bsb.content_margin_left = COLUMN_X
	bsb.border_width_top = 1
	bsb.border_color = Color(ACCENT, 0.5)
	bar.add_theme_stylebox_override("panel", bsb)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	home.add_child(bar)
	var help := HBoxContainer.new()
	help.add_theme_constant_override("separation", 30)
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(help)
	help.add_child(UiKit.prompt("cross", "Valider"))
	help.add_child(UiKit.prompt("circle", "Retour"))
	help.add_child(UiKit.prompt("l1", "/"))
	(help.get_child(help.get_child_count() - 1) as HBoxContainer).add_child(_glyph("r1", 28))
	(help.get_child(help.get_child_count() - 1) as HBoxContainer).add_child(UiKit.label("Joueurs", 18, UiKit.TEXT, 600, false))
	help.add_child(UiKit.prompt("triangle", "Circuit"))
	help.add_child(UiKit.prompt("options", "Prêt"))
	help.add_child(UiKit.prompt("key:1-6", "Joueurs"))
	help.add_child(UiKit.prompt("key:T", "Circuit"))
	help.add_child(UiKit.prompt("key:F11", "Plein écran"))
	help.add_child(UiKit.prompt("key:Échap", "Quitter"))

	# coin haut droit : son et parametres, boutons ronds
	var corner := HBoxContainer.new()
	corner.name = "Corner"
	corner.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	corner.offset_top = 32
	corner.offset_right = -36
	corner.add_theme_constant_override("separation", 12)
	home.add_child(corner)
	sound_button = Button.new()
	sound_button.name = "Sound"
	sound_button.toggle_mode = true
	sound_button.custom_minimum_size = Vector2(160, 56)
	UiKit.style_icon(sound_button, 18)
	sound_button.toggled.connect(set_sound)
	corner.add_child(sound_button)
	settings_button = Button.new()
	settings_button.name = "Settings"
	settings_button.tooltip_text = "Paramètres"
	settings_button.custom_minimum_size = Vector2(56, 56)
	UiKit.style_icon(settings_button, 18)
	settings_button.pressed.connect(toggle_settings)
	corner.add_child(settings_button)
	_gear = GearIcon.new()
	_gear.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_gear.offset_left = 13
	_gear.offset_top = 13
	_gear.offset_right = -13
	_gear.offset_bottom = -13
	settings_button.add_child(_gear)

	# page de selection (remorque, pouvoirs), apres PRET
	loadout = LoadoutSelect.new()
	loadout.name = "Loadout"
	loadout.visible = false
	root.add_child(loadout)
	loadout.launch_requested.connect(start_race)
	loadout.back_requested.connect(close_selection)
	loadout.trailer_changed.connect(_on_trailer_changed)

	settings = _build_settings()
	root.add_child(settings)
	online_panel = _build_online()
	root.add_child(online_panel)
	join_panel = _build_join()
	root.add_child(join_panel)
	remap_panel = _build_remap()
	root.add_child(remap_panel)


## Carte de circuit : fond a la teinte du circuit, nom en grand, ambiance
## dessous ; choisie = liseré rose lumineux.
func _track_card(k: int, group: ButtonGroup) -> Button:
	var t: Dictionary = GameStateNode.TRACKS[k]
	var b := Button.new()
	b.name = "Track%d" % k
	b.text = String(t["name"]).to_upper()
	b.toggle_mode = true
	b.button_group = group
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 92)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	# trois circuits et plus : cartes plus etroites, nom plus petit
	var many := GameStateNode.TRACKS.size() > 2
	UiKit.style_choice(b, 21 if many else 28)
	var margin := 18 if many else 30
	var tint: Color = TRACK_TINTS[k % TRACK_TINTS.size()]
	for st: String in ["normal", "hover"]:
		var sb := UiKit.box(tint.darkened(0.45 if st == "normal" else 0.3), Color(1, 1, 1, 0.12), 1)
		sb.content_margin_left = margin
		b.add_theme_stylebox_override(st, sb)
	for st: String in ["pressed", "hover_pressed"]:
		var sb := UiKit.box(tint.lightened(0.05 if st == "pressed" else 0.15), ACCENT, 3, -1.0, -1, Color(ACCENT, 0.5), 14)
		sb.content_margin_left = margin
		b.add_theme_stylebox_override(st, sb)
	# fonds teintes sombres : texte clair, quel que soit l'habillage
	for c: String in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, UiKit.TEXT)
	return b


## Picto seul (aide de commande composee).
func _glyph(kind: String, height: int) -> PadGlyph:
	var g := PadGlyph.new()
	g.kind = kind
	g.custom_minimum_size = Vector2(PadGlyph.width_for(kind, height), height)
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return g


## Rangee d'une section : boutons de meme largeur, du bord gauche au bord droit.
func _row(row_name: String) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.name = row_name
	r.add_theme_constant_override("separation", 12)
	return r


## Bouton de choix (un seul enfonce par groupe), largeur partagee de la rangee.
func _choice(button_name: String, text: String, group: ButtonGroup, font_size: int) -> Button:
	var b := Button.new()
	b.name = button_name
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 62)
	UiKit.style_choice(b, font_size)
	return b


func _gap(height: int) -> Control:
	return UiKit.gap(height)


## Ecran des parametres : schema de la manette (chaque commande legendee),
## touches du clavier, son (coupure et volume reels), reglages a venir, et
## RETOUR vers le menu. Couvre le menu : ses clics ne passent pas au travers.
func _build_settings() -> Control:
	var layer := UiKit.page("SettingsPanel", "PARAMÈTRES", "COMMANDES  ·  SON  ·  IMAGE",
		[["cross", "Valider"], ["circle", "Retour"], ["key:Échap", "Retour"], ["key:F11", "Plein écran"]])
	var panel := UiKit.card(UiKit.CYAN, 1720)
	(panel.get_theme_stylebox("panel") as StyleBoxFlat).set_content_margin_all(18)
	UiKit.page_content(layer).add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var sub := _label("Commandes par défaut — manette PlayStation 5 DualSense (disposition Forza Horizon), réaffectables plus bas", 20, 0)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(0.8, 0.82, 0.88)
	box.add_child(sub)
	var diagram := ControllerDiagram.new()
	diagram.name = "ControllerDiagram"
	diagram.custom_minimum_size = Vector2(1180, 410)
	diagram.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(diagram)

	# bas : clavier a gauche, reglages a droite
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 40)
	box.add_child(bottom)
	var keys := VBoxContainer.new()
	keys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	keys.add_theme_constant_override("separation", 6)
	bottom.add_child(keys)
	keys.add_child(_section("Clavier"))
	for line: String in [
		"J1 — flèches · Ctrl droit drift · Maj droite boost · ; cargo · ! klaxon · : vue · Retour arrière reset",
		"J2 — Z Q S D · Espace drift · Maj gauche boost · E cargo · H klaxon · C vue · R reset",
		"Seul : les deux jeux de touches · Échap : menu · Entrée : rejouer · F11 : plein écran / fenêtre",
	]:
		var l := _label(line, 17, 0)
		l.modulate = Color(0.9, 0.9, 0.94)
		keys.add_child(l)
	var opts := VBoxContainer.new()
	opts.custom_minimum_size = Vector2(430, 0)
	opts.add_theme_constant_override("separation", 6)
	bottom.add_child(opts)
	opts.add_child(_section("Son et réglages"))
	sound_check = CheckButton.new()
	sound_check.name = "SoundCheck"
	sound_check.text = "Son"
	sound_check.add_theme_font_size_override("font_size", 19)
	sound_check.toggled.connect(set_sound)
	opts.add_child(sound_check)
	var vol := HBoxContainer.new()
	vol.add_child(_label("Volume", 19, 0))
	volume_slider = HSlider.new()
	volume_slider.name = "Volume"
	volume_slider.min_value = 0.0
	volume_slider.max_value = 100.0
	volume_slider.step = 5.0
	volume_slider.value = roundf(db_to_linear(AudioServer.get_bus_volume_db(_master_bus())) * 100.0)
	volume_slider.custom_minimum_size = Vector2(260, 0)
	volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	volume_slider.value_changed.connect(set_volume)
	vol.add_child(volume_slider)
	opts.add_child(vol)
	var rumble := CheckButton.new()
	rumble.text = "Vibrations manette (bientôt)"
	rumble.button_pressed = true
	rumble.add_theme_font_size_override("font_size", 19)
	opts.add_child(rumble)
	quality_option = OptionButton.new()
	quality_option.name = "Quality"
	for q: String in GraphicsSettings.NAMES:
		quality_option.add_item("Qualité graphique : %s" % q)
	quality_option.tooltip_text = "Haute : reflets, éclairage indirect, occlusion. Moyenne : occlusion. Basse : aucun effet."
	quality_option.add_theme_font_size_override("font_size", 19)
	quality_option.select(GameState.graphics_quality)
	quality_option.item_selected.connect(set_quality)
	opts.add_child(quality_option)
	fps_check = CheckButton.new()
	fps_check.name = "FpsCheck"
	fps_check.text = "Compteur d'images par seconde (FPS)"
	fps_check.tooltip_text = "Affiché en haut à droite, au menu et en course."
	fps_check.add_theme_font_size_override("font_size", 19)
	fps_check.button_pressed = GameState.show_fps
	fps_check.toggled.connect(set_show_fps)
	opts.add_child(fps_check)

	dynres_check = CheckButton.new()
	dynres_check.name = "DynResCheck"
	dynres_check.text = "Résolution dynamique"
	dynres_check.tooltip_text = "Baisse la résolution de la 3D seulement quand la carte graphique\nne tient plus 60 images/s (mise à l'échelle FSR). Effets intacts."
	dynres_check.add_theme_font_size_override("font_size", 19)
	dynres_check.button_pressed = GameState.dynamic_resolution
	dynres_check.toggled.connect(set_dynamic_resolution)
	opts.add_child(dynres_check)

	# reaffecter, puis RETOUR, cote a cote sous les reglages
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	opts.add_child(UiKit.gap(4))
	opts.add_child(actions)
	var remap := Button.new()
	remap.name = "Remap"
	remap.text = "RÉAFFECTER LA MANETTE"
	remap.custom_minimum_size = Vector2(0, 52)
	remap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiKit.style_choice(remap, 17)
	remap.pressed.connect(toggle_remap)
	actions.add_child(remap)
	var back := Button.new()
	back.name = "Back"
	back.text = "RETOUR"
	back.custom_minimum_size = Vector2(170, 52)
	UiKit.style_primary(back, 22)
	back.pressed.connect(toggle_settings)
	actions.add_child(back)
	return layer


## Panneau EN LIGNE : pseudo, HÉBERGER (adresse a donner aux autres),
## REJOINDRE (adresse du host), joueurs de la partie, LANCER (host), QUITTER
## LA PARTIE, RETOUR. Meme habillage que les parametres.
func _build_online() -> Control:
	var layer := UiKit.page("OnlinePanel", "EN LIGNE", "UN PC HÉBERGE  ·  LES AUTRES LE REJOIGNENT",
		[["cross", "Valider"], ["circle", "Retour"], ["key:Échap", "Retour"]])
	var panel := UiKit.card(UiKit.CYAN, 1180)
	UiKit.page_content(layer).add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 12)
	var name_label := _label("Pseudo", 20, 0)
	name_label.custom_minimum_size.x = 120
	name_row.add_child(name_label)
	name_edit = LineEdit.new()
	name_edit.name = "PlayerName"
	name_edit.text = NetSession.player_name
	name_edit.max_length = NetSessionNode.MAX_NAME
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.add_theme_font_size_override("font_size", 20)
	UiKit.style_field(name_edit)
	name_row.add_child(name_edit)
	box.add_child(name_row)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	box.add_child(actions)
	host_button = Button.new()
	host_button.name = "Host"
	host_button.text = "HÉBERGER UNE PARTIE"
	host_button.custom_minimum_size = Vector2(0, 60)
	host_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiKit.style_primary(host_button, 22)
	host_button.pressed.connect(host_game)
	actions.add_child(host_button)
	ip_edit = LineEdit.new()
	ip_edit.name = "HostAddress"
	ip_edit.placeholder_text = "adresse IP du host, ex. 192.168.1.20"
	ip_edit.custom_minimum_size = Vector2(380, 60)
	ip_edit.add_theme_font_size_override("font_size", 20)
	UiKit.style_field(ip_edit)
	ip_edit.text_submitted.connect(func(_t: String) -> void: join_game())
	actions.add_child(ip_edit)
	join_button = Button.new()
	join_button.name = "Join"
	join_button.text = "REJOINDRE"
	join_button.custom_minimum_size = Vector2(220, 60)
	UiKit.style_choice(join_button, 22)
	join_button.pressed.connect(join_game)
	actions.add_child(join_button)

	slow_check = CheckButton.new()
	slow_check.name = "SlowUpload"
	slow_check.text = "Connexion lente du host : 20 envois par seconde au lieu de 60 (un peu plus de délai)"
	slow_check.tooltip_text = "60 envois/s : le moins de délai (~270 kbps à 4 joueurs).\n20 envois/s : pour une connexion Internet qui envoie peu (~90 kbps)."
	slow_check.add_theme_font_size_override("font_size", 17)
	slow_check.button_pressed = NetSession.snapshot_ticks > 1
	slow_check.toggled.connect(func(on: bool) -> void:
		NetSession.snapshot_ticks = NetSessionNode.SNAPSHOT_TICKS_LOW_BANDWIDTH if on else 1)
	box.add_child(slow_check)
	online_status = _label("", 18, 0)
	online_status.name = "Status"
	online_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	online_status.custom_minimum_size = Vector2(0, 56)
	box.add_child(online_status)
	box.add_child(_section("Joueurs de la partie"))
	lobby_label = _label("", 22, 0)
	lobby_label.name = "Lobby"
	lobby_label.custom_minimum_size = Vector2(0, 170)
	box.add_child(lobby_label)

	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 16)
	box.add_child(bottom)
	convoy_button = Button.new()
	convoy_button.name = "Convoy"
	convoy_button.text = "CHOISIR MON CONVOI"
	convoy_button.tooltip_text = "Remorque et pouvoirs de votre camion, comme en solo."
	convoy_button.custom_minimum_size = Vector2(320, 64)
	UiKit.style_choice(convoy_button, 22)
	convoy_button.pressed.connect(open_selection)
	bottom.add_child(convoy_button)
	launch_button = Button.new()
	launch_button.name = "Launch"
	launch_button.text = "LANCER LA COURSE"
	launch_button.custom_minimum_size = Vector2(340, 64)
	UiKit.style_primary(launch_button, 26)
	launch_button.pressed.connect(launch_online)
	bottom.add_child(launch_button)
	leave_button = Button.new()
	leave_button.name = "Leave"
	leave_button.text = "QUITTER LA PARTIE"
	leave_button.custom_minimum_size = Vector2(300, 64)
	UiKit.style_choice(leave_button, 22)
	leave_button.pressed.connect(leave_game)
	bottom.add_child(leave_button)
	var back := Button.new()
	back.name = "Back"
	back.text = "RETOUR"
	back.custom_minimum_size = Vector2(220, 64)
	UiKit.style_choice(back, 22)
	back.pressed.connect(toggle_online)
	bottom.add_child(back)
	return layer


func _section(text: String) -> Control:
	return UiKit.section(text)


func _label(text: String, size: int, outline: int) -> Label:
	return UiKit.label(text, size, UiKit.TEXT, 700, false, outline)


static func _box(fill: Color, border: Color, border_width: int, radius: int = 8) -> StyleBoxFlat:
	var sb := UiKit.box(fill, border, border_width, 0.0, radius)
	sb.set_content_margin_all(18)
	return sb


## Boutons des parametres : tuile sombre, cyan au focus (UiKit).
func _style_button(b: Button, _normal: Color, _pressed: Color, font_size: int) -> void:
	UiKit.style_choice(b, font_size)
