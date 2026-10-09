extends PhysicsTest

## Endurance a 4 camions sur la piste n°1, avec tout le gameplay d'une course :
## RaceLaps, AutoReset, plaques (PadEffects), remorques articulees, anti-collage
## et largage de cargo. Quatre pilotes (TrackAutopilot, par InputFrame) partent
## de la grille, chacun sur sa voie, et roulent 25 s ; chacun largue sa remorque.
## Verifie la robustesse, pas un temps : aucun NaN, personne hors du monde ni
## sur le toit plus de 2 s, tout le monde avance ; les remorques larguees
## restent sur la piste (ou explosent sous les chocs), jamais de disparition
## silencieuse, et chacun recoit une nouvelle remorque (recharge ramenee a
## COOLDOWN_TICKS pour tenir en 25 s).

const DURATION := 1500
const COOLDOWN_TICKS := 600
const LANES: Array[float] = [-2.5, 2.5, -7.5, 7.5]

var _track: TrackBlockout
var _race: RaceLaps
var _trucks: Array[Truck] = []
var _pilots: Array[TrackAutopilot] = []
var _start_progress: PackedFloat32Array = []
var _upside_ticks: PackedInt32Array = [0, 0, 0, 0]
var _max_upside: PackedInt32Array = [0, 0, 0, 0]
var _drops: int = 0
var _crates: Array[DetachedTrailer] = []
var _nan: bool = false
var _escaped: bool = false
var _resets: int = 0
var _unsticks: int = 0
var _shoves: int = 0
var _destroyed: int = 0


func _test_setup() -> void:
	duration_ticks = DURATION
	_track = (load("res://tracks/track_01_blockout.tscn") as PackedScene).instantiate() as TrackBlockout
	add_child(_track)
	_race = RaceLaps.new()
	_race.track = _track
	add_child(_race)
	var auto_reset := AutoReset.new()
	auto_reset.track = _track
	auto_reset.respawn_provider = _race.respawn_transform
	add_child(auto_reset)
	var pads := PadEffects.new()
	pads.track = _track
	add_child(pads)
	var g: Variant = require_baseline("max_lateral_g")
	if g == null:
		return
	for i in 4:
		var t := (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
		t.transform = _track.get_start_transform(i)
		add_child(t)
		_race.watch(t)
		auto_reset.watch(t)
		_trucks.append(t)
		var p := TrackAutopilot.new(_track, t, float(g))
		p.lane = LANES[i]
		_pilots.append(p)
		# recharge de 10 s (30 s par defaut) : la course de 25 s voit chacun
		# recevoir une nouvelle remorque
		(t.get_node("Cargo") as TruckCargo).cooldown_ticks = COOLDOWN_TICKS
		(t.get_node("Cargo") as TruckCargo).dropped.connect(func(c: DetachedTrailer) -> void:
			_drops += 1
			_crates.append(c)
			c.destroyed.connect(func() -> void: _destroyed += 1))
		t.wall_unstuck.connect(func(_n: Vector3) -> void: _unsticks += 1)
		t.trailer_shoved.connect(func(_o: Truck, _j: float) -> void: _shoves += 1)
	auto_reset.truck_reset.connect(func(_t: Truck, _r: StringName) -> void: _resets += 1)


func _test_tick(t: int) -> void:
	if t == 1:
		_race.start()
		for tr in _trucks:
			_start_progress.append(_race.progress(tr))
	for i in 4:
		var tr := _trucks[i]
		var f := _pilots[i].drive(t)
		f.cargo = t == 300 + 150 * i
		tr.set_input(f)
		var p := tr.global_position
		if not p.is_finite():
			_nan = true
		if p.y < -20.0:
			_escaped = true
		if tr.is_upside_down():
			_upside_ticks[i] += 1
			_max_upside[i] = maxi(_max_upside[i], _upside_ticks[i])
		else:
			_upside_ticks[i] = 0


func _test_finish() -> void:
	var moved := PackedFloat32Array()
	for i in 4:
		moved.append(_race.progress(_trucks[i]) - _start_progress[i])
	var alive := 0
	for c in _crates:
		if is_instance_valid(c):
			alive += 1
	print("  INFO   progression %s m ; %d largages, %d decollages de mur, %d coups de remorque, %d resets ; sur le toit max %s ticks"
		% [moved, _drops, _unsticks, _shoves, _resets, _max_upside])
	check("aucun NaN", not _nan)
	check("personne hors du monde", not _escaped)
	var slow := []
	for i in 4:
		if moved[i] < 400.0:
			slow.append(i + 1)
	check("tout le monde avance (> 400 m en 25 s)", slow.is_empty(), "lents : %s" % [slow])
	check("jamais sur le toit plus de 2 s", Array(_max_upside).max() < 120, str(_max_upside))
	check("4 largages de cargo", _drops == 4, "%d" % _drops)
	check("remorques larguees : sur la piste ou explosees, jamais disparues", alive + _destroyed == _drops,
		"%d sur la piste, %d explosees, %d largages" % [alive, _destroyed, _drops])
	var fresh := 0
	for tr in _trucks:
		fresh += 0 if tr.is_trailer_detached() else 1
	check("chacun a recu une nouvelle remorque apres la recharge", fresh == 4, "%d / 4" % fresh)
