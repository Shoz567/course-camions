extends PhysicsTest

## Depart des bots (2026-10-22 : « leur objectif principal, c'est de finir la
## course et pas d'attaquer le joueur. Car au debut, on le voit, ils foncent
## sur le joueur a la place de partir pour faire la course ») : course a
## Playa Del Sol, 5 bots durs, le joueur reste sur la grille sans toucher a
## rien. Avant, chaque bot visait une voie tiree de son numero (-4 / 4 / 0 /
## -8 / 8 m), sans rapport avec sa place sur la grille a 12 : au GO, il
## traversait la grille, et le joueur immobile prenait 1 a 3 chocs en 10 s
## (3 a Playa). Maintenant, sur les 10 s apres le GO :
##   A. aucun bot ne touche le joueur ;
##   B. chacun part faire la course : a plus de 100 m de sa place (a vol
##      d'oiseau, virages compris ; un bot qui resterait autour du joueur
##      ne s'eloignerait pas de 30 m de la grille ; mesure : 140 a 236 m).

const SECONDS := 10

var _race: Node3D
var _saved: Dictionary = {}
var _saved_players: int = 0
var _hits: int = 0
var _go: int = -1
var _starts: Array[Vector3] = []


func _test_setup() -> void:
	duration_ticks = 1500
	_saved = GameState.rules()
	_saved_players = GameState.requested_players
	GameState.requested_players = 1
	GameState.apply_rules({"track": 1, "mode": GameStateNode.GameMode.RACE, "bots": 5,
		"bot_level": BotInputSource.Level.HARD}, 0)
	_race = (load(GameStateNode.track_scene(1)) as PackedScene).instantiate() as Node3D
	_race.set("ready_gate", false)   # le sas READY a son propre test (race_ready_test)
	add_child(_race)


func _test_tick(t: int) -> void:
	var players: Array = _race.get("players")
	if players.is_empty():
		return
	if _go < 0 and RaceManager.state == RaceManagerNode.State.RACING:
		_go = t
		var me := (players[0] as Object).get("truck") as Truck
		me.body_impact.connect(func(_v: float, _r: bool, _a: Vector3, _n: Vector3) -> void: _hits += 1)
		for p: Object in players:
			_starts.append((p.get("truck") as Truck).global_position)
	if _go >= 0 and t - _go >= SECONDS * 60:
		duration_ticks = mini(duration_ticks, t + 1)


func _test_finish() -> void:
	var players: Array = _race.get("players")
	var gone := []
	for i in range(1, players.size()):
		if i < _starts.size():
			gone.append(roundi(((players[i] as Object).get("truck") as Truck).global_position.distance_to(_starts[i])))
	check("A %d s apres le GO : aucun bot ne touche le joueur immobile" % SECONDS, _go >= 0 and _hits == 0,
		"%d choc(s)" % _hits)
	var raced := gone.size() == 5
	for d: int in gone:
		raced = raced and d > 100
	check("B chaque bot part faire la course (> 100 m de sa place)", raced, "%s m" % [gone])
	GameState.apply_rules(_saved, 0)
	GameState.requested_players = _saved_players
