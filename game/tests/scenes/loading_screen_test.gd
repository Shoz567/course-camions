extends PhysicsTest

## Ecran de chargement (2026-10-17) : sous l'ecran, la course n'avance pas -
## grille immobile meme plein gaz, pas de compte a rebours ; prete
## (loading_done) une fois la prechauffe faite ; l'ecran s'efface
## (release_start) : compte a rebours tout de suite si les remorques sont
## deja choisies au menu, sinon sas READY. Sans ecran : depart immediat.
## L'ecran lui-meme n'existe pas en headless : on simule sa presence.

const LocalRace := preload("res://dev/local_race.gd")

var _scene: Node3D
var _seen: Dictionary = {}
var _start: Vector3


func _test_setup() -> void:
	duration_ticks = 120
	GameState.loadout_locked = true
	var cover := LoadingScreen.new()
	cover.step = LoadingScreen.Step.PREPARING
	LoadingScreen._current = cover
	_seen["covering"] = LoadingScreen.covering()
	_scene = (load("res://dev/race.tscn") as PackedScene).instantiate() as Node3D
	_scene.set("player_count", 1)
	add_child(_scene)
	LoadingScreen._current = null
	cover.free()


func _test_tick(t: int) -> void:
	var truck := ((_scene.get("players") as Array)[0] as Object).get("truck") as Truck
	match t:
		2:
			_start = truck.global_position
			var e := InputEventJoypadMotion.new()
			e.device = 0
			e.axis = JOY_AXIS_TRIGGER_RIGHT
			e.axis_value = 1.0
			Input.parse_input_event(e)
		60:
			_seen["held_state"] = int(_scene.get("state"))
			_seen["moved"] = truck.global_position.distance_to(_start)
			_seen["done"] = bool(_scene.call("loading_done"))
			_scene.call("release_start")
			_seen["after"] = int(_scene.get("state"))
			var e := InputEventJoypadMotion.new()
			e.device = 0
			e.axis = JOY_AXIS_TRIGGER_RIGHT
			e.axis_value = 0.0
			Input.parse_input_event(e)


func _test_finish() -> void:
	var S := RaceManagerNode.State
	check("l'ecran couvre la scene", bool(_seen.get("covering", false)))
	check("sous l'ecran : ni sas ni compte a rebours qui avancent (grille en attente)",
		int(_seen.get("held_state", -1)) == S.LOBBY, str(_seen.get("held_state")))
	check("sous l'ecran : camion immobile meme plein gaz", float(_seen.get("moved", 9.0)) < 0.2,
		"%.2f m" % float(_seen.get("moved", 9.0)))
	check("course prete (prechauffe faite)", bool(_seen.get("done", false)))
	check("l'ecran s'efface : compte a rebours (remorques choisies au menu)",
		int(_seen.get("after", -1)) == S.COUNTDOWN, str(_seen.get("after")))
	check("release_start sans ecran : sans effet (deja partie)", _release_again())
	GameState.loadout_locked = false


func _release_again() -> bool:
	var before := int(_scene.get("state"))
	_scene.call("release_start")
	return int(_scene.get("state")) == before
