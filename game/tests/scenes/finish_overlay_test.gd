extends PhysicsTest

## Fin de course sans gene (2026-10-19 : « la fin de course du premier laisse
## les autres joueurs finir sans obstruer leur ecran ») ; course a 2 :
##   A. avant toute arrivee : ni carte de classement ni bandeau ;
##   B. J1 passe la ligne : chez J2, encore en course, aucune carte au centre
##      (ni classement, ni message), un bandeau en haut (1er, temps limite) ;
##      chez J1, sa place et le classement ;
##   C. J2 passe la ligne : course finie, le classement complet chez les deux,
##      plus de bandeau.

var _scene: Node3D
var _seen: Dictionary = {}


func _test_setup() -> void:
	duration_ticks = 300
	GameState.requested_players = 0
	_scene = (load("res://dev/race.tscn") as PackedScene).instantiate() as Node3D
	_scene.set("ready_gate", false)
	_scene.set("player_count", 2)
	add_child(_scene)


func _hud(i: int) -> RaceHud:
	return (_scene.get("players") as Array)[i].get("hud") as RaceHud


func _truck(i: int) -> Truck:
	return (_scene.get("players") as Array)[i].get("truck") as Truck


func _finish(i: int) -> void:
	_scene.get("race").racer(_truck(i)).finished = true
	_scene.call("_on_race_finished", _truck(i), 1000)


func _snap(key: String) -> void:
	_seen[key] = [_hud(0).standings_visible(), _hud(0).ticker_text(), _hud(1).standings_visible(),
		_hud(1).ticker_text(), String(_hud(1).get("_center_text")), String(_hud(0).get("_center_text"))]


func _test_tick(t: int) -> void:
	match t:
		210:
			_snap("before")
			_finish(0)
		215:
			_snap("first")
			_finish(1)
		220:
			_snap("end")


func _test_finish() -> void:
	var b: Array = _seen.get("before", [])
	var f: Array = _seen.get("first", [])
	var e: Array = _seen.get("end", [])
	check("avant toute arrivee : ni classement ni bandeau", b.size() == 6 and not b[0] and b[1] == ""
		and not b[2] and b[3] == "", str(b))
	check("J1 arrive : J2 n'a ni classement ni message au centre", f.size() == 6 and not f[2] and f[4] == "",
		str(f))
	check("J1 arrive : bandeau en haut chez J2 (1er, temps limite)", f.size() == 6 and String(f[3]).contains("1er")
		and String(f[3]).contains("FIN DANS"), str(f[3] if f.size() == 6 else f))
	check("J1 arrive : chez lui, sa place et le classement, pas de bandeau", f.size() == 6 and f[0]
		and f[1] == "" and String(f[5]).contains("1er"), str(f))
	check("tous arrives : classement chez les deux, plus de bandeau", e.size() == 6 and e[0] and e[2]
		and e[1] == "" and e[3] == "", str(e))
