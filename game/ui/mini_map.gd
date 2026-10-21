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

var ui_scale: float = 1.0
## Camions suivis : { "truck": Truck, "color": Color, "self": bool }.
var markers: Array[Dictionary] = []
## Trace en pixels : une polyligne par troncon au sol, une par tablier de
## pont, une par raccourci ; ligne d'arrivee (deux points).
var ground: Array[PackedVector2Array] = []
var decks: Array[PackedVector2Array] = []
var branches: Array[PackedVector2Array] = []
var finish: PackedVector2Array = []
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
		branches.append(PackedVector2Array([to_map(track.branch_frame(b, 0.0, 0.0, 0.0).origin),
			to_map(track.branch_frame(b, 1.0, 0.0, 0.0).origin)]))
	var start := track.frame_at(0, 0.0, 0.0)
	var half := start.basis.x * (track.width / 2.0)
	finish = PackedVector2Array([to_map(start.origin - half), to_map(start.origin + half)])
	queue_redraw()


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
