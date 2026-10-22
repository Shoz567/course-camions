extends PhysicsTest

## InputFrame (format 6 octets, groupement par 3), ScriptedInputSource,
## DeviceInputSource (isolation par device, zone morte, disposition Forza
## Horizon sur DualSense, fronts de reset, de klaxon et de cargo, camera et regard
## (stick droit, L1 derriere, 2026-10-20) hors InputFrame,
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
	var tn := InputFrame.new()
	tn.target_next = true
	var tg := InputFrame.from_bytes(tn.to_bytes())
	check("cible suivante : bit transporte, rien d'autre", tg.target_next and not tg.power_left
		and not tg.power_right and not tg.honk and tn.to_bytes().size() == 6)
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

	# Profil Forza Horizon, manette DualSense (boutons par POSITION)
	_send_axis(0, JOY_AXIS_TRIGGER_RIGHT, 0.0)
	_send_axis(0, JOY_AXIS_TRIGGER_LEFT, 0.6)
	var fb := _pad0.poll(5)
	check("L2 : freinage analogique, sans gaz", absf(fb.brake - 0.6) < 1e-6 and fb.throttle == 0.0,
		"brake=%.2f" % fb.brake)
	_send_axis(0, JOY_AXIS_TRIGGER_LEFT, 0.0)
	_send_axis(0, JOY_AXIS_TRIGGER_RIGHT, 1.0)
	var fr := _pad0.poll(6)
	check("R2 : plein gaz, sans drift", fr.throttle == 1.0 and not fr.handbrake)
	_send_axis(0, JOY_AXIS_TRIGGER_RIGHT, 0.0)
	# poll() rend toujours la meme InputFrame : lire avant le tick suivant
	var drift := []
	for b: JoyButton in [JOY_BUTTON_A, JOY_BUTTON_RIGHT_SHOULDER]:
		_send_button(0, b, true)
		drift.append(_pad0.poll(7).handbrake)
		_send_button(0, b, false)
	drift.append(_pad0.poll(7).handbrake)
	check("Croix ou R1 : frein a main (drift), relache : plus rien", drift == [true, true, false], str(drift))
	_send_button(0, JOY_BUTTON_X, true)
	check("Carre : nitro boost", _pad0.poll(8).boost)
	_send_button(0, JOY_BUTTON_X, false)
	_send_button(0, JOY_BUTTON_Y, true)
	var c1 := _pad0.poll(9).cargo
	var c2 := _pad0.poll(10).cargo
	_send_button(0, JOY_BUTTON_Y, false)
	check("Triangle : largage de remorque, un seul tick", c1 and not c2, "%s puis %s" % [c1, c2])
	_send_button(0, JOY_BUTTON_LEFT_STICK, true)
	var h1 := _pad0.poll(11).honk
	var h2 := _pad0.poll(12).honk
	_send_button(0, JOY_BUTTON_LEFT_STICK, false)
	check("L3 : klaxon, un seul tick", h1 and not h2, "%s puis %s" % [h1, h2])
	_send_button(0, JOY_BUTTON_LEFT_SHOULDER, true)
	var back := [_pad0.looking_back(), _pad0.poll(12).honk]
	_send_button(0, JOY_BUTTON_LEFT_SHOULDER, false)
	back.append(_pad0.looking_back())
	check("L1 tenu : regarder derriere (hors InputFrame), relache : fini", back == [true, false, false], str(back))
	var resets := 0
	for b: JoyButton in [JOY_BUTTON_BACK, JOY_BUTTON_TOUCHPAD]:
		_send_button(0, b, true)
		resets += 1 if _pad0.poll(13).reset else 0
		_send_button(0, b, false)
	check("Create, pave tactile : reset", resets == 2, "%d / 2" % resets)
	# Options ouvre le menu pause (LocalRace, 2026-10-22) : plus de reset
	_send_button(0, JOY_BUTTON_START, true)
	var opt := _pad0.poll(13).reset
	_send_button(0, JOY_BUTTON_START, false)
	check("Options : pas de reset (menu pause)", not opt)
	check("reset : vrai un seul tick", not _pad0.poll(14).reset)
	_send_button(0, JOY_BUTTON_B, true)
	var fo := _pad0.poll(15)
	_send_button(0, JOY_BUTTON_B, false)
	check("Rond : libre en course (aucune commande)", fo.throttle == 0.0 and fo.brake == 0.0
		and not fo.handbrake and not fo.boost and not fo.reset and not fo.honk and not fo.cargo)
	var toggles := [0]
	_pad0.camera_toggle_requested.connect(func() -> void: toggles[0] += 1)
	_send_button(0, JOY_BUTTON_RIGHT_STICK, true)
	var fc := _pad0.poll(17)
	_send_button(0, JOY_BUTTON_RIGHT_STICK, false)
	check("R3 : changement de camera, hors InputFrame",
		toggles[0] == 1 and not fc.reset and not fc.honk, "signaux=%d" % toggles[0])
	_send_axis(0, JOY_AXIS_RIGHT_X, 0.1)
	var dead := _pad0.look()
	_send_axis(0, JOY_AXIS_RIGHT_X, 1.0)
	_send_axis(0, JOY_AXIS_RIGHT_Y, -1.0)
	var full := _pad0.look()
	_send_axis(0, JOY_AXIS_RIGHT_X, 0.0)
	_send_axis(0, JOY_AXIS_RIGHT_Y, 0.0)
	check("stick droit : regard (zone morte, plein = 1), sans changer de vue", dead == Vector2.ZERO
		and absf(full.length() - 1.0) < 0.01 and full.x > 0.0 and full.y < 0.0 and toggles[0] == 1,
		"%s %s signaux=%d" % [dead, full, toggles[0]])
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
