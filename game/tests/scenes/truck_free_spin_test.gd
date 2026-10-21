extends PhysicsTest

## Demi-tour libre en arene (2026-10-21 : « retirer la limitation de drift
## dans l'arène pour pouvoir se retourner plus vite ») : deux camions a
## 60 km/h, frein a main et plein braquage pendant 2 s :
##   A. camion de course (garde anti tete-a-queue) : la derive reste sous
##      drift_max_slip_deg + 15 deg ;
##   B. camion d'arene (free_spin) : la derive depasse 100 deg, il se
##      retourne ; il tourne plus de cap que l'autre.

var _race: Truck
var _arena: Truck
var _slip := [0.0, 0.0]
var _yaw0 := [0.0, 0.0]
var _turn := [0.0, 0.0]
var _frame := InputFrame.new()


func _test_setup() -> void:
	duration_ticks = 200
	add_floor(2000.0)
	_race = TruckTestUtil.spawn_truck(self, Vector3(-200.0, 0.0, 0.0))
	_arena = TruckTestUtil.spawn_truck(self, Vector3(200.0, 0.0, 0.0))
	_arena.free_spin = true


func _test_tick(t: int) -> void:
	var trucks := [_race, _arena]
	if t == 30:
		for k in 2:
			var tr0 := trucks[k] as Truck
			tr0.linear_velocity = -tr0.global_basis.z * 16.7
			_yaw0[k] = tr0.global_rotation.y
	_frame.tick = t
	_frame.throttle = 0.4 if t >= 30 else 0.0
	_frame.handbrake = t >= 32 and t < 152
	_frame.steer = 1.0 if t >= 32 and t < 152 else 0.0
	for k in 2:
		var tr := trucks[k] as Truck
		tr.set_input(_frame)
		if t >= 32 and t < 160:
			var v := tr.linear_velocity
			v.y = 0.0
			if v.length() > 3.0:
				var f := -tr.global_basis.z
				f.y = 0.0
				_slip[k] = maxf(_slip[k], rad_to_deg(absf(f.signed_angle_to(v, Vector3.UP))))
			_turn[k] = maxf(_turn[k], rad_to_deg(absf(wrapf(tr.global_rotation.y - _yaw0[k], -PI, PI))))


func _test_finish() -> void:
	var max_slip := _race.tuning.drift_max_slip_deg
	check_below("A course : derive max (deg)", float(_slip[0]), max_slip + 15.0)
	check_above("B arene : derive max (deg)", float(_slip[1]), 100.0)
	check("B arene : tourne plus de cap", float(_turn[1]) > float(_turn[0]), "%.0f / %.0f deg" % [_turn[1], _turn[0]])
