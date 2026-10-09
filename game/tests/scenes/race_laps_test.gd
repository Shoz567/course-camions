extends PhysicsTest

## RaceLaps (taches 2.3, 2.5, 2.8) sur la piste n°1. Les checkpoints sont
## emis par le signal de la piste, au tick voulu, pour des camions figes hors
## piste ; le mauvais sens se mesure sur un vrai camion qui roule.
##   A. 3 tours dans l'ordre : temps 90 / 80 / 110 ticks, meilleur 80, arrivee
##      a 280 ticks, un seul race_finished, plus rien ne compte ensuite.
##   B. raccourci (checkpoints 6 a 11 sautes) : aucun tour compte.
##   C. demi-tour sur la ligne (checkpoint 19 puis 0) : aucun tour compte.
##   Avant le depart, rien ne compte.
##   D. camion qui roule a contre-sens : MAUVAIS SENS leve ; E dans le bon
##      sens : jamais.
##   F. reapparition bridee : un camion qui attend le checkpoint 3 et tombe
##      pres du 6 reapparait AVANT le 3.

const START := 10

var _track: TrackBlockout
var _race: RaceLaps
var _a: Truck
var _b: Truck
var _c: Truck
var _d: Truck
var _e: Truck
var _f: Truck
var _fd: InputFrame = InputFrame.new()
var _fe: InputFrame = InputFrame.new()
var _plan: Dictionary = {}        # tick -> Array de [camion, checkpoint]
var _laps: Dictionary = {}        # Truck -> PackedInt32Array
var _finishes: Dictionary = {}    # Truck -> nombre de race_finished
var _wrong: Dictionary = {}       # Truck -> vrai si MAUVAIS SENS leve un jour
var _respawn_s: float = -1.0


func _test_setup() -> void:
	duration_ticks = 400
	_track = (load("res://tracks/track_01_blockout.tscn") as PackedScene).instantiate() as TrackBlockout
	add_child(_track)
	_race = RaceLaps.new()
	_race.track = _track
	_race.total_laps = 3
	add_child(_race)
	_race.lap_completed.connect(func(t: Truck, _lap: int, ticks: int) -> void:
		# PackedInt32Array est un type valeur : on reaffecte apres l'ajout
		var arr: PackedInt32Array = _laps.get(t, PackedInt32Array())
		arr.append(ticks)
		_laps[t] = arr)
	_race.race_finished.connect(func(t: Truck, _total: int) -> void:
		_finishes[t] = int(_finishes.get(t, 0)) + 1)
	_race.wrong_way_changed.connect(func(t: Truck, wrong: bool) -> void:
		if wrong:
			_wrong[t] = true)
	_a = _frozen(Vector3(3000, 0, 3000))
	_b = _frozen(Vector3(3100, 0, 3000))
	_c = _frozen(Vector3(3200, 0, 3000))
	var near6 := _track.index_at_s(_track.checkpoint_s(6))
	var off := _track.sample_position(near6) + _track.sample_right(near6) * 20.0
	_f = _frozen(Vector3(off.x, 0.5, off.z))
	# D a contre-sens et E dans le bon sens, sur la ligne droite de depart
	var xd := _track.frame_at(_track.index_at_s(120.0), -5.0, 0.0)
	xd.basis = xd.basis * Basis(Vector3.UP, PI)
	_d = _spawn(xd)
	_e = _spawn(_track.frame_at(_track.index_at_s(40.0), 5.0, 0.0))
	for t in [_a, _b, _c, _d, _e, _f]:
		_race.watch(t)
	_plan_events()


func _frozen(p: Vector3) -> Truck:
	var t := _spawn(Transform3D(Basis.IDENTITY, p))
	t.freeze = true
	return t


func _spawn(xf: Transform3D) -> Truck:
	var t := (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
	t.transform = xf
	add_child(t)
	return t


func _at(tick_: int, truck: Truck, cp: int) -> void:
	if not _plan.has(tick_):
		_plan[tick_] = []
	(_plan[tick_] as Array).append([truck, cp])


func _plan_events() -> void:
	var n := _track.checkpoint_count
	_at(5, _a, 0)                                  # avant le depart : ignore
	# A : ligne a 20, puis 3 tours ; lignes a 100, 180, 290
	var lines := [20, 100, 180, 290]
	_at(lines[0], _a, 0)                           # ouvre le tour 1
	for k in 3:
		for c in range(1, n):
			_at(lines[k] + c, _a, c)
		_at(lines[k + 1], _a, 0)
	_at(300, _a, 1)                                # apres l'arrivee : ignore
	# B : raccourci
	_at(20, _b, 0)
	for c in range(1, 6):
		_at(20 + c, _b, c)
	for c in range(12, n):
		_at(30 + c, _b, c)
	_at(100, _b, 0)
	# C : demi-tour sur la ligne
	_at(20, _c, 0)
	_at(21, _c, n - 1)
	_at(22, _c, 0)
	# F : attend le checkpoint 3
	for c in [0, 1, 2]:
		_at(20 + c, _f, c)


func _test_tick(t: int) -> void:
	if t == START:
		_race.start()
	for ev: Array in _plan.get(t, []):
		_track.checkpoint_passed.emit(ev[0], ev[1])
	if t == 60:
		var xf := _race.respawn_transform(_f)
		_respawn_s = _track.sample_s(_track.closest_sample(xf.origin))
	# D roule "en avant" pour lui, donc a contre-sens de la piste ; E aussi,
	# dans le bon sens
	_fd.tick = t
	_fd.throttle = clampf((30.0 - _d.get_speed_kmh()) / 5.0, 0.0, 1.0)
	_d.set_input(_fd)
	_fe.tick = t
	_fe.throttle = clampf((30.0 - _e.get_speed_kmh()) / 5.0, 0.0, 1.0)
	_e.set_input(_fe)


func _test_finish() -> void:
	var la: PackedInt32Array = _laps.get(_a, PackedInt32Array())
	check("A : 3 tours comptes, temps 90 / 80 / 110 ticks",
		la == PackedInt32Array([90, 80, 110]), "tours=%s" % [la])
	var ra := _race.racer(_a)
	check("A : meilleur tour 80 ticks", ra.best_lap == 80, "meilleur=%d" % ra.best_lap)
	check("A : arrivee a 280 ticks, un seul signal",
		ra.finished and ra.finish_ticks == 280 and int(_finishes.get(_a, 0)) == 1,
		"fini=%s ticks=%d signaux=%d" % [ra.finished, ra.finish_ticks, int(_finishes.get(_a, 0))])
	check("B : raccourci, aucun tour compte", not _laps.has(_b), "tours=%s" % [_laps.get(_b)])
	check("C : demi-tour sur la ligne, aucun tour compte", not _laps.has(_c))
	check("D : MAUVAIS SENS leve a contre-sens", _wrong.has(_d))
	check("E : jamais MAUVAIS SENS dans le bon sens", not _wrong.has(_e))
	var s3 := _track.checkpoint_s(3)
	var s2 := _track.checkpoint_s(2)
	check("F : reapparition avant le checkpoint attendu (3), pas pres du 6",
		_respawn_s >= s2 and _respawn_s < s3, "s=%.0f m (cp2 %.0f, cp3 %.0f)" % [_respawn_s, s2, s3])
