extends PhysicsTest

## Raccrochage de la remorque sans projection (2026-10-01, « quand la remorque
## se remet apres l'avoir detachee, le camion peut etre propulse »).
##
## TruckCargo raccroche la remorque au bout de 60 s ; si sa place est prise,
## il attend reattach_timeout_ticks puis FORCE le raccrochage. La caisse de
## collision reapparaissait alors dans l'obstacle, et le solveur separait les
## deux corps d'un coup : le camion etait ejecte.
##
## Trois camions arretes, remorque detachee, raccrochage force au tick FORCE_AT :
##   A. un bloc de decor (couche monde) occupe presque toute la place de la
##      remorque (camion colle a une glissiere, pied de rampe) ;
##   B. un autre camion, en travers, occupe cette place ;
##   C. temoin : place libre ;
##   D. la remorque larguee d'un ADVERSAIRE (corps mobile de 9 t, couche
##      hazard) occupe la place : raccrochage normal, non force (avant le
##      2026-10-01, le test de place libre ignorait cette couche).
## Puis A et B avancent : la remorque doit redevenir solide une fois degagee.
## Criteres :
##   - jamais projete : vitesse < 1 m/s (A, B, le camion de B, D et la
##     remorque larguee de D) tant qu'ils sont arretes ;
##   - la remorque est raccrochee tout de suite (plus de bonus du tracteur
##     seul), meme si sa place est prise ;
##   - C : caisse de collision active des le raccrochage ;
##   - A et B : caisse active une fois l'obstacle degage.

const FORCE_AT := 30
const DRIVE_AT := 120

var _a: Truck
var _b: Truck
var _b_other: Truck
var _c: Truck
var _d: Truck
var _d_other: DetachedTrailer
var _frame := InputFrame.new()
var _idle := InputFrame.new()
var _max_v: Dictionary = {}
var _attached_at_force: Array[bool] = []
var _c_solid := false


func _test_setup() -> void:
	duration_ticks = 360
	add_floor(2000.0)
	_a = TruckTestUtil.spawn_truck(self, Vector3(0.0, 0.0, 0.0))
	_b = TruckTestUtil.spawn_truck(self, Vector3(200.0, 0.0, 0.0))
	_c = TruckTestUtil.spawn_truck(self, Vector3(400.0, 0.0, 0.0))
	_d = TruckTestUtil.spawn_truck(self, Vector3(600.0, 0.0, 0.0))
	for t: Truck in [_a, _b, _c]:
		t.detach_trailer()
	# remorque larguee par un adversaire, a la place exacte de celle de D
	_d_other = DetachedTrailer.new()
	_d_other.lifetime_ticks = 100000
	_d_other.transform = _d.detach_trailer()
	add_child(_d_other)
	# bloc de decor au milieu de la place de la remorque de A
	var block := StaticBody3D.new()
	block.collision_layer = 1 << (TruckSpec.LAYER_WORLD - 1)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 3.0, 12.0)   # presque toute la caisse : glissiere, pied de rampe
	cs.shape = box
	block.add_child(cs)
	block.position = TruckSpec.TRAILER_CENTER
	add_child(block)
	# camion en travers sur la place de la remorque de B
	_b_other = TruckTestUtil.spawn_truck(self, Vector3(200.0 - 12.0, 0.0, TruckSpec.TRAILER_CENTER.z),
		Vector3(0.0, 90.0, 0.0))
	_frame.throttle = 1.0
	for k: String in ["A", "B", "B autre camion", "C", "D", "D remorque adverse"]:
		_max_v[k] = 0.0


func _speed(t: Truck) -> float:
	return t.linear_velocity.length()


func _test_tick(t: int) -> void:
	_frame.tick = t
	_idle.tick = t
	var drive := t >= DRIVE_AT
	_a.set_input(_frame if drive else _idle)
	_b.set_input(_frame if drive else _idle)
	_c.set_input(_idle)
	_d.set_input(_idle)
	_b_other.set_input(_idle)
	if t == FORCE_AT:
		for tr: Truck in [_a, _b, _c]:
			tr.reattach_trailer(true)
			_attached_at_force.append(not tr.is_trailer_detached())
	if t >= FORCE_AT and _d.is_trailer_detached():
		_d.reattach_trailer(false)
	if t > FORCE_AT and t < DRIVE_AT:
		_max_v["A"] = maxf(_max_v["A"], _speed(_a))
		_max_v["B"] = maxf(_max_v["B"], _speed(_b))
		_max_v["B autre camion"] = maxf(_max_v["B autre camion"], _speed(_b_other))
	if t > FORCE_AT:
		_max_v["C"] = maxf(_max_v["C"], _speed(_c))
		_max_v["D"] = maxf(_max_v["D"], _speed(_d))
		_max_v["D remorque adverse"] = maxf(_max_v["D remorque adverse"], _d_other.linear_velocity.length())
	if t == FORCE_AT + 1:
		_c_solid = _solid(_c)


func _solid(t: Truck) -> bool:
	var shape := t.get_node(^"Trailer") as CollisionShape3D
	return not shape.disabled


func _test_finish() -> void:
	for k: String in _max_v:
		check_below("%s : jamais projete apres le raccrochage (m/s)" % k, _max_v[k], 1.0)
	check("raccrochee tout de suite, place prise ou non (A, B, C)",
		_attached_at_force == [true, true, true], str(_attached_at_force))
	check("C (place libre) : caisse active des le raccrochage", _c_solid)
	for tr: Truck in [_a, _b]:
		print("  INFO   %s : avance de %.0f m apres degagement" % [tr.name, absf(tr.global_position.z)])
	check("A : caisse active une fois le bloc degage", _solid(_a))
	check("B : caisse active une fois le camion degage", _solid(_b))
	check_finite("A : position finie", _a.global_position)
	check_finite("B : position finie", _b.global_position)
