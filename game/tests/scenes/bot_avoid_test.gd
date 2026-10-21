extends PhysicsTest

## Bots qui esquivent (2026-10-20 : « les barils explosifs, ils foncent dedans
## s'ils sont au milieu du passage ; pareil quand on largue une remorque ») :
## course hors ligne sur la piste n°1, 1 joueur immobile et 1 bot dur.
##   A. barils : sur les 700 premiers metres (deux barils), il n'en fait
##      sauter aucun ;
##   B. remorque larguee en travers de sa ligne, 130 m devant lui lance : il
##      la contourne sans la toucher ;
##   C. largage juste devant lui, sur la ligne droite de depart du 2e tour
##      (sans tremplin : en l'air, il ne peut ni braquer ni freiner) : une remorque
##      dans l'axe, 40 m devant sur sa ligne, lancee a 60 % de sa vitesse (elle glisse et ralentit) : il la
##      contourne, ou la touche a moins de 8 m/s.

const TICKS := 8400

var _scene: Node3D
var _bot: BotInputSource
var _truck: Truck
var _barrels: int = 0
var _hits: Dictionary = {}
var _b: DetachedTrailer
var _c: DetachedTrailer
var _race_tick: int = -1
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
	var track := _scene.get("track") as TrackBlockout
	track.barrel_hit.connect(func(t: Truck, _i: int) -> void:
		if t == _truck:
			_barrels += 1)
	_truck.hazard_impact.connect(func(o: Node3D, v: float, _tr: bool, _p: Vector3, _n: Vector3) -> void:
		_hits[o] = maxf(float(_hits.get(o, 0.0)), v))


## Remorque larguee sur la ligne du bot, `ahead` m devant lui, en travers ou
## dans l'axe, lancee a `speed` m/s le long de la piste.
func _drop(ahead: float, across: bool, speed: float) -> DetachedTrailer:
	var track := _scene.get("track") as TrackBlockout
	var i := track.sample_ahead(_bot.index, ahead)
	var d := DetachedTrailer.new()
	d.configure(_truck.trailer_type)
	var xf := track.frame_at(i, _bot.line.offset[i], 0.3)
	d.transform = xf.rotated_local(Vector3.UP, PI / 2.0) if across else xf
	_scene.add_child(d)
	d.linear_velocity = track.sample_forward(i) * speed
	return d


func _test_tick(t: int) -> void:
	if _race_tick < 0 and int(_scene.get("state")) == RaceManagerNode.State.RACING:
		_race_tick = t
	if _race_tick < 0:
		return
	var track := _scene.get("track") as TrackBlockout
	var s := track.sample_s(_bot.index)
	if _b == null and s > 700.0 and s < 1000.0:
		_seen["barrels"] = _barrels
		_seen["v_b"] = _truck.linear_velocity.length()
		_b = _drop(130.0, true, 0.0)
	# C : sur une ligne droite (circuit rallonge du 2026-10-20 : la ou etait
	# le cas C, il y a maintenant les virages des docks)
	if _b != null and _c == null and t - _race_tick > 3000 and s > 15.0 and s < 45.0:
		_seen["v_c"] = _truck.linear_velocity.length()
		_c = _drop(40.0, false, _truck.linear_velocity.length() * 0.6)


func _test_finish() -> void:
	check("A barils : aucun ne saute sur les 700 premiers metres", _seen.has("barrels") and int(_seen["barrels"]) == 0,
		str(_seen.get("barrels")))
	check("B remorque en travers a 130 m : contournee sans contact", _b != null and not _hits.has(_b),
		"lance a %.0f km/h, choc %.1f m/s" % [float(_seen.get("v_b", 0.0)) * 3.6, float(_hits.get(_b, 0.0))])
	check("C largage 40 m devant : contournee, ou touchee a moins de 8 m/s", _c != null and float(_hits.get(_c, 0.0)) < 8.0,
		"lance a %.0f km/h, choc %.1f m/s" % [float(_seen.get("v_c", 0.0)) * 3.6, float(_hits.get(_c, 0.0))])
