extends PhysicsTest

## Contre-la-montre (2026-10-20 : « seul sur la piste, tu cours contre le
## fantome de ton meilleur tour enregistre ») :
##   A. TimeTrial : un tour boucle devient le record et le fantome ; rejoue
##      au meme instant du tour, il est la ou etait le camion ;
##   B. un tour plus lent ne remplace pas le record ;
##   C. le record et le fantome sont sauvegardes, puis relus ;
##   D. course en mode contre-la-montre (2 joueurs et 3 bots demandes) : un
##      seul camion, sans pouvoir ; au GO, aucun largage ; bandeau du record.

const TEST_PATH := "user://time_trial_test.ghost"

var _track: TrackBlockout
var _race: RaceLaps
var _truck: Truck
var _tt: TimeTrial
var _lap_tick: int = -1
var _rec_pos: Dictionary = {}
var _scene: Node3D
var _seen: Dictionary = {}


func _test_setup() -> void:
	duration_ticks = 520
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)
	_track = (load("res://tracks/track_01_blockout.tscn") as PackedScene).instantiate() as TrackBlockout
	add_child(_track)
	_race = RaceLaps.new()
	_race.track = _track
	add_child(_race)
	_truck = (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
	_truck.transform = _track.frame_at(0, 0.0, 1.0)
	add_child(_truck)
	_truck.freeze = true
	_race.watch(_truck)
	_tt = TimeTrial.new()
	_tt.path = TEST_PATH
	add_child(_tt)
	_tt.setup(_race, _truck, 0, 1)


## Pose du camion `k` ticks apres le debut du tour : il avance sur la piste.
func _pose(k: int) -> Transform3D:
	return _track.frame_at(_track.index_at_s(float(k) * 2.0), 3.0, 1.0)


func _test_tick(t: int) -> void:
	if t == 2:
		_race.start()
		var r := _race.racer(_truck)
		r.lap = 1
		r.lap_start_tick = _race.start_tick
		_lap_tick = _race.start_tick
	if _lap_tick < 0:
		return
	var k := Engine.get_physics_frames() - _lap_tick
	if t < 130:
		_truck.global_transform = _pose(k)
		_rec_pos[k] = _truck.global_position
	if t == 130:
		# tour boucle en k ticks : record
		_race.lap_completed.emit(_truck, 1, k)
		_seen["record"] = [_tt.best_ticks, _tt.ghost_frames.size() / TimeTrial.STRIDE]
		var r := _race.racer(_truck)
		r.lap = 2
		r.lap_start_tick = Engine.get_physics_frames()
		_seen["ghost40"] = _tt.ghost_pose(40.0).origin.distance_to(_rec_pos.get(40, Vector3.INF))
		_seen["ghost41"] = _tt.ghost_pose(41.0).origin.distance_to(
			(_rec_pos.get(40, Vector3.ZERO) as Vector3).lerp(_rec_pos.get(42, Vector3.ZERO), 0.5))
		# tour plus lent : rien ne change
		_race.lap_completed.emit(_truck, 2, k + 200)
		_seen["slower"] = _tt.best_ticks
		_tt.persist = true
		_tt._save()
		var again := TimeTrial.new()
		again.path = TEST_PATH
		add_child(again)
		again.setup(_race, _truck, 0, 1)
		_seen["loaded"] = [again.best_ticks, again.ghost_frames.size() == _tt.ghost_frames.size()]
		again.queue_free()
		DirAccess.remove_absolute(TEST_PATH)
		# D : la course en mode contre-la-montre
		GameState.requested_players = 0
		_scene = (load("res://dev/race.tscn") as PackedScene).instantiate() as Node3D
		_scene.set("ready_gate", false)
		_scene.set("player_count", 2)
		_scene.set("bot_count", 3)
		_scene.set("game_mode", GameStateNode.GameMode.TIME_TRIAL)
		_scene.position = Vector3(0.0, -400.0, 0.0)
		add_child(_scene)
		var ps: Array = _scene.get("players")
		var truck := (ps[0] as Object).get("truck") as Truck
		_seen["mode"] = [ps.size(), TruckPowers.of(truck) == null, _scene.get("time_trial") != null]
	if t == 500:
		var ps: Array = _scene.get("players")
		var truck := (ps[0] as Object).get("truck") as Truck
		var tt := _scene.get("time_trial") as TimeTrial
		_seen["race"] = [int(_scene.get("state")) == RaceManagerNode.State.RACING,
			(truck.get_node(^"Cargo") as TruckCargo).drops_left, tt.ticker_text().begins_with("CONTRE-LA-MONTRE"),
			tt.persist]


func _test_finish() -> void:
	var rec: Array = _seen.get("record", [-1, 0])
	check("A tour boucle : record et fantome", int(rec[0]) > 100 and int(rec[1]) > 50, str(rec))
	check("A fantome rejoue au meme instant du tour : a la place du camion",
		float(_seen.get("ghost40", INF)) < 0.01 and float(_seen.get("ghost41", INF)) < 0.05,
		"%.3f / %.3f m" % [float(_seen.get("ghost40", INF)), float(_seen.get("ghost41", INF))])
	check("B tour plus lent : record garde", int(_seen.get("slower", -1)) == int(rec[0]), str(_seen.get("slower")))
	check("C sauvegarde puis relu", _seen.get("loaded") == [int(rec[0]), true], str(_seen.get("loaded")))
	check("D un seul camion, sans pouvoir, chrono actif", _seen.get("mode") == [1, true, true], str(_seen.get("mode")))
	check("D au GO : aucun largage, bandeau du record, rien d'ecrit en test",
		_seen.get("race") == [true, 0, true, false], str(_seen.get("race")))
