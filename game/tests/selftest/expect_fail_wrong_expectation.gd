extends PhysicsTest

## Auto-test du socle — doit donner FAIL.
##
## Meme sphere que expect_pass_sphere, mais on affirme qu'elle flotte encore a
## 1 m. Si ce test passait, le socle ne detecterait pas un echec reel.

var _ball: RigidBody3D


func _test_setup() -> void:
	duration_ticks = 90
	add_floor()
	_ball = RigidBody3D.new()
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.1
	shape.shape = sphere
	_ball.add_child(shape)
	_ball.position = Vector3(0.0, 1.0, 0.0)
	add_child(_ball)


func _test_finish() -> void:
	check_near("affirmation fausse : la sphere flotte", _ball.global_position.y, 1.0, 0.01)
