extends PhysicsTest

## Largages limites (2026-10-20 : « limiter le nombre de largages par joueur,
## le choisir au debut d'une course, entre 0 et 5 ; une fois la remorque
## revenue, un delai d'une vingtaine de secondes avant de pouvoir la
## larguer ») :
##   A. TruckCargo : 20 s (rearm_ticks) apres le retour d'une remorque ;
##   B. deux largages permis (recharge raccourcie a 1 s, delai a 2 s pour le
##      test) : le premier part ; la remorque revenue, un appui pendant le delai
##      ne fait rien (« largage dans ») ; apres, le second part ; ensuite plus
##      rien (« PLUS DE LARGAGE »), deux remorques sur la route en tout ;
##   C. zero largage permis : rien ne part jamais ;
##   D. menu : une ligne LARGAGES de 0 a 5, le choix va dans GameState ;
##   E. course (dev/race.tscn) : au GO, chaque camion a les largages du menu ;
##   F. en ligne, largage predit refuse par le host (undo_drop) : rendu ;
##   G. camion reapparu avec une remorque neuve : le meme delai avant le
##      largage qu'au retour d'une remorque.

var _a: Truck
var _z: Truck
var _ca: TruckCargo
var _cz: TruckCargo
var _drops_a: int = 0
var _drops_z: int = 0
var _seen: Dictionary = {}
var _menu: MainMenu
var _race: Node3D
var _saved_drops: int = 3


func _test_setup() -> void:
	duration_ticks = 920
	_saved_drops = GameState.trailer_drops
	add_floor(2000.0)
	_a = TruckTestUtil.spawn_truck(self, Vector3(0.0, 0.0, 0.0))
	_z = TruckTestUtil.spawn_truck(self, Vector3(300.0, 0.0, 0.0))
	_ca = _a.get_node(^"Cargo") as TruckCargo
	_cz = _z.get_node(^"Cargo") as TruckCargo
	_seen["rearm_default"] = _ca.rearm_ticks
	_ca.cooldown_ticks = 60
	_ca.rearm_ticks = 120
	_ca.drops_left = 2
	_cz.drops_left = 0
	_ca.dropped.connect(func(_t: DetachedTrailer) -> void: _drops_a += 1)
	_cz.dropped.connect(func(_t: DetachedTrailer) -> void: _drops_z += 1)


func _press(t: Truck, on: bool) -> void:
	var f := InputFrame.new()
	f.cargo = on
	t.set_input(f)


## Appui de largage aux ticks voulus ; A s'eloigne de chaque remorque posee
## (place libre pour la suivante).
func _test_tick(t: int) -> void:
	var press := t in [10, 40, 110, 210, 600]
	_press(_a, press)
	_press(_z, press)
	match t:
		12:
			_seen["first"] = [_drops_a, _ca.drops_left]
			_a.reset_to(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, -80.0)))
		42:
			_seen["while_away"] = _drops_a
		110:
			# revenue (1 s de recharge, vers le tick 72) : delai de 2 s en cours
			_seen["rearm"] = [not _a.is_trailer_detached(), _ca.status_text()]
		112:
			_seen["refused"] = _drops_a
		205:
			_seen["ready_text"] = _ca.status_text()
		212:
			_seen["second"] = [_drops_a, _ca.drops_left]
			_a.reset_to(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, -160.0)))
		598:
			_seen["none_text"] = _ca.status_text()
		602:
			_seen["after"] = _drops_a
			_seen["z"] = [_drops_z, _cz.status_text()]
			_cz.drops_left = 1
			_cz.undo_drop()
			_seen["undo"] = _cz.drops_left
			TruckHealth.of(_z).damage(1000.0, &"test")
			# D : le menu
			_menu = (load("res://ui/main_menu.tscn") as PackedScene).instantiate() as MainMenu
			_menu.auto_change_scene = false
			add_child(_menu)
		606:
			_menu.select_drops(4)
			var pressed := -1
			for k in _menu.drop_buttons.size():
				if _menu.drop_buttons[k].button_pressed:
					pressed = k
			_seen["menu"] = [_menu.drop_buttons.size(), GameState.trailer_drops, pressed]
			_menu.queue_free()
			# E : la course pose les largages du menu au GO
			GameState.requested_players = 0
			_race = (load("res://dev/race.tscn") as PackedScene).instantiate() as Node3D
			_race.set("ready_gate", false)
			_race.set("player_count", 1)
			_race.position = Vector3(0.0, -500.0, 0.0)
			add_child(_race)
		900:
			_seen["respawn"] = [_z.is_wrecked(), _cz.status_text()]
		910:
			var p: Object = (_race.get("players") as Array)[0]
			var c := (p.get("truck") as Truck).get_node(^"Cargo") as TruckCargo
			_seen["race"] = c.drops_left


func _test_finish() -> void:
	GameState.trailer_drops = _saved_drops
	check("A delai apres le retour : 20 s", int(_seen.get("rearm_default", 0)) == 1200, str(_seen.get("rearm_default")))
	check("B premier largage (il en reste 1)", _seen.get("first") == [1, 1], str(_seen.get("first")))
	check("B remorque revenue : un appui pendant le delai ne largue rien",
		int(_seen.get("refused", 9)) == 1 and int(_seen.get("while_away", 9)) == 1
		and (_seen.get("rearm", [false, ""]) as Array)[0] == true
		and String((_seen.get("rearm", [false, ""]) as Array)[1]).begins_with("largage dans"), str(_seen))
	check("B apres le delai : second largage (plus aucun)", String(_seen.get("ready_text", "")).begins_with("REMORQUE PRETE")
		and _seen.get("second") == [2, 0], "%s %s" % [_seen.get("ready_text"), _seen.get("second")])
	check("B ensuite : plus rien, « PLUS DE LARGAGE »", int(_seen.get("after", 9)) == 2
		and String(_seen.get("none_text", "")) == "PLUS DE LARGAGE", "%s %s" % [_seen.get("after"), _seen.get("none_text")])
	var z: Array = _seen.get("z", [9, ""])
	check("C zero largage permis : rien ne part", int(z[0]) == 0 and String(z[1]) == "PLUS DE LARGAGE", str(z))
	check("D menu : LARGAGES de 0 a 5, choix enregistre", _seen.get("menu") == [6, 4, 4], str(_seen.get("menu")))
	check("F largage predit refuse : rendu", int(_seen.get("undo", 0)) == 2, str(_seen.get("undo")))
	var r: Array = _seen.get("respawn", [true, ""])
	check("G reapparu : delai avant le largage", not bool(r[0]) and String(r[1]).begins_with("largage dans"), str(r))
	check("E course : au GO, les largages du menu", int(_seen.get("race", -9)) == 4, str(_seen.get("race")))
