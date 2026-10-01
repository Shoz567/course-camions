extends PhysicsTest

## Sensation de conduite en l'air et a la reception.
##
## Ne a la demande de l'utilisateur (2026-09-30) : « le camion semble trop
## rigide, surtout en l'air ». Trois situations, trois camions separes :
##
##   A. sortie de tremplin : decolle a 90 km/h en montant de 15,6 deg ;
##   B. plaque de saut : roule a 90 km/h, lance a 8 m/s vers le haut ;
##   C. choc en vol : a plat, coup de roulis de 1,5 rad/s en plein vol.
##
## Criteres de SENSATION (ce que « moins rigide » veut dire, en nombres) :
##   - A : le nez suit la trajectoire. Pente de la regression du tangage sur
##     l'angle de la trajectoire, en phase DESCENDANTE (apres le sommet, dans
##     les 70 premiers % du vol), >= 0,5 : ~0 pour un camion maintenu a
##     l'horizontale comme sur des rails, ~1 pour un nez qui plonge avec l'arc.
##     Deux metriques ont ete ecartees parce qu'un camion garde a plat les
##     reussissait : l'ecart moyen |tangage - pente| (3,8 deg, la trajectoire
##     passe par 0 au sommet), puis la pente sur tout le vol (0,59, le retour a
##     l'horizontale du decollage co-varie avec la trajectoire).
##   - B : reception absorbee par la suspension, pas « rattrapee » : pic de
##     deceleration verticale < 12 g, soit pas pire qu'une reception naturelle
##     (A et C mesurent 8 a 10 g). Arreter 8 m/s de chute sur les ~0,45 m de
##     compression disponibles demande au moins v^2 / 2d = 7 g : moins de 6 g
##     serait physiquement impossible. Avant : plafonnement de la vitesse de
##     chute en UN tick, 36,6 g.
## Criteres de SECURITE (inchanges, CLAUDE.md §10) :
##   - retombe sur ses roues : 4 roues au sol < 30 ticks apres le 1er contact,
##     assiette au 1er contact < 15 deg, jamais retourne ;
##   - chassis jamais au sol.
## Mesures affichees (INFO) : roulis max atteint apres le choc de C (liberte en
## vol) et roulis au contact (retablissement).

const SPEED_MS := 25.0          # 90 km/h
const RAMP_DEG := 15.6          # pente de sortie du tremplin A
const PAD_UP_MS := 8.0          # plaque de saut B
const KICK_RAD_S := 1.5         # choc de roulis C

const LABELS: PackedStringArray = ["A tremplin", "B plaque de saut", "C choc en vol"]

var _trucks: Array[Truck] = []
var _frames: Array[InputFrame] = []

# par camion
var _launch: PackedInt32Array = [-1, -1, -1]      # tick de decollage
var _first: PackedInt32Array = [-1, -1, -1]       # tick du 1er contact
var _all4: PackedInt32Array = [-1, -1, -1]
var _chassis: PackedInt32Array = [0, 0, 0]
var _upside: Array[bool] = [false, false, false]
var _attitude_contact: PackedFloat32Array = [0.0, 0.0, 0.0]
var _peak_g: PackedFloat32Array = [0.0, 0.0, 0.0]
var _prev_vy: PackedFloat32Array = [0.0, 0.0, 0.0]

# A : tangage et pente de la trajectoire, tick par tick pendant le vol
var _a_pitch: PackedFloat32Array = []
var _a_path: PackedFloat32Array = []

# C : roulis
var _c_max_roll: float = 0.0
var _c_roll_contact: float = 0.0


func _test_setup() -> void:
	duration_ticks = 420
	add_floor(4000.0)
	var fwd := Vector3(0.0, 0.0, -1.0)

	# A : en l'air a 3 m, nez leve de la pente du tremplin, vitesse le long du nez.
	var a := TruckTestUtil.spawn_truck(self, Vector3(-60.0, 3.0, 0.0), Vector3(RAMP_DEG, 0.0, 0.0))
	a.linear_velocity = fwd.rotated(Vector3.RIGHT, deg_to_rad(RAMP_DEG)) * SPEED_MS
	_launch[0] = 0

	# B : au sol, lance a pleine vitesse ; la plaque agit au tick 40.
	var b := TruckTestUtil.spawn_truck(self, Vector3(0.0, 0.0, 0.0))
	b.linear_velocity = fwd * SPEED_MS

	# C : en l'air a 6 m, a plat ; choc de roulis au tick 10.
	var c := TruckTestUtil.spawn_truck(self, Vector3(60.0, 6.0, 0.0))
	c.linear_velocity = fwd * SPEED_MS * 0.8

	_trucks = [a, b, c]
	for i in 3:
		_frames.append(InputFrame.new())


func _test_tick(t: int) -> void:
	var dt := 1.0 / Engine.physics_ticks_per_second
	for i in 3:
		var tr := _trucks[i]
		var f := _frames[i]
		f.tick = t
		# B garde sa vitesse au sol avant la plaque ; aucun autre input.
		f.throttle = 0.5 if (i == 1 and t < 40) else 0.0
		tr.set_input(f)

		if i == 1 and t == 40:
			tr.jump_pad_launch(PAD_UP_MS)
			_launch[1] = t
		if i == 2 and t == 10:
			tr.angular_velocity += -tr.global_basis.z * KICK_RAD_S
			_launch[2] = t

		if _launch[i] < 0 or t <= _launch[i]:
			_prev_vy[i] = tr.linear_velocity.y
			continue

		var w := tr.wheels_on_ground()
		_upside[i] = _upside[i] or tr.is_upside_down()
		if tr.get_contact_count() > 0:
			_chassis[i] += 1

		# en vol : avant tout contact apres le decollage (B decolle sous
		# quelques ticks : on attend qu'il ait quitte le sol)
		var airborne := w == 0
		if i == 0 and airborne and _first[0] < 0:
			var v := tr.linear_velocity
			var path := rad_to_deg(atan2(v.y, Vector2(v.x, v.z).length()))
			_a_pitch.append(TruckTestUtil.pitch_roll_deg(tr).x)
			_a_path.append(path)
		if i == 2 and _first[2] < 0:
			_c_max_roll = maxf(_c_max_roll, absf(TruckTestUtil.pitch_roll_deg(tr).y))

		var was_flying := i != 1 or (t - _launch[1]) > 8
		if w > 0 and _first[i] < 0 and was_flying:
			_first[i] = t
			_attitude_contact[i] = TruckTestUtil.tilt_deg(tr)
			if i == 2:
				_c_roll_contact = absf(TruckTestUtil.pitch_roll_deg(tr).y)
		if w == 4 and _first[i] >= 0 and _all4[i] < 0:
			_all4[i] = t

		# pic de deceleration verticale autour de la reception (60 ticks)
		if _first[i] >= 0 and t - _first[i] < 60:
			var accel_g := (tr.linear_velocity.y - _prev_vy[i]) / dt / 9.81
			_peak_g[i] = maxf(_peak_g[i], accel_g)
		_prev_vy[i] = tr.linear_velocity.y


func _test_finish() -> void:
	# --- sensation ---------------------------------------------------------
	var n := _a_pitch.size()
	var upto := int(n * 0.7)
	# Phase DESCENDANTE seulement (apres le sommet, trajectoire < 0). Sur tout
	# le vol, le retour a l'horizontale du decollage (+15,6 -> 0 deg) co-varie
	# par coincidence avec la trajectoire qui baisse aussi : une camion garde a
	# plat obtenait 0,59. Apres le sommet, lui reste a 0 deg pendant que la
	# trajectoire plonge : pente ~0 ; un nez qui suit plonge avec : pente ~1.
	var desc_path: PackedFloat32Array = []
	var desc_pitch: PackedFloat32Array = []
	for k in upto:
		if _a_path[k] < 0.0:
			desc_path.append(_a_path[k])
			desc_pitch.append(_a_pitch[k])
	var follow := _slope(desc_path, desc_pitch, desc_path.size())
	check("A : assez de vol descendant pour mesurer", desc_path.size() >= 15,
		"ticks=%d" % desc_path.size())
	check_above("A : le nez plonge avec la trajectoire (pente, phase descendante)", follow, 0.5)
	check_below("B : reception absorbee (pic vertical, g)", _peak_g[1], 12.0)

	# --- securite ----------------------------------------------------------
	for i in 3:
		var l := LABELS[i]
		check("%s : retombe (1er contact observe)" % l, _first[i] >= 0, "tick=%d" % _first[i])
		if _first[i] < 0:
			continue
		var settle := _all4[i] - _first[i] if _all4[i] >= 0 else 9999
		check_below("%s : 4 roues au sol apres le contact (ticks)" % l, float(settle), 30.0)
		check_below("%s : assiette au 1er contact (deg)" % l, _attitude_contact[i], 15.0)
		check("%s : jamais retourne" % l, not _upside[i], "retourne=%s" % _upside[i])
		check("%s : chassis jamais au sol" % l, _chassis[i] == 0, "ticks=%d" % _chassis[i])

	# --- mesures -----------------------------------------------------------
	print("  INFO   A : vol de %d ticks ; trajectoire de %+.1f a %+.1f deg ; tangage de %+.1f a %+.1f deg ; pente %.2f"
		% [n, _a_path[0], _a_path[upto - 1], _a_pitch[0], _a_pitch[upto - 1], follow])
	for i in 3:
		print("  INFO   %s : pic vertical a la reception %.1f g" % [LABELS[i], _peak_g[i]])
	print("  INFO   C : roulis max apres le choc %.1f deg ; roulis au contact %.1f deg"
		% [_c_max_roll, _c_roll_contact])


## Pente de la regression lineaire de y sur x, sur les `count` premiers points.
func _slope(x: PackedFloat32Array, y: PackedFloat32Array, count: int) -> float:
	var n := mini(count, mini(x.size(), y.size()))
	if n < 2:
		return 0.0
	var mx := 0.0
	var my := 0.0
	for k in n:
		mx += x[k]
		my += y[k]
	mx /= n
	my /= n
	var sxy := 0.0
	var sxx := 0.0
	for k in n:
		sxy += (x[k] - mx) * (y[k] - my)
		sxx += (x[k] - mx) * (x[k] - mx)
	return sxy / sxx if sxx > 1e-9 else 0.0
