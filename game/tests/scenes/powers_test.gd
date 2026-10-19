extends PhysicsTest

## Pouvoirs, premiere serie (tache 4.5.8) :
##   A. catalogue : BOUCLIER, MISSILE, LASER, recharges ; InputFrame transporte
##      les deux fronts (6 octets) ; profil manette : fleches gauche / droite ;
##   B. MISSILE : vise le camion devant (pas celui de derriere), le touche :
##      -20 PV, souleve ; un second appui pendant la recharge ne tire rien ;
##   C. LASER : 90 ticks a 0,4 PV sur le camion devant (-36 PV), pas derriere ;
##   D. BOUCLIER : 300 ticks sans degats, puis les degats reprennent ;
##   E. emplacement vide : rien ; une epave ne tire pas.
## Tireur A en (0, 0, 0) face a -Z, cible B 40 m devant, C 40 m derriere ;
## D (bouclier) a l'ecart.

var _a: Truck
var _b: Truck
var _c: Truck
var _d: Truck
var _pa: TruckPowers
var _pd: TruckPowers
var _seen: Dictionary = {}
var _hp_b0: float = 0.0
var _missiles: int = 0


func _test_setup() -> void:
	duration_ticks = 460
	add_floor(2000.0)
	_a = TruckTestUtil.spawn_truck(self, Vector3(0.0, 0.0, 0.0))
	_b = TruckTestUtil.spawn_truck(self, Vector3(0.0, 0.0, -40.0))
	_c = TruckTestUtil.spawn_truck(self, Vector3(0.0, 0.0, 40.0))
	_d = TruckTestUtil.spawn_truck(self, Vector3(300.0, 0.0, 0.0))
	for t in [_a, _b, _c, _d]:
		(t as Truck).add_to_group(TruckPowers.TARGETS)
	_pa = TruckPowers.setup(_a, PowerCatalog.Id.MISSILE, PowerCatalog.Id.LASER)
	_pd = TruckPowers.setup(_d, PowerCatalog.Id.SHIELD, -1)
	child_entered_tree.connect(func(n: Node) -> void:
		if n is PowerMissile:
			_missiles += 1
			(n as PowerMissile).exploded.connect(func(_at: Vector3, v: Truck) -> void: _seen["victim"] = v))


func _press(t: Truck, left: bool, right: bool) -> void:
	var f := InputFrame.new()
	f.power_left = left
	f.power_right = right
	t.set_input(f)


func _test_tick(t: int) -> void:
	# fronts d'un tick, puis neutre
	_press(_a, t == 30 or t == 45, t == 130)
	_press(_d, t == 30 or t == 40, t == 30)
	match t:
		29:
			_hp_b0 = TruckHealth.of(_b).hp
			_seen["target"] = _pa.target_ahead()
		31:
			_seen["cool"] = _pa.seconds_left(0)
		50:
			_seen["missiles_after_spam"] = _missiles
		110:
			_seen["hp_b_missile"] = TruckHealth.of(_b).hp
			_seen["hp_c_missile"] = TruckHealth.of(_c).hp
			_seen["b_up"] = _b.global_position.y
		128:
			_seen["hp_b_before_laser"] = TruckHealth.of(_b).hp
		225:
			_seen["hp_b_laser"] = TruckHealth.of(_b).hp
			_seen["hp_c_laser"] = TruckHealth.of(_c).hp
			_seen["laser_hit"] = _pa.laser_hit
			_seen["laser_done"] = _pa.laser_ticks
		60:
			var h := TruckHealth.of(_d)
			h.damage(10.0, &"test")
			_seen["shielded_hp"] = h.hp
			_seen["empty_slot"] = _pd.use(1)
		340:
			var h := TruckHealth.of(_d)
			h.damage(10.0, &"test")
			_seen["after_shield_hp"] = h.hp
		350:
			# epave : plus rien ne part
			TruckHealth.of(_c).damage(1000.0, &"test")
		352:
			var pc := TruckPowers.setup(_c, PowerCatalog.Id.MISSILE, -1)
			_seen["wreck_fire"] = pc.use(0)


func _test_finish() -> void:
	check("catalogue : BOUCLIER, MISSILE, LASER en tete (2e serie : powers2_test)", PowerCatalog.count() >= 3
		and PowerCatalog.display_name(PowerCatalog.Id.SHIELD) == "BOUCLIER"
		and PowerCatalog.display_name(PowerCatalog.Id.MISSILE) == "MISSILE"
		and PowerCatalog.display_name(PowerCatalog.Id.LASER) == "LASER" and PowerCatalog.display_name(-1) == "AUCUN")
	var f := InputFrame.new()
	f.power_right = true
	f.cargo = true
	var g := InputFrame.from_bytes(f.to_bytes())
	check("InputFrame : fronts des pouvoirs transportes, toujours 6 octets",
		f.to_bytes().size() == 6 and g.power_right and not g.power_left and g.cargo)
	var d := PadBindings.defaults()
	check("manette : fleches gauche / droite de la croix", PadBindings.list_name(d["power_left"]) == "Gauche"
		and PadBindings.list_name(d["power_right"]) == "Droite")
	check("missile : vise le camion devant", _seen.get("target") == _b, str(_seen.get("target")))
	check("missile : touche B (-20 PV), pas C", _seen.get("victim") == _b
		and is_equal_approx(float(_seen.get("hp_b_missile", 0.0)), _hp_b0 - PowerCatalog.MISSILE_DAMAGE)
		and is_equal_approx(float(_seen.get("hp_c_missile", 0.0)), 100.0),
		"B %s, C %s" % [_seen.get("hp_b_missile"), _seen.get("hp_c_missile")])
	check("missile : recharge 15 s, un second appui ne tire rien", int(_seen.get("cool", 0)) == 15
		and int(_seen.get("missiles_after_spam", 0)) == 1, "%s s, %s missile(s)" % [_seen.get("cool"), _seen.get("missiles_after_spam")])
	var lost := float(_seen.get("hp_b_before_laser", 0.0)) - float(_seen.get("hp_b_laser", 0.0))
	check("laser : -36 PV sur B en 90 ticks, C intact, rayon eteint", absf(lost - 36.0) < 0.5
		and _seen.get("laser_hit") == _b and is_equal_approx(float(_seen.get("hp_c_laser", 0.0)), 100.0)
		and int(_seen.get("laser_done", 1)) == 0, "%.1f PV" % lost)
	check("bouclier : aucun degat pendant 5 s", is_equal_approx(float(_seen.get("shielded_hp", 0.0)), 100.0),
		str(_seen.get("shielded_hp")))
	check("bouclier : les degats reprennent apres", is_equal_approx(float(_seen.get("after_shield_hp", 0.0)), 90.0),
		str(_seen.get("after_shield_hp")))
	check("emplacement vide : rien", not bool(_seen.get("empty_slot", true)))
	check("une epave ne tire pas", not bool(_seen.get("wreck_fire", true)))
