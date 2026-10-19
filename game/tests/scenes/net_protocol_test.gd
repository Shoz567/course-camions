extends PhysicsTest

## Protocole reseau, sans reseau (phase 6, docs/NETCODE.md) :
##   - TruckState : 36 octets, aller-retour fidele (position exacte,
##     orientation a moins de 0,3 deg, vitesses en float16, angles a 0,4 deg,
##     PV, cargo, pneus creves, klaxon) ;
##   - snapshot : section des obstacles (remorques larguees, carcasses) ;
##   - snapshot : en-tete + 32 o par camion ; bande passante montante du host
##     a 4 joueurs, en-tetes ENet compris : a 60 Hz (le moins de delai) et a
##     20 Hz (connexion lente, sous l'objectif de 128 kbps) ;
##   - RemoteInputSource : chaque frame sert une fois, les fronts (reset,
##     klaxon, cargo) ne sont ni perdus ni repetes, paquets douteux refuses ;
##   - NetRace cote client : interpolation entre deux snapshots, extrapolation
##     bornee, horloge du host.

## En-tetes par datagramme (UDP + IP + ENet), NETCODE.md §3.
const PACKET_OVERHEAD := 48


func _test_setup() -> void:
	duration_ticks = 1


func _test_finish() -> void:
	_test_truck_state()
	_test_quaternions()
	_test_bandwidth()
	_test_remote_input()
	_test_interpolation()


func _state(pos: Vector3, yaw: float, v: Vector3) -> TruckState:
	var s := TruckState.new()
	s.position = pos
	s.rotation = Quaternion(Vector3.UP, yaw) * Quaternion(Vector3.RIGHT, 0.2)
	s.linear_velocity = v
	s.angular_velocity = Vector3(0.1, -1.3, 0.05)
	s.steer_deg = -21.5
	s.trailer_angle_deg = 33.0
	s.flags = TruckState.FLAG_BOOSTING | TruckState.FLAG_TRAILER_DETACHED | TruckState.FLAG_HONK \
		| (0b100101 << TruckState.FLAG_TIRES_SHIFT)
	s.hp = 63.0
	s.trailer_hp = 140.0
	s.cargo_charge = 0.4
	s.cargo_locked = true
	return s


func _test_truck_state() -> void:
	var a := _state(Vector3(1234.5678, -3.25, -987.125), 2.4, Vector3(41.7, -2.3, -18.9))
	var buf := PackedByteArray()
	buf.resize(TruckState.SIZE + 3)
	a.write_to(buf, 3)
	var b := TruckState.new()
	b.read_from(buf, 3)
	check("TruckState : 36 octets", TruckState.SIZE == 36)
	check("position exacte (float32)", a.position.is_equal_approx(b.position), "%s -> %s" % [a.position, b.position])
	var angle := rad_to_deg(a.rotation.angle_to(b.rotation))
	check_below("orientation (deg d'erreur)", angle, 0.3)
	check_below("vitesse lineaire (m/s d'erreur)", (a.linear_velocity - b.linear_velocity).length(), 0.05)
	check_below("vitesse angulaire (rad/s d'erreur)", (a.angular_velocity - b.angular_velocity).length(), 0.005)
	check_below("braquage (deg d'erreur)", absf(a.steer_deg - b.steer_deg), 0.4)
	check_below("angle de remorque (deg d'erreur)", absf(a.trailer_angle_deg - b.trailer_angle_deg), 0.4)
	check("flags (boost, remorque, klaxon, pneus FL, RL, remorque droite)", a.flags == b.flags and b.tires() == 0b100101,
		"%d -> %d" % [a.flags, b.flags])
	check("PV de la tete et de la remorque", b.hp == 63.0 and b.trailer_hp == 140.0, "%.0f %.0f" % [b.hp, b.trailer_hp])
	check_near("recharge du cargo", b.cargo_charge, 0.4, 0.01)
	check("verrou du depart", b.cargo_locked)


## Smallest-three sur des cas limites : identite, q et -q, demi-tours, la
## plus grande composante a chaque place.
func _test_quaternions() -> void:
	var worst := 0.0
	var cases: Array[Quaternion] = [Quaternion.IDENTITY, Quaternion(0, 0, 0, -1),
		Quaternion(Vector3.UP, PI), Quaternion(Vector3.RIGHT, PI), Quaternion(Vector3.FORWARD, PI),
		Quaternion(Vector3(1, 1, 1).normalized(), 2.1), Quaternion(Vector3(-1, 0.3, 0.2).normalized(), -2.9)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 200:
		var axis := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		if axis.length_squared() < 1e-4:
			continue
		cases.append(Quaternion(axis.normalized(), rng.randf_range(-PI, PI)))
	for q in cases:
		var back := TruckState.decode_quaternion(TruckState.encode_quaternion(q))
		worst = maxf(worst, rad_to_deg(q.normalized().angle_to(back)))
	check_below("quaternion smallest-three : pire erreur sur %d rotations (deg)" % cases.size(), worst, 0.3)


func _test_bandwidth() -> void:
	# taille seule (encode_snapshot lit de vrais camions : course en ligne)
	var size := NetRace.SNAPSHOT_HEADER + 4 * TruckState.SIZE + 1
	check("snapshot a 4 camions, sans obstacle qui bouge : 8 + 4 x 36 + 1 octets", size == 153, str(size))
	var kbps: Array[float] = []
	for ticks: int in [1, NetSessionNode.SNAPSHOT_TICKS_LOW_BANDWIDTH]:
		var per_s := 60.0 / float(ticks)
		kbps.append((size + PACKET_OVERHEAD) * per_s * 3.0 * 8.0 / 1000.0)
	print("  INFO   montant du host vers 3 clients : %.0f kbps a 60 Hz, %.0f kbps a 20 Hz" % [kbps[0], kbps[1]])
	check_below("60 Hz : montant du host a 4 joueurs, en-tetes compris (kbps)", kbps[0], 300.0)
	# references de baseline.json (NETCODE.md §9), a +/- 10 %
	var ref_bytes: Variant = baseline("snapshot_bytes_per_truck")
	var ref_kbps: Variant = baseline("uplink_kbps_4_players")
	if ref_bytes != null and ref_kbps != null:
		check("baseline : octets par camion", TruckState.SIZE == int(ref_bytes), "%d / %s" % [TruckState.SIZE, ref_bytes])
		check_near("baseline : montant du host a 4 joueurs (kbps)", kbps[0], float(ref_kbps), float(ref_kbps) * 0.1)
	check_below("20 Hz : montant du host a 4 joueurs, en-tetes compris (kbps)", kbps[1], 128.0)
	# un paquet d'inputs par tick, 3 frames (redondance)
	var up := (InputFrame.SIZE * RemoteInputSource.BATCH + PACKET_OVERHEAD) * 60.0 * 8.0 / 1000.0
	check_below("montant d'un client : 3 frames par tick (kbps)", up, 40.0)

func _packet(frames: Array[InputFrame]) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(frames.size() * InputFrame.SIZE)
	for i in frames.size():
		frames[i].write_to(b, i * InputFrame.SIZE)
	return b


func _frame(t: int, steer: float, reset: bool = false, honk: bool = false) -> InputFrame:
	var f := InputFrame.new()
	f.tick = t
	f.steer = steer
	f.throttle = 1.0
	f.reset = reset
	f.honk = honk
	return f


func _test_remote_input() -> void:
	var src := RemoteInputSource.new()
	add_child(src)
	# 3 frames, un reset au milieu ; le paquet arrive deux fois (doublon)
	var pkt := _packet([_frame(100, 0.5), _frame(101, 0.5, true), _frame(102, -0.25)])
	check("paquet de 3 frames accepte", src.push_packet(pkt))
	src.push_packet(pkt)
	check("doublon ignore (meme ticks)", src.queued() == 3 and src.duplicate_frames == 3,
		"file=%d doublons=%d" % [src.queued(), src.duplicate_frames])
	var resets := 0
	var steers := []
	for k in 5:
		var f := src.poll(k)
		resets += 1 if f.reset else 0
		steers.append(snappedf(f.steer, 0.01))
	check("reset : vrai une seule fois", resets == 1, str(resets))
	check("ack : la frame consommee au tick precedent, invalide apres une file vide",
		src.applied_tick == 102 and not src.applied_valid, "%d %s" % [src.applied_tick, src.applied_valid])
	check("file vide : derniere consigne tenue", steers == [0.5, 0.5, -0.25, -0.25, -0.25], str(steers))
	check("paquet mal forme refuse (5 octets)", not src.push_packet(PackedByteArray([1, 2, 3, 4, 5])))
	check("paquet trop long refuse (4 frames)", not src.push_packet(_packet([_frame(1, 0), _frame(2, 0),
		_frame(3, 0), _frame(4, 0)])))
	# rafale apres un trou (15 frames) : au-dela de 12, la file revient a la
	# cible ; le klaxon et le boost d'une frame sautee sont reportes
	var burst: Array[InputFrame] = []
	for t in range(103, 118):
		var bf := _frame(t, 0.1, false, t == 103)
		bf.boost = t == 104
		burst.append(bf)
	for k in 5:
		src.push_packet(_packet(burst.slice(k * 3, k * 3 + 3)))
	var honks := 0
	var boosts := 0
	var n := 0
	while src.queued() > 0:
		var bf := src.poll(200 + n)
		honks += 1 if bf.honk else 0
		boosts += 1 if bf.boost else 0
		n += 1
	check("rafale : file ramenee a la cible, klaxon et boost reportes",
		n == RemoteInputSource.TARGET_QUEUE and honks == 1 and boosts == 1,
		"frames=%d klaxons=%d boosts=%d sautees=%d" % [n, honks, boosts, src.dropped_frames])
	# une frame d'avance de trop, tenue : une seule sautee apres SLOW_DROP_TICKS
	src.clear()
	var dropped := src.dropped_frames
	var next_tick := 300
	for k in 3:
		src.push_packet(_packet([_frame(next_tick, 0.0)]))
		next_tick += 1
	for k in RemoteInputSource.SLOW_DROP_TICKS + 5:
		src.push_packet(_packet([_frame(next_tick, 0.0)]))
		next_tick += 1
		src.poll(k)
	check("avance de trop tenue : une seule frame sautee, file a la cible",
		src.dropped_frames - dropped == 1 and src.queued() == RemoteInputSource.TARGET_QUEUE,
		"sautees=%d file=%d" % [src.dropped_frames - dropped, src.queued()])	# tick qui boucle (u16) : 65535 puis 0 est bien plus recent
	src.clear()
	src.push_packet(_packet([_frame(65535, 0.0)]))
	check("ticks modulo 65536 : 0 apres 65535", src.push_packet(_packet([_frame(0, 0.7)])) and src.queued() == 2)
	src.queue_free()


func _snap(tick: int, x: float, vx: float) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(NetRace.SNAPSHOT_HEADER + TruckState.SIZE + 1 + NetRace.OBJECT_SIZE)
	b.encode_u32(0, tick)
	b.encode_u8(4, 1)
	# un obstacle (id 7) qui glisse avec le camion, 2 m derriere
	var o := NetRace.SNAPSHOT_HEADER + TruckState.SIZE
	b.encode_u8(o, 1)
	b.encode_u16(o + 1, 7)
	b.encode_float(o + 3, x - 2.0)
	b.encode_float(o + 7, 0.0)
	b.encode_float(o + 11, 0.0)
	b.encode_u32(o + 15, TruckState.encode_quaternion(Quaternion.IDENTITY))
	var s := TruckState.new()
	s.position = Vector3(x, 0, 0)
	s.linear_velocity = Vector3(vx, 0, 0)
	s.write_to(b, NetRace.SNAPSHOT_HEADER)
	return b


func _test_interpolation() -> void:
	var nr := NetRace.new()
	# host en avance de 1000 ticks ; snapshots tous les 3 ticks, 60 m/s
	nr.receive_snapshot(_snap(1000, 0.0, 60.0), 0)
	nr.receive_snapshot(_snap(1003, 3.0, 60.0), 3)
	nr.receive_snapshot(_snap(1006, 6.0, 60.0), 6)
	check_near("horloge du host (decalage en ticks)", nr.host_offset(), 1000.0, 0.01)
	var out := TruckState.new()
	nr.sample(0, 1004.0, out)
	check_near("interpole entre deux snapshots (m)", out.position.x, 4.0, 0.01)
	nr.sample(0, 1010.0, out)
	check_near("extrapole 4 ticks par la vitesse (m)", out.position.x, 10.0, 0.05)
	nr.sample(0, 1100.0, out)
	check_near("extrapolation bornee a 15 ticks, puis gel (m)", out.position.x,
		6.0 + 60.0 * NetRace.EXTRAPOLATE_MAX_TICKS / 60.0, 0.05)
	# 10 snapshots perdus d'affilee (NETCODE.md §9) : extrapolation bornee, gel,
	# puis reprise propre (interpolation) des que le suivant arrive
	nr.sample(0, 1030.0, out)
	var frozen := out.position.x
	nr.receive_snapshot(_snap(1036, 36.0, 60.0), 36)
	nr.sample(0, 1030.0, out)
	check("10 snapshots perdus : gel a 15 ticks, puis reprise interpolee",
		is_equal_approx(frozen, 21.0) and absf(out.position.x - 30.0) < 0.01, "gel=%.2f reprise=%.2f" % [frozen, out.position.x])
	# snapshot en retard sur un plus recent, paquet tronque : ignores
	nr.receive_snapshot(_snap(1001, 99.0, 0.0), 9)
	var bad := _snap(1009, 99.0, 0.0)
	bad.resize(bad.size() - 1)
	nr.receive_snapshot(bad, 9)
	check("snapshot en retard ou tronque ignore", nr.snapshots_received == 4, str(nr.snapshots_received))
	check("tick du host -> tick local", nr.to_local_tick(1500) == 500, str(nr.to_local_tick(1500)))
	# obstacle : pose lue dans le snapshot, interpolee entre deux snapshots
	var crate := Node3D.new()
	add_child(crate)
	nr._objects[7] = crate
	nr._apply_objects(1004.0)
	check_near("obstacle : pose interpolee entre deux snapshots (m)", crate.global_position.x, 2.0, 0.01)
	crate.queue_free()
	nr.free()
