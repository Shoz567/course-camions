extends PhysicsTest

## Arene : un joueur passif ne gagne pas contre des bots durs (2026-10-22 :
## immobile, il finissait en tete 4 manches sur 9, les durs s'eliminant entre
## eux ; dans l'une, aucun ne l'avait touche en 4 min). dev/arena.tscn, le
## joueur immobile contre 4 bots durs, manche de 3 min (le lanceur coupe a
## 12 000 ticks) :
##   A. il perd au moins 2 de ses 3 vies (chocs et pouvoirs) ;
##   B. il ne finit pas en tete (vies, puis PV, comme le classement) ;
##   C. la manche se termine (temps limite ou dernier debout).

const MINUTES := 3

var _scene: Node3D
var _saved: Array = []
var _hits := 0


func _test_setup() -> void:
	duration_ticks = 300 + MINUTES * 3600 + 120
	_saved = [GameState.requested_players, GameState.bot_count, GameState.game_mode, GameState.arena_minutes,
		GameState.bot_level]
	GameState.requested_players = 1
	GameState.bot_count = 4
	GameState.bot_level = BotInputSource.Level.HARD
	GameState.game_mode = GameStateNode.GameMode.ARENA
	GameState.arena_minutes = MINUTES
	_scene = (load("res://dev/arena.tscn") as PackedScene).instantiate() as Node3D
	_scene.set("ready_gate", false)
	add_child(_scene)
	var me := ((_scene.get("players") as Array)[0] as Object).get("truck") as Truck
	me.truck_impact.connect(func(_o: Truck, ms: float, _a: bool, _p: Vector3, _n: Vector3) -> void:
		if ms > 4.0:
			_hits += 1)


func _test_finish() -> void:
	GameState.requested_players = _saved[0]
	GameState.bot_count = _saved[1]
	GameState.game_mode = _saved[2]
	GameState.arena_minutes = _saved[3]
	GameState.bot_level = _saved[4]
	var lives: Array = _scene.get("lives")
	var players: Array = _scene.get("players")
	var score := func(i: int) -> float:
		var h := TruckHealth.of((players[i] as Object).get("truck") as Truck)
		return int(lives[i]) * 1000.0 + (h.hp + h.trailer_hp if h != null and int(lives[i]) > 0 else 0.0)
	var mine: float = score.call(0)
	var ahead := 0
	for i in range(1, lives.size()):
		if float(score.call(i)) >= mine:
			ahead += 1
	check("A le joueur immobile perd au moins 2 vies", int(lives[0]) <= 1, "%d vie(s), %d chocs" % [int(lives[0]), _hits])
	check("B il ne finit pas en tete", ahead >= 1, "%d devant ou a egalite, vies %s" % [ahead, lives])
	check("C la manche se termine", RaceManager.state == RaceManagerNode.State.FINISHED,
		"%d" % RaceManager.state)
