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
## Puis un camion par categorie de vitesse (50cc a 200cc, GameState), lance a
## SA vitesse max, plein braquage au frein a main (2026-10-01, « en 200cc je me
## prends encore le mur ») : r = v^2 / a, le rayon croit comme le carre de la
## vitesse, la courbe du drift doit donc suivre la categorie.
##
## Criteres :
##   - A : rayon < 140 m, le virage le plus serre du jeu ;
##   - le stick commande la courbe : courbure A > B > C ;
##   - chaque categorie : rayon < 140 m a sa vitesse max ;
##   - jamais de tete-a-queue (derive < 90 deg), jamais retourne.

const SPEED_MS := 150.0 / 3.6
const TIGHTEST_TURN_M := 140.0
const LABELS: PackedStringArray = ["A plein braquage", "B stick neutre", "C contre-braquage"]
const STEER: PackedFloat32Array = [1.0, 0.0, -1.0]
const N := 3 + 4   # A, B, C puis une categorie de vitesse par camion

var _trucks: Array[Truck] = []
var _frames: Array[InputFrame] = []
var _prev_head := PackedFloat32Array()
var _sum_k := PackedFloat32Array()
var _n := PackedInt32Array()
var _max_slip := PackedFloat32Array()
var _upside: Array[bool] = []


func _test_setup() -> void:
	duration_ticks = 150
	add_floor(8000.0)
	_prev_head.resize(N)
	_sum_k.resize(N)
	_n.resize(N)
	_max_slip.resize(N)
	var base := load("res://vehicles/default_vehicle.tres") as VehicleTuning
	for i in N:
		var t := (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
		var speed := SPEED_MS
		if i >= 3:
			t.tuning = GameStateNode.speed_tuning(base, i - 3)
			speed = t.tuning.top_speed_kmh / 3.6
		t.position = Vector3(-3000.0 + i * 900.0, 0.0, 0.0)
		add_child(t)
		t.linear_velocity = Vector3(0.0, 0.0, -speed)
		_trucks.append(t)
		_frames.append(InputFrame.new())
		_upside.append(false)


func _test_tick(t: int) -> void:
	for i in N:
		var tr := _trucks[i]
		var f := _frames[i]
		f.tick = t
		f.throttle = 1.0
		f.handbrake = t > 5
		# Le drift s'amorce toujours en braquant dans le virage (20 ticks), puis
		# chaque camion applique sa consigne.
		f.steer = 1.0 if t <= 25 or i >= 3 else STEER[i]
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
	for c in 4:
		var i := 3 + c
		var cls: Dictionary = GameStateNode.SPEED_CLASSES[c]
		check_below("%s : jamais de tete-a-queue (deg)" % cls["cc"], _max_slip[i], 90.0)
		check("%s : jamais retourne" % cls["cc"], not _upside[i])
		var k_c := _sum_k[i] / maxi(_n[i], 1)
		print("  INFO   %s a %.0f km/h : rayon de trajectoire %.0f m, derive max %.0f deg"
			% [cls["cc"], cls["top_kmh"], 1.0 / k_c if k_c != 0.0 else INF, _max_slip[i]])
		check_below("%s : le drift prend le virage le plus serre a %.0f km/h (rayon, m)"
			% [cls["cc"], cls["top_kmh"]], 1.0 / maxf(k_c, 1e-6), TIGHTEST_TURN_M)
	check("le stick commande la courbe : courbure A > B > C", k[0] > k[1] and k[1] > k[2],
		"A=%.5f B=%.5f C=%.5f 1/m" % [k[0], k[1], k[2]])
