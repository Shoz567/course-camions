extends PhysicsTest

## Remorques au choix (TrailerCatalog, TrailerType) :
##   - chaque remorque du catalogue charge et passe validate() ; ids uniques ;
##   - chaque remorque a son modele ; le Conteneur (defaut) ne change pas la
##     conduite : stats a 1, reglage identique au reglage de base ;
##   - les stats s'appliquent au reglage ; validate() refuse un 0 et un
##     multiplicateur hors bornes ;
##   - Truck.set_trailer_type : la caisse de collision prend la taille et la
##     place de la remorque, SANS toucher a celle d'un autre camion (la forme
##     de truck.tscn est partagee) ;
##   - DetachedTrailer.configure : PV, masse et boite de la remorque choisie.

var _a: Truck
var _b: Truck


func _test_setup() -> void:
	duration_ticks = 2
	var scene := load("res://vehicles/truck.tscn") as PackedScene
	_a = scene.instantiate() as Truck
	_b = scene.instantiate() as Truck
	_b.position = Vector3(20.0, 0.0, 0.0)
	add_child(_a)
	add_child(_b)


func _test_finish() -> void:
	var ids := {}
	var invalid := PackedStringArray()
	for i in TrailerCatalog.count():
		var t := TrailerCatalog.at(i)
		if t == null:
			invalid.append(TrailerCatalog.PATHS[i] + " : ne charge pas")
			continue
		ids[t.id] = true
		var errors := t.validate()
		if not errors.is_empty():
			invalid.append("%s : %s" % [t.id, errors])
	check("chaque remorque du catalogue est valide", invalid.is_empty(), str(invalid))
	check("ids uniques", ids.size() == TrailerCatalog.count(), "%d / %d" % [ids.size(), TrailerCatalog.count()])
	check_above("au moins 2 remorques au choix", TrailerCatalog.count(), 1)
	check("le choix boucle (index -1 = derniere)",
		TrailerCatalog.at(-1) == TrailerCatalog.at(TrailerCatalog.count() - 1))

	var ref := TrailerCatalog.default_type()
	var no_model := PackedStringArray()
	for i in TrailerCatalog.count():
		if TrailerCatalog.at(i).model == "":
			no_model.append(String(TrailerCatalog.at(i).id))
	check("chaque remorque a son modele (plus de remorque d'origine)", no_model.is_empty(), str(no_model))
	check("defaut : Conteneur", ref.id == &"conteneur", String(ref.id))
	var base := _a.tuning
	var same := ref.apply_to(base)
	check("Conteneur : reglage identique au reglage de base (reference)",
		is_equal_approx(same.top_speed_kmh, base.top_speed_kmh)
		and is_equal_approx(same.engine_accel_ms2, base.engine_accel_ms2)
		and is_equal_approx(same.lateral_grip_g, base.lateral_grip_g)
		and is_equal_approx(same.boost_accel_ms2, base.boost_accel_ms2))

	var tank := load("res://vehicles/trailers/citerne.tres") as TrailerType
	var heavy := tank.apply_to(base)
	check("stats appliquees (citerne : vitesse, acceleration)",
		is_equal_approx(heavy.top_speed_kmh, base.top_speed_kmh * tank.top_speed_mult)
		and is_equal_approx(heavy.engine_accel_ms2, base.engine_accel_ms2 * tank.accel_mult),
		"%.1f km/h, %.2f m/s2" % [heavy.top_speed_kmh, heavy.engine_accel_ms2])
	check("le reglage de base n'est pas modifie", is_equal_approx(base.top_speed_kmh, _b.tuning.top_speed_kmh))
	check("le reglage avec remorque reste valide", heavy.validate().is_empty(), str(heavy.validate()))
	var bad := tank.duplicate() as TrailerType
	bad.accel_mult = 0.0
	check("validate refuse un multiplicateur a 0", not bad.validate().is_empty())
	bad.accel_mult = 1.5
	check("validate refuse un multiplicateur desequilibre", not bad.validate().is_empty())

	# caisse de collision du camion
	_a.set_trailer_type(tank)
	var shape_a := _a.get_node(^"Trailer") as CollisionShape3D
	var shape_b := _b.get_node(^"Trailer") as CollisionShape3D
	check("caisse a la taille de la remorque",
		(shape_a.shape as BoxShape3D).size.is_equal_approx(tank.box_size), str((shape_a.shape as BoxShape3D).size))
	check("caisse a la place de la remorque", shape_a.position.is_equal_approx(tank.box_center), str(shape_a.position))
	check("l'autre camion garde sa caisse",
		(shape_b.shape as BoxShape3D).size.is_equal_approx(TruckSpec.TRAILER_SIZE), str((shape_b.shape as BoxShape3D).size))
	var vis := _a.get_node(^"Visual") as TruckVisual
	vis.set_trailer_type(tank)
	var mesh := vis.get_node(^"TrailerPivot/TrailerMesh") as Node3D
	check("boite de blockout a la taille de la caisse",
		(mesh.basis.get_scale() * TruckSpec.TRAILER_SIZE).is_equal_approx(tank.box_size), str(mesh.basis.get_scale()))
	_a.set_trailer_type(null)
	check("retour a la remorque d'origine",
		(shape_a.shape as BoxShape3D).size.is_equal_approx(TruckSpec.TRAILER_SIZE) and _a.trailer_type == null)

	# remorque larguee
	var dropped := DetachedTrailer.new()
	dropped.configure(tank)
	var box := (dropped.get_child(0) as CollisionShape3D).shape as BoxShape3D
	check("larguee : PV et masse de la remorque",
		dropped.max_hp == tank.dropped_hp * DetachedTrailer.ROAD_HP_MULT and dropped.trailer_mass == tank.dropped_mass_kg,
		"%s PV, %s kg" % [dropped.max_hp, dropped.trailer_mass])
	check("larguee : boite a la largeur et a la longueur de la remorque",
		is_equal_approx(box.size.x, tank.box_size.x) and is_equal_approx(box.size.z, tank.box_size.z), str(box.size))
	dropped.free()
