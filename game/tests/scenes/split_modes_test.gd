extends PhysicsTest

## Elimination et arene en ecran partage (2026-10-22 : « verifie que tout est
## bien disponible en multijoueur » ; seule la course avait un test a
## plusieurs joueurs sur un PC). 3 joueurs locaux et 2 bots, lances comme par
## le menu ; les 3 joueurs sont pilotes par des bots durs :
##   A. au depart, un ecran par joueur (3 SubViewport), sa camera suit son
##      camion, son HUD existe ; rien de tout cela pour les bots ;
##   B. elimination (elimination toutes les 10 s) : 4 elimines, un vainqueur,
##      la course se termine ; un joueur elimine lit « ELIMINE » sur SON ecran,
##      fin comprise (il lisait « temps limite ecoule ») ;
##      arene (1 vie, manche de 2 min) : au moins un joueur sorti (2026-10-22 :
##      « 2 camions » basculait d'une manche a l'autre), la manche se
##      termine, un joueur sorti lit « ELIMINE » sur son ecran.

@export var arena := false

const HUMANS := 3

var _scene: Node3D
var _saved: Array = []
var _views_ok := false
var _views := 0


func _test_setup() -> void:
	duration_ticks = 300 + 7200 + 200 if arena else 300 + 600 * 4 + 400
	_saved = [GameState.requested_players, GameState.bot_count, GameState.game_mode, GameState.arena_minutes,
		GameState.bot_level]
	GameState.requested_players = HUMANS
	GameState.bot_count = 2
	GameState.bot_level = BotInputSource.Level.HARD
	GameState.game_mode = GameStateNode.GameMode.ARENA if arena else GameStateNode.GameMode.ELIMINATION
	GameState.arena_minutes = 2
	_scene = (load("res://dev/arena.tscn" if arena else "res://dev/race.tscn") as PackedScene).instantiate() as Node3D
	_scene.set("ready_gate", false)
	if arena:
		_scene.set("arena_lives", 1)
	else:
		_scene.set("elim_first_ticks", 600)
		_scene.set("elim_every_ticks", 600)
	add_child(_scene)
	var players: Array = _scene.get("players")
	for i in HUMANS:
		var p := players[i] as Object
		var drv := BotInputSource.new()
		drv.setup(_scene.get("track") as TrackBlockout, p.get("truck") as Truck, BotInputSource.Level.HARD, 10 + i)
		add_child(drv)
		p.set("input", drv)


func _test_tick(t: int) -> void:
	if t == 400:
		_check_views()
	# fin de manche : plus rien a observer
	if t > 400 and RaceManager.state == RaceManagerNode.State.FINISHED and t % 60 == 0:
		duration_ticks = mini(duration_ticks, t + 60)


func _check_views() -> void:
	var players: Array = _scene.get("players")
	var ok := players.size() == HUMANS + 2
	var views := {}
	for i in players.size():
		var p := players[i] as Object
		var cam := p.get("camera") as ChaseCamera
		var human := i < HUMANS
		if human:
			ok = ok and cam != null and cam.target == p.get("truck") and p.get("hud") != null and p.get("viewport") != null
			if p.get("viewport") != null:
				views[p.get("viewport")] = true
		else:
			ok = ok and cam == null and p.get("hud") == null
	_views_ok = ok and views.size() == HUMANS
	_views = views.size()


func _test_finish() -> void:
	GameState.requested_players = _saved[0]
	GameState.bot_count = _saved[1]
	GameState.game_mode = _saved[2]
	GameState.arena_minutes = _saved[3]
	GameState.bot_level = _saved[4]
	var players: Array = _scene.get("players")
	check("A un ecran, une camera et un HUD par joueur, aucun pour les bots", _views_ok,
		"%d joueurs, %d ecrans" % [players.size(), _views])
	var eliminated: Array = _scene.get("eliminated")
	var lives: Array = _scene.get("lives")
	# ce que lit l'ecran d'un joueur sorti du jeu
	var shown := []
	for i in HUMANS:
		var out := (not arena and eliminated.has(i)) or (arena and int(lives[i]) <= 0)
		if out:
			shown.append(str((players[i] as Object).get("hud").get("_center_text")))
	if arena:
		check("B arene : des camions sortis, fin de manche, un joueur sorti le lit sur son ecran",
			not shown.is_empty() and RaceManager.state == RaceManagerNode.State.FINISHED
			and shown.all(func(s: String) -> bool: return s.contains("ÉLIMINÉ")),
			"vies %s, etat %d, ecrans des joueurs sortis %s" % [lives, RaceManager.state, shown])
	else:
		check("B elimination : 4 elimines, la course se termine, chacun le lit sur son ecran",
			eliminated.size() == 4 and RaceManager.state == RaceManagerNode.State.FINISHED
			and shown.all(func(s: String) -> bool: return s.contains("ÉLIMINÉ")),
			"elimines %s, etat %d, ecrans %s" % [eliminated, RaceManager.state, shown])
