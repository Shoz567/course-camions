extends PhysicsTest

## Controle en l'air (tache 1.6). Chutes de 3 m (~0,76 s de vol, un saut de
## tremplin a 100 km/h) :
##   A. mal parti (roulis 30 deg, tangage 20 deg), controle en l'air actif ;
##   B. temoin : A sans controle en l'air ;
##   C. a plat, plein stick a droite pendant le vol ;
##   D. a plat, stick au neutre.
## Criteres :
##   - A se reoriente : inclinaison au premier contact B / A >= 2 ;
##   - A retombe sur ses roues : 4 roues < 30 ticks apres le 1er contact,
##     jamais retourne (critere de saut, CLAUDE.md §10) ;
##   - le stick oriente : lacet de C >= la moitie de air_yaw_rate x temps de vol ;
##   - sans stick, pas de lacet parasite : D < 1 deg.

const HEIGHT := 3.0

var _trucks: Array[Truck] = []
var _labels: PackedStringArray = ["A mal parti, controle actif", "B mal parti, temoin sans controle",
	"C plein stick en l'air", "D stick au neutre"]
var _frames: Array[InputFrame] = []
var _first: PackedInt32Array = [-1, -1, -1, -1]
var _all4: PackedInt32Array = [-1, -1, -1, -1]
var _tilt_contact: PackedFloat32Array = [0.0, 0.0, 0.0, 0.0]
var _yaw_contact: PackedFloat32Array = [0.0, 0.0, 0.0, 0.0]
var _yaw0: PackedFloat32Array = [0.0, 0.0, 0.0, 0.0]
var _upside: Array[bool] = [false, false, false, false]


func _test_setup() -> void:
	duration_ticks = 180
	add_floor(200.0)
	var bad := Vector3(20.0, 0.0, 30.0)
	for i in 4:
		var rot := bad if i < 2 else Vector3.ZERO
		var t := TruckTestUtil.spawn_truck(self, Vector3(-45.0 + i * 30.0, HEIGHT, 0.0), rot)
		_trucks.append(t)
		_frames.append(InputFrame.new())
		_yaw0[i] = t.global_rotation.y
	_trucks[1].debug_air_control = false


func _test_tick(t: int) -> void:
	for i in 4:
		var tr := _trucks[i]
		var f := _frames[i]
		f.tick = t
		f.steer = 1.0 if i == 2 else 0.0
		tr.set_input(f)
		_upside[i] = _upside[i] or tr.is_upside_down()
		var w := tr.wheels_on_ground()
		if w > 0 and _first[i] < 0:
			_first[i] = t
			_tilt_contact[i] = TruckTestUtil.tilt_deg(tr)
			_yaw_contact[i] = absf(rad_to_deg(angle_difference(_yaw0[i], tr.global_rotation.y)))
		if w == 4 and _all4[i] < 0:
			_all4[i] = t


func _test_finish() -> void:
	for i in 4:
		print("  INFO   %s : 1er contact tick %d, inclinaison %.1f deg, lacet %.1f deg, 4 roues tick %d"
			% [_labels[i], _first[i], _tilt_contact[i], _yaw_contact[i], _all4[i]])
		check("%s : jamais retourne" % _labels[i], not _upside[i])
	check_ratio_above("assiette : inclinaison au contact, temoin / controle", _tilt_contact[1], _tilt_contact[0], 2.0)
	check_below("A : 4 roues au sol apres le 1er contact (ticks)", _all4[0] - _first[0], 30)
	var airtime_s := _first[2] / 60.0
	var t := _trucks[2].tuning
	check_above("C : lacet au stick pendant le vol (deg)", _yaw_contact[2], 0.5 * t.air_yaw_rate_deg_s * airtime_s)
	check_below("D : lacet parasite sans stick (deg)", _yaw_contact[3], 1.0)
