extends PhysicsTest

## Mini-carte facon Mario Kart (2026-10-21 : « une mini map à la Mario Kart
## sur laquelle on peut voir les positions des joueurs ») ; Cyber City, 2
## joueurs en ecran partage et 1 bot :
##   A. chaque ecran a sa mini-carte, au milieu du bord gauche de sa vue ;
##   B. elle suit les 3 camions, chacun a la couleur de son joueur ; le sien
##      (et lui seul) est marque ;
##   C. trace (route, raccourcis, ligne d'arrivee) et camions dans son cadre ;
##      nord en haut : +Z du monde vers le bas, +X vers la droite ;
##   D. les pastilles suivent les camions : apres 3 s de course, celle du bot
##      a bouge sur la carte d'autant que lui (a l'echelle) ;
##   E. Sakura : le pont du croisement est dessine a part (par-dessus) et son
##      raccourci figure.

var _scene: Node3D
var _seen: Dictionary = {}
var _bot_start := Vector2.INF
var _bot_world := Vector3.ZERO
var _race_tick: int = -1


func _test_setup() -> void:
	duration_ticks = 400
	GameState.requested_players = 0
	_scene = (load("res://dev/race.tscn") as PackedScene).instantiate() as Node3D
	_scene.set("ready_gate", false)
	_scene.set("player_count", 2)
	_scene.set("bot_count", 1)
	add_child(_scene)
	var sakura := (load("res://tracks/track_03_sakura.tscn") as PackedScene).instantiate() as TrackBlockout
	add_child(sakura)
	var m := MiniMap.new()
	add_child(m)
	m.setup(sakura, [] as Array[Dictionary])
	_seen["e"] = [m.decks.size(), m.branches.size(), m.ground.size()]
	m.queue_free()
	sakura.queue_free()


func _players() -> Array:
	return _scene.get("players")


func _inside(m: MiniMap, p: Vector2) -> bool:
	return p.x >= 0.0 and p.y >= 0.0 and p.x <= m.box.x and p.y <= m.box.y


func _test_tick(t: int) -> void:
	var state := int(_scene.get("state"))
	if _race_tick < 0 and state == RaceManagerNode.State.RACING:
		_race_tick = t
	var bot_truck := (_players()[2] as Object).get("truck") as Truck
	var hud0 := (_players()[0] as Object).get("hud") as RaceHud
	if _race_tick >= 0 and t == _race_tick + 10:
		_bot_start = hud0.minimap.marker_position(bot_truck)
		_bot_world = bot_truck.get_global_transform_interpolated().origin
	if _race_tick >= 0 and t == _race_tick + 190:
		var moved_map := hud0.minimap.marker_position(bot_truck).distance_to(_bot_start)
		var w := bot_truck.get_global_transform_interpolated().origin - _bot_world
		_seen["d"] = [moved_map, Vector2(w.x, w.z).length() * hud0.minimap.get("_scale")]
		var a := []
		var b := []
		var c := []
		for i in 2:
			var hud := (_players()[i] as Object).get("hud") as RaceHud
			var m := hud.minimap
			if m == null:
				a.append(false)
				continue
			var vp := m.get_viewport_rect()
			var r := m.get_global_rect()
			a.append(r.position.x < vp.size.x * 0.2 and absf(r.get_center().y - vp.size.y / 2.0) < vp.size.y * 0.1)
			var colors := []
			var selves := []
			for mk in m.markers:
				colors.append(mk["color"])
				if bool(mk["self"]):
					selves.append(mk["truck"])
			b.append(m.markers.size() == 3 and selves == [hud.truck]
				and colors == [UiKit.PLAYER_COLORS[0], UiKit.PLAYER_COLORS[1], UiKit.PLAYER_COLORS[2]])
			var all_in := m.ground.size() > 0 and m.finish.size() == 2 and m.branches.size() == 2
			for line in m.ground + m.decks + m.branches:
				for p in line:
					all_in = all_in and _inside(m, p)
			for mk in m.markers:
				all_in = all_in and _inside(m, m.marker_position(mk["truck"]))
			var o := m.to_map(Vector3.ZERO)
			c.append(all_in and m.to_map(Vector3(0, 0, 100)).y > o.y and m.to_map(Vector3(100, 0, 0)).x > o.x)
		_seen["abc"] = [a, b, c]
		duration_ticks = t + 1


func _test_finish() -> void:
	var abc: Array = _seen.get("abc", [[], [], []])
	check("A une mini-carte par ecran, au milieu du bord gauche", abc[0] == [true, true], str(abc[0]))
	check("B les 3 camions, a la couleur de leur joueur ; le sien seul marque", abc[1] == [true, true], str(abc[1]))
	check("C trace et camions dans le cadre ; nord en haut", abc[2] == [true, true], str(abc[2]))
	var d: Array = _seen.get("d", [0.0, 0.0])
	check("D la pastille du bot suit son camion (px, a l'echelle)", float(d[1]) > 1.0
		and absf(float(d[0]) - float(d[1])) < 0.5, str(d))
	var e: Array = _seen.get("e", [0, 0, 0])
	check("E Sakura : pont dessine a part, raccourci figure", int(e[0]) >= 1 and int(e[1]) == 1 and int(e[2]) >= 1, str(e))
