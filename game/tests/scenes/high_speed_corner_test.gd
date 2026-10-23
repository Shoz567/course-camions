extends PhysicsTest

## Virages a haute vitesse (2026-10-23 : « dans quelques virages, c'est
## complique de tourner [...] sans aller toucher les bords [...] et meme en
## ligne droite, quand on va plutot vite ») : plein braquage, sans frein a
## main, vitesse tenue, sur le plat. Rayon tenu en regime etabli (centre de
## masse) et derive du camion.
## Seuils (docs/METRICS.md §4) : les virages des circuits font 120 a 160 m de
## rayon.
##   A. Normal (100cc) a 145 km/h, pres de sa vitesse max : rayon <= 120 m,
##      le plus serre des virages, sans deraper (derive < angle de saturation
##      des pneus) ;
##   B. Rapide (150cc) a 180 km/h : rayon <= 160 m (le plus large), sans
##      deraper ;
##   C. Ultrasonique (200cc) a 215 km/h : pas de tete-a-queue (derive sous la
##      saturation), pas de renversement (inclinaison < 20 deg), les roues au
##      sol ;
##   D. a 80 km/h, l'appui ne change presque rien (< 10 % de charge en plus) :
##      la conduite lente reste celle du baseline (handling_test).

const CASES := [[1, 145.0], [2, 180.0], [3, 215.0]]
const LAUNCH := 60
const STEER_AT := 90
const MEASURE_FROM := 300

var _trucks: Array[Truck] = []
var _frames: Array[InputFrame] = []
var _sum_radius: Array[float] = []
var _sum_slip: Array[float] = []
var _max_slip: Array[float] = []
var _max_tilt: Array[float] = []
var _air_ticks: Array[int] = []
var _n: int = 0


func _test_setup() -> void:
	duration_ticks = 520
	add_floor(4000.0)
	for k in CASES.size():
		var t := (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
		t.tuning = GameStateNode.speed_tuning(t.tuning, int(CASES[k][0]))
		t.position = Vector3(-1200.0 + k * 1200.0, 0.0, 900.0)
		add_child(t)
		_trucks.append(t)
		_frames.append(InputFrame.new())
		_sum_radius.append(0.0)
		_sum_slip.append(0.0)
		_max_slip.append(0.0)
		_max_tilt.append(0.0)
		_air_ticks.append(0)


func _test_tick(tk: int) -> void:
	for k in _trucks.size():
		var t := _trucks[k]
		var kmh: float = CASES[k][1]
		if tk == LAUNCH:
			# pose sur le sol depuis LAUNCH ticks, lance a la vitesse voulue
			t.reset_to(t.global_transform, -t.global_transform.basis.z * kmh / 3.6)
		var f := _frames[k]
		f.tick = tk
		f.throttle = 0.0 if tk < LAUNCH else clampf((kmh - t.get_speed_kmh()) / 5.0, 0.0, 1.0)
		f.steer = 1.0 if tk > STEER_AT else 0.0
		t.set_input(f)
		if tk > STEER_AT:
			var slip := TruckTestUtil.sideslip_deg(t)
			_max_slip[k] = maxf(_max_slip[k], slip)
			_max_tilt[k] = maxf(_max_tilt[k], TruckTestUtil.tilt_deg(t))
			if t.wheels_on_ground() == 0:
				_air_ticks[k] += 1
			if tk > MEASURE_FROM:
				_sum_radius[k] += t.linear_velocity.length() / maxf(absf(t.angular_velocity.y), 1e-4)
				_sum_slip[k] += slip
				if k == 0:
					_n += 1


func _test_finish() -> void:
	var sat: float = _trucks[0].tuning.grip_slip_angle_deg
	var r := []
	var s := []
	for k in CASES.size():
		r.append(_sum_radius[k] / maxf(_n, 1))
		s.append(_sum_slip[k] / maxf(_n, 1))
		print("  INFO   classe %d a %d km/h : rayon %.0f m, derive moy %.1f max %.1f deg, inclinaison max %.1f deg, %d ticks en l'air" % [
			CASES[k][0], CASES[k][1], r[k], s[k], _max_slip[k], _max_tilt[k], _air_ticks[k]])
	check_below("A Normal 145 km/h : rayon (m) <= le virage le plus serre", r[0], 120.0)
	check_below("A sans deraper : derive moyenne (deg)", s[0], sat)
	check_below("B Rapide 180 km/h : rayon (m) <= le virage le plus large", r[1], 160.0)
	check_below("B sans deraper : derive moyenne (deg)", s[1], sat)
	check_below("C Ultrasonique 215 km/h : pas de tete-a-queue, derive max (deg)", _max_slip[2], sat)
	check_below("C pas de renversement : inclinaison max (deg)", _max_tilt[2], 20.0)
	check("C les roues au sol", _air_ticks[2] == 0, "%d ticks en l'air" % _air_ticks[2])
	var tu := _trucks[0]
	check_below("D a 80 km/h : charge en plus (fraction du poids)", tu.downforce_ratio(80.0 / 3.6), 0.10)
