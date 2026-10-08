extends PhysicsTest

## Degats visibles et baril remasterise (lot 3, 2026-10-02) :
##   - fumee moteur selon les PV : rien au-dessus de 70, grise de 70 a 30,
##     noire sous 30, fumee d'epave a 0 ;
##   - traces de choc localisees (cicatrices peintes dans la carrosserie) :
##     A choc frontal -> calandre (avant du tracteur, brulure) ; B frottement
##     de biais -> flanc droit (eraflures) ; D marche arriere dans un mur ->
##     arriere de la remorque (accrochee a son pivot), rien sur le tracteur ;
##   - E : 50 PV -> fumee grise ; 20 PV -> fumee noire et etincelles ; 0 PV ->
##     fumee d'epave ; reapparu : neuf (plus de fumee ni de traces) ;
##   - remorque larguee : chaque choc qui l'abime laisse une trace ; sous
##     60 % de ses PV elle fume (gris), sous 30 % fumee noire et etincelles ;
##   - baril : 1,2 m de rayon et 2,5 m de haut, zone de declenchement plus
##     large que lui, gyrophare (dome, lumiere, halo d'au moins 20 pixels a
##     l'ecran) qui clignote en double eclair.
## Vitesses posees au tick 0 et aux ticks de lancement (CLAUDE.md §10 b).

const E_HURT_AT := 5
const E_WORSE_AT := 40
const E_KILL_AT := 80
const R1_AT := 60
const R2_AT := 300

var _a: Truck
var _b: Truck
var _d: Truck
var _e: Truck
var _o: Truck
var _r1: Truck
var _r2: Truck
var _trailer: DetachedTrailer
var _frames: Dictionary = {}
var _seen: Dictionary = {}


func _test_setup() -> void:
	duration_ticks = 460
	add_floor(1500.0)
	_a = _spawn(Vector3(0.0, 0.0, 0.0), 0.0, 20.0)
	_wall(Vector3(30.0, 6.0, 2.0), Vector3(0.0, 3.0, -40.0))
	_b = _spawn(Vector3(100.0, 0.0, 0.0), 8.0, 20.0)
	_wall(Vector3(2.0, 6.0, 300.0), Vector3(104.0, 3.0, -100.0))
	_d = _spawn(Vector3(200.0, 0.0, 0.0), 0.0, -12.0)
	_wall(Vector3(30.0, 6.0, 2.0), Vector3(200.0, 3.0, 32.0))
	_e = _spawn(Vector3(300.0, 0.0, 0.0), 0.0, 0.0)
	var spot := Transform3D(Basis.IDENTITY, Vector3(330.0, 1.0, 0.0))
	TruckHealth.of(_e).respawn_provider = func(_t: Truck) -> Transform3D: return spot
	_o = _spawn(Vector3(400.0, 0.0, 0.0), 0.0, 0.0)
	_r1 = _spawn(Vector3(400.0, 0.0, 60.0), 0.0, 0.0)
	_r2 = _spawn(Vector3(470.0, 0.0, 60.0), 90.0, 0.0)
	(_o.get_node("Cargo") as TruckCargo).dropped.connect(func(tr: DetachedTrailer) -> void: _trailer = tr)


func _spawn(pos: Vector3, yaw_deg: float, speed: float) -> Truck:
	var t := TruckTestUtil.spawn_truck(self, pos, Vector3(0.0, -yaw_deg, 0.0))
	t.linear_velocity = -t.global_basis.z * speed
	_frames[t] = InputFrame.new()
	return t


func _wall(size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	body.position = pos
	add_child(body)


func _fx(t: Truck) -> TruckDamageFx:
	return t.get_node("DamageFx") as TruckDamageFx


func _test_tick(t: int) -> void:
	for tr: Truck in [_a, _b, _d, _e, _o, _r1, _r2]:
		var f: InputFrame = _frames[tr]
		f.tick = t
		f.cargo = tr == _o and t == 5
		f.throttle = 1.0 if tr == _o and t > 10 and t < 200 else 0.0
		f.brake = 1.0 if tr == _o and t >= 200 and t < 330 else 0.0
		tr.set_input(f)
	var eh := TruckHealth.of(_e)
	match t:
		E_HURT_AT: eh.damage(50.0, &"test")
		E_HURT_AT + 5:
			_seen["e50"] = _smoke_state(_e)
			_seen["fire"] = [_burning(_e)]
		E_WORSE_AT: eh.damage(30.0, &"test")
		E_WORSE_AT + 5:
			_seen["e20"] = _smoke_state(_e)
			(_seen["fire"] as Array).append(_burning(_e))
		E_WORSE_AT + 10: eh.damage(8.0, &"test")
		E_WORSE_AT + 15: (_seen["fire"] as Array).append(_burning(_e))
		E_KILL_AT: eh.damage(12.0, &"test")
		E_KILL_AT + 5:
			_seen["e0"] = [_smoke_state(_e), _fx(_e).marks().size()]
			(_seen["fire"] as Array).append(_burning(_e))
		E_KILL_AT + 190: _seen["e_new"] = [_smoke_state(_e), _fx(_e).marks().size(), eh.hp,
			BodyScars.scarred(_e.get_node("Visual") as Node3D)]
		E_KILL_AT + 191: (_seen["fire"] as Array).append(_burning(_e))
		R1_AT: _r1.linear_velocity = Vector3(0.0, 0.0, -25.0)
		R2_AT - 20:
			if _trailer != null and is_instance_valid(_trailer):
				_seen["after_r1"] = [_trailer.hp, _trailer.damage_stage, _trailer.mark_count(), _trailer.is_smoking()]
				var c := (_trailer.get_child(0) as Node3D).global_position
				_r2.reset_to(Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3(c.x + 25.0, 0.3, c.z)))
		R2_AT: _r2.linear_velocity = -_r2.global_basis.z * 18.0
		455:
			if _trailer != null and is_instance_valid(_trailer):
				_seen["after_r2"] = [_trailer.hp, _trailer.damage_stage, _trailer.mark_count(), _trailer.is_smoking(),
					(_trailer.get_node("Sparks") as GPUParticles3D).emitting]


## Le moteur de `t` brule-t-il (feu sous TruckDamageFx.FIRE_HP) ?
func _burning(t: Truck) -> bool:
	var fx := _fx(t)
	fx.refresh()
	return fx.is_burning()


func _smoke_state(t: Truck) -> Array:
	var fx := _fx(t)
	fx.refresh()
	var smoke := fx.get_node("Smoke") as GPUParticles3D
	return [fx.smoke_level(), fx.is_smoking(), fx.is_sparking(), DamageFx.smoke_color(smoke).get_luminance() > 0.5]


## Trace la plus forte d'une liste : position et axe sortant, dans le repere
## de son parent (carrosserie ou pivot de remorque).
func _strongest(marks: Array[Node3D]) -> Dictionary:
	var best: Node3D = null
	for d in marks:
		if best == null or float(d.get_meta(&"severity")) > float(best.get_meta(&"severity")):
			best = d
	if best == null:
		return {}
	return {"pos": best.position, "out": best.transform.basis.y.normalized(),
		"severity": float(best.get_meta(&"severity")), "parent": best.get_parent()}


func _test_finish() -> void:
	var S := DamageFx.Smoke
	check("fumee selon les PV : 100 / 71 rien, 70 / 30 grise, 29 noire, epave",
		[TruckDamageFx.smoke_level_for(100.0, false), TruckDamageFx.smoke_level_for(71.0, false),
		TruckDamageFx.smoke_level_for(70.0, false), TruckDamageFx.smoke_level_for(30.0, false),
		TruckDamageFx.smoke_level_for(29.0, false), TruckDamageFx.smoke_level_for(0.0, true)]
		== [S.NONE, S.NONE, S.LIGHT, S.LIGHT, S.HEAVY, S.WRECK])

	var visual_a := _a.get_node("Visual") as TruckVisual
	var ma := _strongest(_fx(_a).marks())
	print("  INFO   A %s ; B %s ; D %s" % [ma, _strongest(_fx(_b).marks()), _strongest(_fx(_d).marks(true))])
	check("A choc frontal : trace sur la calandre (avant du tracteur), brulure", not ma.is_empty()
		and ma["parent"] == visual_a.mark_parent(false) and ma["pos"].z < -2.5 and ma["out"].dot(Vector3.FORWARD) > 0.7
		and ma["severity"] >= 0.9)
	var scarred := BodyScars.scarred(visual_a)
	check("traces : cicatrices peintes dans la carrosserie, aucun decalque (traits blancs)",
		scarred > 0 and visual_a.find_children("*", "Decal", true, false).is_empty(), "%d maillages" % scarred)
	var front := 0
	for n in visual_a.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for s: Array in BodyScars.of(mi):
			var at := visual_a.mark_parent(false).global_transform.affine_inverse() * (mi.global_transform * (s[0] as Vector3))
			var p: Variant = mi.get_instance_shader_parameter(&"scar0")
			if at.z < -2.0 and float(s[2]) > 0.9 and p is Vector4 and (p as Vector4).w > 8.0:
				front += 1
	check("A : cicatrice violente a l'avant, transmise a la peinture (scar0)", front > 0, str(front))
	var mb := _strongest(_fx(_b).marks())
	check("B frottement : eraflures sur le flanc droit", not mb.is_empty() and mb["pos"].x > 1.0
		and mb["out"].dot(Vector3.RIGHT) > 0.7 and mb["severity"] < 0.35)
	var md := _strongest(_fx(_d).marks(true))
	check("D choc arriere : trace sur l'arriere de la remorque (son pivot), rien sur le tracteur",
		not md.is_empty() and md["parent"] == (_d.get_node("Visual") as TruckVisual).mark_parent(true)
		and md["pos"].z > 8.0 and _fx(_d).marks().is_empty())

	check("E 50 PV : fumee grise legere, sans etincelles", _seen.get("e50", []) == [S.LIGHT, true, false, true],
		str(_seen.get("e50", [])))
	check("E 20 PV : fumee noire epaisse et etincelles", _seen.get("e20", []) == [S.HEAVY, true, true, false],
		str(_seen.get("e20", [])))
	var e0: Array = _seen.get("e0", [[], 0])
	check("E 0 PV : fumee d'epave, cabine noircie", e0[0] == [S.WRECK, true, true, false] and int(e0[1]) >= 4, str(e0))
	check("E reapparu : neuf (ni fumee, ni traces, 100 PV)", _seen.get("e_new", []) == [[S.NONE, false, false, false], 0, 100.0, 0],
		str(_seen.get("e_new", [])))
	# feu moteur (2026-10-08, particules) : sous FIRE_HP et sur l'epave, eteint
	# sur le camion neuf
	check("feu moteur : 50 / 20 PV non, 12 PV oui, epave oui, reapparu non",
		_seen.get("fire", []) == [false, false, true, true, false], str(_seen.get("fire", [])))
	check("feu : seuil FIRE_HP", not TruckDamageFx.fire_for(TruckDamageFx.FIRE_HP, false)
		and TruckDamageFx.fire_for(TruckDamageFx.FIRE_HP - 0.1, false) and TruckDamageFx.fire_for(80.0, true))
	# eclats de tole froissee : plaques pliees de 1 x 1, minces, fermees
	var shard_ok := true
	for k in FxKit.SHARD_VARIANTS:
		var m := FxKit.shard_mesh(k)
		var box := m.get_aabb()
		shard_ok = shard_ok and m.get_surface_count() == 1 and box.size.x > 0.95 and box.size.x < 1.05 \
			and box.size.z > 0.95 and box.size.z < 1.05 and box.size.y < 0.6 and box.size.y >= FxKit.SHARD_THICKNESS
	check("eclats : %d plaques froissees de 1 x 1 m, minces" % FxKit.SHARD_VARIANTS, shard_ok
		and FxKit.shard_mesh(0) != FxKit.shard_mesh(1))

	var r1: Array = _seen.get("after_r1", [])
	var r2: Array = _seen.get("after_r2", [])
	print("  INFO   remorque apres R1 %s ; apres R2 %s" % [r1, r2])
	check("remorque abimee (< 60 % de ses PV) : traces et fumee grise", r1.size() == 4 and r1[1] == 1
		and int(r1[2]) >= 3 and r1[3], str(r1))
	check("remorque en ruine (< 30 %) : plus de traces, fumee noire, etincelles", r2.size() == 5 and r2[1] == 2
		and int(r2[2]) > int(r1[2]) and r2[3] and r2[4], str(r2))

	_check_barrel()


func _check_barrel() -> void:
	var barrel := ExplosiveBarrel.new()
	add_child(barrel)
	var body := barrel.find_children("*", "CollisionShape3D", false, false)[0] as CollisionShape3D
	var cyl := body.shape as CylinderShape3D
	var trigger := (barrel.get_node("Trigger").get_child(0) as CollisionShape3D).shape as CylinderShape3D
	check("baril : 1,2 m de rayon, 2,5 m de haut (x1,85)", is_equal_approx(cyl.radius, 1.2) and is_equal_approx(cyl.height, 2.5),
		"%.2f x %.2f" % [cyl.radius, cyl.height])
	check("baril : zone de declenchement plus large et plus haute que lui",
		trigger.radius > cyl.radius + 0.5 and trigger.height > cyl.height)
	var halo := barrel.find_child("BeaconHalo", true, false) as MeshInstance3D
	var light := barrel.find_child("Beacon", true, false) as OmniLight3D
	check("baril : gyrophare (dome, lumiere, halo qui reste visible au loin)",
		barrel.find_child("BeaconDome", true, false) != null and light != null and halo != null
		and float((halo.material_override as ShaderMaterial).get_shader_parameter("min_pixels")) >= 20.0)
	check("baril : chevrons jaunes et noirs lumineux", barrel.find_child("Chevrons", true, false) != null)
	check("gyrophare : double eclair, puis lueur", ExplosiveBarrel.strobe(0.03) == 1.0
		and ExplosiveBarrel.strobe(0.19) == 1.0 and ExplosiveBarrel.strobe(0.5) < 0.5)
	barrel.free()
