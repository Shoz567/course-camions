extends PhysicsTest

## Degats separes tete / remorque, obstacles qui blessent, carcasse qui reste
## (2026-10-06 : « bien distinguer les degats faits a la tete du camion et a
## la remorque. Les degats faits a la remorque n'impactent pas la tete. Si
## trop de degats sont faits a la remorque, elle explose et la, ca inflige des
## degats a la tete » ; « quand le camion explose, il reste au milieu du
## chemin » ; « les remorques au milieu nous mettent des degats quand on rentre
## dedans et prennent des degats »).
##
##   A. marche arriere a 12 m/s dans un mur, la remorque touche : elle perd des
##      PV, la tete aucun ;
##   B. meme choc, remorque a 3 PV : elle explose et se detache, la tete perd
##      TRAILER_EXPLOSION_DAMAGE, et rien d'autre ;
##   C. de face a 25 m/s dans une remorque larguee (d'un autre) : la tete perd
##      hazard_damage_for(vitesse d'approche), la remorque attelee rien, la
##      remorque larguee perd des PV ;
##   D. tete a 0 PV : une carcasse (TruckWreck) et la remorque attelee
##      (DetachedTrailer, avec ses PV restants) restent sur la route ; le
##      camion, cache et sans collision, reapparait 3 s plus tard A COTE de la
##      carcasse (la place fournie est prise), qui est toujours la ;
##   E. un camion qui percute cette carcasse prend des degats, elle aussi.
##   F. deux camions de face, 15 m/s chacun (2026-10-07 : « les chocs entre
##      camions enlevent egalement des PV ») : les deux tetes perdent
##      hazard_damage_for(approche), source « camion » ;
##   G. un camion percute SA PROPRE remorque larguee (« autant qu'aux
##      autres ») : sa tete perd des PV, comme en C.
## Vitesses posees au tick 0 (CLAUDE.md §10 b).

const KILL_AT := 5

var _a: Truck
var _b: Truck
var _c: Truck
var _d: Truck
var _e: Truck
var _obstacle: DetachedTrailer
var _obstacle_hp0: float = 0.0
var _b_trailer_events: int = 0
var _b_destroyed_at: Vector3 = Vector3.INF
var _c_head: Array = []
var _d_wreck: TruckWreck
var _d_trailer: DetachedTrailer
var _d_trailer_hp: float = -1.0
var _d_hidden: bool = false
var _d_layer: int = -1
var _d_spot: Transform3D
var _d_after: Array = []
var _e_launched: bool = false
var _e_hit: float = 0.0
var _wreck_hp0: float = 0.0
var _f1: Truck
var _f2: Truck
var _f_hits: Array = [[], []]
var _g: Truck
var _g_own: DetachedTrailer
var _g_head: Array = []


func _test_setup() -> void:
	duration_ticks = 400
	add_floor(1600.0)
	# A et B : reculent vers un mur, remorque en premier
	_a = _spawn(Vector3(0.0, 0.0, 0.0), 0.0, -12.0)
	_wall(Vector3(30.0, 6.0, 2.0), Vector3(0.0, 3.0, 32.0))
	_b = _spawn(Vector3(100.0, 0.0, 0.0), 0.0, -12.0)
	_wall(Vector3(30.0, 6.0, 2.0), Vector3(100.0, 3.0, 32.0))
	var bh := TruckHealth.of(_b)
	bh.trailer_hp = 3.0
	bh.trailer_damaged.connect(func(_a: float, _s: StringName) -> void: _b_trailer_events += 1)
	bh.trailer_destroyed.connect(func(at: Vector3) -> void: _b_destroyed_at = at)
	# C : fonce sur une remorque larguee, 40 m devant
	_c = _spawn(Vector3(200.0, 0.0, 0.0), 0.0, 25.0)
	_obstacle = DetachedTrailer.new()
	_obstacle.transform = Transform3D(Basis.IDENTITY, Vector3(200.0, TruckSpec.KINGPIN.y, -60.0))
	add_child(_obstacle)
	TruckHealth.of(_c).damaged.connect(func(amount: float, source: StringName) -> void: _c_head.append([amount, source]))
	# D : detruit ; la place fournie pour reapparaitre est celle de sa carcasse
	_d = _spawn(Vector3(300.0, 0.0, 0.0), 0.0, 0.0)
	_d_spot = Transform3D(Basis.IDENTITY, Vector3(300.0, 1.0, 0.0))
	TruckHealth.of(_d).respawn_provider = func(_t: Truck) -> Transform3D: return _d_spot
	TruckHealth.of(_d).trailer_hp = 31.0
	# E : lance plus tard sur la carcasse de D, depuis 40 m devant elle
	_e = _spawn(Vector3(300.0, 0.0, 200.0), 0.0, 0.0)
	# F : face a face, 70 m entre les centres
	_f1 = _spawn(Vector3(400.0, 0.0, 0.0), 0.0, 15.0)
	_f2 = _spawn(Vector3(400.0, 0.0, -70.0), 180.0, 15.0)
	for k in 2:
		var list: Array = _f_hits[k]
		TruckHealth.of(_f1 if k == 0 else _f2).damaged.connect(func(amount: float, source: StringName) -> void:
			list.append([amount, source]))
	# G : sa propre remorque larguee, 40 m devant ; il la percute une fois
	# devenue solide pour lui (owner_pass_ticks)
	_g = _spawn(Vector3(500.0, 0.0, 0.0), 0.0, 0.0)
	_g_own = DetachedTrailer.new()
	_g_own.dropped_by = _g
	_g_own.transform = Transform3D(Basis.IDENTITY, Vector3(500.0, TruckSpec.KINGPIN.y, -60.0))
	add_child(_g_own)
	TruckHealth.of(_g).damaged.connect(func(amount: float, source: StringName) -> void: _g_head.append([amount, source]))


func _spawn(pos: Vector3, yaw_deg: float, speed: float) -> Truck:
	var t := TruckTestUtil.spawn_truck(self, pos, Vector3(0.0, -yaw_deg, 0.0))
	t.linear_velocity = -t.global_basis.z * speed
	return t


func _wall(size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	body.position = pos
	add_child(body)


func _test_tick(t: int) -> void:
	var dh := TruckHealth.of(_d)
	if t == _g_own.owner_pass_ticks + 5:
		_g.linear_velocity = -_g.global_basis.z * 25.0
	if t == 1:
		_obstacle_hp0 = _obstacle.hp
	if t == KILL_AT:
		dh.damage(150.0, &"test")
	if t == KILL_AT + 2:
		_d_wreck = dh.last_wreck
		for n in find_children("*", "DetachedTrailer", false, false):
			if n != _obstacle and not (n is TruckWreck):
				_d_trailer = n as DetachedTrailer
		if _d_trailer != null:
			_d_trailer_hp = _d_trailer.hp
		_d_hidden = not (_d.get_node("Visual") as Node3D).visible
		_d_layer = _d.collision_layer
	if t == KILL_AT + 200:
		var w := _d_wreck.global_position if is_instance_valid(_d_wreck) else Vector3.INF
		_d_after = [dh.hp, _d.is_wrecked(), is_instance_valid(_d_wreck), _d.global_position.distance_to(w),
			(_d.get_node("Visual") as Node3D).visible, _d.collision_layer != 0, _d.is_trailer_detached()]
		# E : 40 m devant la carcasse (sa remorque est derriere), lance dessus
		# a 20 m/s
		if is_instance_valid(_d_wreck):
			_wreck_hp0 = _d_wreck.hp
			var at := _d_wreck.global_position - Vector3(0.0, 0.0, 40.0)
			_e.reset_to(Transform3D(Basis(Vector3.UP, PI), Vector3(at.x, 1.0, at.z)))
	if t == KILL_AT + 203:
		_e.linear_velocity = Vector3(0.0, 0.0, 20.0)
		_e_launched = true
		TruckHealth.of(_e).damaged.connect(func(amount: float, _s: StringName) -> void: _e_hit += amount)


func _test_finish() -> void:
	var ah := TruckHealth.of(_a)
	print("  INFO   A : tete %.0f PV, remorque %.0f / %.0f PV" % [ah.hp, ah.trailer_hp, ah.trailer_max_hp])
	check("A la remorque touche le mur : elle perd des PV", ah.trailer_hp < ah.trailer_max_hp,
		"%.0f / %.0f" % [ah.trailer_hp, ah.trailer_max_hp])
	check("A la tete ne perd rien", ah.hp == ah.max_hp, "%.0f PV" % ah.hp)

	var bh := TruckHealth.of(_b)
	check("B remorque a 0 PV : explosion, remorque detachee", _b_destroyed_at != Vector3.INF and _b.is_trailer_detached())
	check("B la tete perd les degats de l'explosion, rien d'autre",
		bh.hp == bh.max_hp - TruckHealth.TRAILER_EXPLOSION_DAMAGE, "%.0f PV" % bh.hp)

	var ch := TruckHealth.of(_c)
	print("  INFO   C : tete %s ; remorque larguee %.0f -> %.0f PV" % [_c_head, _obstacle_hp0,
		_obstacle.hp if is_instance_valid(_obstacle) else 0.0])
	check("C l'obstacle percute blesse la tete", not _c_head.is_empty() and _c_head[0][1] == &"obstacle"
		and float(_c_head[0][0]) >= 10.0, str(_c_head))
	check("C la remorque attelee n'a rien", ch.trailer_hp == ch.trailer_max_hp)
	check("C l'obstacle perd des PV", not is_instance_valid(_obstacle) or _obstacle.hp < _obstacle_hp0)

	check("D carcasse laissee sur la route", _d_wreck != null)
	check("D remorque laissee avec ses PV restants (31, x%s sur la route)" % DetachedTrailer.ROAD_HP_MULT,
		_d_trailer != null and _d_trailer_hp == 31.0 * DetachedTrailer.ROAD_HP_MULT,
		"%.0f" % _d_trailer_hp)
	check("D camion cache et sans collision pendant l'attente", _d_hidden and _d_layer == 0)
	print("  INFO   D apres : %s" % [_d_after])
	check("D reapparait neuf, visible, avec collisions et une remorque, la carcasse toujours la",
		_d_after.size() == 7 and _d_after[0] == 100.0 and not _d_after[1] and _d_after[2]
		and _d_after[4] and _d_after[5] and not _d_after[6], str(_d_after))
	check_above("D reapparait a cote de la carcasse, pas dedans (m)", float(_d_after[3]) if _d_after.size() == 7 else 0.0, 5.0)

	print("  INFO   E : %.0f PV perdus, carcasse %.0f -> %.0f PV" % [_e_hit, _wreck_hp0,
		_d_wreck.hp if is_instance_valid(_d_wreck) else 0.0])
	check("E la carcasse blesse le camion qui la percute", _e_launched and _e_hit >= 5.0, "%.0f" % _e_hit)
	check("E la carcasse s'abime", not is_instance_valid(_d_wreck) or _d_wreck.hp < _wreck_hp0)

	var f_ok := true
	for k in 2:
		var h: Array = _f_hits[k]
		f_ok = f_ok and not h.is_empty() and h[0][1] == &"camion" and float(h[0][0]) >= 10.0
	print("  INFO   F : %s / %s ; G : %s" % [_f_hits[0], _f_hits[1], _g_head])
	check("F choc de face entre camions : les deux tetes perdent des PV", f_ok, str(_f_hits))
	check("G sa propre remorque larguee le blesse aussi", is_instance_valid(_g_own) and _g_own.is_solid_for_owner() and not _g_head.is_empty()
		and _g_head[0][1] == &"obstacle" and float(_g_head[0][0]) >= 10.0, str(_g_head))
