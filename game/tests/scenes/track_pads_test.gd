extends PhysicsTest

## Plaques de la piste n°1, par les vraies Area3D, avec PadEffects (le gameplay
## des scenes de course) :
##   - 9 plaques de boost et 4 rampes de saut, a chevrons lumineux ;
##   A. boost : un camion a 100 km/h roule sur une plaque de la ligne droite
##      des stands. Il gagne au moins 35 km/h en 3 ticks (coup de pouce), reste
##      boost pendant 1,5 s, ne depasse pas la vitesse max + 40 km/h, joue son
##      son de boost (signal) une seule fois ; ensuite il redescend.
##   B. saut : un camion a 100 km/h monte la rampe du tremplin. Il s'envole
##      franchement (> 3,5 m au-dessus de la chaussee, plus d'une seconde en
##      l'air), reste a plat en vol (< 20 deg), et la reception est amortie :
##      vitesse de chute ramenee sous 3,5 m/s, 4 roues au sol, jamais couche.

const V0_KMH := 100.0
const BOOST_PAD := 7        # ligne droite des stands, a droite (circuit rallonge : 7)
const JUMP_PAD := 1         # tremplin, a droite (0 : montee, 2 : bosse, 3 : stands)

var _track: TrackBlockout
var _a: Truck
var _b: Truck
var _fa: InputFrame = InputFrame.new()
var _fb: InputFrame = InputFrame.new()
var _boosts: int = 0
var _boost_at: int = -1
var _v_before: float = 0.0
var _v_kick: float = 0.0
var _v_peak: float = 0.0
var _boost_ticks: int = 0
var _v_after: float = 0.0
var _launched: bool = false
var _max_height: float = 0.0
var _air_ticks: int = 0
var _air_tilt: float = 0.0
var _landed_at: int = -1
var _v_land: float = 0.0
var _max_tilt: float = 0.0
var _wheels_after: int = 0
var _b_idx: int = -1


func _test_setup() -> void:
	duration_ticks = 420
	_track = (load("res://tracks/track_01_blockout.tscn") as PackedScene).instantiate() as TrackBlockout
	add_child(_track)
	var pads := PadEffects.new()
	pads.track = _track
	add_child(pads)
	_a = _spawn_before(_track.boost_pad_transform(BOOST_PAD), 60.0)
	_a.boosted.connect(func() -> void: _boosts += 1)
	_b = _spawn_before(_track.jump_pad_transform(JUMP_PAD), 55.0)
	_track.jump_pad_entered.connect(func(body: Node3D, _i: int) -> void: _launched = _launched or body == _b)


## Camion pose `back` metres avant la plaque, a son decalage lateral, a 100 km/h.
func _spawn_before(pad: Transform3D, back: float) -> Truck:
	var i := _track.closest_sample(pad.origin)
	var lateral := (pad.origin - _track.sample_position(i)).dot(_track.sample_right(i))
	var xf := _track.frame_at(_track.sample_ahead(i, -back), lateral, 0.0)
	var t := (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
	t.transform = xf
	add_child(t)
	t.linear_velocity = -xf.basis.z * V0_KMH / 3.6
	return t


func _test_tick(t: int) -> void:
	# A. 100 km/h tenus jusqu'a la plaque, puis plein gaz
	var va := _a.get_speed_kmh()
	_fa.tick = t
	_fa.throttle = 1.0 if _boost_at >= 0 else clampf((V0_KMH - va) / 5.0, 0.0, 1.0)
	_a.set_input(_fa)
	if _boost_at < 0 and _boosts > 0:
		_boost_at = t
		_v_before = _v_prev_a
	if _boost_at >= 0:
		if t == _boost_at + 3:
			_v_kick = va
		_v_peak = maxf(_v_peak, va)
		if _a.is_boosting():
			_boost_ticks += 1
		if t == _boost_at + 90 + 180:
			_v_after = va
	_v_prev_a = va

	# B. plein gaz dans l'axe de la rampe ; frein 60 ticks apres la reception
	_fb.tick = t
	_fb.throttle = 1.0 if _landed_at < 0 else 0.0
	_fb.brake = 0.0 if _landed_at < 0 else 1.0
	_b.set_input(_fb)
	_b_idx = _track.closest_sample(_b.global_position, _b_idx)
	var height := (_b.global_position - _track.sample_position(_b_idx)).dot(_track.sample_up(_b_idx))
	_max_tilt = maxf(_max_tilt, TruckTestUtil.tilt_deg(_b))
	if _launched and _landed_at < 0:
		_max_height = maxf(_max_height, height)
		if _b.wheels_on_ground() == 0:
			_air_ticks += 1
			_air_tilt = maxf(_air_tilt, TruckTestUtil.tilt_deg(_b))
		elif _air_ticks > 30:
			_landed_at = t
	if _landed_at >= 0 and t == _landed_at + 2:
		_v_land = _b.linear_velocity.y
	if _landed_at >= 0 and t == _landed_at + 60:
		_wheels_after = _b.wheels_on_ground()


var _v_prev_a: float = 0.0


func _test_finish() -> void:
	check("9 plaques de boost, 4 rampes de saut",
		_track.boost_pad_count() == 9 and _track.jump_pad_count() == 4,
		"%d / %d" % [_track.boost_pad_count(), _track.jump_pad_count()])
	var pad := _track.get_node("Pads/BoostPad0/Chevrons") as MeshInstance3D
	check("plaque a chevrons orange (materiau)", pad != null
		and pad.material_override == preload("res://tracks/materials/boost_pad.tres"))
	print("  INFO   A : %.0f -> %.0f km/h en 3 ticks, pic %.0f, %d ticks de boost, %.0f km/h 3 s apres"
		% [_v_before, _v_kick, _v_peak, _boost_ticks, _v_after])
	check("A plaque de boost declenchee, un seul son de boost", _boosts == 1, "%d" % _boosts)
	check_above("A coup de pouce immediat (km/h en 3 ticks)", _v_kick - _v_before, 35.0)
	check_near("A boost pendant 1,5 s (ticks)", _boost_ticks, 90, 2)
	var top := _a.tuning.top_speed_kmh
	check_below("A jamais au-dela de vitesse max + 40 km/h", _v_peak, top + 40.0 + 2.0)
	check("A mesure 3 s apres la plaque faite", _v_after > 0.0)
	check_below("A 3 s apres la plaque : revenu a la vitesse max (km/h)", _v_after, top + 8.0)
	print("  INFO   B : %.1f m de haut, %d ticks en l'air, chute %.1f m/s avant amorti, %.1f m/s apres"
		% [_max_height, _air_ticks, _b.last_landing_fall_ms, _v_land])
	check("B rampe de saut declenchee", _launched)
	check_above("B saut franc : hauteur au-dessus de la chaussee (m)", _max_height, 3.5)
	check_above("B saut franc : temps en l'air (ticks)", _air_ticks, 60)
	check_below("B a plat en vol (deg)", _air_tilt, 20.0)
	check_above("B reception amortie : vitesse verticale apres contact (m/s)", _v_land, -3.5)
	check("B reception : 4 roues au sol", _wheels_after == 4, "%d" % _wheels_after)
	check_below("B jamais couche (deg)", _max_tilt, 45.0)
