class_name MainMenu
extends Node3D

## Ecran d'accueil (tache 4.2, partiel) : titre anime, choix du nombre de
## joueurs (1 a 4), START / COMMENCER, son on / off, parametres (factices pour
## l'instant). En arriere-plan : la piste n°1, les camions des joueurs choisis
## sur la grille, et une camera en orbite lente autour d'eux.
##
## Manette : croix ou stick pour naviguer, A (ou B) pour valider, L / R pour
## changer le nombre de joueurs, + (Start) pour commencer, - pour fermer les
## parametres. Clavier et souris : fleches + Entree, touches 1 a 4, clic ;
## Echap ferme les parametres, sinon quitte le jeu.
##
## COMMENCER ecrit le choix dans GameState.requested_players puis charge
## dev/race.tscn (LocalRace le lit). Le menu ne touche pas a la physique : les
## camions de decor sont geles.

signal launch_requested(players: int)

const RACE_SCENE := "res://dev/race.tscn"
const LocalRace := preload("res://dev/local_race.gd")

## Faux pour les tests : COMMENCER emet `launch_requested` sans changer de scene.
@export var auto_change_scene: bool = true
@export var orbit_speed: float = 0.12        # rad/s
@export var orbit_radius: float = 44.0
@export var orbit_height: float = 11.0

@onready var track: TrackBlockout = $Track01
@onready var camera: Camera3D = $OrbitCamera

var selected_players: int = 1
var trucks: Array[Truck] = []
var player_buttons: Array[Button] = []
var title: Label
var start_button: Button
var sound_button: Button
var settings_button: Button
var settings: Control
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


## Manette Switch (positions SDL) : A est le bouton EST (JOY_BUTTON_B), que
## Godot range dans ui_cancel. Au menu, A et B valident tous les deux.
static func _setup_menu_input() -> void:
	var accept := InputEventJoypadButton.new()
	accept.device = -1
	accept.button_index = JOY_BUTTON_B
	if not InputMap.action_has_event("ui_accept", accept):
		InputMap.action_add_event("ui_accept", accept)
	for e: InputEvent in InputMap.action_get_events("ui_cancel"):
		var jb := e as InputEventJoypadButton
		if jb != null and jb.button_index == JOY_BUTTON_B:
			InputMap.action_erase_event("ui_cancel", e)


## Les 4 camions sur la grille, geles : du decor, pas de physique.
func _spawn_trucks() -> void:
	var center := Vector3.ZERO
	for i in 4:
		var t := (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
		t.name = "Truck%d" % (i + 1)
		var visual := t.get_node("Visual") as TruckVisual
		visual.external_model = LocalRace.MODELS[i]
		visual.mock_tint = LocalRace.TINTS[i]
		t.transform = track.get_start_transform(i)
		t.freeze = true
		add_child(t)
		trucks.append(t)
		center += t.global_position
	# centre de l'orbite : milieu de la grille, recule vers les remorques
	_orbit_center = center / 4.0 + trucks[0].global_basis.z * 5.0 + Vector3.UP * 2.0


func _process(delta: float) -> void:
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


## Nombre de joueurs (borne a 1..4) : bouton enfonce, camions montres.
func select_players(n: int) -> void:
	selected_players = clampi(n, 1, 4)
	for i in player_buttons.size():
		player_buttons[i].set_pressed_no_signal(i == selected_players - 1)
	for i in trucks.size():
		trucks[i].visible = i < selected_players
	_update_pads_label()


func start_race() -> void:
	GameState.requested_players = selected_players
	launch_requested.emit(selected_players)
	if auto_change_scene:
		get_tree().change_scene_to_file(RACE_SCENE)


func set_sound(on: bool) -> void:
	AudioServer.set_bus_mute(_master_bus(), not on)
	sound_button.set_pressed_no_signal(on)
	sound_button.text = "SON : ON" if on else "SON : OFF"


func toggle_settings() -> void:
	settings.visible = not settings.visible
	if settings.visible:
		(settings.find_child("Close", true, false) as Button).grab_focus()
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
	var text := "Manettes detectees : %d" % pads
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
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 22)
	root.add_child(column)

	# le titre s'anime (echelle, rotation) : hors conteneur, qui les remettrait a zero
	var title_box := Control.new()
	title_box.custom_minimum_size = Vector2(1200, 150)
	column.add_child(title_box)
	title = _label("COURSE DE CAMIONS", 112, 16)
	title.name = "Title"
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_box.add_child(title)
	var subtitle := _label("ARCADE   -   PISTE MEGA-LARGE 50 M   -   3 TOURS   -   1 A 4 JOUEURS", 26, 6)
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

	var help := _label("Manette : croix pour choisir, A pour valider, L / R nombre de joueurs, + commencer"
			+ "      Clavier : fleches, Entree, 1 a 4, Echap pour quitter", 18, 4)
	help.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	help.grow_horizontal = Control.GROW_DIRECTION_BOTH
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	help.offset_bottom = -20
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(help)

	settings = _build_settings()
	root.add_child(settings)


## Panneau de parametres : factice pour l'instant (rien n'est branche).
func _build_settings() -> Control:
	var layer := Control.new()
	layer.name = "SettingsPanel"
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)                   # arrete aussi les clics vers le menu
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(560, 0)
	panel.add_theme_stylebox_override("panel", _box(Color(0.06, 0.08, 0.13, 0.97), Color(0.95, 0.55, 0.1), 3))
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	var head := _label("PARAMETRES", 38, 6)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	var music := HBoxContainer.new()
	music.add_child(_label("Volume musique", 22, 0))
	var slider := HSlider.new()
	slider.value = 80
	slider.custom_minimum_size = Vector2(240, 0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	music.add_child(slider)
	box.add_child(music)
	var rumble := CheckButton.new()
	rumble.text = "Vibrations manette"
	rumble.button_pressed = true
	rumble.add_theme_font_size_override("font_size", 22)
	box.add_child(rumble)
	var quality := OptionButton.new()
	for q: String in ["Qualite graphique : haute", "Qualite graphique : moyenne", "Qualite graphique : basse"]:
		quality.add_item(q)
	quality.add_theme_font_size_override("font_size", 22)
	box.add_child(quality)
	var note := _label("Reglages factices : bientot branches.", 16, 0)
	note.modulate = Color(0.7, 0.7, 0.75)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(note)
	var close := Button.new()
	close.name = "Close"
	close.text = "FERMER"
	close.custom_minimum_size = Vector2(220, 56)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_button(close, Color(0.07, 0.09, 0.15, 0.88), Color(0.95, 0.55, 0.1), 24)
	close.pressed.connect(toggle_settings)
	box.add_child(close)
	return layer


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
