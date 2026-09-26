extends PhysicsTest

## Perf physique (CLAUDE.md §10) : < 4 ms par tick a 4 camions.
##
## Nomme perf_* : le runner le lance SANS --fixed-fps, seul mode ou
## Performance.TIME_PHYSICS_PROCESS mesure quelque chose (SPIKE A2, A11). Il
## tourne donc en temps reel : 720 ticks = 12 s.
##
## 1 camion pendant 360 ticks, puis 4. Chaque camion roule et braque, forces et
## rayons actifs : c'est le cas de course. Les 60 premiers ticks de chaque phase
## (demarrage, arrivee des camions) ne sont pas mesures.
##
## Le budget se verifie partout ; la reference de baseline.json
## (physics_frame_ms_*) ne s'ecrit que sur la machine de reference
## (ENVIRONMENT.md §1) : ce test ne l'ecrit pas, il l'affiche.

const BUDGET_MS := 4.0
const PHASE := 360
const WARMUP := 60

var _trucks: Array[Truck] = []
var _frames: Array[InputFrame] = []
var _sum_1: float = 0.0
var _n_1: int = 0
var _sum_4: float = 0.0
var _n_4: int = 0


func _test_setup() -> void:
	duration_ticks = PHASE * 2
	add_floor(1200.0)
	_spawn(0)


func _spawn(i: int) -> void:
	_trucks.append(TruckTestUtil.spawn_truck(self, Vector3(-150.0 + i * 100.0, 0.0, 0.0)))
	_frames.append(InputFrame.new())


func _test_tick(t: int) -> void:
	if t == PHASE:
		for i in range(1, 4):
			_spawn(i)
	for i in _trucks.size():
		var f := _frames[i]
		f.tick = t
		f.throttle = clampf((60.0 - _trucks[i].get_speed_kmh()) / 5.0, 0.0, 1.0)
		f.steer = 0.6
		_trucks[i].set_input(f)
	var ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	if t > WARMUP and t < PHASE:
		_sum_1 += ms
		_n_1 += 1
	elif t > PHASE + WARMUP:
		_sum_4 += ms
		_n_4 += 1


func _test_finish() -> void:
	var ms_1 := _sum_1 / maxi(_n_1, 1)
	var ms_4 := _sum_4 / maxi(_n_4, 1)
	check_above("mesure effective (TIME_PHYSICS_PROCESS non nul)", ms_4, 0.0)
	check_below("physique a 4 camions (ms/tick)", ms_4, BUDGET_MS)
	print("  INFO   1 camion %.3f ms/tick ; 4 camions %.3f ms/tick ; machine : %s"
		% [ms_1, ms_4, OS.get_processor_name()])
	print("  INFO   baseline.json (machine de reference) : 1 camion %s, 4 camions %s"
		% [baseline("physics_frame_ms_1_truck"), baseline("physics_frame_ms_4_trucks")])
