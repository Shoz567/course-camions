extends PhysicsTest

## Choix de la remorque dans le sas READY (dev/race.tscn, 2 joueurs) :
##   - au chargement : la remorque par defaut, affichee avec ses stats et les
##     fleches ;
##   - stick a droite (manette 0), deux poussees : J1 passe a la 3e remorque
##     (une poussee maintenue = une seule remorque) ; stick a gauche (manette
##     1) : J2 boucle sur la derniere ;
##   - le camion prend la caisse et le reglage de la remorque ; l'autre joueur
##     n'est pas touche ;
##   - une fois READY, le stick ne change plus rien ;
##   - le choix est garde dans GameState pour la course suivante.

var _scene: Node3D
var _players: Array = []
var _seen: Dictionary = {}
var _base_top: float = 0.0


func _test_setup() -> void:
	duration_ticks = 50
	GameState.requested_players = 2
	GameState.trailer_choice = PackedInt32Array([0, 0, 0, 0, 0, 0])
	_scene = (load("res://dev/race.tscn") as PackedScene).instantiate() as Node3D
	add_child(_scene)
	_players = _scene.get("players")
	_base_top = (_players[0].truck as Truck).tuning.top_speed_kmh


func _stick(device: int, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = device
	e.axis = JOY_AXIS_LEFT_X
	e.axis_value = value
	Input.parse_input_event(e)


func _pad(device: int, button: JoyButton, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = button
	e.pressed = pressed
	Input.parse_input_event(e)


func _center(i: int) -> String:
	return String(_players[i].hud.get("_center_text"))


func _test_tick(t: int) -> void:
	match t:
		2:
			_seen["start"] = [_players[0].trailer, _players[1].trailer, _center(0)]
		4:
			_stick(0, 1.0)
			_stick(1, -1.0)
		9:
			_stick(0, 0.0)
			_stick(1, 0.0)
		12: _stick(0, 1.0)
		16: _stick(0, 0.0)
		20:
			var t1: Truck = _players[0].truck
			var t2: Truck = _players[1].truck
			_seen["chosen"] = [_players[0].trailer, _players[1].trailer, t1.trailer_box_size,
				t1.tuning.top_speed_kmh, t2.trailer_box_size, _center(0), _center(1)]
		24: _pad(0, JOY_BUTTON_X, true)
		27: _pad(0, JOY_BUTTON_X, false)
		30: _stick(0, 1.0)
		35: _stick(0, 0.0)
		40:
			_seen["locked"] = [_players[0].trailer, _center(0)]
			_seen["saved"] = GameState.trailer_choice.slice(0, 2)


func _test_finish() -> void:
	var start: Array = _seen.get("start", [-1, -1, ""])
	check("au chargement : remorque par defaut pour tous", start[0] == 0 and start[1] == 0, str(start))
	check("sas : remorque, fleches et stats affichees",
		String(start[2]).contains("REMORQUE : " + TrailerCatalog.default_type().display_name) and String(start[2]).contains("◄")
		and String(start[2]).contains("[CARRÉ]"), String(start[2]))

	var last := TrailerCatalog.count() - 1
	var tank := TrailerCatalog.at(2)
	var chosen: Array = _seen.get("chosen", [-1, -1, Vector3.ZERO, 0.0, Vector3.ZERO, "", ""])
	check("J1 : deux poussees a droite = 3e remorque (une poussee tenue = une remorque)",
		chosen[0] == 2, "J1 = %s" % chosen[0])
	check("J2 : a gauche depuis la 1re = derniere (le choix boucle)", chosen[1] == last, "J2 = %s" % chosen[1])
	check("J1 : caisse de collision de sa remorque",
		(chosen[2] as Vector3).is_equal_approx(tank.box_size), str(chosen[2]))
	check("J1 : reglage de sa remorque",
		is_equal_approx(float(chosen[3]), _base_top * tank.top_speed_mult), "%.2f km/h" % chosen[3])
	check("J2 : caisse de SA remorque, pas celle de J1",
		(chosen[4] as Vector3).is_equal_approx(TrailerCatalog.at(last).box_size), str(chosen[4]))
	check("HUD J1 : nom de sa remorque", String(chosen[5]).contains(tank.display_name), String(chosen[5]))
	check("HUD J2 : nom de sa remorque", String(chosen[6]).contains(TrailerCatalog.at(last).display_name))

	var locked: Array = _seen.get("locked", [-1, ""])
	check("READY : le stick ne change plus la remorque", locked[0] == 2, "J1 = %s" % locked[0])
	check("READY : la remorque choisie est rappelee", String(locked[1]).contains("READY !")
		and String(locked[1]).contains(tank.display_name), String(locked[1]))
	check("choix garde pour la course suivante", _seen.get("saved", PackedInt32Array()) == PackedInt32Array([2, last]),
		str(_seen.get("saved")))
	# rien ne fuit vers les tests suivants (GameState est un autoload)
	GameState.trailer_choice = PackedInt32Array([0, 0, 0, 0, 0, 0])
