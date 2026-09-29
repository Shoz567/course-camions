extends PhysicsTest

## InputFrame (format 6 octets, groupement par 3), ScriptedInputSource,
## DeviceInputSource (isolation par device, zone morte, schema de boutons style
## Mario Kart, fronts de reset, de klaxon et de cargo, camera hors InputFrame,
## debranchement), KeyboardInputSource (touches de cargo par jeu de touches).
## docs/INPUT_SPEC.md.

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
	f.honk = true
	f.cargo = true
	var b := f.to_bytes()
	check("taille d'une frame", b.size() == InputFrame.SIZE, "octets=%d" % b.size())
	var g := InputFrame.from_bytes(b)
	check("tick modulo 65536", g.tick == 70000 % 65536, "tick=%d" % g.tick)
	check_near("steer quantifie", g.steer, -0.5, 1.0 / 127.0)
	check_near("throttle quantifie", g.throttle, 0.3, 1.0 / 255.0)
	check_near("brake quantifie", g.brake, 1.0, 1.0 / 255.0)
	check("bits handbrake/boost/reset/klaxon/cargo",
		g.handbrake and not g.boost and g.reset and g.honk and g.cargo)
	var c := InputFrame.new()
	c.copy_from(g)
	check("copie : cargo recopie", c.cargo)
	c.clear()
	check("neutre : plus de cargo", not c.cargo)

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

	# Profil Mario Kart 8 Deluxe (disposition Switch, boutons par POSITION)
	_send_button(0, JOY_BUTTON_BACK, true)
	var r1 := _pad0.poll(5).reset
	var r2 := _pad0.poll(6).reset
	check("reset (-) : vrai un seul tick", r1 and not r2, "%s puis %s" % [r1, r2])
	_send_button(0, JOY_BUTTON_BACK, false)
	_send_axis(0, JOY_AXIS_TRIGGER_LEFT, 1.0)
	# poll() rend toujours la meme InputFrame : lire avant le tick suivant
	var z1 := _pad0.poll(7)
	var c1 := z1.cargo
	var h1 := z1.honk
	var c2 := _pad0.poll(8).cargo
	check("cargo (ZL) : vrai un seul tick, sans klaxon", c1 and not c2 and not h1,
		"%s puis %s" % [c1, c2])
	_send_axis(0, JOY_AXIS_TRIGGER_LEFT, 0.0)
	check("ZL ne freine pas (profil MK8)", _pad0.poll(8).brake == 0.0)
	_send_axis(0, JOY_AXIS_TRIGGER_LEFT, 1.0)
	check("ZL maintenu puis rappuye : un seul largage par appui", _pad0.poll(8).cargo)
	_send_axis(0, JOY_AXIS_TRIGGER_LEFT, 0.8)
	check("ZL maintenu : pas de second largage", not _pad0.poll(8).cargo)
	_send_axis(0, JOY_AXIS_TRIGGER_LEFT, 0.0)
	var honks := 0
	for d: JoyButton in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]:
		_send_button(0, d, true)
		var fh := _pad0.poll(8)
		honks += 1 if (fh.honk and not fh.cargo) else 0
		_send_button(0, d, false)
	check("klaxon : chaque direction de la croix", honks == 4, "%d / 4" % honks)
	check("klaxon : vrai un seul tick", not _pad0.poll(8).honk)
	_send_axis(0, JOY_AXIS_TRIGGER_RIGHT, 0.0)
	_send_button(0, JOY_BUTTON_B, true)
	var fa := _pad0.poll(9)
	check("A Switch (droite) : plein gaz, pas de drift", fa.throttle == 1.0 and not fa.handbrake)
	_send_axis(0, JOY_AXIS_TRIGGER_RIGHT, 1.0)
	var fd := _pad0.poll(10)
	check("A + ZR : plein gaz ET drift", fd.throttle == 1.0 and fd.handbrake)
	_send_axis(0, JOY_AXIS_TRIGGER_RIGHT, 0.0)
	_send_button(0, JOY_BUTTON_X, true)
	_send_button(0, JOY_BUTTON_B, false)
	check("Y Switch (gauche) accelere aussi, A et Y cumules", _pad0.poll(11).throttle == 1.0)
	_send_button(0, JOY_BUTTON_X, false)
	check("A et Y relaches : plus de gaz", _pad0.poll(12).throttle == 0.0)
	_send_axis(0, JOY_AXIS_TRIGGER_RIGHT, 0.7)
	var fr := _pad0.poll(13)
	check("ZR seul : accelerateur analogique, pas de drift",
		absf(fr.throttle - 0.7) < 1e-6 and not fr.handbrake, "throttle=%.2f" % fr.throttle)
	_send_axis(0, JOY_AXIS_TRIGGER_RIGHT, 0.0)
	_send_button(0, JOY_BUTTON_RIGHT_SHOULDER, true)
	check("R : drift", _pad0.poll(14).handbrake)
	_send_button(0, JOY_BUTTON_RIGHT_SHOULDER, false)
	_send_button(0, JOY_BUTTON_A, true)
	check("B Switch (bas) : freiner / reculer", _pad0.poll(15).brake == 1.0)
	_send_button(0, JOY_BUTTON_A, false)
	_send_button(0, JOY_BUTTON_LEFT_SHOULDER, true)
	check("L : boost", _pad0.poll(16).boost)
	_send_button(0, JOY_BUTTON_LEFT_SHOULDER, false)
	var toggles := [0]
	_pad0.camera_toggle_requested.connect(func() -> void: toggles[0] += 1)
	_send_button(0, JOY_BUTTON_Y, true)
	var fc := _pad0.poll(17)
	check("X Switch (haut) : changement de camera, hors InputFrame",
		toggles[0] == 1 and not fc.reset and not fc.honk, "signaux=%d" % toggles[0])
	_pad0._on_joy_connection_changed(0, false)
	var fu := _pad0.poll(18)
	check("manette debranchee : neutre", fu.throttle == 0.0 and fu.steer == 0.0 and not _pad0.connected)
	_test_keyboard_cargo()


## Cargo au clavier : E (ZQSD), ; en AZERTY (FLECHES), aucun pour AUCUN.
func _test_keyboard_cargo() -> void:
	var got := []
	for pair: Array in [[KeyboardInputSource.Layout.ZQSD, KEY_E], [KeyboardInputSource.Layout.ARROWS, KEY_COMMA],
			[KeyboardInputSource.Layout.ZQSD, KEY_COMMA], [KeyboardInputSource.Layout.NONE, KEY_E]]:
		var kb := KeyboardInputSource.new()
		kb.layout = pair[0]
		var e := InputEventKey.new()
		e.physical_keycode = pair[1]
		e.pressed = true
		kb._input(e)
		got.append(kb.poll(1).cargo)
		got.append(kb.poll(2).cargo)
		kb.free()
	check("clavier : E (ZQSD) et ; (FLECHES) larguent, un seul tick ; rien ailleurs",
		got == [true, false, true, false, false, false, false, false], str(got))


func _send_button(device: int, button: JoyButton, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = button
	e.pressed = pressed
	_pad0._input(e)
	_pad1._input(e)


func _send_axis(device: int, axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = device
	e.axis = axis
	e.axis_value = value
	_pad0._input(e)
	_pad1._input(e)
