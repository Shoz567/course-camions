extends PhysicsTest

## Pouvoir cargo : la remorque entiere se detache et fait barrage 60 s
## (detach_ticks par defaut, verifie a part). Pour garder la suite rapide, A
## largue avec un barrage de DETACH_A ticks (10 s) : le deroule est le meme.
##   A. A roule a 80 km/h et largue (front de l'InputFrame) : une
##      DetachedTrailer apparait a la place exacte de la remorque, la caisse
##      de collision du camion est coupee et son visuel de remorque masque ;
##      un second appui (pendant le largage, puis pendant la recharge) est
##      ignore ; au bout de 10 s la remorque larguee disparait et la remorque
##      se raccroche (caisse et visuel de retour).
##   B. jumeau de A sans largage : A, tracteur seul, va plus vite (+5 km/h
##      au moins apres 5 s).
##   C. C suit A dans la meme voie et percute la remorque larguee : il est
##      ralenti (<= 75 % de sa vitesse), sans se coucher ; A n'est jamais
##      penalise par sa propre remorque.
##   D. camion sur le toit : largage refuse.
##   E. recharge courte (6,7 s, largage 3,3 s) : largage, refus pendant le
##      largage puis pendant la recharge, raccrochage, nouveau largage.
## Vitesses initiales posees au tick 0 (CLAUDE.md §10 b).

const V0 := 22.0
const DROP_AT := 20
const DETACH_A := 600
const DETACH_DEFAULT_S := 60

var _a: Truck
var _b: Truck
var _c: Truck
var _d: Truck
var _e: Truck
var _frames: Dictionary = {}
var _drops: Dictionary = {}
var _trailer: DetachedTrailer
var _spawn_err: float = INF
var _kingpin_at_drop: Vector3
var _detached_ok: bool = false
var _hidden_ok: bool = false
var _speed_gain: float = 0.0
var _c_hit_at: int = -1
var _c_before: float = 0.0
var _c_after: float = 0.0
var _c_prev: float = 0.0
var _c_hit: bool = false
var _a_hit: bool = false
var _blinking: bool = false
var _alive_before: bool = false
var _gone_after: bool = false
var _reattached: bool = false
var _default_detach: int = 0
var _max_tilt: float = 0.0


func _test_setup() -> void:
	duration_ticks = DROP_AT + 700
	add_floor(3000.0)
	_a = _spawn(Vector3(0.0, 0.0, 1200.0), V0)
	_b = _spawn(Vector3(60.0, 0.0, 1200.0), V0)
	_c = _spawn(Vector3(0.0, 0.0, 1270.0), V0)
	_d = _spawn(Vector3(160.0, 3.5, 1200.0), 0.0)
	_d.rotation_degrees = Vector3(0.0, 0.0, 180.0)
	_e = _spawn(Vector3(240.0, 0.0, 1200.0), 0.0)
	var e_cargo := _e.get_node("Cargo") as TruckCargo
	e_cargo.cooldown_ticks = 400
	e_cargo.detach_ticks = 200
	var a_cargo := _a.get_node("Cargo") as TruckCargo
	_default_detach = a_cargo.detach_ticks
	a_cargo.detach_ticks = DETACH_A
	for t: Truck in [_a, _b, _c, _d, _e]:
		_drops[t] = 0
		(t.get_node("Cargo") as TruckCargo).dropped.connect(func(tr: DetachedTrailer) -> void:
			_drops[t] += 1
			if t == _a:
				_trailer = tr)
	_a.cargo_hit_taken.connect(func() -> void: _a_hit = true)
	_c.cargo_hit_taken.connect(func() -> void: _c_hit = true)


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
	_drive(_a, t, 1.0, t == DROP_AT or t == DROP_AT + 100 or t == DROP_AT + 650)
	_drive(_b, t, 1.0, false)
	_drive(_c, t, 1.0, false)
	_drive(_d, t, 0.0, t == 2)
	_drive(_e, t, 0.0, t == 10 or t == 60 or t == 330 or t == 450)
	if t == DROP_AT:
		# le largage se fait pendant le pas du camion, juste apres ce tick
		_kingpin_at_drop = _a.global_transform * TruckSpec.KINGPIN
	if t == DROP_AT + 1 and _trailer != null:
		_spawn_err = _trailer.global_position.distance_to(_kingpin_at_drop)
		var shape := _a.get_node("Trailer") as CollisionShape3D
		_detached_ok = _a.is_trailer_detached() and shape.disabled
		_hidden_ok = not (_a.get_node("Visual/TrailerPivot") as Node3D).visible
	if t == DROP_AT + 300:
		_speed_gain = _a.get_speed_kmh() - _b.get_speed_kmh()
	if _trailer != null and is_instance_valid(_trailer) and t == DROP_AT + 540:
		_blinking = _trailer.is_blinking()
	if t == DROP_AT + 590:
		_alive_before = _trailer != null and is_instance_valid(_trailer)
	if t == DROP_AT + 620:
		_gone_after = _trailer == null or not is_instance_valid(_trailer)
		var shape := _a.get_node("Trailer") as CollisionShape3D
		_reattached = not _a.is_trailer_detached() and not shape.disabled \
				and (_a.get_node("Visual/TrailerPivot") as Node3D).visible
	# C : vitesse juste avant le choc, puis 10 ticks apres
	var vc := _c.linear_velocity.length()
	if _c_hit_at < 0 and _c_hit:
		_c_hit_at = t
		_c_before = _c_prev
	if _c_hit_at > 0 and t == _c_hit_at + 10:
		_c_after = vc
	_c_prev = vc
	for tr: Truck in [_a, _b, _c]:
		_max_tilt = maxf(_max_tilt, TruckTestUtil.tilt_deg(tr))


func _test_finish() -> void:
	print("  INFO   A : %d largage(s), tracteur seul +%.1f km/h ; C %.1f -> %.1f m/s au choc (tick %d)"
		% [_drops[_a], _speed_gain, _c_before, _c_after, _c_hit_at])
	check("A largue sa remorque : une seule fois (largage puis recharge)", _drops[_a] == 1, "%d" % _drops[_a])
	check_below("remorque larguee a la place de la remorque (m, sellette)", _spawn_err, 1.0)
	check("A : caisse de remorque coupee pendant le largage", _detached_ok)
	check("A : visuel de remorque masque pendant le largage", _hidden_ok)
	check_above("A tracteur seul plus rapide que B (km/h)", _speed_gain, 5.0)
	check("C percute la remorque larguee", _c_hit_at > 0, "tick=%d" % _c_hit_at)
	if _c_hit_at > 0:
		check_below("C ralenti (vitesse apres / avant)", _c_after / maxf(_c_before, 0.1), 0.75)
	check("A jamais penalise par sa propre remorque", not _a_hit)
	check("la remorque larguee clignote avant de disparaitre", _blinking)
	check("barrage par defaut : %d s" % DETACH_DEFAULT_S,
		_default_detach == DETACH_DEFAULT_S * Engine.physics_ticks_per_second, "ticks=%d" % _default_detach)
	check("la remorque larguee tient 10 s", _alive_before)
	check("apres 10 s : elle disparait", _gone_after)
	check("apres 10 s : la remorque se raccroche (caisse et visuel)", _reattached)
	check("camion sur le toit : largage refuse", _drops[_d] == 0, "%d" % _drops[_d])
	check("E recharge courte : largage, raccrochage, nouveau largage", _drops[_e] == 2, "%d" % _drops[_e])
	check_below("personne ne se couche (deg)", _max_tilt, 45.0)
