extends PhysicsTest

## Tours et classement chez un client en ligne (2026-10-22, essai de bout en
## bout host + client sur ce PC : le client affichait un tour de retard, et
## ses checkpoints restaient figes, d'ou des positions inversees). Piste n°1,
## un RaceLaps du host et un RaceLaps miroir (client) ; a chaque
## racer_updated du host, l'etat part au miroir comme en ligne
## (NetRace.racer_data -> RaceLaps.apply_remote). Deux camions figes ; A fait
## un tour et demi, B un demi-tour, puis A finit (finish_now) :
##   A. apres chaque checkpoint, le miroir a le meme tour affiche, le meme
##      checkpoint attendu et le meme classement que le host ;
##   B. il emet autant de lap_completed et un race_finished, comme le host.

const START := 10

var _track: TrackBlockout
var _host: RaceLaps
var _mirror: RaceLaps
var _a: Truck
var _b: Truck
var _plan: Array = []             # [tick, camion, checkpoint] ; checkpoint -1 : finish_now
var _diffs: Array = []
var _checked := 0
var _laps := [0, 0]
var _finishes := [0, 0]


func _test_setup() -> void:
	duration_ticks = 200
	_track = (load("res://tracks/track_01_blockout.tscn") as PackedScene).instantiate() as TrackBlockout
	add_child(_track)
	_host = _laps_node(false)
	_mirror = _laps_node(true)
	_a = _frozen(Vector3(3000, 0, 3000))
	_b = _frozen(Vector3(3100, 0, 3000))
	for r: RaceLaps in [_host, _mirror]:
		r.watch(_a)
		r.watch(_b)
	_host.racer_updated.connect(func(t: Truck) -> void:
		var d := NetRace.racer_data(_host.racer(t))
		_mirror.apply_remote(t, int(d[0]), int(d[1]), int(d[2]), int(d[3]), int(d[4]), int(d[5]), bool(d[6]), int(d[7])))
	_host.lap_completed.connect(func(_t: Truck, _l: int, _lt: int) -> void: _laps[0] += 1)
	_mirror.lap_completed.connect(func(_t: Truck, _l: int, _lt: int) -> void: _laps[1] += 1)
	_host.race_finished.connect(func(_t: Truck, _tt: int) -> void: _finishes[0] += 1)
	_mirror.race_finished.connect(func(_t: Truck, _tt: int) -> void: _finishes[1] += 1)
	var n := _track.checkpoint_count
	var tick := START + 5
	for k in n + n / 2:
		_plan.append([tick, _a, k % n])
		tick += 1
		if k < n / 2:
			_plan.append([tick, _b, k])
			tick += 1
	_plan.append([tick, _a, -1])


func _laps_node(mirror: bool) -> RaceLaps:
	var r := RaceLaps.new()
	r.track = _track
	r.total_laps = 3
	r.mirror = mirror
	add_child(r)
	return r


func _frozen(p: Vector3) -> Truck:
	var t := (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
	t.transform = Transform3D(Basis.IDENTITY, p)
	add_child(t)
	t.freeze = true
	return t


func _test_tick(t: int) -> void:
	if t == START:
		_host.start()
		_mirror.start()
	for e: Array in _plan:
		if int(e[0]) != t:
			continue
		var truck := e[1] as Truck
		if int(e[2]) < 0:
			_host.finish_now(truck)
		else:
			_track.checkpoint_passed.emit(truck, int(e[2]))
		for x: Truck in [_a, _b]:
			var h := [_host.display_lap(x), _host.racer(x).next_cp, _host.position(x)]
			var m := [_mirror.display_lap(x), _mirror.racer(x).next_cp, _mirror.position(x)]
			_checked += 1
			if h != m and _diffs.size() < 5:
				_diffs.append([t, "A" if x == _a else "B", h, m])


func _test_finish() -> void:
	check("A meme tour, checkpoint et classement chez le client", _checked > 40 and _diffs.is_empty(),
		"%d comparaisons, ecarts (tick, camion, host [tour, cp, place], client) %s" % [_checked, _diffs])
	check("B memes tours et arrivee", _laps[0] >= 1 and _laps == [_laps[0], _laps[0]] and _finishes == [1, 1],
		"tours %s, arrivees %s" % [_laps, _finishes])
