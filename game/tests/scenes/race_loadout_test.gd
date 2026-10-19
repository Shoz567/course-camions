extends PhysicsTest

## Course lancee depuis la page de selection du menu (GameState.loadout_locked,
## 2026-10-16) : pas de sas READY, compte a rebours tout de suite ; chaque
## joueur a la remorque et les pouvoirs choisis au menu (camion, reglage).

var _scene: Node3D
var _seen: Dictionary = {}


func _test_setup() -> void:
	duration_ticks = 10
	GameState.requested_players = 2
	GameState.loadout_locked = true
	GameState.trailer_choice = PackedInt32Array([3, 5, 0, 0, 0, 0])
	GameState.power_left = PackedInt32Array([-1, -1, -1, -1, -1, -1])
	GameState.power_right = PackedInt32Array([-1, -1, -1, -1, -1, -1])
	_scene = (load("res://dev/race.tscn") as PackedScene).instantiate() as Node3D
	add_child(_scene)


func _test_tick(t: int) -> void:
	if t == 3:
		var players: Array = _scene.get("players")
		_seen["state"] = _scene.get("state")
		_seen["trailers"] = [players[0].trailer, players[1].trailer]
		_seen["types"] = [(players[0].truck as Truck).trailer_type == TrailerCatalog.at(3),
			(players[1].truck as Truck).trailer_type == TrailerCatalog.at(5)]
		_seen["powers"] = [players[0].power_left, players[0].power_right]


func _test_finish() -> void:
	GameState.loadout_locked = false
	check("choix fait au menu : pas de sas, compte a rebours", _seen.get("state", -1) == 0, str(_seen.get("state")))
	check("remorques du menu (index)", _seen.get("trailers", []) == [3, 5], str(_seen.get("trailers")))
	check("remorques du menu (camions)", _seen.get("types", []) == [true, true], str(_seen.get("types")))
	check("pouvoirs du menu : aucun (-1)", _seen.get("powers", []) == [-1, -1], str(_seen.get("powers")))
