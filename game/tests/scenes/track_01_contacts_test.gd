extends PhysicsTest

## Piste n°1 : grille, reset et glissieres.
##
## A. Grille : 4 camions poses sur leurs cases ne se touchent pas, ne glissent
##    pas, restent sur leurs 4 roues (track-designer.md, regles dures).
## B. Reset : un camion retourne contre le mur de l'epingle relevee, et un autre
##    tombe dans l'herbe au pied de la crete (6 m plus bas), sont remis par
##    get_respawn_transform() : sur la chaussee, dans le sens de course
##    (cap a < 5 deg de la piste), sur leurs 4 roues.
## C. Glissiere : un camion a 120 km/h, a 12 m du mur droit, qui le vise a
##    20 deg, glisse le
##    long sans s'y encastrer : 60 ticks apres le premier contact, il avance
##    encore a >= 50 % de sa vitesse d'entree le long de la piste, sans jamais
##    grimper (< 1,5 m au-dessus de la chaussee) ni se coucher (< 45 deg).
##    Mesure sur les 90 ticks qui suivent le contact ; ensuite il freine (sans
##    direction, il traverserait la piste jusque dans l'epingle).

const RESET_AT := 30
const WALL_KMH := 120.0
const WALL_ANGLE_DEG := 20.0
const WALL_WINDOW := 90

var _track: TrackBlockout
var _grid: Array[Truck] = []
var _grid_start: Array[Vector3] = []
var _flipped: Truck
var _fallen: Truck
var _wall: Truck
var _wall_frame: InputFrame = InputFrame.new()
var _wall_contact: int = -1
var _wall_speed_after: float = -1.0
var _wall_max_rise: float = 0.0
var _wall_max_tilt: float = 0.0
var _wall_idx: int = -1


func _test_setup() -> void:
	duration_ticks = 180
	_track = (load("res://tracks/track_01_blockout.tscn") as PackedScene).instantiate() as TrackBlockout
	add_child(_track)
	for slot in 4:
		var t := _spawn(_track.get_start_transform(slot))
		t.contact_monitor = true
		t.max_contacts_reported = 4
		_grid.append(t)
		_grid_start.append(t.position)
	# B. retourne contre le mur exterieur de l'epingle (s = 250 m)
	var i_hairpin := _index_at(250.0)
	var flip := _track.frame_at(i_hairpin, 5.0, 2.0)
	flip.basis = flip.basis * Basis(Vector3.FORWARD, PI)
	_flipped = _spawn(flip)
	# B. dans l'herbe, 10 m a cote de la chaussee au milieu de la crete
	var i_crest := _index_at(_segment_start("Crete") + 40.0)
	var side := _track.sample_position(i_crest) + _track.sample_right(i_crest) * (_track.width / 2.0 + 10.0)
	_fallen = _spawn(Transform3D(Basis.IDENTITY, Vector3(side.x, 0.2, side.z)))
	# C. ligne droite de depart (s = 60 m), a 12 m du mur droit, cap tourne de
	# 20 deg vers la droite
	var i_wall := _index_at(60.0)
	var xf := _track.frame_at(i_wall, _track.width / 2.0 - 12.0, 0.0)
	xf.basis = Basis(Vector3.UP, -deg_to_rad(WALL_ANGLE_DEG)) * xf.basis
	_wall = _spawn(xf)
	_wall.linear_velocity = -xf.basis.z * WALL_KMH / 3.6
	_wall.contact_monitor = true
	_wall.max_contacts_reported = 4


func _spawn(xf: Transform3D) -> Truck:
	var t := (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
	t.transform = xf
	add_child(t)
	return t


## Abscisse du debut du segment nomme (droites auto comprises).
func _segment_start(seg_name: String) -> float:
	var s := 0.0
	var auto := 0
	for seg: Dictionary in _track.segments:
		if seg.get("name", "") == seg_name:
			return s
		if seg.get("type", "straight") == "arc":
			s += float(seg["radius"]) * deg_to_rad(absf(float(seg["angle"])))
		elif seg.get("auto", false):
			s += _track._auto_lengths[auto]
			auto += 1
		else:
			s += float(seg.get("length", 0.0))
	return -1.0


func _index_at(s: float) -> int:
	return roundi(s / (_track.length() / _track.sample_count()))


func _test_tick(t: int) -> void:
	if t == RESET_AT:
		_flipped.reset_to(_track.get_respawn_transform(_flipped.global_position))
		_fallen.reset_to(_track.get_respawn_transform(_fallen.global_position))

	var in_window := _wall_contact < 0 or t <= _wall_contact + WALL_WINDOW
	_wall_frame.tick = t
	_wall_frame.throttle = 1.0 if in_window else 0.0
	_wall_frame.brake = 0.0 if in_window else 1.0
	_wall.set_input(_wall_frame)
	_wall_idx = _track.closest_sample(_wall.global_position, _wall_idx)
	if not in_window:
		return
	var road := _track.sample_position(_wall_idx)
	_wall_max_rise = maxf(_wall_max_rise, (_wall.global_position - road).dot(_track.sample_up(_wall_idx)))
	_wall_max_tilt = maxf(_wall_max_tilt, TruckTestUtil.tilt_deg(_wall))
	if _wall_contact < 0 and _wall.get_contact_count() > 0:
		_wall_contact = t
	if _wall_contact > 0 and t == _wall_contact + 60:
		_wall_speed_after = _wall.linear_velocity.dot(_track.sample_forward(_wall_idx)) * 3.6


func _test_finish() -> void:
	# A. grille
	for k in _grid.size():
		var t := _grid[k]
		var drift := Vector2(t.position.x - _grid_start[k].x, t.position.z - _grid_start[k].z).length()
		check("grille case %d : 4 roues, aucun contact, derive < 5 cm" % k,
			t.wheels_on_ground() == 4 and t.get_contact_count() == 0 and drift < 0.05,
			"roues=%d contacts=%d derive=%.3f m" % [t.wheels_on_ground(), t.get_contact_count(), drift])
	# B. reset
	for pair: Array in [["retourne dans l'epingle", _flipped], ["tombe au pied de la crete", _fallen]]:
		var label: String = pair[0]
		var t: Truck = pair[1]
		var i := _track.closest_sample(t.global_position)
		var lateral := (t.global_position - _track.sample_position(i)).dot(_track.sample_right(i))
		var heading := rad_to_deg((-t.global_transform.basis.z).angle_to(_track.sample_forward(i)))
		check("reset %s : 4 roues sur la chaussee" % label,
			t.wheels_on_ground() == 4 and absf(lateral) < _track.width / 2.0,
			"roues=%d ecart lateral=%.1f m" % [t.wheels_on_ground(), lateral])
		check_below("reset %s : cap / sens de course (deg)" % label, heading, 5.0)
	# C. glissiere
	check("glissiere : contact avec le mur", _wall_contact > 0, "tick=%d" % _wall_contact)
	check_above("glissiere : vitesse le long de la piste 60 ticks apres le contact (km/h)",
		_wall_speed_after, WALL_KMH * 0.5)
	check_below("glissiere : jamais au-dessus de la chaussee (m)", _wall_max_rise, 1.5)
	check_below("glissiere : inclinaison max (deg)", _wall_max_tilt, 45.0)
