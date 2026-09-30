extends PhysicsTest

## Course a 6 joueurs lancee comme par le menu (GameState.requested_players,
## dev/race.tscn) :
##   - grille 3 x 2 (GridContainer, 3 colonnes), 6 SubViewport distincts, pas
##     de camera TV, HUD a l'echelle 0,5 ;
##   - J5 VIOLET NEO-TOKYO et J6 ORANGE CARBO : modele existant + livree
##     (violet pour J5, orange pour J6), manettes 4 et 5, pas de clavier ;
##   - depart : J5 et J6 au 2e rang, 20 m derriere, en quinconce (couloirs
##     libres entre ceux du 1er rang), personne ne se chevauche ;
##   - isolation (INPUT_SPEC §4) : la manette 5 fait avancer J6 et lui seul ;
##   - livree : TruckVisual.apply_livery repeint les surfaces dont le materiau
##     porte le bon prefixe, sans toucher au materiau d'origine.

const LocalRace := preload("res://dev/local_race.gd")

var _scene: Node3D
var _players: Array = []
var _starts: Array[Vector3] = []
var _max_tilt: float = 0.0


func _test_setup() -> void:
	duration_ticks = 400
	GameState.requested_players = 6
	_scene = (load("res://dev/race.tscn") as PackedScene).instantiate() as Node3D
	add_child(_scene)
	_players = _scene.get("players")
	for p: Object in _players:
		_starts.append((p.get("truck") as Truck).global_position)


func _axis(device: int, axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = device
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)


func _truck(i: int) -> Truck:
	return _players[i].truck


func _test_tick(t: int) -> void:
	# depart au tick ~180 : manette 5 plein gaz pendant 200 ticks
	if t == 195:
		_axis(5, JOY_AXIS_TRIGGER_RIGHT, 1.0)
	elif t == 395:
		_axis(5, JOY_AXIS_TRIGGER_RIGHT, 0.0)
	for i in _players.size():
		_max_tilt = maxf(_max_tilt, TruckTestUtil.tilt_deg(_truck(i)))


func _test_finish() -> void:
	check("6 joueurs", _players.size() == 6, "%d" % _players.size())
	var split := _scene.get("split") as GridContainer
	check("grille 3 x 2 (GridContainer, 3 colonnes, 6 cases)",
		split != null and split.columns == 3 and split.get_child_count() == 6)
	var vps := {}
	for p: Object in _players:
		var vp := (p.get("camera") as ChaseCamera).get_camera().get_viewport() as SubViewport
		if vp != null and vp == p.get("viewport"):
			vps[vp] = true
	check("6 SubViewport distincts, chaque camera dans sa vue", vps.size() == 6, "%d" % vps.size())
	check("pas de camera TV a 6 joueurs", _scene.get("leader_camera") == null)
	var env := (_scene.get_node("WorldEnvironment") as WorldEnvironment).environment
	check("6 vues : MSAA 2x par vue, occlusion seule (ni reflets ni eclairage indirect)",
		(_players[5].viewport as SubViewport).msaa_3d == Viewport.MSAA_2X
		and env.ssao_enabled and not env.ssr_enabled and not env.ssil_enabled)
	check_near("HUD a l'echelle 0,5", (_players[5].hud as RaceHud).ui_scale, 0.5, 0.001)

	check("J5 VIOLET NÉO-TOKYO, J6 ORANGE CARBO",
		(_players[4].hud as RaceHud).player_label == "J5 VIOLET NÉO-TOKYO"
		and (_players[5].hud as RaceHud).player_label == "J6 ORANGE CARBO")
	var v5 := _truck(4).get_node("Visual") as TruckVisual
	var v6 := _truck(5).get_node("Visual") as TruckVisual
	var paint5: Color = v5.livery.get("Peinture_Cabine", {}).get("albedo", Color.BLACK)
	var paint6: Color = v6.livery.get("Peinture_Cabine", {}).get("albedo", Color.BLACK)
	check("J5 : livree violette (cabine)", paint5.b > paint5.r and paint5.r > paint5.g, str(paint5))
	check("J6 : livree orange (cabine)", paint6.r > paint6.g and paint6.g > paint6.b, str(paint6))
	check("J6 : jantes cuivrees, carbone mat",
		v6.livery.has("Jante") and float(v6.livery["Carbone"]["roughness"]) > 0.7)
	check("J1 a J4 : modeles d'origine, sans livree",
		(_truck(0).get_node("Visual") as TruckVisual).livery.is_empty()
		and (_truck(3).get_node("Visual") as TruckVisual).livery.is_empty())
	check("couleurs de repli : J5 violet, J6 orange",
		v5.mock_tint.b > v5.mock_tint.g and v6.mock_tint.r > v6.mock_tint.b)

	var inputs_ok := true
	for i in 6:
		var input := _players[i].input as LocalInputSource
		inputs_ok = inputs_ok and input.device == i
		if i >= 2:
			inputs_ok = inputs_ok and input.keyboard_layout == KeyboardInputSource.Layout.NONE
	check("manettes 0 a 5 ; pas de clavier au-dela de J2", inputs_ok)

	var track: TrackBlockout = _scene.get("track")
	var i0 := track.closest_sample(_starts[0])
	var fwd := track.sample_forward(i0)
	var right := track.sample_right(i0)
	var o := track.sample_position(i0)
	check_near("depart : J5 au 2e rang, derriere J1 (m)", (_starts[4] - _starts[0]).dot(fwd),
		-track.grid_row_spacing, 0.5)
	check_near("depart : J6 au 2e rang, derriere J2 (m)", (_starts[5] - _starts[1]).dot(fwd),
		-track.grid_row_spacing, 0.5)
	var lat5 := (_starts[4] - o).dot(right)
	var lat6 := (_starts[5] - o).dot(right)
	check("depart : J5 et J6 en quinconce (couloirs du 2e rang)",
		absf(lat5 - track.grid_back_lateral[0]) < 0.3 and absf(lat6 - track.grid_back_lateral[1]) < 0.3,
		"%.1f / %.1f m" % [lat5, lat6])
	# voie libre devant eux : aucun camion du 1er rang a moins de 8 m de leur axe
	var lane := INF
	for i in 4:
		var lat := (_starts[i] - o).dot(right)
		lane = minf(lane, minf(absf(lat - lat5), absf(lat - lat6)))
	check_above("depart : voie libre devant le 2e rang (m de l'axe)", lane, 8.0)
	var closest := INF
	for a in 6:
		for b in range(a + 1, 6):
			closest = minf(closest, _starts[a].distance_to(_starts[b]))
	check_above("depart : ecart minimal entre deux camions (m)", closest, 15.0)

	var d := []
	for i in 6:
		d.append(_truck(i).global_position.distance_to(_starts[i]))
	check("manette 5 : J6 avance", d[5] > 15.0, "J6 %.1f m" % d[5])
	var others := 0.0
	for i in 5:
		others = maxf(others, d[i])
	check_below("les 5 autres ne bougent pas (m)", others, 0.5)
	check_below("personne ne se couche (deg)", _max_tilt, 45.0)

	_check_livery()


## Livree sur un faux modele : deux surfaces, une seule a repeindre.
func _check_livery() -> void:
	var root := Node3D.new()
	var paint_src := StandardMaterial3D.new()
	paint_src.resource_name = "Peinture_Cabine_Bleu"
	paint_src.albedo_color = Color(0.15, 0.35, 0.68)
	var tyre_src := StandardMaterial3D.new()
	tyre_src.resource_name = "Pneu"
	for m: StandardMaterial3D in [paint_src, tyre_src]:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.material = m
		mi.mesh = box
		mi.name = m.resource_name
		root.add_child(mi)
	var livery: Dictionary = LocalRace.LIVERIES[4]
	var painted := TruckVisual.apply_livery(root, livery)
	var cab := root.get_node("Peinture_Cabine_Bleu") as MeshInstance3D
	var over := cab.get_surface_override_material(0) as StandardMaterial3D
	check("livree : 1 surface repeinte sur 2", painted == 1, "%d" % painted)
	check("livree : cabine violette, brillante, vernie", over != null
		and over.albedo_color == livery["Peinture_Cabine"]["albedo"] and over.clearcoat_enabled
		and over.roughness < 0.2)
	check("livree : materiau d'origine intact", paint_src.albedo_color == Color(0.15, 0.35, 0.68))
	check("livree : pneus inchanges",
		(root.get_node("Pneu") as MeshInstance3D).get_surface_override_material(0) == null)
	root.free()
