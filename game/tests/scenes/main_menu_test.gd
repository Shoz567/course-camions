extends PhysicsTest

## Menu principal (ui/main_menu.tscn), par les vrais chemins d'entree
## (Input.parse_input_event : clavier, manette, clics souris) :
##   - titre au centre, 4 boutons de joueurs, 1 joueur par defaut ;
##   - touche 3, puis L / R de la manette, puis clic : le choix suit, et les
##     camions montres en decor aussi ;
##   - son : un clic coupe le bus Master, un second le remet ;
##   - roue crantee : ouvre l'ecran des parametres, - le referme ; rouvert, il
##     montre le schema de la manette (les 8 commandes de la demande, legendes
##     sans chevauchement), regle le volume reel, et RETOUR ramene au menu ;
##   - camera d'orbite : tourne autour de la grille, a distance constante ;
##   - + (Start) et A Switch (JOY_BUTTON_B, ajoute a ui_accept) lancent la
##     course : signal avec le nombre choisi, ecrit dans GameState.

var _menu: MainMenu
var _launches: Array[int] = []
var _cam_start: Vector3
var _cam_dist: Array[float] = []
var _defaults_ok: bool = false
var _seen: Dictionary = {}


func _test_setup() -> void:
	duration_ticks = 140
	# la fenetre headless fait 64 x 64 : on lui donne la taille de reference
	# (1920 x 1080, display/window/size) pour que les boutons soient a l'ecran
	get_window().size = Vector2i(1920, 1080)
	GameState.requested_players = 0
	_menu = (load("res://ui/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	_menu.auto_change_scene = false
	_menu.launch_requested.connect(func(n: int) -> void: _launches.append(n))
	add_child(_menu)


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func _pad(button: JoyButton, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = button
	e.pressed = pressed
	Input.parse_input_event(e)


## Clic reel : la souris survole d'abord le bouton (BaseButton ignore un appui
## sans survol), puis appui / relachement.
func _click(c: Control, pressed: bool) -> void:
	if pressed:
		var m := InputEventMouseMotion.new()
		m.position = c.get_global_rect().get_center()
		m.global_position = m.position
		Input.parse_input_event(m)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = c.get_global_rect().get_center()
	e.global_position = e.position
	e.pressed = pressed
	Input.parse_input_event(e)


func _visible_trucks() -> int:
	var n := 0
	for t in _menu.trucks:
		n += 1 if t.visible else 0
	return n


func _test_tick(t: int) -> void:
	var cam := _menu.camera.global_position
	match t:
		3:
			_cam_start = cam
			_defaults_ok = _menu.selected_players == 1 and _visible_trucks() == 1 \
					and _menu.player_buttons[0].button_pressed and not _menu.player_buttons[1].button_pressed
			var title_center := _menu.title.get_global_rect().get_center().x
			_seen["title_dx"] = absf(title_center - _menu.get_viewport().get_visible_rect().size.x / 2.0)
		10: _key(KEY_3, true)
		11: _key(KEY_3, false)
		14: _seen["key3"] = [_menu.selected_players, _visible_trucks()]
		20: _pad(JOY_BUTTON_RIGHT_SHOULDER, true)
		21: _pad(JOY_BUTTON_RIGHT_SHOULDER, false)
		24:
			_seen["r"] = _menu.selected_players
			_pad(JOY_BUTTON_LEFT_SHOULDER, true)
		25: _pad(JOY_BUTTON_LEFT_SHOULDER, false)
		28: _seen["l"] = _menu.selected_players
		30: _click(_menu.player_buttons[1], true)
		31: _click(_menu.player_buttons[1], false)
		34:
			_seen["click2"] = [_menu.selected_players, _menu.player_buttons[1].button_pressed,
					_menu.player_buttons[2].button_pressed]
			_key(KEY_3, true)
		35: _key(KEY_3, false)
		40: _click(_menu.sound_button, true)
		41: _click(_menu.sound_button, false)
		44:
			_seen["mute"] = [AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), _menu.sound_button.text]
			_click(_menu.sound_button, true)
		45: _click(_menu.sound_button, false)
		48: _seen["unmute"] = AudioServer.is_bus_mute(AudioServer.get_bus_index("Master"))
		60: _click(_menu.settings_button, true)
		61: _click(_menu.settings_button, false)
		64:
			var back := _menu.settings.find_child("Back", true, false) as Button
			_seen["settings_open"] = _menu.settings.visible and back.has_focus()
			_pad(JOY_BUTTON_BACK, true)
		65: _pad(JOY_BUTTON_BACK, false)
		68: _seen["settings_closed"] = not _menu.settings.visible and _menu.settings_button.has_focus()
		72: _click(_menu.settings_button, true)
		73: _click(_menu.settings_button, false)
		76:
			var diagram := _menu.settings.find_child("ControllerDiagram", true, false) as ControllerDiagram
			_seen["diagram"] = diagram != null and diagram.is_visible_in_tree() and diagram.size.x >= 1000.0
			if diagram != null:
				_seen["callouts"] = diagram.callouts()
			_menu.volume_slider.value = 50.0
			_seen["volume_db"] = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master"))
			_menu.volume_slider.value = 100.0
			_seen["sound_check"] = _menu.sound_check.button_pressed
		78: _click(_menu.settings.find_child("Back", true, false) as Control, true)
		79: _click(_menu.settings.find_child("Back", true, false) as Control, false)
		82: _seen["back"] = not _menu.settings.visible
		110: _pad(JOY_BUTTON_START, true)
		111: _pad(JOY_BUTTON_START, false)
		114:
			_seen["start"] = _launches.duplicate()
			_menu.start_button.grab_focus()
		116: _pad(JOY_BUTTON_B, true)
		118: _pad(JOY_BUTTON_B, false)
	if t >= 3:
		_cam_dist.append(Vector2(cam.x - _menu._orbit_center.x, cam.z - _menu._orbit_center.z).length())
	if t == 100:
		_seen["cam_moved"] = cam.distance_to(_cam_start)
		var fwd := -_menu.camera.global_basis.z
		_seen["cam_aim"] = fwd.dot((_menu._orbit_center - cam).normalized())


func _test_finish() -> void:
	check("1 joueur par defaut, 1 camion montre, bouton 1 enfonce", _defaults_ok)
	check("4 boutons de joueurs", _menu.player_buttons.size() == 4)
	check_below("titre centre horizontalement (px)", _seen["title_dx"], 4.0)
	check("titre anime (echelle ou rotation non neutres)",
		_menu.title.scale != Vector2.ONE or _menu.title.rotation != 0.0)
	check("touche 3 : 3 joueurs, 3 camions", _seen["key3"] == [3, 3], str(_seen["key3"]))
	check("manette R : 4 joueurs", _seen["r"] == 4, str(_seen["r"]))
	check("manette L : 3 joueurs", _seen["l"] == 3, str(_seen["l"]))
	check("clic sur 2 JOUEURS : choisi et seul enfonce", _seen["click2"] == [2, true, false], str(_seen["click2"]))
	check("son : un clic coupe le bus Master", _seen["mute"] == [true, "SON : OFF"], str(_seen["mute"]))
	check("son : un second clic le remet", _seen["unmute"] == false)
	check("roue crantee : panneau ouvert, FERMER selectionne", _seen["settings_open"])
	check("- referme le panneau, focus sur la roue", _seen["settings_closed"])
	check("parametres : schema de la manette affiche", _seen.get("diagram", false))
	var callouts: Array = _seen.get("callouts", [])
	var keys := {}
	for c: Dictionary in callouts:
		keys[c["key"]] = c["text"]
	var wanted := {"A / Y": "Accélérer", "B": "Freiner / marche arrière", "R / ZR": "Dérapage (drift)",
		"L": "Nitro boost (recharge 4 s)", "ZL": "Drop de cargo (recharge 30 s)",
		"X": "Changer de vue (1re / 3e personne)", "-": "Reset sur la piste", "Croix": "Klaxon"}
	var missing := []
	for k: String in wanted:
		if keys.get(k, "") != wanted[k]:
			missing.append(k)
	check("schema : les 8 commandes de la demande", missing.is_empty(), "manquent %s" % [missing])
	var overlap := false
	var outside := false
	var bounds := Rect2(0, 0, ControllerDiagram.W, ControllerDiagram.H)
	for i in callouts.size():
		var ri := ControllerDiagram.label_rect(callouts[i])
		outside = outside or not bounds.encloses(ri)
		for j in range(i + 1, callouts.size()):
			overlap = overlap or ri.intersects(ControllerDiagram.label_rect(callouts[j]))
	check("schema : legendes sans chevauchement, dans le cadre", not overlap and not outside)
	check_near("parametres : volume a 50 % (dB)", _seen.get("volume_db", 0.0), linear_to_db(0.5), 0.01)
	check("parametres : case Son synchronisee avec le bouton", _seen.get("sound_check", false))
	check("RETOUR ramene au menu", _seen.get("back", false))
	check_above("camera en orbite : deplacement en 97 ticks (m)", _seen["cam_moved"], 3.0)
	check_below("orbite a distance constante (ecart m)", _cam_dist.max() - _cam_dist.min(), 0.01)
	check_above("la camera vise le centre de la grille (cos)", _seen["cam_aim"], 0.999)
	check("A Switch (JOY_BUTTON_B) valide dans le menu",
		InputMap.action_has_event("ui_accept", _switch_a()))
	check("+ (Start) : lance la course a 3", _seen["start"] == [3], str(_seen["start"]))
	check("A Switch sur COMMENCER : relance", _launches == [3, 3], str(_launches))
	check("choix ecrit dans GameState", GameState.requested_players == 3, str(GameState.requested_players))


func _switch_a() -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.device = -1
	e.button_index = JOY_BUTTON_B
	return e
