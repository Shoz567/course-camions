extends PhysicsTest

## Scene de course (dev/track_drive.tscn, scene principale) : elle se charge,
## le compte a rebours immobilise le camion puis donne le depart, le HUD
## tourne sans erreur (le runner echoue sur toute SCRIPT ERROR). Et la camera
## bascule en vue cabine (oeil dans la cabine, regard vers l'avant) puis revient
## en poursuite (au-dela de la semi-remorque).

var _scene: Node3D
var _truck: Truck
var _camera: ChaseCamera
var _race: RaceLaps
var _moved_during_countdown: float = 0.0
var _started_at: int = -1
var _cockpit_dist: float = -1.0
var _cockpit_dot: float = -2.0
var _chase_dist: float = -1.0


func _test_setup() -> void:
	duration_ticks = 330
	_scene = (load("res://dev/track_drive.tscn") as PackedScene).instantiate() as Node3D
	add_child(_scene)
	_truck = _scene.get_node("Truck") as Truck
	_camera = _scene.get_node("ChaseCamera") as ChaseCamera
	_race = _scene.get_node("RaceLaps") as RaceLaps


func _test_tick(t: int) -> void:
	if t < 170:
		_moved_during_countdown = maxf(_moved_during_countdown, _truck.linear_velocity.length())
	if _started_at < 0 and _race.is_started():
		_started_at = t
	if t == 250:
		_camera.toggle_view()
	elif t == 280:
		var cam := _camera.get_camera().global_transform
		_cockpit_dist = cam.origin.distance_to(_truck.global_position)
		_cockpit_dot = (-cam.basis.z).dot(-_truck.global_transform.basis.z)
		_camera.toggle_view()
	elif t == 320:
		_chase_dist = _camera.get_camera().global_position.distance_to(_truck.global_position)


func _test_finish() -> void:
	check_below("compte a rebours : camion immobile (m/s)", _moved_during_countdown, 0.5)
	check("depart donne apres le compte a rebours", _started_at >= 170 and _started_at <= 200,
		"tick=%d" % _started_at)
	check_below("vue cabine : oeil pres du camion (m)", _cockpit_dist, 4.0)
	check_above("vue cabine : regard vers l'avant (cos)", _cockpit_dot, 0.95)
	check_above("retour en poursuite : au-dela de la remorque (m)", _chase_dist, 15.0)
