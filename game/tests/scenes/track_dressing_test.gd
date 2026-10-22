extends PhysicsTest

## Decor proche et lointain des trois circuits (2026-10-22), generation forcee
## en headless :
##   - au-dessus de la route : des cables tendus en travers, au moins
##     RoadsideDressing.SPAN_CLEARANCE m au-dessus du bord le plus haut de la
##     chaussee (plus haut que les arches), jamais pres d'une arche ni aux
##     tribunes ; objets de bord de piste, aucun sur la chaussee ;
##   - aucun corps physique dans ce decor ;
##   - au loin : palmiers (Playa) et cerisiers (Sakura) en sprites tournes, un
##     par arbre, texture chargee ; les cases 3D proches s'arretent a
##     FarLod.NEAR_END m.

const SCENES: PackedStringArray = ["res://tracks/track_01_blockout.tscn", "res://tracks/track_02_playa.tscn",
	"res://tracks/track_03_sakura.tscn"]

var _tracks: Array[TrackBlockout] = []


func _test_setup() -> void:
	duration_ticks = 3
	RoadsideDressing.generate_in_headless = true
	PlayaBackdrop.generate_in_headless = true
	SakuraBackdrop.generate_in_headless = true
	for path in SCENES:
		var t := (load(path) as PackedScene).instantiate() as TrackBlockout
		add_child(t)
		_tracks.append(t)
	RoadsideDressing.generate_in_headless = false
	PlayaBackdrop.generate_in_headless = false
	SakuraBackdrop.generate_in_headless = false


func _test_finish() -> void:
	for t in _tracks:
		var label := String(t.name)
		var d := t.get_node("RoadsideDressing") as RoadsideDressing
		check("%s : decor de bord de piste genere" % label, d != null and d.get_node_or_null(^"Dressing") != null)
		if d == null:
			continue
		check_above("%s : cables au-dessus de la route" % label, d.spans.size(), 15.0)
		var worst := INF
		var near_arch := 0
		for sp: Dictionary in d.spans:
			worst = minf(worst, float(sp["low"]) - float(sp["road_top"]))
			for k in t.arch_count():
				var ds := absf(float(sp["s"]) - t.arch_s(k))
				if minf(ds, t.length() - ds) < 60.0:
					near_arch += 1
			if float(sp["s"]) < RoadsideDressing.STANDS_AFTER or float(sp["s"]) > t.length() - RoadsideDressing.STANDS_BEFORE:
				near_arch += 1
		check_above("%s : hauteur libre sous les cables (m)" % label, worst, RoadsideDressing.SPAN_CLEARANCE - 0.01)
		check("%s : aucun cable aux arches ni aux tribunes" % label, near_arch == 0, "%d" % near_arch)
		var on_road := 0
		for p in d.props:
			var i := t.closest_sample(p)
			var q := t.sample_position(i)
			var lateral := absf((p - q).dot((t.sample_right(i) * Vector3(1, 0, 1)).normalized()))
			# (les panneaux de la face interieure des murs penches, vus a
			# l'horizontale dans un virage releve, debordent de ~0,6 m)
			if lateral < t.width / 2.0 - 1.5 and absf(p.y - q.y) < 6.0:
				on_road += 1
		check_above("%s : objets de bord de piste" % label, d.props.size(), 100.0)
		check("%s : aucun objet sur la chaussee" % label, on_road == 0, "%d sur %d" % [on_road, d.props.size()])
		check("%s : decor sans collision" % label, d.find_children("*", "CollisionObject3D", true, false).is_empty())
		# sur la route (RoadDecor, 2026-10-22) : vibreurs au bord, fleches,
		# chevrons, objets volants hors de portee des camions
		var road: Dictionary = d.get_meta(&"road", {})
		var kerbs: PackedVector3Array = road.get("kerbs", PackedVector3Array())
		var flyers: PackedVector3Array = road.get("flyers", PackedVector3Array())
		var off_edge := 0
		for p in kerbs:
			var i := t.closest_sample(p)
			var lat := absf((p - t.sample_position(i)).dot((t.sample_right(i) * Vector3(1, 0, 1)).normalized()))
			if lat < t.width / 2.0 - RoadDecor.KERB_WIDTH - 0.5:
				off_edge += 1
		check("%s : vibreurs au bord de la chaussee, a la corde des virages" % label, kerbs.size() > 20 and off_edge == 0,
			"%d, %d hors du bord" % [kerbs.size(), off_edge])
		check("%s : fleches peintes et chevrons de virage" % label, (road.get("arrows", []) as PackedVector3Array).size() > 8
			and int(road.get("chevrons", 0)) > 20, "%d fleches, %d chevrons" % [(road.get("arrows", []) as PackedVector3Array).size(),
			int(road.get("chevrons", 0))])
		var lowest := INF
		for p in flyers:
			var i := t.closest_sample(p)
			var q := t.sample_position(i)
			var r := t.sample_right(i) * (t.width / 2.0)
			var top := maxf(q.y + r.y, q.y - r.y)
			# point le plus bas de l'objet, au creux de sa montee et descente
			lowest = minf(lowest, p.y - float(road.get("flyer_drop", 0.0)) - top)
		check("%s : objets volants au-dessus des camions" % label, flyers.size() > 20 and lowest >= RoadDecor.SKY_MIN - 0.01,
			"%d, plus bas %.1f m" % [flyers.size(), lowest])
	# sprites lointains
	for spec: Array in [[1, "PlayaBackdrop/Playa", "PalmFar", &"palms"], [2, "SakuraBackdrop/Sakura", "TreesFar", &"trees"]]:
		var t := _tracks[spec[0]]
		var root := t.get_node(String(spec[1]))
		var far := root.get_node_or_null(String(spec[2])) as MultiMeshInstance3D
		var trees: Array = root.get_meta(spec[3], [])
		var mat := (far.multimesh.mesh as QuadMesh).material as ShaderMaterial if far != null else null
		check("%s : un sprite tourne par arbre au loin" % t.name, far != null and far.multimesh.instance_count == trees.size()
			and trees.size() > 100, "%d / %d" % [far.multimesh.instance_count if far != null else 0, trees.size()])
		check("%s : sprite texture (photo du modele)" % t.name, mat != null and mat.get_shader_parameter("albedo") != null)
		var near_ok := true
		var chunks := 0
		for n in root.get_children():
			var mmi := n as MultiMeshInstance3D
			if mmi != null and mmi != far and (String(mmi.name).begins_with("Palm") or String(mmi.name).begins_with("Trunks")
					or String(mmi.name).begins_with("Crowns")):
				chunks += 1
				near_ok = near_ok and is_equal_approx(mmi.visibility_range_end, FarLod.NEAR_END)
		check("%s : arbres 3D par cases, jusqu'a %d m" % [t.name, FarLod.NEAR_END], chunks > 4 and near_ok, "%d cases" % chunks)
