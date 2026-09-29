extends PhysicsTest

## Course a 4 joueurs lancee comme par le menu (GameState.requested_players,
## dev/race.tscn) :
##   - grille 2 x 2 (GridContainer), 4 SubViewport distincts, HUD reduit ;
##   - J1 bleu, J2 rouge, J3 jaune SOLEIL, J4 vert ; manettes 0 a 3 ;
##     clavier : fleches J1, ZQSD J2, aucun pour J3 / J4 ;
##   - depart : 4 camions sur la meme ligne, etales sur la largeur ;
##   - isolation (INPUT_SPEC §4) : la manette 3 fait avancer J4 et lui seul,
##     ZQSD fait avancer J2 et lui seul (pas J3, qui n'a pas de clavier) ; le
##     bouton camera de la manette 2 ne bascule que la vue de J3.

var _scene: Node3D
var _players: Array = []
var _starts: Array[Vector3] = []


func _test_setup() -> void:
	duration_ticks = 420
	GameState.requested_players = 4
	_scene = (load("res://dev/race.tscn") as PackedScene).instantiate() as Node3D
	add_child(_scene)
	_players = _scene.get("players")
	for p: Object in _players:
		_starts.append((p.get("truck") as Truck).global_position)


func _pad(device: int, button: JoyButton, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = button
	e.pressed = pressed
	Input.parse_input_event(e)


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func _test_tick(t: int) -> void:
	# depart au tick ~180 : manette 3 (A Switch) et Z de ZQSD pendant 200 ticks
	if t == 200:
		_pad(3, JOY_BUTTON_B, true)
		_key(KEY_W, true)
	elif t == 400:
		_pad(3, JOY_BUTTON_B, false)
		_key(KEY_W, false)
		_pad(2, JOY_BUTTON_Y, true)
	elif t == 402:
		_pad(2, JOY_BUTTON_Y, false)


func _truck(i: int) -> Truck:
	return _players[i].truck


func _test_finish() -> void:
	check("4 joueurs", _players.size() == 4, "%d" % _players.size())
	var split := _scene.get("split") as GridContainer
	check("grille 2 x 2 (GridContainer, 2 colonnes, 4 cases)",
		split != null and split.columns == 2 and split.get_child_count() == 4)
	var vps := {}
	for p: Object in _players:
		var vp := p.get("viewport") as SubViewport
		if vp != null:
			vps[vp] = true
	check("4 SubViewport distincts", vps.size() == 4, "%d" % vps.size())
	var cams := {}
	for p: Object in _players:
		cams[(p.get("camera") as ChaseCamera).get_camera().get_viewport()] = true
	check("chaque camera dans sa vue", cams.size() == 4)
	check_near("HUD reduit dans la grille", (_players[3].hud as RaceHud).ui_scale, 0.6, 0.001)

	var colors := ["Bleu", "Rouge", "Jaune", "Vert"]
	var models_ok := true
	for i in 4:
		var v := _truck(i).get_node("Visual") as TruckVisual
		models_ok = models_ok and v.external_model.ends_with("Camion_%s.glb" % colors[i])
	check("J1 bleu, J2 rouge, J3 jaune, J4 vert", models_ok)
	check("J3 SOLEIL", (_players[2].hud as RaceHud).player_label == "J3 SOLEIL")

	var inputs_ok := true
	var layouts := [KeyboardInputSource.Layout.ARROWS, KeyboardInputSource.Layout.ZQSD,
		KeyboardInputSource.Layout.NONE, KeyboardInputSource.Layout.NONE]
	for i in 4:
		var input := _players[i].input as LocalInputSource
		inputs_ok = inputs_ok and input.device == i and input.keyboard_layout == layouts[i]
	check("manettes 0 a 3 ; clavier fleches, ZQSD, aucun, aucun", inputs_ok)

	var track: TrackBlockout = _scene.get("track")
	var i0 := track.closest_sample(_starts[0])
	var fwd := track.sample_forward(i0)
	var right := track.sample_right(i0)
	var o := track.sample_position(i0)
	var line_ok := true
	var lateral_ok := true
	for i in 4:
		line_ok = line_ok and absf((_starts[i] - _starts[0]).dot(fwd)) < 0.5
		lateral_ok = lateral_ok and absf((_starts[i] - o).dot(right) - track.grid_lateral[i]) < 0.3
	check("depart : les 4 sur la meme ligne", line_ok)
	check("depart : etales sur la largeur (grille laterale)", lateral_ok, str(track.grid_lateral))
	var spread := absf((_starts[3] - _starts[2]).dot(right))
	check_above("depart : ecart entre les camions exterieurs (m)", spread, 30.0)
	check_below("depart : camions exterieurs loin des murs (m du centre)",
		maxf(absf(track.grid_lateral[2]), absf(track.grid_lateral[3])), track.width / 2.0 - 4.0)

	var d := []
	for i in 4:
		d.append(_truck(i).global_position.distance_to(_starts[i]))
	check("manette 3 : J4 avance", d[3] > 15.0, "J4 %.1f m" % d[3])
	check("ZQSD : J2 avance", d[1] > 15.0, "J2 %.1f m" % d[1])
	check("J1 et J3 ne bougent pas", d[0] < 0.5 and d[2] < 0.5, "J1 %.2f m, J3 %.2f m" % [d[0], d[2]])
	var views := []
	for p: Object in _players:
		views.append((p.get("camera") as ChaseCamera).view)
	check("manette 2 : seule la camera de J3 passe en cabine",
		views == [ChaseCamera.View.CHASE, ChaseCamera.View.CHASE, ChaseCamera.View.COCKPIT, ChaseCamera.View.CHASE],
		str(views))
