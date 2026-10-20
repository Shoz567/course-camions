extends PhysicsTest

## Pouvoirs, deuxieme serie (2026-10-19 : « plus de pouvoirs », les armes de
## l'equipe encore libres) :
##   A. catalogue : 6 pouvoirs, la scie a une arme gauche et une droite ;
##   B. MITRAILLEUSE : 20 balles en 2 s sur le camion devant, 24 PV (sur sa
##      remorque, prise par derriere) ;
##   C. SCIE : un camion contre le flanc perd des PV, ses pneus de ce cote
##      eclatent (lames a plat, 2026-10-20), il est ecarte ; un
##      camion loin derriere n'est pas touche ;
##   D. BOOMERANG : touche le camion devant a l'aller et au retour (30 PV),
##      puis revient au tireur et disparait ;
##   E. en miroir (client en ligne) : le boomerang touche sans retirer de PV ;
##   F. chaque coup marque la tole (traces) de la partie touchee (2026-10-20).

var _gun: Truck
## PV neufs, tete et remorque.
var _full: float = 0.0
var _gun_target: Truck
var _saw: Truck
var _saw_side: Truck
var _saw_far: Truck
var _boom: Truck
var _boom_target: Truck
var _mirror: Truck
var _mirror_target: Truck
var _pg: TruckPowers
var _ps: TruckPowers
var _pb: TruckPowers
var _pm: TruckPowers
var _boomerangs: int = 0
var _mirror_strikes: int = 0
var _side_x0: float = 0.0
var _seen: Dictionary = {}


func _test_setup() -> void:
	duration_ticks = 300
	add_floor(4000.0)
	_gun = _spawn(Vector3(0.0, 0.0, 0.0))
	_gun_target = _spawn(Vector3(0.0, 0.0, -30.0))
	_saw = _spawn(Vector3(300.0, 0.0, 0.0))
	_saw_side = _spawn(Vector3(304.2, 0.0, 0.0))
	_saw_far = _spawn(Vector3(300.0, 0.0, 40.0))
	_boom = _spawn(Vector3(600.0, 0.0, 0.0))
	_boom_target = _spawn(Vector3(600.0, 0.0, -25.0))
	_mirror = _spawn(Vector3(900.0, 0.0, 0.0))
	_mirror_target = _spawn(Vector3(900.0, 0.0, -25.0))
	_pg = TruckPowers.setup(_gun, PowerCatalog.Id.GUN, -1)
	_ps = TruckPowers.setup(_saw, PowerCatalog.Id.SAW, -1)
	_pb = TruckPowers.setup(_boom, PowerCatalog.Id.BOOMERANG, -1)
	_pm = TruckPowers.setup(_mirror, PowerCatalog.Id.BOOMERANG, -1, true)
	_side_x0 = _saw_side.global_position.x
	_full = _total(_gun_target)
	child_entered_tree.connect(func(n: Node) -> void:
		if n is PowerBoomerang:
			_boomerangs += 1
			var b := n as PowerBoomerang
			if b.mirror:
				b.struck.connect(func(_v: Truck) -> void: _mirror_strikes += 1))


func _spawn(at: Vector3) -> Truck:
	var t := TruckTestUtil.spawn_truck(self, at)
	t.add_to_group(TruckPowers.TARGETS)
	return t


func _test_tick(t: int) -> void:
	if t == 20:
		_seen["gun"] = _pg.use(0)
		_seen["saw"] = _ps.use(0)
		_seen["boom"] = _pb.use(0)
		_pm.net_fire(0, null)
	if t == 22:
		_seen["active"] = [_pg.active(0), _ps.active(0)]
	if t == 150:
		_seen["gun_hits"] = _pg.gun_hits
		_seen["hp_gun"] = _total(_gun_target)
		_seen["gun_trailer"] = TruckHealth.of(_gun_target).trailer_hp
	if t == 290:
		_seen["hp_side"] = _total(_saw_side)
		_seen["hp_far"] = TruckHealth.of(_saw_far).hp
		_seen["side_moved"] = _saw_side.global_position.x - _side_x0
		_seen["marks"] = [_marks(_gun_target, true), _marks(_saw_side, false), _marks(_boom_target, false)
			+ _marks(_boom_target, true), _marks(_saw_far, false) + _marks(_saw_far, true)]
		_seen["tires"] = [_saw_side.is_tire_burst(0), _saw_side.is_tire_burst(2),
			_saw_side.is_tire_burst(1), _saw_side.is_tire_burst(3)]
		_seen["hp_boom"] = _total(_boom_target)
		_seen["boom_parts"] = [TruckHealth.of(_boom_target).hp, TruckHealth.of(_boom_target).trailer_hp]
		_seen["hp_mirror"] = TruckHealth.of(_mirror_target).hp
		_seen["left"] = get_tree().get_nodes_in_group(&"__none").size()
		var alive := 0
		for n in get_children():
			if n is PowerBoomerang:
				alive += 1
		_seen["alive"] = alive


## PV de la tete et de la remorque (pris par derriere, un tir touche la remorque).
func _total(t: Truck) -> float:
	var h := TruckHealth.of(t)
	return h.hp + h.trailer_hp


func _marks(t: Truck, on_trailer: bool) -> int:
	return (t.get_node(^"DamageFx") as TruckDamageFx).marks(on_trailer).size()


func _test_finish() -> void:
	check("catalogue : 6 pouvoirs, scie gauche et droite", PowerCatalog.count() == 6
		and PowerCatalog.display_name(PowerCatalog.Id.GUN) == "MITRAILLEUSE"
		and PowerCatalog.model(PowerCatalog.Id.SAW, 0).ends_with("scie_geante_g.glb")
		and PowerCatalog.model(PowerCatalog.Id.SAW, 1).ends_with("scie_geante_d.glb"))
	check("trois tirs acceptes, rafale et scies actives", _seen.get("gun") == true and _seen.get("saw") == true
		and _seen.get("boom") == true and _seen.get("active") == [true, true], str(_seen))
	check("mitrailleuse : 20 balles, 24 PV (sur la remorque)", int(_seen.get("gun_hits", 0)) == 20
		and absf(float(_seen.get("hp_gun", 0.0)) - (_full - 20 * PowerCatalog.GUN_DAMAGE)) < 0.01
		and float(_seen.get("gun_trailer", 0.0)) < TruckHealth.DEFAULT_TRAILER_HP,
		"%s balles, %s PV" % [_seen.get("gun_hits"), _seen.get("hp_gun")])
	check("scie : le camion contre le flanc perd des PV et est ecarte", float(_seen.get("hp_side", 150.0)) < _full - 5.0
		and float(_seen.get("side_moved", 0.0)) > 0.5, "%s PV, %.2f m" % [_seen.get("hp_side"), float(_seen.get("side_moved", 0.0))])
	check("scie : pneus du flanc tranches, pas ceux de l'autre cote", _seen.get("tires") == [true, true, false, false],
		str(_seen.get("tires")))
	var m: Array = _seen.get("marks", [0, 0, 0, 1])
	check("degats visuels : remorque mitraillee, flanc scie, boomerang ; rien loin",
		int(m[0]) > 0 and int(m[1]) > 0 and int(m[2]) > 0 and int(m[3]) == 0, str(m))
	check("scie : un camion loin derriere intact", is_equal_approx(float(_seen.get("hp_far", 0.0)), 100.0))
	check("boomerang : touche a l'aller et au retour (30 PV, a la remorque)",
		is_equal_approx(float((_seen.get("boom_parts", [0.0, 0.0]) as Array)[1]), TruckHealth.DEFAULT_TRAILER_HP
			- 2.0 * PowerCatalog.BOOMERANG_DAMAGE), str(_seen.get("boom_parts")))
	check("boomerang : revenu au tireur, disparu", _boomerangs == 2 and int(_seen.get("alive", 1)) == 0,
		"%d lances, %s en vol" % [_boomerangs, _seen.get("alive")])
	check("miroir : le boomerang touche sans retirer de PV", _mirror_strikes >= 1
		and is_equal_approx(float(_seen.get("hp_mirror", 0.0)), 100.0), "%d coups, %s PV" % [_mirror_strikes, _seen.get("hp_mirror")])
