extends PhysicsTest

## Sas « READY ? » avant le compte a rebours (dev/race.tscn, 2 joueurs) :
##   - chaque vue montre le joueur et sa manette (« J1 - BLEU (Manette 1 /
##     fleches) ») et l'invite a appuyer sur CARRE ; personne ne bouge, meme
##     plein gaz ;
##   - Carre de la manette 0 : J1 READY (vert), le sas reste ouvert ; Carre
##     d'une manette sans joueur : rien ;
##   - Carre de la manette 1 : tous READY, le compte a rebours demarre
##     aussitot, puis la course ;
##   - Carre n'a pas declenche le boost ; au depart, largage verrouille
##     (« VERROU ») et PV au HUD.

var _scene: Node3D
var _players: Array = []
var _starts: Array[Vector3] = []
var _seen: Dictionary = {}


func _test_setup() -> void:
	duration_ticks = 330
	GameState.requested_players = 2
	_scene = (load("res://dev/race.tscn") as PackedScene).instantiate() as Node3D
	add_child(_scene)
	_players = _scene.get("players")
	for p: Object in _players:
		_starts.append((p.get("truck") as Truck).global_position)


func _pad(device: int, button: JoyButton, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = button
	e.pressed = pressed
	Input.parse_input_event(e)


func _axis(device: int, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = device
	e.axis = JOY_AXIS_TRIGGER_RIGHT
	e.axis_value = value
	Input.parse_input_event(e)


func _center(i: int) -> String:
	return String(_players[i].hud.get("_center_text"))


func _test_tick(t: int) -> void:
	var lobby := 3   # LocalRace.State.LOBBY
	match t:
		2:
			_axis(0, 1.0)
			_axis(1, 1.0)
		10:
			_seen["lobby"] = [_scene.get("state") == lobby, _center(0), _center(1)]
		20: _pad(0, JOY_BUTTON_X, true)
		23: _pad(0, JOY_BUTTON_X, false)
		26: _pad(4, JOY_BUTTON_X, true)
		29: _pad(4, JOY_BUTTON_X, false)
		40:
			_seen["j1"] = [str(_scene.get("ready_flags")), _scene.get("state") == lobby, _center(0)]
			var moved := 0.0
			for i in 2:
				moved = maxf(moved, (_players[i].truck as Truck).global_position.distance_to(_starts[i]))
			_seen["moved"] = moved
		50: _pad(1, JOY_BUTTON_X, true)
		53: _pad(1, JOY_BUTTON_X, false)
		56:
			_axis(0, 0.0)
			_axis(1, 0.0)
			_seen["all"] = [str(_scene.get("ready_flags")), _scene.get("state")]
		245:
			var t1: Truck = _players[0].truck
			_seen["go"] = [_scene.get("state"), t1.get_boost_charge(), t1.is_boosting(),
				String(_players[0].hud.get("_cargo_label").text), String(_players[0].hud.get("_hp_label").text)]


func _test_finish() -> void:
	var lobby: Array = _seen.get("lobby", [false, "", ""])
	check("sas READY ouvert au chargement", lobby[0])
	check("J1 : joueur, manette, invite CARRE", String(lobby[1]).contains("J1 - BLEU (Manette 1 / flèches)")
		and String(lobby[1]).contains("[CARRÉ]"), String(lobby[1]))
	check("J2 : joueur, manette, invite CARRE", String(lobby[2]).contains("J2 - ROUGE (Manette 2 / ZQSD)")
		and String(lobby[2]).contains("[CARRÉ]"), String(lobby[2]))
	check_below("dans le sas, personne ne bouge, meme plein gaz (m)", float(_seen.get("moved", 99.0)), 0.05)
	var j1: Array = _seen.get("j1", ["", false, ""])
	check("Carre manette 0 : J1 READY, J2 pas encore, sas ouvert (manette 4 sans effet)",
		j1[0] == "[true, false]" and j1[1], str(j1[0]))
	check("J1 voit READY !", String(j1[2]).contains("READY !"), String(j1[2]))
	var all: Array = _seen.get("all", ["", -1])
	check("Carre manette 1 : tous READY, compte a rebours lance", all[0] == "[true, true]" and all[1] == 0, str(all))
	var go: Array = _seen.get("go", [-1, 0.0, true, "", ""])
	check("course lancee apres 3 s de compte a rebours", go[0] == 1, "etat %s" % go[0])
	check("Carre dans le sas n'a pas pris le boost", go[1] == 1.0 and not go[2])
	check("au depart : largage verrouille (VERROU), PV au HUD",
		String(go[3]).begins_with("VERROU") and go[4] == "100 HP", "« %s » / « %s »" % [go[3], go[4]])
