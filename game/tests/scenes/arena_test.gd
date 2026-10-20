extends PhysicsTest

## Arene stock-car (2026-10-20 : « une arene fermee, sans tours : on se detruit
## avec les pouvoirs et les remorques, le dernier debout gagne ») :
## dev/arena.tscn, 1 joueur immobile et 3 bots durs, 2 vies (au lieu de 3) :
##   A. l'arene : anneau de 160 m autour d'un ilot, mode arene, bots chasseurs ;
##      le menu lance l'arene de l'habillage du circuit choisi ;
##   B. les bots chassent : ils restent au contact de leur proie (moins de 60 m
##      en moyenne sur 15 s, dans une arene de 340 m) et la percutent ;
##   C. vies : detruit une fois, un camion reapparait avec une vie de moins ;
##      la seconde, il sort (son epave reste) ;
##   D. le dernier debout gagne : course finie, 1er au classement, vainqueur ;
##   E. HUD : bandeau ARENE (temps, coeurs), vies a la place des tours.

var _scene: Node3D
var _seen: Dictionary = {}
var _race_tick: int = -1
var _impacts: int = 0
var _gaps: Array[float] = []


func _test_setup() -> void:
	duration_ticks = 2600
	GameState.requested_players = 0
	_scene = (load("res://dev/arena.tscn") as PackedScene).instantiate() as Node3D
	_scene.set("ready_gate", false)
	_scene.set("player_count", 1)
	_scene.set("bot_count", 3)
	_scene.set("bot_level", BotInputSource.Level.HARD)
	_scene.set("arena_lives", 2)
	add_child(_scene)
	var saved := GameState.game_mode
	GameState.game_mode = GameStateNode.GameMode.ARENA
	_seen["menu_scene"] = GameStateNode.track_scene(1)
	GameState.game_mode = saved
	for p: Object in _players():
		(p.get("truck") as Truck).body_impact.connect(func(_v: float, _r: bool, _a: Vector3, _n: Vector3) -> void:
			_impacts += 1)


func _players() -> Array:
	return _scene.get("players")


func _truck(i: int) -> Truck:
	return (_players()[i] as Object).get("truck") as Truck


## Distance moyenne de chaque bot a son camion le plus proche.
func _hunt_gap() -> float:
	var sum := 0.0
	for i in range(1, 4):
		var best := INF
		for j in 4:
			if j != i:
				best = minf(best, _truck(i).global_position.distance_to(_truck(j).global_position))
		sum += best
	return sum / 3.0


func _test_tick(t: int) -> void:
	var state := int(_scene.get("state"))
	if _race_tick < 0 and state == RaceManagerNode.State.RACING:
		_race_tick = t
		var track := _scene.get("track") as TrackBlockout
		var bot := (_players()[1] as Object).get("input") as BotInputSource
		_seen["arena"] = [track.width, int(_scene.get("game_mode")) == GameStateNode.GameMode.ARENA, bot.arena]
	if _race_tick < 0:
		return
	var k := t - _race_tick
	if k >= 120 and k <= 900 and k % 60 == 0:
		_gaps.append(_hunt_gap())
	if k == 900:
		var mean := 0.0
		for g in _gaps:
			mean += g / _gaps.size()
		_seen["hunt"] = [mean, _impacts]
		var hud := (_players()[0] as Object).get("hud") as RaceHud
		_seen["hud"] = [String(_scene.call("ticker_text")), hud.lap_override]
		# C : le bot 1 detruit une fois
		TruckHealth.of(_truck(1)).damage(1000.0, &"test")
	if k == 1150:
		var lives: Array = _scene.get("lives")
		_seen["one"] = [int(lives[1]), _truck(1).is_wrecked()]
		TruckHealth.of(_truck(1)).damage(1000.0, &"test")
	if k == 1400:
		var lives: Array = _scene.get("lives")
		_seen["out"] = [int(lives[1]), (_scene.get("eliminated") as Array).has(1), _truck(1).is_wrecked()]
		# D : le joueur immobile et le bot 2 sortent aussi
		for i: int in [0, 2]:
			(_scene.get("lives") as Array)[i] = 1
			TruckHealth.of(_truck(i)).damage(1000.0, &"test")
	if state == RaceManagerNode.State.FINISHED and not _seen.has("end"):
		var first := (_scene.call("ranking") as Array)[0] as Object
		_seen["end"] = [_players().find(first), String(_scene.call("standings_text"))]
		duration_ticks = t + 5


func _test_finish() -> void:
	check("A arene : 160 m, mode arene, bots chasseurs", _seen.get("arena") == [160.0, true, true], str(_seen.get("arena")))
	check("A le menu lance l'arene de l'habillage choisi", String(_seen.get("menu_scene", "")) == "res://dev/arena_playa.tscn",
		str(_seen.get("menu_scene")))
	var h: Array = _seen.get("hunt", [INF, 0])
	check("B les bots chassent : au contact, des chocs", float(h[0]) < 60.0 and int(h[1]) >= 10,
		"%.0f m en moyenne, %d chocs" % [float(h[0]), int(h[1])])
	check("C detruit une fois : reapparu, une vie de moins", _seen.get("one") == [1, false], str(_seen.get("one")))
	check("C la seconde : sorti, l'epave reste", _seen.get("out") == [0, true, true], str(_seen.get("out")))
	var end: Array = _seen.get("end", [-1, ""])
	check("D le dernier debout gagne (le bot 3)", int(end[0]) == 3 and String(end[1]).contains("vainqueur"), str(end))
	var hud: Array = _seen.get("hud", ["", ""])
	check("E bandeau ARENE et vies au HUD", String(hud[0]).begins_with("ARÈNE") and String(hud[0]).contains("♥")
		and String(hud[1]).begins_with("VIES"), str(hud))
