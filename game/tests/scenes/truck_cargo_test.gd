extends PhysicsTest

## Largage de cargo (ZL) : barriere ephemere.
##   A. A roule a 80 km/h et largue (front de l'InputFrame) : une caisse est
##      posee au sol derriere sa remorque ; un second appui pendant la
##      recharge est ignore ; recharge affichee 30 s.
##   B. B suit A dans la meme voie et percute la caisse : il est ralenti
##      (<= 75 % de sa vitesse) et deporte en lacet, sans se coucher ni
##      s'envoler. A, qui l'a larguee, n'est jamais penalise.
##   C. Anti-jeu : la caisse clignote a partir de 3 s et disparait a 5 s.
##   D. Recharge courte (2 s) sur C : largage, refus pendant la recharge, puis
##      nouveau largage une fois la recharge finie.
##   E. Cas limites : camion sur le toit, largage refuse ; camion en l'air,
##      la caisse part de derriere la remorque et retombe au sol.
## Vitesses initiales posees au tick 0 (CLAUDE.md §10 b).

const V0 := 22.0
const DROP_AT := 20

var _a: Truck
var _b: Truck
var _c: Truck
var _frames: Dictionary = {}
var _drops_a: int = 0
var _drops_c: int = 0
var _crate: CargoCrate
var _crate_ok: bool = false
var _crate_behind: float = 0.0
var _crate_height: float = -1.0
var _seconds_left: int = -1
var _b_hit_at: int = -1
var _b_before: float = 0.0
var _b_after: float = 0.0
var _b_yaw: float = 0.0
var _a_hit: bool = false
var _b_prev_speed: float = 0.0
var _b_hit_pending: bool = false
var _hidden_ticks: int = 0
var _blinking_at_250: bool = false
var _alive_at_318: bool = false
var _gone_at_322: bool = false
var _max_tilt: float = 0.0
var _d: Truck
var _e: Truck
var _drops_d: int = 0
var _e_crate: CargoCrate
var _e_crate_y: float = -1.0
var _max_y: float = 0.0


func _test_setup() -> void:
	duration_ticks = 330
	add_floor(2000.0)
	_a = _spawn(Vector3(0.0, 0.0, 600.0), V0)
	_b = _spawn(Vector3(0.0, 0.0, 660.0), V0)
	_c = _spawn(Vector3(80.0, 0.0, 600.0), 0.0)
	(_c.get_node("Cargo") as TruckCargo).cooldown_ticks = 120
	(_a.get_node("Cargo") as TruckCargo).dropped.connect(func(cr: CargoCrate) -> void:
		_drops_a += 1
		_crate = cr)
	(_c.get_node("Cargo") as TruckCargo).dropped.connect(func(_cr: CargoCrate) -> void: _drops_c += 1)
	_a.cargo_hit_taken.connect(func() -> void: _a_hit = true)
	_d = _spawn(Vector3(160.0, 3.5, 600.0), 0.0)
	_d.rotation_degrees = Vector3(0.0, 0.0, 180.0)
	(_d.get_node("Cargo") as TruckCargo).dropped.connect(func(_cr: CargoCrate) -> void: _drops_d += 1)
	_e = _spawn(Vector3(240.0, 8.0, 600.0), 0.0)
	(_e.get_node("Cargo") as TruckCargo).dropped.connect(func(cr: CargoCrate) -> void: _e_crate = cr)
	_b.cargo_hit_taken.connect(func() -> void: _b_hit_pending = true)


func _spawn(p: Vector3, v: float) -> Truck:
	var t := TruckTestUtil.spawn_truck(self, p)
	t.linear_velocity = Vector3(0.0, 0.0, -v)
	_frames[t] = InputFrame.new()
	return t


func _drive(t: Truck, tick: int, throttle: float, cargo: bool) -> void:
	var f: InputFrame = _frames[t]
	f.tick = tick
	f.throttle = throttle
	f.cargo = cargo
	t.set_input(f)


func _test_tick(t: int) -> void:
	_drive(_a, t, 1.0, t == DROP_AT or t == DROP_AT + 20)
	_drive(_b, t, 1.0, false)
	_drive(_c, t, 0.0, t == 10 or t == 60 or t == 140)
	_drive(_d, t, 0.0, t == 2)   # encore a l'envers (l'assiette auto le redresse ensuite)
	_drive(_e, t, 0.0, t == 3)
	if t == 120 and _e_crate != null and is_instance_valid(_e_crate):
		_e_crate_y = _e_crate.global_position.y

	if t == DROP_AT + 2:
		_seconds_left = (_a.get_node("Cargo") as TruckCargo).seconds_left()
	if _crate != null and is_instance_valid(_crate):
		if t == DROP_AT + 1:
			_crate_ok = true
			_crate_behind = (_crate.global_position - _a.global_position).dot(_a.global_basis.z)
		if t == DROP_AT + 30:
			_crate_height = _crate.global_position.y
		if t > DROP_AT + 180 and not (_crate.get_node("Mesh") as MeshInstance3D).visible:
			_hidden_ticks += 1
		if t == DROP_AT + 230:
			_blinking_at_250 = _crate.is_blinking()
	if t == DROP_AT + 298:
		_alive_at_318 = _crate != null and is_instance_valid(_crate)
	if t == DROP_AT + 302:
		_gone_at_322 = _crate == null or not is_instance_valid(_crate)

	# B : vitesse juste avant le choc, puis 10 ticks apres
	var vb := _b.linear_velocity.length()
	if _b_hit_at < 0 and _b_hit_pending:
		_b_hit_at = t
		_b_before = _b_prev_speed
	if _b_hit_at > 0 and t == _b_hit_at + 10:
		_b_after = vb
	if _b_hit_at > 0 and t <= _b_hit_at + 20:
		_b_yaw = maxf(_b_yaw, absf(_b.angular_velocity.y))
	_b_prev_speed = vb
	for tr: Truck in [_a, _b, _c]:
		_max_tilt = maxf(_max_tilt, TruckTestUtil.tilt_deg(tr))
		_max_y = maxf(_max_y, tr.global_position.y)


func _test_finish() -> void:
	print("  INFO   caisse a %.1f m derriere A ; B %.1f -> %.1f m/s au choc (tick %d), lacet %.2f rad/s"
		% [_crate_behind, _b_before, _b_after, _b_hit_at, _b_yaw])
	check("A largue une caisse, un seul largage pendant la recharge", _crate_ok and _drops_a == 1,
		"largages=%d" % _drops_a)
	check("A recharge affichee : 30 s", _seconds_left == 30, "%d s" % _seconds_left)
	check_above("caisse derriere la remorque (m)", _crate_behind, 14.0)
	check_near("caisse posee au sol (hauteur du centre, m)", _crate_height, CargoCrate.SIZE.y / 2.0, 0.15)
	check("B percute la caisse", _b_hit_at > 0, "tick=%d" % _b_hit_at)
	if _b_hit_at > 0:
		check_below("B ralenti (vitesse apres / avant)", _b_after / maxf(_b_before, 0.1), 0.75)
		check_above("B deporte en lacet (rad/s)", _b_yaw, 0.5)
	check("A, qui l'a larguee, jamais penalise", not _a_hit)
	check("la caisse clignote apres 3 s", _blinking_at_250 and _hidden_ticks > 0, "masquee %d ticks" % _hidden_ticks)
	check("la caisse vit jusqu'a 5 s", _alive_at_318)
	check("la caisse disparait a 5 s", _gone_at_322)
	check("C recharge courte : largage, refus, nouveau largage", _drops_c == 2, "largages=%d" % _drops_c)
	check("camion sur le toit : largage refuse", _drops_d == 0, "%d" % _drops_d)
	check_near("largue en l'air : la caisse retombe au sol (hauteur, m)", _e_crate_y, CargoCrate.SIZE.y / 2.0, 0.15)
	check_below("personne ne se couche (deg)", _max_tilt, 45.0)
	check_below("personne ne s'envole (m)", _max_y, 1.5)
