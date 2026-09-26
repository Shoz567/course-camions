extends PhysicsTest

## Stabilite a l'arret et hauteur de caisse (CLAUDE.md §10) :
## pose 600 ticks sans input -> roulis et tangage < 1 deg, derive < 5 cm,
## hauteur de caisse = VEHICLE_SPEC +/- 3 cm, 4 roues au sol.

var _truck: Truck
var _start: Vector3
var _max_pitch: float = 0.0
var _max_roll: float = 0.0


func _test_setup() -> void:
	duration_ticks = 600
	add_floor()
	_truck = (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
	add_child(_truck)
	_start = _truck.global_position


func _test_tick(_t: int) -> void:
	var a := TruckTestUtil.pitch_roll_deg(_truck)
	_max_pitch = maxf(_max_pitch, absf(a.x))
	_max_roll = maxf(_max_roll, absf(a.y))


func _test_finish() -> void:
	var p := _truck.global_position
	check_finite("position finie", p)
	check_below("tangage max (deg)", _max_pitch, 1.0)
	check_below("roulis max (deg)", _max_roll, 1.0)
	check_below("derive horizontale (m)", Vector2(p.x - _start.x, p.z - _start.z).length(), 0.05)
	# L'origine est au sol quand le camion est au repos (VEHICLE_SPEC §1) :
	# bas du chassis a 0,75 m <=> origine a y = 0.
	check_near("hauteur de caisse : bas du chassis (m)",
		p.y + TruckSpec.CHASSIS_CENTER.y - TruckSpec.CHASSIS_SIZE.y / 2.0,
		TruckSpec.CHASSIS_CENTER.y - TruckSpec.CHASSIS_SIZE.y / 2.0, 0.03)
	check("4 roues au sol", _truck.wheels_on_ground() == 4, "n=%d" % _truck.wheels_on_ground())
	check_below("vitesse residuelle (m/s)", _truck.linear_velocity.length(), 0.01)
