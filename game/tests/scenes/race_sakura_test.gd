extends PhysicsTest

## Course sur Sakura lancee comme par le menu (GameState.selected_track = 2) :
## LocalRace y trouve son circuit (Track03), RaceLaps, AutoReset et
## PadEffects suivent le MEME circuit, l'ambiance est celle du Japon, la
## brume de chaleur legere, et la course demarre : la manette 0 fait avancer
## J1 sur l'avenue des cerisiers, et lui seul.

var _scene: Node3D
var _players: Array = []
var _starts: Array[Vector3] = []
var _haze: float = -1.0


func _test_setup() -> void:
	duration_ticks = 330
	GameState.selected_track = 2
	GameState.requested_players = 2
	_scene = (load(GameStateNode.track_scene(GameState.selected_track)) as PackedScene).instantiate() as Node3D
	_scene.set("ready_gate", false)
	add_child(_scene)
	GameState.selected_track = 0
	_haze = ScreenFx.haze
	_players = _scene.get("players")
	for p: Object in _players:
		_starts.append((p.get("truck") as Truck).global_position)


func _test_tick(t: int) -> void:
	if t == 190:
		_axis(0, 1.0)


func _axis(device: int, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = device
	e.axis = JOY_AXIS_TRIGGER_RIGHT
	e.axis_value = value
	Input.parse_input_event(e)


func _test_finish() -> void:
	_axis(0, 0.0)
	check("3e circuit : Sakura", GameStateNode.TRACKS.size() >= 3 and GameStateNode.TRACKS[2]["name"] == "Sakura"
		and GameStateNode.track_scene(2) == "res://dev/race_sakura.tscn")
	var track := _scene.get("track") as TrackBlockout
	check("la course court sur Sakura", track != null and track.name == "Track03"
		and track.theme_id == TrackTheme.Id.SAKURA)
	var same := true
	for n: String in ["RaceLaps", "AutoReset", "PadEffects"]:
		same = same and _scene.get_node(n).get("track") == track
	check("tours, reset et plaques suivent ce circuit", same)
	var amb := _scene.get_node_or_null(^"Ambience") as AmbienceSound
	check("ambiance du Japon", amb != null and amb.theme_id == TrackTheme.Id.SAKURA)
	check("printemps : brume de chaleur legere", _haze > 0.0 and _haze < 1.0, "haze=%.2f" % _haze)
	check("course lancee (GO passe)", _scene.get("state") == 1, "etat %s" % _scene.get("state"))
	var d0 := (_players[0].truck as Truck).global_position.distance_to(_starts[0])
	var d1 := (_players[1].truck as Truck).global_position.distance_to(_starts[1])
	check("manette 0 : J1 avance sur l'avenue, J2 reste", d0 > 10.0 and d1 < 0.5, "J1 %.1f m, J2 %.2f m" % [d0, d1])
