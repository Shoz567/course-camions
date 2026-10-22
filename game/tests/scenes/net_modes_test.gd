extends PhysicsTest

## Modes en ligne (2026-10-21 : « tous les modes disponibles en ligne, à part
## le contre-la-montre ») : l'etat de course que le host diffuse
## (LocalRace.net_state) porte ce que le client ne decide pas : elimines, vies
## en arene, tick de la prochaine elimination. Arene a 2 joueurs :
##   A. l'etat a 9 champs (le 9e : course chargee chez chacun, sas en
##      ligne) ; un client qui l'applique retrouve elimines, vies et
##      prochaine elimination du host (meme sans changement d'etat de course) ;
##   B. un etat de l'ancien protocole (5 champs) est ignore : rien ne change.

var _scene: Node3D
var _seen: Dictionary = {}


func _test_setup() -> void:
	duration_ticks = 10
	GameState.requested_players = 0
	_scene = (load("res://dev/arena.tscn") as PackedScene).instantiate() as Node3D
	_scene.set("ready_gate", false)
	_scene.set("player_count", 2)
	_scene.set("bot_count", 0)
	add_child(_scene)


func _test_tick(t: int) -> void:
	if t != 5:
		return
	# le host : J2 sorti, J1 a une vie, prochaine elimination au tick 9000
	_scene.set("eliminated", [1] as Array[int])
	_scene.set("lives", [1, 0] as Array[int])
	_scene.set("_next_elim", 9000)
	var s: Array = _scene.call("net_state")
	_seen["size"] = s.size()
	# le client, avant de recevoir l'etat
	_scene.set("eliminated", [] as Array[int])
	_scene.set("lives", [3, 3] as Array[int])
	_scene.set("_next_elim", -1)
	_scene.call("apply_net_state", s)
	_seen["applied"] = [_scene.get("eliminated"), _scene.get("lives"), _scene.get("_next_elim")]
	_scene.call("apply_net_state", s.slice(0, 5))
	_seen["old"] = [_scene.get("eliminated"), _scene.get("lives"), _scene.get("_next_elim")]


func _test_finish() -> void:
	check("A etat de course : 9 champs", int(_seen.get("size", 0)) == 9, str(_seen.get("size")))
	check("A le client retrouve elimines, vies et prochaine elimination",
		str(_seen.get("applied")) == str([[1], [1, 0], 9000]), str(_seen.get("applied")))
	check("B ancien protocole ignore", str(_seen.get("old")) == str([[1], [1, 0], 9000]), str(_seen.get("old")))
