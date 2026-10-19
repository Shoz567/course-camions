class_name MainMenu
extends Node3D

## Ecran d'accueil (tache 4.2, partiel) : titre anime, choix du circuit (Cyber
## City ou Playa Del Sol), du nombre de joueurs (1 a 6), de la categorie de
## vitesse, START / COMMENCER, son on / off, parametres. Decor dedie
## (Showroom) : les camions des joueurs choisis exposes sur un plateau tournant,
## sur le toit d'une tour de Cyber City, sous les projecteurs ; camera en orbite
## lente, decalee pour montrer les camions a droite, le menu a gauche.
##
## Manette (PlayStation, positions SDL) : croix directionnelle ou stick pour
## naviguer, Croix pour valider, Rond ou Create pour fermer les parametres,
## L1 / R1 pour changer le nombre de joueurs, Triangle pour changer de circuit,
## Options pour commencer.
## Clavier et souris : fleches + Entree, touches 1 a 6, T (circuit), clic ;
## F11 : plein ecran / fenetre ; Echap ferme les parametres, sinon quitte le
## jeu.
##
## COMMENCER ecrit le choix dans GameState (requested_players, selected_track)
## puis charge la scene de course du circuit (LocalRace le lit). Le menu ne touche pas a la physique : les
## camions de decor sont geles.

signal launch_requested(players: int)

const LocalRace := preload("res://dev/local_race.gd")

## Faux pour les tests : COMMENCER emet `launch_requested` sans changer de scene.
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
var online_status: Label
var lobby_label: Label
## Host : connexion qui envoie peu (snapshots a 20 Hz au lieu de 60).
var slow_check: CheckButton
var _gear: GearIcon
var _pads_label: Label
var _orbit_center: Vector3
var _orbit_angle: float = 0.0
var _time: float = 0.0
var _fov_target: float = 55.0


func _ready() -> void:
	DebugDraw.enabled = false
	_setup_menu_input()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.current = true
	_spawn_trucks()
	_build_ui()
	set_quality(GameState.graphics_quality)
	set_sound(not AudioServer.is_bus_mute(_master_bus()))
	# musique de course rendue en fond pendant le menu (sans effet en headless)
	RaceMusic.prepare()
	# on retrouve le dernier choix en revenant d'une course
	select_players(GameState.requested_players if GameState.requested_players > 0 else 1)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	for sig: Signal in [NetSession.lobby_changed, NetSession.joined, NetSession.race_launched]:
		sig.connect(_refresh_online)
	NetSession.join_failed.connect(func(_r: String) -> void: _refresh_online())
	NetSession.connection_lost.connect(func(_r: String) -> void: _refresh_online())
	_refresh_online()
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
					start_race()
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
	for i in track_buttons.size():
		track_buttons[i].set_pressed_no_signal(i == GameState.selected_track)
	if subtitle != null:
		var t: Dictionary = GameStateNode.TRACKS[GameState.selected_track]
		var tag := String(t["tagline"])
		subtitle.text = "%s  ·  4 tours" % (tag.left(1).to_upper() + tag.substr(1))


## Scene de course du circuit choisi.
func race_scene() -> String:
	return GameStateNode.track_scene(GameState.selected_track)


## Categorie de vitesse (0 = Lent .. 3 = Ultrasonique), gardee dans GameState
## pour la course et les suivantes.
func select_speed(k: int) -> void:
	GameState.speed_class = clampi(k, 0, GameStateNode.SPEED_CLASSES.size() - 1)
	for i in speed_buttons.size():
		speed_buttons[i].set_pressed_no_signal(i == GameState.speed_class)


## Nombre de joueurs (borne a 1..6) : bouton enfonce, camions montres.
func select_players(n: int) -> void:
	var prev := selected_players
	selected_players = clampi(n, 1, LocalRace.MAX_PLAYERS)
	if is_node_ready() and selected_players != prev:
		MenuSound.play_select()
	for i in player_buttons.size():
		player_buttons[i].set_pressed_no_signal(i == selected_players - 1)
	_fov_target = fov_deg if selected_players <= 4 else fov_wide_deg
	for i in trucks.size():
		trucks[i].visible = i < selected_players
		# les camions exposes restent centres sur le plateau
		if i < selected_players:
			trucks[i].transform = Showroom.slot(i, selected_players)
	_update_pads_label()


func start_race() -> void:
	if NetSession.is_online():
		# en ligne : le host lance la course de la partie, le client l'attend
		if NetSession.is_host():
			launch_online()
		elif not online_panel.visible:
			toggle_online()
		return
	MenuSound.play_confirm()
	GameState.requested_players = selected_players
	launch_requested.emit(selected_players)
	if auto_change_scene:
		get_tree().change_scene_to_file(race_scene())


func set_sound(on: bool) -> void:
	AudioServer.set_bus_mute(_master_bus(), not on)
	sound_button.set_pressed_no_signal(on)
	sound_button.text = "SON : ON" if on else "SON : OFF"
	if sound_check != null:
		sound_check.set_pressed_no_signal(on)
	if is_node_ready():
		MenuSound.play_toggle()


## Compteur d'images par seconde, garde dans GameState (menu et courses).
func set_show_fps(on: bool) -> void:
	GameState.show_fps = on
	if fps_check != null:
		fps_check.set_pressed_no_signal(on)


## Resolution dynamique, gardee dans GameState (DynamicResolution).
func set_dynamic_resolution(on: bool) -> void:
	GameState.dynamic_resolution = on
	if dynres_check != null:
		dynres_check.set_pressed_no_signal(on)


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


## Volume general (0 a 100 %), sur le bus Master.
func set_volume(percent: float) -> void:
	AudioServer.set_bus_volume_db(_master_bus(), linear_to_db(maxf(percent, 0.001) / 100.0))


func toggle_online() -> void:
	online_panel.visible = not online_panel.visible
	if is_node_ready():
		MenuSound.play_toggle()
	if online_panel.visible:
		_refresh_online()
		(launch_button if NetSession.is_host() else host_button).grab_focus()
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
	launch_button.disabled = NetSession.members.size() < 1
	leave_button.visible = online
	var status := ""
	if host:
		var ips := NetSessionNode.local_addresses()
		status = "Partie ouverte. Les autres joueurs tapent : %s  (port %d)" % [
			" ou ".join(ips) if not ips.is_empty() else "l'adresse IP de ce PC", NetSessionNode.DEFAULT_PORT]
		status += "\nCircuit et vitesse : ceux choisis dans le menu. LANCER quand tout le monde est là."
	elif NetSession.is_client():
		status = "Connecté, en attente du lancement par le host." if NetSession.local_slot() >= 0 \
				else "Connexion à %s..." % ip_edit.text
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
		lines.append("J%d  %s  (%s)%s%s" % [slot + 1, String(m["name"]), LocalRace.COLOR_NAMES[slot],
			"  · host" if int(m["peer"]) == 1 else "", "  · vous" if slot == NetSession.local_slot() else ""])
	lobby_label.text = "\n".join(lines) if not lines.is_empty() else "Personne pour l'instant."
	if online_button != null:
		online_button.text = ("EN LIGNE : %d JOUEUR%s" % [NetSession.members.size(),
			"S" if NetSession.members.size() > 1 else ""]) if online else "EN LIGNE / RÉSEAU LOCAL"


func toggle_settings() -> void:
	settings.visible = not settings.visible
	MenuSound.play_toggle()
	if settings.visible:
		(settings.find_child("Back", true, false) as Button).grab_focus()
	else:
		settings_button.grab_focus()


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
	_pads_label.modulate = Color(1.0, 0.72, 0.35) if warn else TEXT_DIM


# --- interface ------------------------------------------------------------------

## Charte du menu : un seul accent (orange) pour tout ce qui est choisi, des
## fonds sombres unis, du texte secondaire gris-bleu.
const ACCENT := Color(0.98, 0.55, 0.12)
const PANEL_BG := Color(0.03, 0.035, 0.065, 0.88)
const BUTTON_BG := Color(0.11, 0.13, 0.19, 1.0)
const TEXT_DIM := Color(0.66, 0.7, 0.79)
## Largeur du panneau de gauche (px, ecran de reference 1920 x 1080).
const SIDEBAR_W := 760


## Panneau de gauche, de haut en bas : titre, CIRCUIT, JOUEURS, VITESSE,
## COMMENCER et l'aide des commandes. Chaque section : un intitule, puis une
## rangee de boutons de meme largeur qui remplit le panneau (bords alignes).
## A droite, le decor : les camions sur le plateau tournant.
func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)

	var sidebar := PanelContainer.new()
	sidebar.name = "Sidebar"
	sidebar.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	sidebar.offset_right = SIDEBAR_W
	var sb := _box(PANEL_BG, Color(ACCENT, 0.55), 0, 0)
	sb.border_width_right = 2
	sb.content_margin_left = 64
	sb.content_margin_right = 56
	sb.content_margin_top = 56
	sb.content_margin_bottom = 40
	sidebar.add_theme_stylebox_override("panel", sb)
	root.add_child(sidebar)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 0)
	sidebar.add_child(column)

	# le titre s'anime (echelle) : hors conteneur, qui la remettrait a zero
	var title_box := Control.new()
	title_box.custom_minimum_size = Vector2(0, 100)
	column.add_child(title_box)
	title = _label("CRAZY WHEELS", 80, 10)
	title.name = "Title"
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.modulate = ACCENT
	title_box.add_child(title)
	var tagline := _label("COURSE DE CAMIONS ARCADE", 18, 0)
	tagline.modulate = TEXT_DIM
	column.add_child(tagline)
	var rule := ColorRect.new()
	rule.color = ACCENT
	rule.custom_minimum_size = Vector2(72, 4)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(_gap(16))
	column.add_child(rule)
	column.add_child(_gap(40))

	# circuit
	column.add_child(_section("Circuit"))
	var track_row := _row("Tracks")
	column.add_child(track_row)
	var track_group := ButtonGroup.new()
	for k in GameStateNode.TRACKS.size():
		var tb := _choice("Track%d" % k, String(GameStateNode.TRACKS[k]["name"]).to_upper(), track_group, 22)
		tb.pressed.connect(select_track.bind(k))
		track_row.add_child(tb)
		track_buttons.append(tb)
	subtitle = _label("", 16, 0)
	subtitle.modulate = TEXT_DIM
	column.add_child(_gap(10))
	column.add_child(subtitle)
	select_track(GameState.selected_track)
	column.add_child(_gap(30))

	# joueurs
	column.add_child(_section("Joueurs"))
	var row := _row("Players")
	column.add_child(row)
	var group := ButtonGroup.new()
	for i in LocalRace.MAX_PLAYERS:
		var b := _choice("Players%d" % (i + 1), str(i + 1), group, 26)
		b.tooltip_text = "%d joueur%s" % [i + 1, "s" if i > 0 else ""]
		b.pressed.connect(select_players.bind(i + 1))
		row.add_child(b)
		player_buttons.append(b)
	_pads_label = _label("", 16, 0)
	_pads_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_gap(10))
	column.add_child(_pads_label)
	column.add_child(_gap(30))

	# categorie de vitesse, facon cylindree
	column.add_child(_section("Vitesse"))
	var speed_row := _row("Speeds")
	column.add_child(speed_row)
	var speed_group := ButtonGroup.new()
	for k in GameStateNode.SPEED_CLASSES.size():
		var c: Dictionary = GameStateNode.SPEED_CLASSES[k]
		var sbtn := _choice("Speed%d" % k, "%s\n%s" % [c["cc"], String(c["name"]).to_upper()], speed_group, 17)
		sbtn.custom_minimum_size.y = 76
		# marges serrees : « ULTRASONIQUE » tient dans un quart de rangee, les
		# 4 boutons gardent la meme largeur
		for st: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			(sbtn.get_theme_stylebox(st) as StyleBoxFlat).content_margin_left = 6
			(sbtn.get_theme_stylebox(st) as StyleBoxFlat).content_margin_right = 6
		sbtn.tooltip_text = "%s : %d km/h" % [c["name"], int(c["top_kmh"])]
		sbtn.pressed.connect(select_speed.bind(k))
		speed_row.add_child(sbtn)
		speed_buttons.append(sbtn)
	select_speed(GameState.speed_class)

	# COMMENCER en bas du panneau, aide des commandes dessous
	var push := Control.new()
	push.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(push)
	# en ligne / reseau local : un PC heberge, les autres le rejoignent par IP
	online_button = Button.new()
	online_button.name = "Online"
	online_button.text = "EN LIGNE / RÉSEAU LOCAL"
	online_button.custom_minimum_size = Vector2(0, 58)
	_style_button(online_button, BUTTON_BG, ACCENT, 22)
	online_button.pressed.connect(toggle_online)
	column.add_child(online_button)
	column.add_child(_gap(14))
	start_button = Button.new()
	start_button.name = "Start"
	start_button.text = "COMMENCER"
	start_button.custom_minimum_size = Vector2(0, 84)
	_style_button(start_button, ACCENT, ACCENT, 36)
	start_button.add_theme_stylebox_override("hover", _box(ACCENT.lightened(0.12), Color(1, 1, 1, 0.5), 2))
	start_button.pressed.connect(start_race)
	column.add_child(start_button)
	column.add_child(_gap(22))
	for pair: Array in [
		["MANETTE", "Croix valider · Rond retour · L1 / R1 joueurs · Triangle circuit · Options jouer"],
		["CLAVIER", "Flèches · Entrée · 1 à 6 joueurs · T circuit · F11 plein écran · Échap quitter"],
	]:
		var help := HBoxContainer.new()
		help.add_theme_constant_override("separation", 0)
		var key := _label(pair[0], 13, 0)
		key.custom_minimum_size.x = 82
		help.add_child(key)
		var text := _label(pair[1], 15, 0)
		text.modulate = TEXT_DIM
		help.add_child(text)
		column.add_child(help)

	# coin haut droit : son et parametres, meme style sobre
	var corner := HBoxContainer.new()
	corner.name = "Corner"
	corner.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	corner.offset_top = 32
	corner.offset_right = -32
	corner.add_theme_constant_override("separation", 10)
	root.add_child(corner)
	sound_button = Button.new()
	sound_button.name = "Sound"
	sound_button.toggle_mode = true
	sound_button.custom_minimum_size = Vector2(150, 56)
	_style_button(sound_button, Color(PANEL_BG, 0.92), Color(PANEL_BG, 0.92), 18)
	sound_button.add_theme_color_override("font_color", TEXT_DIM)
	sound_button.toggled.connect(set_sound)
	corner.add_child(sound_button)
	settings_button = Button.new()
	settings_button.name = "Settings"
	settings_button.tooltip_text = "Paramètres"
	settings_button.custom_minimum_size = Vector2(56, 56)
	_style_button(settings_button, Color(PANEL_BG, 0.92), Color(PANEL_BG, 0.92), 18)
	settings_button.pressed.connect(toggle_settings)
	corner.add_child(settings_button)
	_gear = GearIcon.new()
	_gear.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_gear.offset_left = 11
	_gear.offset_top = 11
	_gear.offset_right = -11
	_gear.offset_bottom = -11
	settings_button.add_child(_gear)

	settings = _build_settings()
	root.add_child(settings)
	online_panel = _build_online()
	root.add_child(online_panel)


## Rangee d'une section : boutons de meme largeur, du bord gauche au bord droit.
func _row(row_name: String) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.name = row_name
	r.add_theme_constant_override("separation", 8)
	return r


## Bouton de choix (un seul enfonce par groupe), largeur partagee de la rangee.
func _choice(button_name: String, text: String, group: ButtonGroup, font_size: int) -> Button:
	var b := Button.new()
	b.name = button_name
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 58)
	_style_button(b, BUTTON_BG, ACCENT, font_size)
	return b


func _gap(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Ecran des parametres : schema de la manette (chaque commande legendee),
## touches du clavier, son (coupure et volume reels), reglages a venir, et
## RETOUR vers le menu. Couvre le menu : ses clics ne passent pas au travers.
func _build_settings() -> Control:
	var layer := Control.new()
	layer.name = "SettingsPanel"
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)                   # arrete aussi les clics vers le menu
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(1500, 0)
	panel.add_theme_stylebox_override("panel", _box(Color(0.05, 0.07, 0.11, 0.97), Color(0.95, 0.55, 0.1), 3))
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var head := _label("PARAMÈTRES", 40, 6)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	var sub := _label("Commandes — manette PlayStation 5 DualSense (disposition Forza Horizon)", 20, 0)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(0.8, 0.82, 0.88)
	box.add_child(sub)
	var diagram := ControllerDiagram.new()
	diagram.name = "ControllerDiagram"
	diagram.custom_minimum_size = Vector2(1260, 470)
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

	var back := Button.new()
	back.name = "Back"
	back.text = "RETOUR"
	back.custom_minimum_size = Vector2(260, 60)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_button(back, Color(0.07, 0.09, 0.15, 0.88), Color(0.95, 0.55, 0.1), 26)
	back.pressed.connect(toggle_settings)
	box.add_child(back)
	return layer


## Panneau EN LIGNE : pseudo, HÉBERGER (adresse a donner aux autres),
## REJOINDRE (adresse du host), joueurs de la partie, LANCER (host), QUITTER
## LA PARTIE, RETOUR. Meme habillage que les parametres.
func _build_online() -> Control:
	var layer := Control.new()
	layer.name = "OnlinePanel"
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(1100, 0)
	panel.add_theme_stylebox_override("panel", _box(Color(0.05, 0.07, 0.11, 0.97), ACCENT, 3))
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var head := _label("EN LIGNE  ·  RÉSEAU LOCAL", 40, 6)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)

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
	_style_button(host_button, BUTTON_BG, ACCENT, 22)
	host_button.pressed.connect(host_game)
	actions.add_child(host_button)
	ip_edit = LineEdit.new()
	ip_edit.name = "HostAddress"
	ip_edit.placeholder_text = "adresse IP du host, ex. 192.168.1.20"
	ip_edit.custom_minimum_size = Vector2(380, 60)
	ip_edit.add_theme_font_size_override("font_size", 20)
	ip_edit.text_submitted.connect(func(_t: String) -> void: join_game())
	actions.add_child(ip_edit)
	join_button = Button.new()
	join_button.name = "Join"
	join_button.text = "REJOINDRE"
	join_button.custom_minimum_size = Vector2(220, 60)
	_style_button(join_button, BUTTON_BG, ACCENT, 22)
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
	launch_button = Button.new()
	launch_button.name = "Launch"
	launch_button.text = "LANCER LA COURSE"
	launch_button.custom_minimum_size = Vector2(340, 64)
	_style_button(launch_button, ACCENT, ACCENT, 26)
	launch_button.pressed.connect(launch_online)
	bottom.add_child(launch_button)
	leave_button = Button.new()
	leave_button.name = "Leave"
	leave_button.text = "QUITTER LA PARTIE"
	leave_button.custom_minimum_size = Vector2(300, 64)
	_style_button(leave_button, BUTTON_BG, ACCENT, 22)
	leave_button.pressed.connect(leave_game)
	bottom.add_child(leave_button)
	var back := Button.new()
	back.name = "Back"
	back.text = "RETOUR"
	back.custom_minimum_size = Vector2(220, 64)
	_style_button(back, Color(0.07, 0.09, 0.15, 0.88), ACCENT, 22)
	back.pressed.connect(toggle_online)
	bottom.add_child(back)
	return layer


func _section(text: String) -> Label:
	var l := _label(text.to_upper(), 17, 0)
	l.modulate = ACCENT
	l.custom_minimum_size.y = 34
	return l


func _label(text: String, size: int, outline: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	if outline > 0:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override("outline_size", outline)
	return l


static func _box(fill: Color, border: Color, border_width: int, radius: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(18)
	return sb


## Fond uni, enfonce = couleur du bouton, survol = un cran plus clair, focus
## (manette, clavier) = liseré blanc.
func _style_button(b: Button, normal: Color, pressed: Color, font_size: int) -> void:
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_stylebox_override("normal", _box(normal, Color(1, 1, 1, 0.08), 1))
	b.add_theme_stylebox_override("hover", _box(normal.lightened(0.1), Color(1, 1, 1, 0.25), 1))
	b.add_theme_stylebox_override("pressed", _box(pressed, Color(1, 1, 1, 0.0), 1))
	b.add_theme_stylebox_override("hover_pressed", _box(pressed.lightened(0.08), Color(1, 1, 1, 0.3), 1))
	var focus := _box(Color(0, 0, 0, 0), Color(1, 1, 1, 0.95), 3)
	focus.draw_center = false
	b.add_theme_stylebox_override("focus", focus)
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, Color.WHITE)
