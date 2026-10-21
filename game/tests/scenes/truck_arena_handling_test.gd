extends PhysicsTest

## Maniabilite en arene (2026-10-21 : « augmenter la maniabilité des camions :
## moins glisser, accélérer plus vite, réagir plus vite, tourner plus serré ») :
## deux camions (remorque attelee) sur un sol plat, reglage 100cc, l'un en
## reglage de course, l'autre en VehicleTuning.for_arena() :
##   A. 0 -> 60 km/h : au moins 20 % plus court ;
##   B. braquage a fond a 50 km/h (regule) : quart de tour au moins 15 % plus
##      vite ;
##   C. rayon de virage en regime (1,5 s apres) au moins 15 % plus court ;
##   D. il glisse moins : acceleration laterale tenue en regime (v^2 / R) au
##      moins 15 % plus forte (la derive au centre du camion grandit d'elle-
##      meme quand le virage se resserre : elle ne mesure pas l'adherence).

const CRUISE_KMH := 50.0

var _trucks: Array[Truck] = []
var _frames: Array[InputFrame] = [InputFrame.new(), InputFrame.new()]
var _phase := [0, 0]
var _t_phase := [0, 0]
var _accel := [0, 0]
var _quarter := [0, 0]
var _yaw0 := [0.0, 0.0]
var _radius := [0.0, 0.0]
var _lat_g := [0.0, 0.0]


func _test_setup() -> void:
	duration_ticks = 900
	add_floor(4000.0)
	var base := (load("res://vehicles/default_vehicle.tres") as VehicleTuning)
	var normal := GameStateNode.speed_tuning(base, GameStateNode.SpeedClass.NORMAL)
	for k in 2:
		var t := (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
		t.tuning = normal if k == 0 else normal.for_arena()
		t.position = Vector3(-400.0 + 800.0 * k, 0.0, 0.0)
		add_child(t)
		_trucks.append(t)


func _test_tick(t: int) -> void:
	for k in 2:
		var tr := _trucks[k]
		var f := _frames[k]
		f.tick = t
		var v := tr.linear_velocity.length()
		var dt := t - int(_t_phase[k])
		match int(_phase[k]):
			0:
				# depart arrete : plein gaz jusqu'a 60 km/h
				f.throttle = 1.0 if t > 20 else 0.0
				f.steer = 0.0
				if v * 3.6 >= 60.0:
					_accel[k] = t - 20
					_phase[k] = 1
					_t_phase[k] = t
			1:
				# regule a 50 km/h, tout droit
				f.throttle = clampf((CRUISE_KMH / 3.6 - v) * 0.6, 0.0, 1.0)
				f.brake = clampf((v - CRUISE_KMH / 3.6 - 0.5) * 0.4, 0.0, 1.0)
				if dt >= 90:
					_phase[k] = 2
					_t_phase[k] = t
					_yaw0[k] = tr.global_rotation.y
			2:
				# braquage a fond, regule
				f.steer = 1.0
				f.throttle = clampf((CRUISE_KMH / 3.6 - v) * 0.6, 0.0, 1.0)
				f.brake = 0.0
				var turned := absf(wrapf(tr.global_rotation.y - float(_yaw0[k]), -PI, PI))
				if int(_quarter[k]) == 0 and turned >= PI / 2.0:
					_quarter[k] = dt
				var vel := tr.linear_velocity
				vel.y = 0.0
				if dt == 90:
					var w := absf(tr.angular_velocity.y)
					_radius[k] = vel.length() / maxf(w, 1e-3)
					_lat_g[k] = vel.length() * w / TruckSpec.GRAVITY
				if dt > 240:
					_phase[k] = 3
		tr.set_input(f)


func _test_finish() -> void:
	print("  INFO   0-60 : %s ticks ; quart de tour : %s ticks ; rayon : %.1f / %.1f m ; lateral : %.2f / %.2f g" % [
		_accel, _quarter, _radius[0], _radius[1], _lat_g[0], _lat_g[1]])
	check_ratio_above("A 0 -> 60 km/h (course / arene)", float(_accel[0]), maxf(float(_accel[1]), 1.0), 1.2)
	check_ratio_above("B quart de tour a 50 km/h (course / arene)", float(_quarter[0]), maxf(float(_quarter[1]), 1.0), 1.15)
	check_ratio_above("C rayon de virage (course / arene)", float(_radius[0]), maxf(float(_radius[1]), 0.1), 1.15)
	check_ratio_above("D acceleration laterale tenue (arene / course)", float(_lat_g[1]), maxf(float(_lat_g[0]), 0.01), 1.15)
