extends PhysicsTest

## Mode elimination (2026-10-20 : « le dernier a chaque tour, ou toutes les N
## secondes, est elimine, jusqu'au vainqueur ») : piste n°1, 1 joueur immobile
## et 3 bots ; premiere elimination a 5 s de course puis toutes les 4 s (au
## lieu de 30 et 20 s) :
##   A. le premier elimine est le dernier : le joueur immobile ;
##   B. un elimine reste une epave : il ne reapparait pas ;
##   C. trois eliminations, puis le dernier en piste gagne : la course est
##      finie, il est 1er et marque vainqueur, les autres elimines ;
##   D. bandeau pendant la course : le compte a rebours et le dernier.

var _scene: Node3D
var _seen: Dictionary = {}
var _race_tick: int = -1


func _test_setup() -> void:
	duration_ticks = 1600
	GameState.requested_players = 0
	_scene = (load("res://dev/race.tscn") as PackedScene).instantiate() as Node3D
	_scene.set("ready_gate", false)
	_scene.set("player_count", 1)
	_scene.set("bot_count", 3)
	_scene.set("game_mode", GameStateNode.GameMode.ELIMINATION)
	_scene.set("elim_first_ticks", 300)
	_scene.set("elim_every_ticks", 240)
	add_child(_scene)


func _players() -> Array:
	return _scene.get("players")


func _test_tick(t: int) -> void:
	var state := int(_scene.get("state"))
	if _race_tick < 0 and state == RaceManagerNode.State.RACING:
		_race_tick = t
	if _race_tick < 0:
		return
	var elim: Array = _scene.get("eliminated")
	if t == _race_tick + 200:
		_seen["ticker"] = String(_scene.call("ticker_text"))
	if elim.size() >= 1 and not _seen.has("first"):
		_seen["first"] = int(elim[0])
		_seen["first_tick"] = t
	if _seen.has("first_tick") and t == int(_seen["first_tick"]) + 280:
		var truck := (_players()[int(_seen["first"])] as Object).get("truck") as Truck
		_seen["stays"] = truck.is_wrecked()
	if state == RaceManagerNode.State.FINISHED and not _seen.has("end"):
		_seen["end"] = [elim.duplicate(), String(_scene.call("standings_text"))]
		var first := (_scene.call("ranking") as Array)[0] as Object
		var r := (_scene.get("race") as RaceLaps).racer(first.get("truck") as Truck)
		_seen["winner"] = [_players().find(first), r.finished]
		duration_ticks = t + 5


func _test_finish() -> void:
	check("A premier elimine : le joueur immobile", int(_seen.get("first", -1)) == 0, str(_seen.get("first")))
	check("B un elimine reste une epave", _seen.get("stays") == true, str(_seen.get("stays")))
	var end: Array = _seen.get("end", [[], ""])
	var w: Array = _seen.get("winner", [-1, false])
	check("C trois eliminations, puis la course est finie", (end[0] as Array).size() == 3, str(end[0]))
	check("C le dernier en piste gagne, 1er au classement", bool(w[1]) and not (end[0] as Array).has(int(w[0])), str(w))
	var text := String(end[1])
	check("C classement : vainqueur, puis elimines", text.contains("vainqueur") and text.count("éliminé") == 3, text)
	check("D bandeau : compte a rebours et dernier", String(_seen.get("ticker", "")).begins_with("ÉLIMINATION DANS")
		and String(_seen.get("ticker", "")).contains("dernier"), String(_seen.get("ticker", "")))
