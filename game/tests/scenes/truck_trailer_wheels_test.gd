extends PhysicsTest

## En virage, aucune remorque ne traverse les roues arriere du tracteur
## (2026-10-06 : « le probleme n'est pas regle » - la remorque pivote jusqu'a
## +-35 deg et penche au-dessus d'elles). SAUTE si les modeles sont absents
## (clone sans Git LFS).
##
## Un camion par remorque du catalogue, tous pilotes pareil : chute, virages
## serres a basse vitesse dans les deux sens, drifts au frein a main. A chaque
## tick, les sommets bas de l'avant de chaque remorque (repere de son pivot,
## articulation et roulis compris) sont compares aux pneus arriere du tracteur
## (debattement compris).

const SPACING := 60.0

var _trucks: Array[Truck] = []
var _types: Array[TrailerType] = []
var _trailer_pivots: Array[Node3D] = []
var _rear: Array = []        # par camion : [pivots de roue arriere]
## Par camion : sommets de l'avant de la remorque, repere de son pivot.
var _front: Array[PackedVector3Array] = []
var _worst: int = 0
var _worst_at: String = ""
var _max_angle: float = 0.0
var _frame := InputFrame.new()


func _test_setup() -> void:
	duration_ticks = 760
	TruckVisual.load_external_in_headless = true
	add_floor(4000.0)
	for i in TrailerCatalog.count():
		var type := TrailerCatalog.at(i)
		var t := TruckTestUtil.spawn_truck(self, Vector3(i * SPACING, 2.0, 0.0))
		var visual := t.get_node("Visual") as TruckVisual
		if not visual.model_loaded:
			skip("modele externe absent (%s)" % visual.external_model)
			return
		t.set_trailer_type(type)
		visual.set_trailer_type(type)
		if visual.get_trailer_skin() == null:
			skip("modele de remorque absent (%s)" % type.model)
			return
		var model := visual.get_node("ExternalModel")
		var pivot := model.get_node(NodePath(TruckVisual.TRAILER_PIVOT)) as Node3D
		var rear: Array[Node3D] = []
		for p in model.get_children():
			if p is Node3D and String(p.name).begins_with("WheelPivot_R"):
				rear.append(p as Node3D)
		var verts := PackedVector3Array()
		var to_pivot := pivot.global_transform.affine_inverse()
		for n in visual.get_trailer_skin().find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var xf := to_pivot * mi.global_transform
			for si in mi.mesh.get_surface_count():
				for v: Vector3 in mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
					var w := xf * v
					# avant bas de la remorque : la seule partie qui passe au-dessus
					# des roues du tracteur (sellette a l'origine, remorque vers +Z)
					if w.y < 0.6 and Vector2(w.x, w.z).length() < 4.0:
						verts.append(w)
		_trucks.append(t)
		_types.append(type)
		_trailer_pivots.append(pivot)
		_rear.append(rear)
		_front.append(verts)


func _test_tick(t: int) -> void:
	if _trucks.is_empty():
		return
	_frame.tick = t
	_frame.throttle = 0.0
	_frame.steer = 0.0
	_frame.handbrake = false
	var phase := "chute"
	if t > 90 and t <= 330:
		phase = "virages serres"
		_frame.throttle = 0.5
		_frame.steer = 1.0 if (t / 80) % 2 == 0 else -1.0
	elif t > 330 and t <= 520:
		phase = "elan"
		_frame.throttle = 1.0
	elif t > 520:
		phase = "drifts"
		_frame.throttle = 1.0
		_frame.steer = 1.0 if t < 640 else -1.0
		_frame.handbrake = (t > 520 and t < 560) or (t > 640 and t < 680)
	for k in _trucks.size():
		var truck := _trucks[k]
		truck.set_input(_frame)
		_max_angle = maxf(_max_angle, absf(truck.get_trailer_angle_deg()))
		var pivot := _trailer_pivots[k]
		for w: Node3D in _rear[k]:
			var tire: Vector2 = w.get_meta(&"tire")
			var to_tire := Transform3D(w.transform.basis.orthonormalized(), w.transform.origin).affine_inverse() \
				* pivot.transform
			var inside := 0
			for v in _front[k]:
				var l := to_tire * v
				if absf(l.x) <= tire.y and Vector2(l.y, l.z).length() <= tire.x:
					inside += 1
			if inside > _worst:
				_worst = inside
				_worst_at = "%s, roue %s, %s, tick %d, remorque a %.0f deg" % [_types[k].display_name, w.name,
					phase, t, truck.get_trailer_angle_deg()]


func _test_finish() -> void:
	check_above("les remorques ont vraiment pivote (deg)", _max_angle, 20.0)
	check("aucune remorque dans les roues arriere du tracteur", _worst == 0,
		("pire : %d sommets (%s)" % [_worst, _worst_at]) if _worst > 0 else "%d remorques suivies" % _trucks.size())
	TruckVisual.load_external_in_headless = false
