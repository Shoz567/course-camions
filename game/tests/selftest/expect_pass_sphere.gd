extends PhysicsTest

## Auto-test du socle — doit donner PASS.
##
## Une sphere lachee de 1 m doit se poser sur le sol. Exerce les principales
## verifications du socle et la lecture de baseline.json, sans dependre d'un vehicule.

const RADIUS := 0.1
const DROP_HEIGHT := 1.0

var _ball: RigidBody3D
var _y0: float = 0.0


func _test_setup() -> void:
	duration_ticks = 90
	add_floor()

	_ball = RigidBody3D.new()
	_ball.mass = 1.0
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS
	shape.shape = sphere
	_ball.add_child(shape)
	_ball.position = Vector3(0.0, DROP_HEIGHT, 0.0)
	add_child(_ball)

	_y0 = _ball.position.y


func _test_finish() -> void:
	var y := _ball.global_position.y

	check_finite("position finie (pas de NaN)", _ball.global_position)
	# Jolt laisse les corps au repos s'enfoncer de `penetration_slop` (0,02 m par
	# defaut) : la sphere se pose a RADIUS - slop, pas a RADIUS. Premiere
	# version de ce test : 0,080 mesure contre 0,100 attendu. L'attente se
	# derive du reglage reel plutot que d'etre codee en dur.
	var slop: float = ProjectSettings.get_setting(
		"physics/jolt_physics_3d/simulation/penetration_slop", 0.0)
	check_near("sphere posee sur le sol", y, RADIUS - slop, 0.005)
	check_below("la sphere a chute", y, _y0)
	# Ratio volontairement lache : on verifie le helper, pas la physique.
	check_ratio_above("ratio calcule", y, _y0, 0.05)

	# Lecture de baseline.json. On compare la valeur de reference au reglage
	# REEL du moteur : si une mise a jour de Godot change le defaut de Jolt
	# (les roues d'un camion s'enfoncent de cette valeur), ce test le signale.
	var ref_slop: Variant = require_baseline("jolt_penetration_slop_m")
	if ref_slop != null:
		check_near("baseline.json lu et a jour (penetration_slop)", slop, float(ref_slop), 0.0001)

	# Diagnostic : rapport iterations / ticks, pour calibrer --quit-after.
	print("  INFO   iterations=%d ticks=%d" % [Engine.get_process_frames(), tick])
