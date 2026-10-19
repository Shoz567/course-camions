extends PhysicsTest

## Pouvoirs en ligne (2026-10-19 : « les pouvoirs sont actuellement uniquement
## cote host ») : chez le host, un tir annonce l'emplacement et la cible
## (fired, last_target -> NetRace Ev.POWER) ; chez un client, TruckPowers en
## miroir (mirror) :
##   A. n'ecoute pas les entrees : appuyer ne tire rien ;
##   B. net_fire rejoue le tir : recharge, missile en copie qui explose sur la
##      cible sans lui retirer de PV ;
##   C. laser rejoue : rayon actif, touche la cible, aucun PV retire ;
##   D. bouclier rejoue : aura (shield_ticks) le temps du bouclier.
## Host : tireur A, cible B 40 m devant. Client : tireur A2, cible B2 (meme
## disposition, 300 m a cote).

var _a: Truck
var _b: Truck
var _a2: Truck
var _b2: Truck
var _host: TruckPowers
var _mirror: TruckPowers
var _shield: TruckPowers
var _fired: Array = []
var _boom: Array = []
var _seen: Dictionary = {}


func _test_setup() -> void:
	duration_ticks = 240
	add_floor(2000.0)
	_a = TruckTestUtil.spawn_truck(self, Vector3(0.0, 0.0, 0.0))
	_b = TruckTestUtil.spawn_truck(self, Vector3(0.0, 0.0, -40.0))
	_a2 = TruckTestUtil.spawn_truck(self, Vector3(300.0, 0.0, 0.0))
	_b2 = TruckTestUtil.spawn_truck(self, Vector3(300.0, 0.0, -40.0))
	for t in [_a, _b, _a2, _b2]:
		(t as Truck).add_to_group(TruckPowers.TARGETS)
	_host = TruckPowers.setup(_a, PowerCatalog.Id.MISSILE, PowerCatalog.Id.LASER)
	_mirror = TruckPowers.setup(_a2, PowerCatalog.Id.MISSILE, PowerCatalog.Id.LASER, true)
	_shield = TruckPowers.setup(_b2, PowerCatalog.Id.SHIELD, -1, true)
	_host.fired.connect(func(slot: int, p: int) -> void: _fired.append([slot, p, _host.last_target]))
	child_entered_tree.connect(func(n: Node) -> void:
		if n is PowerMissile and (n as PowerMissile).mirror:
			(n as PowerMissile).exploded.connect(func(_at: Vector3, v: Truck) -> void: _boom.append(v)))


func _test_tick(t: int) -> void:
	var f := InputFrame.new()
	f.power_left = t == 20
	_a.set_input(f)
	var g := InputFrame.new()
	g.power_left = t == 20
	g.power_right = t == 20
	_a2.set_input(g)
	match t:
		22:
			_seen["mirror_cool"] = _mirror.cooldown.duplicate()
			# le host annonce : le client rejoue
			_mirror.net_fire(0, _b2)
			_seen["mirror_cool_after"] = _mirror.seconds_left(0)
			_shield.net_fire(0, null)
		24:
			_seen["shield"] = TruckHealth.of(_b2).shield_ticks
		90:
			_seen["hp_b2_missile"] = TruckHealth.of(_b2).hp
			TruckHealth.of(_b2).shield_ticks = 0
			_mirror.net_fire(1, null)
		120:
			_seen["laser_on"] = _mirror.laser_ticks
			_seen["laser_hit"] = _mirror.laser_hit
		200:
			_seen["hp_b2_laser"] = TruckHealth.of(_b2).hp


func _test_finish() -> void:
	check("host : le tir annonce l'emplacement et la cible", _fired.size() == 1
		and int(_fired[0][0]) == 0 and _fired[0][2] == _b, str(_fired))
	check("NetRace : evenement POWER", NetRace.Ev.has("POWER"))
	check("miroir : appuyer ne tire rien", _seen.get("mirror_cool") == PackedInt32Array([0, 0]),
		str(_seen.get("mirror_cool")))
	check("miroir : net_fire lance la recharge", int(_seen.get("mirror_cool_after", 0)) == 15)
	check("miroir : le missile explose sur la cible, sans retirer de PV", _boom == [_b2]
		and is_equal_approx(float(_seen.get("hp_b2_missile", 0.0)), 100.0),
		"%s, %s PV" % [_boom, _seen.get("hp_b2_missile")])
	check("miroir : laser actif sur la cible", int(_seen.get("laser_on", 0)) > 0 and _seen.get("laser_hit") == _b2)
	check("miroir : laser sans degat", is_equal_approx(float(_seen.get("hp_b2_laser", 0.0)), 100.0),
		str(_seen.get("hp_b2_laser")))
	check("miroir : bouclier rejoue (aura)", int(_seen.get("shield", 0)) > PowerCatalog.SHIELD_TICKS - 5)
