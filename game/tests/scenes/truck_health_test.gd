extends PhysicsTest

## Points de vie du camion (TruckHealth, 2026-10-02) :
##   A. choc frontal contre un mur a 20 m/s (72 km/h) : -5 PV (le maximum),
##      en un seul impact ;
##   B. le nez entre de biais (30 deg) a 20 m/s, 10 m/s vers le mur : -3 PV
##      au premier impact (degats proportionnels a la vitesse normale) ;
##   C. frottement : le nez entre a 8 deg, ~2,8 m/s vers le mur : -1 PV (sous
##      ~5 deg, c'est la remorque, plus large, qui toucherait d'abord) ;
##   D. marche arriere a 12 m/s dans un mur, seule la remorque touche :
##      impact signale, aucun PV perdu par la TETE (la remorque a ses propres
##      PV, truck_damage_split_test) ;
##   E. 0 PV : explosion, epave gelee 3 s (180 ticks) meme plein gaz, aucun
##      degat de plus, puis reapparition a l'endroit fourni, 100 PV.
## Vitesses posees au tick 0 (CLAUDE.md §10 b).

const KILL_AT := 5

var _a: Truck
var _b: Truck
var _c: Truck
var _d: Truck
var _e: Truck
var _events: Dictionary = {}
var _d_impacts: Array = []
var _frames: Dictionary = {}
var _e_spot: Transform3D
var _e_wreck_pos: Vector3
var _e_moved: float = 0.0
var _e_destroyed: int = 0
var _e_respawned: int = 0
var _e_frozen: bool = false
var _e_explosion: bool = false
var _e_after: Array = []


func _test_setup() -> void:
	duration_ticks = 260
	add_floor(1200.0)
	# A : mur en travers, 40 m devant
	_a = _spawn(Vector3(0.0, 0.0, 0.0), 0.0, 20.0)
	_wall(Vector3(30.0, 6.0, 2.0), Vector3(0.0, 3.0, -40.0))
	# B et C : long mur a droite, nez tourne vers lui
	_b = _spawn(Vector3(100.0, 0.0, 0.0), 30.0, 20.0)
	_wall(Vector3(2.0, 6.0, 300.0), Vector3(110.0, 3.0, -100.0))
	_c = _spawn(Vector3(200.0, 0.0, 0.0), 8.0, 20.0)
	_wall(Vector3(2.0, 6.0, 300.0), Vector3(204.0, 3.0, -100.0))
	# D : recule vers un mur (la remorque en premier)
	_d = _spawn(Vector3(300.0, 0.0, 0.0), 0.0, -12.0)
	_wall(Vector3(30.0, 6.0, 2.0), Vector3(300.0, 3.0, 32.0))
	_d.wall_impact.connect(func(speed: float, on_trailer: bool) -> void: _d_impacts.append([on_trailer, speed]))
	# E : detruit, reapparait ici
	_e = _spawn(Vector3(400.0, 0.0, 0.0), 0.0, 0.0)
	_e_spot = Transform3D(Basis.IDENTITY, Vector3(450.0, 1.0, 0.0))
	var eh := TruckHealth.of(_e)
	eh.respawn_provider = func(_t: Truck) -> Transform3D: return _e_spot
	eh.destroyed.connect(func() -> void: _e_destroyed += 1)
	eh.respawned.connect(func() -> void: _e_respawned += 1)
	for t: Truck in [_a, _b, _c, _d, _e]:
		_events[t] = []
		var h := TruckHealth.of(t)
		h.damaged.connect(func(amount: float, source: StringName) -> void: _events[t].append([amount, source]))


## Camion pose a `pos`, nez tourne de `yaw_deg` vers +X, lance a `speed`
## (m/s, < 0 : en arriere).
func _spawn(pos: Vector3, yaw_deg: float, speed: float) -> Truck:
	var t := TruckTestUtil.spawn_truck(self, pos, Vector3(0.0, -yaw_deg, 0.0))
	t.linear_velocity = -t.global_basis.z * speed
	_frames[t] = InputFrame.new()
	return t


func _wall(size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	body.position = pos
	add_child(body)


func _test_tick(t: int) -> void:
	for tr: Truck in [_a, _b, _c, _d, _e]:
		var f: InputFrame = _frames[tr]
		f.tick = t
		# E plein gaz pendant toute l'epave : il ne doit pas bouger
		f.throttle = 1.0 if tr == _e and t > KILL_AT else 0.0
		tr.set_input(f)
	var eh := TruckHealth.of(_e)
	if t == KILL_AT:
		eh.damage(60.0, &"test")
		eh.damage(60.0, &"test")
	if t == KILL_AT + 2:
		_e_wreck_pos = _e.global_position
		_e_frozen = _e.is_wrecked() and _e.freeze
		_e_explosion = not find_children("Explosion*", "", true, false).is_empty()
		eh.damage(10.0, &"pendant l'epave")
	if t > KILL_AT + 2 and t < KILL_AT + 170:
		_e_moved = maxf(_e_moved, _e.global_position.distance_to(_e_wreck_pos))
	if t == KILL_AT + 200:
		_e_after = [eh.hp, _e.is_wrecked(), _e.freeze, _e.global_position.distance_to(_e_spot.origin)]


func _first(t: Truck) -> float:
	var ev: Array = _events[t]
	return float(ev[0][0]) if not ev.is_empty() else 0.0


func _test_finish() -> void:
	for tr: Truck in [_a, _b, _c, _d]:
		print("  INFO   %s : PV %.0f, degats %s" % [tr.name, TruckHealth.of(tr).hp, _events[tr]])
	print("  INFO   D : impacts %s" % [_d_impacts])
	check("A choc frontal a 72 km/h : -5 PV, un seul impact", _events[_a].size() == 1 and _first(_a) == 5.0,
		str(_events[_a]))
	check("B nez de biais (10 m/s vers le mur) : -3 PV au premier impact", _first(_b) == 3.0, str(_events[_b]))
	check("C frottement (~2,8 m/s vers le mur) : -1 PV au premier impact", _first(_c) == 1.0, str(_events[_c]))
	var trailer_hit := false
	var front_hit := false
	for im: Array in _d_impacts:
		trailer_hit = trailer_hit or im[0]
		front_hit = front_hit or not im[0]
	check("D la remorque touche le mur", trailer_hit and not front_hit, str(_d_impacts))
	check("D la tete ne perd aucun PV", TruckHealth.of(_d).hp == 100.0 and _events[_d].is_empty(),
		"%.0f PV" % TruckHealth.of(_d).hp)
	check("E 0 PV : epave gelee, explosion", _e_frozen and _e_explosion and _e_destroyed == 1)
	check("E epave : aucun degat de plus", _events[_e].size() == 2, str(_events[_e]))
	check_below("E epave immobile 3 s, meme plein gaz (m)", _e_moved, 0.01)
	check("E reapparait apres 3 s : 100 PV, plus gele, a l'endroit fourni",
		_e_respawned == 1 and _e_after.size() == 4 and _e_after[0] == 100.0 and not _e_after[1]
		and not _e_after[2] and float(_e_after[3]) < 3.0, str(_e_after))
