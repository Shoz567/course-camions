extends PhysicsTest

## Remorque larguee et camion qui l'a larguee (2026-10-01, « je passe a
## travers ma propre remorque »). Elle reste traversable owner_pass_ticks
## (~1 s, le temps de s'eloigner), puis devient un obstacle pour lui aussi,
## jamais tant qu'il est dedans.
##   A. lance a 8 m/s, largue, s'eloigne en roue libre, freine a partir de
##      BRAKE_AT puis recule droit sur elle (a l'arret, freiner = reculer) : il
##      la percute (son origine ne depasse jamais la sellette de la remorque),
##      sans penalite (pas de cargo_hit) ;
##   B. largue a 0,5 m/s, sans aucune commande : il s'arrete dans son volume.
##      Elle reste traversable, et le camion n'est jamais projete (< 1 m/s).
## Vitesses posees au tick 0 (CLAUDE.md §10 b).

const DROP_AT := 10
const BRAKE_AT := 40
const REVERSE_AT := 130

var _a: Truck
var _b: Truck
var _frames: Dictionary = {}
var _trailers: Dictionary = {}
var _a_solid_at: int = -1
var _a_hit: bool = false
var _a_through: float = -INF
var _b_max_v: float = 0.0
var _b_solid: bool = false


func _test_setup() -> void:
	duration_ticks = REVERSE_AT + 420
	add_floor(2000.0)
	_a = _spawn(Vector3(0.0, 0.0, 600.0), 8.0)
	_b = _spawn(Vector3(100.0, 0.0, 600.0), 0.5)
	for t: Truck in [_a, _b]:
		(t.get_node("Cargo") as TruckCargo).dropped.connect(func(tr: DetachedTrailer) -> void: _trailers[t] = tr)
	_a.cargo_hit_taken.connect(func() -> void: _a_hit = true)


func _spawn(p: Vector3, v: float) -> Truck:
	var t := TruckTestUtil.spawn_truck(self, p)
	t.linear_velocity = Vector3(0.0, 0.0, -v)
	_frames[t] = InputFrame.new()
	return t


func _drive(t: Truck, tick: int, throttle: float, brake: float) -> void:
	var f: InputFrame = _frames[t]
	f.tick = tick
	f.throttle = throttle
	f.brake = brake
	f.cargo = tick == DROP_AT
	t.set_input(f)


func _test_tick(t: int) -> void:
	_drive(_a, t, 0.0, 1.0 if t >= BRAKE_AT else 0.0)
	_drive(_b, t, 0.0, 0.0)
	var ta := _trailers.get(_a) as DetachedTrailer
	if ta != null and is_instance_valid(ta):
		if _a_solid_at < 0 and ta.is_solid_for_owner():
			_a_solid_at = t - DROP_AT
		if t >= REVERSE_AT:
			# l'avant est en -Z : en reculant, le camion va vers +Z, vers la remorque
			_a_through = maxf(_a_through, _a.global_position.z - ta.global_position.z)
	var tb := _trailers.get(_b) as DetachedTrailer
	if tb != null and is_instance_valid(tb) and t > DROP_AT + 5:
		_b_max_v = maxf(_b_max_v, _b.linear_velocity.length())
		_b_solid = _b_solid or tb.is_solid_for_owner()


func _test_finish() -> void:
	check("A et B ont largue", _trailers.has(_a) and _trailers.has(_b))
	print("  INFO   A : obstacle pour lui %d ticks apres le largage ; origine du camion a %.1f m de la sellette (max, > 0 = traversee)"
		% [_a_solid_at, _a_through])
	check("A : obstacle pour lui apres son delai", _a_solid_at >= 60, "ticks=%d" % _a_solid_at)
	check_below("A : en reculant, ne la traverse pas (m)", _a_through, 0.0)
	check("A : jamais penalise par sa propre remorque", not _a_hit)
	check("B : reste dedans, elle reste traversable", not _b_solid)
	check_below("B : jamais projete (m/s)", _b_max_v, 1.0)
	check_finite("A : position finie", _a.global_position)
