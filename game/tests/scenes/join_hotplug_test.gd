extends PhysicsTest

## Salle d'attente du menu et manettes a chaud (taches 4.2, 4.4) :
##   A. menu : la manette 3 appuie sur Croix -> J1 ; la manette 1 -> J2 ;
##      Espace -> J3 au clavier ZQSD ; la manette 3 appuie sur Rond -> elle
##      repart, les autres remontent ; Options (manette 1) ouvre la page de
##      selection a 2, chaque appareil y pilote son joueur ; depart :
##      GameState.join_devices = [1, ZQSD] ;
##   B. course lancee avec cette liste : la manette 1 fait avancer J1 et lui
##      seul, ZQSD fait avancer J2 et lui seul, la manette 0 (non inscrite)
##      personne ;
##   C. a chaud : la manette 1 se debranche en pleine acceleration -> J1 en
##      roue libre (plus de gaz), aucune pause, sa vue l'affiche ; rebranchee,
##      elle le fait repartir.
##   Options : seul le joueur 1 lance (INPUT_SPEC §5).

var _menu: MainMenu
var _launched: int = 0
var _scene: Node3D
var _seen: Dictionary = {}
var _start: Array[Vector3] = []


func _test_setup() -> void:
	duration_ticks = 700
	GameState.join_devices = PackedInt32Array()
	_menu = (load("res://ui/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	_menu.auto_change_scene = false
	_menu.launch_requested.connect(func(n: int) -> void: _launched = n)
	add_child(_menu)


func _pad(device: int, button: JoyButton, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = button
	e.pressed = pressed
	Input.parse_input_event(e)


func _axis(device: int, axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = device
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func _test_tick(t: int) -> void:
	match t:
		5:
			_menu.toggle_join()
		6:
			_pad(3, JOY_BUTTON_A, true)
		7:
			_pad(3, JOY_BUTTON_A, false)
			_pad(1, JOY_BUTTON_A, true)
		8:
			_pad(1, JOY_BUTTON_A, false)
			_key(KEY_SPACE, true)
		9:
			_key(KEY_SPACE, false)
			_seen["three"] = _menu.join_list.duplicate()
			_seen["slot3"] = (_menu._join_slots[2]).text
			# la manette 3 repart, puis le clavier ZQSD aussi (Retour arriere : le dernier)
			_pad(3, JOY_BUTTON_B, true)
		10:
			_pad(3, JOY_BUTTON_B, false)
			_seen["after_leave"] = _menu.join_list.duplicate()
			_pad(1, JOY_BUTTON_START, true)
		11:
			_pad(1, JOY_BUTTON_START, false)
			# Options : la page de selection s'ouvre pour les inscrits
			var sel := _menu.loadout
			_seen["selection"] = [sel.visible, sel.panels.size()]
			var e1 := InputEventJoypadButton.new()
			e1.device = 1
			e1.button_index = JOY_BUTTON_A
			e1.pressed = true
			var e3 := e1.duplicate() as InputEventJoypadButton
			e3.device = 3
			var sp := InputEventKey.new()
			sp.physical_keycode = KEY_SPACE
			sp.pressed = true
			var en := sp.duplicate() as InputEventKey
			en.physical_keycode = KEY_ENTER
			_seen["route"] = [sel.route(e1), sel.route(e3), sel.route(sp), sel.route(en)]
			_menu.start_race()
			_seen["launched"] = _launched
			_seen["devices"] = GameState.join_devices.duplicate()
			_menu.queue_free()
			_scene = (load("res://dev/race.tscn") as PackedScene).instantiate() as Node3D
			_scene.set("ready_gate", false)
			add_child(_scene)
	if _scene == null:
		return
	var players: Array = _scene.get("players")
	if players.size() != 2:
		return
	var t1 := (players[0] as Object).get("truck") as Truck
	var t2 := (players[1] as Object).get("truck") as Truck
	# commande recue par chaque camion pendant chaque appui (l'elan d'un camion
	# lance ne compte pas)
	match t:
		200:
			_start = [t1.global_position, t2.global_position]
			_axis(1, JOY_AXIS_TRIGGER_RIGHT, 1.0)
		260:
			_seen["pad1"] = [t1.get_input().throttle, t2.get_input().throttle, t1.global_position.distance_to(_start[0])]
			_axis(1, JOY_AXIS_TRIGGER_RIGHT, 0.0)
		300:
			_key(KEY_W, true)
		340:
			_seen["zqsd"] = [t1.get_input().throttle, t2.get_input().throttle]
			_key(KEY_W, false)
		370:
			_axis(0, JOY_AXIS_TRIGGER_RIGHT, 1.0)
		400:
			_seen["pad0"] = [t1.get_input().throttle, t2.get_input().throttle]
			_axis(0, JOY_AXIS_TRIGGER_RIGHT, 0.0)
			# a chaud : la manette 1 accelere, puis se debranche
			_axis(1, JOY_AXIS_TRIGGER_RIGHT, 1.0)
		500:
			Input.joy_connection_changed.emit(1, false)
		502:
			_seen["unplugged"] = [t1.get_input().throttle, get_tree().paused]
			_seen["unplug_msg"] = String(((players[0] as Object).get("hud") as RaceHud).get("_center_text"))
			Input.joy_connection_changed.emit(1, true)
		504:
			_seen["replug_idle"] = t1.get_input().throttle
			_axis(1, JOY_AXIS_TRIGGER_RIGHT, 1.0)
		510:
			_seen["replugged"] = t1.get_input().throttle
			_seen["replug_msg"] = String(((players[0] as Object).get("hud") as RaceHud).get("_center_text"))
			_axis(1, JOY_AXIS_TRIGGER_RIGHT, 0.0)


func _test_finish() -> void:
	var zqsd := GameStateNode.JOIN_ZQSD
	check("salle d'attente : manette 3, manette 1, clavier ZQSD dans l'ordre",
		str(_seen.get("three", [])) == str(PackedInt32Array([3, 1, zqsd])), str(_seen.get("three", [])))
	check("case J3 : clavier ZQSD, couleur jaune", String(_seen.get("slot3", "")).contains("ZQSD")
		and String(_seen.get("slot3", "")).contains("JAUNE"), String(_seen.get("slot3", "")))
	check("Rond : la manette 3 repart, les autres remontent",
		str(_seen.get("after_leave", [])) == str(PackedInt32Array([1, zqsd])), str(_seen.get("after_leave", [])))
	var sel: Array = _seen.get("selection", [false, 0])
	check("Options : page de selection ouverte, 2 cartes", bool(sel[0]) and int(sel[1]) == 2, str(sel))
	var r: Array = _seen.get("route", [])
	check("selection : manette 1 -> J1, manette 3 (partie) -> personne, Espace -> J2, Entree -> personne",
		r.size() == 4 and str(r[0]) == str([0, &"accept"]) and (r[1] as Array).is_empty()
		and str(r[2]) == str([1, &"accept"]) and (r[3] as Array).is_empty(), str(r))
	check("tous prets : depart a 2, avec les appareils inscrits", int(_seen.get("launched", 0)) == 2
		and str(_seen.get("devices", [])) == str(PackedInt32Array([1, zqsd])), str(_seen.get("devices", [])))
	var p1: Array = _seen.get("pad1", [0.0, 0.0])
	var kz: Array = _seen.get("zqsd", [0.0, 0.0])
	var p0: Array = _seen.get("pad0", [1.0, 1.0])
	check("manette 1 : gaz de J1 seul, J1 avance", float(p1[0]) > 0.99 and float(p1[1]) == 0.0 and float(p1[2]) > 2.0, str(p1))
	check("ZQSD : gaz de J2 seul", float(kz[1]) > 0.5 and float(kz[0]) == 0.0, str(kz))
	check("manette 0, non inscrite : le gaz de personne", float(p0[0]) == 0.0 and float(p0[1]) == 0.0, str(p0))
	var un: Array = _seen.get("unplugged", [1.0, true])
	check("manette debranchee : roue libre, pas de pause", float(un[0]) == 0.0 and not bool(un[1]), str(un))
	check("rebranchee : elle pilote de nouveau J1", float(_seen.get("replug_idle", 1.0)) == 0.0
		and float(_seen.get("replugged", 0.0)) > 0.9, "%s -> %s" % [_seen.get("replug_idle"), _seen.get("replugged")])
	check("vue de J1 : MANETTE DECONNECTEE, puis plus rien au rebranchement",
		String(_seen.get("unplug_msg", "")).begins_with("MANETTE DÉCONNECTÉE")
		and not String(_seen.get("replug_msg", "")).contains("MANETTE"),
		"%s | %s" % [String(_seen.get("unplug_msg", "")).replace("\n", " "), String(_seen.get("replug_msg", "")).replace("\n", " ")])
	GameState.join_devices = PackedInt32Array()
	GameState.requested_players = 0
