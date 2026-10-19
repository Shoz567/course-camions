extends PhysicsTest

## Moins de delai en ligne (2026-10-19 : « le delai est legerement
## perceptible ») :
##   A. file d'inputs du host adaptative : liaison reguliere, la cible descend
##      a 1 frame (~16 ms de moins) ; une file vide, elle remonte ;
##   B. retard de rendu des autres camions : 1 tick sur une liaison a 60 Hz
##      sans gigue, plus avec de la gigue ou 20 Hz ;
##   C. pouvoirs du joueur local chez un client : le tir part a l'appui
##      (predict), l'annonce du host qui suit ne le rejoue pas.

var _a: Truck
var _b: Truck
var _pa: TruckPowers
var _missiles: int = 0
var _seen: Dictionary = {}


func _test_setup() -> void:
	duration_ticks = 200
	add_floor(2000.0)
	_a = TruckTestUtil.spawn_truck(self, Vector3(0.0, 0.0, 0.0))
	_b = TruckTestUtil.spawn_truck(self, Vector3(0.0, 0.0, -40.0))
	for t in [_a, _b]:
		(t as Truck).add_to_group(TruckPowers.TARGETS)
	_pa = TruckPowers.setup(_a, PowerCatalog.Id.MISSILE, -1, true)
	_pa.predict = true
	child_entered_tree.connect(func(n: Node) -> void:
		if n is PowerMissile:
			_missiles += 1)


func _packet(t: int) -> PackedByteArray:
	var f := InputFrame.new()
	f.tick = t
	var b := PackedByteArray()
	b.resize(InputFrame.SIZE)
	f.write_to(b, 0)
	return b


func _test_tick(t: int) -> void:
	var f := InputFrame.new()
	f.power_left = t == 20
	_a.set_input(f)
	match t:
		22:
			_seen["cool_now"] = _pa.seconds_left(0)
			_seen["missiles_now"] = _missiles
		40:
			# l'annonce du host arrive apres l'aller-retour
			_pa.net_fire(0, _b)
			_seen["missiles_after_host"] = _missiles


func _test_finish() -> void:
	_test_queue()
	_test_interp()
	check("pouvoir local : le missile part a l'appui, recharge lancee", int(_seen.get("missiles_now", 0)) == 1
		and int(_seen.get("cool_now", 0)) == 15, "%s missile(s), %s s" % [_seen.get("missiles_now"), _seen.get("cool_now")])
	check("annonce du host : pas de second missile", int(_seen.get("missiles_after_host", 0)) == 1)


func _test_queue() -> void:
	var src := RemoteInputSource.new()
	var tick := 1000
	for k in 2:
		src.push_packet(_packet(tick))
		tick += 1
	# liaison reguliere : une frame par tick
	var n := RemoteInputSource.ADAPT_TICKS * (RemoteInputSource.ADAPT_CLEAN_WINDOWS + 1) + 40
	for k in n:
		src.push_packet(_packet(tick))
		tick += 1
		src.poll(k)
	check("liaison reguliere : cible a 1 frame, file a 1", src.target == RemoteInputSource.MIN_TARGET
		and src.queued() <= 1, "cible %d file %d" % [src.target, src.queued()])
	# deux paquets en retard : la file se vide, la cible remonte
	for k in RemoteInputSource.ADAPT_TICKS + 5:
		if k != 10 and k != 11:
			src.push_packet(_packet(tick))
			tick += 1
		src.poll(n + k)
	check("file vide : la cible remonte", src.target == RemoteInputSource.MIN_TARGET + 1, "cible %d" % src.target)
	src.queue_free()


func _test_interp() -> void:
	var net := NetRace.new()
	net.set("_interval", 1.0)
	for k in 60:
		net.call("_track_clock", 5.0)
	var calm := net.interp_ticks()
	for k in 60:
		net.call("_track_clock", 5.0 + (1.5 if k % 2 == 0 else -1.5))
	var shaky := net.interp_ticks()
	net.set("_interval", 3.0)
	net.call("_track_clock", 5.0)
	var slow := net.interp_ticks()
	check("rendu des autres : 1 tick a 60 Hz regulier, plus avec gigue ou a 20 Hz",
		is_equal_approx(calm, 1.0) and shaky >= 3.0 and slow >= 3.0, "%s / %s / %s" % [calm, shaky, slow])
	net.free()
