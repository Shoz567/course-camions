extends PhysicsTest

## Depart et rattrapage des bots en course (2026-10-22 : « permettre aux bots
## d'aller plus vite que le joueur pour qu'ils puissent le rattraper ; les
## bots attaquent tous en meme temps des le spawn »). dev/race.tscn, 1 joueur
## et 3 bots durs, sans largage :
##   A. aucun pouvoir pendant le compte a rebours ;
##   B. le premier pouvoir de chaque bot vient au plus tot START_POWER_TICKS
##      apres le GO, jamais deux au meme tick (au moins un tire) ;
##   C. le joueur derriere eux (immobile au depart) : aucun rattrapage ;
##   D. le joueur (pilote par un bot dur) prend de l avance pendant que les 3
##      bots sont retenus (apres 10 s de course) : chacun rattrape selon son retard (de 1 a 1,1
##      de la vitesse max, CATCHUP_*), et nettement (au moins x 1,03).

const AHEAD_TICK := 2400
const HOLD_TICK := 600

var _scene: Node3D
var _drops_saved := 3
var _go := -1
var _early := 0
var _first: Array[int] = [-1, -1, -1]
var _seen: Dictionary = {}


func _test_setup() -> void:
	duration_ticks = AHEAD_TICK + 400
	GameState.requested_players = 0
	_drops_saved = GameState.trailer_drops
	GameState.trailer_drops = 0
	_scene = (load("res://dev/race.tscn") as PackedScene).instantiate() as Node3D
	_scene.set("ready_gate", false)
	_scene.set("player_count", 1)
	_scene.set("bot_count", 3)
	_scene.set("bot_level", BotInputSource.Level.HARD)
	add_child(_scene)


func _test_tick(t: int) -> void:
	var players: Array = _scene.get("players")
	var racing := RaceManager.state == RaceManagerNode.State.RACING
	if racing and _go < 0:
		_go = t
	for i in range(1, players.size()):
		var b := (players[i] as Object).get("input") as BotInputSource
		var fired := b.frame.power_left or b.frame.power_right
		if fired and not racing:
			_early += 1
		if fired and racing and _first[i - 1] < 0:
			_first[i - 1] = t - _go
	if _go < 0:
		return
	var k := t - _go
	if k == 200:
		_seen["behind"] = _catchups(players)
	if k == 201:
		# le joueur conduit (bot dur) ; les 3 bots, retenus a HOLD_TICK
		var drv := BotInputSource.new()
		drv.setup(_scene.get("track") as TrackBlockout, (players[0] as Object).get("truck") as Truck,
			BotInputSource.Level.HARD, 7)
		add_child(drv)
		(players[0] as Object).set("input", drv)
	if k == HOLD_TICK:
		for i in range(1, players.size()):
			((players[i] as Object).get("truck") as Truck).freeze = true
	if k == AHEAD_TICK:
		var race := _scene.get("race") as RaceLaps
		var lead := race.progress((players[0] as Object).get("truck") as Truck)
		var want := []
		for i in range(1, players.size()):
			var behind := lead - race.progress((players[i] as Object).get("truck") as Truck)
			want.append(snappedf(1.0 + LocalRace_catchup_max() * clampf((behind - 40.0) / 400.0, 0.0, 1.0), 0.001))
		_seen["want"] = want
		_seen["ahead"] = _catchups(players)


func _catchups(players: Array) -> Array:
	var out := []
	for i in range(1, players.size()):
		out.append(snappedf(((players[i] as Object).get("truck") as Truck).catchup, 0.001))
	return out


func _test_finish() -> void:
	GameState.trailer_drops = _drops_saved
	check("A aucun pouvoir avant le GO", _early == 0, str(_early))
	var earliest := BotInputSource.START_POWER_TICKS[BotInputSource.Level.HARD]
	var ok := true
	for f in _first:
		ok = ok and (f < 0 or f >= earliest)
	var fired := _first.filter(func(f: int) -> bool: return f >= 0)
	var distinct := {}
	for f in fired:
		distinct[f] = true
	check("B premiers pouvoirs apres le delai (et pas tous au meme tick)", ok and fired.size() >= 1
		and distinct.size() == fired.size(),
		str(_first))
	check("C joueur derriere : aucun rattrapage", _seen.get("behind", []) == [1.0, 1.0, 1.0], str(_seen.get("behind")))
	var ahead: Array = _seen.get("ahead", [])
	var want: Array = _seen.get("want", [])
	var d_ok := ahead.size() == 3 and want.size() == 3
	for i in ahead.size():
		d_ok = d_ok and absf(float(ahead[i]) - float(want[i])) < 0.002 and float(ahead[i]) >= 1.03
	check("D joueur devant : rattrapage selon le retard", d_ok, "%s (attendu %s)" % [ahead, want])


## CATCHUP_MAX du niveau dur, lu sur la scene (LocalRace n'a pas de class_name).
func LocalRace_catchup_max() -> float:
	return float((_scene.get_script() as Script).get_script_constant_map()["CATCHUP_MAX"][BotInputSource.Level.HARD])
