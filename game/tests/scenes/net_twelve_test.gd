extends PhysicsTest

## 12 joueurs en ligne (2026-10-22 : « monter le nombre de joueurs max en
## ligne a 12 ») :
##   A. 12 places de depart sur chaque circuit : sur la chaussee, derriere la
##      ligne, a plus de 8 m l'une de l'autre (avant, les places 6 et 7
##      tombaient sur les 4 et 5) ;
##   B. 12 couleurs, noms de couleur, modeles, teintes et livrees, couleurs
##      toutes differentes ;
##   C. course hebergee (autoload NetSession, host seul) avec 11 bots : 12
##      camions, 12 cases et 12 noms differents ; 10 s apres le depart, chaque
##      bot a roule plus de 40 m (les rangs arriere, dans le bouchon du depart :
##      60 a 85 m ; le joueur du host, que personne ne pilote, est exclu).

const LocalRace := preload("res://dev/local_race.gd")
const PORT := 7796
const TRACKS: PackedStringArray = ["res://tracks/track_01_blockout.tscn", "res://tracks/track_02_playa.tscn",
	"res://tracks/track_03_sakura.tscn"]

var _race: Node3D
var _saved: Array = []
var _go := -1
var _starts: Array[Vector3] = []


func _test_setup() -> void:
	duration_ticks = 1500
	_check_grids()
	_check_colors()
	_saved = [GameState.bot_count, GameState.bot_level, GameState.game_mode]
	GameState.bot_count = 11
	GameState.bot_level = BotInputSource.Level.MEDIUM
	GameState.game_mode = GameStateNode.GameMode.RACE
	check("partie ouverte", NetSession.host(PORT) == OK, NetSession.last_error)
	NetSession.set_loadout(0, -1, -1)
	_race = (load("res://dev/race.tscn") as PackedScene).instantiate() as Node3D
	add_child(_race)
	for p: Object in _race.get("players"):
		_starts.append((p.get("truck") as Truck).global_position)


func _check_grids() -> void:
	var bad := []
	for path in TRACKS:
		var tr := (load(path) as PackedScene).instantiate() as TrackBlockout
		add_child(tr)
		var pos: Array[Vector3] = []
		for k in NetSessionNode.MAX_PLAYERS:
			var p := tr.get_start_transform(k).origin
			var i := tr.closest_sample(p)
			var lat := absf((p - tr.sample_position(i)).dot(tr.sample_right(i)))
			if lat > tr.width / 2.0 - 3.0:
				bad.append("%s %d hors chaussee" % [path.get_file(), k])
			for q in pos:
				if q.distance_to(p) < 8.0:
					bad.append("%s %d trop pres" % [path.get_file(), k])
			pos.append(p)
		tr.queue_free()
	check("A 12 places de depart par circuit, sur la chaussee, espacees", bad.is_empty(), str(bad))


func _check_colors() -> void:
	var n := NetSessionNode.MAX_PLAYERS
	var ok: bool = n == 12 and LocalRace.MAX_TRUCKS == 12 and UiKit.PLAYER_COLORS.size() >= n
	ok = ok and LocalRace.COLOR_NAMES.size() >= n and LocalRace.MODELS.size() >= n
	ok = ok and LocalRace.TINTS.size() >= n and LocalRace.LIVERIES.size() >= n
	var close := []
	for a in n:
		for b in range(a + 1, n):
			var ca := UiKit.PLAYER_COLORS[a]
			var cb := UiKit.PLAYER_COLORS[b]
			if Vector3(ca.r - cb.r, ca.g - cb.g, ca.b - cb.b).length() < 0.2:
				close.append([a, b])
	check("B 12 couleurs, noms, modeles, teintes et livrees, couleurs distinctes", ok and close.is_empty(),
		"couleurs trop proches %s" % [close])


func _test_tick(t: int) -> void:
	if RaceManager.state == RaceManagerNode.State.RACING and _go < 0:
		_go = t
	if _go >= 0 and t - _go >= 600:
		duration_ticks = mini(duration_ticks, t + 1)


func _test_finish() -> void:
	var players: Array = _race.get("players")
	var slots := {}
	var names := {}
	var moved := 0
	var dist := []
	for i in players.size():
		slots[int(_race.call("slot_of", i))] = true
		names[String(_race.call("player_name", i))] = true
		var dd := ((players[i] as Object).get("truck") as Truck).global_position.distance_to(_starts[i])
		dist.append(roundi(dd))
		if i > 0 and dd > 40.0:
			moved += 1
	check("C 12 camions en ligne : cases et noms distincts, ils roulent",
		players.size() == 12 and slots.size() == 12 and names.size() == 12 and moved == 11,
		"%d camions, %d cases, %d noms, %d ont roule %s m" % [players.size(), slots.size(), names.size(), moved, dist])
	GameState.bot_count = _saved[0]
	GameState.bot_level = _saved[1]
	GameState.game_mode = _saved[2]
	NetSession.leave()
