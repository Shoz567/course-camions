extends PhysicsTest

## Les roues de la tete ne traversent pas la carrosserie (2026-10-06 : « en
## drift, a l'atterrissage, en virage, les roues traversent »). SAUTE si le
## modele externe est absent (clone sans Git LFS).
##
## Le camion tombe de 4 m, accelere, braque a fond a basse vitesse, drifte au
## frein a main, contre-braque et pile. A chaque tick, pour chaque roue : les
## sommets de la carrosserie proches de la roue (repere de la carrosserie,
## penche compris) sont compares au pneu (repere de son pivot, debattement et
## braquage compris). Aucun sommet ne doit entrer dans un pneu, au-dela de ceux
## qui y sont deja au repos.

var _truck: Truck
var _visual: TruckVisual
var _body: Node3D
var _pivots: Array[Node3D] = []
## Par roue : sommets de carrosserie proches (repere de Body), rayon,
## demi-largeur, sommets deja dans le pneu au repos.
var _near: Array[PackedVector3Array] = []
## Par roue : nom de la piece de chaque sommet proche (diagnostic).
var _near_names: Array[PackedStringArray] = []
var _tire: Array[Vector2] = []
var _rest_inside: PackedInt32Array = []
var _worst: int = 0
var _worst_at: String = ""
var _max_up: float = 0.0
var _max_roll: float = 0.0
var _max_steer: float = 0.0
var _frame := InputFrame.new()


func _test_setup() -> void:
	duration_ticks = 900
	TruckVisual.load_external_in_headless = true
	add_floor(2000.0)
	_truck = TruckTestUtil.spawn_truck(self, Vector3(0.0, 4.0, 0.0))
	_visual = _truck.get_node("Visual") as TruckVisual
	if not _visual.model_loaded:
		skip("modele externe absent (%s)" % _visual.external_model)
		return
	var model := _visual.get_node("ExternalModel")
	_body = model.get_node("Body") as Node3D
	for p in model.get_children():
		if p is Node3D and (p as Node3D).has_meta(&"tire"):
			_pivots.append(p as Node3D)
	# sommets de la carrosserie (hors remorque), repere de Body
	var verts := PackedVector3Array()
	var names := PackedStringArray()
	for n in _body.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if String(mi.get_path()).contains("Remorque"):
			continue
		var xf := _body.global_transform.affine_inverse() * mi.global_transform
		for si in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
				verts.append(xf * v)
				names.append(String(mi.name))
	var body_rest := _body.transform
	for p in _pivots:
		var tire: Vector2 = p.get_meta(&"tire")
		_tire.append(tire)
		var near := PackedVector3Array()
		var near_names := PackedStringArray()
		for k in verts.size():
			var v := verts[k]
			var w := body_rest * v   # repere du modele (comme les pivots)
			if (w - p.position).length() < tire.x + tire.y + 1.0:
				near.append(v)
				near_names.append(names[k])
		_near.append(near)
		_near_names.append(near_names)
		_rest_inside.append(_inside(near, body_rest, p.transform, tire))


func _inside(near: PackedVector3Array, body_xf: Transform3D, pivot_xf: Transform3D, tire: Vector2) -> int:
	var to_tire := _tire_frame(pivot_xf).affine_inverse() * body_xf
	var count := 0
	for v in near:
		var l := to_tire * v
		if absf(l.x) <= tire.y and Vector2(l.y, l.z).length() <= tire.x:
			count += 1
	return count


func _test_tick(t: int) -> void:
	if _pivots.is_empty():
		return
	_frame.tick = t
	_frame.throttle = 0.0
	_frame.brake = 0.0
	_frame.steer = 0.0
	_frame.handbrake = false
	var phase := "atterrissage"
	if t > 150 and t <= 260:
		phase = "braquage a fond, basse vitesse"
		_frame.throttle = 0.4
		_frame.steer = 1.0 if t < 205 else -1.0
	elif t > 260 and t <= 520:
		phase = "acceleration"
		_frame.throttle = 1.0
	elif t > 520 and t <= 700:
		phase = "drift"
		_frame.throttle = 1.0
		_frame.steer = 1.0
		_frame.handbrake = t < 570
	elif t > 700 and t <= 800:
		phase = "contre-braquage"
		_frame.throttle = 1.0
		_frame.steer = -1.0
	elif t > 800:
		phase = "freinage"
		_frame.brake = 1.0
	_truck.set_input(_frame)
	var rest := TruckSpec.rest_hub_distance()
	for i in 4:
		_max_up = maxf(_max_up, rest - _truck.get_probe(i).hub_distance)
	_max_roll = maxf(_max_roll, absf(_visual.get_lean_deg().y))
	_max_steer = maxf(_max_steer, absf(_truck.get_steer_deg()))
	for i in _pivots.size():
		var extra := _inside(_near[i], _body.transform, _pivots[i].transform, _tire[i]) - _rest_inside[i]
		if extra > _worst:
			_worst = extra
			_worst_at = "%s, %s, tick %d, sommets (repere du pneu) %s" % [_pivots[i].name, phase, t,
				_sample(i)]


## Pieces dont des sommets sont dans le pneu de la roue `i` (diagnostic) :
## nom et un sommet, dans le repere du pneu.
func _sample(i: int) -> String:
	var to_tire := _tire_frame(_pivots[i].transform).affine_inverse() * _body.transform
	var tire := _tire[i]
	var seen := {}
	for k in _near[i].size():
		var l := to_tire * _near[i][k]
		if absf(l.x) <= tire.y and Vector2(l.y, l.z).length() <= tire.x and not seen.has(_near_names[i][k]):
			seen[_near_names[i][k]] = "%s (%.2f, %.2f, %.2f)" % [_near_names[i][k], l.x, l.y, l.z]
	return ", ".join(PackedStringArray(seen.values()))


func _test_finish() -> void:
	check_above("la suspension a vraiment travaille (m)", _max_up, 0.2)
	check_above("la carrosserie a vraiment penche (deg)", _max_roll, 3.0)
	check_above("les roues ont vraiment braque (deg)", _max_steer, 20.0)
	check("aucun sommet de carrosserie dans un pneu", _worst == 0,
		"pire : %d sommets (%s)" % [_worst, _worst_at] if _worst > 0 else "%d roues suivies" % _pivots.size())
	TruckVisual.load_external_in_headless = false


## Repere du pneu en metres : le pivot porte aussi l'echelle et le demi-tour
## du modele (TruckVisual._fit) ; seuls comptent sa position et son braquage
## (le demi-tour ne change ni |x| ni la distance a l'axe).
static func _tire_frame(pivot_xf: Transform3D) -> Transform3D:
	return Transform3D(pivot_xf.basis.orthonormalized(), pivot_xf.origin)
