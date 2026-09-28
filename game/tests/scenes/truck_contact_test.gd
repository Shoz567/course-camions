extends PhysicsTest

## Contacts (directive arcade : les camions se percutent souvent). La physique
## doit absorber le choc : jamais retourne (inclinaison < 45 deg, critere de
## virage de CLAUDE.md §10), jamais envole (origine < 1,5 m, soit la moitie
## de la hauteur de cabine), jamais de NaN, jamais de mur traverse.
##
## Quatre scenes independantes, sur des voies espacees de 80 m :
##   A. choc lateral : un camion a 80 km/h percute le flanc d'un camion arrete ;
##   B. frottement : deux camions a 100 km/h cote a cote, l'un braque vers l'autre ;
##   C. mur de 0,3 m (METRICS.md §4) de face a 150 km/h ;
##   D. le meme mur a 30 deg, a 150 km/h ;
##   E. temoin : D avec l'anti-retournement coupe. L'aide doit reduire
##      l'inclinaison max d'au moins 30 % (ratio mesure dans la scene).
##      D et E roulent avec une caisse a 0,2 de frottement : le cas le plus
##      severe mesure (le temoin s'y couche a 52 deg ; a 0,5 le frottement
##      stabilise deja le camion et ne sollicite plus assez l'aide).
## Les vitesses initiales sont posees au tick 0 (m/s ajoutes, CLAUDE.md §10 b),
## puis les camions gardent le gaz.

const MAX_TILT_DEG := 45.0
const MAX_HEIGHT_M := 1.5
const WALL_THICKNESS := 0.3

var _trucks: Array[Truck] = []
var _labels: PackedStringArray = []
var _throttle: PackedFloat32Array = []
var _steer_from: PackedInt32Array = []
var _frames: Array[InputFrame] = []
var _max_tilt: PackedFloat32Array = []
var _max_y: PackedFloat32Array = []
var _upside: Array[bool] = []
var _nan: Array[bool] = []
var _walls: Array[Dictionary] = []   # {truck, z_back}


func _test_setup() -> void:
	duration_ticks = 300
	add_floor(2800.0)
	var lane := 0.0
	# A. choc lateral
	_add("A choc lateral : percuteur", Vector3(lane, 0.0, 30.0), 0.0, 80.0, 1.0)
	_add("A choc lateral : percute", Vector3(lane, 0.0, 0.0), 90.0, 0.0, 0.0)
	# B. frottement : le camion de gauche braque a droite vers l'autre au tick 20
	lane += 80.0
	_add("B frottement : braqueur", Vector3(lane - 1.6, 0.0, 0.0), 0.0, 100.0, 1.0, 20)
	_add("B frottement : frotte", Vector3(lane + 1.6, 0.0, 0.0), 0.0, 100.0, 1.0)
	# C. mur de face
	lane += 80.0
	var c := _add("C mur de face 150 km/h", Vector3(lane, 0.0, 0.0), 0.0, 150.0, 1.0)
	_add_wall(Vector3(lane, 0.0, -40.0), 0.0, c)
	# D. mur a 30 deg : le camion part vers -X et glisse le long du mur apres
	# l'impact ; mur de 300 m pour qu'il ne le depasse pas pendant le test.
	lane = 600.0
	var d := _add("D mur a 30 deg 150 km/h", Vector3(lane, 0.0, 0.0), 30.0, 150.0, 1.0)
	_severe(d)
	_add_wall(Vector3(lane - 150.0, 0.0, -40.0), 0.0, d, 300.0)
	# E. temoin sans anti-retournement
	lane = 1200.0
	var e := _add("E temoin sans aide (non verifie)", Vector3(lane, 0.0, 0.0), 30.0, 150.0, 1.0)
	e.debug_anti_roll = false
	_severe(e)
	_add_wall(Vector3(lane - 150.0, 0.0, -40.0), 0.0, e, 300.0)


func _add(label: String, pos: Vector3, yaw_deg: float, kmh: float, throttle: float,
		steer_from: int = -1) -> Truck:
	var t := TruckTestUtil.spawn_truck(self, pos, Vector3(0.0, yaw_deg, 0.0))
	t.linear_velocity = -t.global_transform.basis.z * kmh / 3.6
	_trucks.append(t)
	_labels.append(label)
	_throttle.append(throttle)
	_steer_from.append(steer_from)
	_frames.append(InputFrame.new())
	_max_tilt.append(0.0)
	_max_y.append(0.0)
	_upside.append(false)
	_nan.append(false)
	return t


## Caisse a 0,2 de frottement : le cas le plus severe pour l'anti-retournement.
func _severe(t: Truck) -> void:
	var pm := PhysicsMaterial.new()
	pm.friction = 0.2
	t.physics_material_override = pm


## Mur de 0,3 m, 3 m de haut, face avant a `pos.z`.
func _add_wall(pos: Vector3, yaw_deg: float, truck: Truck, width: float = 40.0) -> void:
	var w := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, 3.0, WALL_THICKNESS)
	cs.shape = box
	w.add_child(cs)
	w.position = pos + Vector3(0.0, 1.5, -WALL_THICKNESS / 2.0)
	w.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	add_child(w)
	_walls.append({"truck": truck, "z_back": pos.z - WALL_THICKNESS})


func _test_tick(t: int) -> void:
	for i in _trucks.size():
		var tr := _trucks[i]
		var f := _frames[i]
		f.tick = t
		f.throttle = _throttle[i]
		f.steer = 0.6 if _steer_from[i] >= 0 and t >= _steer_from[i] else 0.0
		tr.set_input(f)
		if not tr.global_position.is_finite():
			_nan[i] = true
			continue
		_max_tilt[i] = maxf(_max_tilt[i], TruckTestUtil.tilt_deg(tr))
		_max_y[i] = maxf(_max_y[i], tr.global_position.y)
		_upside[i] = _upside[i] or tr.is_upside_down()


func _test_finish() -> void:
	var n := _trucks.size()
	for i in n - 1:
		var l := _labels[i]
		check("%s : aucun NaN" % l, not _nan[i])
		check_below("%s : inclinaison max (deg)" % l, _max_tilt[i], MAX_TILT_DEG)
		check("%s : jamais retourne" % l, not _upside[i])
		check_below("%s : hauteur max (m)" % l, _max_y[i], MAX_HEIGHT_M)
	check_ratio_above("anti-retournement : inclinaison sans aide / avec aide",
		_max_tilt[n - 1], _max_tilt[n - 2], 1.0 / 0.7)
	for w in _walls:
		var tr: Truck = w["truck"]
		check_above("mur jamais traverse (z du camion - dos du mur, m)",
			tr.global_position.z - float(w["z_back"]), 0.0)
