extends PhysicsTest

## Derapage au frein a main (tache 1.6). Trois camions lances a 80 km/h, plein
## gaz, puis virage a droite pendant DRIFT ticks :
##   A. reference, plein braquage sans frein a main ;
##   B. frein a main, conduit par le pilote de drift (TruckTestUtil, derive
##      visee PILOT_DEG : l'angle est libre depuis le 2026-10-01, c'est le
##      joueur qui le tient), puis stick et frein relaches ;
##   C. comme B, puis contre-braquage franc pendant COUNTER ticks.
## Criteres :
##   - le drift s'amorce : derive max de B >= 3 x derive max de A ;
##   - il se rattrape seul : B revient sous 5 deg de derive en < 90 ticks ;
##   - le contre-braquage aide : C revient au moins aussi vite que B ;
##   - jamais de tete-a-queue (derive < 90 deg), jamais retourne.
## Derive = angle signe entre le cap et la vitesse (> 0 : la vitesse part a
## droite du cap).

const LAUNCH_KMH := 80.0
const LAUNCH := 360
const DRIFT := 60
const COUNTER := 20
const EXIT := 180
const RECOVERED_DEG := 5.0
const PILOT_DEG := 45.0

var _trucks: Array[Truck] = []
var _labels: PackedStringArray = ["A sans frein a main", "B drift puis relache", "C drift puis contre-braquage"]
var _frames: Array[InputFrame] = []
var _max_slip: PackedFloat32Array = [0.0, 0.0, 0.0]
var _recovered_at: PackedInt32Array = [-1, -1, -1]
var _overshoot: PackedFloat32Array = [0.0, 0.0, 0.0]
var _speed_entry: PackedFloat32Array = [0.0, 0.0, 0.0]
var _speed_min: PackedFloat32Array = [INF, INF, INF]
# vitesse REELLE (norme horizontale), km/h : get_speed_kmh() ne donne que la
# composante le long du nez, soit cos(derive) x la vitesse en plein drift
var _real_entry: PackedFloat32Array = [0.0, 0.0, 0.0]
var _real_min: PackedFloat32Array = [INF, INF, INF]
var _max_roll: PackedFloat32Array = [0.0, 0.0, 0.0]
var _upside: Array[bool] = [false, false, false]
# effets de roues (TruckWheelFx) : ticks ou une roue arriere marque la route,
# en ligne droite (lancement) et pendant le drift
var _marks_launch: PackedInt32Array = [0, 0, 0]
var _marks_drift: PackedInt32Array = [0, 0, 0]
var _max_rear_slide: PackedFloat32Array = [0.0, 0.0, 0.0]


func _test_setup() -> void:
	duration_ticks = LAUNCH + DRIFT + EXIT
	add_floor(1600.0)
	for i in 3:
		_trucks.append(TruckTestUtil.spawn_truck(self, Vector3(-200.0 + i * 200.0, 0.0, 300.0)))
		_frames.append(InputFrame.new())


static func signed_slip_deg(t: RigidBody3D) -> float:
	var b := t.global_transform.basis
	var v_fwd := t.linear_velocity.dot(-b.z)
	var v_right := t.linear_velocity.dot(b.x)
	if Vector2(v_fwd, v_right).length() < 1.0:
		return 0.0
	return rad_to_deg(atan2(v_right, v_fwd))


func _test_tick(t: int) -> void:
	var release := LAUNCH + DRIFT
	for i in 3:
		var tr := _trucks[i]
		var f := _frames[i]
		f.tick = t
		var v := tr.get_speed_kmh()
		f.throttle = clampf((LAUNCH_KMH - v) / 5.0, 0.0, 1.0) if t <= LAUNCH else 1.0
		f.steer = 0.0
		f.handbrake = false
		if t > LAUNCH and t <= release:
			f.steer = TruckTestUtil.drift_pilot_steer(tr, PILOT_DEG) if i > 0 else 1.0
			f.handbrake = i > 0
		elif i == 2 and t > release and t <= release + COUNTER:
			f.steer = -1.0
		tr.set_input(f)
		var fx := tr.get_node("WheelFx") as TruckWheelFx
		var marking := fx.is_marking(0) or fx.is_marking(1)
		if t > 60 and t <= LAUNCH and marking:
			_marks_launch[i] += 1
		if t > LAUNCH and t <= release:
			_marks_drift[i] += 1 if marking else 0
			_max_rear_slide[i] = maxf(_max_rear_slide[i], maxf(fx.slide(0), fx.slide(1)))
		var real := Vector2(tr.linear_velocity.x, tr.linear_velocity.z).length() * 3.6
		if t == LAUNCH:
			_speed_entry[i] = v
			_real_entry[i] = real
		if t <= LAUNCH:
			continue
		var slip := signed_slip_deg(tr)
		_max_slip[i] = maxf(_max_slip[i], absf(slip))
		_speed_min[i] = minf(_speed_min[i], v)
		_real_min[i] = minf(_real_min[i], real)
		_max_roll[i] = maxf(_max_roll[i], absf(TruckTestUtil.pitch_roll_deg(tr).y))
		_upside[i] = _upside[i] or tr.is_upside_down()
		if t > release:
			# braquage a droite : le cap tourne plus vite que la vitesse, qui
			# passe a gauche du cap (derive < 0). Un depassement de l'autre cote
			# (balancier a la relance) est donc > 0.
			_overshoot[i] = maxf(_overshoot[i], slip)
			if _recovered_at[i] < 0 and absf(slip) < RECOVERED_DEG:
				_recovered_at[i] = t - release


func _test_finish() -> void:
	for i in 3:
		var l := _labels[i]
		check_finite("%s : position finie" % l, _trucks[i].global_position)
		check_below("%s : jamais de tete-a-queue, derive max (deg)" % l, _max_slip[i], 90.0)
		check("%s : jamais retourne" % l, not _upside[i])
		print("  INFO   %s : derive max %.1f deg, retour < %.0f deg en %d ticks, depassement %.1f deg, vitesse %.0f -> min %.0f km/h, roulis max %.1f deg"
			% [l, _max_slip[i], RECOVERED_DEG, _recovered_at[i], _overshoot[i], _speed_entry[i], _speed_min[i], _max_roll[i]])
	check_ratio_above("le drift s'amorce : derive B / derive A", _max_slip[1], _max_slip[0], 3.0)
	# traces de gomme et fumee (2026-10-08) : rien en ligne droite, le drift
	# marque la route ; glissement max des roues arriere affiche
	check("aucune trace de gomme en ligne droite (lancement)", _marks_launch == PackedInt32Array([0, 0, 0]),
		str(_marks_launch))
	check_above("B : le drift laisse des traces (ticks sur %d)" % DRIFT, _marks_drift[1], DRIFT / 3)
	check("B : la fumee de pneus (ou la nappe d'eau) monte pendant le drift",
		TruckWheelFx.smoke_for(_max_rear_slide[1]) > 0.0, "glissement max %.1f m/s" % _max_rear_slide[1])
	print("  INFO   glissement arriere max (m/s) : A %.1f  B %.1f  C %.1f ; ticks marques A %d  B %d  C %d"
		% [_max_rear_slide[0], _max_rear_slide[1], _max_rear_slide[2], _marks_drift[0], _marks_drift[1], _marks_drift[2]])
	# Ajoute le 2026-10-01 (« le derapage freine trop ») : drift court PUIS
	# sortie, vitesse REELLE minimale >= 95 % de la vitesse d'entree. Mesure :
	# 98,6 % avant le reglage du 2026-10-01, 100 % apres. Ce scenario court
	# protege la sortie de drift ; le gain de vitesse se mesure, lui, sur le
	# drift tenu 4 s de truck_drift_control_test (74 % -> 92 %).
	# Piege rencontre : la « vitesse min » affichee plus haut est
	# get_speed_kmh(), composante le long du nez. En drift elle vaut
	# cos(derive) x la vitesse : 62 km/h a 38,5 deg (ancien reglage), 49 km/h a
	# 53 deg (nouveau), sans aucune perte de vitesse reelle derriere.
	check_ratio_above("B : vitesse reelle gardee jusqu'a la sortie du drift", _real_min[1], _real_entry[1], 0.95)
	print("  INFO   B : vitesse reelle %.0f -> min %.0f km/h" % [_real_entry[1], _real_min[1]])
	check("B se rattrape seul", _recovered_at[1] >= 0, "ticks=%d" % _recovered_at[1])
	check_below("B : retour sous 5 deg de derive (ticks)", _recovered_at[1], 90)
	check("C se rattrape", _recovered_at[2] >= 0, "ticks=%d" % _recovered_at[2])
	check("le contre-braquage aide : C au moins aussi vite que B",
		_recovered_at[2] >= 0 and _recovered_at[2] <= _recovered_at[1],
		"C=%d B=%d ticks" % [_recovered_at[2], _recovered_at[1]])
