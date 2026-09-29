extends PhysicsTest

## Categories de vitesse du menu (GameState.SPEED_CLASSES, facon cylindree) :
##   - quatre camions, un par categorie, plein gaz sur le plat : chacun atteint
##     la vitesse max de sa categorie (+/- 4 %), et plus la categorie est
##     haute, plus le 0 -> 80 km/h est court ;
##   - le reglage de base (default_vehicle.tres) n'est jamais modifie ;
##   - la course lancee depuis le menu (dev/race.tscn) applique la categorie
##     choisie a chaque camion.

const TICKS := 1000

var _trucks: Array[Truck] = []
var _frames: Array[InputFrame] = []
var _t80: PackedInt32Array = [-1, -1, -1, -1]
var _race_top: float = 0.0


func _test_setup() -> void:
	duration_ticks = TICKS
	add_floor(4000.0)
	var base := load("res://vehicles/default_vehicle.tres") as VehicleTuning
	for k in 4:
		var t := (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
		t.tuning = GameStateNode.speed_tuning(base, k)
		t.position = Vector3(k * 40.0, 0.0, 1800.0)
		add_child(t)
		_trucks.append(t)
		var f := InputFrame.new()
		f.throttle = 1.0
		_frames.append(f)
	# course lancee depuis le menu en Ultrasonique
	GameState.speed_class = GameStateNode.SpeedClass.ULTRA
	GameState.requested_players = 1
	var race := (load("res://dev/race.tscn") as PackedScene).instantiate() as Node3D
	race.position = Vector3(0.0, -500.0, 0.0)
	add_child(race)
	var players: Array = race.get("players")
	_race_top = (players[0].truck as Truck).tuning.top_speed_kmh
	race.queue_free()
	GameState.speed_class = GameStateNode.SpeedClass.NORMAL


func _test_tick(t: int) -> void:
	for k in 4:
		_frames[k].tick = t
		_trucks[k].set_input(_frames[k])
		if _t80[k] < 0 and _trucks[k].get_speed_kmh() >= 80.0:
			_t80[k] = t


func _test_finish() -> void:
	var tops := []
	for k in 4:
		tops.append(snappedf(_trucks[k].get_speed_kmh(), 0.1))
	print("  INFO   vitesse finale %s km/h ; 0 -> 80 km/h en %s ticks" % [tops, _t80])
	for k in 4:
		var c: Dictionary = GameStateNode.SPEED_CLASSES[k]
		check_near("%s (%s) : vitesse max (km/h)" % [c["name"], c["cc"]], tops[k], float(c["top_kmh"]),
			float(c["top_kmh"]) * 0.04)
	check("plus la categorie est haute, plus le 0 -> 80 est court",
		_t80[0] > _t80[1] and _t80[1] > _t80[2] and _t80[2] > _t80[3], str(_t80))
	var base := load("res://vehicles/default_vehicle.tres") as VehicleTuning
	check("reglage de base intact", is_equal_approx(base.top_speed_kmh, 150.0), "%.1f" % base.top_speed_kmh)
	check_near("course : categorie du menu appliquee (vitesse max, km/h)", _race_top, 225.0, 0.01)
