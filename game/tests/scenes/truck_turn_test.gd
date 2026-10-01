extends PhysicsTest

## Virage (CLAUDE.md §10) a 80 km/h tenus par une commande de gaz calculee a
## chaque tick (le camion n'est jamais soulage par une perte de vitesse) :
##   1. braquage 30 % pendant 180 ticks : rayon de reference ;
##   2. plein braquage pendant 300 ticks : jamais retourne (roulis < 45 deg) ;
##      la direction est progressive : rayon a 30 % >= 1,3 x rayon a 100 % ;
##   3. stick relache 120 ticks : le camion se rattrape seul (derive < 3 deg,
##      lacet quasi nul), pas de tete-a-queue.
## Les rayons se mesurent en regime etabli, sur la 2e moitie de chaque phase
## (METRICS.md).

const TARGET_KMH := 80.0
const LAUNCH := 360
const PARTIAL := 180
const FULL := 300
const RELEASE := 120

var _truck: Truck
var _frame: InputFrame = InputFrame.new()
var _max_roll: float = 0.0
var _max_slip: float = 0.0
var _upside: bool = false
var _min_wheels: int = 4
var _r_partial: float = 0.0
var _n_partial: int = 0
var _r_full: float = 0.0
var _n_full: int = 0
var _lat_g_full: float = 0.0


func _test_setup() -> void:
	duration_ticks = LAUNCH + PARTIAL + FULL + RELEASE
	add_floor(800.0)
	_truck = TruckTestUtil.spawn_truck(self, Vector3.ZERO)


func _test_tick(t: int) -> void:
	var v := _truck.get_speed_kmh()
	_frame.tick = t
	_frame.throttle = clampf((TARGET_KMH - v) / 5.0, 0.0, 1.0)
	_frame.steer = 0.0
	if t > LAUNCH and t <= LAUNCH + PARTIAL:
		_frame.steer = 0.3
	elif t > LAUNCH + PARTIAL and t <= LAUNCH + PARTIAL + FULL:
		_frame.steer = 1.0
	_truck.set_input(_frame)
	if t <= LAUNCH:
		return
	_max_roll = maxf(_max_roll, absf(TruckTestUtil.pitch_roll_deg(_truck).y))
	_upside = _upside or _truck.is_upside_down()
	_min_wheels = mini(_min_wheels, _truck.wheels_on_ground())
	_max_slip = maxf(_max_slip, TruckTestUtil.sideslip_deg(_truck))
	var speed := _truck.linear_velocity.length()
	var yaw := absf(_truck.angular_velocity.y)
	if t > LAUNCH + PARTIAL / 2 and t <= LAUNCH + PARTIAL:
		_r_partial += speed / maxf(yaw, 1e-4)
		_n_partial += 1
	elif t > LAUNCH + PARTIAL + FULL / 2 and t <= LAUNCH + PARTIAL + FULL:
		_r_full += speed / maxf(yaw, 1e-4)
		_lat_g_full += speed * yaw / TruckSpec.GRAVITY
		_n_full += 1


func _test_finish() -> void:
	check_finite("position finie", _truck.global_position)
	check_below("roulis max en virage (deg)", _max_roll, 45.0)
	check("jamais retourne", not _upside)
	var r_partial := _r_partial / maxi(_n_partial, 1)
	var r_full := _r_full / maxi(_n_full, 1)
	check_ratio_above("direction progressive : rayon 30 % / rayon 100 %", r_partial, r_full, 1.3)
	check_below("rattrapage : derive finale (deg)", TruckTestUtil.sideslip_deg(_truck), 3.0)
	check_below("rattrapage : lacet final (rad/s)", absf(_truck.angular_velocity.y), 0.05)
	print("  INFO   rayon a 30 %% : %.1f m ; a 100 %% : %.1f m (%.2f g)"
		% [r_partial, r_full, _lat_g_full / maxi(_n_full, 1)])
	print("  INFO   roulis max %.1f deg, derive max %.1f deg, roues au sol min %d"
		% [_max_roll, _max_slip, _min_wheels])
