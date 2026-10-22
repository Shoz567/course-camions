extends PhysicsTest

## Reapparition sur un raccourci (2026-10-22 : un bot detruit sur la rampe du
## saut de la marina reapparaissait a 14 m de sa carcasse, au-dela du mur,
## dans le vide, et explosait une seconde fois). dev/race_playa.tscn, un
## joueur pose sur le raccourci de la marina (u = 0,6, apres le saut), detruit,
## sa carcasse sur place :
##   A. la carcasse est sur le raccourci ;
##   B. sans controle de la chaussee, la place libre la plus proche est hors
##      de la route (le bug, pour que ce test le voie) ;
##   C. avec (LocalRace.on_road), elle est sur la chaussee ;
##   D. le camion reapparu y est, et n'en tombe pas dans les 2 s.

const PLACE_TICK := 60
const KILL_TICK := 120

var _scene: Node3D
var _track: TrackBlockout
var _crashes := 0
var _seen: Dictionary = {}


func _test_setup() -> void:
	duration_ticks = KILL_TICK + 240 + 150
	GameState.requested_players = 0
	_scene = (load("res://dev/race_playa.tscn") as PackedScene).instantiate() as Node3D
	_scene.set("ready_gate", false)
	_scene.set("player_count", 1)
	_scene.set("bot_count", 0)
	add_child(_scene)
	_track = _scene.get("track") as TrackBlockout
	(_scene.get("auto_reset") as AutoReset).truck_crashed.connect(func(_t: Truck) -> void:
		_crashes += 1)


func _truck() -> Truck:
	return ((_scene.get("players") as Array)[0] as Object).get("truck") as Truck


func _test_tick(t: int) -> void:
	var tr := _truck()
	var h := TruckHealth.of(tr)
	if t == PLACE_TICK:
		tr.reset_to(_track.branch_frame(0, 0.6, 0.0, 1.0))
	elif t == KILL_TICK:
		h.damage(1000.0, &"test")
	elif t == KILL_TICK + 10:
		var wreck: Node3D = null
		for n in get_tree().get_nodes_in_group(DetachedTrailer.OBSTACLES):
			if n is TruckWreck:
				wreck = n as Node3D
		_seen["wreck"] = _track.on_branch(wreck.global_position, 1.0) if wreck != null else -2
		# la ou il reapparaitrait sur place, a cote de sa carcasse
		var xf := _track.get_respawn_transform(wreck.global_position if wreck != null else tr.global_position)
		var keep := h.spot_ok
		h.spot_ok = Callable()
		_seen["raw"] = _on_road(h.free_spot(xf).origin)
		h.spot_ok = keep
		_seen["checked"] = _on_road(h.free_spot(xf).origin)
		_crashes = 0
	elif t == duration_ticks - 150:
		_seen["back"] = [tr.is_wrecked(), _on_road(tr.global_position), tr.global_position.round()]
	elif t == duration_ticks - 1:
		_seen["after"] = [tr.is_wrecked(), _on_road(tr.global_position)]


func _test_finish() -> void:
	check("A carcasse sur le raccourci", _seen.get("wreck") == 0, str(_seen.get("wreck")))
	check("B sans controle : hors de la route (le bug)", _seen.get("raw") == false, str(_seen.get("raw")))
	check("C avec controle : sur la chaussee", _seen.get("checked") == true, str(_seen.get("checked")))
	var back: Array = _seen.get("back", [])
	var after: Array = _seen.get("after", [])
	check("D reapparu sur la chaussee, sans chute ensuite", back.size() == 3 and back[0] == false and back[1] == true
		and _crashes == 0 and after == [false, true], "%s %d %s" % [back, _crashes, after])


## Sur la chaussee (comme LocalRace.on_road, que ce test ne suppose pas).
func _on_road(p: Vector3) -> bool:
	var kb := _track.on_branch(p)
	if kb >= 0:
		return absf(_track.branch_lateral_of(kb, p)) <= _track.branch_width_of(kb) / 2.0 - 2.5
	var i := _track.closest_sample(p)
	var d := p - _track.sample_position(i)
	return absf(d.dot(_track.sample_right(i))) <= _track.width / 2.0 - 2.5 and absf(d.dot(_track.sample_up(i))) < 4.0
