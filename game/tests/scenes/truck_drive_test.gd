extends PhysicsTest

## Moteur, freins, marche arriere (taches 1.3 a 1.4), cibles de VEHICLE_SPEC §6 :
##   plein gaz 720 ticks : 0 -> 100 km/h a +/- 5 % de 6 s, vitesse max a
##   +/- 5 % de 150 km/h, stabilisee (+/- 0,5 km/h sur 60 ticks, METRICS.md) ;
##   puis frein 480 ticks : 100 -> 0 en < 45 m, puis marche arriere.
## Vitesses le long de l'axe avant (METRICS.md).

const THROTTLE_TICKS := 720
const BRAKE_TICKS := 480

var _truck: Truck
var _src: ScriptedInputSource
var _t100: int = -1
var _top: Stat = Stat.new()
var _brake_start: Vector3
var _brake_armed: bool = false
var _brake_dist: float = -1.0
var _min_wheels: int = 4
var _max_pitch_brake: float = 0.0
var _max_x: float = 0.0


class Stat:
	var lo: float = INF
	var hi: float = -INF
	var s: float = 0.0
	var n: int = 0

	func add(v: float) -> void:
		lo = minf(lo, v)
		hi = maxf(hi, v)
		s += v
		n += 1


func _test_setup() -> void:
	duration_ticks = THROTTLE_TICKS + BRAKE_TICKS
	add_floor(2400.0)
	_truck = TruckTestUtil.spawn_truck(self, Vector3.ZERO)
	_src = ScriptedInputSource.new()
	_src.push_hold(&"throttle", 1.0, THROTTLE_TICKS)
	_src.push_hold(&"brake", 0.0, THROTTLE_TICKS)
	_src.push_hold(&"brake", 1.0, BRAKE_TICKS)
	add_child(_src)


func _test_tick(t: int) -> void:
	_truck.set_input(_src.poll(t))
	var v := _truck.get_speed_kmh()
	_min_wheels = mini(_min_wheels, _truck.wheels_on_ground()) if t > 5 else 4
	_max_x = maxf(_max_x, absf(_truck.global_position.x))
	if _t100 < 0 and v >= 100.0:
		_t100 = t
	if t > THROTTLE_TICKS - 60 and t <= THROTTLE_TICKS:
		_top.add(v)
	if t > THROTTLE_TICKS:
		_max_pitch_brake = maxf(_max_pitch_brake, absf(TruckTestUtil.pitch_roll_deg(_truck).x))
		if not _brake_armed and v <= 100.0:
			_brake_armed = true
			_brake_start = _truck.global_position
		if _brake_armed and _brake_dist < 0.0 and v <= 0.5:
			_brake_dist = _truck.global_position.distance_to(_brake_start)


func _test_finish() -> void:
	var tol := TruckSpec.TARGET_TOLERANCE
	check_finite("position finie", _truck.global_position)
	check("100 km/h atteint", _t100 > 0, "tick=%d" % _t100)
	check_near("0 -> 100 km/h (s)", _t100 / 60.0, TruckSpec.TARGET_ACCEL_0_100_S,
		TruckSpec.TARGET_ACCEL_0_100_S * tol)
	var top := _top.s / maxi(_top.n, 1)
	check_near("vitesse max (km/h)", top, TruckSpec.TARGET_TOP_SPEED_KMH,
		TruckSpec.TARGET_TOP_SPEED_KMH * tol)
	check_below("vitesse max stabilisee : ecart sur 60 ticks (km/h)", _top.hi - _top.lo, 1.0)
	check("arret atteint au freinage", _brake_dist >= 0.0)
	check_below("freinage 100 -> 0 (m)", _brake_dist, TruckSpec.TARGET_BRAKING_100_0_M)
	var rev := _truck.get_speed_kmh()
	check_below("marche arriere engagee (km/h)", rev, -0.5 * _truck.tuning.reverse_top_speed_kmh)
	check_above("marche arriere bornee (km/h)", rev, -_truck.tuning.reverse_top_speed_kmh * (1.0 + tol))
	check("4 roues au sol en ligne droite", _min_wheels == 4, "min=%d" % _min_wheels)
	check_below("ecart lateral en ligne droite (m)", _max_x, 0.5)
	print("  INFO   tangage max au freinage : %.2f deg" % _max_pitch_brake)
