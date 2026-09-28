@tool
class_name TrackBlockout
extends Node3D

## Piste de blockout generee a partir d'une liste de segments (tache 2.2).
##
## Le trace est une suite de droites et d'arcs de rayon choisi : chaque rayon se
## derive des metriques mesurees (baseline.json, docs/METRICS.md). Deux droites
## marquees "auto" voient leur longueur CALCULEE pour que la boucle se referme
## exactement : on peut modifier un virage sans recoudre le trace a la main.
##
## Segment (Dictionary) :
##   {"type": "straight", "length": m}           ou  {"type": "straight", "auto": true}
##   {"type": "arc", "radius": m, "angle": deg}  (angle > 0 : a gauche)
## Options de segment :
##   "bank": deg    devers : > 0 leve le bord DROIT (virage a gauche releve,
##                  ou virage a droite en devers inverse). Raccord progressif.
##   "climb": m     denivele sur le segment (raccord en S, pentes douces).
##   "line": m      decalage lateral de la ligne de course (> 0 a droite).
##   "jump": m      tremplin a cette distance du debut du segment, cote droit.
##
## Genere : Geometry (chaussee, sol, tremplin), Walls (2 glissieres continues),
## ResetZones (Area3D au-dela des murs, tout autour), StartGrid, RacingLine.
## Checkpoints : tache 2.3.
##
## La piste ne decide rien (track-designer.md) : elle EMET un signal quand un
## camion entre dans une zone de reset ou en sort ; le gameplay (AutoReset,
## puis RaceManager) decide de le replacer.

signal truck_entered_reset_zone(truck: Node3D)
signal truck_exited_reset_zone(truck: Node3D)

const ROAD_LAYER := 1          # couche 1 `world` (VEHICLE_SPEC §7)
const RESET_ZONE_LAYER := 4    # couche 4 `reset_zone`
const VEHICLE_LAYER := 2
const GROUND_Y := -0.05        # sol sous la chaussee (evite le z-fighting)

@export var segments: Array[Dictionary] = []
## Largeur de chaussee entre les murs (METRICS.md §4 : 14 m minimum).
@export var width: float = 14.0
## Pas d'echantillonnage de la ligne centrale.
@export var sample_step: float = 2.0
## Longueur des raccords de devers et de ligne de course.
@export var blend_length: float = 30.0

@export_group("Glissieres")
## Epaisseur a hauteur de chaussee (METRICS.md §4 : 0,3 m minimum).
@export var wall_thickness: float = 0.3
@export var wall_height: float = 1.4
## Porte-a-faux du haut du mur vers la piste : la face interieure penche vers
## la chaussee, le contact pousse le camion vers le bas, jamais vers le haut.
@export var wall_lean: float = 0.15
## Frottement nul : un camion qui touche le mur glisse le long, il ne s'y
## accroche pas.
@export var wall_friction: float = 0.0

@export_group("Tremplin")
@export var jump_length: float = 10.0
@export var jump_angle_deg: float = 8.0
@export var jump_width: float = 4.8
## Decalage lateral du centre du tremplin (> 0 : a droite).
@export var jump_offset: float = 4.2

@export_group("Zones de reset")
## Longueur d'une zone le long de la piste (courte : suit les courbes).
@export var reset_zone_length: float = 20.0
## Ecart entre le haut exterieur du mur et le bord interieur de la zone : une
## remorque qui frotte le mur ne doit jamais y entrer.
@export var reset_zone_margin: float = 2.0
@export var reset_zone_depth: float = 60.0
@export var reset_zone_height: float = 40.0

@export_group("Grille")
@export var grid_distance: float = 12.0
@export var grid_row_spacing: float = 9.0
@export var grid_lateral: PackedFloat32Array = [-4.5, -1.5, 1.5, 4.5]

@export_tool_button("Reconstruire") var _rebuild_button: Callable = rebuild

## Echantillons de la ligne centrale (boucle fermee : le dernier rejoint le premier).
var _pos: PackedVector3Array = []
var _right: PackedVector3Array = []     # lateral, devers applique
var _up: PackedVector3Array = []        # normale de chaussee, devers applique
var _fwd: PackedVector3Array = []       # tangente (sens de course)
var _s: PackedFloat32Array = []
var _curv: PackedFloat32Array = []      # courbure signee (1/m), > 0 a gauche
var _line: PackedFloat32Array = []
var _length: float = 0.0
var _jumps: Array[Vector2] = []         # (s du tremplin, decalage)
var _auto_lengths: PackedFloat32Array = []


func _ready() -> void:
	if _pos.is_empty():
		rebuild()


## Construit la piste si ce n'est pas deja fait : l'interface marche avant
## _ready (ordre d'initialisation indifferent).
func _ensure_built() -> void:
	if _pos.is_empty() and not segments.is_empty():
		rebuild()


func rebuild() -> void:
	for c in get_children():
		if c.has_meta(&"generated"):
			remove_child(c)
			c.queue_free()
	if segments.is_empty():
		return
	if not _build_centerline():
		return
	_build_geometry()


# --- interface (gameplay, tests, IA) --------------------------------------------

func length() -> float:
	_ensure_built()
	return _length


func sample_count() -> int:
	_ensure_built()
	return _pos.size()


func sample_position(i: int) -> Vector3:
	return _pos[posmod(i, _pos.size())]


func sample_right(i: int) -> Vector3:
	return _right[posmod(i, _pos.size())]


func sample_up(i: int) -> Vector3:
	return _up[posmod(i, _pos.size())]


func sample_forward(i: int) -> Vector3:
	return _fwd[posmod(i, _pos.size())]


func sample_s(i: int) -> float:
	return _s[posmod(i, _pos.size())]


func curvature(i: int) -> float:
	return _curv[posmod(i, _pos.size())]


func line_offset(i: int) -> float:
	return _line[posmod(i, _pos.size())]


## Indice de l'echantillon situe `distance` metres plus loin (sens de course).
func sample_ahead(i: int, distance: float) -> int:
	return posmod(i + roundi(distance / (_length / _pos.size())), _pos.size())


## Echantillon le plus proche. Avec `hint` >= 0, recherche locale (+/- 40 m) :
## c'est le cas d'un camion suivi tick apres tick.
func closest_sample(p: Vector3, hint: int = -1) -> int:
	_ensure_built()
	var n := _pos.size()
	var best := 0
	var best_d := INF
	if hint >= 0:
		var span := ceili(40.0 / (_length / n))
		for k in range(-span, span + 1):
			var i := posmod(hint + k, n)
			var d := _pos[i].distance_squared_to(p)
			if d < best_d:
				best_d = d
				best = i
		return best
	for i in n:
		var d := _pos[i].distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = i
	return best


## Repere pose sur la chaussee a l'echantillon i, decale lateralement, oriente
## dans le sens de course (avant du camion en -Z), `lift` metres au-dessus.
func frame_at(i: int, lateral: float, lift: float) -> Transform3D:
	var r := sample_right(i)
	var u := sample_up(i)
	var f := sample_forward(i)
	return Transform3D(Basis(r, u, -f), sample_position(i) + r * lateral + u * lift)


## Case de depart `slot` (0 = pole) : rangs de 4 derriere la ligne.
@warning_ignore("integer_division")
func get_start_transform(slot: int) -> Transform3D:
	_ensure_built()
	var row := slot / grid_lateral.size()
	var col := slot % grid_lateral.size()
	var s := _length - grid_distance - row * grid_row_spacing
	var i := roundi(s / (_length / _pos.size()))
	return frame_at(i, grid_lateral[col], 0.0)


## Reapparition au plus pres de `p` : sur la chaussee, dans le sens de course,
## ecart lateral conserve mais ramene a 2 m des murs, 1 m au-dessus du sol.
func get_respawn_transform(p: Vector3) -> Transform3D:
	_ensure_built()
	var i := closest_sample(p)
	var lateral := (p - sample_position(i)).dot(sample_right(i))
	var limit := width / 2.0 - 2.0
	return frame_at(i, clampf(lateral, -limit, limit), 1.0)


# --- ligne centrale -------------------------------------------------------------

## Integre le trace, resout les droites "auto", reechantillonne, calcule les
## reperes (devers compris). Faux si le trace ne se referme pas.
func _build_centerline() -> bool:
	var autos: Array[int] = []
	for k in segments.size():
		if segments[k].get("auto", false):
			autos.append(k)
	var lengths := PackedFloat32Array()
	lengths.resize(segments.size())
	for k in segments.size():
		lengths[k] = _segment_length(segments[k], 0.0)
	if autos.size() == 2:
		# fermeture lineaire en fonction des deux longueurs libres
		var e0 := _endpoint(lengths)
		lengths[autos[0]] = 1.0
		var e1 := _endpoint(lengths)
		lengths[autos[0]] = 0.0
		lengths[autos[1]] = 1.0
		var e2 := _endpoint(lengths)
		var a := e1 - e0
		var b := e2 - e0
		var det := a.x * b.y - b.x * a.y
		var l1 := (-e0.x * b.y + b.x * e0.y) / det
		var l2 := (-a.x * e0.y + a.y * e0.x) / det
		if l1 <= 0.0 or l2 <= 0.0:
			push_error("TrackBlockout : fermeture impossible (droites auto %.1f / %.1f m)" % [l1, l2])
			return false
		lengths[autos[0]] = l1
		lengths[autos[1]] = l2
		_auto_lengths = [l1, l2]
	var end := _endpoint(lengths)
	if end.length() > 0.05:
		push_warning("TrackBlockout : la boucle ne se referme pas (ecart %.2f m)" % end.length())

	# integration fine, puis reechantillonnage a pas regulier
	var fine_p: Array[Vector2] = []
	var fine_s := PackedFloat32Array()
	var fine_seg := PackedInt32Array()
	var fine_u := PackedFloat32Array()
	var x := 0.0
	var z := 0.0
	var th := 0.0
	var s := 0.0
	fine_p.append(Vector2.ZERO)
	fine_s.append(0.0)
	fine_seg.append(0)
	fine_u.append(0.0)
	for k in segments.size():
		var seg: Dictionary = segments[k]
		var L := lengths[k]
		var n := maxi(1, ceili(L / 0.25))
		var h := L / n
		var turn := 0.0
		if seg.get("type", "straight") == "arc":
			turn = signf(float(seg["angle"])) / float(seg["radius"])
		for j in n:
			th += turn * h
			x += -sin(th) * h
			z += -cos(th) * h
			s += h
			fine_p.append(Vector2(x, z))
			fine_s.append(s)
			fine_seg.append(k)
			fine_u.append(float(j + 1) / n)
	_length = s
	var count := maxi(8, roundi(_length / sample_step))
	var ds := _length / count
	_pos.resize(count)
	_s.resize(count)
	_curv.resize(count)
	var raw_bank := PackedFloat32Array()
	raw_bank.resize(count)
	var raw_line := PackedFloat32Array()
	raw_line.resize(count)
	var seg_of := PackedInt32Array()
	seg_of.resize(count)
	var climb_base := PackedFloat32Array()
	climb_base.resize(segments.size())
	var yb := 0.0
	for k in segments.size():
		climb_base[k] = yb
		yb += float(segments[k].get("climb", 0.0))
	if absf(yb) > 0.01:
		push_warning("TrackBlockout : le denivele total n'est pas nul (%.2f m)" % yb)
	_jumps.clear()
	var jump_done: Dictionary = {}
	var f := 0
	for i in count:
		var si := i * ds
		while f < fine_s.size() - 2 and fine_s[f + 1] < si:
			f += 1
		var w := clampf((si - fine_s[f]) / maxf(fine_s[f + 1] - fine_s[f], 1e-6), 0.0, 1.0)
		var p2 := fine_p[f].lerp(fine_p[f + 1], w)
		var k := fine_seg[f + 1]
		var seg: Dictionary = segments[k]
		var u := lerpf(fine_u[f], fine_u[f + 1], w) if fine_seg[f] == k else w * fine_u[f + 1]
		var y := climb_base[k] + float(seg.get("climb", 0.0)) * smoothstep(0.0, 1.0, u)
		_pos[i] = Vector3(p2.x, y, p2.y)
		_s[i] = si
		seg_of[i] = k
		_curv[i] = 0.0
		if seg.get("type", "straight") == "arc":
			_curv[i] = signf(float(seg["angle"])) / float(seg["radius"])
		raw_bank[i] = float(seg.get("bank", 0.0))
		raw_line[i] = float(seg.get("line", 0.0))
		if seg.has("jump") and not jump_done.has(k) and u * lengths[k] >= float(seg["jump"]):
			jump_done[k] = true
			_jumps.append(Vector2(si, jump_offset))
	var bank := _smooth_loop(_smooth_loop(raw_bank, blend_length / ds / 2.0), blend_length / ds / 2.0)
	_line = _smooth_loop(_smooth_loop(raw_line, blend_length / ds), blend_length / ds)

	# reperes : tangente, lateral horizontal, puis devers autour de la tangente
	_fwd.resize(count)
	_right.resize(count)
	_up.resize(count)
	for i in count:
		var t := (_pos[(i + 1) % count] - _pos[(i - 1 + count) % count]).normalized()
		var r := t.cross(Vector3.UP).normalized()
		var up := r.cross(t).normalized()
		var b := deg_to_rad(bank[i])
		_fwd[i] = t
		_right[i] = r * cos(b) + up * sin(b)
		_up[i] = up * cos(b) - r * sin(b)
	return true


func _segment_length(seg: Dictionary, auto_value: float) -> float:
	if seg.get("type", "straight") == "arc":
		return float(seg["radius"]) * deg_to_rad(absf(float(seg["angle"])))
	if seg.get("auto", false):
		return auto_value
	return float(seg.get("length", 0.0))


## Point d'arrivee (x, z) du trace pour ces longueurs de segments.
func _endpoint(lengths: PackedFloat32Array) -> Vector2:
	var x := 0.0
	var z := 0.0
	var th := 0.0
	for k in segments.size():
		var seg: Dictionary = segments[k]
		var L := lengths[k]
		if seg.get("type", "straight") == "arc":
			var sgn := signf(float(seg["angle"]))
			var R := float(seg["radius"])
			var n := maxi(1, ceili(L / 0.25))
			var h := L / n
			for j in n:
				th += sgn * h / R
				x += -sin(th) * h
				z += -cos(th) * h
		else:
			x += -sin(th) * L
			z += -cos(th) * L
	return Vector2(x, z)


## Moyenne glissante circulaire (rayon en echantillons) : transforme un profil en
## marches en raccords progressifs.
static func _smooth_loop(v: PackedFloat32Array, radius: float) -> PackedFloat32Array:
	var n := v.size()
	var r := maxi(1, roundi(radius))
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var acc := 0.0
		for k in range(-r, r + 1):
			acc += v[posmod(i + k, n)]
		out[i] = acc / (2 * r + 1)
	return out


# --- geometrie ------------------------------------------------------------------

func _build_geometry() -> void:
	var geometry := _group("Geometry")
	var walls := _group("Walls")
	var zones := _group("ResetZones")
	var grid := _group("StartGrid")

	# chaussee
	var n := _pos.size()
	var road_tris := PackedVector3Array()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		var j := (i + 1) % n
		var v0 := _s[i]
		var v1 := _s[i] + _length / n
		var l0 := _pos[i] - _right[i] * width / 2.0
		var r0 := _pos[i] + _right[i] * width / 2.0
		var l1 := _pos[j] - _right[j] * width / 2.0
		var r1 := _pos[j] + _right[j] * width / 2.0
		_quad(st, road_tris, l0, r0, r1, l1, Vector2(0, v0), Vector2(1, v0), Vector2(1, v1), Vector2(0, v1), _up[i])
	var road := _static_body(geometry, "Road", st, road_tris, preload("res://tracks/materials/road.tres"), 1.0)
	road.set_meta(&"surface", &"asphalt")

	# glissieres : profil vertical dans le monde (independant du devers),
	# face interieure penchee vers la piste, face exterieure jusqu'au sol
	for side: float in [-1.0, 1.0]:
		var wst := SurfaceTool.new()
		wst.begin(Mesh.PRIMITIVE_TRIANGLES)
		var wtris := PackedVector3Array()
		for i in n:
			var j := (i + 1) % n
			var a := _wall_profile(i, side)
			var b := _wall_profile(j, side)
			var v0 := _s[i]
			var v1 := _s[i] + _length / n
			for k in 3:
				if side > 0.0:
					_quad(wst, wtris, a[k], b[k], b[k + 1], a[k + 1],
						Vector2(k, v0), Vector2(k, v1), Vector2(k + 1, v1), Vector2(k + 1, v0), Vector3.ZERO)
				else:
					_quad(wst, wtris, a[k], a[k + 1], b[k + 1], b[k],
						Vector2(k, v0), Vector2(k + 1, v0), Vector2(k + 1, v1), Vector2(k, v1), Vector3.ZERO)
		var wall := _static_body(walls, "WallLeft" if side < 0.0 else "WallRight", wst, wtris,
			preload("res://tracks/materials/wall.tres"), wall_friction)
		wall.set_meta(&"surface", &"asphalt")

	# sol d'herbe sous toute la piste (hors piste : lent, pas de vide)
	var span := _bounds_span() + 200.0
	var gst := SurfaceTool.new()
	gst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gtris := PackedVector3Array()
	var c := _bounds_center()
	var h := span / 2.0
	_quad(gst, gtris, c + Vector3(-h, GROUND_Y, -h), c + Vector3(-h, GROUND_Y, h),
		c + Vector3(h, GROUND_Y, h), c + Vector3(h, GROUND_Y, -h),
		Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector3.UP)
	var ground := _static_body(geometry, "Ground", gst, gtris, preload("res://tracks/materials/grass.tres"), 1.0)
	ground.set_meta(&"surface", &"grass")

	for jmp in _jumps:
		_build_jump(geometry, jmp.x, jmp.y)

	_build_reset_zones(zones)

	for slot in grid_lateral.size():
		var m := Marker3D.new()
		m.name = "Slot%d" % slot
		m.transform = get_start_transform(slot)
		grid.add_child(m)

	var path := Path3D.new()
	path.name = "RacingLine"
	path.set_meta(&"generated", true)
	var curve := Curve3D.new()
	for i in n + 1:
		curve.add_point(_pos[i % n])
	path.curve = curve
	add_child(path)


## Profil d'un mur en 4 points : bas interieur (sous la chaussee), haut
## interieur (penche vers la piste), haut exterieur, bas exterieur (au sol).
func _wall_profile(i: int, side: float) -> PackedVector3Array:
	var edge := _pos[i] + _right[i] * (side * width / 2.0)
	var out := Vector3(_right[i].x, 0.0, _right[i].z).normalized() * side
	var top_y := edge.y + wall_height
	var inner_bottom := edge + Vector3(0.0, -0.3, 0.0)
	var inner_top := Vector3(edge.x, top_y, edge.z) - out * wall_lean
	var thick_top := wall_thickness + wall_lean * (1.0 + 0.3 / wall_height)
	var outer_top := inner_top + out * thick_top
	var outer_bottom := Vector3(outer_top.x, minf(GROUND_Y - 0.1, edge.y - 0.3), outer_top.z)
	return PackedVector3Array([inner_bottom, inner_top, outer_top, outer_bottom])


## Zones de reset : une boite par troncon de piste et par cote, au-dela du mur,
## orientee le long de la piste (courtes, pour suivre les virages sans jamais
## deborder sur la chaussee). Du sol jusqu'a reset_zone_height au-dessus.
func _build_reset_zones(parent: Node3D) -> void:
	var n := _pos.size()
	var step := _length / n
	var chunk := maxi(1, roundi(reset_zone_length / step))
	var inner := width / 2.0 + wall_thickness + wall_lean + reset_zone_margin
	var k := 0
	var i := 0
	while i < n:
		var mid := (i + floori(chunk / 2.0)) % n
		var t := Vector3(_fwd[mid].x, 0.0, _fwd[mid].z).normalized()
		var r := t.cross(Vector3.UP).normalized()
		var zone_basis := Basis(r, Vector3.UP, -t)
		for side: float in [-1.0, 1.0]:
			var area := Area3D.new()
			area.name = "Zone%03d%s" % [k, "L" if side < 0.0 else "R"]
			area.collision_layer = 1 << (RESET_ZONE_LAYER - 1)
			area.collision_mask = 1 << (VEHICLE_LAYER - 1)
			area.monitorable = false
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(reset_zone_depth, reset_zone_height, chunk * step + 2.0)
			cs.shape = box
			area.add_child(cs)
			var center := _pos[mid] + r * side * (inner + reset_zone_depth / 2.0)
			center.y = GROUND_Y - 2.0 + reset_zone_height / 2.0
			area.transform = Transform3D(zone_basis, center)
			area.body_entered.connect(_on_reset_zone_body_entered)
			area.body_exited.connect(_on_reset_zone_body_exited)
			parent.add_child(area)
		k += 1
		i += chunk


func _on_reset_zone_body_entered(body: Node3D) -> void:
	truck_entered_reset_zone.emit(body)


func _on_reset_zone_body_exited(body: Node3D) -> void:
	truck_exited_reset_zone.emit(body)


## Tremplin : prisme convexe, bord d'attaque au ras de la chaussee.
func _build_jump(parent: Node3D, s: float, offset: float) -> void:
	var i := roundi(s / (_length / _pos.size())) % _pos.size()
	var f := _fwd[i]
	var r := _right[i]
	var u := _up[i]
	var base := _pos[i] + r * offset
	var hw := jump_width / 2.0
	var top := jump_length * tan(deg_to_rad(jump_angle_deg))
	var p := PackedVector3Array([
		base - r * hw - u * 0.02, base + r * hw - u * 0.02,                              # attaque
		base - r * hw + f * jump_length + u * top, base + r * hw + f * jump_length + u * top,  # sommet
		base - r * hw + f * jump_length - u * 0.3, base + r * hw + f * jump_length - u * 0.3,  # pied arriere
	])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := PackedVector3Array()
	var z2 := Vector2.ZERO
	_quad(st, tris, p[0], p[1], p[3], p[2], z2, z2, z2, z2, Vector3.ZERO)   # rampe
	_quad(st, tris, p[2], p[3], p[5], p[4], z2, z2, z2, z2, Vector3.ZERO)   # dos
	_tri(st, tris, p[0], p[2], p[4])                                        # flancs
	_tri(st, tris, p[1], p[5], p[3])
	var body := StaticBody3D.new()
	body.name = "Jump"
	body.collision_layer = 1 << (ROAD_LAYER - 1)
	body.collision_mask = 0
	body.set_meta(&"surface", &"asphalt")
	var cs := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = p
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	st.generate_normals()
	mi.mesh = st.commit()
	mi.material_override = preload("res://tracks/materials/jump.tres")
	body.add_child(mi)
	parent.add_child(body)


# --- utilitaires ------------------------------------------------------------------

func _group(group_name: String) -> Node3D:
	var g := Node3D.new()
	g.name = group_name
	g.set_meta(&"generated", true)
	add_child(g)
	return g


func _static_body(parent: Node3D, body_name: String, st: SurfaceTool, tris: PackedVector3Array,
		mat: Material, friction: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = 1 << (ROAD_LAYER - 1)
	body.collision_mask = 0
	var pm := PhysicsMaterial.new()
	pm.friction = friction
	pm.bounce = 0.0
	body.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(tris)
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	st.generate_normals()
	st.generate_tangents()
	mi.mesh = st.commit()
	mi.material_override = mat
	body.add_child(mi)
	parent.add_child(body)
	return body


## Quadrilatere a, b, c, d (sens anti-horaire vu de la face visible).
func _quad(st: SurfaceTool, tris: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, _n: Vector3) -> void:
	var vs: Array[Vector3] = [a, c, b, a, d, c]
	var us: Array[Vector2] = [ua, uc, ub, ua, ud, uc]
	for k in 6:
		st.set_uv(us[k])
		st.add_vertex(vs[k])
		tris.append(vs[k])


func _tri(st: SurfaceTool, tris: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	var vs: Array[Vector3] = [a, c, b]
	for v in vs:
		st.set_uv(Vector2.ZERO)
		st.add_vertex(v)
		tris.append(v)


func _bounds_center() -> Vector3:
	var lo := _pos[0]
	var hi := _pos[0]
	for p in _pos:
		lo = lo.min(p)
		hi = hi.max(p)
	return Vector3((lo.x + hi.x) / 2.0, 0.0, (lo.z + hi.z) / 2.0)


func _bounds_span() -> float:
	var lo := _pos[0]
	var hi := _pos[0]
	for p in _pos:
		lo = lo.min(p)
		hi = hi.max(p)
	return maxf(hi.x - lo.x, hi.z - lo.z)
