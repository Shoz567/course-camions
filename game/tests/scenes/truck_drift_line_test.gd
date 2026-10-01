extends PhysicsTest

## Le drift doit pouvoir PRENDRE LES VIRAGES de la piste.
##
## Ne d'un retour de l'utilisateur (2026-10-01) : « je ne peux pas prendre le
## virage en drift, je me deporte contre la rambarde exterieure ». Mesure : en
## drift, la trajectoire ne tenait que ~0,67 g lateral, moins qu'un virage en
## adherence. Rayon minimal r = v^2 / a : ~263 m a 150 km/h, alors que le
## virage le plus serre des deux pistes fait 140 m au centre
## (track_01_blockout, track_02_playa). Le camion pivotait, sa trajectoire non.
##
## Camions lances a 150 km/h (vitesse max), plein gaz, frein a main, et :
##   A. plein braquage dans le virage   -> la courbe se resserre ;
##   B. stick au neutre                 -> pas de force ajoutee ;
##   C. contre-braquage                 -> la courbe s'ouvre (le nez revient
##                                         vers la vitesse, la force s'efface).
## Courbure de la TRAJECTOIRE = vitesse de rotation de la trajectoire / vitesse
## (1/m, signee : > 0 dans le sens du virage d'entree, a droite), moyenne en
## regime etabli (ticks 60 a 150) ; rayon = 1 / courbure.
##
## Criteres :
##   - A : rayon < 140 m, le virage le plus serre du jeu ;
##   - le stick commande la courbe : courbure A > B > C ;
##   - jamais de tete-a-queue (derive < 90 deg), jamais retourne.

const SPEED_MS := 150.0 / 3.6
const TIGHTEST_TURN_M := 140.0
const LABELS: PackedStringArray = ["A plein braquage", "B stick neutre", "C contre-braquage"]
const STEER: PackedFloat32Array = [1.0, 0.0, -1.0]

var _trucks: Array[Truck] = []
var _frames: Array[InputFrame] = []
var _prev_head: PackedFloat32Array = [0.0, 0.0, 0.0]
var _sum_k: PackedFloat32Array = [0.0, 0.0, 0.0]
var _n: PackedInt32Array = [0, 0, 0]
var _max_slip: PackedFloat32Array = [0.0, 0.0, 0.0]
var _upside: Array[bool] = [false, false, false]


func _test_setup() -> void:
	duration_ticks = 150
	add_floor(8000.0)
	for i in 3:
		var t := TruckTestUtil.spawn_truck(self, Vector3(-900.0 + i * 900.0, 0.0, 0.0))
		t.linear_velocity = Vector3(0.0, 0.0, -SPEED_MS)
		_trucks.append(t)
		_frames.append(InputFrame.new())


func _test_tick(t: int) -> void:
	for i in 3:
		var tr := _trucks[i]
		var f := _frames[i]
		f.tick = t
		f.throttle = 1.0
		f.handbrake = t > 5
		# Le drift s'amorce toujours en braquant dans le virage (20 ticks), puis
		# chaque camion applique sa consigne.
		f.steer = 1.0 if t <= 25 else STEER[i]
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
	var k: PackedFloat32Array = []
	for i in 3:
		k.append(_sum_k[i] / maxi(_n[i], 1))
		check_below("%s : jamais de tete-a-queue (deg)" % LABELS[i], _max_slip[i], 90.0)
		check("%s : jamais retourne" % LABELS[i], not _upside[i])
		print("  INFO   %s : rayon de trajectoire %.0f m (> 0 : a droite), derive max %.0f deg"
			% [LABELS[i], 1.0 / k[i] if k[i] != 0.0 else INF, _max_slip[i]])
	check("A tourne dans le sens du virage", k[0] > 0.0, "courbure=%.5f" % k[0])
	check_below("A : le drift prend le virage le plus serre a 150 km/h (rayon, m)",
		1.0 / maxf(k[0], 1e-6), TIGHTEST_TURN_M)
	check("le stick commande la courbe : courbure A > B > C", k[0] > k[1] and k[1] > k[2],
		"A=%.5f B=%.5f C=%.5f 1/m" % [k[0], k[1], k[2]])
