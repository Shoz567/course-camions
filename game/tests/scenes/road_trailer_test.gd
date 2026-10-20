extends PhysicsTest

## Remorques larguees (2026-10-20 : « qu'elles prennent des degats au meme
## titre que les remorques attelees, meme visuels ; augmenter leurs PV ; plus
## elle prend de degats, qu'elle se casse en plusieurs morceaux, faire un trou
## en rentrant dedans ; quand elle est vraiment tres abimee, elle explose ») :
## quatre camions larguent leur remorque (TruckCargo.drop), puis s'en vont ;
##   A. PV sur la route : ceux de la remorque attelee fois ROAD_HP_MULT ;
##   B. un missile tire dans l'arriere de T1 : -MISSILE_DAMAGE, traces, et un
##      premier palier de morceaux (20 % perdus) ;
##   C. le laser sur T2 : -LASER_TICKS x LASER_DAMAGE_PER_TICK, traces ;
##   D. un camion percute T3 (neuve) plein gaz, a ~100 km/h : le choc ne lui
##      retire que MAX_HIT_SHARE de ses PV (elle tient), elle passe sous
##      BREACH_RATIO et il la traverse (trou), ressort devant, s'y abime et y
##      perd des PV ;
##   E. T4 a bout : elle explose et disparait.

var _drops: Array[Truck] = []
var _trailers: Array[DetachedTrailer] = []
var _missile: Truck
var _laser: Truck
var _ram: Truck
var _pm: TruckPowers
var _pl: TruckPowers
var _seen: Dictionary = {}
var _t4_gone: bool = false


func _test_setup() -> void:
	duration_ticks = 300
	add_floor(4000.0)
	for i in 4:
		_drops.append(TruckTestUtil.spawn_truck(self, Vector3(i * 300.0, 0.0, 0.0)))
	_missile = _spawn(Vector3(0.0, 0.0, 45.0))
	_laser = _spawn(Vector3(300.0, 0.0, 45.0))
	_ram = _spawn(Vector3(600.0, 0.0, 60.0))
	_pm = TruckPowers.setup(_missile, PowerCatalog.Id.MISSILE, -1)
	_pl = TruckPowers.setup(_laser, PowerCatalog.Id.LASER, -1)


func _spawn(at: Vector3) -> Truck:
	var t := TruckTestUtil.spawn_truck(self, at)
	t.add_to_group(TruckPowers.TARGETS)
	return t


func _hp(t: Truck) -> float:
	return TruckHealth.of(t).hp


func _test_tick(t: int) -> void:
	match t:
		5:
			for d in _drops:
				var dt := (d.get_node(^"Cargo") as TruckCargo).drop()
				_trailers.append(dt)
		8:
			# les camions qui ont largue s'en vont (plus de collision avec elles)
			for i in _drops.size():
				_drops[i].reset_to(Transform3D(Basis.IDENTITY, Vector3(i * 300.0 + 150.0, 0.5, -200.0)))
			var h0 := TruckHealth.of(_drops[0])
			_seen["hp"] = [_trailers[0].max_hp, h0.trailer_max_hp * DetachedTrailer.ROAD_HP_MULT, _trailers[0].hp]
			_seen["ram0"] = _hp(_ram)
			_seen["t3_0"] = _trailers[2].hp
		20:
			_pm.use(0)
			_pl.use(0)
			_trailers[3].power_hit(10000.0, _trailers[3].global_position + Vector3.UP * 3.0, Vector3.FORWARD, 18.0)
			_trailers[3].destroyed.connect(func() -> void: _t4_gone = true)
	if t >= 20 and t <= 140:
		# le belier fonce dans l'arriere de T3, plein gaz
		var f := InputFrame.new()
		f.throttle = 1.0
		_ram.set_input(f)
		if t == 20:
			_ram.linear_velocity = Vector3(0.0, 0.0, -22.0)
	if t == 140:
		var t1 := _trailers[0]
		_seen["t1"] = [t1.max_hp - t1.hp, t1.mark_count(), t1.breaks]
		var t2 := _trailers[1]
		_seen["t2"] = [t2.max_hp - t2.hp, t2.mark_count()]
	if t == 290:
		var t3 := _trailers[2]
		var front := t3.global_transform * Vector3(0.0, 0.0, t3.box_center.z - t3.box_size.z / 2.0)
		_seen["breach"] = [t3.breaches, _ram.global_position.z < front.z, float(_seen.get("t3_0", 0.0)) - t3.hp,
			float(_seen.get("ram0", 0.0)) - _hp(_ram), _ram.global_position.z, front.z,
			(_ram.get_node(^"DamageFx") as TruckDamageFx).marks(false).size()]
		_seen["t4"] = [_t4_gone, not is_instance_valid(_trailers[3]) or _trailers[3].is_queued_for_deletion()]


func _test_finish() -> void:
	var hp: Array = _seen.get("hp", [0.0, 1.0, 0.0])
	check("A PV sur la route : %s fois ceux de la remorque attelee" % DetachedTrailer.ROAD_HP_MULT,
		is_equal_approx(float(hp[0]), float(hp[1])) and is_equal_approx(float(hp[2]), float(hp[0])), str(hp))
	var t1: Array = _seen.get("t1", [0.0, 0, 0])
	check("B missile : -%d PV, traces, un palier de morceaux" % roundi(PowerCatalog.MISSILE_DAMAGE),
		is_equal_approx(float(t1[0]), PowerCatalog.MISSILE_DAMAGE) and int(t1[1]) > 0 and int(t1[2]) >= 1, str(t1))
	var t2: Array = _seen.get("t2", [0.0, 0])
	var laser := PowerCatalog.LASER_TICKS * PowerCatalog.LASER_DAMAGE_PER_TICK
	check("C laser : -%d PV, traces" % roundi(laser), absf(float(t2[0]) - laser) < 0.5 and int(t2[1]) > 0, str(t2))
	var b: Array = _seen.get("breach", [0, false, 0.0, 0.0])
	check("D trou : le camion la traverse et ressort devant", int(b[0]) >= 1 and bool(b[1]), str(b))
	check("D trou : la remorque perd %d %% de ses PV au plus, le camion des PV et des traces"
		% roundi(DetachedTrailer.MAX_HIT_SHARE * 100.0), float(b[2]) > 0.0
		and float(b[2]) <= DetachedTrailer.MAX_HIT_SHARE * 100.0 + 0.01 and float(b[3]) > 0.0 and int(b[6]) > 0, str(b))
	var t4: Array = _seen.get("t4", [false, false])
	check("E a bout : elle explose et disparait", bool(t4[0]) and bool(t4[1]), str(t4))
