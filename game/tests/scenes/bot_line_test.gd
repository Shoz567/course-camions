extends PhysicsTest

## Ligne de course des bots (2026-10-20, RacingLine) et zones de reset, sur
## chaque circuit (Cyber City, Playa, Sakura) :
##   A. la ligne reste dans la chaussee, a MARGIN_M des murs ;
##   B. elle passe sur des pads de boost (ceux a un petit detour), et evite
##      au moins la moitie des sauts et des flaques ;
##   B2. elle passe a cote de chaque baril explosif (2026-10-20) : le centre
##      de la ligne a plus de zone de declenchement + demi-largeur du camion ;
##   C. elle est lisse : rayon d'au moins 40 m partout (pas d'angle) ;
##   D. le profil de vitesse laisse toujours freiner a temps (v2 <= v1^2 +
##      2 a d) et reste sous la vitesse max ;
##   E. zone de reset touchee, centre du camion sur la route (remorque
##      au-dessus du mur interieur) : pas d'explosion. Au-dela du mur : oui.

const SCENES := ["res://dev/race.tscn", "res://dev/race_playa.tscn", "res://dev/race_sakura.tscn"]

var _seen: Dictionary = {}
var _scene: Node3D
var _crashed: int = 0


func _test_setup() -> void:
	duration_ticks = 40
	GameState.requested_players = 0
	for k in SCENES.size():
		var sc := (load(SCENES[k]) as PackedScene).instantiate() as Node3D
		sc.set("ready_gate", false)
		sc.set("player_count", 1)
		add_child(sc)
		_line_checks(k, sc.get("track") as TrackBlockout)
		if k == 0:
			_scene = sc
		else:
			sc.queue_free()
	var ar := _scene.get("auto_reset") as AutoReset
	ar.truck_crashed.connect(func(_t: Truck) -> void: _crashed += 1)


func _line_checks(k: int, t: TrackBlockout) -> void:
	var l := RacingLine.of(t)
	var n := t.sample_count()
	var lim := t.width / 2.0 - RacingLine.MARGIN_M + 0.01
	var inside := true
	var kmax := 0.0
	var kmax_center := 0.0
	for i in n:
		inside = inside and absf(l.offset[i]) <= lim
		kmax = maxf(kmax, absf(l.curvature[i]))
		kmax_center = maxf(kmax_center, absf(t.curvature(i)))
	var on_pads := 0
	for b: Vector2 in t._boosts:
		on_pads += 1 if absf(l.offset[t.index_at_s(b.x)] - b.y) <= t.boost_pad_size.x / 2.0 else 0
	var avoided := 0
	for j: Vector2 in t._jumps:
		avoided += 1 if absf(l.offset[t.index_at_s(j.x)] - j.y) >= t.jump_width / 2.0 + 2.0 else 0
	for p: Vector3 in t._puddles:
		avoided += 1 if absf(l.offset[t.index_at_s(p.x)] - p.y) >= p.z + 2.0 else 0
	var barrels_ok := true
	var barrel_min := INF
	for b: Vector2 in t._barrels:
		var clear := absf(l.offset[t.index_at_s(b.x)] - b.y)
		barrel_min = minf(barrel_min, clear)
		barrels_ok = barrels_ok and clear >= ExplosiveBarrel.BARREL_RADIUS + 1.0 + BotInputSource.HALF_WIDTH_M + 1.0
	_seen["barrels%d" % k] = [barrels_ok, barrel_min]
	var pads := on_pads >= 1
	var avoid := avoided * 2 >= t._jumps.size() + t._puddles.size()
	var top := 150.0 / 3.6
	var brake := 8.0
	var v := l.speed_profile(10.0, brake, top)
	var brakes := true
	var under := true
	for i in n:
		var j := (i + 1) % n
		var ds := absf(t.sample_s(j) - t.sample_s(i))
		if ds > t.length() / 2.0:
			ds = t.length() - ds
		brakes = brakes and v[i] * v[i] <= v[j] * v[j] + 2.0 * brake * ds + 0.01
		under = under and v[i] <= top + 0.001
	_seen[k] = [inside, pads, avoid, kmax < 1.0 / 40.0, brakes and under]
	_seen["detail%d" % k] = "rayon min %.0f m (ligne centrale %.0f m), pads %d/%d, evites %d/%d" % [1.0 / maxf(kmax, 1e-4),
		1.0 / maxf(kmax_center, 1e-4), on_pads, t._boosts.size(), avoided, t._jumps.size() + t._puddles.size()]


func _test_tick(t: int) -> void:
	var ar := _scene.get("auto_reset") as AutoReset
	var truck := ((_scene.get("players") as Array)[0] as Object).get("truck") as Truck
	match t:
		5:
			# remorque dans une zone, tete sur la route
			ar._zones[truck] = 1
		20:
			_seen["on_road"] = [_crashed, truck.is_wrecked()]
			ar._zones[truck] = 0
			# au-dela du mur, dans une zone : chute
			var tr := _scene.get("track") as TrackBlockout
			var i := tr.closest_sample(truck.global_position)
			_seen["past"] = ar._zones.has(truck)
			ar._zones[truck] = 1
			truck.global_position = tr.sample_position(i) + tr.sample_right(i) * (tr.width / 2.0 + 3.0) + Vector3.UP * 30.0
		38:
			_seen["past_wall"] = ar._past_wall(truck)


func _test_finish() -> void:
	var names := ["Cyber City", "Playa", "Sakura"]
	for k in SCENES.size():
		var r: Array = _seen.get(k, [])
		var d: String = _seen.get("detail%d" % k, "")
		check("%s : ligne dans la chaussee, a %.1f m des murs" % [names[k], RacingLine.MARGIN_M], r.size() == 5 and r[0], d)
		check("%s : sur les pads de boost, a cote des sauts et des flaques (petits detours)" % names[k], r.size() == 5 and r[1] and r[2], d)
		var br: Array = _seen.get("barrels%d" % k, [false, 0.0])
		check("%s : a cote de chaque baril" % names[k], br[0], "au plus pres %.1f m" % br[1])
		check("%s : ligne lisse, rayon de 40 m au moins" % names[k], r.size() == 5 and r[3], d)
		check("%s : profil de vitesse freinable et sous la vitesse max" % names[k], r.size() == 5 and r[4], d)
	check("zone touchee, centre sur la route : pas d'explosion", _seen.get("on_road", []) == [0, false],
		str(_seen.get("on_road")))
	check("zone touchee, centre au-dela du mur : compte comme sorti", bool(_seen.get("past_wall", false)) and bool(_seen.get("past", false)))
