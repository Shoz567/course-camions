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
	start_button.grab_focus()
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
		subtitle.text = "%s  ·  3 tours" % (tag.left(1).to_upper() + tag.substr(1))


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

	var back := Button.new()
	back.name = "Back"
	back.text = "RETOUR"
	back.custom_minimum_size = Vector2(260, 60)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_button(back, Color(0.07, 0.09, 0.15, 0.88), Color(0.95, 0.55, 0.1), 26)
	back.pressed.connect(toggle_settings)
	box.add_child(back)
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
