extends PhysicsTest

## Anti-collage de mur (demande du playtest a 4) : un camion qui frotte une
## glissiere ne doit jamais y rester aimante. Mur de 0,3 m, 2,8 m de haut,
## frottement 0,5 (celui de la piste), a droite des camions.
##   A. 120 km/h, braque en continu vers le mur : apres ~1,6 s de frottement
##      continu, il est decolle : -25 % de vitesse (+/- 6 %), repousse vers
##      l'interieur (> 3 m/s le long de la normale du mur). Tant qu'il force
##      contre le mur, ca recommence (au moins 2 fois en 8 s).
##   B. 120 km/h contre le mur, puis contre-braque : il s'en eloigne (> 6 m).
##   C. temoins : un camion qui roule loin des murs, un camion couche sur le
##      toit (contact avec le SOL, pas un mur) : jamais decolles.
## Personne ne se couche ni ne s'envole.

const V0 := 33.3
const WALL_X := 5.0

var _a: Truck
var _b: Truck
var _c: Truck
var _d: Truck
var _frames: Dictionary = {}
var _unsticks: Dictionary = {}
var _a_contact_at: int = -1
var _a_unstick_at: int = -1
var _a_before: float = 0.0
var _a_after: float = 0.0
var _a_push: float = 0.0
var _a_prev_speed: float = 0.0
var _b_min_x: float = INF
var _b_end_gap: float = 0.0
var _max_tilt: float = 0.0
var _max_y: float = 0.0


func _test_setup() -> void:
	duration_ticks = 480
	add_floor(2000.0)
	_a = _spawn(Vector3(2.0, 0.0, 700.0), V0)
	_add_wall(Vector3(WALL_X, 0.0, 500.0), 600.0)
	_b = _spawn(Vector3(202.0, 0.0, 700.0), V0)
	_add_wall(Vector3(200.0 + WALL_X, 0.0, 500.0), 600.0)
	_c = _spawn(Vector3(400.0, 0.0, 700.0), 25.0)
	_d = _spawn(Vector3(600.0, 3.5, 700.0), 0.0)
	_d.rotation_degrees = Vector3(0.0, 0.0, 180.0)
	for t: Truck in [_a, _b, _c, _d]:
		_unsticks[t] = 0
		t.wall_unstuck.connect(func(_n: Vector3) -> void: _unsticks[t] += 1)
	_a.wall_unstuck.connect(func(_n: Vector3) -> void:
		if _a_unstick_at < 0:
			_a_unstick_at = tick
			_a_before = _a_prev_speed)


func _spawn(p: Vector3, v: float) -> Truck:
	var t := TruckTestUtil.spawn_truck(self, p)
	t.linear_velocity = Vector3(0.0, 0.0, -v)
	_frames[t] = InputFrame.new()
	return t


func _add_wall(center: Vector3, length: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.5
	body.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.3, 2.8, length)
	cs.shape = box
	body.add_child(cs)
	body.position = center + Vector3(0.0, 1.4, 0.0)
	add_child(body)


func _drive(t: Truck, tick_i: int, steer: float, throttle: float) -> void:
	var f: InputFrame = _frames[t]
	f.tick = tick_i
	f.steer = steer
	f.throttle = throttle
	t.set_input(f)


func _test_tick(t: int) -> void:
	_drive(_a, t, 0.7, 1.0)
	_drive(_b, t, 0.35 if t < 120 else -0.6, 1.0)
	_drive(_c, t, 0.0, 1.0)
	_drive(_d, t, 0.0, 0.0)
	if _a_contact_at < 0 and _a.get_wall_contact_ticks() > 0:
		_a_contact_at = t
	if _a_unstick_at > 0 and t == _a_unstick_at + 3:
		_a_after = _a.linear_velocity.length()
		_a_push = -_a.linear_velocity.x   # normale du mur : vers -X
	_a_prev_speed = _a.linear_velocity.length()
	if OS.has_environment("WALL_TRACE") and t % 8 == 0:
		print("TRACE t=%d x=%.2f wall=%d yaw=%.1f v=%.1f" % [t, _a.global_position.x, _a.get_wall_contact_ticks(),
			rad_to_deg(_a.global_rotation.y), _a.linear_velocity.length()])
	if t >= 120:
		_b_min_x = minf(_b_min_x, _b.global_position.x - 200.0)
	_b_end_gap = (200.0 + WALL_X) - _b.global_position.x
	for tr: Truck in [_a, _b, _c]:
		_max_tilt = maxf(_max_tilt, TruckTestUtil.tilt_deg(tr))
		_max_y = maxf(_max_y, tr.global_position.y)


func _test_finish() -> void:
	print("  INFO   A : contact au tick %d, decolle au tick %d, %.1f -> %.1f m/s, repousse a %.1f m/s, %d decollages"
		% [_a_contact_at, _a_unstick_at, _a_before, _a_after, _a_push, _unsticks[_a]])
	print("  INFO   B : a %.1f m du mur a la fin (%d decollage(s))" % [_b_end_gap, _unsticks[_b]])
	check("A touche le mur", _a_contact_at > 0)
	check("A decolle apres 1,5 a 2,5 s de frottement", _a_unstick_at - _a_contact_at >= 90
		and _a_unstick_at - _a_contact_at <= 150, "%d ticks" % (_a_unstick_at - _a_contact_at))
	if _a_unstick_at > 0:
		check_near("A -25 % de vitesse au decollage (apres / avant)", _a_after / maxf(_a_before, 0.1), 0.75, 0.06)
		check_above("A repousse vers l'interieur (m/s)", _a_push, 3.0)
	check("A force contre le mur : decolle a nouveau", _unsticks[_a] >= 2, "%d" % _unsticks[_a])
	check_above("B contre-braque : s'eloigne du mur (m)", _b_end_gap, 6.0)
	check("temoins : jamais decolles (loin des murs, couche sur le sol)",
		_unsticks[_c] == 0 and _unsticks[_d] == 0, "%d / %d" % [_unsticks[_c], _unsticks[_d]])
	check_below("personne ne se couche (deg)", _max_tilt, 45.0)
	check_below("personne ne s'envole (m)", _max_y, 1.5)
