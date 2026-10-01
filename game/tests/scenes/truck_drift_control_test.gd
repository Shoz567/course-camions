extends PhysicsTest

## Conduite demandee apres le playtest : train avant vif, drift maitrise,
## remorque amortie. Trois camions a 90 km/h, plein gaz :
##   A. drift long (frein a main pendant 4 s, conduit par le pilote de drift
##      de TruckTestUtil qui vise PILOT_DEG : l'angle est libre depuis le
##      2026-10-01, c'est le joueur qui le tient) : le nez pivote tout de suite
##      (30 deg de derive en moins de 0,7 s) et les roues avant sont debridees
##      (drift_steer_deg, au lieu des ~5 deg d'adherence) ; la derive tient (pas
##      de tete-a-queue : < 90 deg), reste stable (ecart-type < 4 deg sur les 2
##      dernieres secondes), garde de la vitesse (> 90 %) et un angle franc
##      (derive moyenne > 45 deg) ; relachee, elle revient sous
##      5 deg en < 1,5 s ; la remorque suit sans balancier (moins de 10 deg de
##      l'autre cote) ;
##   B. coup de volant sans frein a main : 90 % du lacet etabli en < 0,5 s ;
##   C. choc en lacet (4 rad/s donnes d'un coup, sans frein a main) : le
##      camion finit par se rattraper (derive < 5 deg a la fin). Le tete-a-queue
##      est permis depuis le retrait de la garde anti tete-a-queue (2026-10-01,
##      demande de l'utilisateur) : derive max 126 deg, affichee seulement ;
##   D. Ultrasonique (200cc) lance a 210 km/h, plein braquage sans frein a
##      main : la direction n'est pas figee, le camion tient au moins 0,75 g
##      (plancher steer_floor_deg ; 0,41 g sans lui).
## Vitesses posees au tick 0 et coup de lacet pose au tick 40 (CLAUDE.md §10 b).

const V0 := 25.0
const START := 30
const DRIFT := 240
const PILOT_DEG := 55.0

var _a: Truck
var _b: Truck
var _c: Truck
var _frames: Dictionary = {}
var _a_max_slip: float = 0.0
var _a_slips: PackedFloat32Array = []
var _a_speed_in: float = 0.0
var _a_speed_out: float = 0.0
var _a_recovered: int = -1
var _a_trailer_other: float = 0.0
var _b_yaw: PackedFloat32Array = []
var _c_max_slip: float = 0.0
var _c_final_slip: float = 0.0
var _max_tilt: float = 0.0
var _a_pivot: int = -1
var _a_max_steer: float = 0.0
var _d: Truck
var _d_prev_h: float = 0.0
var _d_turn: float = 0.0
var _d_speed: float = 0.0
var _d_n: int = 0


func _test_setup() -> void:
	duration_ticks = START + DRIFT + 150
	add_floor(2400.0)
	_a = _spawn(Vector3(-300.0, 0.0, 800.0))
	_b = _spawn(Vector3(0.0, 0.0, 800.0))
	_c = _spawn(Vector3(300.0, 0.0, 800.0))
	_d = (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
	_d.tuning = GameStateNode.speed_tuning(load("res://vehicles/default_vehicle.tres") as VehicleTuning,
		GameStateNode.SpeedClass.ULTRA)
	_d.position = Vector3(700.0, 0.0, 900.0)
	add_child(_d)
	_d.linear_velocity = Vector3(0.0, 0.0, -210.0 / 3.6)
	_frames[_d] = InputFrame.new()


func _spawn(p: Vector3) -> Truck:
	var t := TruckTestUtil.spawn_truck(self, p)
	t.linear_velocity = Vector3(0.0, 0.0, -V0)
	_frames[t] = InputFrame.new()
	return t


func _drive(t: Truck, tick: int, steer: float, handbrake: bool) -> void:
	var f: InputFrame = _frames[t]
	f.tick = tick
	f.throttle = 1.0
	f.steer = steer
	f.handbrake = handbrake
	t.set_input(f)


## Derive signee (deg), > 0 : vitesse a droite du cap.
static func slip_deg(t: Truck) -> float:
	var v := t.linear_velocity * Vector3(1, 0, 1)
	if v.length() < 2.0:
		return 0.0
	var fwd := -t.global_basis.z * Vector3(1, 0, 1)
	return rad_to_deg(atan2(v.dot(t.global_basis.x), v.dot(fwd.normalized())))


func _test_tick(t: int) -> void:
	var drifting := t >= START and t < START + DRIFT
	_drive(_a, t, TruckTestUtil.drift_pilot_steer(_a, PILOT_DEG) if drifting else 0.0, drifting)
	_drive(_b, t, 1.0 if t >= START else 0.0, false)
	_drive(_c, t, 0.0, false)
	_drive(_d, t, 1.0, false)
	if t == 40:
		_c.angular_velocity = Vector3(0.0, 4.0, 0.0)

	var sa := slip_deg(_a)
	if t == START:
		_a_speed_in = _a.linear_velocity.length()
	if drifting:
		_a_max_slip = maxf(_a_max_slip, absf(sa))
		# braquage DANS le virage (a droite, > 0) seulement : en contre-braquage,
		# la limite s'elargit de l'angle de derive (rattrapage permissif)
		_a_max_steer = maxf(_a_max_steer, _a.get_steer_deg())
		if _a_pivot < 0 and absf(sa) >= 30.0:
			_a_pivot = t - START
		if t >= START + DRIFT - 120:
			_a_slips.append(sa)
	if t == START + DRIFT - 1:
		_a_speed_out = _a.linear_velocity.length()
	if t >= START + DRIFT:
		if _a_recovered < 0 and absf(sa) < 5.0:
			_a_recovered = t - (START + DRIFT)
		# derapage a droite : remorque a gauche (< 0) ; de l'autre cote = > 0
		_a_trailer_other = maxf(_a_trailer_other, _a.get_trailer_angle_deg())
	if t >= START:
		_b_yaw.append(absf(_b.angular_velocity.y))
	if t >= 40:
		_c_max_slip = maxf(_c_max_slip, absf(slip_deg(_c)))
	_c_final_slip = absf(slip_deg(_c))
	var dv := _d.linear_velocity * Vector3(1, 0, 1)
	var dh := atan2(-dv.x, -dv.z)
	if t > 30 and t <= 150:
		_d_turn += absf(wrapf(dh - _d_prev_h, -PI, PI)) * 60.0
		_d_speed += dv.length()
		_d_n += 1
	_d_prev_h = dh
	for tr: Truck in [_a, _b, _c, _d]:
		_max_tilt = maxf(_max_tilt, TruckTestUtil.tilt_deg(tr))


func _test_finish() -> void:
	var mean := 0.0
	for s in _a_slips:
		mean += s
	mean /= maxi(_a_slips.size(), 1)
	var var_sum := 0.0
	for s in _a_slips:
		var_sum += (s - mean) * (s - mean)
	var std := sqrt(var_sum / maxi(_a_slips.size(), 1))
	var steady := _b_yaw[_b_yaw.size() - 1]
	var turn_in := -1
	for k in _b_yaw.size():
		if _b_yaw[k] >= 0.9 * steady:
			turn_in = k
			break
	var d_speed := _d_speed / maxi(_d_n, 1)
	var d_lat_g := d_speed * _d_turn / maxi(_d_n, 1) / 9.81
	print("  INFO   A : 30 deg de derive en %d ticks, roues avant jusqu'a %.1f deg ; D : %.2f g a %.0f km/h"
		% [_a_pivot, _a_max_steer, d_lat_g, d_speed * 3.6])
	print("  INFO   A : derive max %.1f deg, moyenne %.1f, ecart-type %.1f, vitesse %.0f %%, retour %d ticks, remorque de l'autre cote %.1f deg"
		% [_a_max_slip, mean, std, 100.0 * _a_speed_out / _a_speed_in, _a_recovered, _a_trailer_other])
	print("  INFO   B : 90 %% du lacet en %d ticks ; C : derive max %.1f deg apres le choc" % [turn_in, _c_max_slip])
	check("A drift : le nez pivote (30 deg de derive)", _a_pivot >= 0, "ticks=%d" % _a_pivot)
	check_below("A drift : 30 deg de derive en (ticks)", _a_pivot, 42)
	check_near("A drift : roues avant debridees (deg)", _a_max_steer, _a.tuning.drift_steer_deg, 0.5)
	check_below("A drift : derive max, pas de tete-a-queue (deg)", _a_max_slip, 90.0)
	# Seuils releves le 2026-10-01 a la demande de l'utilisateur (« le derapage
	# freine trop et l'angle n'est pas assez eleve ») : etaient 15 deg et 60 %,
	# pour 38,7 deg et 74 % mesures.
	check_above("A drift : la derive tient (deg, moyenne)", absf(mean), 45.0)
	check_below("A drift stable : ecart-type sur 2 s (deg)", std, 4.0)
	check_above("A drift : vitesse gardee (fin / debut)", _a_speed_out / _a_speed_in, 0.9)
	check("A relache : retour sous 5 deg", _a_recovered >= 0, "ticks=%d" % _a_recovered)
	check_below("A relache : retour sous 5 deg (ticks)", _a_recovered, 90)
	check_below("A remorque : pas de balancier de l'autre cote (deg)", _a_trailer_other, 10.0)
	check("B braquage franc : 90 % du lacet etabli", turn_in >= 0)
	check_below("B braquage franc : 90 % du lacet en (ticks)", turn_in, 30)
	check_below("C choc en lacet : rattrapage (deg)", _c_final_slip, 5.0)
	check_above("D 200cc a 210 km/h : direction jamais figee (g)", d_lat_g, 0.75)
	check_below("jamais couche (deg)", _max_tilt, 45.0)
