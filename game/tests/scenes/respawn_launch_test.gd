extends PhysicsTest

## Reapparition lancee (2026-10-22 : « pour que cela soit plus dynamique, que
## lorsque l'on reapparait on soit lance, de meme pour les bots »).
## dev/race.tscn (ou dev/arena.tscn avec `arena`), 1 joueur et 3 bots durs ; le
## joueur est pilote par un bot dur. Chaque camion est detruit (crash) a
## CRASH_TICKS apres le GO ; a chaque reapparition :
##   A. il repart vers l'avant a la vitesse prevue (LocalRace.launch_for, a
##      10 % pres), et la plupart du temps a plus de 40 km/h ;
##   B. dans les FOLLOW_TICKS qui suivent : aucune nouvelle destruction, et
##      peu de degats de mur (moins de WALL_MAX PV par reapparition, en moyenne).

const CRASH_TICKS: Array[int] = [300, 1500]
const FOLLOW_TICKS := 300
const WALL_MAX := 4.0

@export var arena := false

var _scene: Node3D
var _saved: Array = []
var _go := -1
## Par reapparition : [vitesse vers l'avant 2 ticks apres, vitesse prevue].
var _launches: Array = []
var _pending: Dictionary = {}     # Truck -> tick de reapparition
var _since: Dictionary = {}       # Truck -> tick de sa derniere reapparition
var _wall := 0.0
var _rewrecked := 0


func _test_setup() -> void:
	duration_ticks = 400 + CRASH_TICKS[-1] + 180 + FOLLOW_TICKS + 60
	_saved = [GameState.requested_players, GameState.bot_count, GameState.game_mode, GameState.bot_level,
		GameState.trailer_drops]
	GameState.trailer_drops = 0
	if arena:
		GameState.requested_players = 1
		GameState.bot_count = 3
		GameState.bot_level = BotInputSource.Level.HARD
		GameState.game_mode = GameStateNode.GameMode.ARENA
		_scene = (load("res://dev/arena.tscn") as PackedScene).instantiate() as Node3D
	else:
		GameState.requested_players = 0
		_scene = (load("res://dev/race.tscn") as PackedScene).instantiate() as Node3D
		_scene.set("player_count", 1)
		_scene.set("bot_count", 3)
		_scene.set("bot_level", BotInputSource.Level.HARD)
	_scene.set("ready_gate", false)
	add_child(_scene)
	for p: Object in _scene.get("players"):
		var t := p.get("truck") as Truck
		var h := TruckHealth.of(t)
		h.respawned.connect(func() -> void:
			_pending[t] = Engine.get_physics_frames()
			_since[t] = Engine.get_physics_frames())
		h.damaged.connect(func(a: float, s: StringName) -> void:
			if _since.has(t) and Engine.get_physics_frames() - int(_since[t]) <= FOLLOW_TICKS:
				if s == &"mur":
					_wall += a
				if h.hp <= 0.0:
					_rewrecked += 1)


func _test_tick(t: int) -> void:
	var players: Array = _scene.get("players")
	if RaceManager.state == RaceManagerNode.State.RACING and _go < 0:
		_go = t
		var drv := BotInputSource.new()
		drv.setup(_scene.get("track") as TrackBlockout, (players[0] as Object).get("truck") as Truck,
			BotInputSource.Level.HARD, 7)
		# en arene, il conduit comme les bots de l'arene (LocalRace : bot.arena) ;
		# sans ca, il roulait comme sur un circuit, au milieu de l'arene
		drv.arena = arena
		add_child(drv)
		(players[0] as Object).set("input", drv)
	for tr: Truck in _pending.keys():
		if Engine.get_physics_frames() - int(_pending[tr]) == 2:
			var want := float(_scene.call("launch_for", tr.global_transform))
			_launches.append([snappedf(-tr.linear_velocity.dot(tr.global_basis.z), 0.1), snappedf(want, 0.1)])
			_pending.erase(tr)
	if _go >= 0 and CRASH_TICKS.has(t - _go):
		for p: Object in players:
			TruckHealth.of(p.get("truck") as Truck).crash(&"test")


func _test_finish() -> void:
	GameState.requested_players = _saved[0]
	GameState.bot_count = _saved[1]
	GameState.game_mode = _saved[2]
	GameState.bot_level = _saved[3]
	GameState.trailer_drops = _saved[4]
	var ok := _launches.size() == 8
	var fast := 0
	for l: Array in _launches:
		ok = ok and absf(float(l[0]) - float(l[1])) <= 0.1 * float(l[1]) + 0.5
		if float(l[0]) > 40.0 / 3.6:
			fast += 1
	check("A lance a la vitesse prevue (et le plus souvent > 40 km/h)", ok and fast >= 6,
		"%s (m/s : mesure, prevu)" % [_launches])
	check("B ni nouvelle destruction ni mur juste apres", _rewrecked == 0 and _wall < WALL_MAX * 8.0,
		"%d destruction(s), %.1f PV de mur sur 8 reapparitions" % [_rewrecked, _wall])
