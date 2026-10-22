extends PhysicsTest

## Remorque de chaque joueur en course (dev/race.tscn, 2 joueurs). Elle se
## choisit au menu (page de selection, GameState.trailer_choice) ; l'ancien
## choix au stick dans le sas jaune est retire le 2026-10-22 (« il y a
## toujours le texte jaune que je ne veux pas. Maintenant, c'est le menu »).
##   - au chargement : chacun a la remorque gardee dans GameState, sans sas
##     (compte a rebours tout de suite, ni invite ni fleches) ;
##   - le camion prend la caisse et le reglage de SA remorque (VEHICLE_SPEC
##     §5 bis : rapport des vitesses max = rapport des multiplicateurs) ;
##   - le stick pendant le compte a rebours ne change plus rien ;
##   - le choix reste dans GameState pour la course suivante.

var _scene: Node3D
var _players: Array = []
var _seen: Dictionary = {}
var _last: int = 0


func _test_setup() -> void:
	duration_ticks = 30
	_last = TrailerCatalog.count() - 1
	GameState.requested_players = 2
	GameState.trailer_choice = PackedInt32Array([2, _last, 0, 0, 0, 0])
	_scene = (load("res://dev/race.tscn") as PackedScene).instantiate() as Node3D
	add_child(_scene)
	_players = _scene.get("players")


func _stick(device: int, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = device
	e.axis = JOY_AXIS_LEFT_X
	e.axis_value = value
	Input.parse_input_event(e)


func _center(i: int) -> String:
	return String(_players[i].hud.get("_center_text"))


func _test_tick(t: int) -> void:
	match t:
		2:
			_seen["start"] = [_players[0].trailer, _players[1].trailer, _scene.get("state") == 0, _center(0)]
		4:
			_stick(0, 1.0)
			_stick(1, -1.0)
		9:
			_stick(0, 0.0)
			_stick(1, 0.0)
		20:
			var t1: Truck = _players[0].truck
			var t2: Truck = _players[1].truck
			_seen["chosen"] = [_players[0].trailer, _players[1].trailer, t1.trailer_box_size,
				t2.trailer_box_size, t1.tuning.top_speed_kmh / t2.tuning.top_speed_kmh]
			_seen["saved"] = GameState.trailer_choice.slice(0, 2)


func _test_finish() -> void:
	var tank := TrailerCatalog.at(2)
	var last := TrailerCatalog.at(_last)
	var start: Array = _seen.get("start", [-1, -1, false, ""])
	check("au chargement : la remorque du menu pour chacun", start[0] == 2 and start[1] == _last, str(start))
	check("sans sas : compte a rebours, ni invite ni fleches", start[2]
		and not String(start[3]).contains("CARRÉ") and not String(start[3]).contains("◄"), String(start[3]))
	var chosen: Array = _seen.get("chosen", [-1, -1, Vector3.ZERO, Vector3.ZERO, 0.0])
	check("le stick ne change plus la remorque", chosen[0] == 2 and chosen[1] == _last, "%s / %s" % [chosen[0], chosen[1]])
	check("J1 : caisse de collision de sa remorque", (chosen[2] as Vector3).is_equal_approx(tank.box_size), str(chosen[2]))
	check("J2 : caisse de SA remorque, pas celle de J1", (chosen[3] as Vector3).is_equal_approx(last.box_size),
		str(chosen[3]))
	check("reglage de chacun : rapport des vitesses max = rapport des multiplicateurs",
		is_equal_approx(float(chosen[4]), tank.top_speed_mult / last.top_speed_mult),
		"%.4f / %.4f" % [chosen[4], tank.top_speed_mult / last.top_speed_mult])
	check("choix garde pour la course suivante", _seen.get("saved", PackedInt32Array()) == PackedInt32Array([2, _last]),
		str(_seen.get("saved")))
	# rien ne fuit vers les tests suivants (GameState est un autoload)
	GameState.trailer_choice = PackedInt32Array([0, 0, 0, 0, 0, 0])
