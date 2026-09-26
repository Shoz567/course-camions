extends PhysicsTest

## truck.tscn est conforme au contrat docs/VEHICLE_SPEC.md (via TruckSpec) :
## masse, centre de masse, formes, ancrages, roues visuelles, amortissement,
## detection continue, couches. Et la repartition de charge par essieu.

const EPS := 0.001

var _truck: Truck


func _test_setup() -> void:
	duration_ticks = 2
	add_floor()
	_truck = (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
	add_child(_truck)


func _test_finish() -> void:
	var t := _truck
	check_near("masse (kg)", t.mass, TruckSpec.MASS_KG, EPS)
	check("centre de masse personnalise",
		t.center_of_mass_mode == RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM)
	check_near("ecart centre de masse (m)", (t.center_of_mass - TruckSpec.CENTER_OF_MASS).length(), 0.0, EPS)
	check("linear_damp remplace (SPIKE A10)",
		t.linear_damp_mode == RigidBody3D.DAMP_MODE_REPLACE, "mode=%d" % t.linear_damp_mode)
	check_near("linear_damp", t.linear_damp, 0.0, 1e-6)
	check("detection continue (SPIKE V2)", t.continuous_cd)
	check("couche vehicle seule", t.collision_layer == 1 << (TruckSpec.LAYER_VEHICLE - 1),
		"layer=%d" % t.collision_layer)
	check("tuning present et valide", t.tuning != null and t.tuning.validate().is_empty())

	_check_box("Chassis", TruckSpec.CHASSIS_SIZE, TruckSpec.CHASSIS_CENTER)
	_check_box("Cab", TruckSpec.CAB_SIZE, TruckSpec.CAB_CENTER)
	var shapes := 0
	for c in t.get_children():
		if c is CollisionShape3D:
			shapes += 1
	check("exactement 2 formes de collision", shapes == 2, "n=%d" % shapes)

	for i in 4:
		var probe := t.get_node_or_null(NodePath(TruckSpec.PROBE_NAMES[i])) as Node3D
		if check("ancrage %s present" % TruckSpec.PROBE_NAMES[i], probe != null):
			check_near("ancrage %s (m)" % TruckSpec.PROBE_NAMES[i],
				(probe.position - TruckSpec.ANCHORS[i]).length(), 0.0, EPS)
		var wheel := t.get_node_or_null(NodePath("Visual/%s" % TruckSpec.WHEEL_NAMES[i])) as MeshInstance3D
		if check("roue visuelle %s presente" % TruckSpec.WHEEL_NAMES[i], wheel != null):
			check_near("moyeu %s au repos (m)" % TruckSpec.WHEEL_NAMES[i],
				(wheel.position - TruckSpec.hub_rest_position(i)).length(), 0.0, EPS)
			var aabb := wheel.get_aabb()
			var size := wheel.transform.basis * aabb.size
			check_near("roue %s : diametre (m)" % TruckSpec.WHEEL_NAMES[i],
				absf(size.y), TruckSpec.WHEEL_RADIUS * 2.0, 0.01)
			check_near("roue %s : largeur sur X (m)" % TruckSpec.WHEEL_NAMES[i],
				absf(size.x), TruckSpec.WHEEL_WIDTH, 0.01)

	# VEHICLE_SPEC §4 : 57,9 % sur l'avant, et la somme des charges = m g.
	check_near("part de masse sur l'avant", TruckSpec.axle_share(0), 2.2 / 3.8, 1e-4)
	var total := 0.0
	for i in 4:
		total += TruckSpec.static_wheel_load(i)
	check_near("somme des charges statiques (N)", total, TruckSpec.MASS_KG * TruckSpec.GRAVITY, 0.5)
	check_finite("position apres 2 ticks", t.global_position)


func _check_box(node_name: String, size: Vector3, center: Vector3) -> void:
	var cs := _truck.get_node_or_null(node_name) as CollisionShape3D
	if not check("forme %s presente" % node_name, cs != null):
		return
	var box := cs.shape as BoxShape3D
	if not check("forme %s est une boite" % node_name, box != null):
		return
	check_near("forme %s : taille (m)" % node_name, (box.size - size).length(), 0.0, EPS)
	check_near("forme %s : centre (m)" % node_name, (cs.position - center).length(), 0.0, EPS)
