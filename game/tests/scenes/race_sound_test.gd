extends PhysicsTest

## Bruitages de course (tache 7.3) :
##   A. RaceSound.cue_for : carillon a chaque tour, annonce du dernier tour en
##      bouclant l'avant-dernier, fanfare a l'arrivee ;
##   B. signaux : duree, crete sous 0,8 sans saturer, fin a zero (aucun
##      claquement), notes justes (la note attendue domine sa fenetre) ;
##   C. largage : son de la sellette sans saturation ;
##   D. en course : tour boucle par J1 -> son du dernier tour ; la remorque
##      larguee -> la sellette sonne (compteur de TruckAudio).

var _scene: Node3D
var _seen: Dictionary = {}


func _test_setup() -> void:
	duration_ticks = 160
	_scene = (load("res://dev/race.tscn") as PackedScene).instantiate() as Node3D
	_scene.set("ready_gate", false)
	add_child(_scene)


func _test_tick(t: int) -> void:
	var players: Array = _scene.get("players")
	if players.is_empty():
		return
	var truck := (players[0] as Object).get("truck") as Truck
	var race := _scene.get("race") as RaceLaps
	match t:
		20:
			race.lap_completed.emit(truck, race.total_laps - 1, 3000)
			_seen["cue_final"] = int(_scene.get("last_cue"))
			race.lap_completed.emit(truck, 1, 3000)
			_seen["cue_lap"] = int(_scene.get("last_cue"))
		30:
			var cargo := truck.get_node(^"Cargo") as TruckCargo
			var audio := truck.get_node(^"Audio") as TruckAudio
			_seen["before"] = audio.releases
			_seen["dropped"] = cargo.drop() != null
			_seen["after"] = audio.releases


func _test_finish() -> void:
	var C := RaceSound.Cue
	check("cue_for : tours 1 et 2 sur 4 -> carillon", RaceSound.cue_for(1, 4) == C.LAP and RaceSound.cue_for(2, 4) == C.LAP)
	check("cue_for : tour 3 sur 4 -> dernier tour", RaceSound.cue_for(3, 4) == C.FINAL_LAP)
	check("cue_for : tour 4 sur 4 -> arrivee", RaceSound.cue_for(4, 4) == C.FINISH)
	check("cue_for : course en 2 et 1 tours, tour 0", RaceSound.cue_for(1, 2) == C.FINAL_LAP
		and RaceSound.cue_for(1, 1) == C.FINISH and RaceSound.cue_for(0, 4) == C.NONE)
	for spec: Array in [[C.LAP, 0.5], [C.FINAL_LAP, 0.95], [C.FINISH, 1.7]]:
		var s := RaceSound.build(spec[0])
		_check_signal("son %d" % int(spec[0]), s, float(spec[1]), RaceSound.RATE)
	var lap := RaceSound.build(C.LAP)
	check("carillon : mi puis si", _dominant(lap, 0.02, 0.1, [RaceSound.E5, RaceSound.B5]) == 0
		and _dominant(lap, 0.2, 0.35, [RaceSound.E5, RaceSound.B5]) == 1)
	var fin := RaceSound.build(C.FINAL_LAP)
	check("dernier tour : do, mi, sol, do aigu dans l'ordre",
		_dominant(fin, 0.02, 0.11, [RaceSound.C5, RaceSound.E5, RaceSound.G5, RaceSound.C6]) == 0
		and _dominant(fin, 0.14, 0.23, [RaceSound.C5, RaceSound.E5, RaceSound.G5, RaceSound.C6]) == 1
		and _dominant(fin, 0.26, 0.35, [RaceSound.C5, RaceSound.E5, RaceSound.G5, RaceSound.C6]) == 2
		and _dominant(fin, 0.45, 0.7, [RaceSound.C5, RaceSound.E5, RaceSound.G5, RaceSound.C6]) == 3)
	_check_signal("largage", TruckAudio.build_release(), 0.7, TruckAudio.RATE, 1.0)
	check("en course : J1 boucle l'avant-dernier tour -> dernier tour, puis un tour -> carillon",
		int(_seen.get("cue_final", -1)) == C.FINAL_LAP and int(_seen.get("cue_lap", -1)) == C.LAP,
		"%s / %s" % [_seen.get("cue_final"), _seen.get("cue_lap")])
	check("en course : remorque larguee -> la sellette sonne une fois", bool(_seen.get("dropped", false))
		and int(_seen.get("after", 0)) == int(_seen.get("before", -9)) + 1,
		"%s -> %s" % [_seen.get("before"), _seen.get("after")])


func _check_signal(what: String, s: PackedFloat32Array, length_s: float, rate: int, max_peak: float = 0.81) -> void:
	var peak := 0.0
	var finite := true
	for v in s:
		peak = maxf(peak, absf(v))
		finite = finite and is_finite(v)
	check("%s : %.2f s, crete %.2f (0,3 .. %.2f), fin a zero" % [what, length_s, peak, max_peak],
		absi(s.size() - roundi(length_s * rate)) <= 1 and finite and peak > 0.3 and peak <= max_peak
		and absf(s[s.size() - 1]) < 0.001, "%d echantillons" % s.size())


## Index de la frequence la plus forte (Goertzel) sur la fenetre [a, b] s.
static func _dominant(s: PackedFloat32Array, a: float, b: float, freqs: Array) -> int:
	var best := -1
	var best_p := -1.0
	for k in freqs.size():
		var w := TAU * float(freqs[k]) / RaceSound.RATE
		var coeff := 2.0 * cos(w)
		var s1 := 0.0
		var s2 := 0.0
		for i in range(roundi(a * RaceSound.RATE), roundi(b * RaceSound.RATE)):
			var s0 := s[i] + coeff * s1 - s2
			s2 = s1
			s1 = s0
		var p := s1 * s1 + s2 * s2 - coeff * s1 * s2
		if p > best_p:
			best_p = p
			best = k
	return best
