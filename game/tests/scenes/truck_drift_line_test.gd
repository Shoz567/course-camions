extends PhysicsTest

## Le drift doit pouvoir PRENDRE LES VIRAGES de la piste.
##
## Ne d'un retour de l'utilisateur (2026-10-01) : « je ne peux pas prendre le
## virage en drift, je me deporte contre la rambarde exterieure ». Mesure : en
## drift, la trajectoire ne tenait que ~0,75 g lateral. Rayon minimal
## r = v^2 / a : ~237 m a 150 km/h, alors que le virage le plus serre des deux
## pistes fait 140 m au centre (track_01_blockout, track_02_playa). D'ou la
## force de courbe du drift (drift_carve_g), dosee par l'angle de glisse.
##
## Depuis le 2026-10-01 l'angle du drift est libre (plus d'anti tete-a-queue,
## demande de l'utilisateur) : chaque camion est conduit par le pilote de
## drift de TruckTestUtil, frein a main tenu, plein gaz, qui contre-braque pour
## tenir sa derive visee.
##   A. 100cc a 150 km/h, derive visee 40 deg ;
##   B. 100cc a 150 km/h, derive visee 55 deg ;
##   puis un camion par categorie (50cc a 200cc), a SA vitesse max, derive
##   visee 55 deg (le rayon croit comme le carre de la vitesse : la courbe
##   suit la categorie, GameState.SPEED_CLASSES « drift »).
## Courbure de la TRAJECTOIRE = vitesse de rotation de la trajectoire / vitesse
## (1/m, > 0 a droite), moyenne en regime etabli (ticks 60 a 240).
##
## Criteres :
##   - plus d'angle, courbe plus serree : courbure B > courbure A ;
##   - chaque categorie : rayon < 140 m a sa vitesse max ;
##   - le pilote tient le drift : derive < 90 deg (pas de tete-a-queue),
##     jamais retourne.

const TIGHTEST_TURN_M := 140.0
## [categorie, derive visee (deg), libelle]
const CASES := [
	[1, 40.0, "A 100cc vise 40 deg"],
	[1, 55.0, "B 100cc vise 55 deg"],
	[0, 55.0, "50cc"],
	[1, 55.0, "100cc"],
	[2, 55.0, "150cc"],
	[3, 55.0, "200cc"],
]

var _trucks: Array[Truck] = []
var _frames: Array[InputFrame] = []
var _prev_head := PackedFloat32Array()
var _sum_k := PackedFloat32Array()
var _n := PackedInt32Array()
var _max_slip := PackedFloat32Array()
var _upside: Array[bool] = []


func _test_setup() -> void:
	duration_ticks = 240
	add_floor(10000.0)
	_prev_head.resize(CASES.size())
	_sum_k.resize(CASES.size())
	_n.resize(CASES.size())
	_max_slip.resize(CASES.size())
	var base := load("res://vehicles/default_vehicle.tres") as VehicleTuning
	for i in CASES.size():
		var t := (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
		t.tuning = GameStateNode.speed_tuning(base, CASES[i][0])
		t.position = Vector3(-4000.0 + i * 1000.0, 0.0, 0.0)
		add_child(t)
		t.linear_velocity = Vector3(0.0, 0.0, -t.tuning.top_speed_kmh / 3.6)
		_trucks.append(t)
		_frames.append(InputFrame.new())
		_upside.append(false)


func _test_tick(t: int) -> void:
	for i in CASES.size():
		var tr := _trucks[i]
		var f := _frames[i]
		f.tick = t
		f.throttle = 1.0
		f.handbrake = t > 5
		f.steer = TruckTestUtil.drift_pilot_steer(tr, CASES[i][1])
		tr.set_input(f)
		_max_slip[i] = maxf(_max_slip[i], TruckTestUtil.sideslip_deg(tr))
		_upside[i] = _upside[i] or tr.is_upside_down()
		var v := Vector2(tr.linear_velocity.x, tr.linear_velocity.z)
		var head := atan2(v.x, v.y)
		if t > 60:
			# heading = atan2(vx, vz) decroit quand la trajectoire tourne a droite
			var rate := -angle_difference(_prev_head[i], head) * Engine.physics_ticks_per_second
			_sum_k[i] += rate / maxf(v.length(), 1.0)
			_n[i] += 1
		_prev_head[i] = head


func _test_finish() -> void:
	var k := PackedFloat32Array()
	for i in CASES.size():
		k.append(_sum_k[i] / maxi(_n[i], 1))
		var label: String = CASES[i][2]
		check_below("%s : pas de tete-a-queue (deg)" % label, _max_slip[i], 90.0)
		check("%s : jamais retourne" % label, not _upside[i])
		print("  INFO   %s a %.0f km/h : rayon de trajectoire %.0f m, derive max %.0f deg" % [
			label, _trucks[i].tuning.top_speed_kmh, 1.0 / k[i] if k[i] != 0.0 else INF, _max_slip[i]])
	check("plus d'angle, courbe plus serree : courbure B > A", k[1] > k[0],
		"A=%.5f B=%.5f 1/m" % [k[0], k[1]])
	for i in range(2, CASES.size()):
		check_below("%s : le drift prend le virage le plus serre a %.0f km/h (rayon, m)"
			% [CASES[i][2], _trucks[i].tuning.top_speed_kmh], 1.0 / maxf(k[i], 1e-6), TIGHTEST_TURN_M)
