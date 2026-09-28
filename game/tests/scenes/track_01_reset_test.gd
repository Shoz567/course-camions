extends PhysicsTest

## Reset automatique (tache 2.6) sur la piste n°1, avec AutoReset et les zones
## de reset de la piste (tache 2.4) :
##   A. un camion pose dans l'herbe au-dela du mur est replace sur la chaussee,
##      dans le sens de course, en zone_ticks (+ quelques ticks de detection) ;
##   B. un camion retourne sur la chaussee est replace apres flipped_ticks ;
##   C. un camion qui frotte le mur avec sa semi-remorque a 100 km/h n'est
##      JAMAIS replace : les zones commencent au-dela du haut du mur.

var _track: TrackBlockout
var _reset: AutoReset
var _outside: Truck
var _flipped: Truck
var _rubbing: Truck
var _rub_frame: InputFrame = InputFrame.new()
var _resets: Dictionary = {}      # Truck -> [tick, raison]
var _rub_contacts: int = 0


func _test_setup() -> void:
	duration_ticks = 240
	_track = (load("res://tracks/track_01_blockout.tscn") as PackedScene).instantiate() as TrackBlockout
	add_child(_track)
	_reset = AutoReset.new()
	_reset.track = _track
	add_child(_reset)
	_reset.truck_reset.connect(func(t: Truck, reason: StringName) -> void:
		if not _resets.has(t):
			_resets[t] = [tick, reason])
	# A. dans l'herbe, 12 m au-dela du mur droit de la ligne droite (s = 100 m)
	var i := _index_at(100.0)
	var out := _track.sample_position(i) + _track.sample_right(i) * (_track.width / 2.0 + 12.0)
	_outside = _spawn(Transform3D(_track.frame_at(i, 0.0, 0.0).basis, Vector3(out.x, 0.3, out.z)))
	# B. retourne au milieu de la chaussee (s = 150 m)
	var flip := _track.frame_at(_index_at(150.0), 0.0, 3.0)
	flip.basis = flip.basis * Basis(Vector3.FORWARD, PI)
	_flipped = _spawn(flip)
	# C. le long du mur gauche de la ligne des stands, a 100 km/h, cap tourne
	#    de 4 deg vers le mur : la remorque (3 m de large) vient le frotter
	var j := _index_at(_track.length() - 500.0)
	var xf := _track.frame_at(j, -(_track.width / 2.0 - 2.5), 0.0)
	xf.basis = Basis(Vector3.UP, deg_to_rad(4.0)) * xf.basis
	_rubbing = _spawn(xf)
	_rubbing.linear_velocity = -xf.basis.z * 100.0 / 3.6
	_rubbing.contact_monitor = true
	_rubbing.max_contacts_reported = 4
	for t in [_outside, _flipped, _rubbing]:
		_reset.watch(t)


func _spawn(xf: Transform3D) -> Truck:
	var t := (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
	t.transform = xf
	add_child(t)
	return t


func _index_at(s: float) -> int:
	return roundi(s / (_track.length() / _track.sample_count()))


func _test_tick(t: int) -> void:
	_rub_frame.tick = t
	_rub_frame.throttle = clampf((100.0 - _rubbing.get_speed_kmh()) / 5.0, 0.0, 1.0)
	_rubbing.set_input(_rub_frame)
	if _rubbing.get_contact_count() > 0:
		_rub_contacts += 1


func _on_road(t: Truck) -> bool:
	var i := _track.closest_sample(t.global_position)
	var lateral := (t.global_position - _track.sample_position(i)).dot(_track.sample_right(i))
	var heading := rad_to_deg((-t.global_transform.basis.z).angle_to(_track.sample_forward(i)))
	return t.wheels_on_ground() == 4 and absf(lateral) < _track.width / 2.0 and heading < 5.0


func _test_finish() -> void:
	check("A hors piste : replace", _resets.has(_outside))
	if _resets.has(_outside):
		check_below("A hors piste : delai (ticks)", _resets[_outside][0], _reset.zone_ticks + 10)
	check("A hors piste : sur la chaussee, dans le sens de course", _on_road(_outside))
	check("B retourne : replace", _resets.has(_flipped))
	if _resets.has(_flipped):
		check("B retourne : raison", _resets[_flipped][1] == &"retourne", str(_resets[_flipped][1]))
		check_below("B retourne : delai (ticks)", _resets[_flipped][0], _reset.flipped_ticks + 60)
	check("B retourne : sur la chaussee, dans le sens de course", _on_road(_flipped))
	check("C frottement : la remorque a touche le mur", _rub_contacts > 0, "ticks=%d" % _rub_contacts)
	check("C frottement : jamais replace (pas de faux positif)", not _resets.has(_rubbing))
