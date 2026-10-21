extends PhysicsTest

## Regles de l'arene (2026-10-21 : « retire les gradins au centre ; pas de
## concept de tour, c'est juste une arène ; ne pas démarrer sur la ligne de
## départ mais à différents points ; pouvoir choisir la limite de temps ;
## retirer le principe de sens ») ; arene de Cyber City lancee comme par le
## menu : 1 joueur et 3 bots, duree « sans limite » :
##   A. aucune tribune ni projecteur sur l'ilot central : tous a l'exterieur ;
##   B. pas de ligne d'arrivee peinte ; chaque tremplin a sa rampe jumelle ;
##   C. departs repartis tout autour de l'anneau (aucun sur la grille), un sur
##      deux dans l'autre sens ;
##   D. HUD : ni chrono de tour ni meilleur tour ; rang des vies ;
##   E. duree du menu : sans limite, pas de compte a rebours, bandeau
##      « SANS LIMITE » ; 3 min : 10 800 ticks ;
##   F. reapparition la ou il est tombe, tourne dans le sens ou il roulait ;
##   G. (2026-10-21) departs a l'ecart des tremplins, barils, plaques et
##      flaques (un camion partait sur un baril) ; mini-carte sans ligne
##      d'arrivee.

var _scene: Node3D
var _seen: Dictionary = {}
var _saved: Array = []


func _test_setup() -> void:
	duration_ticks = 320
	_saved = [GameState.requested_players, GameState.bot_count, GameState.game_mode, GameState.arena_minutes]
	GameState.requested_players = 1
	GameState.bot_count = 3
	GameState.game_mode = GameStateNode.GameMode.ARENA
	GameState.arena_minutes = 0
	RaceDecor.generate_in_headless = true
	_scene = (load("res://dev/arena.tscn") as PackedScene).instantiate() as Node3D
	_scene.set("ready_gate", false)
	add_child(_scene)
	RaceDecor.generate_in_headless = false
	var track := _scene.get("track") as TrackBlockout
	# A : tribunes et projecteurs, tous plus loin du centre que la piste
	var centroid := RaceDecor._centroid(track)
	var stands := 0
	var inner := 0
	for n in _scene.find_children("*", "Node3D", true, false):
		var nm := String(n.name)
		if not (nm.begins_with("Stand") or nm.begins_with("Beam")):
			continue
		stands += 1
		var p := (n as Node3D).global_position
		var q := track.sample_position(track.closest_sample(p))
		if Vector2(p.x - centroid.x, p.z - centroid.z).length() < Vector2(q.x - centroid.x, q.z - centroid.z).length():
			inner += 1
	_seen["a"] = [stands, inner]
	# B : route sans damier, rampes jumelles
	var road := track.find_child("Road", true, false)
	var finish: Variant = null
	for m in road.find_children("*", "MeshInstance3D", true, false):
		var mat := (m as MeshInstance3D).material_override as ShaderMaterial
		if mat != null:
			finish = mat.get_shader_parameter("finish_line")
	var twins := 0
	for k in track.jump_pad_count():
		twins += 1 if track.find_child("JumpPad%dB" % k, true, false) != null else 0
	_seen["b"] = [finish, twins, track.jump_pad_count()]
	# C : poses de depart
	var players: Array = _scene.get("players")
	var min_gap := INF
	var on_grid := 0
	var backwards := 0
	for i in players.size():
		var t := (players[i] as Object).get("truck") as Truck
		if t.global_position.distance_to(track.get_start_transform(0).origin) < 25.0:
			on_grid += 1
		var j0 := track.closest_sample(t.global_position)
		if (-t.global_basis.z).dot(track.sample_forward(j0)) < 0.0:
			backwards += 1
		for j in range(i + 1, players.size()):
			var o := (players[j] as Object).get("truck") as Truck
			min_gap = minf(min_gap, t.global_position.distance_to(o.global_position))
		if not track.clear_spot(t.global_position, 8.0):  # LocalRace : ARENA_CLEAR_M - 1
			_seen["g_bad"] = int(_seen.get("g_bad", 0)) + 1
	_seen["c"] = [min_gap, on_grid, backwards, players.size()]
	_seen["limit"] = int(_scene.get("arena_limit_ticks"))


func _test_tick(t: int) -> void:
	if t != 280:
		return
	var players: Array = _scene.get("players")
	var hud := (players[0] as Object).get("hud") as RaceHud
	var ranking: Array = _scene.call("ranking")
	_seen["g_map"] = hud.minimap.finish.size() if hud.minimap != null else -1
	_seen["d"] = [hud.lap_times, (hud.get("_lap_time") as Label).visible, (hud.get("_times") as Label).visible,
		hud.place_override == ranking.find(players[0]) + 1]
	_seen["e"] = [int(_scene.call("arena_seconds_left")), String(_scene.call("ticker_text")).contains("SANS LIMITE")]
	# F : un camion qui roule a l'envers de la piste reapparait dans son sens
	var bot := (players[1] as Object).get("truck") as Truck
	var track := _scene.get("track") as TrackBlockout
	var i := track.closest_sample(bot.global_position)
	bot.linear_velocity = -track.sample_forward(i) * 12.0
	var xf: Transform3D = _scene.call("respawn_for", bot)
	_seen["f"] = [(-xf.basis.z).dot(-track.sample_forward(i)) > 0.5, xf.origin.distance_to(bot.global_position) < 40.0]
	# E : 3 minutes
	GameState.arena_minutes = 3
	var other := (load("res://dev/arena.tscn") as PackedScene).instantiate() as Node3D
	other.set("ready_gate", false)
	add_child(other)
	_seen["e3"] = int(other.get("arena_limit_ticks"))
	other.queue_free()


func _test_finish() -> void:
	GameState.requested_players = _saved[0]
	GameState.bot_count = _saved[1]
	GameState.game_mode = _saved[2]
	GameState.arena_minutes = _saved[3]
	var a: Array = _seen.get("a", [0, -1])
	check("A tribunes et projecteurs, aucun sur l'ilot central", int(a[0]) > 0 and int(a[1]) == 0, str(a))
	var b: Array = _seen.get("b", [true, 0, 1])
	check("B pas de ligne d'arrivee ; chaque tremplin dans les deux sens", b[0] == false and int(b[1]) == int(b[2])
		and int(b[2]) > 0, str(b))
	var c: Array = _seen.get("c", [0.0, 1, 0, 0])
	check("C departs repartis (> 60 m), aucun sur la grille, un sur deux a l'envers",
		float(c[0]) > 60.0 and int(c[1]) == 0 and int(c[2]) == int(c[3]) / 2, str(c))
	check("D HUD : ni chrono de tour, rang des vies", _seen.get("d") == [false, false, false, true], str(_seen.get("d")))
	check("E sans limite : pas de compte a rebours, bandeau SANS LIMITE", int(_seen.get("limit", -1)) == 0
		and _seen.get("e") == [-1, true], "%s %s" % [_seen.get("limit"), _seen.get("e")])
	check("E 3 minutes : 10 800 ticks", int(_seen.get("e3", 0)) == 10800, str(_seen.get("e3")))
	check("F reapparition sur place, dans le sens ou il roulait", _seen.get("f") == [true, true], str(_seen.get("f")))
	check("G departs a l'ecart des obstacles ; mini-carte sans ligne d'arrivee",
		int(_seen.get("g_bad", 0)) == 0 and _seen.get("g_map") == 0, "%s %s" % [_seen.get("g_bad", 0), _seen.get("g_map")])
