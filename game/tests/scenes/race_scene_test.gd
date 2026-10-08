extends PhysicsTest

## Scene principale : course a 2 joueurs en ecran partage (dev/race_2p.tscn).
##   - 2 joueurs, 2 SubViewport, chaque camera suit SON camion ;
##   - J1 camion bleu, J2 camion rouge (chemins des modeles) ;
##   - depart cote a cote : meme abscisse, ecart lateral de la grille ;
##   - compte a rebours : personne ne bouge ; depart donne ensuite ;
##   - isolation des manettes (INPUT_SPEC §4, critere de la phase 4) : la
##     manette 1 fait avancer le camion 2 et lui seul ; son bouton camera ne
##     bascule que la vue du joueur 2.
## Les evenements manette passent par Input.parse_input_event : le vrai chemin.

var _scene: Node3D
var _p1: Truck
var _p2: Truck
var _moved_countdown: float = 0.0
var _started_at: int = -1
var _p1_start: Vector3
var _p2_start: Vector3
var _spray: int = -1
var _haze: float = -1.0


func _test_setup() -> void:
	duration_ticks = 440
	_scene = (load("res://dev/race_2p.tscn") as PackedScene).instantiate() as Node3D
	_scene.set("ready_gate", false)   # le sas READY a son propre test (race_ready_test)
	add_child(_scene)
	_spray = TruckWheelFx.spray
	_haze = ScreenFx.haze
	var players: Array = _scene.get("players")
	_p1 = players[0].truck
	_p2 = players[1].truck
	_p1_start = _p1.global_position
	_p2_start = _p2.global_position


func _send_button(device: int, button: JoyButton, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = button
	e.pressed = pressed
	Input.parse_input_event(e)


func _test_tick(t: int) -> void:
	if t < 170:
		_moved_countdown = maxf(_moved_countdown, maxf(_p1.linear_velocity.length(), _p2.linear_velocity.length()))
	var race: RaceLaps = _scene.get("race")
	if _started_at < 0 and race.is_started():
		_started_at = t
	# apres le depart : la manette 1 (device 1) accelere (R2) et bascule sa
	# camera (R3)
	# (220 ticks de gaz : ~40 m, loin du seuil de 20 m)
	if t == 200:
		_send_axis(1, JOY_AXIS_TRIGGER_RIGHT, 1.0)
	elif t == 420:
		_send_axis(1, JOY_AXIS_TRIGGER_RIGHT, 0.0)
		_send_button(1, JOY_BUTTON_RIGHT_STICK, true)
	elif t == 422:
		_send_button(1, JOY_BUTTON_RIGHT_STICK, false)


func _test_finish() -> void:
	var players: Array = _scene.get("players")
	check("2 joueurs, 2 vues", players.size() == 2 and players[0].viewport != null and players[1].viewport != null)
	var v1 := _p1.get_node("Visual") as TruckVisual
	var v2 := _p2.get_node("Visual") as TruckVisual
	check("Cyber City sous la pluie : trainees d'eau, pas de fumee de pneus ni de brume de chaleur",
		_spray == TruckWheelFx.Spray.WATER and not TruckWheelFx.tire_smoke(_spray) and _haze == 0.0, "spray=%d haze=%.1f" % [_spray, _haze])
	check("J1 bleu, J2 rouge", v1.external_model.ends_with("Camion_Bleu.glb") and v2.external_model.ends_with("Camion_Rouge.glb"),
		"%s / %s" % [v1.external_model.get_file(), v2.external_model.get_file()])
	var track: TrackBlockout = _scene.get("track")
	var i1 := track.closest_sample(_p1_start)
	var lateral := (_p2_start - _p1_start).dot(track.sample_right(i1))
	check("depart cote a cote : meme ligne", absf((_p2_start - _p1_start).dot(track.sample_forward(i1))) < 0.5)
	check_near("depart cote a cote : ecart lateral (m)", lateral,
		track.grid_lateral[1] - track.grid_lateral[0], 0.2)
	check_below("compte a rebours : personne ne bouge (m/s)", _moved_countdown, 0.5)
	check("depart donne apres le compte a rebours", _started_at >= 170 and _started_at <= 200, "tick=%d" % _started_at)
	var d1 := _p1.global_position.distance_to(_p1_start)
	var d2 := _p2.global_position.distance_to(_p2_start)
	check("manette 1 : le camion 2 avance", d2 > 20.0, "J2 %.1f m" % d2)
	check("manette 1 : le camion 1 ne bouge pas", d1 < 0.5, "J1 %.2f m" % d1)
	var c1: ChaseCamera = players[0].camera
	var c2: ChaseCamera = players[1].camera
	check("camera J2 en vue cabine, J1 reste en poursuite",
		c2.view == ChaseCamera.View.COCKPIT and c1.view == ChaseCamera.View.CHASE)
	check("chaque camera suit son camion", c1.target == _p1 and c2.target == _p2)
	check("les cameras sont dans des vues distinctes",
		c1.get_camera().get_viewport() != c2.get_camera().get_viewport())


func _send_axis(device: int, axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = device
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)
