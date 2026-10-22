@tool
class_name PlayaBackdrop
extends Node3D

## Decor de Playa Del Sol autour de la piste parente : palmiers en bordure de
## piste et sur l'ile, parasols sur le sable, rochers et ilots au large, un
## phare. Palmiers et parasols en 3D pres de la camera seulement ; au loin,
## les palmiers sont des sprites tournes (FarLod, 2026-10-22). Purement visuel (aucune collision : un camion qui passe le mur tombe
## dans une zone de reset, il ne percute rien) ; en headless (tests), rien
## n'est genere, sauf si un test le force.
##
## Six MultiMesh (troncs, palmes, parasols, mats, rochers) : six appels de
## rendu pour tout le decor. Placement deterministe (generateur congruentiel a
## graine fixe : aucun aleatoire de jeu, CLAUDE.md §7).

@export var decor_seed: int = 5
## Ecart entre deux palmiers de bordure, le long de la piste (m).
@export var palm_spacing: float = 12.0

## Un test peut forcer la generation en headless.
static var generate_in_headless: bool = false

var _state: int = 1


func _ready() -> void:
	if DisplayServer.get_name() == "headless" and not generate_in_headless:
		return
	var track := get_parent() as TrackBlockout
	if track == null:
		return
	# la piste parente se construit dans SON _ready, apres le notre
	if track.is_node_ready():
		_generate(track)
	else:
		track.ready.connect(_generate.bind(track), CONNECT_ONE_SHOT)


func _rand() -> float:
	_state = (_state * 1103515245 + 12345) & 0x7fffffff
	return float(_state) / 2147483648.0


func _range(a: float, b: float) -> float:
	return a + (b - a) * _rand()


func _generate(track: TrackBlockout) -> void:
	_state = maxi(decor_seed, 1)
	var root := Node3D.new()
	root.name = "Playa"
	add_child(root)
	var ground := TrackBlockout.GROUND_Y
	var half := track.width / 2.0
	var beyond := half + track.wall_thickness + track.wall_lean

	var palms: Array[Transform3D] = []
	var crowns: Array[Transform3D] = []
	var parasols: Array[Transform3D] = []
	var parasol_colors := PackedColorArray()
	var poles: Array[Transform3D] = []
	var tints := [Color(0.95, 0.2, 0.2), Color(1.0, 0.8, 0.1), Color(0.1, 0.6, 0.95), Color(0.98, 0.98, 0.95),
		Color(1.0, 0.45, 0.7), Color(0.2, 0.8, 0.55)]

	var length := track.length()
	var s := 0.0
	while s < length:
		var i := track.index_at_s(s)
		var p := track.sample_position(i)
		var t := (track.sample_forward(i) * Vector3(1, 0, 1)).normalized()
		var r := t.cross(Vector3.UP).normalized()
		var low := p.y < 2.0 and not track.is_bridge_deck(i)
		# les tribunes occupent le bord de piste autour de la ligne de depart
		var stands := s < 124.0 or s > length - 116.0
		for side: float in [-1.0, 1.0]:
			# bordure : un palmier pres du mur (au pied du talus si la route
			# est haute ; rien sous un pont), un autre plus loin
			var foot := track.embankment_reach(i, side)
			for row in 2:
				if row == 0 and (track.is_bridge_deck(i) or stands):
					continue
				if row == 1 and _rand() < 0.45:
					continue
				var lat := beyond + (foot + _range(3.0, 9.0) if row == 0 else _range(22.0, 70.0))
				if row == 1 and not low:
					lat += 55.0
				if row == 1 and stands:
					lat += 8.0
				var c := p + r * side * lat + t * _range(-5.0, 5.0)
				c.y = ground
				if track.is_water(c) or not _clear_of_track(track, c, beyond + 2.0, i):
					continue
				_add_palm(palms, crowns, c)
			# parasols sur le sable, entre la piste et la mer
			if low and not stands and _rand() < 0.6:
				var c := p + r * side * (beyond + _range(14.0, 60.0)) + t * _range(-6.0, 6.0)
				c.y = ground
				if not track.is_water(c) and _clear_of_track(track, c, beyond + 6.0, i):
					var size := _range(1.9, 2.6)
					parasols.append(Transform3D(Basis(Vector3.UP, _rand() * TAU).scaled(Vector3(size, size, size)),
						c + Vector3(0.0, 2.3, 0.0)))
					parasol_colors.append(tints[int(_rand() * tints.size()) % tints.size()])
					poles.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.07, 2.5, 0.07)), c + Vector3(0.0, 1.25, 0.0)))
		s += palm_spacing

	# rochers et ilots au large, tout autour de l'ile
	var rocks: Array[Transform3D] = []
	var center := Vector3.ZERO
	var n := track.sample_count()
	for i in range(0, n, 16):
		center += track.sample_position(i)
	center /= ceilf(n / 16.0)
	center.y = ground
	var tries := 0
	while rocks.size() < 46 and tries < 600:
		tries += 1
		var a := _rand() * TAU
		var d := _range(520.0, 1500.0)
		var c := center + Vector3(cos(a) * d, 0.0, sin(a) * d)
		if not track.is_water(c) or not _clear_of_track(track, c, 260.0):
			continue
		var w := _range(18.0, 70.0) * (1.0 + d / 900.0)
		var h := w * (_range(0.6, 1.5) if _rand() < 0.5 else _range(0.18, 0.35))
		rocks.append(Transform3D(Basis(Vector3.UP, _rand() * TAU).scaled(Vector3(w, h, w * _range(0.7, 1.3))),
			c + Vector3(0.0, -h * 0.15, 0.0)))

	# palmiers : 3D pres de la camera, sprite tourne au loin (FarLod) ;
	# parasols : 3D pres seulement (au loin, ils ne se voient plus)
	var bases := PackedVector3Array()
	var scales := PackedFloat32Array()
	for xf in palms:
		bases.append(xf.origin)
		scales.append(xf.basis.y.length() / float(FarLod.KINDS["palm"]["ref"]))
	FarLod.add(root, "Palm", [
		{"name": "PalmTrunks", "mesh": _trunk_mesh(), "xfs": palms},
		{"name": "PalmCrowns", "mesh": _crown_mesh(), "xfs": crowns}], "palm", bases, scales)
	FarLod.add(root, "Parasol", [
		{"name": "Parasols", "mesh": _parasol_mesh(), "xfs": parasols, "colors": parasol_colors},
		{"name": "ParasolPoles", "mesh": _pole_mesh(), "xfs": poles, "shadows": false}])
	root.add_child(_multimesh("Rocks", _rock_mesh(), rocks, PackedColorArray(), true))
	_add_lighthouse(root, track, beyond)
	# positions gardees a part : le rendu factice du headless ne relit pas les
	# transformations des MultiMesh (tests)
	root.set_meta(&"palms", palms.duplicate())
	root.set_meta(&"rocks", rocks.duplicate())
	root.set_meta(&"parasols", parasols.duplicate())
	# rien sur un raccourci (2026-10-20)
	track.clear_branch_corridors(self)


## Un palmier : tronc penche au hasard, couronne de palmes au sommet.
func _add_palm(palms: Array[Transform3D], crowns: Array[Transform3D], at: Vector3) -> void:
	var h := _range(9.0, 15.0)
	var b := Basis(Vector3.UP, _rand() * TAU).scaled(Vector3(h, h, h))
	palms.append(Transform3D(b, at))
	var top := at + b * Vector3(0.14, 1.0, 0.0)
	var cs := h * _range(0.42, 0.55)
	crowns.append(Transform3D(Basis(Vector3.UP, _rand() * TAU).scaled(Vector3(cs, cs, cs)), top))


## Vrai si `c` est a plus de `margin` de l'axe de la piste. `hint` >= 0 :
## recherche locale autour de cet echantillon (decor pose le long de la piste).
static func _clear_of_track(track: TrackBlockout, c: Vector3, margin: float, hint: int = -1) -> bool:
	var i := track.closest_sample(c, hint)
	var p := track.sample_position(i)
	return Vector2(c.x - p.x, c.z - p.z).length() > margin


## Phare raye rouge et blanc, sur la terre, a l'exterieur du premier virage.
func _add_lighthouse(root: Node3D, track: TrackBlockout, beyond: float) -> void:
	var i := track.index_at_s(track.segment_start_s("Montee de la corniche") + 40.0)
	var p := track.sample_position(i)
	var t := (track.sample_forward(i) * Vector3(1, 0, 1)).normalized()
	var base := p + t.cross(Vector3.UP).normalized() * (beyond + 75.0)
	base.y = TrackBlockout.GROUND_Y
	root.add_child(build_lighthouse(base))


## Phare raye rouge et blanc pose en `base` (aussi le decor du menu, Showroom).
static func build_lighthouse(base: Vector3) -> Node3D:
	var tower := Node3D.new()
	tower.name = "Lighthouse"
	tower.position = base
	var white := _flat(Color(0.95, 0.95, 0.92))
	var red := _flat(Color(0.85, 0.12, 0.1))
	var y := 0.0
	for k in 6:
		var cm := CylinderMesh.new()
		cm.bottom_radius = 5.0 - k * 0.45
		cm.top_radius = 5.0 - (k + 1) * 0.45
		cm.height = 7.0
		cm.radial_segments = 20
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = white if k % 2 == 0 else red
		mi.position = Vector3(0.0, y + 3.5, 0.0)
		tower.add_child(mi)
		y += 7.0
	var lamp := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 2.0
	lm.bottom_radius = 2.0
	lm.height = 3.0
	lamp.mesh = lm
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(1.0, 0.95, 0.7)
	glass.emission_enabled = true
	glass.emission = Color(1.0, 0.92, 0.6)
	glass.emission_energy_multiplier = 3.0
	lamp.material_override = glass
	lamp.position = Vector3(0.0, y + 1.5, 0.0)
	tower.add_child(lamp)
	var roof := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.0
	rm.bottom_radius = 2.8
	rm.height = 2.5
	roof.mesh = rm
	roof.material_override = red
	roof.position = Vector3(0.0, y + 4.2, 0.0)
	tower.add_child(roof)
	return tower


static func _flat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.8
	return m


static func _multimesh(node_name: String, mesh: Mesh, xfs: Array[Transform3D], colors: PackedColorArray,
		shadows: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


## Tronc : tube effile, legerement courbe, haut de 1 (mis a l'echelle).
static func _trunk_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 7
	var sides := 7
	var pts: Array[PackedVector3Array] = []
	for k in rings + 1:
		var u := float(k) / rings
		var radius := lerpf(0.034, 0.02, u) * (1.0 + 0.25 * (1.0 - u) * (1.0 - u))
		var c := Vector3(0.14 * u * u, u, 0.0)
		var ring := PackedVector3Array()
		for j in sides:
			var a := TAU * j / sides
			ring.append(c + Vector3(cos(a), 0.0, sin(a)) * radius)
		pts.append(ring)
	for k in rings:
		for j in sides:
			var j2 := (j + 1) % sides
			var a := pts[k][j]
			var b := pts[k][j2]
			var c := pts[k + 1][j2]
			var d := pts[k + 1][j]
			for v: Array in [[a, float(k)], [c, float(k + 1)], [b, float(k)], [a, float(k)], [d, float(k + 1)], [c, float(k + 1)]]:
				st.set_uv(Vector2(0.0, v[1]))
				st.add_vertex(v[0])
	st.generate_normals()
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://tracks/materials/playa_palm.gdshader")
	mat.set_shader_parameter("trunk", true)
	mesh.surface_set_material(0, mat)
	return mesh


## Couronne : 10 palmes qui montent puis retombent, pliees en V, rayon 1.
static func _crown_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fronds := 10
	var segs := 6
	for f in fronds:
		var a := TAU * f / fronds + 0.35 * sin(f * 2.4)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var across := Vector3(-dir.z, 0.0, dir.x)
		var lift := 0.35 + 0.25 * sin(f * 1.7)
		var rows: Array[PackedVector3Array] = []
		for k in segs + 1:
			var u := float(k) / segs
			var spine := dir * u + Vector3.UP * (lift * u - (0.75 + 0.3 * lift) * u * u)
			var w := 0.17 * pow(sin(PI * clampf(u * 0.96 + 0.04, 0.0, 1.0)), 0.75)
			rows.append(PackedVector3Array([spine - across * w - Vector3.UP * w * 0.45, spine,
				spine + across * w - Vector3.UP * w * 0.45]))
		for k in segs:
			for half in 2:
				var p0 := rows[k][half]
				var p1 := rows[k][half + 1]
				var p2 := rows[k + 1][half + 1]
				var p3 := rows[k + 1][half]
				var u0 := float(k) / segs
				var u1 := float(k + 1) / segs
				var x0 := half * 0.5
				var x1 := half * 0.5 + 0.5
				for v: Array in [[p0, x0, u0], [p2, x1, u1], [p1, x1, u0], [p0, x0, u0], [p3, x0, u1], [p2, x1, u1]]:
					st.set_uv(Vector2(v[1], v[2]))
					st.add_vertex(v[0])
	st.generate_normals()
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://tracks/materials/playa_palm.gdshader")
	mat.set_shader_parameter("trunk", false)
	mesh.surface_set_material(0, mat)
	return mesh


## Toile de parasol : cone aplati de rayon 1, couleur par instance.
static func _parasol_mesh() -> Mesh:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.04
	cm.bottom_radius = 1.0
	cm.height = 0.32
	cm.radial_segments = 10
	cm.rings = 1
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cm.material = mat
	return cm


static func _pole_mesh() -> Mesh:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.5
	cm.bottom_radius = 0.5
	cm.height = 1.0
	cm.radial_segments = 6
	cm.material = _flat(Color(0.9, 0.9, 0.88))
	return cm


## Rocher : sphere grossiere cabossee (deterministe), rayon ~0,5.
static func _rock_mesh() -> Mesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 12
	sphere.rings = 6
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for k in verts.size():
		var v := verts[k]
		var bump := 1.0 + 0.22 * sin(v.x * 9.0 + v.y * 5.0) * sin(v.z * 7.0 + v.y * 3.0) + 0.12 * sin(v.y * 13.0)
		verts[k] = Vector3(v.x * bump, maxf(v.y, -0.2) * bump, v.z * bump)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = null
	arrays[Mesh.ARRAY_TANGENT] = null
	var st := SurfaceTool.new()
	var tmp := ArrayMesh.new()
	tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	st.create_from(tmp, 0)
	st.generate_normals()
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://tracks/materials/playa_rock.gdshader")
	mesh.surface_set_material(0, mat)
	return mesh
