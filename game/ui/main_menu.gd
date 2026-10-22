class_name MainMenu
extends Node3D

## Menu principal, range en pages (2026-10-22 : « ameliorer tout ce qui est
## menu [...] ranger tout ca [...] le mode en ligne et local, pas tres bien
## separe ») :
##   ACCUEIL       logo et quatre tuiles : JOUER EN LOCAL, JOUER EN LIGNE,
##                 PARAMETRES, QUITTER ;
##   PARTIE LOCALE par etapes : 1 circuit (menu deroulant), 2 mode de jeu,
##                 3 joueurs et bots (manettes, salle d'attente), 4 regles
##                 (vitesse, duree de l'arene ou largages), puis PRET ;
##   EN LIGNE      menu a part (OnlineMenu) : heberger ou rejoindre, puis le
##                 salon (regles du host, joueurs).
## Local et en ligne gardent chacun leurs reglages (GameState.use_profile).
## Rond / Echap : page precedente ; a l'accueil, Echap quitte. Charte arcade
## neon (UiKit, 2026-10-16). PRET ouvre la page de selection (LoadoutSelect) :
## chaque joueur y choisit remorque et pouvoirs, puis la course part. Decor dedie
## (Showroom) : les camions des joueurs choisis exposes sur un plateau tournant,
## sur le toit d'une tour de Cyber City, sous les projecteurs ; camera en orbite
## lente, decalee pour montrer les camions a droite, le menu a gauche.
## Ambiance du circuit choisi (2026-10-19) : le decor du showroom, le ciel et
## la lumiere (Cyber City de nuit, Playa au soleil, jardin japonais), et toute
## l'interface (UiKit : neon, plage, bois et laque) changent avec lui ;
## l'interface se reconstruit (_restyle) et retrouve son etat.
##
## Manette (PlayStation, positions SDL) : croix directionnelle ou stick pour
## naviguer, Croix pour valider, Rond ou Create pour revenir ; partie locale :
## L1 / R1 pour changer le nombre de joueurs, Triangle pour changer de circuit,
## Options pour PRET.
## Clavier et souris : fleches + Entree, clic ; partie locale : touches 1 a 6,
## T (circuit) ; F11 : plein ecran / fenetre ; Echap revient, a l'accueil
## quitte le jeu.
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

## Noeuds sonores retires des camions du plateau (vehicles/truck.tscn).
const SHOWROOM_MUTED: PackedStringArray = ["Audio", "Horn", "BoostSound"]

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
var drop_buttons: Array[Button] = []
## Duree de l'arene (GameState.ARENA_MINUTES), ligne visible en mode arene.
var arena_time_buttons: Array[Button] = []
var arena_time_row: Control
## Ligne LARGAGES : cachee en arene et en contre-la-montre (aucun largage).
var drops_row: Control
var mode_buttons: Array[Button] = []
const MODE_TIPS: PackedStringArray = [
	"Course classique en 3 tours",
	"Toutes les 20 s, le dernier saute : le dernier en piste gagne",
	"Seul contre le chrono et le fantôme de ton meilleur tour",
	"Arène fermée, 3 vies chacun : le dernier debout gagne",
]
const BOT_LEVELS: PackedStringArray = ["FACILE", "MOYEN", "DUR"]
var speed_buttons: Array[Button] = []
## Circuit : menu deroulant (2026-10-22, « plus des cases, mais un menu
## deroulant »).
var track_option: OptionButton
var subtitle: Label
var title: Label
var start_button: Button
var sound_button: Button
var settings_button: Button
var settings: Control
## Ecran des parametres : case du son (miroir du bouton du menu), volume.
var sound_check: CheckButton
var volume_slider: HSlider
## Jauges Musique et Bruitages (2026-10-22), sous le volume general.
var music_slider: HSlider
var effects_slider: HSlider
var quality_option: OptionButton
## Avertissement avant la qualite extreme, et ses deux boutons.
var extreme_warning: Control
var _warn_yes: Button
var _warn_no: Button
## Compteur d'images par seconde (GameState.show_fps).
var fps_check: CheckButton
## Resolution dynamique de la 3D (GameState.dynamic_resolution).
var dynres_check: CheckButton
## Menu EN LIGNE (OnlineMenu : heberger, rejoindre, salon).
var online: OnlineMenu
## Accueil : tuiles des quatre choix.
var local_tile: Button
var online_tile: Button
var settings_tile: Button
var quit_tile: Button
## Partie locale : explication du mode choisi.
var mode_tip: Label
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
## Pages principales : accueil, partie locale (EN LIGNE : online) ; `page`
## est celle affichee quand aucun panneau (parametres, salle d'attente,
## reaffectation, selection) n'est ouvert par-dessus.
var title_page: Control
var local_page: Control
var page: Control
## Voile et filet sous l'accueil et la partie locale ; son et parametres.
var _backdrop: Control
var _corner: Control
## Page de selection, ouverte par PRET.
var loadout: LoadoutSelect
var _player_dots: HBoxContainer
var _column: VBoxContainer
var _column_gaps: Array[Control] = []
var _fitting: bool = false
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
	# retour d'une partie en ligne (perdue ou en cours) : le menu en ligne, ses
	# reglages ; sinon ceux de la partie locale
	var back_online := NetSession.is_online() or NetSession.last_error != ""
	GameState.use_profile(GameStateNode.Profile.ONLINE if back_online else GameStateNode.Profile.LOCAL)
	apply_ambiance(GameState.selected_track)
	_spawn_trucks()
	_build_ui()
	set_quality(GameState.graphics_quality)
	set_sound(not AudioServer.is_bus_mute(_master_bus()))
	# musique du menu (2026-10-22), en fondu
	var music := MenuMusic.new()
	music.name = "MenuMusic"
	add_child(music)
	music.play()
	# on retrouve le dernier choix en revenant d'une course
	select_players(GameState.requested_players if GameState.requested_players > 0 else 1, false)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	for sig: Signal in [NetSession.lobby_changed, NetSession.joined, NetSession.race_launched]:
		sig.connect(_on_net_changed)
	NetSession.join_failed.connect(func(_r: String) -> void: _on_net_changed())
	NetSession.connection_lost.connect(func(_r: String) -> void: _on_net_changed())
	# retour de course : circuit, vitesse et remorques choisis sont gardes
	GameState.save_settings()
	if back_online:
		show_page(online)
		online.focus_default()
	elif GameState.requested_players > 0:
		# retour d'une course locale : sa page, prete a relancer
		show_page(local_page)
		start_button.grab_focus()
	else:
		show_page(title_page)
		local_tile.grab_focus()
	_place_camera()



## Les 6 camions sur le plateau tournant, geles : du decor, pas de physique.
func _spawn_trucks() -> void:
	for i in LocalRace.MAX_PLAYERS:
		var t := (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
		t.name = "Truck%d" % (i + 1)
		LocalRace.dress(t.get_node("Visual") as TruckVisual, i)
		t.transform = Showroom.slot(i, LocalRace.MAX_PLAYERS)
		t.freeze = true
		# decor muet (2026-10-22, « un bruit sourd au lancement » : six moteurs
		# au ralenti, boucle a 55 Hz) : ni moteur, ni klaxon, ni boost
		for sound: String in SHOWROOM_MUTED:
			var n := t.get_node_or_null(sound)
			if n != null:
				t.remove_child(n)
				n.free()
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
	if extreme_warning != null and extreme_warning.visible:
		return    # l'avertissement de la qualite extreme attend sa reponse
	var key := event as InputEventKey
	var pad := event as InputEventJoypadButton
	# raccourcis de la partie locale : seulement sur sa page
	var on_local := local_page.visible
	if key != null and key.pressed and not key.echo:
		match key.physical_keycode:
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
				if not on_local:
					return
				select_players(key.physical_keycode - KEY_0)
			KEY_T:
				if not on_local:
					return
				select_track((GameState.selected_track + 1) % GameStateNode.TRACKS.size())
			KEY_F11:
				GraphicsSettings.toggle_fullscreen()
			KEY_ESCAPE:
				go_back()
			_:
				return
		get_viewport().set_input_as_handled()
	elif pad != null and pad.pressed:
		# Rond (ui_cancel) : page precedente ; a l'accueil, rien
		if event.is_action_pressed("ui_cancel"):
			if settings.visible or page != title_page:
				go_back()
				get_viewport().set_input_as_handled()
			return
		match pad.button_index:
			JOY_BUTTON_LEFT_SHOULDER:
				if not on_local:
					return
				select_players(selected_players - 1)
			JOY_BUTTON_RIGHT_SHOULDER:
				if not on_local:
					return
				select_players(selected_players + 1)
			JOY_BUTTON_Y:
				if not on_local:
					return
				select_track((GameState.selected_track + 1) % GameStateNode.TRACKS.size())
			JOY_BUTTON_START:
				if not on_local:
					return
				open_selection()
			JOY_BUTTON_BACK:
				if not settings.visible:
					return
				toggle_settings()
			_:
				return
		get_viewport().set_input_as_handled()


## Rond / Echap : ferme les parametres, sinon revient a l'accueil ; a
## l'accueil, Echap quitte le jeu.
func go_back() -> void:
	if settings.visible:
		toggle_settings()
	elif page != title_page:
		back_to_title()
	else:
		get_tree().quit()


## Circuit (GameState.TRACKS), garde dans GameState pour la course et les
## suivantes ; le sous-titre, sous les boutons, annonce son ambiance.
func select_track(k: int) -> void:
	var prev := GameState.selected_track
	GameState.selected_track = clampi(k, 0, GameStateNode.TRACKS.size() - 1)
	if is_node_ready() and GameState.selected_track != prev:
		MenuSound.play_select()
		GameState.save_settings()
	if track_option != null:
		track_option.select(GameState.selected_track)
	# ambiance du circuit : decor et ciel tout de suite, interface a la fin de
	# l'image (le controle clique ne se libere pas pendant son propre signal)
	if is_node_ready() and GameState.selected_track != _ambiance:
		apply_ambiance(GameState.selected_track)
		call_deferred(&"_restyle")
	_update_subtitle()


## Ambiance du circuit choisi, et ses tours (une arene n'en a pas).
func _update_subtitle() -> void:
	if subtitle == null:
		return
	var t: Dictionary = GameStateNode.TRACKS[GameState.selected_track]
	var tag := String(t["tagline"])
	var laps := "arène" if GameState.game_mode == GameStateNode.GameMode.ARENA else "%d tours" % RaceLaps.DEFAULT_LAPS
	subtitle.text = "%s  ·  %s" % [tag.left(1).to_upper() + tag.substr(1), laps]


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
	var open := [settings.visible, join_panel.visible, remap_panel.visible]
	var which := [title_page, local_page, online].find(page)
	remove_child(ui)
	ui.queue_free()
	player_buttons.clear()
	bot_buttons.clear()
	bot_level_buttons.clear()
	drop_buttons.clear()
	arena_time_buttons.clear()
	mode_buttons.clear()
	speed_buttons.clear()
	_join_slots.clear()
	_remap_buttons.clear()
	_build_ui()
	var on := not AudioServer.is_bus_mute(_master_bus())
	sound_button.set_pressed_no_signal(on)
	sound_button.text = "SON : ON" if on else "SON : OFF"
	sound_check.set_pressed_no_signal(on)
	select_players(selected_players, false)
	settings.visible = open[0]
	join_panel.visible = open[1]
	remap_panel.visible = open[2]
	if join_panel.visible:
		_refresh_join()
	show_page([title_page, local_page, online][maxi(which, 0)])
	if local_page.visible:
		track_option.grab_focus()
	elif online.visible:
		online.focus_default()
	elif title_page.visible:
		local_tile.grab_focus()


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
	# habillage a tuiles (bois de Playa, de Sakura) : le bois, en gris teinte
	# a la couleur du joueur (le bois de miel virait le bleu au vert) ; neon :
	# aplat de sa couleur
	if b.get_theme_stylebox("normal") is SkewTileBox:
		if lit:
			b.add_theme_stylebox_override("normal", UiKit.tile_box(c, true))
			b.add_theme_stylebox_override("hover", UiKit.tile_box(c.lightened(0.2), true))
		# choisi : meme bois teinte (style_choice) ; texte sombre sur le jaune
		if c.get_luminance() > 0.55:
			for k: String in ["font_pressed_color", "font_hover_pressed_color"]:
				b.add_theme_color_override(k, UiKit.BTN_TEXT)
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


## Mode de jeu (GameStateNode.GameMode).
func select_mode(k: int, save: bool = true) -> void:
	GameState.game_mode = clampi(k, 0, GameStateNode.MODE_NAMES.size() - 1)
	if save and is_node_ready():
		GameState.save_settings()
		MenuSound.play_select()
	for i in mode_buttons.size():
		mode_buttons[i].set_pressed_no_signal(i == GameState.game_mode)
	if arena_time_row != null:
		arena_time_row.visible = GameState.game_mode == GameStateNode.GameMode.ARENA
	if drops_row != null:
		drops_row.visible = GameState.game_mode != GameStateNode.GameMode.ARENA \
				and GameState.game_mode != GameStateNode.GameMode.TIME_TRIAL
	if mode_tip != null:
		mode_tip.text = MODE_TIPS[GameState.game_mode]
	_update_subtitle()


## Duree d'une manche d'arene (minutes, 0 : sans limite).
func select_arena_time(minutes: int, save: bool = true) -> void:
	GameState.arena_minutes = minutes if GameStateNode.ARENA_MINUTES.has(minutes) else 4
	if save and is_node_ready():
		GameState.save_settings()
		MenuSound.play_select()
	for k in arena_time_buttons.size():
		arena_time_buttons[k].set_pressed_no_signal(GameStateNode.ARENA_MINUTES[k] == GameState.arena_minutes)


## Largages de remorque par joueur et par course (0 a 5).
func select_drops(n: int, save: bool = true) -> void:
	GameState.trailer_drops = clampi(n, 0, GameStateNode.MAX_TRAILER_DROPS)
	if save and is_node_ready():
		GameState.save_settings()
		MenuSound.play_select()
	for k in drop_buttons.size():
		drop_buttons[k].set_pressed_no_signal(k == GameState.trailer_drops)


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


## PRET : la page de selection (une carte par joueur), la page du menu se
## cache.
func open_selection() -> void:
	MenuSound.play_confirm()
	if NetSession.is_online():
		# en ligne : la meme page, pour le seul joueur de ce PC ; son choix part
		# au salon (start_race), puis le host lance quand tout le monde est PRET
		loadout.open(1)
		_update_home()
		return
	GameState.requested_players = selected_players
	loadout.open(selected_players)
	_update_home()


## Retour de la page de selection vers la partie locale (en ligne : le salon).
func close_selection() -> void:
	loadout.close()
	MenuSound.play_toggle()
	if NetSession.is_online():
		_show_lobby()
		return
	show_page(local_page)
	start_button.grab_focus()


## En ligne : le salon, de nouveau au premier plan.
func _show_lobby() -> void:
	show_page(online)
	online.refresh()
	online.focus_default()


## Page principale affichee (title_page, local_page, online).
func show_page(p: Control) -> void:
	page = p
	_update_home()
	if online_tile != null:
		_refresh_title()


## Accueil -> partie locale (reglages du profil local).
func open_local() -> void:
	if NetSession.is_online():
		return    # quitter d'abord la partie en ligne (tuile grisee)
	MenuSound.play_confirm()
	_use_profile(GameStateNode.Profile.LOCAL)
	select_bots(GameState.bot_count, false)
	show_page(local_page)
	start_button.grab_focus()


## Accueil -> menu en ligne (reglages du profil en ligne).
func open_online() -> void:
	MenuSound.play_confirm()
	_use_profile(GameStateNode.Profile.ONLINE)
	show_page(online)
	online.refresh()
	online.focus_default()


## Retour a l'accueil ; une partie en ligne reste ouverte (QUITTER LA PARTIE,
## dans le salon, la ferme).
func back_to_title() -> void:
	var from := page
	MenuSound.play_toggle()
	show_page(title_page)
	(online_tile if from == online else local_tile).grab_focus()


## Passe au profil de reglages `p` ; l'ambiance suit son circuit.
func _use_profile(p: int) -> void:
	if GameState.use_profile(p):
		_follow_track(GameState.selected_track)
		return
	_refresh_local_choices()


## Choix de la partie locale remis sur les reglages du profil actif.
func _refresh_local_choices() -> void:
	select_speed(GameState.speed_class)
	select_mode(GameState.game_mode, false)
	select_arena_time(GameState.arena_minutes, false)
	select_drops(GameState.trailer_drops, false)
	select_bot_level(GameState.bot_level, false)
	select_bots(GameState.bot_count, false)


## Ambiance du circuit `track` (decor tout de suite, interface reconstruite a
## la fin de l'image).
func _follow_track(track: int) -> void:
	if track_option != null:
		track_option.select(track)
	if track != _ambiance:
		apply_ambiance(track)
		call_deferred(&"_restyle")


## Partie en ligne changee (salon, connexion, perte) : tuile de l'accueil ;
## client : l'ambiance suit le circuit choisi par le host.
func _on_net_changed() -> void:
	if online_tile != null:
		_refresh_title()
	if NetSession.is_client() and not NetSession.host_rules.is_empty() and online.visible:
		var track := int(NetSession.host_rules["track"])
		if track != _ambiance:
			GameState.selected_track = track
			_follow_track(track)


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


## Ligne choisie dans la liste des qualites : l'extreme demande d'abord
## confirmation (2026-10-22 : « on met un warning avant que la personne
## selectionne Extreme »), la liste reste sur l'ancienne qualite en attendant.
func _on_quality_item(index: int) -> void:
	var q := quality_option.get_item_id(index)
	if q == GraphicsSettings.Quality.EXTREME and GameState.graphics_quality != q:
		quality_option.select(quality_option.get_item_index(GameState.graphics_quality))
		show_extreme_warning()
		return
	set_quality(q)


## Avertissement de la qualite extreme : par-dessus tout le menu.
func show_extreme_warning() -> void:
	extreme_warning.visible = true
	_warn_no.grab_focus()
	MenuSound.play_select()


## Ferme l'avertissement ; `accept` : passe en qualite extreme.
func close_extreme_warning(accept: bool) -> void:
	if extreme_warning == null or not extreme_warning.visible:
		return
	extreme_warning.visible = false
	if accept:
		set_quality(GraphicsSettings.Quality.EXTREME)
		MenuSound.play_confirm()
	else:
		MenuSound.play_toggle()
	if quality_option != null and quality_option.is_visible_in_tree():
		quality_option.grab_focus()


## Carte d'avertissement a l'habillage du circuit : voile, cadre or, texte,
## « Oui, activer » / « Annuler » (Annuler par defaut).
func _build_extreme_warning() -> Control:
	var layer := Control.new()
	layer.name = "ExtremeWarning"
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.visible = false
	var dim := ColorRect.new()
	dim.color = Color(UiKit.NIGHT, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)
	var card := UiKit.card(UiKit.GOLD, 780.0)
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	card.add_child(col)
	col.add_child(UiKit.section("Qualité extrême", 22))
	var msg := UiKit.label(GraphicsSettings.EXTREME_WARNING, 26, UiKit.TEXT, 800, false)
	msg.name = "Message"
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size = Vector2(720, 0)
	col.add_child(msg)
	var more := UiKit.label("Reflets, ombres et éclairage au maximum, décor plus dense et plus détaillé (arbres, bâtiments) : "
		+ "fait pour les grands écrans et la 4K. Sur un PC portable, les images par seconde chutent.", 18, UiKit.DIM, 600, false)
	more.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	more.custom_minimum_size = Vector2(720, 0)
	col.add_child(more)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(row)
	_warn_no = Button.new()
	_warn_no.name = "Cancel"
	_warn_no.text = "ANNULER"
	_warn_no.custom_minimum_size = Vector2(220, 60)
	UiKit.style_choice(_warn_no, 22)
	_warn_no.pressed.connect(close_extreme_warning.bind(false))
	row.add_child(_warn_no)
	_warn_yes = Button.new()
	_warn_yes.name = "Accept"
	_warn_yes.text = "OUI, ACTIVER"
	_warn_yes.custom_minimum_size = Vector2(260, 60)
	UiKit.style_primary(_warn_yes, 22)
	_warn_yes.pressed.connect(close_extreme_warning.bind(true))
	row.add_child(_warn_yes)
	_warn_no.focus_neighbor_right = _warn_no.get_path_to(_warn_yes)
	_warn_yes.focus_neighbor_left = _warn_yes.get_path_to(_warn_no)
	return layer


## Qualite graphique (GraphicsSettings.Quality), gardee dans GameState pour les
## courses ; appliquee tout de suite au decor du menu (une seule vue).
func set_quality(q: int) -> void:
	GameState.graphics_quality = clampi(q, 0, GraphicsSettings.NAMES.size() - 1)
	if quality_option != null:
		quality_option.select(quality_option.get_item_index(GameState.graphics_quality))
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


## Jauge de la musique (0 a 100 %), gardee dans GameState.
func set_music_volume(percent: float) -> void:
	GameState.music_volume = clampf(percent, 0.0, 100.0)
	SoundMix.apply_user_volumes(GameState.music_volume, GameState.effects_volume)
	if is_node_ready():
		GameState.save_settings()


## Jauge des bruitages et de l'ambiance (0 a 100 %) ; un bip pour l'entendre.
func set_effects_volume(percent: float) -> void:
	GameState.effects_volume = clampf(percent, 0.0, 100.0)
	SoundMix.apply_user_volumes(GameState.music_volume, GameState.effects_volume)
	if is_node_ready():
		GameState.save_settings()
		MenuSound.play_select()


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
	if extreme_warning != null and extreme_warning.visible:
		var k := event as InputEventKey
		var b := event as InputEventJoypadButton
		if (k != null and k.pressed and not k.echo and k.physical_keycode == KEY_ESCAPE) \
				or (b != null and b.pressed and b.button_index == JOY_BUTTON_B):
			close_extreme_warning(false)
			get_viewport().set_input_as_handled()
		return
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


## Ligne d'une jauge de volume des parametres : intitule, curseur (0 a 100 %,
## par pas de 5), pourcentage ; ajoutee a `box`, rend le curseur.
func _volume_row(box: Container, slider_name: String, text: String, value: float, on_change: Callable) -> HSlider:
	var row := HBoxContainer.new()
	# texte aligne sur celui des interrupteurs (marge de 6 px)
	row.add_theme_constant_override("separation", 6)
	row.add_child(UiKit.gap(0))
	var l := UiKit.label(text, 19, UiKit.TEXT, 600, false)
	l.custom_minimum_size.x = 150
	row.add_child(l)
	var s := HSlider.new()
	s.name = slider_name
	s.min_value = 0.0
	s.max_value = 100.0
	s.step = 5.0
	s.value = value
	s.custom_minimum_size = Vector2(200, 0)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiKit.style_slider(s)
	row.add_child(s)
	var pct := UiKit.label("%d %%" % roundi(value), 17, UiKit.DIM, 600, false)
	pct.custom_minimum_size.x = 58
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(pct)
	s.value_changed.connect(func(v: float) -> void: pct.text = "%d %%" % roundi(v))
	s.value_changed.connect(on_change)
	box.add_child(row)
	return s


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


func toggle_settings() -> void:
	settings.visible = not settings.visible
	_update_home()
	MenuSound.play_toggle()
	if settings.visible:
		(settings.find_child("Back", true, false) as Button).grab_focus()
	elif page == title_page:
		settings_tile.grab_focus()
	else:
		settings_button.grab_focus()


## Seule la page principale est affichee, et seulement sans panneau ouvert
## par-dessus (son texte transparaissait sous le voile) ; voile, son et
## parametres avec l'accueil et la partie locale.
func _update_home() -> void:
	if title_page == null or settings == null:
		return
	var covered := settings.visible or join_panel.visible or remap_panel.visible or (loadout != null and loadout.visible)
	for p: Control in [title_page, local_page, online]:
		p.visible = p == page and not covered
	_backdrop.visible = (page == title_page or page == local_page) and not covered
	_corner.visible = _backdrop.visible


## Tuiles de l'accueil selon la partie en ligne : JOUER EN LOCAL grisee tant
## qu'elle est ouverte, JOUER EN LIGNE ramene au salon.
func _refresh_title() -> void:
	var online_now := NetSession.is_online()
	local_tile.disabled = online_now
	_tile_ink(local_tile)
	_tile_text(local_tile, "Quitte d'abord la partie en ligne (salon : QUITTER LA PARTIE)" if online_now
		else "Seul ou jusqu'à %d sur ce PC, en écran partagé, avec ou sans bots" % LocalRace.MAX_PLAYERS)
	var n := NetSession.members.size()
	_tile_text(online_tile, ("Partie en cours : %d joueur%s  ·  retour au salon" % [n, "s" if n > 1 else ""]) if online_now
		else "Jusqu'à %d joueurs, en réseau local ou par Internet" % NetSessionNode.MAX_PLAYERS)


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
## Hauteur de la colonne : du haut (40) a la barre d'aide (64 px), moins une
## marge ; espace garde au minimum entre VITESSE et PRET.
const COLUMN_H := 960.0
const START_GAP := 14
## Teinte de chaque circuit : pastille du menu deroulant (Cyber City : nuit
## violette ; Playa : lagon ; Sakura : cerisier).
const TRACK_TINTS: Array[Color] = [Color(0.36, 0.1, 0.62), Color(0.0, 0.5, 0.58), Color(0.86, 0.3, 0.48)]


## Interface (2026-10-16 : « fait une vraie belle UI de jeu video » ; rangee
## en pages le 2026-10-22) : voile degrade a gauche sur le showroom, son et
## parametres en haut a droite, puis les pages - accueil, partie locale, en
## ligne - et les panneaux qui passent par-dessus (selection, parametres,
## salle d'attente, reaffectation, avertissement de la qualite extreme).
func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	_backdrop = _build_backdrop()
	root.add_child(_backdrop)
	title_page = _build_title()
	root.add_child(title_page)
	local_page = _build_local()
	root.add_child(local_page)
	online = OnlineMenu.new()
	online.name = "Online"
	online.visible = false
	root.add_child(online)
	online.back_requested.connect(back_to_title)
	online.convoy_requested.connect(open_selection)
	online.ambiance_requested.connect(_follow_track)
	_corner = _build_corner()
	root.add_child(_corner)

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
	join_panel = _build_join()
	root.add_child(join_panel)
	remap_panel = _build_remap()
	root.add_child(remap_panel)
	extreme_warning = _build_extreme_warning()
	root.add_child(extreme_warning)
	if page == null:
		page = title_page
	_refresh_title()


## Voile (nuit opaque a gauche, transparente vers les camions) et filet
## incline le long de la colonne.
func _build_backdrop() -> Control:
	var back := Control.new()
	back.name = "Backdrop"
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	back.add_child(veil)
	var stripe := Panel.new()
	stripe.add_theme_stylebox_override("panel", UiKit.box(Color(ACCENT, 0.75), Color(0, 0, 0, 0), 0, -0.6 * UiKit.SKEW, 1,
		Color(ACCENT, 0.4), 10))
	stripe.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	stripe.offset_left = COLUMN_X + COLUMN_W + 64
	stripe.offset_right = COLUMN_X + COLUMN_W + 68
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(stripe)
	return back


## Coin haut droit : son et parametres, boutons ronds.
func _build_corner() -> Control:
	var corner := HBoxContainer.new()
	corner.name = "Corner"
	corner.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	corner.offset_top = 32
	corner.offset_right = -36
	corner.add_theme_constant_override("separation", 12)
	# compteur d'images par seconde sous ces boutons (il les recouvrait)
	GameState.set_fps_top(corner.offset_top + 56.0 + 14.0)
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
	_gear.color = UiKit.icon_color()
	_gear.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_gear.offset_left = 13
	_gear.offset_top = 13
	_gear.offset_right = -13
	_gear.offset_bottom = -13
	settings_button.add_child(_gear)
	return corner


## Page vide plein ecran (accueil, partie locale) et sa colonne de gauche.
func _blank_page(page_name: String) -> Control:
	var p := Control.new()
	p.name = page_name
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.visible = false
	return p


## Barre d'aide en bas, sur toute la largeur : pictos `prompts`.
func _help_bar(prompts: Array) -> Control:
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
	var help := HBoxContainer.new()
	help.add_theme_constant_override("separation", 30)
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(help)
	for p: Array in prompts:
		help.add_child(UiKit.prompt(String(p[0]), String(p[1])))
	return bar


## Accueil : logo (anime), « course de camions arcade », puis quatre tuiles
## l'une sous l'autre - JOUER EN LOCAL, JOUER EN LIGNE, PARAMETRES, QUITTER.
func _build_title() -> Control:
	var p := _blank_page("Title")
	var column := VBoxContainer.new()
	column.name = "Column"
	column.position = Vector2(COLUMN_X, 70)
	column.custom_minimum_size = Vector2(COLUMN_W, 0)
	column.add_theme_constant_override("separation", 0)
	p.add_child(column)
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
	column.add_child(UiKit.gap(64))

	local_tile = _tile("PlayLocal", "JOUER EN LOCAL", "", true)
	local_tile.pressed.connect(open_local)
	column.add_child(local_tile)
	column.add_child(UiKit.gap(16))
	online_tile = _tile("PlayOnline", "JOUER EN LIGNE", "", false)
	online_tile.pressed.connect(open_online)
	column.add_child(online_tile)
	column.add_child(UiKit.gap(16))
	settings_tile = _tile("Options", "PARAMÈTRES", "Commandes, manettes, son et image", false)
	settings_tile.pressed.connect(toggle_settings)
	column.add_child(settings_tile)
	column.add_child(UiKit.gap(16))
	quit_tile = _tile("Quit", "QUITTER", "", false)
	quit_tile.custom_minimum_size.y = 64
	quit_tile.pressed.connect(func() -> void: get_tree().quit())
	column.add_child(quit_tile)
	p.add_child(_help_bar([["cross", "Valider"], ["key:Entrée", "Valider"], ["key:F11", "Plein écran"],
		["key:Échap", "Quitter"]]))
	return p


## Tuile de l'accueil : grand titre, ligne d'explication dessous (vide :
## titre seul) ; `primary` : couleur de l'action principale.
func _tile(tile_name: String, text: String, sub: String, primary: bool) -> Button:
	var b := Button.new()
	b.name = tile_name
	b.custom_minimum_size = Vector2(COLUMN_W, 104)
	if primary:
		UiKit.style_primary(b, 36)
	else:
		UiKit.style_choice(b, 36)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 34
	box.offset_right = -24
	# au-dessus de la jointure basse des planches (habillages en bois)
	box.offset_top = 4
	box.offset_bottom = -16
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	var head := UiKit.label(text, 34, UiKit.TEXT, 900)
	head.name = "Head"
	box.add_child(head)
	var line := UiKit.label(sub, 17, UiKit.TEXT, 700, false)
	line.name = "Sub"
	line.visible = sub != ""
	box.add_child(line)
	b.set_meta(&"primary", primary)
	_tile_ink(b)
	return b


## Couleur du texte d'une tuile : celle de son bouton, claire et attenuee
## quand elle est grisee (texte sombre sur fond eteint, illisible).
static func _tile_ink(tile: Button) -> void:
	var ink := UiKit.PRIMARY_TEXT if bool(tile.get_meta(&"primary", false)) else UiKit.BTN_TEXT
	if tile.disabled:
		ink = Color(UiKit.TEXT, 0.55)
	(tile.find_child("Head", true, false) as Label).add_theme_color_override("font_color", ink)
	(tile.find_child("Sub", true, false) as Label).add_theme_color_override("font_color", Color(ink, ink.a * 0.8))


## Ligne d'explication d'une tuile de l'accueil.
static func _tile_text(tile: Button, sub: String) -> void:
	var line := tile.find_child("Sub", true, false) as Label
	line.text = sub
	line.visible = sub != ""


## Partie locale, par etapes : 1 CIRCUIT (menu deroulant, 2026-10-22), 2 MODE
## (et son explication), 3 JOUEURS (pastilles, bots, manettes et salle
## d'attente), 4 REGLES (vitesse, duree de l'arene ou largages), puis RETOUR
## et le gros PRET qui ouvre la page de selection (LoadoutSelect).
func _build_local() -> Control:
	var p := _blank_page("Local")
	var column := VBoxContainer.new()
	column.name = "Column"
	column.position = Vector2(COLUMN_X, 40)
	column.size = Vector2(COLUMN_W, COLUMN_H)
	column.add_theme_constant_override("separation", 0)
	p.add_child(column)
	_column = column
	_column_gaps.clear()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(head)
	head.add_child(UiKit.label("PARTIE LOCALE", 52, UiKit.LOGO_TOP, 900))
	var head_sub := UiKit.label("sur ce PC  ·  écran partagé", 18, UiKit.CYAN, 800)
	head_sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(head_sub)
	column.add_child(_column_gap(22))

	# 1. circuit : menu deroulant, son ambiance dessous
	column.add_child(_section("1  ·  Circuit"))
	column.add_child(_column_gap(8))
	track_option = track_dropdown(24, 64)
	track_option.item_selected.connect(select_track)
	column.add_child(track_option)
	subtitle = UiKit.label("", 17, TEXT_DIM, 600, false)
	column.add_child(_column_gap(6))
	column.add_child(subtitle)
	select_track(GameState.selected_track)
	column.add_child(_column_gap(30))

	# 2. mode de jeu
	column.add_child(_section("2  ·  Mode de jeu"))
	column.add_child(_column_gap(8))
	var mode_row := _row("Modes")
	var mode_group := ButtonGroup.new()
	for k in GameStateNode.MODE_NAMES.size():
		var mb := _choice("Mode%d" % k, GameStateNode.MODE_NAMES[k], mode_group, 16)
		mb.custom_minimum_size.y = 46
		mb.tooltip_text = MODE_TIPS[k]
		mb.pressed.connect(select_mode.bind(k))
		mode_row.add_child(mb)
		mode_buttons.append(mb)
	column.add_child(mode_row)
	mode_tip = UiKit.label("", 17, TEXT_DIM, 600, false)
	mode_tip.name = "ModeTip"
	column.add_child(_column_gap(6))
	column.add_child(mode_tip)
	column.add_child(_column_gap(30))

	# 3. joueurs et bots
	column.add_child(_section("3  ·  Joueurs"))
	column.add_child(_column_gap(8))
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
	column.add_child(_column_gap(8))
	column.add_child(_player_dots)
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
	column.add_child(_column_gap(8))
	column.add_child(pads_row)
	# bots : nombre et niveau, sur une ligne
	column.add_child(_column_gap(8))
	var bots_row := _row("Bots")
	bots_row.add_child(_row_label("BOTS", 72))
	var bots_group := ButtonGroup.new()
	for k in LocalRace.MAX_PLAYERS:
		var bb := _choice("Bots%d" % k, str(k), bots_group, 20)
		bb.custom_minimum_size.y = 40
		bb.tooltip_text = "Aucun bot" if k == 0 else "%d bot%s pilote%s par l'ordinateur" % [k, "s" if k > 1 else "", "s" if k > 1 else ""]
		bb.pressed.connect(select_bots.bind(k))
		bots_row.add_child(bb)
		bot_buttons.append(bb)
	bots_row.add_child(UiKit.gap(0))
	var level_group := ButtonGroup.new()
	for k in BOT_LEVELS.size():
		var lb := _choice("BotLevel%d" % k, BOT_LEVELS[k], level_group, 16)
		lb.custom_minimum_size = Vector2(96, 40)
		lb.size_flags_horizontal = Control.SIZE_FILL
		lb.pressed.connect(select_bot_level.bind(k))
		bots_row.add_child(lb)
		bot_level_buttons.append(lb)
	column.add_child(bots_row)
	select_bots(GameState.bot_count, false)
	select_bot_level(GameState.bot_level, false)
	column.add_child(_column_gap(30))

	# 4. regles : vitesse, puis duree de l'arene ou largages selon le mode
	column.add_child(_section("4  ·  Règles"))
	column.add_child(_column_gap(8))
	var speed_row := _row("Speeds")
	column.add_child(speed_row)
	var speed_group := ButtonGroup.new()
	for k in GameStateNode.SPEED_CLASSES.size():
		var c: Dictionary = GameStateNode.SPEED_CLASSES[k]
		var sbtn := _choice("Speed%d" % k, "%s  %s\n%s" % [c["cc"], ">".repeat(k + 1), String(c["name"]).to_upper()],
			speed_group, 18)
		sbtn.custom_minimum_size.y = 54
		sbtn.tooltip_text = "%s : %d km/h" % [c["name"], int(c["top_kmh"])]
		sbtn.pressed.connect(select_speed.bind(k))
		speed_row.add_child(sbtn)
		speed_buttons.append(sbtn)
	select_speed(GameState.speed_class)
	# duree de l'arene (2026-10-21), visible en mode arene
	var time_row := _row("ArenaTime")
	time_row.add_child(_row_label("DURÉE", 112))
	var time_group := ButtonGroup.new()
	for minutes in GameStateNode.ARENA_MINUTES:
		var ab := _choice("ArenaTime%d" % minutes, "%d MIN" % minutes if minutes > 0 else "SANS LIMITE", time_group, 15)
		ab.custom_minimum_size.y = 40
		ab.tooltip_text = "Manche d'arène de %d minutes" % minutes if minutes > 0 \
				else "Pas de limite de temps : le dernier debout gagne"
		ab.pressed.connect(select_arena_time.bind(minutes))
		time_row.add_child(ab)
		arena_time_buttons.append(ab)
	column.add_child(_column_gap(8))
	column.add_child(time_row)
	arena_time_row = time_row
	select_arena_time(GameState.arena_minutes, false)
	# largages de remorque par joueur dans la course (2026-10-20)
	drops_row = _row("Drops")
	drops_row.add_child(_row_label("LARGAGES", 112))
	var drops_group := ButtonGroup.new()
	for k in GameStateNode.MAX_TRAILER_DROPS + 1:
		var db := _choice("Drops%d" % k, str(k), drops_group, 20)
		db.custom_minimum_size.y = 40
		db.tooltip_text = "Aucun largage de remorque" if k == 0 \
				else "%d largage%s de remorque par joueur et par course" % [k, "s" if k > 1 else ""]
		db.pressed.connect(select_drops.bind(k))
		drops_row.add_child(db)
		drop_buttons.append(db)
	column.add_child(drops_row)
	select_drops(GameState.trailer_drops, false)
	select_mode(GameState.game_mode, false)

	# RETOUR et PRET : la page de selection
	var push := Control.new()
	push.custom_minimum_size.y = START_GAP
	push.size_flags_vertical = Control.SIZE_EXPAND_FILL
	push.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(push)
	var go_row := HBoxContainer.new()
	go_row.add_theme_constant_override("separation", 16)
	column.add_child(go_row)
	var back := Button.new()
	back.name = "Back"
	back.text = "RETOUR"
	back.custom_minimum_size = Vector2(190, 72)
	UiKit.style_choice(back, 24)
	back.pressed.connect(back_to_title)
	go_row.add_child(back)
	start_button = Button.new()
	start_button.name = "Start"
	start_button.text = "PRÊT"
	start_button.custom_minimum_size = Vector2(0, 72)
	start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiKit.style_primary(start_button, 52)
	start_button.pressed.connect(open_selection)
	go_row.add_child(start_button)
	column.add_child(_column_gap(8))
	var next := UiKit.label("ensuite : remorque et pouvoirs de chaque joueur", 16, TEXT_DIM, 600, false)
	next.name = "NextHint"
	next.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(next)
	column.minimum_size_changed.connect(_fit_column)
	_fit_column()

	var bar := _help_bar([["cross", "Valider"], ["circle", "Accueil"], ["l1", "/"], ["triangle", "Circuit"],
		["options", "Prêt"], ["key:1-6", "Joueurs"], ["key:T", "Circuit"], ["key:Échap", "Accueil"]])
	var help := bar.get_child(0) as HBoxContainer
	var lr := help.get_child(2) as HBoxContainer
	lr.add_child(_glyph("r1", 28))
	lr.add_child(UiKit.label("Joueurs", 18, UiKit.TEXT, 600, false))
	p.add_child(bar)
	return p


## Intitule d'une rangee de choix (BOTS, DUREE, LARGAGES), centre en hauteur.
func _row_label(text: String, width: int) -> Label:
	var l := _label(text, 18, 0)
	l.custom_minimum_size.x = width
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## Menu deroulant des circuits (partie locale, salon en ligne) : une ligne
## par circuit, nom en capitales precede d'une pastille a sa teinte ;
## l'ambiance en infobulle. L'index de la ligne est celui du circuit.
static func track_dropdown(font_size: int, height: int) -> OptionButton:
	var o := OptionButton.new()
	o.name = "Track"
	o.custom_minimum_size = Vector2(0, height)
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.fit_to_longest_item = false
	for k in GameStateNode.TRACKS.size():
		var t: Dictionary = GameStateNode.TRACKS[k]
		o.add_icon_item(_track_swatch(TRACK_TINTS[k % TRACK_TINTS.size()], font_size), String(t["name"]).to_upper(), k)
		o.set_item_tooltip(k, String(t["tagline"]))
	UiKit.style_option(o, font_size)
	for st: String in ["normal", "hover", "pressed", "focus"]:
		var sb := o.get_theme_stylebox(st) as StyleBoxFlat
		if sb != null:
			sb.content_margin_left = 18
			sb.content_margin_right = 18
	o.add_theme_constant_override("h_separation", 14)
	var popup := o.get_popup()
	popup.add_theme_constant_override("v_separation", 14)
	# liste ouverte sur le circuit choisi : la croix part de lui (sans ca, la
	# premiere fleche ne faisait que surligner la premiere ligne)
	popup.about_to_popup.connect(func() -> void: popup.set_focused_item.call_deferred(o.selected))
	return o


## Pastille carree d'un circuit (icone du menu deroulant).
static func _track_swatch(tint: Color, font_size: int) -> Texture2D:
	var s := maxi(12, roundi(font_size * 0.9))
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(tint.lightened(0.15))
	for i in s:
		for edge: Vector2i in [Vector2i(i, 0), Vector2i(i, s - 1), Vector2i(0, i), Vector2i(s - 1, i)]:
			img.set_pixelv(edge, Color(1, 1, 1, 0.7))
	return ImageTexture.create_from_image(img)


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
	b.custom_minimum_size = Vector2(0, 48)
	UiKit.style_choice(b, font_size)
	return b


func _gap(height: int) -> Control:
	return UiKit.gap(height)


## Intervalle de la colonne d'accueil, resserre par _fit_column.
func _column_gap(height: int) -> Control:
	var g := UiKit.gap(height)
	g.set_meta(&"base", height)
	_column_gaps.append(g)
	return g


## Colonne d'accueil dans sa hauteur (2026-10-20, « la note pres » passait
## sous la barre d'aide en Playa : police plus haute, texte des manettes sur
## deux lignes) : si le contenu deborde de COLUMN_H, les intervalles se
## resserrent d'autant (pas sous 30 %), PRET et sa note restent au-dessus de
## la barre.
func _fit_column() -> void:
	if _fitting or _column == null:
		return
	_fitting = true
	# contenu seul (sans les intervalles actuels), puis intervalles voulus :
	# ne change rien si deja bons (pas de boucle de minimum_size_changed)
	var now := 0.0
	var base := 0.0
	for g in _column_gaps:
		now += g.custom_minimum_size.y
		base += float(g.get_meta(&"base"))
	var over := _column.get_combined_minimum_size().y - now + base - COLUMN_H
	var f := clampf(1.0 - over / base, 0.3, 1.0) if over > 0.0 and base > 0.0 else 1.0
	for g in _column_gaps:
		g.custom_minimum_size.y = floorf(float(g.get_meta(&"base")) * f)
	_column.size = Vector2(COLUMN_W, COLUMN_H)
	_fitting = false


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
		"J1 — flèches · Ctrl droit drift · Maj droite boost · ; cargo · ! klaxon · : vue · Fin regarder derrière · K / L pouvoirs · J cible · Retour arrière reset",
		"J2 — Z Q S D · Espace drift · Maj gauche boost · E cargo · H klaxon · C vue · B regarder derrière · F / G pouvoirs · T cible · R reset",
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
	UiKit.style_toggle(sound_check, 19)
	sound_check.toggled.connect(set_sound)
	opts.add_child(sound_check)
	# trois jauges : generale (Master), musique, bruitages (2026-10-22)
	volume_slider = _volume_row(opts, "Volume", "Volume général",
		roundf(db_to_linear(AudioServer.get_bus_volume_db(_master_bus())) * 100.0), set_volume)
	music_slider = _volume_row(opts, "MusicVolume", "Musique", GameState.music_volume, set_music_volume)
	effects_slider = _volume_row(opts, "EffectsVolume", "Bruitages", GameState.effects_volume, set_effects_volume)
	quality_option = OptionButton.new()
	quality_option.name = "Quality"
	# de la plus riche a la plus legere ; l'identifiant de chaque ligne est la
	# qualite (GraphicsSettings.Quality), pas sa place dans la liste
	for q: int in GraphicsSettings.MENU_ORDER:
		quality_option.add_item("Qualité graphique : %s" % GraphicsSettings.NAMES[q], q)
	quality_option.tooltip_text = "Extrême : tout au maximum et décor plus riche (carte graphique dédiée). " \
		+ "Haute : reflets, éclairage indirect, occlusion. Moyenne : occlusion. Basse : aucun effet."
	UiKit.style_option(quality_option, 19)
	quality_option.select(quality_option.get_item_index(GameState.graphics_quality))
	quality_option.item_selected.connect(_on_quality_item)
	opts.add_child(quality_option)
	fps_check = CheckButton.new()
	fps_check.name = "FpsCheck"
	fps_check.text = "Compteur d'images par seconde (FPS)"
	fps_check.tooltip_text = "Affiché en haut à droite, au menu et en course."
	UiKit.style_toggle(fps_check, 19)
	fps_check.button_pressed = GameState.show_fps
	fps_check.toggled.connect(set_show_fps)
	opts.add_child(fps_check)

	dynres_check = CheckButton.new()
	dynres_check.name = "DynResCheck"
	dynres_check.text = "Résolution dynamique"
	dynres_check.tooltip_text = "Baisse la résolution de la 3D seulement quand la carte graphique\nne tient plus 60 images/s (mise à l'échelle FSR). Effets intacts."
	UiKit.style_toggle(dynres_check, 19)
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
