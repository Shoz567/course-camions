extends PhysicsTest

## Saut (CLAUDE.md §10, corrige au spike V1) : chute de 2 m -> 4 roues au sol
## < 30 ticks apres le premier contact, stabilise < 60 ticks apres ce contact,
## chassis jamais au sol, aucun NaN. Deux chutes : a plat, et inclinee
## 5 deg x 5 deg (une reception de saut n'est jamais parfaitement a plat).

const DROP_HEIGHT := 2.0

var _trucks: Array[Truck] = []
var _labels: PackedStringArray = ["a plat", "inclinee 5x5"]
var _first: PackedInt32Array = [-1, -1]
var _all4: PackedInt32Array = [-1, -1]
var _unsettled: PackedInt32Array = [0, 0]
var _chassis: PackedInt32Array = [0, 0]
var _min_hub: PackedFloat32Array = [INF, INF]
var _nan: Array[bool] = [false, false]


func _test_setup() -> void:
	duration_ticks = 240
	add_floor()
	_trucks.append(TruckTestUtil.spawn_truck(self, Vector3(-8.0, DROP_HEIGHT, 0.0)))
	_trucks.append(TruckTestUtil.spawn_truck(self, Vector3(8.0, DROP_HEIGHT, 0.0), Vector3(5.0, 0.0, 5.0)))
	for t in _trucks:
		t.contact_monitor = true
		t.max_contacts_reported = 4


func _test_tick(tick_: int) -> void:
	for i in _trucks.size():
		var t := _trucks[i]
		if not t.global_position.is_finite():
			_nan[i] = true
			continue
		var w := t.wheels_on_ground()
		if w > 0 and _first[i] < 0:
			_first[i] = tick_
		if w == 4 and _all4[i] < 0:
			_all4[i] = tick_
		if t.get_contact_count() > 0:
			_chassis[i] += 1
		for k in 4:
			_min_hub[i] = minf(_min_hub[i], t.get_probe(k).hub_distance)
		var a := TruckTestUtil.pitch_roll_deg(t)
		var settled := w == 4 and absf(t.linear_velocity.y) < 0.05 \
				and absf(t.global_position.y) < 0.03 and absf(a.x) < 1.0 and absf(a.y) < 1.0
		if not settled:
			_unsettled[i] = tick_


func _test_finish() -> void:
	for i in _trucks.size():
		var l := _labels[i]
		check("%s : aucun NaN" % l, not _nan[i])
		check("%s : premier contact" % l, _first[i] > 0, "tick=%d" % _first[i])
		check_below("%s : 4 roues au sol apres 1er contact (ticks)" % l, _all4[i] - _first[i], 30)
		check_below("%s : stabilise apres 1er contact (ticks)" % l, _unsettled[i] - _first[i], 60)
		check("%s : chassis jamais au sol" % l, _chassis[i] == 0, "ticks=%d" % _chassis[i])
		print("  INFO   %s : compression max -> moyeu a %.3f m de l'ancrage" % [l, _min_hub[i]])
