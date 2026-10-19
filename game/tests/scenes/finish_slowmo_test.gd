extends PhysicsTest

## Ralenti d'arrivee (tache 7.4) :
##   A. courbe : 0,3 tenu, puis retour en douceur, 1 a la fin, jamais au-dela ;
##   B. course a 1 joueur : il passe la ligne -> resultats ET ralenti ; le
##      ralenti s'acheve seul, le jeu revient a vitesse normale ;
##   C. quitter la course en plein ralenti remet le jeu a vitesse normale.

const LocalRace := preload("res://dev/local_race.gd")

var _scene: Node3D
var _seen: Dictionary = {}
var _finish_tick: int = -1


func _test_setup() -> void:
	duration_ticks = 460
	GameState.requested_players = 0
	_scene = (load("res://dev/race.tscn") as PackedScene).instantiate() as Node3D
	_scene.set("ready_gate", false)
	_scene.set("player_count", 1)
	add_child(_scene)


func _test_tick(t: int) -> void:
	if _scene == null:
		if t == _finish_tick + 202:
			_seen["after_exit"] = Engine.time_scale
		return
	var players: Array = _scene.get("players")
	if players.is_empty():
		return
	var truck := (players[0] as Object).get("truck") as Truck
	if t == 220:
		_seen["racing"] = int(_scene.get("state")) == RaceManagerNode.State.RACING
		_finish_tick = t
		_scene.call("_on_race_finished", truck, 1000)
		_seen["finished"] = int(_scene.get("state")) == RaceManagerNode.State.FINISHED
		_seen["scale_now"] = Engine.time_scale
	elif _finish_tick > 0 and t == _finish_tick + 5:
		_seen["scale_hold"] = Engine.time_scale
	elif _finish_tick > 0 and t == _finish_tick + 150:
		_seen["scale_end"] = Engine.time_scale
		_seen["active_end"] = bool(_scene.call("slowmo_active"))
		# C : un nouveau ralenti, puis on quitte la course
		_scene.call("_start_slowmo")
		_seen["restart"] = Engine.time_scale
	elif _finish_tick > 0 and t == _finish_tick + 200:
		_scene.queue_free()
		_scene = null


func _test_finish() -> void:
	var lr: GDScript = LocalRace
	check("courbe : 0,3 au depart et pendant la tenue", is_equal_approx(lr.slowmo_scale(0.0), 0.3)
		and is_equal_approx(lr.slowmo_scale(lr.SLOWMO_HOLD_S - 0.01), 0.3))
	var mono := true
	var prev := 0.0
	for k in 41:
		var v: float = lr.slowmo_scale(lr.SLOWMO_TOTAL_S * k / 40.0)
		mono = mono and v >= prev - 1e-6 and v <= 1.0
		prev = v
	check("courbe : remonte sans jamais redescendre ni depasser 1, 1 a la fin",
		mono and is_equal_approx(lr.slowmo_scale(lr.SLOWMO_TOTAL_S), 1.0) and is_equal_approx(lr.slowmo_scale(-1.0), 1.0))
	check("course : en course quand J1 passe la ligne", bool(_seen.get("racing", false)))
	check("arrivee : resultats et ralenti a 0,3", bool(_seen.get("finished", false))
		and is_equal_approx(float(_seen.get("scale_now", 1.0)), 0.3)
		and is_equal_approx(float(_seen.get("scale_hold", 1.0)), 0.3),
		"%s / %s" % [_seen.get("scale_now"), _seen.get("scale_hold")])
	check("le ralenti s'acheve seul : vitesse normale", is_equal_approx(float(_seen.get("scale_end", 0.0)), 1.0)
		and not bool(_seen.get("active_end", true)), str(_seen.get("scale_end")))
	check("quitter en plein ralenti : vitesse normale", is_equal_approx(float(_seen.get("restart", 1.0)), 0.3)
		and is_equal_approx(float(_seen.get("after_exit", 0.0)), 1.0), str(_seen.get("after_exit")))
	Engine.time_scale = 1.0
