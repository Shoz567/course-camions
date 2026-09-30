extends PhysicsTest

## Course a 5 joueurs (dev/race.tscn, choix du menu) : grille 3 x 2 dont la 6e
## case montre le camion en tete (camera TV, comme a 3 joueurs). La manette 4
## fait avancer J5 : il passe en tete, la camera TV le suit et l'annonce.

var _scene: Node3D
var _players: Array = []


func _test_setup() -> void:
	duration_ticks = 440
	GameState.requested_players = 5
	_scene = (load("res://dev/race.tscn") as PackedScene).instantiate() as Node3D
	add_child(_scene)
	_players = _scene.get("players")


func _test_tick(t: int) -> void:
	if t == 190:
		_send_axis(4, JOY_AXIS_TRIGGER_RIGHT, 1.0)


func _test_finish() -> void:
	_send_axis(4, JOY_AXIS_TRIGGER_RIGHT, 0.0)
	check("5 joueurs", _players.size() == 5, "%d" % _players.size())
	var split := _scene.get("split") as GridContainer
	check("grille 3 x 2 : 6 cases pour 5 joueurs", split != null and split.columns == 3 and split.get_child_count() == 6)
	check_near("HUD a l'echelle 0,5", (_players[4].hud as RaceHud).ui_scale, 0.5, 0.001)
	var leader_cam := _scene.get("leader_camera") as ChaseCamera
	check("6e case : camera TV", leader_cam != null)
	if leader_cam == null:
		return
	var leader_vp := leader_cam.get_camera().get_viewport()
	var distinct := true
	for p: Object in _players:
		distinct = distinct and (p.get("viewport") as SubViewport) != leader_vp
	check("camera TV dans sa propre vue, la derniere de la grille",
		distinct and leader_vp is SubViewport and leader_vp.get_parent() == split.get_child(5))
	var j5: Truck = _players[4].truck
	check("J5 (parti du 2e rang) en tete, la camera TV le suit", leader_cam.target == j5,
		"cible %s" % (leader_cam.target.name if leader_cam.target != null else "aucune"))
	var label := _scene.get("_leader_label") as Label
	check("camera TV : annonce du leader", label.text == "EN TETE : J5 VIOLET NÉO-TOKYO", label.text)


func _send_axis(device: int, axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = device
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)
