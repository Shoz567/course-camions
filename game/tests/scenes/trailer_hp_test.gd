extends PhysicsTest

## Remorque larguee persistante (2026-10-02 ; 100 PV et morceaux, 2026-10-20) :
##   - O largue a l'arret puis s'en va (recharge par defaut, 30 s) ; a 32 s,
##     une nouvelle remorque est sur O et l'ancienne est toujours la ;
##   - a 61,7 s (au-dela des 60 s d'avant), elle est toujours sur la piste ;
##   - R1 la percute par l'arriere a 30 m/s : elle perd des PV selon l'energie
##     du choc, au plus MAX_HIT_SHARE (elle tient), R1 est ralenti ;
##   - R2 la percute de flanc a 20 m/s : elle cede (sous BREACH_RATIO : il la
##     perce et la traverse) ; R2 n'est pas penalise au-dela du choc.
## Vitesses posees au tick 0 et aux ticks de lancement (CLAUDE.md §10 b).

const DROP_AT := 5
const R1_AT := 3700
const R2_AT := 4000

var _o: Truck
var _r1: Truck
var _r2: Truck
var _trailer: DetachedTrailer
var _frames: Dictionary = {}
var _hits: Array[float] = []
var _destroyed: int = 0
var _fresh_at_32s: Array = []
var _alive_at_61s: bool = false
var _hp_after_r1: float = -1.0
var _r1_slowed: bool = false
var _explosion: bool = false
var _r2_x0: float = 0.0


func _test_setup() -> void:
	duration_ticks = R2_AT + 200
	add_floor(1200.0)
	_o = _spawn(Vector3(0.0, 0.0, 0.0), 0.0)
	# R1 attend loin derriere ; R2 attend sur le flanc droit de la remorque
	_r1 = _spawn(Vector3(0.0, 0.0, 60.0), 0.0)
	_r2 = _spawn(Vector3(70.0, 0.0, 60.0), 90.0)
	(_o.get_node("Cargo") as TruckCargo).dropped.connect(func(tr: DetachedTrailer) -> void:
		_trailer = tr
		tr.damaged.connect(func(amount: float, _hp: float) -> void: _hits.append(amount))
		tr.destroyed.connect(func() -> void: _destroyed += 1))
	_r1.cargo_hit_taken.connect(func() -> void: _r1_slowed = true)


func _spawn(pos: Vector3, yaw_deg: float) -> Truck:
	var t := TruckTestUtil.spawn_truck(self, pos, Vector3(0.0, yaw_deg, 0.0))
	_frames[t] = InputFrame.new()
	return t


func _test_tick(t: int) -> void:
	for tr: Truck in [_o, _r1, _r2]:
		var f: InputFrame = _frames[tr]
		f.tick = t
		f.cargo = tr == _o and t == DROP_AT
		# O s'eloigne de sa remorque larguee, puis s'arrete
		f.throttle = 1.0 if tr == _o and t > DROP_AT + 5 and t < 240 else 0.0
		f.brake = 1.0 if tr == _o and t >= 240 and t < 420 else 0.0
		tr.set_input(f)
	if t == R1_AT:
		_r1.linear_velocity = Vector3(0.0, 0.0, -30.0)
	if t == R2_AT - 20 and _trailer != null and is_instance_valid(_trailer):
		# R2 face au flanc de la remorque, la ou R1 l'a poussee
		var c := (_trailer.get_child(0) as Node3D).global_position
		_r2.reset_to(Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3(c.x + 30.0, 0.3, c.z)))
	if t == R2_AT:
		_r2_x0 = _r2.global_position.x
		_r2.linear_velocity = -_r2.global_basis.z * 20.0
	if t == 32 * 60:
		_fresh_at_32s = [not _o.is_trailer_detached(), _trailer != null and is_instance_valid(_trailer)]
	if t == 3700:
		_alive_at_61s = _trailer != null and is_instance_valid(_trailer)
	if t == R2_AT - 5 and _trailer != null and is_instance_valid(_trailer):
		_hp_after_r1 = _trailer.hp
	if not _explosion and not find_children("Explosion*", "", true, false).is_empty():
		_explosion = true


func _test_finish() -> void:
	print("  INFO   chocs %s ; PV apres R1 %.1f ; detruite %d fois" % [_hits, _hp_after_r1, _destroyed])
	check("32 s apres le largage : nouvelle remorque sur O, l'ancienne toujours la", _fresh_at_32s == [true, true],
		str(_fresh_at_32s))
	check("61,7 s apres le largage : toujours sur la piste (plus de disparition)", _alive_at_61s)
	check("R1 a 30 m/s : la remorque perd %d %% de ses PV au plus, elle tient"
		% roundi(DetachedTrailer.MAX_HIT_SHARE * 100.0), _hp_after_r1 > 0.0
		and absf(_hp_after_r1 - 100.0 * (1.0 - DetachedTrailer.MAX_HIT_SHARE)) < 0.01, "%.1f PV" % _hp_after_r1)
	check("R1 ralenti par le choc", _r1_slowed)
	check("R2 de flanc : elle cede (percee, ou detruite)", _destroyed == 1
		or (_trailer != null and is_instance_valid(_trailer) and _trailer.breaches >= 1), "%d" % _destroyed)
	check("R2 passe : la remorque ne fait plus barrage", _r2.global_position.x < _r2_x0 - 30.0,
		"%.1f m" % (_r2_x0 - _r2.global_position.x))
