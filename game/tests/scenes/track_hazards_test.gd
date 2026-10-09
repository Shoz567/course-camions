extends PhysicsTest

## Relief et pieges de la piste n°1, avec PadEffects :
##   - collines : au moins 30 m de denivele, une vraie cote raide (pente max entre 12 et 20 %) ;
##     4 flaques, 8 panneaux, 4 barils explosifs ;
##   C. descente plongeante : un camion lache sans gaz ni frein en haut de la chicane
##      accelere sous l'effet de la gravite (+8 km/h en 3 s au moins) ;
##   D. compression : au pied de la grande montee, a 110 km/h, la suspension s'enfonce nettement ;
##   A. flaque (savonnette) : perte d'adherence laterale (glissade) sans perte de vitesse brute ;
##   B. panneau : percute et ejecte (monte de plus de 2 m) sans ralentir le camion, puis respawn ;
##   E. baril explosif : detonation au contact, ejection du baril (envol > 2 m), yeet physique
##      leger sur le camion sans retournement, -15 PV pour le camion (TruckHealth), puis respawn.

const PUDDLE := 0          # grand virage, a l'exterieur
const SIGN := 0            # grand virage, a l'exterieur
const BARREL := 0          # ligne droite de depart
const ExplosiveBarrel := preload("res://tracks/explosive_barrel.gd")

var _track: TrackBlockout
var _a: Truck
var _b: Truck
var _c: Truck
var _d: Truck
var _e: Truck
var _fa: InputFrame = InputFrame.new()
var _fb: InputFrame = InputFrame.new()
var _fd: InputFrame = InputFrame.new()
var _fe: InputFrame = InputFrame.new()
var _c_pilot: TrackAutopilot
var _e_damage: PackedStringArray = []

var _a_slipped: int = 0
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

var _c_v0: float = 0.0
var _c_v3: float = 0.0
var _d_min_hub: float = INF

var _e_hit_at: int = -1
var _barrel_home: Vector3
var _barrel_rise: float = 0.0
var _barrel_back: bool = false

var _max_tilt: float = 0.0


func _test_setup() -> void:
	duration_ticks = 480
	_track = (load("res://tracks/track_01_blockout.tscn") as PackedScene).instantiate() as TrackBlockout
	add_child(_track)
	var pads := PadEffects.new()
	pads.track = _track
	add_child(pads)

	# A : flaque
	_a = _spawn_before(_track.puddle_transform(PUDDLE), 22.0, 100.0)
	_a.puddle_slipped.connect(func(_ticks: int) -> void:
		_a_slipped += 1
		if _a_hit_at < 0:
			_a_hit_at = tick
			_a_before = _a_prev)

	# B : panneau
	var board := _track.sign_node(SIGN)
	_sign_home = board.global_position
	_b = _spawn_before(board.global_transform, 24.0, 80.0)
	_track.sign_hit.connect(func(body: Node3D, _index: int) -> void:
		if body == _b and _b_hit_at < 0:
			_b_hit_at = tick
			_b_before = _b_prev)

	# C : haut de la descente plongeante, 90 km/h, sans gaz
	var i_top := _track.index_at_s(_track.segment_start_s("Chicane gauche (descente plongeante)"))
	_c = _spawn_before(_track.frame_at(i_top, 0.0, 0.0), 0.0, 90.0)
	_c_pilot = TrackAutopilot.new(_track, _c, 0.877)

	# D : 60 m avant le pied de la grande montee, 110 km/h, plein gaz
	var i_foot := _track.index_at_s(_track.segment_start_s("Grande montee"))
	_d = _spawn_before(_track.frame_at(i_foot, -6.0, 0.0), 60.0, 110.0)

	# E : baril explosif
	var barrel := _track.barrel_node(BARREL)
	if barrel != null:
		_barrel_home = barrel.global_position
		_e = _spawn_before(barrel.global_transform, 22.0, 80.0)
		_track.barrel_hit.connect(func(truck: Truck, _index: int) -> void:
			if truck == _e and _e_hit_at < 0:
				_e_hit_at = tick)
		TruckHealth.of(_e).damaged.connect(func(amount: float, source: StringName) -> void:
			_e_damage.append("%s %.0f (tick %d)" % [source, amount, tick]))


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
	_fb.throttle = 0.5
	_fb.brake = 0.0
	_b.set_input(_fb)

	var fc := _c_pilot.drive(t)
	fc.throttle = 0.0
	fc.brake = 0.0
	_c.set_input(fc)

	_fd.tick = t
	_fd.throttle = 1.0
	_d.set_input(_fd)

	if _e != null:
		_fe.tick = t
		_fe.throttle = 0.6
		_e.set_input(_fe)

	if t == 2:
		_c_v0 = _c.get_speed_kmh()
	if t == 182:
		_c_v3 = _c.get_speed_kmh()
	if t < 150:
		for k in 4:
			_d_min_hub = minf(_d_min_hub, _d.get_probe(k).hub_distance)

	var va := _a.linear_velocity.length()
	var vb := _b.linear_velocity.length()
	if _a_hit_at >= 0 and t == _a_hit_at + 3:
		_a_after = va
	if _b_hit_at >= 0 and t == _b_hit_at + 3:
		_b_after = vb
	_a_prev = va
	_b_prev = vb

	var board := _track.sign_node(SIGN)
	if board != null and board.knocked:
		_sign_rise = maxf(_sign_rise, board.global_position.y - _sign_home.y)
	if _b_hit_at >= 0 and t == _b_hit_at + 330 and board != null:
		_sign_back = not board.knocked and board.freeze \
				and board.global_position.distance_to(_sign_home) < 0.1

	var barrel := _track.barrel_node(BARREL)
	if barrel != null and barrel.exploded_state:
		_barrel_rise = maxf(_barrel_rise, barrel.global_position.y - _barrel_home.y)
	if _e_hit_at >= 0 and t == _e_hit_at + 380 and barrel != null:
		_barrel_back = not barrel.exploded_state and barrel.freeze \
				and barrel.global_position.distance_to(_barrel_home) < 0.2

	for tr: Truck in [_a, _b, _c, _d]:
		_max_tilt = maxf(_max_tilt, TruckTestUtil.tilt_deg(tr))
	if _e != null:
		_max_tilt = maxf(_max_tilt, TruckTestUtil.tilt_deg(_e))


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

	print("  INFO   relief %.1f m, pente max %.1f %% ; flaque %.1f -> %.1f m/s ; panneau %.1f -> %.1f m/s, envol %.1f m ; baril envol %.1f m"
		% [hi - lo, grade * 100.0, _a_before, _a_after, _b_before, _b_after, _sign_rise, _barrel_rise])
	print("  INFO   C descente : %.0f -> %.0f km/h sans gaz ; D pied de cote : moyeu a %.2f m (repos %.2f)"
		% [_c_v0, _c_v3, _d_min_hub, TruckSpec.rest_hub_distance()])

	check_above("collines : denivele du trace (m)", hi - lo, 30.0)
	check_above("collines : vraie cote raide, pente max (%)", grade * 100.0, 12.0)
	check_below("collines : pente max reste roulable (%)", grade * 100.0, 20.0)
	check_above("C descente plongeante : la gravite accelere (km/h en 3 s)", _c_v3 - _c_v0, 8.0)
	check_below("D compression au pied de la cote : moyeu (m)", _d_min_hub, 0.40)
	check("4 flaques, 8 panneaux, 4 barils", _track.puddle_count() == 4 and _track.sign_count() == 8 and _track.barrel_count() == 4,
		"%d / %d / %d" % [_track.puddle_count(), _track.sign_count(), _track.barrel_count()])

	check("A flaque : glissade savonnette declenchee", _a_slipped == 1, "%d" % _a_slipped)
	if _a_hit_at >= 0:
		check_above("A flaque : vitesse conservee (pas de freinage)", _a_after / maxf(_a_before, 0.1), 0.90)

	check("B panneau percute", _b_hit_at >= 0, "tick=%d" % _b_hit_at)
	if _b_hit_at >= 0:
		check_above("B panneau : vitesse conservee sans ralentissement (apres / avant)", _b_after / maxf(_b_before, 0.1), 0.90)
	check_above("panneau ejecte : envol (m)", _sign_rise, 2.0)
	check("panneau revenu a sa place, gele, 5 s apres", _sign_back)

	check("E baril explosif percute", _e_hit_at >= 0, "tick=%d" % _e_hit_at)
	print("  INFO   E : degats %s" % [_e_damage])
	check("E baril : -15 PV pour le camion qui le fait sauter, au contact",
		not _e_damage.is_empty() and _e_damage[0] == "baril 15 (tick %d)" % _e_hit_at, str(_e_damage))
	check_above("baril ejecte : envol (m)", _barrel_rise, 2.0)
	check("baril revenu a sa place apres respawn", _barrel_back)

	check_below("personne ne se couche (deg)", _max_tilt, 45.0)
