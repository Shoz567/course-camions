extends PhysicsTest

## Raccourcis (2026-10-20 : « ajouter des raccourcis dans les circuits ; des
## detours pour que les raccourcis aient un reel interet ») :
##   A. Cyber City et Playa en ont 2, Sakura 1 ; chacun est au moins 200 m plus
##      court que le detour qu'il coupe ;
##   B. les murs de la piste s'ouvrent a ses deux bouts, et aucune zone de
##      reset ne touche sa chaussee ;
##   C. chaque checkpoint du detour a son double en travers du raccourci ;
##   D. un camion lance sur le raccourci des docks (Cyber City, 40 m de haut)
##      le suit jusqu'au bout : jamais remis en piste ni detruit, il passe les
##      checkpoints du detour dans l'ordre, et ressort sur la piste apres le
##      detour ;
##   E. sur le raccourci, sa progression suit le detour (closest_sample) ;
##      sa reapparition se fait sur le raccourci.

const TRACKS := ["res://tracks/track_01_blockout.tscn", "res://tracks/track_02_playa.tscn",
	"res://tracks/track_03_sakura.tscn"]
const COUNTS := [2, 2, 1]

var _track: TrackBlockout
var _truck: Truck
var _reset: AutoReset
var _resets: int = 0
var _cps: Array[int] = []
var _seen: Dictionary = {}
var _s0: float = 0.0
var _s1: float = 0.0
var _progress: Array[float] = []


func _test_setup() -> void:
	duration_ticks = 1500
	# A, B, C sur les trois circuits (construction seule)
	var counts := []
	var shorter := []
	var open_ok := []
	var zones_ok := []
	var cps_ok := []
	for k in TRACKS.size():
		var t := (load(TRACKS[k]) as PackedScene).instantiate() as TrackBlockout
		add_child(t)
		counts.append(t.branch_count())
		for b in t.branch_count():
			var span := t.branch_span(b)
			shorter.append(span.y - span.x - t.branch_length(b) >= 200.0)
			open_ok.append(_wall_opened(t, b))
			zones_ok.append(_zones_clear(t, b))
			cps_ok.append(_cps_doubled(t, b))
		if k > 0:
			t.queue_free()
		else:
			_track = t
	_seen["abc"] = [counts, shorter, open_ok, zones_ok, cps_ok]
	# D : le camion sur le raccourci des docks
	_reset = AutoReset.new()
	_reset.track = _track
	add_child(_reset)
	_reset.truck_reset.connect(func(_t: Truck, _r: StringName) -> void: _resets += 1)
	_reset.truck_crashed.connect(func(_t: Truck) -> void: _resets += 1)
	var span := _track.branch_span(0)
	_s0 = span.x
	_s1 = span.y
	var start := _track.branch_frame(0, 0.0, 0.0, 0.0)
	var i := _track.index_at_s(_s0 - 40.0)
	var lat := (start.origin - _track.sample_position(i)).dot(_track.sample_right(i))
	_truck = (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
	_truck.transform = _track.frame_at(i, lat, 0.6)
	add_child(_truck)
	_truck.linear_velocity = -_truck.global_basis.z * 20.0
	_reset.watch(_truck)
	_track.checkpoint_passed.connect(func(body: Node3D, index: int) -> void:
		if body == _truck and (_cps.is_empty() or _cps[-1] != index):
			_cps.append(index))


## Le mur de la piste est ouvert pres des deux bouts du raccourci b.
func _wall_opened(t: TrackBlockout, b: int) -> bool:
	var span := t.branch_span(b)
	var opened: Array[PackedByteArray] = t.get("_wall_open")
	var near0 := false
	var near1 := false
	for side in 2:
		for i in opened[side].size():
			if opened[side][i] == 1:
				var s := t.sample_s(i)
				near0 = near0 or absf(s - span.x) < 150.0
				near1 = near1 or absf(s - span.y) < 150.0
	return near0 and near1


## Aucune zone de reset ne contient un point de la chaussee du raccourci.
func _zones_clear(t: TrackBlockout, b: int) -> bool:
	var zones := t.get_node("ResetZones")
	for u in range(0, 21):
		var p := t.branch_frame(b, u / 20.0, 0.0, 1.5).origin
		for z in zones.get_children():
			var area := z as Area3D
			var cs := area.get_child(0) as CollisionShape3D
			var box := cs.shape as BoxShape3D
			var l := area.global_transform.affine_inverse() * p
			if absf(l.x) < box.size.x / 2.0 and absf(l.y) < box.size.y / 2.0 and absf(l.z) < box.size.z / 2.0:
				return false
	return true


## Chaque checkpoint du detour a son double sur le raccourci.
func _cps_doubled(t: TrackBlockout, b: int) -> bool:
	var span := t.branch_span(b)
	var want := 0
	for k in t.checkpoint_count:
		var s := t.checkpoint_s(k)
		if s > span.x and s < span.y:
			want += 1
			if t.get_node_or_null("Checkpoints/CP%02dB%d" % [k, b]) == null:
				return false
	return want > 0


func _test_tick(t: int) -> void:
	# pilote : suit l'axe du raccourci (ecart lateral, puis cap)
	var start := _track.branch_frame(0, 0.0, 0.0, 0.0)
	var dir := -start.basis.z
	var right := start.basis.x
	var p := _truck.global_position
	var lat := (p - start.origin).dot(right)
	var f := -_truck.global_basis.z
	var heading := atan2(f.cross(dir).y, f.dot(dir))
	var frame := InputFrame.new()
	frame.throttle = 0.7
	frame.steer = clampf(-lat * 0.06 - heading * 1.5, -1.0, 1.0)
	_truck.set_input(frame)
	var along := (p - start.origin).dot(dir) / _track.branch_length(0)
	if along > 0.1 and along < 0.9:
		_progress.append(_track.sample_s(_track.closest_sample(p)))
	if along > 0.5 and not _seen.has("respawn"):
		var r := _track.get_respawn_transform(p)
		_seen["respawn"] = _track.on_branch(r.origin, 0.0)
	if along > 1.0 and not _seen.has("out"):
		_seen["out"] = [t, _track.sample_s(_track.closest_sample(p)), _track.on_branch(p)]
		duration_ticks = t + 60


func _test_finish() -> void:
	var abc: Array = _seen.get("abc", [[], [], [], [], []])
	check("A raccourcis par circuit : 2, 2, 1", abc[0] == COUNTS, str(abc[0]))
	check("A chacun au moins 200 m plus court que son detour", not (abc[1] as Array).has(false)
		and (abc[1] as Array).size() == 5, str(abc[1]))
	check("B murs de la piste ouverts aux deux bouts", not (abc[2] as Array).has(false), str(abc[2]))
	check("B aucune zone de reset sur un raccourci", not (abc[3] as Array).has(false), str(abc[3]))
	check("C checkpoints du detour doubles sur le raccourci", not (abc[4] as Array).has(false), str(abc[4]))
	var out: Array = _seen.get("out", [-1, 0.0, 0])
	check("D au bout du raccourci, sans remise en piste", int(out[0]) > 0 and _resets == 0,
		"%s, %d remises" % [out, _resets])
	check("D ressort sur la piste apres le detour", float(out[1]) > _s1 - 20.0 and float(out[1]) < _s1 + 200.0,
		"s=%.0f (detour %.0f .. %.0f)" % [float(out[1]), _s0, _s1])
	var ordered := _cps.size() >= 1
	for k in range(1, _cps.size()):
		ordered = ordered and _cps[k] == (_cps[k - 1] + 1) % _track.checkpoint_count
	check("D checkpoints du detour passes dans l'ordre", ordered, str(_cps))
	var monotone := _progress.size() > 10
	for k in range(1, _progress.size()):
		monotone = monotone and _progress[k] >= _progress[k - 1] - 0.5
	check("E progression : suit le detour, toujours en avant", monotone and _progress[0] > _s0 and _progress[-1] < _s1,
		"%d mesures, %.0f .. %.0f" % [_progress.size(), _progress[0] if not _progress.is_empty() else 0.0,
		_progress[-1] if not _progress.is_empty() else 0.0])
	check("E reapparition sur le raccourci", int(_seen.get("respawn", -1)) == 0, str(_seen.get("respawn")))
