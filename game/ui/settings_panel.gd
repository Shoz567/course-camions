class_name SettingsPanel
extends Control

## Parametres du jeu (sortis du menu principal le 2026-10-22, pour le menu
## pause de la course : « un onglet reglage [...] comme dans le menu
## principal, assigner des touches, voir les touches, regler le son ») :
##   - page PARAMETRES : schema de la DualSense (chaque commande legendee),
##     touches du clavier, son (coupure, jauges generale, musique,
##     bruitages), qualite graphique (l'extreme demande confirmation),
##     compteur FPS, resolution dynamique, REAFFECTER LA MANETTE, RETOUR ;
##   - page REAFFECTER : une ligne par action, la pression suivante d'une
##     manette devient son bouton (PadBindings) ;
##   - avertissement de la qualite extreme, par-dessus.
## Tout est garde dans GameState (save_settings). open() l'affiche, Rond /
## Echap reviennent d'un cran (attente d'un bouton, reaffectation,
## avertissement, puis la fermeture : signal closed). Le menu principal et le
## menu pause l'embarquent ; il ne connait pas le decor : quality_changed et
## sound_changed laissent son hote suivre.

signal closed
signal sound_changed(on: bool)
signal quality_changed(quality: int)

## Page PARAMETRES (le bouton RETOUR s'y appelle « Back »).
var page: Control
var sound_check: CheckButton
var volume_slider: HSlider
## Jauges Musique et Bruitages (2026-10-22), sous le volume general.
var music_slider: HSlider
var effects_slider: HSlider
var quality_option: OptionButton
## Compteur d'images par seconde (GameState.show_fps).
var fps_check: CheckButton
## Resolution dynamique de la 3D (GameState.dynamic_resolution).
var dynres_check: CheckButton
## Reaffectation de la manette (tache 7.1) : page, bouton de chaque action,
## action qui attend son bouton ("" : aucune).
var remap_panel: Control
var _remap_buttons: Dictionary = {}
var remap_waiting: String = ""
## Avertissement avant la qualite extreme, et ses deux boutons.
var extreme_warning: Control
var _warn_yes: Button
var _warn_no: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	page = _build_settings()
	page.visible = true
	add_child(page)
	remap_panel = _build_remap()
	add_child(remap_panel)
	extreme_warning = _build_extreme_warning()
	add_child(extreme_warning)
	visible = false


## Affiche la page des parametres, focus sur RETOUR.
func open() -> void:
	visible = true
	page.visible = true
	remap_panel.visible = false
	extreme_warning.visible = false
	remap_waiting = ""
	(page.find_child("Back", true, false) as Button).grab_focus()


## Ferme les parametres (signal closed).
func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


## Avant le reste du jeu : avertissement (Rond / Echap l'annulent),
## reaffectation, puis Rond / Echap ferment la page.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	var pad := event as InputEventJoypadButton
	var back := (key != null and key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE) \
			or (pad != null and pad.pressed and pad.button_index == JOY_BUTTON_B)
	if extreme_warning.visible:
		if back:
			close_extreme_warning(false)
			get_viewport().set_input_as_handled()
		return
	if remap_panel.visible:
		_remap_input(event)
		return
	if back:
		MenuSound.play_toggle()
		close()
		get_viewport().set_input_as_handled()


static func _master_bus() -> int:
	return AudioServer.get_bus_index("Master")


# --- son et image ---------------------------------------------------------------

## Son coupe ou non (bus Master), garde dans les reglages.
func set_sound(on: bool) -> void:
	AudioServer.set_bus_mute(_master_bus(), not on)
	if sound_check != null:
		sound_check.set_pressed_no_signal(on)
	if is_node_ready():
		MenuSound.play_toggle()
		GameState.save_settings()
	sound_changed.emit(on)


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


## Avertissement de la qualite extreme : par-dessus les parametres.
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


## Qualite graphique (GraphicsSettings.Quality), gardee dans GameState ; la
## vue principale la prend tout de suite, l'hote le reste (quality_changed :
## decor du menu, effets de la course).
func set_quality(q: int) -> void:
	GameState.graphics_quality = clampi(q, 0, GraphicsSettings.NAMES.size() - 1)
	if quality_option != null:
		quality_option.select(quality_option.get_item_index(GameState.graphics_quality))
	GraphicsSettings.apply_viewport(get_viewport(), GameState.graphics_quality)
	if is_node_ready():
		GameState.save_settings()
	quality_changed.emit(GameState.graphics_quality)


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


# --- reaffectation de la manette (tache 7.1) ------------------------------------

## Ouvre ou ferme la reaffectation ; la page des parametres se cache dessous.
func toggle_remap() -> void:
	remap_panel.visible = not remap_panel.visible
	page.visible = not remap_panel.visible
	remap_waiting = ""
	if is_node_ready():
		MenuSound.play_toggle()
	if remap_panel.visible:
		_refresh_remap()
		(_remap_buttons[PadBindings.ACTIONS[0]] as Button).grab_focus()
	else:
		(page.find_child("Remap", true, false) as Button).grab_focus()


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
## (boutons reserves refuses), Echap annule ; rien d'autre n'atteint le jeu.
## Sinon, Rond ou Echap ferment la page.
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


# --- construction -------------------------------------------------------------

## Page des parametres : schema de la manette (chaque commande legendee),
## touches du clavier, son et reglages, REAFFECTER et RETOUR. Couvre ce qui est
## derriere : ses clics ne passent pas au travers.
func _build_settings() -> Control:
	var layer := UiKit.page("SettingsPage", "PARAMÈTRES", "COMMANDES  ·  SON  ·  IMAGE",
		[["cross", "Valider"], ["circle", "Retour"], ["key:Échap", "Retour"], ["key:F11", "Plein écran"]])
	var panel := UiKit.card(UiKit.CYAN, 1720)
	(panel.get_theme_stylebox("panel") as StyleBoxFlat).set_content_margin_all(18)
	UiKit.page_content(layer).add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var sub := _label("Commandes par défaut — manette PlayStation 5 DualSense (disposition Forza Horizon), réaffectables plus bas", 20)
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
	keys.add_child(UiKit.section("Clavier"))
	for line: String in [
		"J1 — flèches · Ctrl droit drift · Maj droite boost · ; cargo · ! klaxon · : vue · Fin regarder derrière · K / L pouvoirs · J cible · Retour arrière reset",
		"J2 — Z Q S D · Espace drift · Maj gauche boost · E cargo · H klaxon · C vue · B regarder derrière · F / G pouvoirs · T cible · R reset",
		"Seul : les deux jeux de touches · Échap : menu pause · Entrée : rejouer · F11 : plein écran / fenêtre",
	]:
		var l := _label(line, 17)
		l.modulate = Color(0.9, 0.9, 0.94)
		keys.add_child(l)
	var opts := VBoxContainer.new()
	opts.custom_minimum_size = Vector2(430, 0)
	opts.add_theme_constant_override("separation", 6)
	bottom.add_child(opts)
	opts.add_child(UiKit.section("Son et réglages"))
	sound_check = CheckButton.new()
	sound_check.name = "SoundCheck"
	sound_check.text = "Son"
	UiKit.style_toggle(sound_check, 19)
	sound_check.button_pressed = not AudioServer.is_bus_mute(_master_bus())
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
	back.pressed.connect(func() -> void:
		MenuSound.play_toggle()
		close())
	actions.add_child(back)
	return layer


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


## Page de reaffectation : une ligne par action (nom, boutons actuels a
## cliquer), PAR DEFAUT, RETOUR.
func _build_remap() -> Control:
	var layer := UiKit.page("RemapPanel", "RÉAFFECTER LA MANETTE", "TOUTES LES MANETTES",
		[["cross", "Choisir l'action"], ["circle", "Retour"], ["key:Échap", "Annuler / retour"]])
	var panel := UiKit.card(UiKit.CYAN, 1100)
	UiKit.page_content(layer).add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var help := UiKit.label("Choisissez une action, puis appuyez sur son nouveau bouton. Un bouton ne sert qu'à une action :\n"
		+ "pris ailleurs, il y est échangé. R2, L2, le stick gauche et Options (menu pause) ne changent pas.", 18,
		UiKit.DIM, 600, false)
	box.add_child(help)
	box.add_child(UiKit.gap(6))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for a: String in PadBindings.ACTIONS:
		var l := _label(String(PadBindings.LABELS[a]), 21)
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
	back.name = "RemapBack"
	back.text = "RETOUR"
	back.custom_minimum_size = Vector2(220, 58)
	UiKit.style_choice(back, 22)
	back.pressed.connect(toggle_remap)
	bottom.add_child(back)
	return layer


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


func _label(text: String, size: int) -> Label:
	return UiKit.label(text, size, UiKit.TEXT, 700, false)
