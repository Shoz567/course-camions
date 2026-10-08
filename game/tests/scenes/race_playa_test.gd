extends PhysicsTest

## Course sur Playa Del Sol lancee comme par le menu : GameState.selected_track
## donne la scene (dev/race_playa.tscn), LocalRace y trouve son circuit
## (track_path), RaceLaps, AutoReset et PadEffects suivent le MEME circuit, et
## la course demarre : la manette 0 fait avancer J1 sur la promenade, et lui
## seul. Cyber City reste le circuit par defaut.

var _scene: Node3D
var _players: Array = []
var _starts: Array[Vector3] = []
var _default_scene: String = ""
# meteo de la course (statiques poses par LocalRace a son entree)
var _spray: int = -1
var _haze: float = -1.0


func _test_setup() -> void:
	duration_ticks = 330
	GameState.selected_track = 0
	_default_scene = GameStateNode.track_scene(GameState.selected_track)
	GameState.selected_track = 1
	GameState.requested_players = 2
	_scene = (load(GameStateNode.track_scene(GameState.selected_track)) as PackedScene).instantiate() as Node3D
	_scene.set("ready_gate", false)   # le sas READY a son propre test (race_ready_test)
	add_child(_scene)
	GameState.selected_track = 0
	_spray = TruckWheelFx.spray
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
	check("circuit par defaut : Cyber City", _default_scene == "res://dev/race.tscn", _default_scene)
	check("2 circuits au choix, noms et scenes", GameStateNode.TRACKS.size() == 2
		and GameStateNode.TRACKS[1]["name"] == "Playa Del Sol"
		and GameStateNode.track_scene(1) == "res://dev/race_playa.tscn"
		and GameStateNode.track_scene(99) == "res://dev/race_playa.tscn")
	check("scenes de course presentes", ResourceLoader.exists(GameStateNode.track_scene(0))
		and ResourceLoader.exists(GameStateNode.track_scene(1)))
	var track := _scene.get("track") as TrackBlockout
	check("la course court sur Playa Del Sol", track != null and track.name == "Track02"
		and track.theme_id == TrackTheme.Id.PLAYA_DEL_SOL)
	var same := true
	for n: String in ["RaceLaps", "AutoReset", "PadEffects"]:
		same = same and _scene.get_node(n).get("track") == track
	check("tours, reset et plaques suivent ce circuit", same)
	check("2 joueurs, ecran partage", _players.size() == 2 and _scene.get("split") != null)
	check("plage : poussiere de sable derriere les roues, brume de chaleur",
		_spray == TruckWheelFx.Spray.DUST and _haze > 0.0, "spray=%d haze=%.1f" % [_spray, _haze])
	check("course lancee (GO passe)", _scene.get("state") == 1, "etat %s" % _scene.get("state"))
	var d0 := (_players[0].truck as Truck).global_position.distance_to(_starts[0])
	var d1 := (_players[1].truck as Truck).global_position.distance_to(_starts[1])
	check("manette 0 : J1 avance sur la promenade, J2 reste", d0 > 10.0 and d1 < 0.5, "J1 %.1f m, J2 %.2f m" % [d0, d1])
