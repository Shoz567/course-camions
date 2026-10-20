extends PhysicsTest

## Boomerang en course (2026-10-20 : « il ne va pas tres loin, il revient sans
## faire grand-chose ») : tireur et cible lances a 35 m/s (126 km/h) vers -Z,
## la cible 60 m devant et 4 m sur le cote. L'ancien boomerang (55 m/s dans
## l'absolu, demi-tour au bout de 50 ticks) ne prenait que ~17 m d'avance :
##   A. il vise la cible (target_ahead) et la touche a l'aller et au retour
##      (2 x BOOMERANG_DAMAGE, tete et remorque comprises) ;
##   B. il revient au tireur et disparait ;
##   C. un camion hors du cone, loin sur le cote, n'est pas touche.

const SPEED := 35.0

var _a: Truck
var _b: Truck
var _c: Truck
var _p: TruckPowers
var _full: float = 0.0
var _seen: Dictionary = {}
var _boomerangs: int = 0


func _test_setup() -> void:
	duration_ticks = 420
	add_floor(6000.0)
	_a = TruckTestUtil.spawn_truck(self, Vector3(0.0, 0.0, 0.0))
	_b = TruckTestUtil.spawn_truck(self, Vector3(4.0, 0.0, -60.0))
	_c = TruckTestUtil.spawn_truck(self, Vector3(60.0, 0.0, -30.0))
	for t in [_a, _b, _c]:
		(t as Truck).add_to_group(TruckPowers.TARGETS)
	_p = TruckPowers.setup(_a, PowerCatalog.Id.BOOMERANG, -1)
	_full = _total(_b)
	child_entered_tree.connect(func(n: Node) -> void:
		if n is PowerBoomerang:
			_boomerangs += 1)


func _total(t: Truck) -> float:
	var h := TruckHealth.of(t)
	return h.hp + h.trailer_hp


func _test_tick(t: int) -> void:
	# allure de course imposee (le test porte sur le boomerang, pas la conduite)
	if t >= 10:
		for k in [_a, _b]:
			var v := (k as Truck).linear_velocity
			(k as Truck).linear_velocity = Vector3(0.0, v.y, -SPEED)
	if t == 40:
		_seen["target"] = _p.target_ahead() == _b
		_seen["fired"] = _p.use(0)
	if t == 410:
		_seen["lost"] = _full - _total(_b)
		_seen["c"] = _total(_c)
		var alive := 0
		for n in get_children():
			if n is PowerBoomerang:
				alive += 1
		_seen["alive"] = alive


func _test_finish() -> void:
	check("A vise la cible, la touche a l'aller et au retour", _seen.get("target") == true and _seen.get("fired") == true
		and is_equal_approx(float(_seen.get("lost", 0.0)), 2.0 * PowerCatalog.BOOMERANG_DAMAGE), str(_seen))
	check("B revenu au tireur, disparu", _boomerangs == 1 and int(_seen.get("alive", 1)) == 0, str(_seen.get("alive")))
	check("C camion hors du cone intact", is_equal_approx(float(_seen.get("c", 0.0)), _full), str(_seen.get("c")))
