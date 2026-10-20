extends PhysicsTest

## Degats visuels gardes ou ajoutes (2026-10-20) :
##   A. bouclier : un choc violent contre un mur (signale) ne laisse ni trace
##      ni pneu use ; le meme choc sur un camion temoin, si ;
##   B. coller un mur (« ne pas desagreger le camion, les pneus ») : un camion
##      qui longe un mur en braquant dedans pendant 5 s le touche plusieurs
##      fois : des eraflures au plus, ni creux dans la tole ni usure de pneu ;
##   C. baril explosif : le camion qui le fait sauter garde une trace et des
##      sommets enfonces du cote du baril ; sous bouclier, rien.

var _shielded: Truck
var _plain: Truck
var _hugger: Truck
var _barrel_hit: Truck
var _barrel_shield: Truck
var _hug_hits: int = 0
var _hug_in: InputFrame = InputFrame.new()
var _seen: Dictionary = {}


func _test_setup() -> void:
	duration_ticks = 330
	add_floor(1600.0)
	_shielded = TruckTestUtil.spawn_truck(self, Vector3(0.0, 0.0, 0.0))
	_plain = TruckTestUtil.spawn_truck(self, Vector3(30.0, 0.0, 0.0))
	TruckHealth.of(_shielded).shield_ticks = 100000
	# B : mur a gauche, le long de la course (-Z), camion qui braque dedans
	_wall(Vector3(1.0, 4.0, 400.0), Vector3(93.0, 2.0, -150.0))
	_hugger = TruckTestUtil.spawn_truck(self, Vector3(100.0, 0.0, 0.0), Vector3(0.0, 4.0, 0.0))
	_hugger.linear_velocity = -_hugger.global_basis.z * 26.0
	_hug_in.throttle = 1.0
	_hug_in.steer = -0.25
	_hugger.set_input(_hug_in)
	_hugger.wall_impact_at.connect(func(_s: float, _t: bool, _p: Vector3, _n: Vector3) -> void: _hug_hits += 1)
	_barrel_hit = TruckTestUtil.spawn_truck(self, Vector3(200.0, 0.0, 0.0))
	_barrel_shield = TruckTestUtil.spawn_truck(self, Vector3(230.0, 0.0, 0.0))
	TruckHealth.of(_barrel_shield).shield_ticks = 100000


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


func _fx(t: Truck) -> TruckDamageFx:
	return t.get_node("DamageFx") as TruckDamageFx


func _wear(t: Truck) -> float:
	var tires := t.get_node("Tires") as TruckTires
	var w := 0.0
	for i in 6:
		w += tires.wear(i)
	return w


## Pieces de carrosserie creusees (BodyDamage : coups retenus par maillage).
func _dents(t: Truck) -> int:
	var c := 0
	for n in t.get_node("Visual").find_children("*", "MeshInstance3D", true, false):
		if n.has_meta(BodyDamage.META_HITS):
			c += 1
	return c


func _barrel(near: Truck) -> ExplosiveBarrel:
	var b := ExplosiveBarrel.new()
	b.position = near.global_position + near.global_basis.x * 2.6 + Vector3.DOWN * near.global_position.y
	add_child(b)
	return b


func _test_tick(t: int) -> void:
	if t == 30:
		# choc lateral violent, a hauteur de la roue avant gauche
		for tr: Truck in [_shielded, _plain]:
			var n := tr.global_basis.x
			var at := tr.global_transform * Vector3(-1.3, 0.6, TruckSpec.ANCHORS[0].z)
			tr.wall_impact_at.emit(18.0, false, at, n)
		for tr: Truck in [_barrel_hit, _barrel_shield]:
			_barrel(tr).explode(tr)
	if t == 60:
		_seen["shield"] = [_fx(_shielded).marks().size(), _wear(_shielded)]
		_seen["plain"] = [_fx(_plain).marks().size(), _wear(_plain)]
		_seen["barrel"] = _fx(_barrel_hit).marks().size()
		_seen["barrel_dents"] = _dents(_barrel_hit)
		_seen["barrel_shield"] = _fx(_barrel_shield).marks().size()


func _test_finish() -> void:
	var s: Array = _seen.get("shield", [-1, -1])
	var p: Array = _seen.get("plain", [0, 0])
	check("A bouclier : ni trace ni pneu use", s[0] == 0 and s[1] == 0.0, "traces %d, usure %.1f" % [s[0], s[1]])
	check("A temoin sans bouclier : trace et pneu use", p[0] > 0 and p[1] > 0.0, "traces %d, usure %.1f" % [p[0], p[1]])
	check("B longe le mur : plusieurs contacts", _hug_hits >= 2, "%d contacts" % _hug_hits)
	check("B longe le mur : ni creux ni pneu use", _dents(_hugger) == 0 and _wear(_hugger) == 0.0,
		"pieces creusees %d, usure %.1f" % [_dents(_hugger), _wear(_hugger)])
	check("C baril : trace et tole creusee", int(_seen.get("barrel", 0)) > 0 and int(_seen.get("barrel_dents", 0)) > 0,
		"traces %s, pieces creusees %s" % [_seen.get("barrel"), _seen.get("barrel_dents")])
	check("C baril sous bouclier : rien", int(_seen.get("barrel_shield", -1)) == 0, str(_seen.get("barrel_shield")))
