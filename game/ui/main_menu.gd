class_name MainMenu
extends Node3D

## Ecran d'accueil (tache 4.2, partiel) : titre anime, choix du nombre de
## joueurs (1 a 4), START / COMMENCER, son on / off, parametres. Decor dedie
## (Showroom) : les camions des joueurs choisis exposes sur un plateau tournant,
## sur le toit d'une tour de Cyber City, sous les projecteurs ; camera en orbite
## lente, decalee pour montrer les camions a droite, le menu a gauche.
##
## Manette (PlayStation, positions SDL) : croix directionnelle ou stick pour
## naviguer, Croix pour valider, Rond ou Create pour fermer les parametres,
## L1 / R1 pour changer le nombre de joueurs, Options pour commencer.
## Clavier et souris : fleches + Entree, touches 1 a 4, clic ; Echap ferme les
## parametres, sinon quitte le jeu.
##
## COMMENCER ecrit le choix dans GameState.requested_players puis charge
## dev/race.tscn (LocalRace le lit). Le menu ne touche pas a la physique : les
## camions de decor sont geles.

signal launch_requested(players: int)

const RACE_SCENE := "res://dev/race.tscn"
const LocalRace := preload("res://dev/local_race.gd")

## Faux pour les tests : COMMENCER emet `launch_requested` sans changer de scene.
@export var auto_change_scene: bool = true
@export var orbit_speed: float = 0.06        # rad/s
@export var orbit_radius: float = 46.0
@export var orbit_height: float = 9.0
## Decalage lateral de l'image (m) : les camions a droite, le menu a gauche.
@export var frame_offset: float = -20.0

@onready var showroom: Showroom = $Showroom
@onready var camera: Camera3D = $OrbitCamera

var selected_players: int = 1
var trucks: Array[Truck] = []
var player_buttons: Array[Button] = []
var speed_buttons: Array[Button] = []
var title: Label
var start_button: Button
var sound_button: Button
var settings_button: Button
var settings: Control
## Ecran des parametres : case du son (miroir du bouton du menu), volume.
var sound_check: CheckButton
var volume_slider: HSlider
var _gear: GearIcon
var _pads_label: Label
var _orbit_center: Vector3
var _orbit_angle: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	DebugDraw.enabled = false
	_setup_menu_input()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.current = true
	_spawn_trucks()
	_build_ui()
	set_sound(not AudioServer.is_bus_mute(_master_bus()))
	# on retrouve le dernier choix en revenant d'une course
	select_players(GameState.requested_players if GameState.requested_players > 0 else 1)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	start_button.grab_focus()
	_place_camera()



## Les 4 camions sur le plateau tournant, geles : du decor, pas de physique.
func _spawn_trucks() -> void:
	for i in 4:
		var t := (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
		t.name = "Truck%d" % (i + 1)
		var visual := t.get_node("Visual") as TruckVisual
		visual.external_model = LocalRace.MODELS[i]
		visual.mock_tint = LocalRace.TINTS[i]
		t.transform = Showroom.slot(i, 4)
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
	# titre arcade : pulsation, balancement, couleur chaude qui varie
	title.pivot_offset = title.size / 2.0
	var s := 1.0 + 0.045 * sin(_time * 3.2)
	title.scale = Vector2(s, s)
	title.rotation = deg_to_rad(1.8) * sin(_time * 1.4)
	title.modulate = Color.from_hsv(0.09 + 0.05 * sin(_time * 0.9), 0.85, 1.0)
	start_button.modulate = Color(1, 1, 1).lerp(Color(1.25, 1.2, 1.0), 0.5 + 0.5 * sin(_time * 5.0)) \
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
			KEY_1, KEY_2, KEY_3, KEY_4:
				select_players(key.physical_keycode - KEY_0)
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
			JOY_BUTTON_START:
				if not settings.visible:
					start_race()
			JOY_BUTTON_BACK:
				if settings.visible:
					toggle_settings()
			_:
				return
		get_viewport().set_input_as_handled()


## Categorie de vitesse (0 = Lent .. 3 = Ultrasonique), gardee dans GameState
## pour la course et les suivantes.
func select_speed(k: int) -> void:
	GameState.speed_class = clampi(k, 0, GameStateNode.SPEED_CLASSES.size() - 1)
	for i in speed_buttons.size():
		speed_buttons[i].set_pressed_no_signal(i == GameState.speed_class)


## Nombre de joueurs (borne a 1..4) : bouton enfonce, camions montres.
func select_players(n: int) -> void:
	var prev := selected_players
	selected_players = clampi(n, 1, 4)
	if is_node_ready() and selected_players != prev:
		MenuSound.play_select()
	for i in player_buttons.size():
		player_buttons[i].set_pressed_no_signal(i == selected_players - 1)
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
		get_tree().change_scene_to_file(RACE_SCENE)


func set_sound(on: bool) -> void:
	AudioServer.set_bus_mute(_master_bus(), not on)
	sound_button.set_pressed_no_signal(on)
	sound_button.text = "SON : ON" if on else "SON : OFF"
	if sound_check != null:
		sound_check.set_pressed_no_signal(on)
	if is_node_ready():
		MenuSound.play_toggle()


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
	var text := "Manettes détectées : %d" % pads
	var warn := selected_players > 2 and pads < selected_players
	if warn:
		text += "   -   il en faut %d pour %d joueurs (J1 et J2 peuvent jouer au clavier)" \
				% [selected_players, selected_players]
	elif selected_players > 1:
		text += "   -   joueur N = manette N  (clavier : J1 fleches, J2 ZQSD)"
	_pads_label.text = text
	_pads_label.modulate = Color(1.0, 0.7, 0.3) if warn else Color(0.9, 0.9, 0.9)


# --- interface ------------------------------------------------------------------

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)

	# colonne centrale : titre, sous-titre, joueurs, manettes, COMMENCER
	var column := VBoxContainer.new()
	column.name = "Column"
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	column.offset_left = 70
	column.grow_horizontal = Control.GROW_DIRECTION_END
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 22)
	root.add_child(column)

	# le titre s'anime (echelle, rotation) : hors conteneur, qui les remettrait a zero
	var title_box := Control.new()
	title_box.custom_minimum_size = Vector2(980, 140)
	column.add_child(title_box)
	title = _label("CRAZY WHEELS", 96, 14)
	title.name = "Title"
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_box.add_child(title)
	var subtitle := _label("CYBER CITY   ·   PISTE DE 75 M   ·   3 TOURS   ·   1 À 4 JOUEURS", 26, 6)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(1.0, 0.95, 0.8)
	# carte translucide : lisible devant les camions du decor
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.add_theme_stylebox_override("panel", _box(Color(0.02, 0.03, 0.06, 0.55), Color(1, 1, 1, 0.12), 1))
	column.add_child(card)
	var card_box := VBoxContainer.new()
	card_box.add_theme_constant_override("separation", 16)
	card.add_child(card_box)
	card_box.add_child(subtitle)

	var row := HBoxContainer.new()
	row.name = "Players"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	card_box.add_child(row)
	var group := ButtonGroup.new()
	for i in 4:
		var b := Button.new()
		b.name = "Players%d" % (i + 1)
		b.text = "%d JOUEUR%s" % [i + 1, "S" if i > 0 else ""]
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(200, 72)
		_style_button(b, Color(0.07, 0.09, 0.15, 0.88), Color(0.95, 0.55, 0.1), 26)
		b.pressed.connect(select_players.bind(i + 1))
		row.add_child(b)
		player_buttons.append(b)

	# categorie de vitesse, facon cylindree
	var speed_row := HBoxContainer.new()
	speed_row.name = "Speeds"
	speed_row.alignment = BoxContainer.ALIGNMENT_CENTER
	speed_row.add_theme_constant_override("separation", 12)
	card_box.add_child(speed_row)
	var speed_group := ButtonGroup.new()
	for k in GameStateNode.SPEED_CLASSES.size():
		var c: Dictionary = GameStateNode.SPEED_CLASSES[k]
		var sbtn := Button.new()
		sbtn.name = "Speed%d" % k
		sbtn.text = "%s · %s" % [String(c["name"]).to_upper(), c["cc"]]
		sbtn.toggle_mode = true
		sbtn.button_group = speed_group
		sbtn.custom_minimum_size = Vector2(0, 52)
		_style_button(sbtn, Color(0.07, 0.09, 0.15, 0.88), Color(0.1, 0.6, 0.95), 18)
		sbtn.pressed.connect(select_speed.bind(k))
		speed_row.add_child(sbtn)
		speed_buttons.append(sbtn)
	select_speed(GameState.speed_class)

	_pads_label = _label("", 20, 4)
	_pads_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_box.add_child(_pads_label)

	start_button = Button.new()
	start_button.name = "Start"
	start_button.text = "START / COMMENCER"
	start_button.custom_minimum_size = Vector2(480, 96)
	start_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_button(start_button, Color(0.85, 0.16, 0.08, 0.95), Color(1.0, 0.3, 0.15), 42)
	start_button.pressed.connect(start_race)
	column.add_child(start_button)

	# coin haut droit : son et parametres
	var corner := HBoxContainer.new()
	corner.name = "Corner"
	corner.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	corner.offset_top = 24
	corner.offset_right = -24
	corner.add_theme_constant_override("separation", 12)
	root.add_child(corner)
	sound_button = Button.new()
	sound_button.name = "Sound"
	sound_button.toggle_mode = true
	sound_button.custom_minimum_size = Vector2(180, 64)
	_style_button(sound_button, Color(0.07, 0.09, 0.15, 0.88), Color(0.15, 0.55, 0.3, 0.95), 24)
	sound_button.toggled.connect(set_sound)
	corner.add_child(sound_button)
	settings_button = Button.new()
	settings_button.name = "Settings"
	settings_button.tooltip_text = "Parametres"
	settings_button.custom_minimum_size = Vector2(64, 64)
	_style_button(settings_button, Color(0.07, 0.09, 0.15, 0.88), Color(0.07, 0.09, 0.15, 0.88), 24)
	settings_button.pressed.connect(toggle_settings)
	corner.add_child(settings_button)
	_gear = GearIcon.new()
	_gear.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_gear.offset_left = 10
	_gear.offset_top = 10
	_gear.offset_right = -10
	_gear.offset_bottom = -10
	settings_button.add_child(_gear)

	var help := _label("Manette : croix directionnelle pour choisir, Croix valider, Rond retour, L1 / R1 joueurs, Options commencer"
			+ "      Clavier : fleches, Entree, 1 a 4, Echap pour quitter", 18, 4)
	help.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	help.grow_horizontal = Control.GROW_DIRECTION_BOTH
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	help.offset_bottom = -20
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(help)

	settings = _build_settings()
	root.add_child(settings)


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
		"Seul : les deux jeux de touches · Échap : menu · Entrée : rejouer",
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
	var quality := OptionButton.new()
	for q: String in ["Qualité graphique : haute", "Qualité graphique : moyenne", "Qualité graphique : basse"]:
		quality.add_item(q)
	quality.add_theme_font_size_override("font_size", 19)
	opts.add_child(quality)

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
	var l := _label(text.to_upper(), 20, 0)
	l.modulate = Color(1.0, 0.62, 0.12)
	return l


func _label(text: String, size: int, outline: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	if outline > 0:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override("outline_size", outline)
	return l


static func _box(fill: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(18)
	return sb


## Style arcade : fond sombre, enfonce = couleur du bouton, focus = liseré jaune.
func _style_button(b: Button, normal: Color, pressed: Color, font_size: int) -> void:
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_stylebox_override("normal", _box(normal, Color(1, 1, 1, 0.25), 2))
	b.add_theme_stylebox_override("hover", _box(normal.lightened(0.18), Color(1, 1, 1, 0.5), 2))
	b.add_theme_stylebox_override("pressed", _box(pressed, Color(1, 1, 1, 0.7), 2))
	b.add_theme_stylebox_override("hover_pressed", _box(pressed.lightened(0.12), Color(1, 1, 1, 0.8), 2))
	var focus := _box(Color(0, 0, 0, 0), Color(1.0, 0.9, 0.2), 5)
	focus.draw_center = false
	b.add_theme_stylebox_override("focus", focus)
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, Color.WHITE)
