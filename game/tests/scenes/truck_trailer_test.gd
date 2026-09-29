extends PhysicsTest

## Remorque articulee (VEHICLE_SPEC §5 bis) : la caisse pivote autour de la
## sellette, avec sa propre inertie de lacet. Cinq scenes sur des voies
## espacees de 100 m, vitesses initiales posees au tick 0 (CLAUDE.md §10 b) :
##   A. ligne droite : la remorque reste dans l'axe (< 0,5 deg) ;
##   B. derapage a gauche (plein braquage + frein a main) : elle chasse vers
##      l'EXTERIEUR (a droite, angle > 0) de plus de 15 deg, jamais au-dela de
##      la butee de 35 deg ; la boite de collision et le pivot visuel suivent
##      le meme angle ; relachee, elle se realigne (< 2 deg) ;
##   C. coup de volant sec a droite : elle chasse vers la gauche (exterieur) ;
##   D. mur de 0,3 m a droite pendant un derapage a gauche : la remorque
##      s'arrete contre le mur, ses coins n'y entrent jamais (< 20 cm), le
##      camion n'est ni envole ni couche ;
##   E. balayage : en derapage, la remorque percute un camion qui roule a sa
##      droite. Il est pousse vers la droite (> 2 m/s), personne ne se couche.
## Le tracteur n'est pas touche par l'articulation : les metriques de conduite
## (handling_test) sont inchangees.

const V0 := 22.0      # m/s, ~80 km/h
const DRIFT_FROM := 20
const DRIFT_TO := 110
const WALL_X := 103.2

var _a: Truck
var _b: Truck
var _c: Truck
var _d: Truck
var _e: Truck
var _e_victim: Truck
var _frames: Dictionary = {}
var _a_max: float = 0.0
var _b_max: float = 0.0
var _b_min: float = 0.0
var _b_end: float = 0.0
var _c_min: float = 0.0
var _c_max: float = 0.0
var _d_max: float = 0.0
var _d_pen: float = -INF
var _max_tilt: float = 0.0
var _max_y: float = 0.0
var _shape_ok: bool = true
var _visual_ok: bool = true
var _victim_v0: float = 0.0
var _victim_push: float = 0.0
var _shoves: int = 0


func _test_setup() -> void:
	duration_ticks = 360
	add_floor(1500.0)
	_a = _spawn(Vector3(-200.0, 0.0, 600.0))
	_b = _spawn(Vector3(-100.0, 0.0, 600.0))
	_c = _spawn(Vector3(0.0, 0.0, 600.0))
	_d = _spawn(Vector3(100.0, 0.0, 600.0))
	# D. mur a droite du camion, sur toute la longueur du test
	_add_wall(Vector3(WALL_X, 0.0, 400.0), 420.0)
	# E. la victime roule a droite, a hauteur de l'arriere de la remorque
	_e = _spawn(Vector3(200.0, 0.0, 600.0))
	_e_victim = _spawn(Vector3(200.0 + 5.0, 0.0, 600.0 + 10.0))
	_e.trailer_shoved.connect(func(_o: Truck, _j: float) -> void: _shoves += 1)


func _spawn(p: Vector3) -> Truck:
	var t := TruckTestUtil.spawn_truck(self, p)
	t.linear_velocity = Vector3(0.0, 0.0, -V0)
	_frames[t] = InputFrame.new()
	return t


func _add_wall(center: Vector3, length: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.3, 2.8, length)
	cs.shape = box
	body.add_child(cs)
	body.position = center + Vector3(0.0, 1.4, 0.0)
	add_child(body)


func _drive(t: Truck, tick: int, steer: float, handbrake: bool) -> void:
	var f: InputFrame = _frames[t]
	f.tick = tick
	f.throttle = 1.0
	f.steer = steer
	f.handbrake = handbrake
	t.set_input(f)


func _test_tick(t: int) -> void:
	var drifting := t >= DRIFT_FROM and t < DRIFT_TO
	_drive(_a, t, 0.0, false)
	_drive(_b, t, -1.0 if drifting else 0.0, drifting)
	_drive(_c, t, 1.0 if (t >= DRIFT_FROM and t < DRIFT_FROM + 15) else 0.0, false)
	_drive(_d, t, -1.0 if drifting else 0.0, drifting)
	_drive(_e, t, -1.0 if drifting else 0.0, drifting)
	_drive(_e_victim, t, 0.0, false)
	if t == DRIFT_FROM:
		_victim_v0 = _e_victim.linear_velocity.x

	if t % 6 == 0 and OS.has_environment("TRAILER_TRACE"):
		var v := _b.linear_velocity
		var fwd := -_b.global_basis.z
		var slip := rad_to_deg(atan2(v.dot(_b.global_basis.x), v.dot(fwd)))
		print("TRACE t=%d ang=%.1f yaw=%.2f slip=%.1f v=%.1f" % [t, _b.get_trailer_angle_deg(), _b.angular_velocity.y, slip, v.length()])
	_a_max = maxf(_a_max, absf(_a.get_trailer_angle_deg()))
	_b_max = maxf(_b_max, _b.get_trailer_angle_deg())
	_b_min = minf(_b_min, _b.get_trailer_angle_deg())
	_c_min = minf(_c_min, _c.get_trailer_angle_deg())
	_c_max = maxf(_c_max, _c.get_trailer_angle_deg())
	_d_max = maxf(_d_max, _d.get_trailer_angle_deg())
	# D. coins de la caisse de remorque contre la face interieure du mur
	var txf := _d.global_transform * Truck.trailer_local_transform(_d.get_trailer_angle())
	var h := TruckSpec.TRAILER_SIZE / 2.0
	for corner: Vector3 in [Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, h.z)]:
		_d_pen = maxf(_d_pen, (txf * corner).x - (WALL_X - 0.15))
	if t == duration_ticks:
		_b_end = absf(_b.get_trailer_angle_deg())
	_victim_push = maxf(_victim_push, _e_victim.linear_velocity.x - _victim_v0)
	for tr: Truck in [_a, _b, _c, _d, _e, _e_victim]:
		_max_tilt = maxf(_max_tilt, TruckTestUtil.tilt_deg(tr))
		_max_y = maxf(_max_y, tr.global_position.y)
	# la boite de collision et le pivot visuel suivent l'angle du camion B
	var shape := _b.get_node("Trailer") as CollisionShape3D
	var expect := Truck.trailer_local_transform(_b.get_trailer_angle())
	if not shape.transform.is_equal_approx(expect) and absf(
			shape.transform.basis.get_euler().y - _b.get_trailer_angle()) > 0.001:
		_shape_ok = false
	var pivot := _b.get_node("Visual/TrailerPivot") as Node3D
	if absf(pivot.basis.get_euler().y - _b.get_trailer_angle()) > 0.001 and t > 1:
		_visual_ok = false


func _test_finish() -> void:
	print("  INFO   B derapage : max %.1f / min %.1f deg ; C coup de volant : %.1f .. %.1f deg ; D mur : max %.1f deg"
		% [_b_max, _b_min, _c_min, _c_max, _d_max])
	print("  INFO   E balayage : %d choc(s), victime poussee de %.2f m/s" % [_shoves, _victim_push])
	check_below("A ligne droite : remorque dans l'axe (deg)", _a_max, 0.5)
	check_above("B derapage a gauche : la remorque chasse a droite (deg)", _b_max, 15.0)
	check_below("B jamais au-dela de la butee (deg)", maxf(_b_max, -_b_min), 35.001)
	check("B boite de collision a l'angle de la remorque", _shape_ok)
	check("B pivot visuel a l'angle de la remorque", _visual_ok)
	check_below("B relachee : realignee (deg)", _b_end, 2.0)
	check_below("C coup de volant a droite : chasse a gauche (deg)", _c_min, -4.0)
	check_below("D mur : la remorque s'arrete contre le mur (deg, B = reference)", _d_max, _b_max)
	check_below("D mur : les coins de la remorque n'y entrent pas (m, tolerance de contact)", _d_pen, 0.2)
	check("E balayage : au moins un choc de remorque", _shoves >= 1, "%d" % _shoves)
	check_above("E balayage : victime poussee vers la droite (m/s)", _victim_push, 2.0)
	check_below("personne ne se couche (deg)", _max_tilt, 45.0)
	check_below("personne ne s'envole (m)", _max_y, 1.5)
