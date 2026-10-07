extends PhysicsTest

## Pneus qui eclatent (2026-10-07 : « quand un pneu est touche, il eclate, on
## perd en adherence, en maniabilite »). Truck.burst_tire, TruckTires.
##
##   A. qui eclate (TruckTires.wheel_hit) : un choc de cote a hauteur de roue,
##      assez fort, eclate le pneu de ce cote et de cet essieu ; pas un choc
##      frontal, ni un frottement lent, ni le milieu du chassis, ni la cabine ;
##   B. un camion lance de cote (12 m/s) dans le flanc avant gauche d'un
##      camion arrete : son pneu avant gauche eclate, aucun autre ; le
##      camion qui percute (de face) garde les siens ;
##   C. un mur pris en biais a 80 km/h (25 deg) par l'avant gauche : ce pneu
##      eclate ; un camion pousse de cote a 5 m/s : rien n'eclate ;
##   D. effets, a cote d'un camion temoin identique : coin avant gauche
##      affaisse a l'arret ; en ligne droite sans braquer, le camion tire du
##      cote creve ; plein braquage du cote oppose : il tourne moins (pneu
##      exterieur creve) ;
##   E. un camion detruit reapparait avec quatre pneus neufs ;
##   F. visuel (modele charge) : le pneu de la roue arriere gauche s'ecrase,
##      ceux des autres roues non ;
##   G. remorque (2026-10-07 : « fais aussi eclater les pneus de la remorque ») :
##      qui eclate (TruckTires.trailer_hit) ; un camion lance de cote dans
##      l'arriere gauche d'une remorque : ses pneus gauches eclatent, pas ceux
##      du tracteur ; en ligne droite, l'ensemble tire du cote creve et perd de
##      la vitesse ; en virage, la remorque chasse plus loin ; les pneus creves
##      partent avec la remorque larguee, la suivante arrive neuve ; a
##      l'image, les pneus gauches de chaque essieu s'ecrasent, la remorque
##      penche a gauche.

var _hit: Truck
var _rammer: Truck
var _wall_truck: Truck
var _push_target: Truck
var _pusher: Truck
var _rest_ok: Truck
var _rest_flat: Truck
var _line_ok: Truck
var _line_flat: Truck
var _turn_ok: Truck
var _turn_flat: Truck
var _respawn: Truck
var _respawned: bool = false
var _model: Truck
var _t_hit: Truck
var _t_rammer: Truck
var _t_line: Truck
var _t_turn: Truck
## Balayage de la remorque a l'entree du virage (120 premiers ticks, meme
## acceleration laterale a 5 % pres) : plus grand |angle| (deg).
var _sweep: Dictionary = {}
var _yaw0: Dictionary = {}
var _yaw_turn: Dictionary = {}
var _straight: InputFrame = InputFrame.new()
var _turning: InputFrame = InputFrame.new()


func _test_setup() -> void:
	duration_ticks = 300
	add_floor(1600.0)
	# B : un camion arrete, un autre qui arrive de sa gauche, sur l'essieu avant
	_hit = _spawn(Vector3(0.0, 0.0, 0.0), 0.0, 0.0)
	_rammer = _spawn(Vector3(-12.0, 0.0, TruckSpec.ANCHORS[0].z), -90.0, 12.0)
	# C : mur longitudinal a gauche, camion en biais vers lui ; pousse lente
	_wall(Vector3(1.0, 4.0, 200.0), Vector3(92.0, 2.0, -60.0))
	_wall_truck = _spawn(Vector3(100.0, 0.0, 0.0), 25.0, 22.2)
	_push_target = _spawn(Vector3(200.0, 0.0, 0.0), 0.0, 0.0)
	_pusher = _spawn(Vector3(188.0, 0.0, TruckSpec.ANCHORS[0].z), -90.0, 5.0)
	# D : paires temoin / creve
	_rest_ok = _spawn(Vector3(300.0, 0.0, 0.0), 0.0, 0.0)
	_rest_flat = _spawn(Vector3(330.0, 0.0, 0.0), 0.0, 0.0)
	_line_ok = _spawn(Vector3(400.0, 0.0, 0.0), 0.0, 16.0)
	_line_flat = _spawn(Vector3(440.0, 0.0, 0.0), 0.0, 16.0)
	_turn_ok = _spawn(Vector3(600.0, 0.0, 0.0), 0.0, 14.0)
	_turn_flat = _spawn(Vector3(700.0, 0.0, 0.0), 0.0, 14.0)
	_straight.throttle = 0.6
	_turning.throttle = 0.5
	_turning.steer = 1.0
	for t: Truck in [_line_ok, _line_flat]:
		t.set_input(_straight)
	for t: Truck in [_turn_ok, _turn_flat]:
		t.set_input(_turning)
	for t: Truck in [_rest_flat, _line_flat, _turn_flat]:
		t.burst_tire(0)
	for t: Truck in [_line_ok, _line_flat, _turn_ok, _turn_flat]:
		_yaw0[t] = t.rotation.y
		_yaw_turn[t] = 0.0
	# E : creve, puis detruit au tick 2 ; reapparait wreck_ticks plus tard
	_respawn = _spawn(Vector3(-700.0, 0.0, 0.0), 0.0, 0.0)
	_respawn.burst_tire(1)
	_respawn.burst_tire(3)
	_respawn.burst_tire(Truck.TRAILER_LEFT)
	TruckHealth.of(_respawn).respawned.connect(func() -> void: _respawned = true)
	# F, G : modele charge (remorque Conteneur), pneu arriere gauche et pneus
	# gauches de la remorque creves
	TruckVisual.load_external_in_headless = true
	_model = _spawn(Vector3(-600.0, 0.0, 0.0), 0.0, 0.0)
	var box := load("res://vehicles/trailers/conteneur.tres") as TrailerType
	_model.set_trailer_type(box)
	(_model.get_node("Visual") as TruckVisual).set_trailer_type(box)
	TruckVisual.load_external_in_headless = false
	_model.burst_tire(2)
	_model.burst_tire(Truck.TRAILER_LEFT)
	# G : remorque arretee, un camion arrive de sa gauche sur le train de roues
	_t_hit = _spawn(Vector3(-400.0, 0.0, 0.0), 0.0, 0.0)
	var bogie_z := TruckSpec.TRAILER_CENTER.z + TruckSpec.TRAILER_SIZE.z / 2.0 - Truck.TRAILER_BOGIE_FROM_REAR_M
	_t_rammer = _spawn(Vector3(-412.0, 0.0, bogie_z), -90.0, 12.0)
	# G : ligne droite et virage, a cote des temoins de D
	_t_line = _spawn(Vector3(480.0, 0.0, 0.0), 0.0, 16.0)
	_t_line.set_input(_straight)
	_t_line.burst_tire(Truck.TRAILER_LEFT)
	_yaw0[_t_line] = _t_line.rotation.y
	_t_turn = _spawn(Vector3(-200.0, 0.0, 0.0), 0.0, 14.0)
	_t_turn.set_input(_turning)
	_t_turn.burst_tire(Truck.TRAILER_LEFT)
	for tr: Truck in [_turn_ok, _t_turn]:
		_sweep[tr] = 0.0


func _spawn(pos: Vector3, yaw_deg: float, speed: float) -> Truck:
	var t := TruckTestUtil.spawn_truck(self, pos, Vector3(0.0, yaw_deg, 0.0))
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
	if t == 2:
		TruckHealth.of(_respawn).damage(1000.0, &"test")
	for tr: Truck in [_turn_ok, _turn_flat]:
		_yaw_turn[tr] = float(_yaw_turn[tr]) + tr.angular_velocity.y / 60.0
	if t <= 120:
		for tr: Truck in [_turn_ok, _t_turn]:
			_sweep[tr] = maxf(float(_sweep[tr]), absf(tr.get_trailer_angle_deg()))


func _test_finish() -> void:
	var xf := Transform3D.IDENTITY
	var fl := TruckSpec.ANCHORS[0]
	var side_l := Vector3(fl.x - 0.3, 1.2, fl.z)
	check("A choc de cote fort a l'avant gauche : pneu avant gauche",
		TruckTires.wheel_hit(xf, side_l, Vector3.RIGHT, 10.0) == 0)
	check("A choc de cote fort a l'arriere droit : pneu arriere droit",
		TruckTires.wheel_hit(xf, Vector3(1.4, 1.0, TruckSpec.ANCHORS[3].z + 1.0), Vector3.LEFT, 10.0) == 3)
	check("A coin d'un camion a 1,4 m de l'essieu : encore le pneu",
		TruckTires.wheel_hit(xf, side_l + Vector3(0.0, 0.0, 1.45), Vector3.RIGHT, 10.0) == 0)
	check("A frottement lent : rien", TruckTires.wheel_hit(xf, side_l, Vector3.RIGHT, 4.0) == -1)
	check("A choc frontal : le pare-chocs, pas les roues",
		TruckTires.wheel_hit(xf, Vector3(-1.2, 1.0, -3.5), Vector3.BACK, 15.0) == -1)
	check("A milieu du chassis : rien", TruckTires.wheel_hit(xf, Vector3(-1.4, 1.2, 0.0), Vector3.RIGHT, 15.0) == -1)
	check("A cabine, en hauteur : rien", TruckTires.wheel_hit(xf, Vector3(-1.4, 3.2, fl.z), Vector3.RIGHT, 15.0) == -1)

	check("B camion pris de cote : pneu avant gauche eclate, et lui seul",
		_hit.is_tire_burst(0) and _hit.burst_tire_count() == 1, _bursts(_hit))
	check("B le camion qui percute de face garde ses pneus", _rammer.burst_tire_count() == 0, _bursts(_rammer))
	check("C mur pris en biais par l'avant gauche : ce pneu eclate", _wall_truck.is_tire_burst(0),
		_bursts(_wall_truck))
	check("C poussee lente de cote : rien n'eclate", _push_target.burst_tire_count() == 0, _bursts(_push_target))

	var drop := (_rest_ok.global_transform * fl).y - (_rest_flat.global_transform * fl).y
	check_near("D coin avant gauche affaisse (m)", drop, _rest_flat.tuning.tire_burst_drop_m, 0.08)
	# en ligne droite : cap tourne vers la gauche (lacet > 0), le temoin tout droit
	var pull := rad_to_deg(angle_difference(float(_yaw0[_line_flat]), _line_flat.rotation.y))
	var straight := rad_to_deg(angle_difference(float(_yaw0[_line_ok]), _line_ok.rotation.y))
	check_above("D ligne droite sans braquer : tire du cote creve (deg)", pull - absf(straight), 3.0)
	var turn_ok := absf(float(_yaw_turn[_turn_ok]))
	var turn_flat := absf(float(_yaw_turn[_turn_flat]))
	check("D plein braquage, pneu exterieur creve : tourne moins", turn_flat < turn_ok * 0.93,
		"%.1f deg contre %.1f" % [rad_to_deg(turn_flat), rad_to_deg(turn_ok)])
	check("D vitesse : la jante freine", _line_flat.get_speed_kmh() < _line_ok.get_speed_kmh(),
		"%.1f / %.1f km/h" % [_line_flat.get_speed_kmh(), _line_ok.get_speed_kmh()])

	check("E reapparu avec quatre pneus neufs", _respawned and _respawn.burst_tire_count() == 0,
		_bursts(_respawn))

	_check_trailer()

	var v := _model.get_node("Visual") as TruckVisual
	if not v.model_loaded:
		check("F visuel (modele absent : saute)", true)
		return
	# tracteur : pneus ecrases, par position (z < 5 m : pas la remorque)
	var inv := _model.global_transform.affine_inverse()
	var flat := 0
	var other := 0
	for n in v.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var b: Variant = mi.get_instance_shader_parameter(&"tyre_burst")
		if b == null or float(b) <= 0.0:
			continue
		var local := inv * mi.global_transform * mi.get_aabb().get_center()
		if local.z > 5.0:
			continue
		if local.x < 0.0 and local.z > 0.0:
			flat += 1
		else:
			other += 1
	check("F pneu arriere gauche ecrase (tyre_burst), les autres non", flat >= 1 and other == 0,
		"%d / %d" % [flat, other])
	# remorque : chaque essieu ecrase, du cote gauche seulement (tyre_side,
	# ramene au repere du camion)
	var left_only := 0
	for a in v._axles:
		var meshes: Array[Node] = a.find_children("*", "MeshInstance3D", true, false)
		if a is MeshInstance3D:
			meshes.append(a)
		for n in meshes:
			var mi := n as MeshInstance3D
			var b: Variant = mi.get_instance_shader_parameter(&"tyre_burst")
			var s: Variant = mi.get_instance_shader_parameter(&"tyre_side")
			var ax: Variant = mi.get_instance_shader_parameter(&"relief_axis")
			if b == null or float(b) <= 0.0 or s == null or not (ax is Vector4):
				continue
			var ax3 := Vector3((ax as Vector4).x, (ax as Vector4).y, (ax as Vector4).z)
			if float(s) * signf((inv.basis * mi.global_basis * ax3).x) < 0.0:
				left_only += 1
	check("G remorque : chaque essieu s'ecrase du cote gauche seulement",
		left_only >= v._axles.size() and v._axles.size() > 0, "%d / %d essieux" % [left_only, v._axles.size()])
	var roll := (v._trailer_pivot as Node3D).basis.get_euler().z
	check_above("G la remorque penche a gauche (deg)", rad_to_deg(roll), 1.0)


func _check_trailer() -> void:
	var box_xf := Transform3D(Basis.IDENTITY, TruckSpec.TRAILER_CENTER)
	var size := TruckSpec.TRAILER_SIZE
	var bz := TruckSpec.TRAILER_CENTER.z + size.z / 2.0 - Truck.TRAILER_BOGIE_FROM_REAR_M
	check("G choc de cote fort sur le train de roues a gauche : pneus gauches",
		TruckTires.trailer_hit(box_xf, size, Vector3(-1.5, 3.0, bz), Vector3.RIGHT, 10.0) == Truck.TRAILER_LEFT)
	check("G a droite, au bout de l'essieu arriere : pneus droits",
		TruckTires.trailer_hit(box_xf, size, Vector3(1.5, 2.5, bz + 2.0), Vector3.LEFT, 10.0) == Truck.TRAILER_RIGHT)
	check("G avant de la remorque : rien",
		TruckTires.trailer_hit(box_xf, size, Vector3(-1.5, 3.0, 3.0), Vector3.RIGHT, 15.0) == -1)
	check("G choc par l'arriere : rien",
		TruckTires.trailer_hit(box_xf, size, Vector3(-1.0, 3.0, 16.0), Vector3.FORWARD, 15.0) == -1)
	check("G frottement lent : rien",
		TruckTires.trailer_hit(box_xf, size, Vector3(-1.5, 3.0, bz), Vector3.RIGHT, 4.0) == -1)

	check("G remorque prise de cote : ses pneus gauches eclatent, pas le tracteur",
		_t_hit.is_tire_burst(Truck.TRAILER_LEFT) and _t_hit.burst_tire_count() == 1, _bursts(_t_hit))
	check("G le camion qui percute garde ses pneus", _t_rammer.burst_tire_count() == 0, _bursts(_t_rammer))

	var pull := rad_to_deg(angle_difference(float(_yaw0[_t_line]), _t_line.rotation.y))
	var straight := rad_to_deg(angle_difference(float(_yaw0[_line_ok]), _line_ok.rotation.y))
	check_above("G ligne droite, remorque creve a gauche : tire a gauche (deg)", pull - absf(straight), 1.0)
	check("G vitesse : la jante de la remorque freine", _t_line.get_speed_kmh() < _line_ok.get_speed_kmh() - 3.0,
		"%.1f / %.1f km/h" % [_t_line.get_speed_kmh(), _line_ok.get_speed_kmh()])
	check("G entree de virage : la remorque creve chasse plus loin", float(_sweep[_t_turn]) > float(_sweep[_turn_ok]) * 1.3,
		"%.1f deg contre %.1f" % [float(_sweep[_t_turn]), float(_sweep[_turn_ok])])

	# larguee : ses pneus creves partent avec elle, la suivante arrive neuve
	_rest_ok.burst_tire(Truck.TRAILER_RIGHT)
	_rest_ok.detach_trailer()
	var gone := not _rest_ok.is_tire_burst(Truck.TRAILER_RIGHT)
	var refused := not _rest_ok.burst_tire(Truck.TRAILER_LEFT)
	_rest_ok.reattach_trailer(true)
	check("G remorque larguee : ses pneus creves partent avec elle", gone and refused
		and _rest_ok.burst_tire_count() == 0, _bursts(_rest_ok))


func _bursts(t: Truck) -> String:
	var s := ""
	for i in 6:
		s += "1" if t.is_tire_burst(i) else "0"
	return s
