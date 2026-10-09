extends PhysicsTest

## Les roues de la remorque suivent le sol (2026-10-06 : « les roues de la
## remorque passent dans le sol », « la remorque est trop rigide »). SAUTE si
## les modeles sont absents (clone sans Git LFS).
##
## Trois camions (citerne, porte-voitures, grue) roulent sur un relief : rampe
## montante de 6 deg, plateau, rampe descendante. Sans suivi du sol, la
## remorque garde l'assiette du tracteur : au pied de la montee, ses roues
## s'enfoncent ; au pied de la descente aussi. A chaque tick, pour chaque
## essieu : bas du pneu compare au sol sous lui (rayon du test).

const SLOPE_DEG := 6.0
const RAMP_LEN := 24.0
const PLATEAU_LEN := 40.0
const TRAILERS: PackedStringArray = ["citerne", "porte_voitures", "grue"]
## Enfoncement tolere (m) : le ressort du suivi a un tick de retard.
const MAX_SINK := 0.06

var _trucks: Array[Truck] = []
var _visuals: Array[TruckVisual] = []
var _names: PackedStringArray = []
var _probe: RayCast3D
var _worst: float = 0.0
var _worst_at: String = ""
var _max_pitch: float = 0.0
var _max_axle_travel: float = 0.0
var _spin_seen: bool = false
var _frame := InputFrame.new()


func _test_setup() -> void:
	duration_ticks = 900
	TruckVisual.load_external_in_headless = true
	add_floor(4000.0)
	_build_relief()
	for k in TRAILERS.size():
		var type := load("res://vehicles/trailers/%s.tres" % TRAILERS[k]) as TrailerType
		var t := TruckTestUtil.spawn_truck(self, Vector3(k * 14.0, 1.6, 30.0))
		var visual := t.get_node("Visual") as TruckVisual
		if not visual.model_loaded:
			skip("modele externe absent (%s)" % visual.external_model)
			return
		t.set_trailer_type(type)
		visual.set_trailer_type(type)
		if visual.get_trailer_skin() == null:
			skip("modele de remorque absent (%s)" % type.model)
			return
		_trucks.append(t)
		_visuals.append(visual)
		_names.append(type.display_name)
	_probe = RayCast3D.new()
	_probe.top_level = true
	_probe.enabled = false
	add_child(_probe)


## Rampe montante, plateau, rampe descendante, sur toute la largeur des voies,
## en direction de -Z (l'avant des camions).
func _build_relief() -> void:
	var a := deg_to_rad(SLOPE_DEG)
	var h := RAMP_LEN * sin(a)
	var run := RAMP_LEN * cos(a)
	var z0 := 0.0
	_slab(Vector3(14.0, h / 2.0 - 0.5 * cos(a), z0 - run / 2.0), Vector3(60.0, 1.0, RAMP_LEN), a)
	_slab(Vector3(14.0, h - 0.5, z0 - run - PLATEAU_LEN / 2.0), Vector3(60.0, 1.0, PLATEAU_LEN), 0.0)
	_slab(Vector3(14.0, h / 2.0 - 0.5 * cos(a), z0 - run - PLATEAU_LEN - run / 2.0), Vector3(60.0, 1.0, RAMP_LEN), -a)


func _slab(center: Vector3, size: Vector3, pitch: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1 << (TruckSpec.LAYER_WORLD - 1)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	body.transform = Transform3D(Basis(Vector3.RIGHT, pitch), center)
	add_child(body)


func _ground(p: Vector3) -> float:
	_probe.global_position = p + Vector3(0.0, 3.0, 0.0)
	_probe.target_position = Vector3(0.0, -6.0, 0.0)
	_probe.force_raycast_update()
	return _probe.get_collision_point().y if _probe.is_colliding() else NAN


func _test_tick(t: int) -> void:
	if _trucks.is_empty():
		return
	_frame.tick = t
	_frame.throttle = 0.55 if t > 60 else 0.0
	_frame.steer = 0.0
	for k in _trucks.size():
		var truck := _trucks[k]
		truck.set_input(_frame)
		var skin := _visuals[k].get_trailer_skin()
		var pivot := skin.get_parent_node_3d()
		_max_pitch = maxf(_max_pitch, absf(rad_to_deg(pivot.basis.get_euler().x)))
		for n in skin.find_children("Gen_Essieu_*", "Node3D", true, false):
			var axle := n as Node3D
			var r := _axle_radius(axle)
			for side: float in [-1.0, 1.0]:
				var hub := axle.global_transform * Vector3(side * 0.9, 0.0, 0.0)
				var bottom := hub - Vector3.UP * r
				var g := _ground(bottom)
				if is_nan(g) or bottom.y - g > 1.5:
					continue   # en l'air : rien a mesurer
				var sink := g - bottom.y
				if sink > _worst:
					_worst = sink
					_worst_at = "%s, %s, tick %d" % [_names[k], axle.name, t]
			_max_axle_travel = maxf(_max_axle_travel, absf(axle.position.y - _rest_y(axle)))
			if not axle.basis.is_equal_approx(Basis.IDENTITY):
				_spin_seen = true


var _radius_cache: Dictionary = {}
var _rest_cache: Dictionary = {}


func _axle_radius(axle: Node3D) -> float:
	if not _radius_cache.has(axle):
		var r := 0.0
		for n in axle.find_children("*", "MeshInstance3D", true, false):
			r = maxf(r, (n as MeshInstance3D).get_aabb().size.y / 2.0)
		if axle is MeshInstance3D:
			r = maxf(r, (axle as MeshInstance3D).get_aabb().size.y / 2.0)
		_radius_cache[axle] = r
	return _radius_cache[axle]


func _rest_y(axle: Node3D) -> float:
	if not _rest_cache.has(axle):
		_rest_cache[axle] = axle.position.y
	return _rest_cache[axle]


func _test_finish() -> void:
	var far := 0.0
	for truck in _trucks:
		far = maxf(far, -truck.global_position.z)
	check_above("les camions ont franchi le relief (m)", far, RAMP_LEN * 2.0 + PLATEAU_LEN)
	check_above("la remorque a pris l'assiette du sol (deg)", _max_pitch, SLOPE_DEG * 0.5)
	check("les roues de la remorque tournent", _spin_seen)
	check_below("roues de remorque jamais dans le sol (m)", _worst, MAX_SINK)
	if _worst >= MAX_SINK:
		print("        | pire enfoncement : %.2f m (%s)" % [_worst, _worst_at])
	TruckVisual.load_external_in_headless = false
