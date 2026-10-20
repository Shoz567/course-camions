extends PhysicsTest

## Visee automatique (2026-10-20 : « que tout ce qui est missile, mitraillette
## et tout, ca vise la personne la plus proche devant soi, qu'il n'y ait pas a
## viser ») : tireurs face a -Z, cible 40 m devant et 12 m sur le cote (17 deg,
## dans le cone du missile ; un tir droit devant la manque) :
##   A. la mitrailleuse touche la cible a chaque balle ;
##   B. le laser la touche et lui retire des PV ;
##   C. sans camion devant, le laser part droit devant et ne touche rien ;
##   D. deux cibles devant : la plus proche est visee.

var _gun: Truck
var _gun_target: Truck
var _laser: Truck
var _laser_target: Truck
var _alone: Truck
var _near: Truck
var _far: Truck
var _two: Truck
var _pg: TruckPowers
var _pl: TruckPowers
var _pa: TruckPowers
var _pt: TruckPowers
var _full: float = 0.0
var _seen: Dictionary = {}


func _test_setup() -> void:
	duration_ticks = 200
	add_floor(4000.0)
	_gun = _spawn(Vector3(0.0, 0.0, 0.0))
	_gun_target = _spawn(Vector3(12.0, 0.0, -40.0))
	_laser = _spawn(Vector3(400.0, 0.0, 0.0))
	_laser_target = _spawn(Vector3(388.0, 0.0, -40.0))
	_alone = _spawn(Vector3(800.0, 0.0, 0.0))
	_two = _spawn(Vector3(1200.0, 0.0, 0.0))
	_near = _spawn(Vector3(1210.0, 0.0, -45.0))
	_far = _spawn(Vector3(1200.0, 0.0, -90.0))
	_pg = TruckPowers.setup(_gun, PowerCatalog.Id.GUN, -1)
	_pl = TruckPowers.setup(_laser, PowerCatalog.Id.LASER, -1)
	_pa = TruckPowers.setup(_alone, PowerCatalog.Id.LASER, -1)
	_pt = TruckPowers.setup(_two, PowerCatalog.Id.GUN, -1)
	_full = _total(_laser_target)


func _spawn(at: Vector3) -> Truck:
	var t := TruckTestUtil.spawn_truck(self, at)
	t.add_to_group(TruckPowers.TARGETS)
	return t


func _total(t: Truck) -> float:
	var h := TruckHealth.of(t)
	return h.hp + h.trailer_hp


func _test_tick(t: int) -> void:
	if t == 20:
		_pg.use(0)
		_pl.use(0)
		_pa.use(0)
		_pt.use(0)
	if t == 60:
		_seen["alone_hit"] = _pa.laser_hit
	if t == 180:
		_seen["gun_hits"] = _pg.gun_hits
		_seen["gun_on"] = _pg.gun_hit == _gun_target
		_seen["laser"] = [_pl.laser_hit == _laser_target or _full - _total(_laser_target) > 30.0,
			_full - _total(_laser_target)]
		_seen["two"] = [_pt.gun_hit == _near, _total(_far)]


func _test_finish() -> void:
	check("A mitrailleuse : chaque balle sur la cible decalee", int(_seen.get("gun_hits", 0)) == 20
		and _seen.get("gun_on") == true, str(_seen))
	var l: Array = _seen.get("laser", [false, 0.0])
	check("B laser : touche la cible decalee (-36 PV)", bool(l[0]) and absf(float(l[1]) - 36.0) < 0.5, str(l))
	check("C sans camion devant : le laser ne touche rien", _seen.get("alone_hit") == null)
	var w: Array = _seen.get("two", [false, 0.0])
	check("D la plus proche est visee, pas l'autre", bool(w[0]) and is_equal_approx(float(w[1]), _full), str(w))
