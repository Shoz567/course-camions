extends PhysicsTest

## Camera de poursuite et decor (2026-10-02, « dans la montee de Cyber City la
## camera peut passer a travers le sol »). Le camion est fige et deplace a la
## main (rendu seulement : la camera ne touche pas a la physique), sans
## interpolation physique.
##   A. ecran plus rapide que la physique : 4 images par tick (240 Hz). Le
##      camion recule de 0,5 m par image vers un mur haut ; la camera, derriere
##      lui, s'en approche. Avant le 2026-10-02 le bras (SpringArm3D) ne
##      verifiait le decor qu'au tick physique : entre deux ticks, la camera
##      entrait dans le mur.
##   B. montee rapide : le camion monte a 11 m/s (225 km/h sur la pente de 10
##      deg de Cyber City). Le pivot suit la hauteur avec retard (anti-pompage) ;
##      il ne doit jamais descendre a moins de 2,5 m au-dessus du camion, d'ou
##      part le bras : un pivot au ras de la route ne voit plus le sol.
## Criteres : A, la camera reste a plus de 0,2 m du mur a chaque image ;
## B, pivot >= camion + 2,5 m a chaque image.

const FRAMES_PER_TICK := 4
const STEP_M := 0.5
const WALL_Z := 30.0
const CLIMB_MS := 11.0
const MIN_FOCUS_ABOVE := 2.5

var _a: Truck
var _a_cam: ChaseCamera
var _b: Truck
var _b_cam: ChaseCamera
var _a_worst := INF      # plus petite distance camera -> face du mur (m)
var _b_worst := INF      # plus petite hauteur du pivot au-dessus du camion (m)


func _test_setup() -> void:
	duration_ticks = 150
	add_floor(400.0)
	_a = _frozen_truck(Vector3(0.0, 0.0, 0.0))
	_a_cam = _camera_for(_a)
	# mur haut derriere A (camera en +Z, le camion regarde -Z)
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 60.0, 2.0)
	cs.shape = box
	wall.add_child(cs)
	wall.position = Vector3(0.0, 30.0, WALL_Z + 1.0)
	add_child(wall)
	_b = _frozen_truck(Vector3(200.0, 0.0, 0.0))
	_b_cam = _camera_for(_b)


func _frozen_truck(p: Vector3) -> Truck:
	var t := TruckTestUtil.spawn_truck(self, p)
	t.freeze = true
	t.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	return t


func _camera_for(t: Truck) -> ChaseCamera:
	var c := ChaseCamera.new()
	c.target = t
	add_child(c)
	# images pilotees par le test seulement (FRAMES_PER_TICK par tick)
	c.set_process(false)
	return c


func _test_tick(t: int) -> void:
	if t < 5:
		return
	var dt := 1.0 / (Engine.physics_ticks_per_second * FRAMES_PER_TICK)
	for k in FRAMES_PER_TICK:
		# A : recule vers le mur tant que la remorque (arriere a 16,1 m) n'y est pas
		if _a.global_position.z < 12.0:
			_a.global_position += Vector3(0.0, 0.0, STEP_M)
		_a_cam._process(dt)
		var cam_a := _a_cam.get_camera().global_position
		_a_worst = minf(_a_worst, WALL_Z - cam_a.z)
		# B : monte
		_b.global_position += Vector3(0.0, CLIMB_MS * dt, 0.0)
		_b_cam._process(dt)
		_b_worst = minf(_b_worst, _b_cam.global_position.y - _b.global_position.y)


func _test_finish() -> void:
	print("  INFO   A : camera au plus pres a %.2f m du mur ; B : pivot au plus bas a %.2f m au-dessus du camion"
		% [_a_worst, _b_worst])
	check_above("A 240 Hz : la camera reste hors du mur (m)", _a_worst, 0.2)
	check_above("B montee rapide : pivot au-dessus du camion (m)", _b_worst, MIN_FOCUS_ABOVE - 0.01)
