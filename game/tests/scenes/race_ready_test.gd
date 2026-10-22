extends PhysicsTest

## Plus de sas jaune (2026-10-22, « il y a toujours le texte jaune que je ne
## veux pas. Maintenant, c'est le menu ») : remorques et pouvoirs se
## choisissent au menu ; meme lancee sans lui (dev/race.tscn, 2 joueurs), la
## course part sans « [CARRE] POUR ETRE READY » :
##   - le compte a rebours demarre tout de suite, aucune vue n'affiche
##     l'invite CARRE ni le choix de remorque ;
##   - pendant le compte a rebours, personne ne bouge, meme plein gaz ;
##   - course lancee apres 3 s ; boost intact ; au depart, largage verrouille
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


func _axis(device: int, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = device
	e.axis = JOY_AXIS_TRIGGER_RIGHT
	e.axis_value = value
	Input.parse_input_event(e)


func _center(i: int) -> String:
	return String(_players[i].hud.get("_center_text"))


func _test_tick(t: int) -> void:
	var countdown := 0   # LocalRace.State.COUNTDOWN
	match t:
		2:
			_axis(0, 1.0)
			_axis(1, 1.0)
		10:
			_seen["start"] = [_scene.get("state") == countdown, _center(0), _center(1)]
		40:
			var moved := 0.0
			for i in 2:
				moved = maxf(moved, (_players[i].truck as Truck).global_position.distance_to(_starts[i]))
			_seen["moved"] = moved
		56:
			_axis(0, 0.0)
			_axis(1, 0.0)
		245:
			var t1: Truck = _players[0].truck
			_seen["go"] = [_scene.get("state"), t1.get_boost_charge(), t1.is_boosting(),
				String(_players[0].hud.get("_cargo_label").text), String(_players[0].hud.get("_hp_label").text)]


func _test_finish() -> void:
	var start: Array = _seen.get("start", [false, "", ""])
	check("pas de sas : compte a rebours tout de suite", start[0])
	var prompt := false
	for i in [1, 2]:
		prompt = prompt or String(start[i]).contains("CARRÉ") or String(start[i]).contains("REMORQUE")
	check("aucune vue n'affiche l'invite CARRE ni le choix de remorque", not prompt, "%s / %s" % [start[1], start[2]])
	check_below("compte a rebours : personne ne bouge, meme plein gaz (m)", float(_seen.get("moved", 99.0)), 0.05)
	var go: Array = _seen.get("go", [-1, 0.0, true, "", ""])
	check("course lancee apres 3 s de compte a rebours", go[0] == 1, "etat %s" % go[0])
	check("boost intact au depart", go[1] == 1.0 and not go[2])
	check("au depart : largage verrouille (VERROU), PV au HUD",
		String(go[3]).begins_with("VERROU") and go[4] == "100 HP", "« %s » / « %s »" % [go[3], go[4]])
