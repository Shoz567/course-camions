extends PhysicsTest

## Juice minimal (tache 3.5), sans entendre ni voir :
##   - regime du moteur (TruckAudio.rpm_for) : ralenti a l'arret, monte dans
##     chaque rapport, retombe au passage de vitesse, monte a vide sous le gaz
##     (arret, en l'air) ;
##   - crissement : rien sous SQUEAL_FROM_MS, plein a SQUEAL_FULL_MS, rien en
##     l'air ; choc : rien sous IMPACT_MIN_MS, plein a IMPACT_FULL_MS ;
##   - sons synthetises : boucles sans claquement (saut au raccord pas plus
##     grand qu'a l'interieur),
##     jamais satures ;
##   - camera : aucune secousse sans choc (la camera ne tremble pas, tache
##     2.1) ; un choc la secoue, la secousse s'eteint en 0,3 s.

var _truck: Truck
var _cam: ChaseCamera
var _offsets: Array[float] = []


func _test_setup() -> void:
	duration_ticks = 60
	add_floor(200.0)
	_truck = TruckTestUtil.spawn_truck(self, Vector3.ZERO)
	_cam = ChaseCamera.new()
	_cam.target = _truck
	add_child(_cam)
	_cam.snap()


func _test_tick(t: int) -> void:
	var cam := _cam.get_camera()
	if t == 20:
		_offsets.append(absf(cam.h_offset) + absf(cam.v_offset))   # avant tout choc
		_cam.shake(LocalRace_shake(20.0))
	if t > 20 and t <= 40:
		_offsets.append(absf(cam.h_offset) + absf(cam.v_offset))


## LocalRace.shake_for, sans charger la scene de course.
static func LocalRace_shake(v: float) -> float:
	return (load("res://dev/local_race.gd") as GDScript).call("shake_for", v)


func _test_finish() -> void:
	# moteur
	var idle := TruckAudio.rpm_for(0.0, 0.0, true)
	var revved := TruckAudio.rpm_for(0.0, 1.0, true)
	var air := TruckAudio.rpm_for(60.0, 1.0, false)
	var g1_lo := TruckAudio.rpm_for(5.0, 1.0, true)
	var g1_hi := TruckAudio.rpm_for(21.0, 1.0, true)
	var g2_lo := TruckAudio.rpm_for(24.0, 1.0, true)
	check("moteur : ralenti a l'arret", is_equal_approx(idle, TruckAudio.IDLE_RPM), "%.0f tr/min" % idle)
	check("moteur : monte a vide sous le gaz", revved > idle + 1000.0, "%.0f tr/min" % revved)
	check("moteur : monte dans le rapport, retombe au passage", g1_hi > g1_lo + 800.0 and g2_lo < g1_hi - 800.0,
		"1re %.0f -> %.0f, 2e %.0f" % [g1_lo, g1_hi, g2_lo])
	check("moteur : en l'air, le gaz fait monter le regime", air >= TruckAudio.rpm_for(60.0, 1.0, true),
		"%.0f tr/min" % air)
	var top := TruckAudio.rpm_for(400.0, 1.0, true)
	check("moteur : jamais au-dela du regime max", top <= TruckAudio.MAX_RPM, "%.0f" % top)
	# crissement et chocs
	check("crissement : seuils", TruckAudio.squeal_for(1.0, 0.0, true) == 0.0
		and is_equal_approx(TruckAudio.squeal_for(9.0, 0.0, true), 1.0) and TruckAudio.squeal_for(9.0, 1.0, false) == 0.0)
	check("choc : seuils", TruckAudio.impact_level(1.0) == 0.0 and is_equal_approx(TruckAudio.impact_level(22.0), 1.0))
	# sons synthetises
	for pair: Array in [["moteur", TruckAudio._build_engine(), true], ["crissement", TruckAudio._build_squeal(), true],
			["choc", TruckAudio._build_impact(), false]]:
		var s: PackedFloat32Array = pair[1]
		var peak := 0.0
		for v in s:
			peak = maxf(peak, absf(v))
		# saut au raccord, au plus le plus grand saut entre deux echantillons
		# voisins a l'interieur (un aigu varie vite d'un echantillon a l'autre)
		var seam := absf(s[0] - s[s.size() - 1])
		var step := 0.0
		for i in s.size() - 1:
			step = maxf(step, absf(s[i + 1] - s[i]))
		check("son %s : pas de saturation (crete)" % pair[0], peak < 0.98 and peak > 0.05, "crete %.2f" % peak)
		if pair[2]:
			check("son %s : boucle sans claquement (raccord)" % pair[0], seam <= step * 1.05,
				"raccord %.3f, saut interieur max %.3f" % [seam, step])
	# camera
	check("camera : aucune secousse sans choc", _offsets[0] == 0.0, str(_offsets[0]))
	var peak_shake := 0.0
	for k in range(1, 6):
		peak_shake = maxf(peak_shake, _offsets[k])
	check("camera : un choc a 20 m/s la secoue", peak_shake > 0.05, "%.3f m" % peak_shake)
	check("camera : secousse eteinte en 0,3 s", _offsets[_offsets.size() - 1] < 0.002,
		"%.4f m" % _offsets[_offsets.size() - 1])
