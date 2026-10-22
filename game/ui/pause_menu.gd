class_name PauseMenu
extends CanvasLayer

## Menu de la course (2026-10-22 : « quand on appuie sur la touche option pour
## la manette et echappe pour clavier souris, ca ne quitte pas la course
## directement, mais ca ouvre un menu et ca met le jeu en pause. Et quand c'est
## en multijoueur [...] ca met pas le jeu en pause ») :
##   - hors ligne, la course se fige (SceneTree.paused) ; en ligne, elle
##     continue pour tous, et le camion de ce PC roule a vide (LocalRace lui
##     donne une frame neutre tant que le menu est ouvert) ;
##   - REPRENDRE, PARAMETRES (SettingsPanel : touches, reaffectation, son,
##     image), puis la sortie, confirmee : QUITTER LA COURSE hors ligne,
##     QUITTER LA PARTIE pour un client, ARRETER LA COURSE pour le host (chacun
##     revient au salon, NetSession.stop_race).
## Options / Echap / Rond referment le menu ; Options le referme meme depuis
## les parametres. LocalRace l'ouvre (open) et fait la sortie (quit_confirmed).

signal quit_confirmed
## Qualite changee dans les parametres : la course reapplique ses effets.
signal quality_changed(quality: int)

enum Exit { LOCAL, CLIENT, HOST }

## Page du menu, et ses boutons.
var page: Control
var resume_button: Button
var settings_button: Button
var quit_button: Button
## Confirmation de la sortie (ANNULER par defaut).
var confirm: Control
var confirm_button: Button
var cancel_button: Button
var settings: SettingsPanel
## Sortie proposee, fixee a l'ouverture (la partie en ligne a pu se fermer).
var exit_kind: Exit = Exit.LOCAL
var _confirm_text: Label
var _title: Label
var _summary: Label


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	# Croix valide, Rond revient (le menu principal le fait aussi, mais une
	# course peut etre lancee sans lui)
	MainMenu._setup_menu_input()
	_build()


## Sortie proposee selon la session : hors ligne, client, host.
static func exit_for_session() -> Exit:
	if NetSession.is_host():
		return Exit.HOST
	if NetSession.is_client():
		return Exit.CLIENT
	return Exit.LOCAL


static func exit_label(kind: Exit) -> String:
	match kind:
		Exit.HOST:
			return "ARRÊTER LA COURSE"
		Exit.CLIENT:
			return "QUITTER LA PARTIE"
	return "QUITTER LA COURSE"


static func exit_question(kind: Exit) -> String:
	match kind:
		Exit.HOST:
			return "Arrêter la course pour tout le monde ?\nChacun revient au salon, la partie reste ouverte."
		Exit.CLIENT:
			return "Quitter la partie ?\nTu reviens au menu, les autres continuent sans toi."
	return "Quitter la course ?\nRetour au menu principal, la course en cours est perdue."


## Ouvre le menu ; hors ligne, la course se fige.
func open() -> void:
	if visible:
		return
	exit_kind = exit_for_session()
	var online := exit_kind != Exit.LOCAL
	_title.text = "MENU" if online else "PAUSE"
	_summary.text = "LA COURSE CONTINUE" if online else "COURSE EN PAUSE"
	quit_button.text = exit_label(exit_kind)
	confirm_button.text = exit_label(exit_kind)
	_confirm_text.text = exit_question(exit_kind)
	visible = true
	page.visible = true
	confirm.visible = false
	if not online:
		get_tree().paused = true
	MenuSound.play_toggle()
	resume_button.grab_focus()


## Referme tout (parametres compris) ; la course repart.
func close() -> void:
	if not visible:
		return
	visible = false
	confirm.visible = false
	if settings.visible:
		settings.close()
	get_tree().paused = false
	MenuSound.play_toggle()


## Ticks figes : l'horloge de jeu (GameClock) les retire, la course reprend
## la ou elle s'etait arretee (compte a rebours, chrono, recharges).
func _physics_process(_delta: float) -> void:
	if get_tree().paused:
		GameClock.paused_ticks += 1


func open_settings() -> void:
	page.visible = false
	MenuSound.play_toggle()
	settings.open()


func _on_settings_closed() -> void:
	if not visible:
		return
	page.visible = true
	settings_button.grab_focus()


## Demande confirmation de la sortie.
func ask_quit() -> void:
	confirm.visible = true
	cancel_button.grab_focus()
	MenuSound.play_select()


func cancel_quit() -> void:
	confirm.visible = false
	quit_button.grab_focus()
	MenuSound.play_toggle()


## Sortie confirmee : le menu se ferme (la pause tombe : le menu principal ne
## doit pas naitre fige), LocalRace fait le reste.
func confirm_quit() -> void:
	visible = false
	confirm.visible = false
	get_tree().paused = false
	MenuSound.play_confirm()
	quit_confirmed.emit()


## Avant la course : Options / Echap / Rond referment (les parametres
## gerent eux-memes Rond / Echap, Options ferme tout), la confirmation
## s'annule ; la course ne recoit aucune de ces touches.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	var pad := event as InputEventJoypadButton
	var esc := key != null and key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE
	var options := pad != null and pad.pressed and pad.button_index == JOY_BUTTON_START
	var circle := pad != null and pad.pressed and pad.button_index == JOY_BUTTON_B
	if settings.visible:
		if options:
			close()
			get_viewport().set_input_as_handled()
		return
	if confirm.visible:
		if esc or circle:
			cancel_quit()
			get_viewport().set_input_as_handled()
		elif options:
			close()
			get_viewport().set_input_as_handled()
		return
	if esc or options or circle:
		close()
		get_viewport().set_input_as_handled()


# --- construction -------------------------------------------------------------

func _build() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	page = UiKit.page("PausePage", "PAUSE", "COURSE EN PAUSE",
		[["cross", "Valider"], ["circle", "Reprendre"], ["key:Échap", "Reprendre"]])
	page.visible = true
	_title = page.get_node(^"Title") as Label
	_summary = page.get_node(^"Summary") as Label
	root.add_child(page)
	var card := UiKit.card(UiKit.CYAN, 620.0)
	UiKit.page_content(page).add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	card.add_child(col)
	resume_button = _button(col, "Resume", "REPRENDRE", true)
	resume_button.pressed.connect(close)
	settings_button = _button(col, "Settings", "PARAMÈTRES", false)
	settings_button.pressed.connect(open_settings)
	quit_button = _button(col, "Quit", "QUITTER LA COURSE", false)
	quit_button.pressed.connect(ask_quit)

	settings = SettingsPanel.new()
	settings.name = "SettingsPanel"
	root.add_child(settings)
	settings.closed.connect(_on_settings_closed)
	settings.quality_changed.connect(func(q: int) -> void: quality_changed.emit(q))

	confirm = _build_confirm()
	root.add_child(confirm)


func _button(box: Container, button_name: String, text: String, primary: bool) -> Button:
	var b := Button.new()
	b.name = button_name
	b.text = text
	b.custom_minimum_size = Vector2(0, 72)
	if primary:
		UiKit.style_primary(b, 28)
	else:
		UiKit.style_choice(b, 26)
	box.add_child(b)
	return b


## Carte de confirmation, par-dessus le menu : question, ANNULER / sortie.
func _build_confirm() -> Control:
	var layer_node := Control.new()
	layer_node.name = "Confirm"
	layer_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer_node.mouse_filter = Control.MOUSE_FILTER_STOP
	layer_node.visible = false
	var dim := ColorRect.new()
	dim.color = Color(UiKit.NIGHT, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer_node.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer_node.add_child(center)
	var card := UiKit.card(UiKit.GOLD, 760.0)
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 22)
	card.add_child(col)
	_confirm_text = UiKit.label("", 26, UiKit.TEXT, 800, false)
	_confirm_text.name = "Question"
	_confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_text.custom_minimum_size = Vector2(700, 0)
	col.add_child(_confirm_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(row)
	cancel_button = Button.new()
	cancel_button.name = "Cancel"
	cancel_button.text = "ANNULER"
	cancel_button.custom_minimum_size = Vector2(220, 60)
	UiKit.style_choice(cancel_button, 22)
	cancel_button.pressed.connect(cancel_quit)
	row.add_child(cancel_button)
	confirm_button = Button.new()
	confirm_button.name = "Accept"
	confirm_button.custom_minimum_size = Vector2(300, 60)
	UiKit.style_primary(confirm_button, 22)
	confirm_button.pressed.connect(confirm_quit)
	row.add_child(confirm_button)
	cancel_button.focus_neighbor_right = cancel_button.get_path_to(confirm_button)
	confirm_button.focus_neighbor_left = confirm_button.get_path_to(cancel_button)
	return layer_node
