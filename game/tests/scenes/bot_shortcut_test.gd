extends PhysicsTest

## Bots et raccourcis (2026-10-21 : « améliore les bots pour qu'ils prennent
## les short cut ») : Cyber City, raccourci des docks (le 1er), un camion
## arrete 320 m avant son entree :
##   A. un bot dur le prend : il passe sur sa chaussee (hors de la piste), le
##      suit jusqu'au bout et ressort sur la piste apres le detour, sans etre
##      remis en piste, sans faire sauter de baril ni frotter un mur ;
##   B. le meme trajet par le detour (bot qui ignore les raccourcis) : le
##      raccourci fait gagner au moins 15 % du temps ;
##   C. decisions (suite fixe) sur 20 passages : dur, tous ; moyen, environ
##      3 sur 4 ; facile, environ 2 sur 5 ; deux bots moyens ne font pas les
##      memes choix.

const RUN_UP_M := 320.0
const PAST_M := 40.0
const LIMIT_TICKS := 3600

var _track: TrackBlockout
var _truck: Truck
var _bot: BotInputSource
var _reset: AutoReset
var _start: Transform3D
var _goal_s: float = 0.0
var _phase: int = 0
var _phase_tick: int = 0
var _resets: int = 0
var _walls: int = 0
var _off_road: bool = false
var _seen: Dictionary = {}


func _test_setup() -> void:
	duration_ticks = LIMIT_TICKS * 2 + 60
	_track = (load("res://tracks/track_01_blockout.tscn") as PackedScene).instantiate() as TrackBlockout
	add_child(_track)
	_reset = AutoReset.new()
	_reset.track = _track
	add_child(_reset)
	_reset.truck_reset.connect(func(_t: Truck, _r: StringName) -> void: _resets += 1)
	_reset.truck_crashed.connect(func(_t: Truck) -> void: _resets += 1)
	var span := _track.branch_span(0)
	_goal_s = span.y + PAST_M
	_start = _track.frame_at(_track.index_at_s(span.x - RUN_UP_M), 0.0, 0.6)
	_truck = (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
	_truck.transform = _start
	add_child(_truck)
	_reset.watch(_truck)
	_truck.wall_impact_at.connect(func(v: float, _r: bool, _a: Vector3, _n: Vector3) -> void:
		if v > 3.0 and _phase == 0:
			_walls += 1)
	_bot = _new_bot(true)
	_seen["c"] = _decisions()


func _new_bot(shortcuts: bool) -> BotInputSource:
	var bot := BotInputSource.new()
	bot.shortcuts = shortcuts
	bot.setup(_track, _truck, BotInputSource.Level.HARD, 0)
	add_child(bot)
	return bot


## [pris sur 20 passages : facile, moyen (n° 0), moyen (n° 1), dur], et les
## choix des deux bots moyens different.
func _decisions() -> Array:
	var counts := []
	var a := []
	var b := []
	for spec: Array in [[BotInputSource.Level.EASY, 0], [BotInputSource.Level.MEDIUM, 0],
			[BotInputSource.Level.MEDIUM, 37], [BotInputSource.Level.HARD, 0]]:
		var n := 0
		for k in range(1, 21):
			var take := BotInputSource.takes_shortcut(spec[0], spec[1], k)
			n += 1 if take else 0
			if spec[0] == BotInputSource.Level.MEDIUM:
				(a if spec[1] == 0 else b).append(take)
		counts.append(n)
	return [counts, a != b]


func _progress() -> float:
	return _track.sample_s(_track.closest_sample(_truck.global_position))


func _test_tick(t: int) -> void:
	if _bot != null:
		_truck.set_input(_bot.poll(t))
	var p := _truck.global_position
	if _phase == 0:
		var k := _track.on_branch(p, 0.0)
		var i := _track.closest_sample(p)
		_off_road = _off_road or (k == 0 and _track.sample_position(i).distance_to(p) > _track.width / 2.0 + 2.0)
		if _progress() > _goal_s or t - _phase_tick > LIMIT_TICKS:
			var exploded := 0
			for b in _track.branch_barrels(0):
				exploded += 1 if b == null or b.exploded_state else 0
			_seen["a"] = [_bot.shortcuts_taken, _off_road, _progress() > _goal_s, _resets, exploded, _walls]
			_seen["ticks_a"] = t - _phase_tick
			# B : meme depart, par le detour
			_bot.queue_free()
			_bot = null
			_truck.reset_to(_start)
			_phase = 1
			_phase_tick = t
	elif _phase == 1:
		# B part quand le camion est revenu au depart (reset_to au pas suivant)
		if _bot == null and p.distance_to(_start.origin) < 3.0:
			_resets = 0
			_bot = _new_bot(false)
			_phase_tick = t
		elif _bot != null and (_progress() > _goal_s or t - _phase_tick > LIMIT_TICKS):
			_seen["b"] = [_bot.shortcuts_taken, _track.on_branch(p, 0.0) < 0, _progress() > _goal_s, _resets]
			_seen["ticks_b"] = t - _phase_tick
			_phase = 2
			duration_ticks = t + 1


func _test_finish() -> void:
	var a: Array = _seen.get("a", [0, false, false, -1, -1, -1])
	print("  INFO   A : %s en %d ticks ; B : %s en %d ticks" % [a, int(_seen.get("ticks_a", 0)), _seen.get("b"),
		int(_seen.get("ticks_b", 0))])
	check("A le bot dur prend le raccourci, sur sa chaussee, et ressort apres le detour",
		int(a[0]) == 1 and bool(a[1]) and bool(a[2]), str(a))
	check("A ni remis en piste, ni baril, ni mur", int(a[3]) == 0 and int(a[4]) == 0 and int(a[5]) == 0, str(a))
	var b: Array = _seen.get("b", [1, false, false, -1])
	check("B sans raccourci : par le detour, jusqu'au meme point", int(b[0]) == 0 and bool(b[2]) and int(b[3]) == 0,
		str(b))
	check_ratio_above("B le raccourci fait gagner au moins 15 % (ticks detour / raccourci)",
		float(_seen.get("ticks_b", 0)), float(maxi(int(_seen.get("ticks_a", 1)), 1)), 1.0 / 0.85)
	var c: Array = _seen.get("c", [[0, 0, 0, 0], false])
	var n: Array = c[0]
	check("C 20 passages : dur 20, moyen ~15, facile ~8 ; deux moyens differents",
		int(n[3]) == 20 and int(n[1]) >= 13 and int(n[1]) <= 17 and int(n[2]) >= 13 and int(n[2]) <= 17
		and int(n[0]) >= 6 and int(n[0]) <= 10 and bool(c[1]), str(c))
