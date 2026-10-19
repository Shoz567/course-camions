extends PhysicsTest

## Reset automatique (tache 2.6) sur la piste n°1, avec AutoReset et les zones
## de reset de la piste (tache 2.4) :
##   A. un camion pose dans l'herbe au-dela du mur explose (chute, 2026-10-19)
##      des fall_min_ticks, puis reapparait sur la chaussee, dans le sens de
##      course, apres son temps d'epave ;
##   B. un camion retourne sur la chaussee est replace apres flipped_ticks ;
##   C. un camion qui frotte le mur avec sa semi-remorque a 100 km/h n'est
##      JAMAIS replace : les zones commencent au-dela du haut du mur.
##   D. un camion en l'air au-dessus des zones (sorti d'une corniche) n'est
##      plus replace en vol : il tombe, explose en touchant le sol, puis
##      reapparait sur la chaussee.

var _track: TrackBlockout
var _reset: AutoReset
var _outside: Truck
var _flipped: Truck
var _rubbing: Truck
var _flying: Truck
var _flying_y: float = 0.0
var _rub_frame: InputFrame = InputFrame.new()
var _resets: Dictionary = {}      # Truck -> [tick, raison]
var _crashes: Dictionary = {}     # Truck -> [tick, hauteur au-dessus du sol]
var _respawned: Dictionary = {}   # Truck -> tick
var _rub_contacts: int = 0


func _test_setup() -> void:
	duration_ticks = 470
	_track = (load("res://tracks/track_01_blockout.tscn") as PackedScene).instantiate() as TrackBlockout
	add_child(_track)
	_reset = AutoReset.new()
	_reset.track = _track
	add_child(_reset)
	_reset.truck_reset.connect(func(t: Truck, reason: StringName) -> void:
		if not _resets.has(t):
			_resets[t] = [tick, reason]
			if t == _flying:
				_flying_y = t.global_position.y)
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
	# D. 15 m au-dela du mur gauche (s = 300 m), 55 m au-dessus du sol
	var k := _index_at(300.0)
	var high := _track.sample_position(k) - _track.sample_right(k) * (_track.width / 2.0 + 15.0)
	_flying = _spawn(Transform3D(_track.frame_at(k, 0.0, 0.0).basis, Vector3(high.x, 55.0, high.z)))
	_reset.truck_crashed.connect(func(t: Truck) -> void:
		if not _crashes.has(t):
			_crashes[t] = [tick, t.global_position.y])
	for t in [_outside, _flipped, _rubbing, _flying]:
		_reset.watch(t)
		var h := TruckHealth.of(t)
		h.respawn_provider = func(tr: Truck) -> Transform3D: return _track.get_respawn_transform(tr.global_position)
		h.respawned.connect(func() -> void:
			if not _respawned.has(t):
				_respawned[t] = tick)


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
	check("A hors piste au sol : explose, jamais replace tel quel", _crashes.has(_outside) and not _resets.has(_outside))
	if _crashes.has(_outside):
		check_below("A hors piste : explose (ticks)", _crashes[_outside][0], _reset.fall_min_ticks + 10)
	check("A : reapparait apres son epave", _respawned.has(_outside))
	var ai := _track.closest_sample(_outside.global_position)
	check("A hors piste : sur la chaussee, dans le sens de course", _on_road(_outside), "roues=%d lat=%.1f cap=%.1f" % [
		_outside.wheels_on_ground(), (_outside.global_position - _track.sample_position(ai)).dot(_track.sample_right(ai)),
		rad_to_deg((-_outside.global_transform.basis.z).angle_to(_track.sample_forward(ai)))])
	check("B retourne : replace", _resets.has(_flipped))
	if _resets.has(_flipped):
		check("B retourne : raison", _resets[_flipped][1] == &"retourne", str(_resets[_flipped][1]))
		check_below("B retourne : delai (ticks)", _resets[_flipped][0], _reset.flipped_ticks + 60)
	check("B retourne : sur la chaussee, dans le sens de course", _on_road(_flipped))
	check("C frottement : la remorque a touche le mur", _rub_contacts > 0, "ticks=%d" % _rub_contacts)
	check("C frottement : jamais replace (pas de faux positif)", not _resets.has(_rubbing))
	check("D en l'air hors piste : jamais replace en vol", not _resets.has(_flying))
	check("D : explose en touchant le sol", _crashes.has(_flying))
	if _crashes.has(_flying):
		check_below("D : hauteur a l'explosion (m)", _crashes[_flying][1], 4.0)
	check("D : reapparait apres son epave", _respawned.has(_flying))
	var fi := _track.closest_sample(_flying.global_position)
	check("D en l'air : sur la chaussee, dans le sens de course", _on_road(_flying), "roues=%d lat=%.1f cap=%.1f" % [
		_flying.wheels_on_ground(), (_flying.global_position - _track.sample_position(fi)).dot(_track.sample_right(fi)),
		rad_to_deg((-_flying.global_transform.basis.z).angle_to(_track.sample_forward(fi)))])
