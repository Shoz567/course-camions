extends PhysicsTest

## Pouvoirs et remorque (2026-10-20 : « quand on a une remorque, le pouvoir
## vise en priorite la remorque, pour penaliser les joueurs qui n'en ont pas ;
## ca diminue fortement les degats faits aux camions qui tractent ») :
##   A. missile tire par derriere sur B, qui tracte : sa remorque prend les
##      MISSILE_DAMAGE PV, sa tete rien ;
##   B. missile sur C, sans remorque : sa tete prend les MISSILE_DAMAGE PV ;
##   C. laser de face sur D, qui tracte : le rayon touche sa tete, qui n'en
##      prend que TOWING_CAB_SHARE ; la remorque encaisse le reste ;
##   D. le point vise d'un camion qui tracte est sa remorque, sinon sa tete.

var _a: Truck
var _b: Truck
var _c_shooter: Truck
var _c: Truck
var _d_shooter: Truck
var _d: Truck
var _pa: TruckPowers
var _pc: TruckPowers
var _pd: TruckPowers
var _seen: Dictionary = {}


func _test_setup() -> void:
	duration_ticks = 220
	add_floor(3000.0)
	_a = _spawn(Vector3(0.0, 0.0, 0.0))
	_b = _spawn(Vector3(0.0, 0.0, -45.0))
	_c_shooter = _spawn(Vector3(400.0, 0.0, 0.0))
	_c = _spawn(Vector3(400.0, 0.0, -45.0))
	_d_shooter = _spawn(Vector3(800.0, 0.0, -40.0), Vector3(0.0, 180.0, 0.0))
	_d = _spawn(Vector3(800.0, 0.0, 0.0))
	_pa = TruckPowers.setup(_a, PowerCatalog.Id.MISSILE, -1)
	_pc = TruckPowers.setup(_c_shooter, PowerCatalog.Id.MISSILE, -1)
	_pd = TruckPowers.setup(_d_shooter, PowerCatalog.Id.LASER, -1)
	# remorque solide pour D : le laser (36 PV) ne la fait pas sauter
	TruckHealth.of(_d).trailer_max_hp = 200.0
	TruckHealth.of(_d).trailer_hp = 200.0


func _spawn(at: Vector3, rot: Vector3 = Vector3.ZERO) -> Truck:
	var t := TruckTestUtil.spawn_truck(self, at, rot)
	t.add_to_group(TruckPowers.TARGETS)
	return t


func _test_tick(t: int) -> void:
	match t:
		5:
			# sans remorque pour de bon : pas de nouvelle remorque (TruckCargo)
			_c.get_node(^"Cargo").set_physics_process(false)
			_c.detach_trailer()
		20:
			_seen["aim"] = [TruckPowers.aim_point(_b).distance_to(TruckHealth.of(_b).trailer_center()) < 0.01,
				TruckPowers.aim_point(_c).distance_to(_c.global_position + Vector3.UP * 1.5) < 0.01]
			_pa.use(0)
			_pc.use(0)
			_pd.use(0)
		200:
			var hb := TruckHealth.of(_b)
			var hc := TruckHealth.of(_c)
			var hd := TruckHealth.of(_d)
			_seen["b"] = [hb.hp, hb.trailer_max_hp - hb.trailer_hp]
			_seen["c"] = hc.hp
			_seen["d"] = [100.0 - hd.hp, hd.trailer_max_hp - hd.trailer_hp]


func _test_finish() -> void:
	check("D point vise : remorque s'il tracte, sinon la tete", _seen.get("aim") == [true, true], str(_seen.get("aim")))
	var b: Array = _seen.get("b", [0.0, 0.0])
	check("A camion qui tracte : la remorque prend le missile, pas la tete",
		is_equal_approx(float(b[0]), 100.0) and is_equal_approx(float(b[1]), PowerCatalog.MISSILE_DAMAGE), str(b))
	check("B sans remorque : la tete prend le missile",
		is_equal_approx(float(_seen.get("c", 0.0)), 100.0 - PowerCatalog.MISSILE_DAMAGE), str(_seen.get("c")))
	var d: Array = _seen.get("d", [0.0, 0.0])
	var full := PowerCatalog.LASER_TICKS * PowerCatalog.LASER_DAMAGE_PER_TICK
	check("C tete touchee en tractant : %d %% des PV, la remorque le reste" % roundi(PowerCatalog.TOWING_CAB_SHARE * 100.0),
		absf(float(d[0]) - full * PowerCatalog.TOWING_CAB_SHARE) < 0.5 and absf(float(d[1]) - full) < 0.5, str(d))
