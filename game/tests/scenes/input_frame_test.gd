extends PhysicsTest

## InputFrame (format 6 octets, groupement par 3), ScriptedInputSource,
## DeviceInputSource (isolation par device, zone morte, front de reset,
## debranchement). docs/INPUT_SPEC.md.

var _pad0: DeviceInputSource
var _pad1: DeviceInputSource


func _test_setup() -> void:
	duration_ticks = 1
	_pad0 = DeviceInputSource.new()
	_pad0.device_id = 0
	_pad1 = DeviceInputSource.new()
	_pad1.device_id = 1
	add_child(_pad0)
	add_child(_pad1)


func _test_finish() -> void:
	_test_bytes()
	_test_scripted()
	_test_device()


func _test_bytes() -> void:
	var f := InputFrame.new()
	f.tick = 70000
	f.steer = -0.5
	f.throttle = 0.3
	f.brake = 1.0
	f.handbrake = true
	f.reset = true
	var b := f.to_bytes()
	check("taille d'une frame", b.size() == InputFrame.SIZE, "octets=%d" % b.size())
	var g := InputFrame.from_bytes(b)
	check("tick modulo 65536", g.tick == 70000 % 65536, "tick=%d" % g.tick)
	check_near("steer quantifie", g.steer, -0.5, 1.0 / 127.0)
	check_near("throttle quantifie", g.throttle, 0.3, 1.0 / 255.0)
	check_near("brake quantifie", g.brake, 1.0, 1.0 / 255.0)
	check("bits handbrake/boost/reset", g.handbrake and not g.boost and g.reset)

	f.steer = 3.0
	check_near("steer borne a 1", InputFrame.from_bytes(f.to_bytes()).steer, 1.0, 1e-6)

	# Phase 6 : 3 frames consecutives dans un paquet de 18 octets.
	var packet := PackedByteArray()
	packet.resize(InputFrame.SIZE * 3)
	for i in 3:
		var fi := InputFrame.new()
		fi.tick = 100 + i
		fi.throttle = i / 2.0
		fi.write_to(packet, i * InputFrame.SIZE)
	var back := InputFrame.new()
	back.read_from(packet, 2 * InputFrame.SIZE)
	check("groupement par 3 : 3e frame relue", back.tick == 102 and absf(back.throttle - 1.0) < 0.01,
		"tick=%d throttle=%.3f" % [back.tick, back.throttle])


func _test_scripted() -> void:
	var src := ScriptedInputSource.new()
	src.push_hold(&"throttle", 1.0, 3)
	src.push_hold(&"steer", 0.0, 1)
	src.push_hold(&"steer", 0.5, 2)
	src.push_once(&"reset")
	check("duree du script (ticks)", src.length_ticks() == 3, "n=%d" % src.length_ticks())
	var seen := PackedStringArray()
	for t in 4:
		var f := src.poll(t)
		seen.append("%.1f/%.1f/%s" % [f.throttle, f.steer, f.reset])
	var expected := PackedStringArray(["1.0/0.0/true", "1.0/0.5/false", "1.0/0.5/false", "0.0/0.0/false"])
	check("lignes de temps paralleles par champ", seen == expected, "obtenu=%s" % [seen])
	check("script termine", src.is_finished())
	src.free()


func _test_device() -> void:
	_send_axis(1, JOY_AXIS_LEFT_X, 1.0)
	_send_axis(1, JOY_AXIS_TRIGGER_RIGHT, 1.0)
	var f0 := _pad0.poll(1)
	check("device 1 n'affecte pas la source du device 0",
		f0.steer == 0.0 and f0.throttle == 0.0, "steer=%.2f throttle=%.2f" % [f0.steer, f0.throttle])
	check_near("device 1 : plein braquage", _pad1.poll(1).steer, 1.0, 1e-6)

	_send_axis(0, JOY_AXIS_LEFT_X, 0.08)
	check_near("zone morte axiale 0,10", _pad0.poll(2).steer, 0.0, 1e-6)
	_send_axis(0, JOY_AXIS_LEFT_X, -0.55)
	var s := _pad0.poll(3).steer
	check("courbe de reponse : signe et attenuation", s < 0.0 and absf(s) < 0.5, "steer=%.3f" % s)
	_send_axis(0, JOY_AXIS_TRIGGER_RIGHT, 0.5)
	check_near("gachette analogique : demi-gaz", _pad0.poll(4).throttle, 0.5, 1e-6)

	var press := InputEventJoypadButton.new()
	press.device = 0
	press.button_index = JOY_BUTTON_Y
	press.pressed = true
	_pad0._input(press)
	var r1 := _pad0.poll(5).reset
	var r2 := _pad0.poll(6).reset
	check("reset : vrai un seul tick", r1 and not r2, "%s puis %s" % [r1, r2])

	_pad0._on_joy_connection_changed(0, false)
	var fd := _pad0.poll(7)
	check("manette debranchee : neutre", fd.throttle == 0.0 and fd.steer == 0.0 and not _pad0.connected)


func _send_axis(device: int, axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = device
	e.axis = axis
	e.axis_value = value
	_pad0._input(e)
	_pad1._input(e)
