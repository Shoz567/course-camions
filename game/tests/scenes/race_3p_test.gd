extends PhysicsTest

## Course a 3 joueurs (dev/race.tscn, choix du menu) : grille 2 x 2 dont la 4e
## case montre le camion en tete (camera TV). La manette 1 fait avancer J2 :
## il passe en tete, la camera TV le suit et l'annonce. Pas de classement
## affiche tant que personne n'est arrive.

var _scene: Node3D
var _players: Array = []


func _test_setup() -> void:
	duration_ticks = 300
	GameState.requested_players = 3
	_scene = (load("res://dev/race.tscn") as PackedScene).instantiate() as Node3D
	_scene.set("ready_gate", false)   # le sas READY a son propre test (race_ready_test)
	add_child(_scene)
	_players = _scene.get("players")


func _pad(device: int, button: JoyButton, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = button
	e.pressed = pressed
	Input.parse_input_event(e)


func _test_tick(t: int) -> void:
	if t == 190:
		_send_axis(1, JOY_AXIS_TRIGGER_RIGHT, 1.0)


func _test_finish() -> void:
	_send_axis(1, JOY_AXIS_TRIGGER_RIGHT, 0.0)
	check("3 joueurs", _players.size() == 3, "%d" % _players.size())
	var split := _scene.get("split") as GridContainer
	check("grille 2 x 2 : 4 cases pour 3 joueurs", split != null and split.columns == 2 and split.get_child_count() == 4)
	var leader_cam := _scene.get("leader_camera") as ChaseCamera
	check("4e case : camera TV", leader_cam != null)
	if leader_cam == null:
		return
	var leader_vp := leader_cam.get_camera().get_viewport()
	var distinct := true
	for p: Object in _players:
		distinct = distinct and (p.get("viewport") as SubViewport) != leader_vp
	check("camera TV dans sa propre vue", distinct and leader_vp is SubViewport)
	var j2: Truck = _players[1].truck
	check("J2 en tete, la camera TV le suit", leader_cam.target == j2,
		"cible %s" % (leader_cam.target.name if leader_cam.target != null else "aucune"))
	var label := _scene.get("_leader_label") as Label
	check("camera TV : annonce du leader", label.text == "EN TETE : J2 DURAND", label.text)
	check("pas de classement avant la premiere arrivee", _scene.call("standings_text") == "")


func _send_axis(device: int, axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = device
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)
