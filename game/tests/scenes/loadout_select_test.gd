extends PhysicsTest

## Page de selection du menu (LoadoutSelect, 2026-10-16), apres PRET, par les
## vrais chemins d'entree (Input.parse_input_event) :
##   - 2 joueurs : deux cartes cote a cote, a l'ecran, chacune a sa manette ;
##   - J1 (fleches) : deux crans vers le bas = 3e remorque, ecrite dans
##     GameState ; J2 (manette 1, croix haut) :
##     remonte en boucle a la derniere ;
##   - Croix / Entree valident colonne par colonne : remorque, pouvoir
##     gauche, pouvoir droit (AUCUN : il n'y a pas encore de pouvoir, et ca
##     se valide quand meme), la derniere = PRET ; Rond revient d'une colonne ;
##   - tous PRETS : bandeau, puis depart apres LAUNCH_DELAY_S ; un joueur qui
##     se ravise (Retour arriere) l'annule ; le depart verrouille le choix
##     (GameState.loadout_locked) ;
##   - grille : 6 joueurs en 3 x 2, 3 joueurs avec la derniere carte
##     centree, sans chevauchement, a l'ecran ;
##   - Echap ramene a l'accueil.

var _menu: MainMenu
var _sel: LoadoutSelect
var _launches: Array[int] = []
var _seen: Dictionary = {}


func _test_setup() -> void:
	duration_ticks = 200
	get_window().size = Vector2i(1920, 1080)
	GameState.requested_players = 0
	GameState.loadout_locked = false
	GameState.trailer_choice = PackedInt32Array([0, 0, 0, 0, 0, 0])
	GameState.power_left = PackedInt32Array([-1, -1, -1, -1, -1, -1])
	GameState.power_right = PackedInt32Array([-1, -1, -1, -1, -1, -1])
	_menu = (load("res://ui/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	_menu.auto_change_scene = false
	_menu.launch_requested.connect(func(n: int) -> void: _launches.append(n))
	add_child(_menu)
	_sel = _menu.loadout


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)
	# livre l'entree tout de suite, pas a la prochaine image (en headless,
	# plusieurs ticks physiques passent par image)
	Input.flush_buffered_events()


func _pad(device: int, button: JoyButton, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = button
	e.pressed = pressed
	Input.parse_input_event(e)
	# livre l'entree tout de suite, pas a la prochaine image (en headless,
	# plusieurs ticks physiques passent par image)
	Input.flush_buffered_events()


func _panel(i: int) -> LoadoutPanel:
	return _sel.panels[i]


func _rects_ok(n: int) -> bool:
	var vp := Rect2(Vector2.ZERO, Vector2(1920, 1080))
	var rects: Array[Rect2] = []
	for p in _sel.panels:
		rects.append(Rect2(p.global_position, LoadoutPanel.DESIGN * p.scale))
	var ok := rects.size() == n
	for i in rects.size():
		ok = ok and vp.encloses(rects[i])
		for j in range(i + 1, rects.size()):
			ok = ok and not rects[i].grow(-1.0).intersects(rects[j].grow(-1.0))
	return ok


func _test_tick(t: int) -> void:
	match t:
		2:
			_menu.select_players(2)
			_menu.open_selection()
		4:
			var a := Rect2(_panel(0).global_position, LoadoutPanel.DESIGN * _panel(0).scale)
			var b := Rect2(_panel(1).global_position, LoadoutPanel.DESIGN * _panel(1).scale)
			_seen["open"] = [_sel.visible, _menu.home.visible, _sel.panels.size()]
			_seen["side"] = a.end.x <= b.position.x and absf(a.position.y - b.position.y) < 1.0 and _rects_ok(2)
			_seen["devices"] = [_panel(0).device_text, _panel(1).device_text]
		6: _key(KEY_DOWN, true)
		7: _key(KEY_DOWN, false)
		8: _key(KEY_DOWN, true)
		9: _key(KEY_DOWN, false)
		10: _pad(1, JOY_BUTTON_DPAD_UP, true)
		11: _pad(1, JOY_BUTTON_DPAD_UP, false)
		12:
			_seen["trailers"] = [_panel(0).trailer, _panel(1).trailer, GameState.trailer_choice[0],
				GameState.trailer_choice[1]]
			_key(KEY_ENTER, true)
		13: _key(KEY_ENTER, false)
		14:
			_seen["col1"] = [_panel(0).column, _panel(0).validated[0], _panel(0).confirmed]
			_key(KEY_ENTER, true)
		15: _key(KEY_ENTER, false)
		16: _key(KEY_ENTER, true)
		17: _key(KEY_ENTER, false)
		18:
			_seen["j1_ready"] = [_panel(0).confirmed, GameState.power_left[0], GameState.power_right[0],
				_panel(0).reels[1].current()["name"]]
			_seen["not_all"] = not _sel.all_ready()
			_pad(1, JOY_BUTTON_A, true)
		19: _pad(1, JOY_BUTTON_A, false)
		20: _pad(1, JOY_BUTTON_A, true)
		21: _pad(1, JOY_BUTTON_A, false)
		22: _pad(1, JOY_BUTTON_B, true)
		23:
			_pad(1, JOY_BUTTON_B, false)
			_seen["back_col"] = [_panel(1).column, _panel(1).validated[1], _panel(1).confirmed]
		24: _pad(1, JOY_BUTTON_X, true)       # Carre valide aussi
		25: _pad(1, JOY_BUTTON_X, false)
		26: _pad(1, JOY_BUTTON_A, true)
		27: _pad(1, JOY_BUTTON_A, false)
		28:
			_seen["all"] = _sel.all_ready()
		40:
			# un joueur se ravise avant le depart
			_key(KEY_BACKSPACE, true)
		41:
			_key(KEY_BACKSPACE, false)
			_seen["cancelled"] = [_panel(0).confirmed, _sel.all_ready()]
		100:
			_seen["no_launch"] = _launches.duplicate()
			_key(KEY_ENTER, true)
		101: _key(KEY_ENTER, false)
		102: _seen["ready_again"] = _sel.all_ready()
		180:
			_seen["launch"] = [_launches.duplicate(), GameState.loadout_locked]
			_sel.open(6)
		182:
			var p0 := _panel(0).global_position
			var p2 := _panel(2).global_position
			var p3 := _panel(3).global_position
			_seen["six"] = [_rects_ok(6), absf(p0.y - p2.y) < 1.0, p3.y > p0.y + 10.0]
			_sel.open(3)
		184:
			var a := Rect2(_panel(0).global_position, LoadoutPanel.DESIGN * _panel(0).scale)
			var b := Rect2(_panel(1).global_position, LoadoutPanel.DESIGN * _panel(1).scale)
			var c := Rect2(_panel(2).global_position, LoadoutPanel.DESIGN * _panel(2).scale)
			var mid := (a.position.x + b.end.x) / 2.0
			_seen["three"] = [_rects_ok(3), absf(c.get_center().x - mid) < 2.0]
		190: _key(KEY_ESCAPE, true)
		191: _key(KEY_ESCAPE, false)
		194: _seen["escape"] = [_sel.visible, _menu.home.visible]


func _test_finish() -> void:
	check("PRET ouvre la page : 2 cartes, accueil cache", _seen.get("open", []) == [true, false, 2], str(_seen.get("open")))
	check("2 joueurs : cartes cote a cote, a l'ecran", _seen.get("side", false))
	check("chaque carte annonce sa manette", _seen.get("devices", []) == ["Manette 1  ·  flèches", "Manette 2  ·  ZQSD"],
		str(_seen.get("devices")))
	check("J1 fleche bas x2 : 3e remorque ; J2 croix haut : derniere (boucle) ; ecrit dans GameState",
		_seen.get("trailers", []) == [2, TrailerCatalog.count() - 1, 2, TrailerCatalog.count() - 1],
		str(_seen.get("trailers")))
	check("Entree : remorque validee, colonne pouvoir", _seen.get("col1", []) == [1, true, false], str(_seen.get("col1")))
	check("pouvoirs : AUCUN se valide (pas de pouvoir), J1 PRET", _seen.get("j1_ready", []) == [true, -1, -1, "AUCUN"],
		str(_seen.get("j1_ready")))
	check("un seul pret : pas encore tous", _seen.get("not_all", false))
	check("Rond : revient d'une colonne", _seen.get("back_col", []) == [1, false, false], str(_seen.get("back_col")))
	check("Carre et Croix : J2 PRET, tous prets", _seen.get("all", false))
	check("Retour arriere : J1 se ravise, plus tous prets", _seen.get("cancelled", []) == [false, false],
		str(_seen.get("cancelled")))
	check("pas de depart tant que quelqu'un se ravise", _seen.get("no_launch", [0]) == [], str(_seen.get("no_launch")))
	check("Entree : J1 de nouveau pret", _seen.get("ready_again", false))
	var launch: Array = _seen.get("launch", [])
	check("tous prets : depart apres le delai, a 2, choix verrouille",
		launch.size() == 2 and launch[0] == [2] and launch[1] == true, str(launch))
	check("6 joueurs : grille 3 x 2 a l'ecran, sans chevauchement", _seen.get("six", []) == [true, true, true],
		str(_seen.get("six")))
	check("3 joueurs : derniere carte centree", _seen.get("three", []) == [true, true], str(_seen.get("three")))
	check("Echap : retour a l'accueil", _seen.get("escape", []) == [false, true], str(_seen.get("escape")))
