extends PhysicsTest

## Bots tactiques (2026-10-20 : « larguer la remorque au bon moment, juste
## avant un virage, avec un poursuivant colle derriere ; sortir le bouclier
## quand un missile arrive ») : course hors ligne sur la piste n°1, 1 joueur
## immobile et 1 bot dur au BOUCLIER.
##   A. un camion pose 35 m derriere lui tire un missile : le bot sort son
##      bouclier avant l'impact et ne perd aucun PV ;
##   B. sans personne derriere lui, il ne largue rien ;
##   C. un camion colle a l'arriere de sa remorque, dans sa voie : il largue
##      sa remorque (juste avant un virage : niveau dur).

const TICKS := 2400

var _scene: Node3D
var _bot: BotInputSource
var _truck: Truck
var _track: TrackBlockout
var _race_tick: int = -1
var _shooter: Truck
var _shot_tick: int = -1
var _hp0: float = 0.0
var _pursuer: Truck
var _seen: Dictionary = {}


func _test_setup() -> void:
	duration_ticks = TICKS
	GameState.requested_players = 0
	_scene = (load("res://dev/race.tscn") as PackedScene).instantiate() as Node3D
	_scene.set("ready_gate", false)
	_scene.set("player_count", 1)
	_scene.set("bot_count", 1)
	_scene.set("bot_level", BotInputSource.Level.HARD)
	add_child(_scene)
	var p: Object = (_scene.get("players") as Array)[1]
	_truck = p.get("truck") as Truck
	_bot = p.get("input") as BotInputSource
	_track = _scene.get("track") as TrackBlockout
	# pouvoirs du bot (fixes par son numero) : le bouclier seul pour ce test
	var old := TruckPowers.of(_truck)
	if old != null:
		old.name = "OldPowers"
		old.queue_free()
	TruckPowers.setup(_truck, PowerCatalog.Id.SHIELD, -1)


func _total() -> float:
	var h := TruckHealth.of(_truck)
	return h.hp + h.trailer_hp


## Camion pose sur la piste a `back` m derriere le bot, dans sa voie.
func _behind(back: float) -> Transform3D:
	var i := _track.sample_ahead(_bot.index, -back)
	var lat := (_truck.global_position - _track.sample_position(_bot.index)).dot(_track.sample_right(_bot.index))
	return _track.frame_at(i, lat, 0.5)


func _test_tick(t: int) -> void:
	if _race_tick < 0 and int(_scene.get("state")) == RaceManagerNode.State.RACING:
		_race_tick = t
	if _race_tick < 0:
		return
	var s := _track.sample_s(_bot.index)
	# A : missile tire de derriere
	if _shot_tick < 0 and t - _race_tick > 120 and s > 500.0 and s < 900.0:
		_shooter = (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
		_shooter.transform = _behind(35.0)
		_scene.add_child(_shooter)
		_shooter.freeze = true
		TruckPowers.setup(_shooter, PowerCatalog.Id.MISSILE, -1)
		_hp0 = _total()
		_shot_tick = t + 2
	if t == _shot_tick:
		_seen["aimed"] = TruckPowers.of(_shooter).target_ahead() == _truck
		TruckPowers.of(_shooter).use(0)
	if _shot_tick > 0 and t > _shot_tick and t < _shot_tick + 150 and TruckHealth.of(_truck).shield_ticks > 0:
		_seen["shield"] = true
	if _shot_tick > 0 and t == _shot_tick + 160:
		_seen["lost"] = _hp0 - _total()
		_shooter.queue_free()
		_seen["drops_before"] = _bot.drops
	# C : poursuivant colle a l'arriere de la remorque (la course a passe son
	# verrou de largage)
	if _seen.has("lost") and _pursuer == null and t - _race_tick > 400 and _bot.drops == 0:
		_pursuer = (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
		_pursuer.transform = _behind(TruckSpec.CHASSIS_SIZE.z + 16.0 + 6.0)
		_scene.add_child(_pursuer)
		_pursuer.add_to_group(TruckPowers.TARGETS)
		_pursuer.freeze = true
		_seen["pursuer_tick"] = t
	if _pursuer != null and is_instance_valid(_pursuer):
		if _bot.drops > 0 or _truck.is_trailer_detached():
			_seen["dropped"] = [_bot.drops, _truck.is_trailer_detached(), t - int(_seen.get("pursuer_tick", t))]
			_pursuer.queue_free()
		else:
			# il le suit : toujours a la meme place derriere la remorque
			_pursuer.global_transform = _behind(TruckSpec.CHASSIS_SIZE.z + 16.0 + 6.0)


func _test_finish() -> void:
	check("A le missile le vise", _seen.get("aimed") == true, str(_seen.get("aimed")))
	check("A bouclier sorti avant l'impact, aucun PV perdu", _seen.get("shield") == true
		and absf(float(_seen.get("lost", 99.0))) < 0.01, "%s, %s PV" % [_seen.get("shield"), _seen.get("lost")])
	check("B personne derriere : aucun largage", int(_seen.get("drops_before", 9)) == 0, str(_seen.get("drops_before")))
	var d: Array = _seen.get("dropped", [0, false, 0])
	check("C poursuivant colle : il largue sa remorque", int(d[0]) == 1 and bool(d[1]), str(d))
