extends PhysicsTest

## Regard de la camera (2026-10-20 : « bouger legerement la camera avec le
## joystick droit, pas une enorme amplitude d'angle ; L1 pour regarder
## derriere ») : camion fige face a -Z, camera de poursuite pilotee image par
## image, manette 0 simulee (evenements bruts) :
##   A. sans regard : la camera est derriere le camion et regarde vers -Z ;
##   B. stick droit a fond a droite : la vue tourne vers la droite d'au plus
##      look_yaw_max_deg (30 deg), stick a fond en haut : elle se releve d'au
##      plus look_pitch_max_deg ;
##   C. L1 tenu : la camera passe devant et regarde vers l'arriere (+Z) ;
##   D. L1 relache, stick au centre : de nouveau derriere, droit devant.

var _truck: Truck
var _cam: ChaseCamera
var _input: LocalInputSource
var _seen: Dictionary = {}


func _test_setup() -> void:
	duration_ticks = 200
	add_floor(400.0)
	_truck = TruckTestUtil.spawn_truck(self, Vector3.ZERO)
	_truck.freeze = true
	_truck.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_input = LocalInputSource.new()
	_input.device = 0
	_input.keyboard_layout = KeyboardInputSource.Layout.NONE
	add_child(_input)
	_cam = ChaseCamera.new()
	_cam.target = _truck
	_cam.look_source = _input
	add_child(_cam)
	_cam.set_process(false)


func _axis(axis: JoyAxis, v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = axis
	e.axis_value = v
	_input.pad._input(e)


func _button(b: JoyButton, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = b
	e.pressed = pressed
	_input.pad._input(e)


## Cap de la vue (deg, 0 = vers -Z, positif vers la droite) et inclinaison
## (deg, positive vers le bas).
func _gaze() -> Vector2:
	var f := -_cam.get_camera().global_basis.z
	return Vector2(rad_to_deg(atan2(f.x, -f.z)), rad_to_deg(asin(clampf(-f.y, -1.0, 1.0))))


func _test_tick(t: int) -> void:
	for k in 2:
		_cam._process(1.0 / 120.0)
	match t:
		20:
			_seen["rest"] = [_gaze(), _cam.get_camera().global_position.z]
			_axis(JOY_AXIS_RIGHT_X, 1.0)
		80:
			_seen["right"] = _gaze()
			_axis(JOY_AXIS_RIGHT_X, 0.0)
			_axis(JOY_AXIS_RIGHT_Y, -1.0)
		140:
			_seen["up"] = _gaze()
			_axis(JOY_AXIS_RIGHT_Y, 0.0)
			_button(JOY_BUTTON_LEFT_SHOULDER, true)
		142:
			_seen["back"] = [_gaze(), _cam.get_camera().global_position.z]
			_button(JOY_BUTTON_LEFT_SHOULDER, false)
		195:
			_seen["after"] = [_gaze(), _cam.get_camera().global_position.z]


func _test_finish() -> void:
	var rest: Array = _seen.get("rest", [Vector2(99, 99), -1.0])
	var g0 := rest[0] as Vector2
	check("A derriere, droit devant", absf(g0.x) < 1.0 and float(rest[1]) > 5.0, str(rest))
	var r := _seen.get("right", Vector2.ZERO) as Vector2
	check("B stick a droite : vue a droite, 30 deg au plus", r.x > 25.0 and r.x <= 30.5, "%.1f deg" % r.x)
	var u := _seen.get("up", Vector2.ZERO) as Vector2
	check("B stick en haut : vue relevee, 10 deg au plus", u.y < g0.y - 7.0 and u.y >= g0.y - 10.5,
		"%.1f -> %.1f deg" % [g0.y, u.y])
	var b: Array = _seen.get("back", [Vector2.ZERO, 1.0])
	check("C L1 : devant le camion, regarde vers l'arriere", absf(absf((b[0] as Vector2).x) - 180.0) < 5.0
		and float(b[1]) < -5.0, str(b))
	var a: Array = _seen.get("after", [Vector2(99, 99), -1.0])
	check("D relache : de nouveau derriere, droit devant", absf((a[0] as Vector2).x) < 1.5 and float(a[1]) > 5.0, str(a))
