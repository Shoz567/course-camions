class_name MiniMap
extends Control

## Mini-carte facon Mario Kart (2026-10-21 : « une mini map à la Mario Kart
## sur laquelle on peut voir les positions des joueurs ») : le trace du
## circuit vu de dessus, nord en haut (-Z du monde), dans un cadre aux
## proportions du circuit (SIZE px pour son grand cote), sur un fond sombre
## translucide (le decor de la ville est tres lumineux) ; une pastille par camion a la couleur de son joueur ; le sien, une
## fleche plus grande tournee dans son cap, dessinee par-dessus les autres.
## Raccourcis en trait plus fin, ligne d'arrivee en damier, ponts dessines
## par-dessus la route qu'ils enjambent (croisement de Sakura). Une epave :
## pastille grise. Rendu seulement : la course lui donne la piste et les
## camions, il lit leurs positions (CLAUDE.md §7).
##
## Arene (piste sans marquage de course, 2026-10-21 : « pas un circuit, une
## carte comme dans les FPS : voir les objets, les tremplins, la position des
## joueurs, et pas juste le tour, qui n'est même pas le bord de la map ») : le
## sol de l'arene jusqu'a ses murs, l'ilot central, les tremplins (emprise,
## arete du sommet en blanc), plaques de boost, flaques, et, tant qu'ils sont
## la, les barils et les bonus (vert : reparation, jaune : recharge).

## Grand cote du cadre (px, avant ui_scale) et marge interieure.
const SIZE := 300.0
const MARGIN := 14.0
## Un echantillon de piste sur STEP dans le trace (2 m chacun).
const STEP := 3
## Epaisseurs (px, avant ui_scale) : route, contour, raccourci.
const ROAD_W := 7.0
const EDGE_W := 3.0
const BRANCH_W := 4.0
## Rayon des pastilles (px, avant ui_scale) : un autre camion, le sien.
const DOT_R := 6.0
const SELF_R := 9.5
const ROAD := Color(0.9, 0.92, 1.0, 0.92)
const EDGE := Color(0.0, 0.0, 0.0, 0.6)
const WRECK := Color(0.45, 0.45, 0.5)
const BACKDROP := Color(0.02, 0.025, 0.06, 0.45)
## Arene : grand cote du cadre (px, avant ui_scale) et couleurs.
const ARENA_SIZE := 330.0
const FLOOR := Color(0.3, 0.33, 0.42, 0.88)
const ISLAND := Color(0.04, 0.05, 0.09, 0.92)
const WALL := Color(1.0, 1.0, 1.0, 0.8)
const RAMP := Color(0.45, 0.8, 1.0, 0.95)
const BOOST := Color(1.0, 0.58, 0.1, 0.95)
const PUDDLE := Color(0.2, 0.55, 1.0, 0.75)
const BARREL := Color(1.0, 0.22, 0.12)
const REPAIR := Color(0.3, 1.0, 0.45)
const POWER := Color(1.0, 0.85, 0.2)

var ui_scale: float = 1.0
## Camions suivis : { "truck": Truck, "color": Color, "self": bool }.
var markers: Array[Dictionary] = []
## Trace en pixels : une polyligne par troncon au sol, une par tablier de
## pont, une par raccourci ; ligne d'arrivee (deux points).
var ground: Array[PackedVector2Array] = []
var decks: Array[PackedVector2Array] = []
var branches: Array[PackedVector2Array] = []
var finish: PackedVector2Array = []
## Arene : sol (jusqu'aux murs) et ilot, en pixels ; tremplins (emprise au
## sol, arete du sommet) ; plaques de boost ; flaques (x, y, rayon en px).
var arena: bool = false
var floor_poly := PackedVector2Array()
var island_poly := PackedVector2Array()
var ramps: Array[PackedVector2Array] = []
var ramp_tops: Array[PackedVector2Array] = []
var pads: Array[PackedVector2Array] = []
var puddles: Array[Vector3] = []
var _track: TrackBlockout
## Monde (x, z) -> carte : centre du trace et echelle (px par m).
var _center := Vector2.ZERO
var _scale := 1.0
## Taille du cadre (px).
var box := Vector2.ONE * SIZE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2.ONE * SIZE * ui_scale
	size = custom_minimum_size


## Prend le trace de `track` et les camions a suivre.
func setup(track: TrackBlockout, list: Array[Dictionary]) -> void:
	markers = list
	_track = track
	arena = not track.race_markings
	if arena:
		_setup_arena(track)
		queue_redraw()
		return
	var n := track.sample_count()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in range(0, n, STEP):
		var p := track.sample_position(i)
		lo = lo.min(Vector2(p.x, p.z))
		hi = hi.max(Vector2(p.x, p.z))
	var side := SIZE * ui_scale
	var pad := MARGIN * ui_scale
	_center = (lo + hi) / 2.0
	var span := (hi - lo).max(Vector2.ONE)
	_scale = (side - 2.0 * pad) / maxf(span.x, span.y)
	box = span * _scale + Vector2.ONE * 2.0 * pad
	custom_minimum_size = box
	size = box
	# au sol, puis les tabliers de pont (dessines ensuite, par-dessus)
	ground.clear()
	decks.clear()
	var cur := PackedVector2Array()
	var cur_deck := false
	for k in range(0, n + STEP, STEP):
		var i := k % n
		var deck := track.is_bridge_deck(i)
		var q := to_map(track.sample_position(i))
		if deck != cur_deck and cur.size() > 0:
			cur.append(q)
			(decks if cur_deck else ground).append(cur)
			cur = PackedVector2Array([cur[-2] if cur.size() > 1 else q])
			cur_deck = deck
		cur.append(q)
	if cur.size() > 1:
		(decks if cur_deck else ground).append(cur)
	branches.clear()
	for b in track.branch_count():
		var line := PackedVector2Array()
		var parts := maxi(2, ceili(track.branch_length(b) / 12.0))
		for k in parts + 1:
			line.append(to_map(track.branch_frame(b, float(k) / parts, 0.0, 0.0).origin))
		branches.append(line)
	var start := track.frame_at(0, 0.0, 0.0)
	var half := start.basis.x * (track.width / 2.0)
	# arene (2026-10-21) : pas de ligne d'arrivee
	finish = PackedVector2Array()
	if track.race_markings:
		finish = PackedVector2Array([to_map(start.origin - half), to_map(start.origin + half)])
	queue_redraw()


## Arene : le sol jusqu'aux murs (bord exterieur de la chaussee), l'ilot
## (bord interieur), les tremplins, plaques et flaques.
func _setup_arena(track: TrackBlockout) -> void:
	var n := track.sample_count()
	var edges: Array[PackedVector2Array] = [PackedVector2Array(), PackedVector2Array()]
	for i in range(0, n, STEP):
		var p := track.sample_position(i)
		var r := track.sample_right(i)
		var flat := Vector2(r.x, r.z).normalized() * track.width / 2.0
		edges[0].append(Vector2(p.x, p.z) - flat)
		edges[1].append(Vector2(p.x, p.z) + flat)
	var outer := 0 if absf(_area(edges[0])) > absf(_area(edges[1])) else 1
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for q in edges[outer]:
		lo = lo.min(q)
		hi = hi.max(q)
	var pad := MARGIN * ui_scale
	_center = (lo + hi) / 2.0
	var span := (hi - lo).max(Vector2.ONE)
	_scale = (ARENA_SIZE * ui_scale - 2.0 * pad) / maxf(span.x, span.y)
	box = span * _scale + Vector2.ONE * 2.0 * pad
	custom_minimum_size = box
	size = box
	floor_poly = _mapped(edges[outer])
	island_poly = _mapped(edges[1 - outer])
	ramps.clear()
	ramp_tops.clear()
	for body in track.find_children("JumpPad*", "StaticBody3D", true, false):
		var pts := ((body.get_child(0) as CollisionShape3D).shape as ConvexPolygonShape3D).points
		var at := (body as Node3D).global_transform
		ramps.append(PackedVector2Array([to_map(at * pts[0]), to_map(at * pts[1]), to_map(at * pts[5]),
			to_map(at * pts[4])]))
		ramp_tops.append(PackedVector2Array([to_map(at * pts[2]), to_map(at * pts[3])]))
	pads.clear()
	for k in track.boost_pad_count():
		var xf := track.boost_pad_transform(k)
		var ax := xf.basis.x.normalized() * track.boost_pad_size.x / 2.0
		var az := xf.basis.z.normalized() * track.boost_pad_size.y / 2.0
		pads.append(PackedVector2Array([to_map(xf.origin - ax - az), to_map(xf.origin + ax - az),
			to_map(xf.origin + ax + az), to_map(xf.origin - ax + az)]))
	puddles.clear()
	for k in track.puddle_count():
		var c := to_map(track.puddle_transform(k).origin)
		puddles.append(Vector3(c.x, c.y, track.puddle_radius(k) * _scale))


## Polygone (x, z du monde) -> pixels.
func _mapped(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in poly:
		out.append((q - _center) * _scale + box / 2.0)
	return out


## Aire signee d'un polygone.
static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		a += poly[i].cross(poly[(i + 1) % poly.size()])
	return a / 2.0


## Point du monde -> pixel de la carte.
func to_map(p: Vector3) -> Vector2:
	return (Vector2(p.x, p.z) - _center) * _scale + box / 2.0


## Position du camion `t` sur la carte (Vector2.INF s'il n'est pas suivi).
func marker_position(t: Truck) -> Vector2:
	for m in markers:
		if m["truck"] == t and is_instance_valid(t):
			return to_map(t.get_global_transform_interpolated().origin)
	return Vector2.INF


func _process(_delta: float) -> void:
	if visible and not markers.is_empty():
		queue_redraw()


func _draw() -> void:
	var k := ui_scale
	draw_style_box(UiKit.box(BACKDROP, Color(1, 1, 1, 0.12), 1, 0.0, roundi(10 * k)), Rect2(Vector2.ZERO, box))
	if arena:
		_draw_arena(k)
	else:
		_draw_track(k)
	# les autres, puis le sien par-dessus
	for pass_self in [false, true]:
		for m in markers:
			if bool(m["self"]) != pass_self:
				continue
			var t := m["truck"] as Truck
			if t == null or not is_instance_valid(t) or not t.is_inside_tree():
				continue
			var xf := t.get_global_transform_interpolated()
			var at := to_map(xf.origin)
			var col: Color = WRECK if t.is_wrecked() else m["color"]
			if pass_self:
				_draw_arrow(at, Vector2(-xf.basis.z.x, -xf.basis.z.z), col, k)
			else:
				draw_circle(at, (DOT_R + 1.5) * k, EDGE)
				draw_circle(at, DOT_R * k, col)


## Arene : sol, ilot et murs, flaques, plaques, tremplins, bonus et barils
## encore la.
func _draw_arena(k: float) -> void:
	if floor_poly.size() >= 3:
		draw_colored_polygon(floor_poly, FLOOR)
		draw_polyline(_closed(floor_poly), WALL, 2.0 * k, true)
	if island_poly.size() >= 3:
		draw_colored_polygon(island_poly, ISLAND)
		draw_polyline(_closed(island_poly), WALL, 2.0 * k, true)
	for pd in puddles:
		draw_circle(Vector2(pd.x, pd.y), maxf(pd.z, 3.0 * k), PUDDLE)
	for p in pads:
		draw_colored_polygon(p, BOOST)
	for i in ramps.size():
		draw_colored_polygon(ramps[i], RAMP)
		draw_polyline(_closed(ramps[i]), EDGE, 1.0 * k, true)
		draw_line(ramp_tops[i][0], ramp_tops[i][1], Color.WHITE, 2.0 * k, true)
	if _track == null:
		return
	var s := 3.6 * k
	for j in _track.pickup_count():
		var pk := _track.pickup_node(j)
		if pk == null or not is_instance_valid(pk) or not pk.available():
			continue
		var at := to_map(pk.global_position)
		draw_rect(Rect2(at - Vector2.ONE * (s + k), Vector2.ONE * 2.0 * (s + k)), EDGE)
		draw_rect(Rect2(at - Vector2.ONE * s, Vector2.ONE * 2.0 * s), REPAIR if pk.kind == TrackPickup.Kind.REPAIR else POWER)
	for j in _track.barrel_count():
		var b := _track.barrel_node(j)
		if b == null or not is_instance_valid(b) or not b.visible or b.exploded_state:
			continue
		var at := to_map(b.global_position)
		draw_circle(at, 4.0 * k, EDGE)
		draw_circle(at, 3.0 * k, BARREL)


static func _closed(poly: PackedVector2Array) -> PackedVector2Array:
	var out := poly.duplicate()
	if out.size() > 0:
		out.append(out[0])
	return out


## Circuit : trace, raccourcis, ponts, ligne d'arrivee.
func _draw_track(k: float) -> void:
	for line in ground:
		draw_polyline(line, EDGE, (ROAD_W + 2.0 * EDGE_W) * k, true)
	for line in branches:
		draw_polyline(line, EDGE, (BRANCH_W + 2.0 * EDGE_W) * k, true)
	for line in ground:
		draw_polyline(line, ROAD, ROAD_W * k, true)
	for line in branches:
		draw_polyline(line, Color(ROAD, 0.75), BRANCH_W * k, true)
	# ponts : par-dessus la route qu'ils enjambent
	for line in decks:
		draw_polyline(line, EDGE, (ROAD_W + 2.0 * EDGE_W) * k, true)
		draw_polyline(line, ROAD, ROAD_W * k, true)
	_draw_finish(k)


## Ligne d'arrivee : damier noir et blanc en travers de la route.
func _draw_finish(k: float) -> void:
	if finish.size() != 2:
		return
	var cells := 6
	var w := maxf(3.0 * k, 2.0)
	var along := (finish[1] - finish[0])
	var normal := along.orthogonal().normalized() * w / 2.0
	for c in cells:
		var a := finish[0] + along * float(c) / cells
		var b := finish[0] + along * float(c + 1) / cells
		for row in 2:
			var off := normal * (1.0 if row == 0 else -1.0)
			var col := Color.WHITE if (c + row) % 2 == 0 else Color.BLACK
			draw_colored_polygon(PackedVector2Array([a, b, b + off, a + off]), col)


## Son camion : fleche dans son cap, contour blanc.
func _draw_arrow(at: Vector2, heading: Vector2, col: Color, k: float) -> void:
	var f := heading.normalized() if heading.length() > 0.01 else Vector2.UP
	var r := f.orthogonal()
	var s := SELF_R * k
	var pts := PackedVector2Array([at + f * s * 1.25, at - f * s * 0.8 + r * s * 0.85, at - f * s * 0.35,
		at - f * s * 0.8 - r * s * 0.85])
	var outline := PackedVector2Array()
	for p in pts:
		outline.append(at + (p - at) * 1.3)
	draw_colored_polygon(outline, Color.WHITE)
	draw_colored_polygon(pts, col)
