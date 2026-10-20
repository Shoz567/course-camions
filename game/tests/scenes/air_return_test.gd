extends PhysicsTest

## Sortie de route en l'air, piste n°1 : un camion lance en l'air vers le mur
## droit, 8 m en deca, a 30 m/s le long de la piste et 14 m/s en travers, 4 m
## au-dessus de la chaussee (il passe au-dessus du mur de 2,8 m). L'aide qui
## le rabattait vers la piste est retiree (2026-10-20 : « elle rabat trop, ca
## se voit trop ») :
##   A. rien ne le pousse : sa vitesse en travers reste la sienne ;
##   B. il passe le mur, tombe et explose (chute).

var _track: TrackBlockout
var _b: Truck
var _crashed: Array = []
var _v0: float = 0.0
var _v20: float = 0.0


func _test_setup() -> void:
	duration_ticks = 240
	_track = (load("res://tracks/track_01_blockout.tscn") as PackedScene).instantiate() as TrackBlockout
	add_child(_track)
	var r := AutoReset.new()
	r.track = _track
	add_child(r)
	r.truck_crashed.connect(func(t: Truck) -> void: _crashed.append(t))
	_b = _launch(_track.length() - 500.0, 14.0)
	r.watch(_b)


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


func _side_speed(t: Truck) -> float:
	var i := _track.closest_sample(t.global_position)
	return t.linear_velocity.dot(_track.sample_right(i))


func _lat(t: Truck) -> float:
	var i := _track.closest_sample(t.global_position)
	return (t.global_position - _track.sample_position(i)).dot(_track.sample_right(i))


func _test_tick(t: int) -> void:
	if t == 2:
		_v0 = _side_speed(_b)
	if t == 20:
		_v20 = _side_speed(_b)


func _test_finish() -> void:
	check("A pas rabattu : vitesse en travers gardee", _v20 > _v0 - 1.0,
		"%.1f -> %.1f m/s" % [_v0, _v20])
	check("B passe le mur et explose", _crashed.has(_b), "travers %.1f m" % _lat(_b))
