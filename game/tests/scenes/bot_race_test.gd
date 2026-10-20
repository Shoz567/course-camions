extends PhysicsTest

## Bots (2026-10-19), course hors ligne sur la piste n°1 (dev/race.tscn) :
## 1 joueur qui ne touche a rien, 3 bots de niveau moyen, 20 s de course :
##   A. les bots sont dans la course : 4 camions, noms « BOT n », toujours
##      prets, ni vue ni HUD, remorques et pouvoirs poses ;
##   B. ils roulent : chacun a parcouru plus de 300 m en 1000 ticks de course,
##      tous devant le joueur immobile ;
##   C. ils restent sur la piste : aucun detruit par une chute, au plus une
##      remise en piste a eux trois ;
##   D. le niveau compte : adherence visee, vitesse visee, freinage, part de
##      la ligne de course et reaction aux pouvoirs progressent de facile a
##      dur.

const TICKS := 1400

var _scene: Node3D
var _crashes: int = 0
var _resets: int = 0
var _start: Array = []
var _seen: Dictionary = {}


func _test_setup() -> void:
	duration_ticks = TICKS
	GameState.requested_players = 0
	_scene = (load("res://dev/race.tscn") as PackedScene).instantiate() as Node3D
	_scene.set("ready_gate", false)
	_scene.set("player_count", 1)
	_scene.set("bot_count", 3)
	add_child(_scene)
	var ar := _scene.get("auto_reset") as AutoReset
	ar.truck_crashed.connect(func(_t: Truck) -> void: _crashes += 1)
	ar.truck_reset.connect(func(_t: Truck, _r: StringName) -> void: _resets += 1)


func _players() -> Array:
	return _scene.get("players")


func _test_tick(t: int) -> void:
	if t == 5:
		var names := PackedStringArray()
		var huds := 0
		var powered := 0
		for i in _players().size():
			var p: Object = _players()[i]
			names.append(String(_scene.call("player_name", i)))
			huds += 1 if p.get("hud") != null else 0
			powered += 1 if TruckPowers.of(p.get("truck") as Truck) != null else 0
		_seen["names"] = names
		_seen["huds"] = huds
		_seen["powered"] = powered
		_seen["ready"] = (_scene.get("ready_flags") as Array).slice(1)
	if _start.is_empty() and int(_scene.get("state")) == RaceManagerNode.State.RACING:
		_seen["race_tick"] = t
		for p: Object in _players():
			_start.append(_scene.get("race").progress(p.get("truck") as Truck))
	if t == int(_seen.get("race_tick", -100000)) + 1000:
		var gone := PackedFloat32Array()
		for i in _players().size():
			gone.append(_scene.get("race").progress((_players()[i] as Object).get("truck") as Truck) - float(_start[i]))
		_seen["gone"] = gone


func _test_finish() -> void:
	var names: PackedStringArray = _seen.get("names", PackedStringArray())
	check("4 camions : 1 joueur et 3 bots", names.size() == 4 and names[1].begins_with("BOT 1")
		and names[3].begins_with("BOT 3"), str(names))
	check("bots : sans vue ni HUD, toujours prets", int(_seen.get("huds", 0)) == 1
		and _seen.get("ready", []) == [true, true, true], "%s HUD, %s" % [_seen.get("huds"), _seen.get("ready")])
	check("bots : pouvoirs poses", int(_seen.get("powered", 0)) >= 3)
	var gone: PackedFloat32Array = _seen.get("gone", PackedFloat32Array())
	var ok := gone.size() == 4
	for i in range(1, gone.size()):
		ok = ok and gone[i] > 300.0 and gone[i] > gone[0] + 300.0
	check("bots : plus de 300 m chacun en 1000 ticks, devant le joueur immobile", ok, str(gone))
	var g := BotInputSource.GRIP
	var sp := BotInputSource.SPEED
	var re := BotInputSource.REACTION_TICKS
	var br := BotInputSource.BRAKE
	var li := BotInputSource.LINE
	check("niveaux : facile < moyen < dur", g[0] < g[1] and g[1] < g[2] and sp[0] < sp[1] and sp[1] <= sp[2]
		and re[0] > re[1] and re[1] > re[2] and br[0] < br[1] and br[1] < br[2] and li[0] < li[1] and li[1] <= li[2])
	check("bots : aucun tombe de la piste", _crashes == 0, "%d chute(s)" % _crashes)
	check("bots : au plus une remise en piste", _resets <= 1, "%d" % _resets)
