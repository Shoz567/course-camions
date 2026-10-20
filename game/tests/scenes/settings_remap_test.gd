extends PhysicsTest

## Options et reaffectation de la manette (tache 7.1) :
##   A. PadBindings.defaults() = les boutons par defaut de DeviceInputSource ;
##   B. assign : un bouton ne sert qu'a une action, une action videe recoit
##      en echange les anciens boutons ; le bouton PS est refuse ;
##   C. un profil abime (action vide, bouton hors bornes) reprend ses defauts ;
##   D. fichier d'options : ecrit puis relu, tout revient a l'identique ;
##   E. menu : RÉAFFECTER, Nitro, puis L3 sur la manette 2 -> nitro = L3,
##      klaxon = Carre (echange) ; PS ignore ; Echap annule ; PAR DEFAUT ;
##   F. en course : une manette suit le profil (L3 = nitro, Carre plus rien) ;
##   G. profil d'avant « regarder derriere » (2026-10-20, klaxon sur L1) :
##      L1 passe a regarder derriere, le klaxon reprend L3.

const TEST_PATH := "user://settings_remap_test.cfg"

var _menu: MainMenu
var _input: LocalInputSource
var _seen: Dictionary = {}


func _test_setup() -> void:
	duration_ticks = 60
	GameState.pad_bindings = PadBindings.defaults()
	_menu = (load("res://ui/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	_menu.auto_change_scene = false
	add_child(_menu)


func _pad(device: int, button: JoyButton, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = button
	e.pressed = pressed
	Input.parse_input_event(e)


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func _test_tick(t: int) -> void:
	match t:
		2:
			_menu.toggle_settings()
			_menu.toggle_remap()
			_menu.begin_remap("boost")
			_seen["waiting_text"] = (_menu._remap_buttons["boost"] as Button).text
			_pad(2, JOY_BUTTON_GUIDE, true)
		3:
			_pad(2, JOY_BUTTON_GUIDE, false)
			_seen["after_ps"] = _menu.remap_waiting
			_pad(2, JOY_BUTTON_LEFT_STICK, true)
		4:
			_pad(2, JOY_BUTTON_LEFT_STICK, false)
			_seen["bindings"] = GameState.pad_bindings.duplicate(true)
			_seen["boost_text"] = (_menu._remap_buttons["boost"] as Button).text
			_seen["honk_text"] = (_menu._remap_buttons["honk"] as Button).text
			_menu.begin_remap("camera")
			_key(KEY_ESCAPE, true)
		5:
			_key(KEY_ESCAPE, false)
			_seen["cancel"] = [_menu.remap_waiting, _menu.remap_panel.visible,
				PadBindings.list_name(GameState.pad_bindings["camera"])]
			# en course : le profil reaffecte suit la manette du joueur
			_input = LocalInputSource.new()
			_input.device = 0
			_input.keyboard_layout = KeyboardInputSource.Layout.NONE
			add_child(_input)
			_pad(0, JOY_BUTTON_LEFT_STICK, true)
		7:
			_seen["l1_boost"] = _input.poll(t).boost
			_pad(0, JOY_BUTTON_LEFT_STICK, false)
			_pad(0, JOY_BUTTON_X, true)
		9:
			var f := _input.poll(t)
			_seen["square"] = [f.boost, f.honk]
			_pad(0, JOY_BUTTON_X, false)
			_menu.reset_remap()
			_seen["reset"] = str(GameState.pad_bindings) == str(PadBindings.defaults())
			_menu.toggle_remap()
			_seen["closed"] = not _menu.remap_panel.visible


func _test_finish() -> void:
	# A
	var d := DeviceInputSource.new()
	var defaults := PadBindings.defaults()
	check("profil par defaut = boutons par defaut de DeviceInputSource",
		_same(defaults["handbrake"], d.buttons_handbrake) and _same(defaults["boost"], d.buttons_boost)
		and _same(defaults["cargo"], d.buttons_cargo) and _same(defaults["honk"], d.buttons_honk)
		and _same(defaults["camera"], d.buttons_camera) and _same(defaults["reset"], d.buttons_reset)
		and _same(defaults["look_back"], d.buttons_look_back))
	d.free()
	# B
	var b1 := PadBindings.assign(defaults, "honk", JOY_BUTTON_RIGHT_SHOULDER)
	check("klaxon = R1 : retire du frein a main, qui garde Croix",
		_list(b1, "honk") == "R1" and _list(b1, "handbrake") == "Croix", "%s / %s" % [_list(b1, "honk"), _list(b1, "handbrake")])
	var b2 := PadBindings.assign(defaults, "handbrake", JOY_BUTTON_X)
	check("frein a main = Carre : la nitro, videe, prend Croix et R1 en echange",
		_list(b2, "handbrake") == "Carré" and _list(b2, "boost") == "Croix, R1", "%s / %s" % [_list(b2, "handbrake"), _list(b2, "boost")])
	var b3 := PadBindings.assign(defaults, "boost", JOY_BUTTON_GUIDE)
	check("bouton PS refuse", str(b3) == str(defaults))
	var empty := true
	for a: String in PadBindings.ACTIONS:
		empty = empty and not ((b1[a] as PackedInt32Array).is_empty() or (b2[a] as PackedInt32Array).is_empty())
	check("aucune action sans bouton apres un echange", empty)
	check("profil d'origine jamais modifie", str(defaults) == str(PadBindings.defaults()))
	# C
	var broken := PadBindings.sanitized({"boost": PackedInt32Array(), "camera": [200, -1], "honk": [JOY_BUTTON_DPAD_UP]})
	check("profil abime : actions vides ou hors bornes -> defaut, le reste garde",
		_list(broken, "boost") == "Carré" and _list(broken, "camera") == "R3" and _list(broken, "honk") == "Haut"
		and _list(broken, "reset") == "Options, Create, Pavé tactile", str(broken))
	# D
	_round_trip()
	# E
	var bound: Dictionary = _seen.get("bindings", {})
	check("menu : en attente, la ligne le dit", String(_seen.get("waiting_text", "")).begins_with("appuyez"),
		String(_seen.get("waiting_text", "")))
	check("menu : le bouton PS est ignore, l'attente continue", String(_seen.get("after_ps", "")) == "boost")
	check("menu : L3 (manette 2) -> nitro = L3, klaxon = Carre en echange",
		not bound.is_empty() and _list(bound, "boost") == "L3" and _list(bound, "honk") == "Carré",
		"%s / %s" % [_seen.get("boost_text"), _seen.get("honk_text")])
	check("menu : les lignes affichent les nouveaux boutons",
		String(_seen.get("boost_text", "")) == "L3" and String(_seen.get("honk_text", "")) == "Carré")
	var cancel: Array = _seen.get("cancel", ["x", false, ""])
	check("menu : Echap annule l'attente sans fermer ni rien changer",
		String(cancel[0]) == "" and bool(cancel[1]) and String(cancel[2]) == "R3", str(cancel))
	# F
	check("en course : L3 = nitro", bool(_seen.get("l1_boost", false)))
	var sq: Array = _seen.get("square", [true, false])
	check("en course : Carre = klaxon, plus nitro", not bool(sq[0]) and bool(sq[1]), str(sq))
	# G
	var old := PadBindings.defaults()
	old.erase("look_back")
	old["honk"] = PackedInt32Array([JOY_BUTTON_LEFT_SHOULDER])
	var migrated := PadBindings.sanitized(old)
	check("ancien profil : L1 regarde derriere, klaxon sur L3",
		_list(migrated, "look_back") == "L1" and _list(migrated, "honk") == "L3", str(migrated))
	check("PAR DEFAUT puis RETOUR", bool(_seen.get("reset", false)) and bool(_seen.get("closed", false)))
	GameState.pad_bindings = PadBindings.defaults()


func _round_trip() -> void:
	var saved := [GameState.graphics_quality, GameState.show_fps, GameState.dynamic_resolution,
		GameState.selected_track, GameState.speed_class, GameState.trailer_choice.duplicate(),
		GameState.pad_bindings.duplicate(true)]
	var bus := AudioServer.get_bus_index("Master")
	var audio := [AudioServer.is_bus_mute(bus), AudioServer.get_bus_volume_db(bus)]
	var custom := PadBindings.assign(PadBindings.defaults(), "cargo", JOY_BUTTON_DPAD_DOWN)
	GameState.graphics_quality = GraphicsSettings.Quality.LOW
	GameState.show_fps = true
	GameState.dynamic_resolution = false
	GameState.selected_track = 1
	GameState.speed_class = 3
	GameState.trailer_choice = PackedInt32Array([2, 1, 0, 3, 0, 1])
	GameState.pad_bindings = custom
	AudioServer.set_bus_mute(bus, true)
	AudioServer.set_bus_volume_db(bus, linear_to_db(0.4))
	var w := GameState.write_settings(TEST_PATH)
	# tout remis aux defauts, puis relu
	GameState.graphics_quality = GraphicsSettings.Quality.HIGH
	GameState.show_fps = false
	GameState.dynamic_resolution = true
	GameState.selected_track = 0
	GameState.speed_class = 1
	GameState.trailer_choice = PackedInt32Array([0, 0, 0, 0, 0, 0])
	GameState.pad_bindings = PadBindings.defaults()
	AudioServer.set_bus_mute(bus, false)
	AudioServer.set_bus_volume_db(bus, 0.0)
	var r := GameState.read_settings(TEST_PATH)
	var ok := w == OK and r == OK and GameState.graphics_quality == GraphicsSettings.Quality.LOW \
		and GameState.show_fps and not GameState.dynamic_resolution and GameState.selected_track == 1 \
		and GameState.speed_class == 3 and GameState.trailer_choice == PackedInt32Array([2, 1, 0, 3, 0, 1]) \
		and str(GameState.pad_bindings) == str(custom) and AudioServer.is_bus_mute(bus) \
		and absf(db_to_linear(AudioServer.get_bus_volume_db(bus)) - 0.4) < 0.01
	check("fichier d'options : ecrit puis relu a l'identique (son, video, course, boutons)", ok,
		"ecriture %d, lecture %d" % [w, r])
	check("fichier absent : erreur, rien ne change", GameState.read_settings("user://absent_xyz.cfg") != OK
		and GameState.selected_track == 1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	GameState.graphics_quality = saved[0]
	GameState.show_fps = saved[1]
	GameState.dynamic_resolution = saved[2]
	GameState.selected_track = saved[3]
	GameState.speed_class = saved[4]
	GameState.trailer_choice = saved[5]
	GameState.pad_bindings = saved[6]
	AudioServer.set_bus_mute(bus, audio[0])
	AudioServer.set_bus_volume_db(bus, audio[1])


static func _list(b: Dictionary, action: String) -> String:
	return PadBindings.list_name(b[action])


static func _same(packed: PackedInt32Array, typed: Array[JoyButton]) -> bool:
	if packed.size() != typed.size():
		return false
	for k in packed.size():
		if packed[k] != int(typed[k]):
			return false
	return true
