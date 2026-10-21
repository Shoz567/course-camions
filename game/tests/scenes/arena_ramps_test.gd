extends PhysicsTest

## Tremplins et bots de l'arene (2026-10-21 : « dans le mode arène, les
## tremplins ont des problèmes, il y en a qui se rentrent dedans ; pas mal de
## petits soucis comme ça ») ; les trois arenes :
##   A. chaque tremplin et sa rampe jumelle sont dos a dos, en ligne droite :
##      memes aretes de sommet, bords d'attaque a 2 longueurs l'un de l'autre
##      (avant : jumelle a l'abscisse s + 2 L, sur l'arc ; decalee vers
##      l'interieur, elle chevauchait la premiere, vers l'exterieur elle s'en
##      ecartait de travers) ;
##   B. flancs inclines : le pied est plus large que le sommet (on aborde un
##      tremplin de tous les cotes) ;
##   C. aucun bonus sur la bosse ni dans ses envols ;
##   D. deux bots face a face, nez a nez : ils ne restent pas a se pousser
##      (aucun ne reste 2 s sous 1,5 m/s).

const TRACKS := ["res://tracks/arena_01.tscn", "res://tracks/arena_02.tscn", "res://tracks/arena_03.tscn"]
const BOT_TICKS := 900
const SLOW_MS := 1.5
const SLOW_MAX_TICKS := 120

var _seen: Dictionary = {}
var _track: TrackBlockout
var _bots: Array[BotInputSource] = []
var _trucks: Array[Truck] = []
var _slow := [0, 0]
var _worst := 0
var _state_was: int = 0


func _test_setup() -> void:
	duration_ticks = BOT_TICKS
	var a := []
	var b := []
	var c := []
	for path in TRACKS:
		var tr := (load(path) as PackedScene).instantiate() as TrackBlockout
		add_child(tr)
		for k in tr.jump_pad_count():
			var p := _points(tr, "JumpPad%d" % k)
			var q := _points(tr, "JumpPad%dB" % k)
			var tops := minf(p[2].distance_to(q[3]) + p[3].distance_to(q[2]), p[2].distance_to(q[2]) + p[3].distance_to(q[3]))
			var attack := ((p[0] + p[1]) / 2.0).distance_to((q[0] + q[1]) / 2.0)
			a.append(tops < 0.1 and absf(attack - 2.0 * tr.jump_length) < 0.1)
			b.append(p[0].distance_to(p[1]) > p[2].distance_to(p[3]) + 4.0)
			var from := (p[0] + p[1]) / 2.0
			var to := (q[0] + q[1]) / 2.0
			for n in tr.pickup_count():
				var pk := tr.pickup_node(n).global_position
				var axis := (to - from).normalized()
				var t := clampf((pk - from).dot(axis), -20.0, from.distance_to(to) + 20.0)
				if (pk - (from + axis * t)).length() < tr.jump_width / 2.0 + tr.jump_side_run + 5.0:
					c.append("%s bonus %d" % [path.get_file(), n])
		tr.free()
	_seen["a"] = a
	_seen["b"] = b
	_seen["c"] = c
	# D : deux bots nez a nez au milieu de l'anneau
	_state_was = RaceManager.state
	RaceManager.state = RaceManagerNode.State.RACING
	_track = (load(TRACKS[0]) as PackedScene).instantiate() as TrackBlockout
	add_child(_track)
	var mid := _track.frame_at(_track.index_at_s(_track.length() * 0.3), 0.0, 0.6)
	for k in 2:
		var truck := (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
		var xf := mid.translated(-mid.basis.z * (5.0 if k == 0 else -5.0))
		truck.transform = xf if k == 0 else xf.rotated_local(Vector3.UP, PI)
		truck.free_spin = true
		add_child(truck)
		var bot := BotInputSource.new()
		bot.setup(_track, truck, BotInputSource.Level.HARD, k)
		bot.arena = true
		add_child(bot)
		_trucks.append(truck)
		_bots.append(bot)


func _points(tr: TrackBlockout, body: String) -> PackedVector3Array:
	var n := tr.find_child(body, true, false)
	if n == null:
		return PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
	return ((n.get_child(0) as CollisionShape3D).shape as ConvexPolygonShape3D).points


func _test_tick(t: int) -> void:
	for k in 2:
		_trucks[k].set_input(_bots[k].poll(t))
		if t > 30:
			_slow[k] = int(_slow[k]) + 1 if _trucks[k].linear_velocity.length() < SLOW_MS else 0
			_worst = maxi(_worst, int(_slow[k]))


func _test_finish() -> void:
	RaceManager.state = _state_was as RaceManagerNode.State
	var a: Array = _seen.get("a", [])
	check("A rampes jumelles dos a dos, en ligne droite", a.size() == 6 and not a.has(false), str(a))
	var b: Array = _seen.get("b", [])
	check("B flancs inclines", b.size() == 6 and not b.has(false), str(b))
	var c: Array = _seen.get("c", ["pas de mesure"])
	check("C aucun bonus sur une bosse ni dans ses envols", c.is_empty(), str(c))
	check_below("D bots nez a nez : plus longue immobilite (ticks)", float(_worst), float(SLOW_MAX_TICKS))
