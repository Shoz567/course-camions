extends PhysicsTest

## Remorque en arene (2026-10-21 : « on ne peut pas lâcher la remorque ; une
## fois détruite, elle ne réapparaît pas tant qu'on n'est pas mort : une
## remorque par vie ») ; dev/arena.tscn, 1 joueur et 1 bot, 3 vies :
##   A. arene : pas de largage (drops_left 0), une remorque par vie ;
##      demander le largage ne detache rien ;
##   B. remorque detruite : 15 s plus tard (la recharge d'un largage finie),
##      toujours pas de nouvelle remorque ;
##   C. tete detruite : il reapparait avec une vie de moins, et une remorque
##      neuve attelee ;
##   D. en course, rien ne change : une remorque detruite revient apres la
##      recharge (TruckCargo.one_per_life faux).

const START := 360

var _scene: Node3D
var _truck: Truck
var _seen: Dictionary = {}


func _test_setup() -> void:
	duration_ticks = START + 900 + 600
	GameState.requested_players = 0
	_scene = (load("res://dev/arena.tscn") as PackedScene).instantiate() as Node3D
	_scene.set("ready_gate", false)
	_scene.set("player_count", 1)
	_scene.set("bot_count", 1)
	add_child(_scene)
	_truck = ((_scene.get("players") as Array)[0] as Object).get("truck") as Truck


func _test_tick(t: int) -> void:
	var cargo := _truck.get_node("Cargo") as TruckCargo
	var health := TruckHealth.of(_truck)
	var lives: Array = _scene.get("lives")
	if t == START:
		# le bot, fige : il ne vient pas detruire le joueur pendant l'attente
		(((_scene.get("players") as Array)[1] as Object).get("truck") as Truck).freeze = true
		_seen["a"] = [cargo.one_per_life, cargo.drops_left]
		_truck.cargo_requested.emit()
	elif t == START + 2:
		_seen["a_drop"] = _truck.is_trailer_detached()
		health.damage_trailer(10000.0, &"test")
	elif t == START + 4:
		_seen["b_lost"] = _truck.is_trailer_detached()
	elif t == START + 900:
		_seen["b"] = _truck.is_trailer_detached()
		_seen["lives0"] = int(lives[0])
		health.damage(10000.0, &"test")
	elif t == START + 900 + 300:
		_seen["c"] = [int(lives[0]), _truck.is_wrecked(), _truck.is_trailer_detached()]
		# D : la meme remorque hors arene revient apres la recharge
		cargo.one_per_life = false
		health.damage_trailer(10000.0, &"test")
	elif t == START + 900 + 305:
		# recharge abregee (30 s sinon)
		cargo.set("_cooldown", 1)
	elif t == START + 900 + 305 + cargo.reattach_timeout_ticks + 30:
		_seen["d"] = _truck.is_trailer_detached()
		duration_ticks = t + 1


func _test_finish() -> void:
	check("A arene : une remorque par vie, aucun largage", _seen.get("a") == [true, 0] and _seen.get("a_drop") == false,
		"%s %s" % [_seen.get("a"), _seen.get("a_drop")])
	check("B detruite : toujours pas de nouvelle remorque 15 s apres", _seen.get("b_lost") == true and _seen.get("b") == true,
		"%s %s" % [_seen.get("b_lost"), _seen.get("b")])
	var c: Array = _seen.get("c", [])
	check("C tete detruite : une vie de moins, remorque neuve", c.size() == 3 and int(c[0]) == int(_seen.get("lives0", 0)) - 1
		and c[1] == false and c[2] == false, "%s (avant : %s vies)" % [c, _seen.get("lives0")])
	check("D hors arene : la remorque revient", _seen.get("d") == false, str(_seen.get("d")))
