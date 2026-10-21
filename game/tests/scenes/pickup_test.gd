extends PhysicsTest

## Bonus sur la piste (2026-10-20 : « reparation, recharge de pouvoir ») :
##   A. chaque circuit a 12 bonus : 6 de reparation, 6 de recharge ;
##   E. epars (2026-10-21 : « pas des rangées, plutôt répartis un peu
##      aléatoirement, comme les barils ») : jamais deux a la meme hauteur de
##      piste (ecart > 20 m), decalages varies, tous sur la chaussee, loin des
##      barils, plaques et tremplins ; memes places a chaque construction (en
##      ligne, host et clients les numerotent pareil) ;
##   B. reparation : le camion abime (40 PV, remorque 20, un pneu creve) en
##      prend un : +40 PV a la tete, +30 a la remorque, pneus neufs ; le bonus
##      disparait (un 2e camion juste apres n'a rien), puis revient ;
##   C. recharge : missile en recharge (10 s) et laser (5 s) : le missile
##      redevient pret, le laser garde sa recharge ;
##   D. HUD : le message du bonus s'affiche puis s'efface.

const TRACKS := ["res://tracks/track_01_blockout.tscn", "res://tracks/track_02_playa.tscn",
	"res://tracks/track_03_sakura.tscn"]

var _track: TrackBlockout
var _pads: PadEffects
var _a: Truck
var _b: Truck
var _c: Truck
var _repair: TrackPickup
var _power: TrackPickup
var _pc: TruckPowers
var _hud: RaceHud
var _seen: Dictionary = {}


func _test_setup() -> void:
	duration_ticks = 260
	var kinds := []
	for k in TRACKS.size():
		var t := (load(TRACKS[k]) as PackedScene).instantiate() as TrackBlockout
		add_child(t)
		var rep := 0
		var pow := 0
		for i in t.pickup_count():
			if t.pickup_node(i).kind == TrackPickup.Kind.REPAIR:
				rep += 1
			else:
				pow += 1
		kinds.append([t.pickup_count(), rep, pow])
		_seen["spread%d" % k] = _spread(t)
		if k == 0:
			# une 2e construction du meme circuit : memes places
			var twin := (load(TRACKS[k]) as PackedScene).instantiate() as TrackBlockout
			add_child(twin)
			var same := true
			for i in t.pickup_count():
				same = same and twin.pickup_place(i) == t.pickup_place(i)
			_seen["twin"] = same and twin.pickup_count() == t.pickup_count()
			twin.queue_free()
		if k == 0:
			_track = t
		else:
			t.queue_free()
	_seen["kinds"] = kinds
	_pads = PadEffects.new()
	_pads.track = _track
	add_child(_pads)
	for i in _track.pickup_count():
		var p := _track.pickup_node(i)
		if _repair == null and p.kind == TrackPickup.Kind.REPAIR:
			_repair = p
		if _power == null and p.kind == TrackPickup.Kind.POWER:
			_power = p
	_repair.respawn_ticks = 120
	_a = _spawn(Vector3(5000.0, 0.0, 0.0))
	_b = _spawn(Vector3(5100.0, 0.0, 0.0))
	_c = _spawn(Vector3(5200.0, 0.0, 0.0))
	_pc = TruckPowers.setup(_c, PowerCatalog.Id.MISSILE, PowerCatalog.Id.LASER)
	_hud = RaceHud.new()
	add_child(_hud)


## [ecart d'abscisse minimal (m), decalages distincts, |decalage| max (m),
## places encombrees].
func _spread(t: TrackBlockout) -> Array:
	var s := PackedFloat32Array()
	var lats := {}
	var widest := 0.0
	var crowded := 0
	for i in t.pickup_count():
		var p := t.pickup_place(i)
		s.append(p.x)
		lats[roundi(p.y * 2.0)] = true
		widest = maxf(widest, absf(p.y))
		if not t.pickup_clear(p.x, p.y):
			crowded += 1
		for k in t.barrel_count():
			var b := t.barrel_transform(k).origin
			if b.distance_to(t.pickup_node(i).global_position) < TrackBlockout.PICKUP_CLEAR_M - 1.0:
				crowded += 1
	s.sort()
	var gap := INF
	for i in range(1, s.size()):
		gap = minf(gap, s[i] - s[i - 1])
	return [gap, lats.size(), widest - (t.width / 2.0 - TrackBlockout.PICKUP_EDGE_M), crowded]


func _spawn(at: Vector3) -> Truck:
	var t := TruckTestUtil.spawn_truck(self, at)
	t.freeze = true
	return t


func _onto(t: Truck, p: TrackPickup) -> void:
	t.freeze = false
	t.reset_to(Transform3D(p.global_basis, p.global_position + Vector3.UP * 0.6))


func _test_tick(t: int) -> void:
	match t:
		5:
			var h := TruckHealth.of(_a)
			h.hp = 40.0
			h.trailer_hp = 20.0
			_a.burst_tire(0)
			_seen["before"] = [h.hp, h.trailer_hp, _a.is_tire_burst(0)]
			_onto(_a, _repair)
			_pc.cooldown[0] = 600
			_pc.cooldown[1] = 300
			_onto(_c, _power)
		12:
			var h := TruckHealth.of(_a)
			_seen["after"] = [h.hp, h.trailer_hp, _a.is_tire_burst(0), _repair.available()]
			_seen["power"] = [_pc.cooldown[0], _pc.cooldown[1]]
			# le 2e camion arrive juste apres : rien a prendre
			_a.reset_to(Transform3D(Basis.IDENTITY, Vector3(5000.0, 1.0, 0.0)))
			var hb := TruckHealth.of(_b)
			hb.hp = 50.0
			_onto(_b, _repair)
			_hud.flash("RÉPARATION", TrackPickup.color_of(TrackPickup.Kind.REPAIR))
			_seen["flash"] = _hud.flash_text()
		20:
			_seen["b"] = TruckHealth.of(_b).hp
			_b.reset_to(Transform3D(Basis.IDENTITY, Vector3(5100.0, 1.0, 0.0)))
		200:
			_seen["back"] = _repair.available()
			_seen["flash_after"] = _hud.flash_text()


func _test_finish() -> void:
	for k in TRACKS.size():
		var sp: Array = _seen.get("spread%d" % k, [0.0, 0, 1.0, 1])
		check("E %s : epars (ecart > 20 m, decalages varies, sur la chaussee, loin des pieges)" % TRACKS[k].get_file(),
			float(sp[0]) > 20.0 and int(sp[1]) >= 6 and float(sp[2]) <= 0.01 and int(sp[3]) == 0, str(sp))
	check("E memes places a chaque construction", bool(_seen.get("twin", false)))
	check("A 12 bonus par circuit (6 reparations, 6 recharges)",
		_seen.get("kinds") == [[12, 6, 6], [12, 6, 6], [12, 6, 6]], str(_seen.get("kinds")))
	var a: Array = _seen.get("after", [0.0, 0.0, true, true])
	check("B reparation : +40 PV, remorque +30, pneus neufs, bonus pris",
		is_equal_approx(float(a[0]), 80.0) and is_equal_approx(float(a[1]), 50.0) and not bool(a[2]) and not bool(a[3]),
		"%s -> %s" % [_seen.get("before"), a])
	check("B un 2e camion juste apres : rien", is_equal_approx(float(_seen.get("b", 0.0)), 50.0), str(_seen.get("b")))
	check("B le bonus revient", bool(_seen.get("back", false)))
	check("C recharge : le missile pret, le laser garde sa recharge", _seen.get("power") == [0, 300] \
		or (_seen.get("power") as Array)[0] == 0 and int((_seen.get("power") as Array)[1]) > 280, str(_seen.get("power")))
	check("D HUD : message affiche puis efface", String(_seen.get("flash", "")) == "RÉPARATION"
		and String(_seen.get("flash_after", "x")) == "", "%s / %s" % [_seen.get("flash"), _seen.get("flash_after")])
