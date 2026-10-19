extends PhysicsTest

## Deroule de la course (taches 3.1, 3.2, 3.6) :
##   A. RaceManager seul : compte a rebours, places d'arrivee, temps limite
##      apres la premiere arrivee, fin quand tous sont arrives ou partis.
##   B. classement au passage de la ligne : deux camions (figes, avances a la
##      main le long de la piste) ; le checkpoint 0 compte quand l'AVANT du
##      camion touche la ligne, comme la zone de la piste, alors que la
##      position se lit au centre. Celui de devant reste 1er a chaque tick ;
##      puis le second est remis en piste (respawn_transform) : toujours 2e.
##   C. vraie course a 2 (dev/race.tscn) : un seul arrive ; HUD du second
##      bandeau « FIN DANS », puis au temps limite resultats, « non classe ».

## Distance centre -> avant du camion (m) : la zone de la ligne le voit avant
## que son centre ne la passe.
const FRONT_M := 4.0
const STEP_M := 0.6
const TIMEOUT := 90

var _track: TrackBlockout
var _race: RaceLaps
var _a: Truck
var _b: Truck
var _sa: float
var _sb: float
var _crossed: Dictionary = {}
var _wrong_rank: int = 0
var _rank_ticks: int = 0
var _reset_done: bool = false
var _after_reset_wrong: int = 0
var _scene: Node3D
var _seen: Dictionary = {}


func _test_setup() -> void:
	duration_ticks = 520
	_test_manager()
	_track = (load("res://tracks/track_01_blockout.tscn") as PackedScene).instantiate() as TrackBlockout
	add_child(_track)
	_race = RaceLaps.new()
	_race.track = _track
	_race.total_laps = 3
	add_child(_race)
	_a = _frozen()
	_b = _frozen()
	_race.watch(_a)
	_race.watch(_b)
	# course C, au-dessus
	RaceManager.finish_timeout_ticks = TIMEOUT
	_scene = (load("res://dev/race.tscn") as PackedScene).instantiate() as Node3D
	_scene.set("players_from_menu", false)
	_scene.set("player_count", 2)
	_scene.set("ready_gate", false)
	add_child(_scene)


func _frozen() -> Truck:
	var t := (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
	t.freeze = true
	t.collision_layer = 0
	t.collision_mask = 0
	add_child(t)
	return t


func _test_manager() -> void:
	var m := RaceManagerNode.new()
	add_child(m)
	m.finish_timeout_ticks = 100
	var changes := []
	m.state_changed.connect(func(s: int, _p: int) -> void: changes.append(s))
	m.begin(true, 0)
	m.enter(RaceManagerNode.State.COUNTDOWN, 10)
	var early := m.countdown_done(10 + RaceManagerNode.COUNTDOWN_TICKS - 1)
	var done := m.countdown_done(10 + RaceManagerNode.COUNTDOWN_TICKS)
	m.enter(RaceManagerNode.State.RACING, 200)
	var t1 := Truck.new()
	var t2 := Truck.new()
	var r1 := m.record_finish(t1, 500)
	var again := m.record_finish(t1, 510)
	check("compte a rebours : %d ticks" % RaceManagerNode.COUNTDOWN_TICKS, not early and done)
	check("arrivee : 1re place, une seule fois", r1 == 1 and again == 1 and m.finish_order.size() == 1)
	check("temps limite apres la 1re arrivee", m.deadline_left(550) == 50 and not m.should_finish(599, 3, 0)
		and m.should_finish(600, 3, 0), "reste %d" % m.deadline_left(550))
	check("fin : tous arrives ou partis", m.should_finish(520, 3, 2) and not m.should_finish(520, 3, 1))
	m.record_finish(t2, 520)
	m.finish(600, true)
	check("resultats : etats LOBBY -> COUNTDOWN -> RACING -> FINISHED, au temps limite",
		changes == [RaceManagerNode.State.COUNTDOWN, RaceManagerNode.State.RACING, RaceManagerNode.State.FINISHED]
		and m.ended_by_timeout and m.state == RaceManagerNode.State.FINISHED, str(changes))
	t1.free()
	t2.free()
	m.queue_free()


func _place(t: Truck, s: float) -> void:
	var length := _track.length()
	var idx := _track.index_at_s(fposmod(s, length))
	t.global_transform = _track.frame_at(idx, 0.0, 1.0)


func _test_tick(t: int) -> void:
	var length := _track.length()
	var n := _track.checkpoint_count
	if t == 2:
		_race.start()
		# tour 1 entier pour les deux : ligne, puis tous les checkpoints
		for tr in [_a, _b]:
			_track.checkpoint_passed.emit(tr, 0)
			for c in range(1, n):
				_track.checkpoint_passed.emit(tr, c)
		_sa = length - 30.0
		_sb = length - 38.0
	if t >= 3 and t < 140:
		_sa += STEP_M
		_sb += STEP_M
		_place(_a, _sa)
		_place(_b, _sb)
		for pair: Array in [[_a, _sa], [_b, _sb]]:
			var tr: Truck = pair[0]
			if not _crossed.has(tr) and float(pair[1]) + FRONT_M >= length:
				_crossed[tr] = true
				_track.checkpoint_passed.emit(tr, 0)
		if t > 4:
			_rank_ticks += 1
			if _race.position(_a) != 1 or _race.position(_b) != 2:
				_wrong_rank += 1
	if t == 140:
		check("ligne franchie : chaque camion compte son tour 2", _race.racer(_a).lap == 2 and _race.racer(_b).lap == 2,
			"%d %d" % [_race.racer(_a).lap, _race.racer(_b).lap])
		check("classement juste a chaque tick du passage de la ligne", _wrong_rank == 0,
			"%d tick(s) faux sur %d" % [_wrong_rank, _rank_ticks])
		# remise en piste du second (bridee, RaceLaps.respawn_transform)
		_b.global_transform = _race.respawn_transform(_b)
		_reset_done = true
	if _reset_done and t > 142 and t < 160:
		if _race.position(_a) != 1 or _race.position(_b) != 2:
			_after_reset_wrong += 1
	if t == 160:
		check("apres une remise en piste : classement inchange", _after_reset_wrong == 0, str(_after_reset_wrong))
	_course(t)


func _course(t: int) -> void:
	var players: Array = _scene.get("players")
	if players.size() != 2:
		return
	var p0: Object = players[0]
	var p1: Object = players[1]
	var t0 := p0.get("truck") as Truck
	var laps := _scene.get("race") as RaceLaps
	if t == 200:
		_seen["racing"] = int(_scene.get("state")) == RaceManagerNode.State.RACING
		# J1 arrive (comme RaceLaps a la derniere ligne)
		var r := laps.racer(t0)
		r.finished = true
		r.finish_ticks = 1234
		laps.race_finished.emit(t0, 1234)
	if t == 230:
		# temps limite dans le bandeau du haut, rien au centre (fin sans gene)
		_seen["deadline"] = (p1.get("hud") as RaceHud).ticker_text().contains("FIN DANS")
		_seen["still_racing"] = int(_scene.get("state")) == RaceManagerNode.State.RACING
	if t == 200 + TIMEOUT + 5:
		_seen["finished"] = int(_scene.get("state")) == RaceManagerNode.State.FINISHED and RaceManager.ended_by_timeout
		_seen["standings"] = String(_scene.call("standings_text"))
	if t == 200 + TIMEOUT + 10:
		_seen["dnf_msg"] = String((p1.get("hud") as RaceHud).get("_center_text"))


func _test_finish() -> void:
	check("course : partie au tick 200", bool(_seen.get("racing", false)))
	check("un seul arrive : bandeau « FIN DANS » pour l'autre, course en cours",
		bool(_seen.get("deadline", false)) and bool(_seen.get("still_racing", false)))
	check("temps limite : resultats", bool(_seen.get("finished", false)))
	check("classement : le second « non classe »", String(_seen.get("standings", "")).contains("non classé"),
		String(_seen.get("standings", "")).replace("\n", " | "))
	check("HUD du second : NON CLASSE", String(_seen.get("dnf_msg", "")).begins_with("NON CLASSÉ"),
		String(_seen.get("dnf_msg", "")).replace("\n", " | "))
	RaceManager.finish_timeout_ticks = RaceManagerNode.FINISH_TIMEOUT_TICKS
