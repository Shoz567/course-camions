extends PhysicsTest

## Reset (tache 1.7) : un camion retourne est remis sur ses roues par
## reset_to(), via state.transform, vitesses nulles dans le meme tick ; il se
## pose ensuite sur ses 4 roues.

const RESET_TICK := 60

var _truck: Truck
var _target := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.3, 0.0))
var _after_ok: bool = false
var _after_detail: String = ""


func _test_setup() -> void:
	duration_ticks = RESET_TICK + 180
	add_floor()
	_truck = TruckTestUtil.spawn_truck(self, Vector3(0.0, 4.0, 0.0), Vector3(0.0, 30.0, 180.0))
	_truck.angular_velocity = Vector3(1.0, 2.0, 0.5)


func _test_tick(t: int) -> void:
	if t == RESET_TICK:
		_truck.reset_to(_target)
	elif t == RESET_TICK + 1:
		var d := _truck.global_position.distance_to(_target.origin)
		var v := _truck.linear_velocity.length() + _truck.angular_velocity.length()
		_after_ok = d < 0.02 and v < 0.2 and _truck.global_transform.basis.y.y > 0.999
		_after_detail = "ecart=%.3f m vitesses=%.3f haut.y=%.4f" % [d, v, _truck.global_transform.basis.y.y]


func _test_finish() -> void:
	check("etat juste apres reset (1 tick)", _after_ok, _after_detail)
	check("4 roues au sol apres reset", _truck.wheels_on_ground() == 4, "n=%d" % _truck.wheels_on_ground())
	check_below("inclinaison finale (deg)", TruckTestUtil.tilt_deg(_truck), 1.0)
