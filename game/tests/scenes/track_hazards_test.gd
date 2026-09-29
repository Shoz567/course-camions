extends PhysicsTest

## Relief et pieges de la piste n°1 (demande du playtest), avec PadEffects :
##   - relief : au moins 12 m de denivele sur le trace, pente jamais au-dela
##     de 9 % ; 4 flaques d'eau, 8 panneaux ;
##   A. flaque : un camion a 100 km/h qui y roule perd au moins 25 % de sa
##      vitesse tout de suite, une seule fois ;
##   B. panneau : un camion a 80 km/h qui le percute voit sa vitesse divisee
##      par 2 ; le panneau est ejecte (il monte de plus de 2 m), puis reprend
##      sa place, gele, 5 s plus tard ; le camion ne se couche pas.
## Les camions partent dans l'axe de la piste, a la hauteur du piege, a
## vitesse posee au tick 0 (CLAUDE.md §10 b).

const PUDDLE := 0          # grand virage, a l'exterieur
const SIGN := 0            # grand virage, a l'exterieur

var _track: TrackBlockout
var _a: Truck
var _b: Truck
var _fa: InputFrame = InputFrame.new()
var _fb: InputFrame = InputFrame.new()
var _a_slowed: int = 0
var _a_hit_at: int = -1
var _a_before: float = 0.0
var _a_after: float = 0.0
var _a_prev: float = 0.0
var _b_hit_at: int = -1
var _b_before: float = 0.0
var _b_after: float = 0.0
var _b_prev: float = 0.0
var _sign_home: Vector3
var _sign_rise: float = 0.0
var _sign_back: bool = false
var _max_tilt: float = 0.0


func _test_setup() -> void:
	duration_ticks = 420
	_track = (load("res://tracks/track_01_blockout.tscn") as PackedScene).instantiate() as TrackBlockout
	add_child(_track)
	var pads := PadEffects.new()
	pads.track = _track
	add_child(pads)
	_a = _spawn_before(_track.puddle_transform(PUDDLE), 22.0, 100.0)
	_a.slowed_down.connect(func() -> void:
		_a_slowed += 1
		if _a_hit_at < 0:
			_a_hit_at = tick
			_a_before = _a_prev)
	var board := _track.sign_node(SIGN)
	_sign_home = board.global_position
	_b = _spawn_before(board.global_transform, 24.0, 80.0)
	_b.slowed_down.connect(func() -> void:
		if _b_hit_at < 0:
			_b_hit_at = tick
			_b_before = _b_prev)


## Camion pose `back` metres avant le point, a son decalage, dans l'axe.
func _spawn_before(at: Transform3D, back: float, kmh: float) -> Truck:
	var i := _track.closest_sample(at.origin)
	var lateral := (at.origin - _track.sample_position(i)).dot(_track.sample_right(i))
	var xf := _track.frame_at(_track.sample_ahead(i, -back), lateral, 0.0)
	var t := (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
	t.transform = xf
	add_child(t)
	t.linear_velocity = -xf.basis.z * kmh / 3.6
	return t


func _test_tick(t: int) -> void:
	_fa.tick = t
	_fa.throttle = 0.6
	_a.set_input(_fa)
	_fb.tick = t
	_fb.throttle = 0.0 if _b_hit_at >= 0 else 0.5
	_fb.brake = 1.0 if _b_hit_at >= 0 else 0.0
	_b.set_input(_fb)
	var va := _a.linear_velocity.length()
	var vb := _b.linear_velocity.length()
	if _a_hit_at >= 0 and t == _a_hit_at + 3:
		_a_after = va
	if _b_hit_at >= 0 and t == _b_hit_at + 3:
		_b_after = vb
	_a_prev = va
	_b_prev = vb
	var board := _track.sign_node(SIGN)
	if board.knocked:
		_sign_rise = maxf(_sign_rise, board.global_position.y - _sign_home.y)
	if _b_hit_at >= 0 and t == _b_hit_at + 330:
		_sign_back = not board.knocked and board.freeze \
				and board.global_position.distance_to(_sign_home) < 0.1
	for tr: Truck in [_a, _b]:
		_max_tilt = maxf(_max_tilt, TruckTestUtil.tilt_deg(tr))


func _test_finish() -> void:
	var lo := INF
	var hi := -INF
	var grade := 0.0
	var n := _track.sample_count()
	var step := _track.length() / n
	var k := maxi(1, roundi(10.0 / step))
	for i in n:
		var p := _track.sample_position(i)
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
		var q := _track.sample_position(i + k)
		grade = maxf(grade, absf(q.y - p.y) / Vector2(q.x - p.x, q.z - p.z).length())
	print("  INFO   relief %.1f m, pente max %.1f %% ; flaque %.1f -> %.1f m/s ; panneau %.1f -> %.1f m/s, envol %.1f m"
		% [hi - lo, grade * 100.0, _a_before, _a_after, _b_before, _b_after, _sign_rise])
	check_above("relief : denivele du trace (m)", hi - lo, 12.0)
	check_below("relief : pente max (%)", grade * 100.0, 9.0)
	check("4 flaques, 8 panneaux", _track.puddle_count() == 4 and _track.sign_count() == 8,
		"%d / %d" % [_track.puddle_count(), _track.sign_count()])
	check("A flaque : ralenti une seule fois", _a_slowed == 1, "%d" % _a_slowed)
	if _a_hit_at >= 0:
		check_below("A flaque : vitesse apres / avant", _a_after / maxf(_a_before, 0.1), 0.75)
	check("B panneau percute", _b_hit_at >= 0, "tick=%d" % _b_hit_at)
	if _b_hit_at >= 0:
		check_below("B panneau : vitesse divisee par 2 (apres / avant)", _b_after / maxf(_b_before, 0.1), 0.55)
	check_above("panneau ejecte : envol (m)", _sign_rise, 2.0)
	check("panneau revenu a sa place, gele, 5 s apres", _sign_back)
	check_below("personne ne se couche (deg)", _max_tilt, 45.0)
