extends PhysicsTest

## Penche visuel de la carrosserie (TruckVisual, groupe « Penche visuel »).
##
## Six camions separes :
##   0. a l'arret ;
##   1. accelere plein gaz depuis l'arret        -> le nez se cabre ;
##   2. lance a 90 km/h, plein frein             -> le nez plonge ;
##   3. virage a droite, plein braquage          -> penche a GAUCHE (exterieur) ;
##   4. identique a 3, penche DESACTIVE          -> temoin ;
##   5. virage a droite, pour la limite de roulis.
##
## Criteres :
##   - a l'arret : penche < 0,1 deg ;
##   - acceleration : tangage max > +0,8 deg ; freinage : tangage min < -1 deg ;
##   - virage a droite : roulis > +1 deg (vers l'exterieur) ;
##   - jamais au-dela de lean_max_deg (plafond + 1 deg de depassement du ressort) ;
##   - le penche est bien APPLIQUE au noeud Body (pas seulement calcule) ;
##   - PUREMENT VISUEL : 3 et 4 ont la meme trajectoire a 1 mm pres.

var _trucks: Array[Truck] = []
var _frames: Array[InputFrame] = []
var _max_pitch_accel: float = -INF
var _min_pitch_brake: float = INF
var _max_roll_turn: float = -INF
var _max_abs: float = 0.0
var _rest_abs: float = 0.0
var _applied_roll: float = 0.0


func _test_setup() -> void:
	duration_ticks = 300
	add_floor(4000.0)
	for i in 6:
		var t := TruckTestUtil.spawn_truck(self, Vector3(-150.0 + i * 60.0, 0.0, 0.0))
		_trucks.append(t)
		_frames.append(InputFrame.new())
	_trucks[2].linear_velocity = Vector3(0.0, 0.0, -25.0)
	(_trucks[4].get_node(^"Visual") as TruckVisual).lean_enabled = false


func _test_tick(t: int) -> void:
	for i in 6:
		var f := _frames[i]
		f.tick = t
		f.throttle = 0.0
		f.brake = 0.0
		f.steer = 0.0
		match i:
			1:
				f.throttle = 1.0
			2:
				f.brake = 1.0 if t > 20 else 0.0
				f.throttle = 0.4 if t <= 20 else 0.0
			3, 4, 5:
				f.throttle = clampf((70.0 - _trucks[i].get_speed_kmh()) / 5.0, 0.0, 1.0)
				f.steer = 1.0 if t > 60 else 0.0
		_trucks[i].set_input(f)

	if t < 30:
		return   # demarrage : les camions se posent
	var lean := func(i: int) -> Vector2:
		return (_trucks[i].get_node(^"Visual") as TruckVisual).get_lean_deg()
	_rest_abs = maxf(_rest_abs, maxf(absf(lean.call(0).x), absf(lean.call(0).y)))
	_max_pitch_accel = maxf(_max_pitch_accel, lean.call(1).x)
	_min_pitch_brake = minf(_min_pitch_brake, lean.call(2).x)
	if t > 120:
		_max_roll_turn = maxf(_max_roll_turn, lean.call(3).y)
		# roulis reellement APPLIQUE au noeud Body, relatif au camion
		var body := _trucks[3].get_node(^"Visual/Body") as Node3D
		var rel := _trucks[3].global_basis.inverse() * body.global_basis
		_applied_roll = maxf(_applied_roll, rad_to_deg(asin(clampf(rel.x.y, -1.0, 1.0))))
	for i in [1, 2, 3, 5]:
		var l: Vector2 = lean.call(i)
		_max_abs = maxf(_max_abs, maxf(absf(l.x), absf(l.y)))


func _test_finish() -> void:
	var vis := _trucks[0].get_node(^"Visual") as TruckVisual
	check_below("a l'arret : penche (deg)", _rest_abs, 0.1)
	check_above("acceleration : le nez se cabre (deg)", _max_pitch_accel, 0.8)
	check_below("freinage : le nez plonge (deg)", _min_pitch_brake, -1.0)
	check_above("virage a droite : penche vers l'exterieur (roulis, deg)", _max_roll_turn, 1.0)
	check_above("roulis bien applique au noeud Body (deg)", _applied_roll, 0.5)
	check_below("plafond respecte (deg)", _max_abs, vis.lean_max_deg + 1.0)

	# purement visuel : 3 (penche actif) et 4 (desactive) roulent pareil, au
	# decalage de depart pres
	var offset := Vector3(60.0, 0.0, 0.0)
	var gap := (_trucks[4].global_position - _trucks[3].global_position - offset).length()
	check_below("purement visuel : trajectoires identiques avec et sans (m)", gap, 0.001)

	print("  INFO   cabrage max %.2f deg ; plongee max %.2f deg ; roulis max en virage %.2f deg (applique %.2f)"
		% [_max_pitch_accel, _min_pitch_brake, _max_roll_turn, _applied_roll])
