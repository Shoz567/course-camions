extends PhysicsTest

## Circuit n°2, Playa Del Sol (tracks/track_02_playa.tscn), avec PadEffects :
##   - habillage : theme plage (chaussee et sol a lui, plus de neon sur les
##     glissieres), 3 arches, environnement de plein soleil (ciel bleu clair,
##     soleil avec ombres dans la scene de course) ;
##   - relief : au moins 25 m de denivele, pente max roulable (< 20 %) ;
##     4 bancs de sable, 8 panneaux, 6 plaques de boost, 4 tremplins ;
##   - ile : terre sous la ligne de depart et le long de la promenade, mer au
##     large et SOUS le grand pont ; le pont et la jetee sont des tabliers sur
##     piles (au moins 12 piles, aucune collision), pas la ligne de depart ;
##     talus de roche sous les portions hautes, sans collision ;
##   - decor (force en headless) : au moins 150 palmiers, tous sur la terre et
##     au-dela des murs ; au moins 30 rochers, tous dans l'eau ; aucun corps
##     physique ;
##   - grille : les 6 camions se posent sans se toucher ni bouger ;
##   - banc de sable : un camion a 100 km/h qui y roule perd au moins 25 % de
##     sa vitesse, une seule fois (le banc remplace la flaque de Cyber City).

const SANDBANK := 0

var _track: TrackBlockout
var _grid: Array[Truck] = []
var _grid_start: Array[Vector3] = []
var _grid_contacts: int = 0
var _a: Truck
var _fa: InputFrame = InputFrame.new()
var _a_slowed: int = 0
var _a_hit_at: int = -1
var _a_before: float = 0.0
var _a_after: float = 0.0
var _a_prev: float = 0.0
var _max_tilt: float = 0.0


func _test_setup() -> void:
	duration_ticks = 240
	PlayaBackdrop.generate_in_headless = true
	_track = (load("res://tracks/track_02_playa.tscn") as PackedScene).instantiate() as TrackBlockout
	add_child(_track)
	PlayaBackdrop.generate_in_headless = false
	var pads := PadEffects.new()
	pads.track = _track
	add_child(pads)
	for slot in 6:
		var t := (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
		t.transform = _track.get_start_transform(slot)
		t.contact_monitor = true
		t.max_contacts_reported = 4
		add_child(t)
		_grid.append(t)
		_grid_start.append(t.global_position)
	# banc de sable : camion pose 22 m avant, dans l'axe, a 100 km/h
	var at := _track.puddle_transform(SANDBANK)
	var i := _track.closest_sample(at.origin)
	var lateral := (at.origin - _track.sample_position(i)).dot(_track.sample_right(i))
	var xf := _track.frame_at(_track.sample_ahead(i, -22.0), lateral, 0.0)
	_a = (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
	_a.transform = xf
	add_child(_a)
	_a.linear_velocity = -xf.basis.z * 100.0 / 3.6
	_a.slowed_down.connect(func() -> void:
		_a_slowed += 1
		if _a_hit_at < 0:
			_a_hit_at = tick
			_a_before = _a_prev)


func _test_tick(t: int) -> void:
	_fa.tick = t
	_fa.throttle = 0.6
	_a.set_input(_fa)
	var va := _a.linear_velocity.length()
	if _a_hit_at >= 0 and t == _a_hit_at + 3:
		_a_after = va
	_a_prev = va
	for truck in _grid:
		_grid_contacts += truck.get_contact_count()
		_max_tilt = maxf(_max_tilt, TruckTestUtil.tilt_deg(truck))
	_max_tilt = maxf(_max_tilt, TruckTestUtil.tilt_deg(_a))


func _test_finish() -> void:
	_check_theme()
	_check_relief()
	_check_island()
	_check_decor()
	var moved := 0.0
	var speed := 0.0
	for k in _grid.size():
		moved = maxf(moved, _grid[k].global_position.distance_to(_grid_start[k]))
		speed = maxf(speed, _grid[k].linear_velocity.length())
	check("grille : 6 camions poses sans contact", _grid_contacts == 0, "%d contacts" % _grid_contacts)
	check_below("grille : personne ne glisse (m)", moved, 0.6)
	check_below("grille : tout le monde a l'arret (m/s)", speed, 0.1)
	check("banc de sable : ralenti une seule fois", _a_slowed == 1, "%d" % _a_slowed)
	if _a_hit_at >= 0:
		check_below("banc de sable : vitesse apres / avant", _a_after / maxf(_a_before, 0.1), 0.75)
	check_below("personne ne se couche (deg)", _max_tilt, 45.0)


func _check_theme() -> void:
	check("theme Playa Del Sol", _track.theme_id == TrackTheme.Id.PLAYA_DEL_SOL and _track.theme.coast)
	var road := _track.get_node("Geometry/Road").find_children("*", "MeshInstance3D", false, false)[0] as MeshInstance3D
	var road_mat := road.material_override as ShaderMaterial
	check("chaussee de jour (shader de la plage, largeur transmise)",
		road_mat != null and road_mat.shader == preload("res://tracks/materials/playa_road.gdshader")
		and is_equal_approx(float(road_mat.get_shader_parameter("road_width")), _track.width))
	var left := _track.get_node("Walls/NeonLeft") as MeshInstance3D
	check("glissieres : plus de neon de ville", left.material_override != preload("res://tracks/materials/neon_cyan.tres"))
	check("3 arches", _track.arch_count() == 3, "%d" % _track.arch_count())
	var env := load("res://tracks/playa_sun.tres") as Environment
	var sky := env.sky.sky_material as ProceduralSkyMaterial
	check("plein soleil : ciel bleu clair", sky.sky_top_color.b > 0.6 and sky.sky_top_color.b > sky.sky_top_color.r * 2.0
		and sky.sky_horizon_color.get_luminance() > 0.6, str(sky.sky_top_color))
	var race := (load("res://dev/race_playa.tscn") as PackedScene).instantiate()
	var sun := race.get_node_or_null("Sun") as DirectionalLight3D
	check("course : soleil chaud, avec ombres", sun != null and sun.shadow_enabled and sun.light_energy >= 1.0
		and sun.light_color.r > sun.light_color.b)
	check("course : environnement de la plage",
		(race.get_node("WorldEnvironment") as WorldEnvironment).environment == env)
	race.free()


func _check_relief() -> void:
	var lo := INF
	var hi := -INF
	var grade := 0.0
	var n := _track.sample_count()
	var k := maxi(1, roundi(10.0 / (_track.length() / n)))
	for i in n:
		var p := _track.sample_position(i)
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
		var q := _track.sample_position(i + k)
		grade = maxf(grade, absf(q.y - p.y) / Vector2(q.x - p.x, q.z - p.z).length())
	print("  INFO   longueur %.0f m, relief %.1f m, pente max %.1f %% ; banc de sable %.1f -> %.1f m/s"
		% [_track.length(), hi - lo, grade * 100.0, _a_before, _a_after])
	check_above("relief : denivele du trace (m)", hi - lo, 25.0)
	check_below("relief : pente max roulable (%)", grade * 100.0, 20.0)
	check("4 bancs de sable, 8 panneaux, 6 plaques de boost, 4 tremplins",
		_track.puddle_count() == 4 and _track.sign_count() == 8 and _track.boost_pad_count() == 6
		and _track.jump_pad_count() == 4,
		"%d / %d / %d / %d" % [_track.puddle_count(), _track.sign_count(), _track.boost_pad_count(), _track.jump_pad_count()])
	var bank := _track.get_node("Pads/Puddle%d/Water" % SANDBANK) as MeshInstance3D
	check("piege : banc de sable (shader de sable), bombe",
		(bank.material_override as ShaderMaterial).shader == preload("res://tracks/materials/playa_sandbank.gdshader")
		and bank.get_aabb().size.y > 0.15, "hauteur %.2f m" % bank.get_aabb().size.y)


func _at(seg: String, along: float, lateral: float) -> Vector3:
	var i := _track.index_at_s(_track.segment_start_s(seg) + along)
	return _track.sample_position(i) + _track.sample_right(i) * lateral


func _check_island() -> void:
	var start := "Promenade du front de mer (depart)"
	var bridge := "Grand pont de la baie"
	check("ile : terre sous la ligne de depart et au bord de la promenade",
		not _track.is_water(_at(start, 0.0, 0.0)) and not _track.is_water(_at(start, 100.0, 70.0)))
	check("ile : la mer au large de la promenade, et loin de tout",
		_track.is_water(_at(start, 100.0, 260.0)) and _track.is_water(Vector3(6000.0, 0.0, 0.0)))
	check("ile : la mer SOUS le grand pont", _track.is_water(_at(bridge, 314.0, 0.0))
		and _track.is_water(_at(bridge, 150.0, 30.0)))
	var i_bridge := _track.index_at_s(_track.segment_start_s(bridge) + 314.0)
	var i_pier := _track.index_at_s(_track.segment_start_s("Jetee (pont de bois)") + 40.0)
	check("pont et jetee : tabliers sur piles ; pas la ligne de depart",
		_track.is_bridge_deck(i_bridge) and _track.is_bridge_deck(i_pier) and not _track.is_bridge_deck(0))
	var bridges := _track.get_node("Bridges")
	var piers := bridges.find_children("Pier*", "Node3D", false, false).size()
	check_above("ponts : piles", piers, 11)
	check("ponts : dessous en beton et en bois, aucune collision",
		bridges.get_node_or_null("DeckUnderConcrete") != null and bridges.get_node_or_null("DeckUnderWood") != null
		and bridges.find_children("*", "CollisionObject3D", true, false).is_empty())
	var banks := _track.get_node("Embankments")
	check("talus de roche des deux cotes, sans collision", banks.get_child_count() == 2
		and banks.find_children("*", "CollisionObject3D", true, false).is_empty())


func _check_decor() -> void:
	var playa := _track.get_node("PlayaBackdrop").get_child(0) as Node3D
	check("decor genere", playa != null)
	if playa == null:
		return
	check("decor : aucun corps physique", playa.find_children("*", "CollisionObject3D", true, false).is_empty())
	var palms: Array = playa.get_meta(&"palms", [])
	var rocks: Array = playa.get_meta(&"rocks", [])
	var beyond := _track.width / 2.0 + _track.wall_thickness + _track.wall_lean
	var wet := 0
	var inside := 0
	for xf: Transform3D in palms:
		wet += 1 if _track.is_water(xf.origin) else 0
		var c := _track.sample_position(_track.closest_sample(xf.origin))
		inside += 1 if Vector2(xf.origin.x - c.x, xf.origin.z - c.z).length() < beyond else 0
	var dry := 0
	for xf: Transform3D in rocks:
		dry += 0 if _track.is_water(xf.origin) else 1
	print("  INFO   decor : %d palmiers, %d rochers, %d parasols"
		% [palms.size(), rocks.size(), (playa.get_meta(&"parasols", []) as Array).size()])
	check_above("decor : palmiers", palms.size(), 149)
	check("decor : tous les palmiers sur la terre, au-dela des murs", wet == 0 and inside == 0,
		"%d dans l'eau, %d sur la piste" % [wet, inside])
	check_above("decor : rochers au large", rocks.size(), 29)
	check("decor : tous les rochers dans l'eau", dry == 0, "%d a sec" % dry)
