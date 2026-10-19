extends PhysicsTest

## Plus dur de sortir de route (2026-10-19), piste n°1 : deux camions lances
## en l'air vers le mur droit, 8 m en deca, a 30 m/s le long de la piste et
## 14 m/s en travers, 4 m au-dessus de la chaussee (ils passeraient au-dessus
## du mur de 2,8 m) :
##   A. avec l'aide en l'air (AutoReset.air_return) : rabattu, il retombe sur
##      la chaussee et n'explose pas ;
##   B. sans l'aide (temoin) : il passe le mur, tombe et explose (chute) ;
##   C. un camion en l'air qui revient deja vers la piste n'est pas pousse :
##      meme vitesse en travers que son jumeau sans l'aide.

var _track: TrackBlockout
var _a: Truck
var _b: Truck
var _c: Truck
var _c2: Truck
var _crashed: Array = []
var _landed_lat: float = INF
var _seen: Dictionary = {}


func _test_setup() -> void:
	duration_ticks = 240
	_track = (load("res://tracks/track_01_blockout.tscn") as PackedScene).instantiate() as TrackBlockout
	add_child(_track)
	var with_aid := _reset(true)
	var without := _reset(false)
	_a = _launch(100.0, 14.0)
	_b = _launch(_track.length() - 500.0, 14.0)
	_c = _launch(200.0, -6.0)
	_c2 = _launch(215.0, -6.0)
	with_aid.watch(_a)
	with_aid.watch(_c)
	without.watch(_b)
	without.watch(_c2)


func _reset(aid: bool) -> AutoReset:
	var r := AutoReset.new()
	r.track = _track
	r.air_return = aid
	add_child(r)
	r.truck_crashed.connect(func(t: Truck) -> void: _crashed.append(t))
	return r


func _launch(s: float, v_side: float) -> Truck:
	var i := roundi(s / (_track.length() / _track.sample_count()))
	var xf := _track.frame_at(i, _track.width / 2.0 - 8.0, 4.0)
	var t := (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
	t.transform = xf
	add_child(t)
	var h := TruckHealth.of(t)
	h.respawn_provider = func(tr: Truck) -> Transform3D: return _track.get_respawn_transform(tr.global_position)
	t.linear_velocity = -xf.basis.z * 30.0 + xf.basis.x * v_side + Vector3.UP * 3.0
	return t


func _lat(t: Truck) -> float:
	var i := _track.closest_sample(t.global_position)
	return (t.global_position - _track.sample_position(i)).dot(_track.sample_right(i))


func _test_tick(t: int) -> void:
	if t == 20:
		for pair: Array in [["c_v", _c], ["c2_v", _c2]]:
			var tr := pair[1] as Truck
			var i := _track.closest_sample(tr.global_position)
			_seen[pair[0]] = tr.linear_velocity.dot(_track.sample_right(i))
	if _landed_lat == INF and t > 5 and _a.wheels_on_ground() >= 2:
		_landed_lat = _lat(_a)


func _test_finish() -> void:
	check("A avec l'aide : retombe sur la chaussee", absf(_landed_lat) < _track.width / 2.0,
		"travers %.1f m (bord %.1f)" % [_landed_lat, _track.width / 2.0])
	check("A avec l'aide : n'explose pas", not _crashed.has(_a))
	check("B sans l'aide (temoin) : passe le mur et explose", _crashed.has(_b), "travers %.1f m" % _lat(_b))
	check("C revient deja vers la piste : pas pousse (comme son jumeau)",
		absf(float(_seen.get("c_v", 0.0)) - float(_seen.get("c2_v", 9.0))) < 0.3,
		"%.2f / %.2f m/s" % [float(_seen.get("c_v", 0.0)), float(_seen.get("c2_v", 0.0))])
