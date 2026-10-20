extends PhysicsTest

## Pouvoir cargo (2026-10-02) : la remorque entiere se detache et RESTE sur la
## piste ; apres la recharge (cooldown_ticks, 30 s par defaut), une nouvelle
## remorque apparait sur le camion. Pour garder la suite rapide, A recharge en
## COOLDOWN_A ticks (10 s) : le deroule est le meme.
##   A. A roule a 80 km/h et largue (front de l'InputFrame) : une
##      DetachedTrailer apparait a la place exacte de la remorque, la caisse
##      de collision du camion est coupee et son visuel de remorque masque ;
##      un second appui pendant la recharge est ignore ; au bout de 10 s, une
##      nouvelle remorque est sur le camion (caisse et visuel) et l'ancienne
##      est toujours sur la piste ; A largue de nouveau : deux remorques sur la
##      piste.
##   B. jumeau de A sans largage : A, tracteur seul, va plus vite (+5 km/h
##      au moins apres 5 s).
##   C. C suit A dans la meme voie, en roue libre (~75 km/h), et percute la
##      remorque larguee : il est ralenti (<= 75 % de sa vitesse), sans se
##      coucher, et la remorque perd des PV sans exploser (un choc plein gaz
##      a 117 km/h la detruisait : trailer_hp_test) ; A n'est jamais penalise
##      par sa propre remorque.
##   D. camion sur le toit : largage refuse.
##   E. recharge courte (6,7 s) : largage, refus pendant la recharge, nouvelle
##      remorque, nouveau largage.
##   F. verrou de depart (start_race_lock, 5 s) : refuse a 1,6 s, avec
##      « VERROU » au HUD, accepte a 5,3 s.
## Vitesses initiales posees au tick 0 (CLAUDE.md §10 b).

const V0 := 22.0
const DROP_AT := 20
const COOLDOWN_A := 600

var _a: Truck
var _b: Truck
var _c: Truck
var _d: Truck
var _e: Truck
var _f: Truck
var _frames: Dictionary = {}
var _drops: Dictionary = {}
var _trailer: DetachedTrailer
var _a_trailers: Array[DetachedTrailer] = []
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
var _trailer_damage: float = 0.0
var _fresh_trailer: bool = false
var _old_still_there: bool = false
var _f_status: String = ""
var _defaults: Array = []
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
	_f = _spawn(Vector3(320.0, 0.0, 1200.0), 0.0)
	var a_cargo := _a.get_node("Cargo") as TruckCargo
	_defaults = [a_cargo.cooldown_ticks, a_cargo.first_seconds_lock_ticks]
	a_cargo.cooldown_ticks = COOLDOWN_A
	(_e.get_node("Cargo") as TruckCargo).cooldown_ticks = 400
	# le delai apres le retour (rearm_ticks, 20 s) a son test : trailer_drops_test
	a_cargo.rearm_ticks = 0
	(_e.get_node("Cargo") as TruckCargo).rearm_ticks = 0
	(_f.get_node("Cargo") as TruckCargo).start_race_lock()
	for t: Truck in [_a, _b, _c, _d, _e, _f]:
		_drops[t] = 0
		(t.get_node("Cargo") as TruckCargo).dropped.connect(func(tr: DetachedTrailer) -> void:
			_drops[t] += 1
			if t == _a:
				_a_trailers.append(tr)
				if _trailer == null:
					_trailer = tr
					tr.damaged.connect(func(amount: float, _hp: float) -> void: _trailer_damage += amount))
	_a.cargo_hit_taken.connect(func() -> void: _a_hit = true)
	_c.cargo_hit_taken.connect(func() -> void: _c_hit = true)


func _spawn(p: Vector3, v: float) -> Truck:
	var t := TruckTestUtil.spawn_truck(self, p)
	t.linear_velocity = Vector3(0.0, 0.0, -v)
	_frames[t] = InputFrame.new()
	return t


func _drive(t: Truck, tick: int, throttle: float, cargo: bool, brake: float = 0.0) -> void:
	var f: InputFrame = _frames[t]
	f.tick = tick
	f.throttle = throttle
	f.brake = brake
	f.cargo = cargo
	t.set_input(f)


func _test_tick(t: int) -> void:
	_drive(_a, t, 1.0, t == DROP_AT or t == DROP_AT + 100 or t == DROP_AT + 650)
	_drive(_b, t, 1.0, false)
	_drive(_c, t, 0.0, false)
	_drive(_d, t, 0.0, t == 2)
	# E s'eloigne de sa remorque larguee, s'arrete, puis attend la nouvelle
	_drive(_e, t, 1.0 if t > 20 and t < 200 else 0.0, t == 10 or t == 60 or t == 330 or t == 450,
		1.0 if t >= 200 and t < 320 else 0.0)
	_drive(_f, t, 0.0, t == 100 or t == 320)
	if t == 101:
		_f_status = (_f.get_node("Cargo") as TruckCargo).status_text()
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
	if t == DROP_AT + 640:
		var shape := _a.get_node("Trailer") as CollisionShape3D
		_fresh_trailer = not _a.is_trailer_detached() and not shape.disabled \
				and (_a.get_node("Visual/TrailerPivot") as Node3D).visible
		_old_still_there = _trailer != null and is_instance_valid(_trailer)
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
	print("  INFO   A : %d largage(s), tracteur seul +%.1f km/h ; C %.1f -> %.1f m/s au choc (tick %d), remorque -%.1f PV"
		% [_drops[_a], _speed_gain, _c_before, _c_after, _c_hit_at, _trailer_damage])
	check("reglages par defaut : recharge 30 s, verrou de depart 5 s", _defaults == [1800, 300], str(_defaults))
	check_below("remorque larguee a la place de la remorque (m, sellette)", _spawn_err, 1.0)
	check("A : caisse de remorque coupee pendant le largage", _detached_ok)
	check("A : visuel de remorque masque pendant le largage", _hidden_ok)
	check_above("A tracteur seul plus rapide que B (km/h)", _speed_gain, 5.0)
	check("C percute la remorque larguee", _c_hit_at > 0, "tick=%d" % _c_hit_at)
	if _c_hit_at > 0:
		check_below("C ralenti (vitesse apres / avant)", _c_after / maxf(_c_before, 0.1), 0.75)
	check_above("la remorque percutee perd des PV", _trailer_damage, 1.0)
	check("A jamais penalise par sa propre remorque", not _a_hit)
	check("apres la recharge : nouvelle remorque sur A (caisse et visuel)", _fresh_trailer)
	check("l'ancienne remorque reste sur la piste (plus de disparition)", _old_still_there)
	var alive := 0
	for tr in _a_trailers:
		alive += 1 if is_instance_valid(tr) else 0
	check("A : refuse pendant la recharge, puis largue de nouveau ; 2 remorques sur la piste",
		_drops[_a] == 2 and alive == 2, "%d largages, %d sur la piste" % [_drops[_a], alive])
	check("camion sur le toit : largage refuse", _drops[_d] == 0, "%d" % _drops[_d])
	check("E recharge courte : largage, nouvelle remorque, nouveau largage", _drops[_e] == 2, "%d" % _drops[_e])
	check("F verrou de depart : refuse a 1,6 s (VERROU au HUD), accepte a 5,3 s",
		_drops[_f] == 1 and _f_status.begins_with("VERROU"), "%d largage(s), « %s »" % [_drops[_f], _f_status])
	check_below("personne ne se couche (deg)", _max_tilt, 45.0)
