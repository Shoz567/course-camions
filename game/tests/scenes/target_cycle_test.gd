extends PhysicsTest

## Cible des pouvoirs au choix (2026-10-20 : « une petite cible rouge sur la
## personne qui va prendre le missile, une touche pour changer, une personne
## devant nous, en cycle ») : tireur A en (0, 0, 0) face a -Z, missile et
## laser montes ; B 30 m devant, C 60 m devant, D derriere, E loin sur le cote
## (hors du cone) :
##   A. sans rien toucher, la cible est la plus proche devant (B) ;
##   B. cible suivante (InputFrame.target_next) : C, puis de nouveau B (cycle),
##      jamais D ni E ;
##   C. la cible choisie (C) prend le missile ;
##   D. le viseur du HUD est pose sur la cible, a l'ecran ;
##   E. la cible choisie sort du cone (deplacee sur le cote) : retour a la
##      plus proche devant.

var _a: Truck
var _b: Truck
var _c: Truck
var _d: Truck
var _e: Truck
var _p: TruckPowers
var _hud: RaceHud
var _cam: Camera3D
var _seen: Dictionary = {}


func _test_setup() -> void:
	duration_ticks = 150
	add_floor(2000.0)
	_a = _spawn(Vector3(0.0, 0.0, 0.0))
	_b = _spawn(Vector3(3.0, 0.0, -30.0))
	_c = _spawn(Vector3(-4.0, 0.0, -60.0))
	_d = _spawn(Vector3(0.0, 0.0, 40.0))
	_e = _spawn(Vector3(60.0, 0.0, -20.0))
	_p = TruckPowers.setup(_a, PowerCatalog.Id.MISSILE, PowerCatalog.Id.LASER)
	child_entered_tree.connect(func(n: Node) -> void:
		if n is PowerMissile:
			(n as PowerMissile).exploded.connect(func(_at: Vector3, v: Truck) -> void: _seen["victim"] = v))
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.global_position = Vector3(0.0, 8.0, 22.0)
	_cam.look_at(Vector3(0.0, 2.0, -30.0), Vector3.UP)
	_hud = RaceHud.new()
	_hud.truck = _a
	_hud.camera = _cam
	add_child(_hud)


func _spawn(at: Vector3) -> Truck:
	var t := TruckTestUtil.spawn_truck(self, at)
	t.add_to_group(TruckPowers.TARGETS)
	return t


func _press_next(on: bool) -> void:
	var f := InputFrame.new()
	f.target_next = on
	_a.set_input(f)


func _test_tick(t: int) -> void:
	_press_next(t == 12 or t == 16 or t == 20)
	match t:
		10:
			_seen["auto"] = _p.target_ahead()
		14:
			_seen["next1"] = _p.target_ahead()
		18:
			_seen["next2"] = _p.target_ahead()
		22:
			_seen["next3"] = _p.target_ahead()
			_hud._place_reticle(_p)
			var at := _cam.unproject_position(_c.global_position + Vector3.UP * 2.2)
			_seen["reticle"] = [_hud.reticle_visible(), (_hud.get("_reticle") as Control).position.distance_to(at) < 1.0]
			_p.use(0)
		120:
			# la cible choisie sort du cone : retour a la plus proche devant
			_c.global_position = Vector3(-120.0, 0.0, -60.0)
		122:
			_seen["lost"] = _p.target_ahead()


func _test_finish() -> void:
	check("A sans choix : la plus proche devant (B)", _seen.get("auto") == _b, str(_seen.get("auto")))
	check("B cycle : C, puis B, puis C (jamais D ni E)", _seen.get("next1") == _c and _seen.get("next2") == _b
		and _seen.get("next3") == _c, "%s %s %s" % [_seen.get("next1"), _seen.get("next2"), _seen.get("next3")])
	check("C le missile part sur la cible choisie (C)", _seen.get("victim") == _c, str(_seen.get("victim")))
	check("D viseur affiche sur la cible", _seen.get("reticle") == [true, true], str(_seen.get("reticle")))
	check("E cible sortie du cone : de nouveau la plus proche", _seen.get("lost") == _b, str(_seen.get("lost")))
