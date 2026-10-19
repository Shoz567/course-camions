extends PhysicsTest

## Circuit n°3, Sakura (tracks/track_03_sakura.tscn, 2026-10-19), un 8 :
##   - habillage : theme Sakura, trois torii (enseignes en kanji), barils en
##     tonneaux de sake (kanji 爆), flaques de bassin aux petales ;
##   - croisement : le trace se croise une fois ; au croisement, une branche
##     est un tablier de pont, l'autre au sol, avec au moins 12 m de hauteur
##     libre ; aucune pile de pont sur la route du dessous ;
##   - aucune zone de reset ne couvre l'autre branche (ni la route sous le
##     pont, ni le pont au-dessus) ; le checkpoint sous le pont s'arrete sous
##     le tablier ;
##   - deux camions a 100 km/h se croisent, l'un dessous, l'autre sur le
##     pont : aucun n'est replace, chacun reste sur sa branche et ne passe
##     que ses checkpoints ;
##   - decor (force en headless) : au moins 500 arbres et 20 maisons, jamais
##     sur la chaussee ni les murs d'aucune branche, chateau et pagode poses,
##     le Fuji a l'horizon ; aucun corps physique.

var _track: TrackBlockout
var _reset: AutoReset
var _low: Truck
var _high: Truck
var _i_low: int = -1
var _i_high: int = -1
var _fl: InputFrame = InputFrame.new()
var _fh: InputFrame = InputFrame.new()
var _resets: Array[Truck] = []
var _cps: Dictionary = {}
var _y_low: float = -INF
var _y_high: float = INF
var _from_low: Vector3
var _from_high: Vector3


func _test_setup() -> void:
	duration_ticks = 220
	SakuraBackdrop.generate_in_headless = true
	RaceDecor.generate_in_headless = true
	_track = (load("res://tracks/track_03_sakura.tscn") as PackedScene).instantiate() as TrackBlockout
	add_child(_track)
	SakuraBackdrop.generate_in_headless = false
	RaceDecor.generate_in_headless = false
	_reset = AutoReset.new()
	_reset.track = _track
	add_child(_reset)
	_reset.truck_reset.connect(func(t: Truck, _why: StringName) -> void: _resets.append(t))
	# croisement : l'echantillon le plus proche d'une autre branche
	var best := INF
	for i in range(0, _track.sample_count(), 2):
		var out := [-1]
		var d := _track.other_section_distance(_track.sample_position(i), _track.sample_s(i), out)
		if d < best:
			best = d
			var j: int = out[0]
			var low_first := _track.sample_position(i).y < _track.sample_position(j).y
			_i_low = i if low_first else j
			_i_high = j if low_first else i
	_low = _spawn(_track.frame_at(_track.sample_ahead(_i_low, -70.0), 0.0, 0.0))
	_high = _spawn(_track.frame_at(_track.sample_ahead(_i_high, -70.0), 0.0, 0.0))
	_from_low = _low.global_position
	_from_high = _high.global_position
	_track.checkpoint_passed.connect(func(body: Node3D, index: int) -> void:
		if not _cps.has(body):
			_cps[body] = []
		(_cps[body] as Array).append(index))


func _spawn(xf: Transform3D) -> Truck:
	var t := (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
	t.transform = xf
	add_child(t)
	t.linear_velocity = -xf.basis.z * 100.0 / 3.6
	_reset.watch(t)
	return t


func _test_tick(t: int) -> void:
	for pair: Array in [[_low, _fl], [_high, _fh]]:
		var truck: Truck = pair[0]
		var f: InputFrame = pair[1]
		f.tick = t
		f.throttle = clampf((100.0 - truck.get_speed_kmh()) / 5.0, 0.0, 1.0)
		truck.set_input(f)
	if t > 5:
		_y_low = maxf(_y_low, _low.global_position.y)
		_y_high = minf(_y_high, _high.global_position.y)


## Checkpoints dont la boite est a moins de 120 m (abscisse) de l'echantillon i.
func _cps_near(i: int) -> Array:
	var out := []
	var s := _track.sample_s(i)
	for k in _track.checkpoint_count:
		var ds := absf(_track.checkpoint_s(k) - s)
		if minf(ds, _track.length() - ds) < 120.0:
			out.append(k)
	return out


func _in_zone(p: Vector3) -> bool:
	for z in _track.get_node("ResetZones").get_children():
		var area := z as Area3D
		var cs := area.get_child(0) as CollisionShape3D
		var half := (cs.shape as BoxShape3D).size / 2.0
		var q := area.global_transform.affine_inverse() * p
		if absf(q.x) < half.x and absf(q.y) < half.y and absf(q.z) < half.z:
			return true
	return false


func _test_finish() -> void:
	var half := _track.width / 2.0
	var beyond := half + _track.wall_thickness + _track.wall_lean
	# habillage
	check("theme Sakura", _track.theme_id == TrackTheme.Id.SAKURA and _track.theme.arch_style == TrackTheme.ArchStyle.TORII)
	var labels := []
	for a in _track.get_node("Arches").get_children():
		var l := a.get_node_or_null(^"Sign") as Label3D
		if l != null:
			labels.append(l.text)
	check("trois torii a enseignes en kanji", labels.size() == 3 and labels.has("桜\n街\n道"), str(labels))
	var sake := true
	for b in _track.get_node("Barrels").get_children():
		sake = sake and b.get_node_or_null(^"Model/Kanji") != null
	check("barils en tonneaux de sake", _track.barrel_count() >= 4 and sake)
	var water := _track.get_node("Pads/Puddle0/Water") as MeshInstance3D
	check("flaques de bassin aux petales", water != null and (water.material_override as ShaderMaterial).shader.resource_path.ends_with("sakura_puddle.gdshader"))
	# croisement
	var lo := _track.sample_position(_i_low)
	var hi := _track.sample_position(_i_high)
	check_below("le 8 se croise (ecart des axes, m)", Vector2(lo.x - hi.x, lo.z - hi.z).length(), 5.0)
	check("une branche sur un pont, l'autre au sol", _track.is_bridge_deck(_i_high) and not _track.is_bridge_deck(_i_low)
		and lo.y < 1.0, "bas y=%.1f, haut y=%.1f" % [lo.y, hi.y])
	check_above("hauteur libre sous le tablier (m)", hi.y - _track.bridge_deck_depth - lo.y, 12.0)
	var crossings := 0
	var inside := false
	for i in range(0, _track.sample_count(), 2):
		var near := _track.other_section_distance(_track.sample_position(i), _track.sample_s(i)) < half
		if near and not inside:
			crossings += 1
		inside = near
	check("un seul croisement (sur chaque branche)", crossings == 2, "%d passages" % crossings)
	var bad_piers := 0
	for p in _track.get_node("Bridges").get_children():
		for col in p.get_children():
			if col is MeshInstance3D and (col as MeshInstance3D).mesh is CylinderMesh:
				var w := (col as Node3D).global_position
				for i in range(0, _track.sample_count(), 2):
					var q := _track.sample_position(i)
					if q.y < 3.0 and Vector2(w.x - q.x, w.z - q.z).length() < beyond + 1.0:
						bad_piers += 1
						break
	check("aucune pile sur la route du dessous", bad_piers == 0, "%d futs" % bad_piers)
	var covered := 0
	for k in range(-30, 31, 3):
		for i: int in [_track.sample_ahead(_i_low, k * 2.0), _track.sample_ahead(_i_high, k * 2.0)]:
			if _in_zone(_track.sample_position(i) + _track.sample_up(i) * 1.5):
				covered += 1
	check("aucune zone de reset sur les routes du croisement", covered == 0, "%d points couverts" % covered)
	# checkpoints de la route du dessous dont la boite passe sous le pont
	var under := 0
	var cp_ok := true
	for k: int in _cps_near(_i_low):
		var area := _track.get_node("Checkpoints/CP%02d" % k) as Area3D
		var cs := area.get_child(0) as CollisionShape3D
		var box := cs.shape as BoxShape3D
		if _track.other_section_distance(area.global_position, _track.checkpoint_s(k)) > box.size.x / 2.0 + half:
			continue
		under += 1
		var top := area.global_position.y + cs.position.y + box.size.y / 2.0
		cp_ok = cp_ok and top < hi.y - _track.bridge_deck_depth
	check("checkpoint sous le pont : arrete sous le tablier", under > 0 and cp_ok, "%d sous le pont" % under)
	# deux camions qui se croisent
	check("croisement a 100 km/h : personne n'est replace", _resets.is_empty(), "%d resets" % _resets.size())
	check_below("le camion du dessous reste en bas (y max, m)", _y_low, 3.0)
	check_above("le camion du pont reste en haut (y min, m)", _y_high, hi.y - 4.0)
	check_above("dessous : il passe le croisement (m)", _low.global_position.distance_to(_from_low), 80.0)
	check_above("sur le pont : il passe le croisement (m)", _high.global_position.distance_to(_from_high), 80.0)
	var low_cps: Array = _cps.get(_low, [])
	var high_cps: Array = _cps.get(_high, [])
	var mixed := false
	for k in high_cps:
		mixed = mixed or _cps_near(_i_low).has(k) and not _cps_near(_i_high).has(k)
	for k in low_cps:
		mixed = mixed or _cps_near(_i_high).has(k) and not _cps_near(_i_low).has(k)
	check("chacun ne passe que les checkpoints de sa branche", not mixed, "bas %s, haut %s" % [low_cps, high_cps])
	# decor
	var deco := _track.get_node("SakuraBackdrop/Sakura")
	var trees: Array = deco.get_meta(&"trees")
	var houses: Array = deco.get_meta(&"houses")
	var landmarks: Dictionary = deco.get_meta(&"landmarks")
	check_above("arbres", trees.size(), 499.0)
	check_above("maisons", houses.size(), 19.0)
	var on_road := 0
	for xf: Transform3D in trees:
		var c := xf.origin
		for i in range(0, _track.sample_count(), 2):
			var q := _track.sample_position(i)
			if Vector2(c.x - q.x, c.z - q.z).length() < beyond + 2.0:
				on_road += 1
				break
	for c: Vector3 in houses:
		for i in range(0, _track.sample_count(), 2):
			var q := _track.sample_position(i)
			if Vector2(c.x - q.x, c.z - q.z).length() < beyond + 6.0:
				on_road += 1
				break
	check("ni arbre ni maison sur la chaussee ou les murs", on_road == 0, "%d" % on_road)
	check("chateau et pagode poses", landmarks.has("castle") and landmarks.has("pagoda"), str(landmarks.keys()))
	var mountains := deco.get_node(^"Mountains") as MeshInstance3D
	check("le Fuji a l'horizon", mountains != null and mountains.has_meta(&"fuji")
		and (mountains.get_meta(&"fuji") as Vector3).length() > 2000.0)
	var bodies := _track.get_node("SakuraBackdrop").find_children("*", "CollisionObject3D", true, false)
	check("decor sans collision", bodies.is_empty(), "%d corps" % bodies.size())
