extends PhysicsTest

## Bots en ligne (2026-10-22 : « tout est bien disponible en multijoueur en
## ligne, les bots egalement ») : le host simule les bots choisis a son menu,
## les clients les recoivent au lancement (NetSession._launch) et les voient
## en marionnettes. Course hebergee (autoload NetSession, host seul), 3 bots
## durs :
##   A. 1 joueur + 3 bots ; chaque bot a son pilote (BotInputSource), un nom
##      « BOT n COULEUR » et une case libre, differente de celle du joueur ;
##   B. le snapshot porte les 4 camions ;
##   C. 10 s apres le depart, chaque bot a roule plus de 100 m.

const PORT := 7795

var _race: Node3D
var _saved: Array = []
var _go := -1
var _starts: Array[Vector3] = []
var _snapshot_trucks := -1


func _test_setup() -> void:
	duration_ticks = 1500
	_saved = [GameState.bot_count, GameState.bot_level, GameState.game_mode]
	GameState.bot_count = 3
	GameState.bot_level = BotInputSource.Level.HARD
	GameState.game_mode = GameStateNode.GameMode.RACE
	check("partie ouverte", NetSession.host(PORT) == OK, NetSession.last_error)
	NetSession.set_loadout(0, -1, -1)
	_race = (load("res://dev/race.tscn") as PackedScene).instantiate() as Node3D
	add_child(_race)
	for p: Object in _race.get("players"):
		_starts.append((p.get("truck") as Truck).global_position)


func _test_tick(t: int) -> void:
	# le joueur du host passe le sas READY (les bots y sont prets d'office)
	var flags: Array = _race.get("ready_flags")
	if not flags.is_empty():
		flags[0] = true
	if RaceManager.state == RaceManagerNode.State.RACING and _go < 0:
		_go = t
		var net := _race.get("net") as NetRace
		var snap := net.encode_snapshot(t) if net != null else PackedByteArray()
		_snapshot_trucks = snap.decode_u8(4) if snap.size() > 4 else -1
	if _go >= 0 and t - _go >= 600:
		duration_ticks = mini(duration_ticks, t + 1)


func _test_finish() -> void:
	var players: Array = _race.get("players")
	var ok := players.size() == 4 and not bool(_race.call("is_bot", 0))
	var slots := {int(_race.call("slot_of", 0)): true}
	var names := []
	for i in range(1, players.size()):
		var p := players[i] as Object
		var name := String(_race.call("player_name", i))
		names.append(name)
		slots[int(_race.call("slot_of", i))] = true
		ok = ok and bool(_race.call("is_bot", i)) and p.get("input") is BotInputSource and name.begins_with("BOT %d " % i)
	check("A 3 bots, chacun son pilote, son nom et sa case", ok and slots.size() == 4, "%s, cases %s" % [names, slots.keys()])
	check("B le snapshot porte les 4 camions", _snapshot_trucks == 4, str(_snapshot_trucks))
	var moved := []
	for i in range(1, players.size()):
		moved.append(roundi(((players[i] as Object).get("truck") as Truck).global_position.distance_to(_starts[i])))
	check("C les bots roulent", _go >= 0 and moved.all(func(m: int) -> bool: return m > 100), "%s m" % [moved])
	GameState.bot_count = _saved[0]
	GameState.bot_level = _saved[1]
	GameState.game_mode = _saved[2]
	NetSession.leave()
