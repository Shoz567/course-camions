extends PhysicsTest

## HUD de course refait (2026-10-19 : « comme RL, le cercle avec les CD et la
## vitesse ; ameliorer l'affichage en haut a gauche ») ; course a 1 joueur et
## 1 bot (dev/race.tscn), pouvoirs MISSILE / BOOMERANG :
##   A. carte du haut a gauche : position « 2e/2 » ou « 1er/2 », nom, tour,
##      bordure a la couleur du joueur ;
##   B. cadran : vitesse = celle du camion, nitro = sa jauge ;
##   C. pastilles des pouvoirs : noms courts ; pret (1) avant le tir, en
##      recharge apres (secondes restantes = TruckPowers.seconds_left) ;
##   D. emplacement vide : pastille vide.

var _scene: Node3D
var _seen: Dictionary = {}


func _test_setup() -> void:
	duration_ticks = 260
	GameState.requested_players = 0
	GameState.power_left[0] = PowerCatalog.Id.MISSILE
	GameState.power_right[0] = PowerCatalog.Id.BOOMERANG
	_scene = (load("res://dev/race.tscn") as PackedScene).instantiate() as Node3D
	_scene.set("ready_gate", false)
	_scene.set("player_count", 1)
	_scene.set("bot_count", 1)
	add_child(_scene)


func _test_tick(t: int) -> void:
	var p: Object = (_scene.get("players") as Array)[0]
	var hud := p.get("hud") as RaceHud
	var truck := p.get("truck") as Truck
	var dial := hud.get("_dial") as HudDial
	if t == 200:
		_seen["pos"] = String((hud.get("_pos") as Label).text)
		_seen["name"] = String((hud.get("_name") as Label).text)
		_seen["lap"] = String((hud.get("_lap") as Label).text)
		_seen["accent"] = hud.accent
		_seen["ready"] = [float(dial.powers[0].get("ready", 0.0)), String(dial.powers[0].get("name", "")),
			String(dial.powers[1].get("name", ""))]
		TruckPowers.of(truck).use(0)
	if t == 210:
		_seen["speed"] = [dial.speed_kmh, roundi(absf(truck.get_speed_kmh()))]
		_seen["boost"] = [dial.boost, truck.get_boost_charge()]
		_seen["after"] = [float(dial.powers[0].get("ready", 1.0)), int(dial.powers[0].get("left", 0)),
			TruckPowers.of(truck).seconds_left(0)]


func _test_finish() -> void:
	var pos := String(_seen.get("pos", ""))
	check("carte : position sur 2, nom, tour", pos.ends_with("/2") and String(_seen.get("name", "")).begins_with("J1")
		and String(_seen.get("lap", "")).begins_with("TOUR"), "%s %s %s" % [pos, _seen.get("name"), _seen.get("lap")])
	check("carte : couleur du joueur", (_seen.get("accent", Color.BLACK) as Color).is_equal_approx(UiKit.PLAYER_COLORS[0]))
	var sp: Array = _seen.get("speed", [0, 1])
	var bo: Array = _seen.get("boost", [0.0, 1.0])
	check("cadran : vitesse et nitro du camion", int(sp[0]) == int(sp[1]) and is_equal_approx(float(bo[0]), float(bo[1])),
		"%s %s" % [sp, bo])
	var r: Array = _seen.get("ready", [0.0, "", ""])
	check("pastilles : noms courts, pret avant le tir", is_equal_approx(float(r[0]), 1.0) and r[1] == "MISSILE"
		and r[2] == PowerCatalog.short_name(PowerCatalog.Id.BOOMERANG), str(r))
	var a: Array = _seen.get("after", [1.0, 0, 1])
	check("pastille : en recharge apres le tir, secondes du pouvoir", float(a[0]) < 0.1 and int(a[1]) == int(a[2])
		and int(a[1]) > 0, str(a))
	GameState.power_left[0] = -1
	GameState.power_right[0] = -1
