extends PhysicsTest

## Raccourcis a saut (2026-10-21 : « ou carrément qu'il y ait un saut à faire
## avec une certaine vitesse ») : l'echangeur de Cyber City et la marina de
## Playa montent vers un plateau coupe par un vide, tremplin au bord :
##   A. un saut sur chacun de ces deux circuits (aucun a Sakura) : le vide
##      (rien sous le plateau), le tremplin, aucun checkpoint entre son pied
##      et le point de reapparition ;
##   B. a la vitesse conseillee (regulee), le camion passe : il retombe de
##      l'autre cote, sur ses roues, sur le raccourci ;
##   C. 15 km/h en dessous, il tombe dans le vide : hors piste pour AutoReset
##      (chute), et sa reapparition est sur le raccourci, apres le vide ;
##   D. un bot dur (100cc) prend le raccourci de l'echangeur et franchit le
##      saut sans remise en piste ; un bot facile en 50cc ne prend pas celui
##      de la marina (trop lent pour lui), un bot dur en 100cc si.

const TRACKS := ["res://tracks/track_01_blockout.tscn", "res://tracks/track_02_playa.tscn",
	"res://tracks/track_03_sakura.tscn"]
const RUN := 600
const BOT_LIMIT := 2400

var _track: TrackBlockout
var _truck: Truck
var _bot: BotInputSource
var _reset: AutoReset
var _kb: int = -1
var _step: int = -1
var _steps: Array[Array] = []
var _t0: int = 0
var _v: float = 0.0
var _frame := InputFrame.new()
var _fell: bool = false
var _landed_ok: bool = false
var _resets: int = 0
var _seen: Dictionary = {}


func _test_setup() -> void:
	# [circuit, essai] ; essais : "ok" (vitesse conseillee), "lent" (-15 km/h), "bot"
	_steps = [[0, "ok"], [0, "lent"], [0, "bot"], [1, "ok"], [1, "lent"]]
	duration_ticks = RUN * 4 + BOT_LIMIT + 120
	# A : construction des trois circuits
	var a := []
	for ti in TRACKS.size():
		var tr := (load(TRACKS[ti]) as PackedScene).instantiate() as TrackBlockout
		add_child(tr)
		var jumps := 0
		var ok := true
		for k in tr.branch_count():
			var j := tr.branch_jump(k)
			if j.x < 0.0:
				continue
			jumps += 1
			var length := tr.branch_length(k)
			var span := tr.branch_span(k)
			var lo := lerpf(span.x, span.y, j.x - TrackBlockout.BRANCH_RAMP_M / length)
			var hi := lerpf(span.x, span.y, j.y + TrackBlockout.BRANCH_JUMP_RESPAWN_M / length) \
					+ (span.y - span.x) / length * 15.0
			for c in tr.checkpoint_count:
				ok = ok and not (tr.checkpoint_s(c) > lo and tr.checkpoint_s(c) < hi)
			ok = ok and tr.find_child("BranchJump%d" % k, true, false) != null
			ok = ok and tr.branch_jump_min_kmh(k) > 0.0
			_seen["gap%d" % ti] = [tr.branch_frame(k, (j.x + j.y) / 2.0, 0.0, 0.0).origin, k]
		a.append([jumps, ok])
		tr.free()
	_seen["a"] = a


func _start(t: int) -> void:
	_step += 1
	if _bot != null:
		_bot.queue_free()
		_bot = null
	if _step >= _steps.size():
		duration_ticks = t + 2
		return
	var ti: int = _steps[_step][0]
	var kind: String = _steps[_step][1]
	if _step == 0 or int(_steps[_step - 1][0]) != ti:
		if _track != null:
			_track.queue_free()
			_truck.queue_free()
			_reset.queue_free()
		_track = (load(TRACKS[ti]) as PackedScene).instantiate() as TrackBlockout
		add_child(_track)
		var pads := PadEffects.new()
		pads.track = _track
		_track.add_child(pads)
		_reset = AutoReset.new()
		_reset.track = _track
		_reset.fall_explodes = false
		add_child(_reset)
		_reset.truck_reset.connect(func(_t: Truck, _r: StringName) -> void: _resets += 1)
		_truck = (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
		add_child(_truck)
		_reset.watch(_truck)
		_kb = -1
		for k in _track.branch_count():
			if _track.branch_jump(k).x >= 0.0:
				_kb = k
		if ti == 1:
			# D : decisions a la marina (50cc facile, 100cc dur)
			_seen["d_choice"] = [_can_jump(BotInputSource.Level.EASY, 0), _can_jump(BotInputSource.Level.HARD, 1)]
	_t0 = t
	_fell = false
	_landed_ok = false
	_resets = 0
	var j := _track.branch_jump(_kb)
	if kind == "bot":
		var span := _track.branch_span(_kb)
		_truck.reset_to(_track.frame_at(_track.index_at_s(span.x - 320.0), 0.0, 0.6))
		_bot = BotInputSource.new()
		_bot.setup(_track, _truck, BotInputSource.Level.HARD, 1)
		add_child(_bot)
	else:
		_v = (_track.branch_jump_min_kmh(_kb) - (15.0 if kind == "lent" else 0.0)) / 3.6
		_truck.reset_to(_track.branch_frame(_kb, j.x - 90.0 / _track.branch_length(_kb), 0.0, 0.8))


## Un bot de ce niveau, dans la categorie de vitesse de ce niveau de test
## (facile : 50cc, dur : 100cc), prendrait-il le saut de la marina ?
func _can_jump(bot_level: int, speed_class: int) -> bool:
	var probe := (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
	probe.tuning = GameStateNode.speed_tuning(probe.tuning, speed_class)
	probe.position = Vector3(0.0, -500.0, 0.0)
	add_child(probe)
	var bot := BotInputSource.new()
	bot.setup(_track, probe, bot_level, 0)
	var ok: bool = bot.call("_can_jump", _kb)
	bot.free()
	remove_child(probe)
	probe.free()
	return ok


func _test_tick(t: int) -> void:
	if _step < 0:
		_start(t)
		return
	if _step >= _steps.size():
		return
	var kind: String = _steps[_step][1]
	var dt := t - _t0
	var p := _truck.global_position
	var u := _track.branch_u(_kb, p)
	var j := _track.branch_jump(_kb)
	if kind == "bot":
		_truck.set_input(_bot.poll(t))
	else:
		if dt == 2:
			_truck.linear_velocity = -_truck.global_basis.z * _v
		var lat := _track.branch_lateral_of(_kb, p)
		var dir := -_track.branch_frame(_kb, clampf(u + 8.0 / _track.branch_length(_kb), 0.0, 1.0), 0.0, 0.0).basis.z
		var f := -_truck.global_basis.z
		var heading := atan2(f.cross(dir).y, f.dot(dir))
		var v := _truck.linear_velocity.length()
		_frame.tick = t
		_frame.throttle = clampf((_v - v) * 0.5, 0.0, 1.0)
		_frame.brake = clampf((v - _v - 0.5) * 0.5, 0.0, 1.0)
		_frame.steer = clampf(-lat * 0.06 - heading * 1.5, -1.0, 1.0)
		_truck.set_input(_frame)
	if dt > 2:
		var plateau := _track.branch_frame(_kb, j.x - 0.01, 0.0, 0.0).origin.y
		if u > j.x and u < j.y + 0.05 and p.y < plateau - 3.0 and not _fell:
			_fell = true
			_seen["off_%d" % _step] = _reset.is_off_track(_truck)
			var r := _track.get_respawn_transform(p + Vector3.DOWN * 4.0)
			_seen["respawn_%d" % _step] = [_track.on_branch(r.origin, 0.0) == _kb,
				_track.branch_u(_kb, r.origin) > j.y, _track.branch_u(_kb, r.origin) < j.y + 0.06]
		# retombe de l'autre cote, sur ses roues, 40 m apres le bord
		var tilt := rad_to_deg(_truck.global_basis.y.angle_to(Vector3.UP))
		if not _fell and u > j.y + 40.0 / _track.branch_length(_kb) and tilt < 30.0 \
				and _track.on_branch(p, 0.0) == _kb and _truck.wheels_on_ground() >= 3:
			_landed_ok = true
	var limit := BOT_LIMIT if kind == "bot" else RUN
	if dt >= limit or (_fell and dt > 30) or _landed_ok:
		_seen["run_%d" % _step] = [kind, _landed_ok, _fell, _resets]
		_start(t)


func _test_finish() -> void:
	var a: Array = _seen.get("a", [])
	check("A un saut a Cyber City et a Playa, aucun a Sakura ; tremplin, checkpoints hors du saut",
		str(a) == str([[1, true], [1, true], [0, true]]), str(a))
	var b := [_seen.get("run_0", []), _seen.get("run_3", [])]
	check("B a la vitesse conseillee : passe, retombe sur ses roues", str(b) == str([["ok", true, false, 0],
		["ok", true, false, 0]]), str(b))
	var c := [_seen.get("run_1", []), _seen.get("run_4", [])]
	check("C 15 km/h en dessous : tombe dans le vide", (c[0] as Array).size() == 4 and bool(c[0][2])
		and (c[1] as Array).size() == 4 and bool(c[1][2]), str(c))
	check("C hors piste (chute), reapparition sur le raccourci apres le vide",
		_seen.get("off_1") == true and _seen.get("off_4") == true
		and str(_seen.get("respawn_1")) == str([true, true, true]) and str(_seen.get("respawn_4")) == str([true, true, true]),
		"%s %s %s %s" % [_seen.get("off_1"), _seen.get("off_4"), _seen.get("respawn_1"), _seen.get("respawn_4")])
	var d: Array = _seen.get("run_2", [])
	check("D bot dur : franchit le saut de l'echangeur, sans remise en piste", str(d) == str(["bot", true, false, 0]),
		str(d))
	check("D marina : bot facile en 50cc non, bot dur en 100cc oui", str(_seen.get("d_choice")) == str([false, true]),
		str(_seen.get("d_choice")))
