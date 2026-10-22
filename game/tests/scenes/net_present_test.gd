extends PhysicsTest

## Moins de latence en ligne (2026-10-22 : « le moins de latence possible, le
## plus fluide, inspire-toi du netcode d'autres jeux ») :
##   A. extrapolation sur la courbe : un camion a 25 m/s dans un virage de
##      60 m de rayon, 16 ticks plus tard (~ l'avance a 200 ms d'aller-retour),
##      a moins de 5 cm de sa vraie place ;
##      l'ancienne (tout droit) s'en ecartait de plus de 20 cm ;
##   B. autres camions au present (facon Rocket League) : l'aller-retour se
##      mesure sur l'ack des snapshots ; ils sont montres a l'heure du host +
##      cet aller-retour (borne a MAX_LEAD_TICKS) ; present_part = 0 : l'ancien
##      rendu, dans le passe ;
##   C. bonus pris par SON camion chez un client : il disparait tout de suite,
##      une seule annonce meme quand le host confirme ; un camion distant ne
##      le prend pas ici ; sans confirmation du host, il revient.

const R := 60.0
const V := 25.0

var _pk: TrackPickup
var _pk2: TrackPickup
var _mine: Truck
var _other: Truck
var _taken := 0
var _back_ok := false


func _test_setup() -> void:
	duration_ticks = TrackPickup.PREDICT_TICKS + 20
	_test_curve()
	_test_present()
	_mine = _truck(Vector3(5000, 0, 5000))
	_other = _truck(Vector3(5100, 0, 5000))
	_other.set_net_puppet(true, true)
	_pk = _pickup()
	_pk2 = _pickup()
	_pk.taken.connect(func(_t: Truck, _p: TrackPickup) -> void: _taken += 1)
	_pk._on_body_entered(_other)
	var puppet_ignored := _pk.available()
	_pk._on_body_entered(_mine)
	var gone := not _pk.available()
	_pk.net_take(_mine)
	check("C bonus pris par son camion : tout de suite, une seule annonce, pas par un distant",
		puppet_ignored and gone and _taken == 1, "distant ignore %s, disparu %s, annonces %d" % [puppet_ignored, gone, _taken])
	# le second : pris ici, jamais confirme par le host
	_pk2._on_body_entered(_mine)


func _test_tick(t: int) -> void:
	if t == TrackPickup.PREDICT_TICKS + 5:
		_back_ok = _pk2.available() and not _pk.available()


func _test_finish() -> void:
	check("C sans confirmation du host, il revient (le confirme reste pris)", _back_ok, str(_back_ok))


func _truck(p: Vector3) -> Truck:
	var t := (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
	t.transform = Transform3D(Basis.IDENTITY, p)
	add_child(t)
	t.freeze = true
	return t


func _pickup() -> TrackPickup:
	var pk := TrackPickup.new()
	pk.net_mirror = true
	add_child(pk)
	return pk


func _test_curve() -> void:
	# virage a gauche autour de (0, 0, 0) ; depart en (R, 0, 0), cap -Z
	var w := V / R
	var s := TruckState.new()
	s.position = Vector3(R, 0, 0)
	s.linear_velocity = Vector3(0, 0, -V)
	s.angular_velocity = Vector3(0, w, 0)
	var out := TruckState.new()
	out.extrapolate(s, 16.0, 1.0 / 60.0)
	var a := w * 16.0 / 60.0
	var truth := Vector3(R * cos(a), 0, -R * sin(a))
	var straight := s.position + s.linear_velocity * 16.0 / 60.0
	var e := out.position.distance_to(truth)
	var e_old := straight.distance_to(truth)
	check("A extrapolation sur la courbe : < 5 cm (tout droit : > 20 cm)", e < 0.05 and e_old > 0.2,
		"%.3f m (tout droit %.3f m)" % [e, e_old])


## Snapshot d'un camion au tick du host `tick`, qui acquitte la frame `ack`.
func _snap(tick: int, ack: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(NetRace.SNAPSHOT_HEADER + TruckState.SIZE + 1)
	b.encode_u32(0, tick)
	b.encode_u8(4, 1)
	b.encode_u16(5, posmod(ack, 65536))
	b.encode_u8(7, 1)
	TruckState.new().write_to(b, NetRace.SNAPSHOT_HEADER)
	return b


func _test_present() -> void:
	var nr := NetRace.new()
	nr.set("_local", 0)
	# host en avance de 1000 ticks ; notre frame revient acquittee 6 ticks
	# apres son envoi
	for k in 30:
		nr.receive_snapshot(_snap(1000 + k, k - 7), k)
	var at := nr.render_tick(30)
	var lead := nr.lead_ticks()
	nr.present_part = 0.0
	var past := nr.render_tick(30)
	nr.present_part = 1.0
	# 40 ticks d'aller-retour : borne
	var far := NetRace.new()
	far.set("_local", 0)
	for k in 200:
		far.receive_snapshot(_snap(1000 + k, k - 41), k)
	var capped := far.render_tick(200) - (200.0 + 1000.0)
	check("B au present : heure du host + aller-retour mesure, borne, l'ancien rendu dans le passe",
		absf(lead - 6.0) < 0.01 and absf(at - (30.0 + 1000.0 + 6.0)) < 0.01 and past < 30.0 + 1000.0
		and absf(capped - NetRace.MAX_LEAD_TICKS) < 0.5,
		"aller-retour %.2f, present %.2f, passe %.2f, borne %.2f" % [lead, at, past, capped])
	nr.free()
	far.free()
