@tool
class_name CityBuilder
extends RefCounted

## Megalopole de decor (Cyber City) : tours a fenetres allumees, antennes a feu
## clignotant, enseignes neon sur les toits. Purement visuelle : aucune
## collision, aucune ombre portee (quatre vues en ecran partage).
##
## Trois MultiMesh d'un cube unite (tours, antennes, enseignes) : trois appels
## de rendu pour toute la ville. Le motif des fenetres, les neons et les
## clignotements sont dans les shaders (tracks/materials/city_*.gdshader).
##
## Placement deterministe : un generateur congruentiel a graine fixe (aucun
## aleatoire de jeu, CLAUDE.md §7), et un test d'encombrement (cercles) pour
## que deux tours ne se chevauchent jamais.

const BUILDING_SHADER := preload("res://tracks/materials/city_building.gdshader")
const ANTENNA_SHADER := preload("res://tracks/materials/city_antenna.gdshader")
const SIGN_SHADER := preload("res://tracks/materials/city_sign.gdshader")

## Ecart minimal entre deux emprises (m).
const GAP := 4.0

var buildings: Array[Transform3D] = []
var building_data: PackedColorArray = []
var antennas: Array[Transform3D] = []
var antenna_data: PackedColorArray = []
var signs: Array[Transform3D] = []
var sign_data: PackedColorArray = []
## Emprises posees : (x, z, rayon).
var footprints: PackedVector3Array = []
## Face de chaque tour tournee vers la piste (ZERO : couronne de l'horizon).
var facings: PackedVector3Array = []

var _state: int


func _init(seed_value: int) -> void:
	_state = maxi(seed_value, 1)


## Nombre pseudo-aleatoire dans [0, 1[ (generateur congruentiel, graine fixe).
func rand() -> float:
	_state = (_state * 1103515245 + 12345) & 0x7fffffff
	return float(_state) / 2147483648.0


func rand_range(a: float, b: float) -> float:
	return a + (b - a) * rand()


## Pose une tour si son emprise est libre. `facing` (horizontal) : direction
## vers laquelle une enseigne de toit se tourne (ZERO = pas d'enseigne).
func try_building(center: Vector3, w: float, d: float, h: float, yaw: float, facing: Vector3) -> bool:
	var radius := 0.5 * sqrt(w * w + d * d)
	for f in footprints:
		if Vector2(center.x - f.x, center.z - f.y).length() < radius + f.z + GAP:
			return false
	footprints.append(Vector3(center.x, center.z, radius))
	facings.append(facing.normalized() if facing != Vector3.ZERO else Vector3.ZERO)
	var b := Basis(Vector3.UP, yaw)
	buildings.append(Transform3D(b.scaled_local(Vector3(w, h, d)), center + Vector3(0.0, h / 2.0, 0.0)))
	building_data.append(Color(rand(), floorf(rand() * 4.0) / 4.0 + 0.01, rand_range(0.22, 0.6),
		1.0 if rand() < 0.55 else 0.0))
	var top := center.y + h
	if rand() < 0.35:
		var ah := rand_range(6.0, 16.0)
		var off := b * Vector3(rand_range(-0.3, 0.3) * w, 0.0, rand_range(-0.3, 0.3) * d)
		antennas.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.5, ah, 0.5)),
			center + off + Vector3(0.0, top - center.y + ah / 2.0, 0.0)))
		antenna_data.append(Color(rand(), 0.0, 0.0, 0.0))
	if facing != Vector3.ZERO and rand() < 0.4:
		var fz := facing.normalized()
		var sb := Basis(Vector3.UP.cross(fz).normalized(), Vector3.UP, fz)
		var sw := minf(w, d) * rand_range(0.55, 0.85)
		var sh := rand_range(4.0, 9.0)
		var edge := minf(w, d) * 0.5 - 1.0
		signs.append(Transform3D(sb.scaled_local(Vector3(sw, sh, 0.4)),
			center + fz * edge + Vector3(0.0, top - center.y + sh / 2.0 + 0.6, 0.0)))
		sign_data.append(Color(rand(), floorf(rand() * 4.0) / 4.0 + 0.01, 0.0, 0.0))
	return true


## Couronne de tours autour de `center`, entre r_min et r_max : la ligne
## d'horizon. Les enseignes regardent le centre.
func add_ring(center: Vector3, r_min: float, r_max: float, count: int, h_min: float, h_max: float) -> void:
	var tries := count * 4
	var placed := 0
	while placed < count and tries > 0:
		tries -= 1
		var a := rand() * TAU
		var r := sqrt(rand_range(r_min * r_min, r_max * r_max))
		var c := center + Vector3(cos(a) * r, 0.0, sin(a) * r)
		var w := rand_range(24.0, 60.0)
		var d := rand_range(24.0, 60.0)
		var h := rand_range(h_min, h_max) * (1.0 if rand() < 0.8 else 1.5)
		if try_building(c, w, d, h, rand() * TAU, (center - c) * Vector3(1, 0, 1)):
			placed += 1


## Construit les trois MultiMesh sous un Node3D.
func build(node_name: String = "City") -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	root.add_child(_multimesh("Buildings", buildings, building_data, BUILDING_SHADER))
	root.add_child(_multimesh("Antennas", antennas, antenna_data, ANTENNA_SHADER))
	root.add_child(_multimesh("Signs", signs, sign_data, SIGN_SHADER))
	# emprises gardees a part : le rendu factice du headless ne relit pas les
	# transformations des MultiMesh (tests)
	root.set_meta(&"buildings", buildings.duplicate())
	return root


static func _multimesh(node_name: String, xfs: Array[Transform3D], data: PackedColorArray,
		shader: Shader) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var box := BoxMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = shader
	box.material = mat
	mm.mesh = box
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_custom_data(i, data[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# hors de l'eclairage global (2026-10-22, « en haute et extreme les
	# batiments deviennent blancs ») : les milliers de fenetres lumineuses
	# l'alimentaient et il rallumait toute la ville en gris clair
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return mmi


## Ville autour d'une piste : deux rangees de tours de chaque cote, tournees
## vers la piste, toujours au-dela des zones de reset (un camion qui sort
## retombe dans une zone de reset avant d'atteindre une tour), puis une
## couronne de gratte-ciel a l'horizon.
static func around_track(track: TrackBlockout, seed_value: int) -> Node3D:
	var cb := CityBuilder.new(seed_value)
	var length := track.length()
	var half := track.width / 2.0
	var clear := half + track.wall_thickness + track.wall_lean + track.reset_zone_margin \
			+ track.reset_zone_depth + 8.0
	# ligne centrale grossiere (tous les 8 m) pour les tests de degagement
	var coarse := PackedVector2Array()
	var n := track.sample_count()
	var every := maxi(1, roundi(8.0 / (length / n)))
	for i in range(0, n, every):
		var p := track.sample_position(i)
		coarse.append(Vector2(p.x, p.z))
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c in coarse:
		lo = lo.min(c)
		hi = hi.max(c)
	# qualite extreme : tours plus serrees, couronne plus fournie, et les tours
	# des rangees detaillees (build_details)
	var x := GraphicsSettings.extreme_assets()
	var s := 0.0
	while s < length:
		var i := track.index_at_s(s)
		var p := track.sample_position(i)
		var t := track.sample_forward(i) * Vector3(1, 0, 1)
		t = t.normalized()
		var r := t.cross(Vector3.UP).normalized()
		for side: float in [-1.0, 1.0]:
			for row in 2:
				var w := cb.rand_range(16.0, 34.0)
				var d := cb.rand_range(16.0, 34.0)
				var lat := clear + (cb.rand_range(12.0, 30.0) if row == 0 else cb.rand_range(70.0, 130.0))
				var h := cb.rand_range(16.0, 55.0) if row == 0 else cb.rand_range(35.0, 120.0)
				var c := p + r * side * lat + t * cb.rand_range(-6.0, 6.0)
				c.y = TrackBlockout.GROUND_Y
				var radius := 0.5 * sqrt(w * w + d * d)
				if _min_distance(Vector2(c.x, c.z), coarse) < clear + radius:
					continue
				cb.try_building(c, w, d, h, atan2(-t.x, -t.z), -r * side)
		s += 18.0 if x else 24.0
	var center := Vector3((lo.x + hi.x) / 2.0, TrackBlockout.GROUND_Y, (lo.y + hi.y) / 2.0)
	var span := maxf(hi.x - lo.x, hi.y - lo.y)
	var near := cb.buildings.size()
	cb.add_ring(center, span / 2.0 + 420.0, span / 2.0 + 1050.0, 240 if x else 170, 70.0, 230.0)
	var city := cb.build()
	if x:
		city.add_child(cb.build_details(near))
	return city


## Qualite extreme (2026-10-22, « les buildings trop simples, detaille-les ») :
## sur les `near` premieres tours (les rangees le long de la piste), une
## corniche a chaque etage tout autour, un acrotere, des blocs de
## climatisation, un chateau d'eau ou un edicule d'escalier, et une enseigne
## verticale lumineuse sur la face tournee vers la piste (a la japonaise).
## Fusionnes par case de DETAIL_CELL m (RoadsideDressing.Batch).
const DETAIL_CELL := 300.0
const DETAIL_VIEW := 1400.0
## Noir mat comme les facades (2026-10-22 : en gris clair, les corniches
## rayaient les tours de blanc en qualite extreme)
const CONCRETE := Color(0.03, 0.033, 0.045)
const ROOF_GREY := Color(0.05, 0.052, 0.06)
const SIGN_NEON: Array[Color] = [Color(0.1, 0.95, 1.0), Color(1.0, 0.15, 0.75), Color(0.6, 0.3, 1.0), Color(1.0, 0.85, 0.15),
	Color(0.3, 1.0, 0.5)]


func build_details(near: int) -> Node3D:
	var batches := {}
	for k in mini(near, buildings.size()):
		var xf := buildings[k]
		var key := Vector2i(floori(xf.origin.x / DETAIL_CELL), floori(xf.origin.z / DETAIL_CELL))
		if not batches.has(key):
			batches[key] = RoadsideDressing.Batch.new(Vector3((key.x + 0.5) * DETAIL_CELL, 0.0,
				(key.y + 0.5) * DETAIL_CELL))
		_detail_tower(batches[key], xf, facings[k] if k < facings.size() else Vector3.ZERO)
	var solid := StandardMaterial3D.new()
	solid.vertex_color_use_as_albedo = true
	solid.roughness = 0.92
	solid.metallic_specular = 0.1
	var glow := ShaderMaterial.new()
	glow.shader = preload("res://tracks/materials/dress_glow.gdshader")
	glow.set_shader_parameter("glow", 2.6)
	var mats := {"solid": solid, "glow": glow}
	var root := Node3D.new()
	root.name = "Details"
	var n := 0
	for key: Vector2i in batches:
		var batch: RoadsideDressing.Batch = batches[key]
		var mi := MeshInstance3D.new()
		mi.name = "Cell%d" % n
		mi.mesh = batch.commit(mats)
		mi.position = batch.origin
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.visibility_range_end = DETAIL_VIEW
		root.add_child(mi)
		n += 1
	return root


func _detail_tower(batch: RoadsideDressing.Batch, xf: Transform3D, facing: Vector3) -> void:
	var ux := xf.basis.x.normalized()
	var uy := Vector3.UP
	var uz := xf.basis.z.normalized()
	var w := xf.basis.x.length()
	var h := xf.basis.y.length()
	var d := xf.basis.z.length()
	var b := Basis(ux, uy, uz)
	var base := xf.origin - Vector3(0, h / 2.0, 0)
	var top := base + Vector3(0, h, 0)
	# corniches d'etage (au plus 14, reparties sur la hauteur)
	var step := maxf(4.2, (h - 8.0) / 14.0)
	var y := 6.0
	while y < h - 2.5:
		var at := base + Vector3(0, y, 0)
		for sgn: float in [-1.0, 1.0]:
			batch.box("solid", Transform3D(b, at + uz * sgn * (d / 2.0 + 0.15)), Vector3(w + 0.6, 0.22, 0.3), CONCRETE)
			batch.box("solid", Transform3D(b, at + ux * sgn * (w / 2.0 + 0.15)), Vector3(0.3, 0.22, d + 0.6), CONCRETE)
		y += step
	# acrotere
	for sgn: float in [-1.0, 1.0]:
		batch.box("solid", Transform3D(b, top + Vector3(0, 0.5, 0) + uz * sgn * (d / 2.0 - 0.18)), Vector3(w, 1.0, 0.36), CONCRETE)
		batch.box("solid", Transform3D(b, top + Vector3(0, 0.5, 0) + ux * sgn * (w / 2.0 - 0.18)), Vector3(0.36, 1.0, d), CONCRETE)
	# toit : climatisation, chateau d'eau ou edicule
	for q in 2 + int(rand() * 3.0):
		var p := top + ux * rand_range(-0.3, 0.3) * w + uz * rand_range(-0.3, 0.3) * d + Vector3(0, 0.65, 0)
		batch.box("solid", Transform3D(b, p), Vector3(2.2, 1.3, 1.6), ROOF_GREY)
		batch.box("solid", Transform3D(b, p + Vector3(0, 0.7, 0)), Vector3(1.2, 0.1, 1.2), Color(0.12, 0.12, 0.14))
	var corner := top + ux * w * 0.28 - uz * d * 0.25
	if rand() < 0.5:
		batch.tube("solid", corner, corner + Vector3(0, 3.2, 0), 1.5, 10, Color(0.08, 0.06, 0.05))
		batch.cone("solid", corner + Vector3(0, 3.2, 0), 1.6, 0.9, 10, Color(0.05, 0.04, 0.035))
		for leg: Vector3 in [ux, -ux, uz, -uz]:
			batch.box("solid", Transform3D(b, corner + leg * 1.1 - Vector3(0, 0.0, 0)), Vector3(0.15, 0.6, 0.15), CONCRETE)
	else:
		batch.box("solid", Transform3D(b, corner + Vector3(0, 1.6, 0)), Vector3(3.5, 3.2, 3.5), CONCRETE)
	# enseigne verticale sur la face tournee vers la piste
	if facing == Vector3.ZERO or h < 18.0:
		return
	var fx := ux.dot(facing)
	var fz := uz.dot(facing)
	var out := ux * signf(fx) if absf(fx) > absf(fz) else uz * signf(fz)
	var along := uz if absf(fx) > absf(fz) else ux
	var half_out := (w if absf(fx) > absf(fz) else d) / 2.0
	var half_along := (d if absf(fx) > absf(fz) else w) / 2.0
	var sh := clampf(h * 0.45, 6.0, 26.0)
	var c := base + Vector3(0, h * 0.28 + sh / 2.0, 0) + out * (half_out + 0.9) + along * half_along * 0.62 * (1.0 if rand() < 0.5 else -1.0)
	var sb := Basis(along, uy, out)
	var col: Color = SIGN_NEON[int(rand() * SIGN_NEON.size()) % SIGN_NEON.size()]
	batch.box("solid", Transform3D(sb, c - out * 0.12), Vector3(1.9, sh + 0.5, 0.3), Color(0.05, 0.05, 0.07))
	batch.box("glow", Transform3D(sb, c + out * 0.06), Vector3(1.5, sh, 0.12), col)
	# separations sombres : des caracteres empiles
	var chars := maxi(3, roundi(sh / 2.4))
	for q in range(1, chars):
		batch.box("solid", Transform3D(sb, c + out * 0.14 + Vector3(0, -sh / 2.0 + sh * q / chars, 0)), Vector3(1.55, 0.18, 0.06),
			Color(0.05, 0.05, 0.07))
	# potences qui la tiennent au mur
	for q: float in [-0.4, 0.4]:
		batch.box("solid", Transform3D(sb, c + Vector3(0, sh * q, 0) - out * 0.55), Vector3(0.12, 0.12, 0.9), CONCRETE)


static func _min_distance(p: Vector2, pts: PackedVector2Array) -> float:
	var best := INF
	for q in pts:
		best = minf(best, p.distance_squared_to(q))
	return sqrt(best)
