extends PhysicsTest

## handling_test (tache 1.10) : mesure les metriques de conduite de
## docs/METRICS.md, source de verite du track-designer.
##
##   make test      verifie les cibles de VEHICLE_SPEC §6 et VERROUILLE chaque
##                  metrique a +/- 10 % de baseline.json (ENVIRONMENT.md §5) ;
##                  une valeur de reference null saute le test.
##   make baseline  meme mesure, puis ECRIT les valeurs dans baseline.json.
##                  C'est le seul moyen de changer la reference : un geste
##                  explicite, jamais un effet de bord d'un test.
##
## Quatre camions independants, un par protocole (METRICS.md §3) :
##   A. plein gaz depuis l'arret : 0 -> 100 km/h, puis vitesse max stabilisee
##      (+/- 0,5 km/h sur 60 ticks), le long de l'axe avant ;
##   B. plein gaz jusqu'a 100 km/h, puis plein frein : distance jusqu'a l'arret ;
##   C. 50 km/h tenus, plein braquage : rayon du cercle decrit par le centre de
##      masse, en regime etabli ;
##   D. 80 km/h tenus, braquage croissant de 0 a 100 % en 600 ticks :
##      acceleration laterale max tenue sans deraper (derive < angle de
##      saturation des pneus), moyenne glissante sur 30 ticks.

const WRITE_FLAG := "--write-baseline"
const DRIFT_TOLERANCE := 0.10
const KEYS: PackedStringArray = ["top_speed_kmh", "accel_0_100_s", "braking_100_0_m",
	"min_turn_radius_m", "max_lateral_g"]
const DECIMALS: PackedInt32Array = [1, 2, 1, 1, 3]

const TURN_KMH := 50.0
const TURN_SETTLE := 300
const TURN_MEASURE := 120
const LAT_KMH := 80.0
const LAT_RAMP := 600
const LAT_WINDOW := 30

var _write: bool = false
var _a: Truck
var _b: Truck
var _c: Truck
var _d: Truck
var _fa: InputFrame = InputFrame.new()
var _fb: InputFrame = InputFrame.new()
var _fc: InputFrame = InputFrame.new()
var _fd: InputFrame = InputFrame.new()

var _t100: int = -1
var _speeds: PackedFloat32Array = []
var _top: float = -1.0
var _brake_from: Vector3
var _braking: bool = false
var _brake_dist: float = -1.0
var _turn_start: int = -1
var _radius_sum: float = 0.0
var _radius_n: int = 0
var _lat_start: int = -1
var _lat_window: PackedFloat32Array = []
var _lat_max: float = 0.0


func _test_setup() -> void:
	duration_ticks = 1500
	_write = OS.get_cmdline_user_args().has(WRITE_FLAG)
	add_floor(2600.0)
	_a = TruckTestUtil.spawn_truck(self, Vector3(0.0, 0.0, 1000.0))
	_b = TruckTestUtil.spawn_truck(self, Vector3(60.0, 0.0, 1000.0))
	_c = TruckTestUtil.spawn_truck(self, Vector3(600.0, 0.0, 0.0))
	_d = TruckTestUtil.spawn_truck(self, Vector3(-600.0, 0.0, 600.0))


## Gaz qui tient `kmh` le long de l'axe avant.
static func hold(t: Truck, kmh: float) -> float:
	return clampf((kmh - t.get_speed_kmh()) / 5.0, 0.0, 1.0)


func _test_tick(t: int) -> void:
	# A : plein gaz
	_fa.tick = t
	_fa.throttle = 1.0
	_a.set_input(_fa)
	var va := _a.get_speed_kmh()
	if _t100 < 0 and va >= 100.0:
		_t100 = t
	_speeds.append(va)
	if _top < 0.0 and _speeds.size() >= 60:
		var w := _speeds.slice(_speeds.size() - 60)
		var lo := w[0]
		var hi := w[0]
		for x in w:
			lo = minf(lo, x)
			hi = maxf(hi, x)
		if hi - lo <= 1.0 and va > 100.0:
			_top = (lo + hi) / 2.0

	# B : 0 -> 100 puis plein frein jusqu'a l'arret
	_fb.tick = t
	var vb := _b.get_speed_kmh()
	if not _braking and vb >= 100.0:
		_braking = true
		_brake_from = _b.global_position
	_fb.throttle = 0.0 if _braking else 1.0
	_fb.brake = 1.0 if _braking and _brake_dist < 0.0 else 0.0
	if _braking and _brake_dist < 0.0 and vb <= 0.5:
		_brake_dist = _b.global_position.distance_to(_brake_from)
	_b.set_input(_fb)

	# C : 50 km/h tenus, plein braquage, rayon en regime etabli
	_fc.tick = t
	_fc.throttle = hold(_c, TURN_KMH)
	if _turn_start < 0 and _c.get_speed_kmh() >= TURN_KMH - 1.0:
		_turn_start = t
	_fc.steer = 1.0 if _turn_start > 0 else 0.0
	_c.set_input(_fc)
	if _turn_start > 0 and t > _turn_start + TURN_SETTLE and t <= _turn_start + TURN_SETTLE + TURN_MEASURE:
		# vitesse du centre de masse / vitesse de rotation de sa trajectoire
		_radius_sum += _c.linear_velocity.length() / maxf(absf(_c.angular_velocity.y), 1e-4)
		_radius_n += 1

	# D : 80 km/h tenus, braquage croissant
	_fd.tick = t
	_fd.throttle = hold(_d, LAT_KMH)
	if _lat_start < 0 and _d.get_speed_kmh() >= LAT_KMH - 1.0:
		_lat_start = t
	_fd.steer = clampf(float(t - _lat_start) / LAT_RAMP, 0.0, 1.0) if _lat_start > 0 else 0.0
	_d.set_input(_fd)
	if _lat_start > 0:
		var lat := _d.linear_velocity.length() * absf(_d.angular_velocity.y) / TruckSpec.GRAVITY
		_lat_window.append(lat)
		if _lat_window.size() > LAT_WINDOW:
			_lat_window.remove_at(0)
		var slip := TruckTestUtil.sideslip_deg(_d)
		if _lat_window.size() == LAT_WINDOW and slip < _d.tuning.grip_slip_angle_deg:
			var s := 0.0
			for x in _lat_window:
				s += x
			_lat_max = maxf(_lat_max, s / LAT_WINDOW)


func _test_finish() -> void:
	var measured: Array[float] = [
		_top,
		_t100 / 60.0 if _t100 > 0 else -1.0,
		_brake_dist,
		_radius_sum / _radius_n if _radius_n > 0 else -1.0,
		_lat_max,
	]
	for i in KEYS.size():
		print("  MESURE %-20s %.3f" % [KEYS[i], measured[i]])
		if not check_above("%s mesure" % KEYS[i], measured[i], 0.0):
			return

	# Cibles de design (VEHICLE_SPEC §6). Le rayon de braquage n'en a pas.
	var tol := TruckSpec.TARGET_TOLERANCE
	check_near("cible : vitesse max (km/h)", measured[0], TruckSpec.TARGET_TOP_SPEED_KMH,
		TruckSpec.TARGET_TOP_SPEED_KMH * tol)
	check_near("cible : 0 -> 100 km/h (s)", measured[1], TruckSpec.TARGET_ACCEL_0_100_S,
		TruckSpec.TARGET_ACCEL_0_100_S * tol)
	check_below("cible : freinage 100 -> 0 (m)", measured[2], TruckSpec.TARGET_BRAKING_100_0_M)
	check_near("cible : adherence laterale (g)", measured[4], TruckSpec.TARGET_LATERAL_G,
		TruckSpec.TARGET_LATERAL_G * 0.10)

	if _write:
		_write_baseline(measured)
		return
	# Verrou : chaque metrique a +/- 10 % de la reference.
	for i in KEYS.size():
		var ref: Variant = require_baseline(KEYS[i])
		if ref == null:
			return
		check_near("baseline : %s" % KEYS[i], measured[i], float(ref), absf(float(ref)) * DRIFT_TOLERANCE)


## Remplace la valeur de chaque cle dans le texte de baseline.json : le reste
## du fichier (commentaires, ordre, lignes vides) ne bouge pas.
func _write_baseline(measured: Array[float]) -> void:
	var path := ProjectSettings.globalize_path(BASELINE_PATH)
	var text := FileAccess.get_file_as_string(path)
	for i in KEYS.size():
		var re := RegEx.create_from_string("(\"%s\"\\s*:\\s*)[^,\\n]+" % KEYS[i])
		var value := String.num(measured[i], DECIMALS[i])
		if re.search(text) == null:
			check("baseline.json contient la cle %s" % KEYS[i], false)
			return
		text = re.sub(text, "${1}" + value)
	var stamp := "%s, Godot %s" % [Time.get_date_string_from_system(), Engine.get_version_info().string]
	var re_stamp := RegEx.create_from_string("(\"handling_measured\"\\s*:\\s*)[^,\\n]+")
	text = re_stamp.sub(text, "${1}\"%s\"" % stamp)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if not check("baseline.json ouvert en ecriture", f != null, path):
		return
	f.store_string(text)
	f.close()
	print("  ECRIT  %s (%s)" % [path, stamp])
