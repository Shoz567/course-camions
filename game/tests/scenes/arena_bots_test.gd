extends PhysicsTest

## Bots d'arene (2026-10-21 : « les bots ont du mal : ils tapent murs et
## obstacles, ils sont trop passifs ») ; dev/arena.tscn, 1 joueur immobile et
## 5 bots durs, 45 s de manche :
##   A. ils ne foncent plus dans les murs : au plus 4 chocs contre un mur sans
##      choc de camion dans les 0,75 s avant (17 avant, la plupart lances a
##      plus de 120 km/h, nitro comprise) ;
##   B. ils vont chercher les bonus (reparation abimes, recharge pouvoirs en
##      attente) : au moins 5 pris ;
##   C. ils se servent de leurs pouvoirs : au moins 10 fois ;
##   D. aucun ne reste coince (2,5 s sous 1,5 m/s).

const RUN_TICKS := 2700
const START := 300

var _scene: Node3D
var _track: TrackBlockout
var _saved: Array = []
var _powers := 0
var _pickups := 0
var _solo_walls := 0
var _stuck := 0
var _slow: Dictionary = {}
var _last_ram: Dictionary = {}


func _test_setup() -> void:
	duration_ticks = START + RUN_TICKS
	_saved = [GameState.requested_players, GameState.bot_count, GameState.game_mode, GameState.arena_minutes,
		GameState.bot_level]
	GameState.requested_players = 1
	GameState.bot_count = 5
	GameState.bot_level = BotInputSource.Level.HARD
	GameState.game_mode = GameStateNode.GameMode.ARENA
	GameState.arena_minutes = 0
	_scene = (load("res://dev/arena.tscn") as PackedScene).instantiate() as Node3D
	_scene.set("ready_gate", false)
	add_child(_scene)
	_track = _scene.get("track") as TrackBlockout
	_track.pickup_taken.connect(func(t: Truck, _k: int, _i: int) -> void:
		if t.name != "Truck1":
			_pickups += 1)
	var players: Array = _scene.get("players")
	for i in range(1, players.size()):
		var t := (players[i] as Object).get("truck") as Truck
		t.truck_impact.connect(func(_o: Truck, _ms: float, _a: bool, _p: Vector3, _n: Vector3) -> void:
			_last_ram[t] = Engine.get_physics_frames())
		t.wall_impact_at.connect(func(v: float, _tr: bool, at: Vector3, _n: Vector3) -> void:
			if v <= 4.0 or Engine.get_physics_frames() - int(_last_ram.get(t, -1000)) <= 45:
				return
			var j := _track.closest_sample(at)
			if absf((at - _track.sample_position(j)).dot(_track.sample_right(j))) > _track.width / 2.0 - 3.0:
				_solo_walls += 1)


func _test_tick(t: int) -> void:
	if t < START:
		return
	var players: Array = _scene.get("players")
	for i in range(1, players.size()):
		var b := (players[i] as Object).get("input") as BotInputSource
		var tr := (players[i] as Object).get("truck") as Truck
		if b.frame.power_left or b.frame.power_right:
			_powers += 1
		if not tr.is_wrecked():
			_slow[i] = int(_slow.get(i, 0)) + 1 if tr.linear_velocity.length() < 1.5 else 0
			if int(_slow[i]) == 150:
				_stuck += 1


func _test_finish() -> void:
	GameState.requested_players = _saved[0]
	GameState.bot_count = _saved[1]
	GameState.game_mode = _saved[2]
	GameState.arena_minutes = _saved[3]
	GameState.bot_level = _saved[4]
	check_below("A chocs contre un mur, pris seuls", float(_solo_walls), 5.0)
	check_above("B bonus pris", float(_pickups), 4.5)
	check_above("C pouvoirs utilises", float(_powers), 9.5)
	check("D aucun bot coince", _stuck == 0, str(_stuck))
