extends PhysicsTest

## Retour de coup et portee au viseur (2026-10-20 : « un marqueur de coup,
## petit son, chiffre de degats ; un bip quand la cible change ; le viseur
## pourrait indiquer la portee ») :
##   A. mitrailleuse sur B (30 m) : un son par balle (20), des chiffres de
##      degats (« -N ») sur l'ecran du tireur, la croix de touche ;
##   B. missile sur C sous bouclier : « BLOQUÉ » ;
##   C. bip a l'acquisition de la cible, et a chaque changement (cycle) ;
##   D. portee : cible a 105 m, mitrailleuse (90 m) a gauche et laser (120 m)
##      a droite : viseur pret, fleche gauche eteinte, droite allumee ; au-dela
##      de 120 m : gris (hors de portee) ; apres le tir : terne (recharge).

var _a: Truck
var _b: Truck
var _shooter_c: Truck
var _c: Truck
var _r: Truck
var _r_target: Truck
var _r_target2: Truck
var _pa: TruckPowers
var _pc: TruckPowers
var _pr: TruckPowers
var _hud_a: RaceHud
var _hud_c: RaceHud
var _hud_r: RaceHud
var _seen: Dictionary = {}


func _test_setup() -> void:
	duration_ticks = 260
	add_floor(4000.0)
	_a = _spawn(Vector3(0.0, 0.0, 0.0))
	_b = _spawn(Vector3(0.0, 0.0, -50.0))
	_shooter_c = _spawn(Vector3(400.0, 0.0, 0.0))
	_c = _spawn(Vector3(400.0, 0.0, -50.0))
	_r = _spawn(Vector3(800.0, 0.0, 0.0))
	_r_target = _spawn(Vector3(800.0, 0.0, -110.0))
	_r_target2 = _spawn(Vector3(806.0, 0.0, -150.0))
	_pa = TruckPowers.setup(_a, PowerCatalog.Id.GUN, -1)
	_pc = TruckPowers.setup(_shooter_c, PowerCatalog.Id.MISSILE, -1)
	_pr = TruckPowers.setup(_r, PowerCatalog.Id.GUN, PowerCatalog.Id.LASER)
	TruckHealth.of(_c).shield_ticks = 600
	_hud_a = _hud_for(_a, _pa)
	_hud_c = _hud_for(_shooter_c, _pc)
	_hud_r = _hud_for(_r, _pr)


func _spawn(at: Vector3) -> Truck:
	var t := TruckTestUtil.spawn_truck(self, at)
	t.add_to_group(TruckPowers.TARGETS)
	return t


func _hud_for(t: Truck, p: TruckPowers) -> RaceHud:
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = t.global_position + Vector3(0.0, 8.0, 22.0)
	cam.look_at(t.global_position + Vector3(0.0, 2.0, -40.0), Vector3.UP)
	var h := RaceHud.new()
	h.truck = t
	h.camera = cam
	add_child(h)
	h._watch_hits(p)
	return h


func _reticle(h: RaceHud) -> TargetReticle:
	return h.get("_reticle") as TargetReticle


func _test_tick(t: int) -> void:
	# la course n'est pas lancee (pas de RaceLaps) : on fait vivre le HUD
	for h in [_hud_a, _hud_c, _hud_r]:
		(h as RaceHud)._place_reticle(TruckPowers.of((h as RaceHud).truck))
		(h as RaceHud)._age_numbers(1.0 / 60.0)
	match t:
		10:
			_seen["beeps0"] = _hud_r.beeps
			var rr := _reticle(_hud_r)
			_seen["range"] = [rr.state, rr.slots[0], rr.slots[1], roundi(rr.distance_m)]
		20:
			_pa.use(0)
			_pc.use(0)
		40:
			_seen["flash"] = _reticle(_hud_a).flashing() or _hud_a.hit_sounds > 0
			_pr.use(0)
		45:
			_seen["recharge"] = [_reticle(_hud_a).state]
			_pr.cycle_target()
		47:
			_seen["beeps1"] = _hud_r.beeps
			_seen["far"] = _reticle(_hud_r).state
		70:
			var blocked := []
			for n in _hud_c.get_children():
				if n is Label and String((n as Label).text) == "BLOQUÉ":
					blocked.append(true)
			_seen["c"] = [_hud_c.hit_sounds, blocked.size()]
		200:
			var texts := []
			for n in _hud_a.get_children():
				if n is Label and String((n as Label).text).begins_with("-"):
					texts.append((n as Label).text)
			_seen["a"] = [_hud_a.hit_sounds, _hud_a.hit_numbers_shown, texts]


func _test_finish() -> void:
	var a: Array = _seen.get("a", [0, 0, []])
	check("A mitrailleuse : un son par balle, des chiffres « -N »", int(a[0]) == 20 and int(a[1]) >= 1, str(a))
	check("A croix de touche", bool(_seen.get("flash", false)))
	var c: Array = _seen.get("c", [0, 0])
	check("B bouclier : « BLOQUÉ »", int(c[0]) == 1 and int(c[1]) == 1, str(c))
	check("C bip a l'acquisition, puis au changement de cible", int(_seen.get("beeps0", 0)) >= 1
		and int(_seen.get("beeps1", 0)) > int(_seen.get("beeps0", 0)), "%s -> %s" % [_seen.get("beeps0"), _seen.get("beeps1")])
	var r: Array = _seen.get("range", [-1, -1, -1, 0])
	check("D 105 m : pret (laser), fleche gauche eteinte, droite allumee",
		int(r[0]) == TargetReticle.State.READY and int(r[1]) == 0 and int(r[2]) == 1, str(r))
	check("D au-dela de 120 m : gris, hors de portee", int(_seen.get("far", -1)) == TargetReticle.State.OUT_OF_RANGE,
		str(_seen.get("far")))
	check("D apres le tir : terne (recharge)", _seen.get("recharge") == [TargetReticle.State.RECHARGING],
		str(_seen.get("recharge")))
