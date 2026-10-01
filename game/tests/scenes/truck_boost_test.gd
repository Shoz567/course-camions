extends PhysicsTest

## Boost avec recharge, et klaxon.
##   A. 100 km/h tenus, boost a BOOST_AT : il dure boost_duration_ticks ; un
##      nouvel appui pendant la recharge est ignore (y compris 5 s apres) ; une fois la jauge pleine
##      (boost_recharge_ticks apres la fin), le boost repart.
##   B. jumeau de A sans boost : A gagne au moins la moitie du gain theorique
##      (boost_accel x duree) sur B pendant le boost.
##   C. a la vitesse max, le boost la depasse d'au moins 5 %.
##   D. un appui de klaxon = un signal honked.

const HOLD_KMH := 100.0
const BOOST_AT := 241
const RETRY_AT := 350
## Recharge du boost : 6 s (demande du 2026-09-30, au lieu de 4 s).
const RECHARGE_TICKS := 360
## Appui 5 s apres la fin du 1er boost : encore en recharge, ignore.
const LATE_RETRY_AT := BOOST_AT + 90 + 300

var _a: Truck
var _b: Truck
var _c: Truck
var _fa: InputFrame = InputFrame.new()
var _fb: InputFrame = InputFrame.new()
var _fc: InputFrame = InputFrame.new()
var _boost_ticks: int = 0
var _starts: PackedInt32Array = []
var _was_boosting: bool = false
var _gain: float = 0.0
var _c_top: float = 0.0
var _c_before: float = 0.0
var _honks: int = 0
var _second_at: int = -1


func _test_setup() -> void:
	duration_ticks = 900
	add_floor(3000.0)
	_a = TruckTestUtil.spawn_truck(self, Vector3(-20.0, 0.0, 1400.0))
	_b = TruckTestUtil.spawn_truck(self, Vector3(20.0, 0.0, 1400.0))
	_c = TruckTestUtil.spawn_truck(self, Vector3(60.0, 0.0, 1400.0))
	_b.honked.connect(func() -> void: _honks += 1)
	_second_at = BOOST_AT + roundi(_a.tuning.boost_duration_ticks + _a.tuning.boost_recharge_ticks) + 10


func _test_tick(t: int) -> void:
	# A et B : 100 km/h tenus jusqu'au boost, puis plein gaz tous les deux
	var hold := t < BOOST_AT
	for pair: Array in [[_a, _fa], [_b, _fb]]:
		var tr: Truck = pair[0]
		var f: InputFrame = pair[1]
		f.tick = t
		f.throttle = clampf((HOLD_KMH - tr.get_speed_kmh()) / 5.0, 0.0, 1.0) if hold else 1.0
	_fa.boost = (t >= BOOST_AT and t < BOOST_AT + 10) or (t >= RETRY_AT and t < RETRY_AT + 10) \
			or (t >= LATE_RETRY_AT and t < LATE_RETRY_AT + 10) or (t >= _second_at and t < _second_at + 10)
	_fb.honk = t == 100
	_a.set_input(_fa)
	_b.set_input(_fb)
	# C : plein gaz jusqu'a la vitesse max, boost a 600
	_fc.tick = t
	_fc.throttle = 1.0
	_fc.boost = t >= 600 and t < 610
	_c.set_input(_fc)
	if t == 599:
		_c_before = _c.get_speed_kmh()
	if t > 600:
		_c_top = maxf(_c_top, _c.get_speed_kmh())

	var boosting := _a.is_boosting()
	if boosting:
		_boost_ticks += 1
		if not _was_boosting:
			_starts.append(t)
	_was_boosting = boosting
	if t == BOOST_AT + roundi(_a.tuning.boost_duration_ticks) + 1:
		_gain = _a.get_speed_kmh() - _b.get_speed_kmh()


func _test_finish() -> void:
	var tu := _a.tuning
	check_near("recharge du boost : 6 s (ticks)", tu.boost_recharge_ticks, RECHARGE_TICKS, 0.5)
	check("deux boosts : au 1er appui et apres recharge, pas pendant la recharge",
		_starts.size() == 2, "debuts=%s" % [_starts])
	if _starts.size() == 2:
		check("1er boost a l'appui (tick)", absi(_starts[0] - BOOST_AT) <= 2, "tick=%d" % _starts[0])
		check("appui pendant la recharge ignore, 2e boost apres recharge",
			_starts[1] >= _second_at and _starts[1] <= _second_at + 2, "tick=%d attendu %d" % [_starts[1], _second_at])
	check_near("duree totale de boost (ticks)", _boost_ticks, 2.0 * tu.boost_duration_ticks, 2.0)
	var theory := tu.boost_accel_ms2 * tu.boost_duration_ticks / 60.0 * 3.6
	check_ratio_above("gain de vitesse du boost / theorie", _gain, theory, 0.5)
	check_ratio_above("vitesse max depassee pendant le boost", _c_top, _c_before, 1.05)
	check("klaxon : un signal par appui", _honks == 1, "signaux=%d" % _honks)
	print("  INFO   gain %.1f km/h (theorie %.1f) ; vitesse max %.1f -> %.1f km/h avec boost"
		% [_gain, theory, _c_before, _c_top])
