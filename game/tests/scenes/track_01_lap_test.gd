extends PhysicsTest

## Piste n°1 : un camion pilote (TrackAutopilot, par InputFrame) part de la
## pole et boucle un tour (track-designer.md, regles dures). En meme temps, la
## camera de poursuite le suit (tache 2.1).
##
## Piste :
##   - un tour complet, en 60 a 90 s (METRICS.md §4, duree de tour) ;
##   - jamais retourne (inclinaison < 45 deg), jamais hors de la chaussee,
##     aucun NaN ; le tremplin est sur la ligne de course et il est franchi ;
##   - geometrie : boucle fermee, largeur >= 14 m et murs >= 0,3 m (METRICS §4).
## Camera :
##   - jamais masquee : aucun obstacle entre son pivot et elle ;
##   - toujours a bonne distance du camion (3 a 20 m) ;
##   - ne tremble pas : le tremblement est la part HAUTE FREQUENCE de la
##     hauteur (ecart a une moyenne glissante de 15 ticks, soit ce qui depasse
##     ~4 Hz : pompage, bosses, chocs de reception). Celle de la camera doit
##     etre au plus la moitie de celle du camion (ratio mesure dans la scene).
##     Les mouvements lents (collines, parabole du saut) sont suivis : c'est
##     voulu.

const MAX_TICKS := 7000

var _track: TrackBlockout
var _truck: Truck
var _camera: ChaseCamera
var _pilot: TrackAutopilot

var _prev_s: float = -1.0
var _progress: float = 0.0
var _lap_start: int = -1
var _lap_end: int = -1
var _max_tilt: float = 0.0
var _upside: bool = false
var _off_track: int = 0
var _wall_ticks: int = 0
var _airborne: int = 0
var _occluded: int = 0
var _cam_dist_min: float = INF
var _cam_dist_max: float = 0.0
var _cam_y: PackedFloat32Array = []
var _truck_y: PackedFloat32Array = []


func _test_setup() -> void:
	duration_ticks = MAX_TICKS
	_track = (load("res://tracks/track_01_blockout.tscn") as PackedScene).instantiate() as TrackBlockout
	add_child(_track)
	_truck = (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
	_truck.transform = _track.get_start_transform(0)
	_truck.contact_monitor = true
	_truck.max_contacts_reported = 4
	add_child(_truck)
	_camera = ChaseCamera.new()
	_camera.target = _truck
	add_child(_camera)
	var g: Variant = require_baseline("max_lateral_g")
	if g == null:
		return
	_pilot = TrackAutopilot.new(_track, _truck, float(g))


func _test_tick(t: int) -> void:
	_truck.set_input(_pilot.drive(t))
	var p := _truck.global_position
	if not p.is_finite():
		abort("NaN sur la position du camion au tick %d" % t)
		return
	# progression le long de la ligne centrale (tour = longueur de piste)
	var i := _pilot.index
	var s := _track.sample_s(i)
	if _prev_s >= 0.0:
		var ds := s - _prev_s
		if ds < -_track.length() / 2.0:
			ds += _track.length()
		elif ds > _track.length() / 2.0:
			ds -= _track.length()
		_progress += ds
	_prev_s = s
	# la pole est derriere la ligne : le tour part au passage de s = 0
	if _lap_start < 0 and _progress >= _track.grid_distance:
		_lap_start = t
	if _lap_end < 0 and _progress >= _track.grid_distance + _track.length():
		_lap_end = t
		duration_ticks = t + 30

	_max_tilt = maxf(_max_tilt, TruckTestUtil.tilt_deg(_truck))
	_upside = _upside or _truck.is_upside_down()
	var lateral := (p - _track.sample_position(i)).dot(_track.sample_right(i))
	if absf(lateral) > _track.width / 2.0:
		_off_track += 1
	if _truck.get_contact_count() > 0:
		_wall_ticks += 1
	if _truck.wheels_on_ground() == 0:
		_airborne += 1

	# camera : mise a jour dans _process, lue ici au tick suivant
	if t > 30:
		var cam := _camera.get_camera().global_position
		var pivot := _camera.global_position
		var q := PhysicsRayQueryParameters3D.create(pivot, cam, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			_occluded += 1
		var dist := cam.distance_to(p)
		_cam_dist_min = minf(_cam_dist_min, dist)
		_cam_dist_max = maxf(_cam_dist_max, dist)
		_cam_y.append(cam.y)
		_truck_y.append(_truck.get_global_transform_interpolated().origin.y)


## Ecart quadratique moyen a la moyenne glissante (+/- `half` echantillons) :
## la part haute frequence du signal.
static func high_frequency_rms(y: PackedFloat32Array, half: int) -> float:
	var acc := 0.0
	var n := 0
	for i in range(half, y.size() - half):
		var m := 0.0
		for k in range(-half, half + 1):
			m += y[i + k]
		m /= 2 * half + 1
		acc += (y[i] - m) * (y[i] - m)
		n += 1
	return sqrt(acc / maxi(n, 1))


func _test_finish() -> void:
	var n := _track.sample_count()
	var step := _track.length() / n
	check_near("boucle fermee : dernier -> premier echantillon (m)",
		_track.sample_position(n - 1).distance_to(_track.sample_position(0)), step, 0.2)
	check("largeur >= 14 m (METRICS.md §4)", _track.width >= 14.0, "largeur=%.1f" % _track.width)
	check("murs >= 0,3 m (METRICS.md §4)", _track.wall_thickness >= 0.3, "epaisseur=%.2f" % _track.wall_thickness)

	check("tour complet", _lap_end > 0, "progression=%.0f m / %.0f m" % [_progress, _track.length() + _track.grid_distance])
	if _lap_end > 0:
		var lap_s := (_lap_end - _lap_start) / 60.0
		check_near("duree du tour (s) dans 60 .. 90 (METRICS.md §4)", lap_s, 75.0, 15.0)
	check("jamais retourne", not _upside)
	check_below("inclinaison max (deg)", _max_tilt, 45.0)
	check("jamais hors de la chaussee", _off_track == 0, "ticks=%d" % _off_track)
	check_above("tremplin franchi : ticks en l'air", _airborne, 10)
	print("  INFO   longueur %.1f m, contact de caisse %d ticks, en l'air %d ticks"
		% [_track.length(), _wall_ticks, _airborne])

	check("camera jamais masquee par la piste", _occluded == 0, "ticks=%d" % _occluded)
	check("camera a bonne distance (3 .. 20 m)", _cam_dist_min >= 3.0 and _cam_dist_max <= 20.0,
		"min=%.1f max=%.1f" % [_cam_dist_min, _cam_dist_max])
	var hf_truck := high_frequency_rms(_truck_y, 7)
	var hf_cam := high_frequency_rms(_cam_y, 7)
	check_ratio_above("camera sans tremblement : haute frequence camion / camera",
		hf_truck, hf_cam, 2.0)
