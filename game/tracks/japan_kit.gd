class_name JapanKit
extends RefCounted

## Kit de construction du decor de Sakura (SakuraBackdrop, 2026-10-19) :
## boites, cylindres et toits japonais (pans concaves, coins releves) ajoutes
## a un LOT, une SurfaceTool par materiau, fusionnes en un seul ArrayMesh
## (une surface par materiau : un appel de rendu par materiau et par lot).
## Batiments composes : machiya (maison de ville), pagode, donjon de
## chateau sur murs de pierre, pavillon de temple, lanterne de pierre.
##
## UV des faces laterales en metres (u le long de la face, v en hauteur
## depuis le bas de la boite) : les shaders y dessinent poteaux, lattis et
## tuiles a l'echelle. COLOR.r choisit le motif de mur (sakura_house.gdshader),
## COLOR.g varie la teinte.

## CLOTH (tissu, couleur de sommet) : seulement en detail (noren).
enum Mat { PLASTER, WOOD, LACQUER, ROOF, STONE, GOLD, PAPER, CLOTH }

## Motifs de mur (COLOR.r).
const WALL_MACHIYA_GROUND := 0.0
const WALL_MACHIYA_UPPER := 0.25
const WALL_CASTLE := 0.5
const WALL_TEMPLE := 0.75
const WALL_PLAIN := 1.0

var _st: Dictionary = {}
## Qualite extreme (2026-10-22, « les buildings trop simples, detaille-les ») :
## les batiments composes ajoutent leurs details (lattis, chevrons, noren,
## lanterne, fenetres a barreaux, faitage ; clochettes de la pagode).
var detail: bool = false


func _tool(m: int) -> SurfaceTool:
	if not _st.has(m):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[m] = st
	return _st[m]


func is_empty() -> bool:
	return _st.is_empty()


## Fusionne le lot : une surface par materiau (`materials` : Mat -> Material).
func commit(materials: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for m: int in _st:
		var st: SurfaceTool = _st[m]
		st.generate_normals()
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, materials[m])
	return mesh


func _v(st: SurfaceTool, p: Vector3, uv: Vector2, c: Color) -> void:
	st.set_color(c)
	st.set_uv(uv)
	st.add_vertex(p)


## Quadrilatere a, b, c, d (anti-horaire vu de la face visible).
func quad(m: int, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2,
		ud: Vector2, col: Color) -> void:
	var st := _tool(m)
	_v(st, a, ua, col)
	_v(st, c, uc, col)
	_v(st, b, ub, col)
	_v(st, a, ua, col)
	_v(st, d, ud, col)
	_v(st, c, uc, col)


## Boite `size` centree en x/z, posee sur y = 0 du repere `xf`. Le dessus
## peut etre plus petit (`top_scale` : talus de pierre, socle).
func box(m: int, xf: Transform3D, size: Vector3, col: Color, top_scale: float = 1.0, bottom: bool = false) -> void:
	var hx := size.x / 2.0
	var hz := size.z / 2.0
	var tx := hx * top_scale
	var tz := hz * top_scale
	var h := size.y
	var b := [xf * Vector3(-hx, 0, -hz), xf * Vector3(hx, 0, -hz), xf * Vector3(hx, 0, hz), xf * Vector3(-hx, 0, hz)]
	var t := [xf * Vector3(-tx, h, -tz), xf * Vector3(tx, h, -tz), xf * Vector3(tx, h, tz), xf * Vector3(-tx, h, tz)]
	var lens := [size.x, size.z, size.x, size.z]
	# faces laterales : -Z, +X, +Z, -X (vues de l'exterieur)
	var order := [[1, 0], [2, 1], [3, 2], [0, 3]]
	for k in 4:
		var i0: int = order[k][0]
		var i1: int = order[k][1]
		var L: float = lens[k]
		quad(m, b[i0], b[i1], t[i1], t[i0], Vector2(0, 0), Vector2(L, 0), Vector2(L, h), Vector2(0, h), col)
	quad(m, t[3], t[2], t[1], t[0], Vector2(0, size.z), Vector2(size.x, size.z), Vector2(size.x, 0), Vector2(0, 0), col)
	if bottom:
		quad(m, b[0], b[1], b[2], b[3], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, col)


## Cylindre (ou tronc de cone) de hauteur `h` pose sur y = 0 de `xf`.
func cylinder(m: int, xf: Transform3D, r0: float, r1: float, h: float, segs: int, col: Color, cap: bool = true) -> void:
	for k in segs:
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		var p0 := Vector3(cos(a0), 0, sin(a0))
		var p1 := Vector3(cos(a1), 0, sin(a1))
		var u0 := a0 * r0
		var u1 := a1 * r0
		quad(m, xf * (p1 * r0), xf * (p0 * r0), xf * (p0 * r1 + Vector3(0, h, 0)), xf * (p1 * r1 + Vector3(0, h, 0)),
			Vector2(u1, 0), Vector2(u0, 0), Vector2(u0, h), Vector2(u1, h), col)
		if cap and r1 > 0.0:
			var st := _tool(m)
			_v(st, xf * Vector3(0, h, 0), Vector2.ZERO, col)
			_v(st, xf * (p0 * r1 + Vector3(0, h, 0)), Vector2.ZERO, col)
			_v(st, xf * (p1 * r1 + Vector3(0, h, 0)), Vector2.ZERO, col)


## Toit japonais en croupe sur une emprise w x d (x, z), pose a y = 0 de
## `xf` : avancee `over` tout autour, faitage le long de x (pyramide si
## w <= d), pans concaves (brisis plat en bas, terrasson raide en haut), coins
## de l'egout releves de `flare`, epaisseur de la rive. UV : u le long de
## l'egout, v le long de la pente (m) - sakura_roof.gdshader y pose les tuiles.
func hip_roof(m: int, xf: Transform3D, w: float, d: float, h: float, over: float, flare: float, col: Color) -> void:
	var ex := w / 2.0 + over
	var ez := d / 2.0 + over
	var ridge := maxf(w - d, 0.0) / 2.0
	# anneaux : egout (coins releves), mi-pente, faitage
	var eave := [Vector3(-ex, flare, -ez), Vector3(ex, flare, -ez), Vector3(ex, flare, ez), Vector3(-ex, flare, ez)]
	var mid_k := 0.55
	var mx := lerpf(ex, ridge, mid_k)
	var mz := lerpf(ez, 0.0, mid_k)
	var mid_y := h * 0.32
	var mid := [Vector3(-mx, mid_y, -mz), Vector3(mx, mid_y, -mz), Vector3(mx, mid_y, mz), Vector3(-mx, mid_y, mz)]
	var top := [Vector3(-ridge, h, 0), Vector3(ridge, h, 0), Vector3(ridge, h, 0), Vector3(-ridge, h, 0)]
	# milieux d'egout un peu plus bas que les coins (courbe de la rive)
	var order := [[1, 0], [2, 1], [3, 2], [0, 3]]
	for k in 4:
		var i0: int = order[k][0]
		var i1: int = order[k][1]
		var a0: Vector3 = eave[i0]
		var a1: Vector3 = eave[i1]
		var b0: Vector3 = mid[i0]
		var b1: Vector3 = mid[i1]
		var c0: Vector3 = top[i0]
		var c1: Vector3 = top[i1]
		var L := a0.distance_to(a1)
		var s1 := a0.distance_to(b0)
		var s2 := s1 + b0.distance_to(c0)
		# egout en deux moities, le milieu abaisse de flare
		var am := (a0 + a1) / 2.0 - Vector3(0, flare, 0)
		var bm := (b0 + b1) / 2.0
		quad(m, xf * a0, xf * am, xf * bm, xf * b0, Vector2(0, 0), Vector2(L / 2.0, 0), Vector2(L / 2.0, s1), Vector2(0, s1), col)
		quad(m, xf * am, xf * a1, xf * b1, xf * bm, Vector2(L / 2.0, 0), Vector2(L, 0), Vector2(L, s1), Vector2(L / 2.0, s1), col)
		quad(m, xf * b0, xf * b1, xf * c1, xf * c0, Vector2(0, s1), Vector2(L, s1), Vector2(L, s2), Vector2(0, s2), col)
		# rive : bandeau d'epaisseur sous l'egout
		var th := Vector3(0, -0.45, 0)
		quad(m, xf * (a0 + th), xf * (am + th), xf * am, xf * a0, Vector2(0, -0.45), Vector2(L / 2.0, -0.45),
			Vector2(L / 2.0, 0), Vector2(0, 0), col)
		quad(m, xf * (am + th), xf * (a1 + th), xf * a1, xf * am, Vector2(L / 2.0, -0.45), Vector2(L, -0.45),
			Vector2(L, 0), Vector2(L / 2.0, 0), col)
		# sous-face sombre (on la voit d'en bas)
		quad(m, xf * (a1 + th), xf * (am + th), xf * Vector3(bm.x * 0.6, -0.45, bm.z * 0.6),
			xf * Vector3(b1.x * 0.6, -0.45, b1.z * 0.6), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO,
			Color(col.r, col.g, 0.0))
		quad(m, xf * (am + th), xf * (a0 + th), xf * Vector3(b0.x * 0.6, -0.45, b0.z * 0.6),
			xf * Vector3(bm.x * 0.6, -0.45, bm.z * 0.6), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO,
			Color(col.r, col.g, 0.0))


# --- batiments composes ----------------------------------------------------------

## Machiya : rez-de-chaussee de bois a lattis, auvent de tuiles, etage
## enduit a poteaux, toit a faitage le long de la rue. Facade vers -Z de `xf`.
func machiya(xf: Transform3D, w: float, d: float, tint: float) -> void:
	var c := Color(WALL_MACHIYA_GROUND, tint, 1.0)
	box(Mat.PLASTER, xf, Vector3(w, 3.4, d), c)
	# auvent (hisashi) le long de la facade
	var front := xf * Transform3D(Basis.IDENTITY, Vector3(0, 3.3, -d / 2.0 - 0.2))
	hip_roof(Mat.ROOF, front, w - 0.6, 0.6, 0.55, 0.7, 0.05, Color(1, tint, 1))
	var up := xf * Transform3D(Basis.IDENTITY, Vector3(0, 3.4, 0.3))
	box(Mat.PLASTER, up, Vector3(w - 0.3, 2.8, d - 0.8), Color(WALL_MACHIYA_UPPER, tint, 1.0))
	hip_roof(Mat.ROOF, xf * Transform3D(Basis.IDENTITY, Vector3(0, 6.2, 0.3)), w, d - 0.8, 2.6, 1.1, 0.25, Color(1, tint, 1))
	if detail:
		_machiya_detail(xf, w, d, tint)


## Details d'une machiya (qualite extreme) : lattis de bois (koshi) devant le
## rez-de-chaussee, porte encadree sous un noren indigo a trois pans, lanterne
## de papier sur potence, chevrons sous l'auvent, fenetres a barreaux a
## l'etage, faitage et tuiles d'about (onigawara).
func _machiya_detail(xf: Transform3D, w: float, d: float, tint: float) -> void:
	var front := -d / 2.0 - 0.05
	var door := -w * 0.22
	var x := -w / 2.0 + 0.6
	while x < w / 2.0 - 0.6:
		if absf(x - door) > 0.75:
			box(Mat.WOOD, xf * Transform3D(Basis.IDENTITY, Vector3(x, 0.35, front)), Vector3(0.045, 2.25, 0.045), Color.WHITE)
		x += 0.13
	for y: float in [0.3, 2.6]:
		box(Mat.WOOD, xf * Transform3D(Basis.IDENTITY, Vector3(0, y, front)), Vector3(w - 1.1, 0.08, 0.09), Color.WHITE)
	# porte : montants, linteau, noren a trois pans
	for side: float in [-1.0, 1.0]:
		box(Mat.WOOD, xf * Transform3D(Basis.IDENTITY, Vector3(door + side * 0.72, 0.0, front)), Vector3(0.12, 2.75, 0.12), Color.WHITE)
	box(Mat.WOOD, xf * Transform3D(Basis.IDENTITY, Vector3(door, 2.75, front)), Vector3(1.6, 0.14, 0.14), Color.WHITE)
	var indigo := Color(0.12, 0.17, 0.36).lerp(Color(0.32, 0.12, 0.1), 1.0 if tint > 0.7 else 0.0)
	for k in 3:
		box(Mat.CLOTH, xf * Transform3D(Basis.IDENTITY, Vector3(door + (k - 1) * 0.46, 1.95, front - 0.08)),
			Vector3(0.43, 0.78, 0.02), indigo.lightened(0.06 * k))
	# lanterne de papier sur sa potence
	box(Mat.WOOD, xf * Transform3D(Basis.IDENTITY, Vector3(door + 1.05, 2.55, front - 0.25)), Vector3(0.06, 0.06, 0.5), Color.WHITE)
	cylinder(Mat.PAPER, xf * Transform3D(Basis.IDENTITY, Vector3(door + 1.05, 1.95, front - 0.45)), 0.2, 0.2, 0.55, 8, Color.WHITE)
	# chevrons sous l'auvent
	x = -(w - 0.6) / 2.0
	while x <= (w - 0.6) / 2.0:
		box(Mat.WOOD, xf * Transform3D(Basis.IDENTITY, Vector3(x, 3.05, -d / 2.0 - 0.5)), Vector3(0.07, 0.07, 0.9), Color.WHITE)
		x += 0.45
	# fenetres a barreaux de l'etage, en relief sur celles que peint
	# sakura_house.gdshader (une travee de 1,8 m sur deux)
	var up_front := -d / 2.0 + 0.7 - 0.04
	var hx := (w - 0.3) / 2.0
	var bay := 1
	while 1.8 * (bay + 1) <= w - 0.3:
		var cx := hx - 1.8 * (bay + 0.5)
		for y: float in [4.36, 5.28]:
			box(Mat.WOOD, xf * Transform3D(Basis.IDENTITY, Vector3(cx, y, up_front)), Vector3(1.15, 0.08, 0.09), Color.WHITE)
		for b in 8:
			box(Mat.WOOD, xf * Transform3D(Basis.IDENTITY, Vector3(cx - 0.49 + b * 0.14, 4.4, up_front)), Vector3(0.045, 0.9, 0.05),
				Color.WHITE)
		bay += 2
	# faitage et tuiles d'about
	var ridge := maxf(w - (d - 0.8), 0.0) / 2.0
	box(Mat.ROOF, xf * Transform3D(Basis.IDENTITY, Vector3(0, 8.7, 0.3)), Vector3(ridge * 2.0 + 0.5, 0.3, 0.34), Color(1, tint, 1))
	for side: float in [-1.0, 1.0]:
		box(Mat.ROOF, xf * Transform3D(Basis.IDENTITY, Vector3(side * (ridge + 0.3), 8.65, 0.3)), Vector3(0.36, 0.6, 0.4),
			Color(1, tint, 1))


## Pagode a `tiers` etages, cote de base `base` : corps vermillon a chaque
## niveau, grands toits debordants, fleche doree (sorin) au sommet.
func pagoda(xf: Transform3D, tiers: int, base: float) -> float:
	var y := 0.0
	box(Mat.STONE, xf, Vector3(base + 6.0, 1.6, base + 6.0), Color(1, 0.5, 1), 0.92)
	y = 1.6
	for k in tiers:
		var s := base * (1.0 - 0.11 * k)
		var hk := 4.2 if k == 0 else 3.4
		box(Mat.PLASTER, xf * Transform3D(Basis.IDENTITY, Vector3(0, y, 0)), Vector3(s, hk, s), Color(WALL_TEMPLE, 0.5, 1))
		y += hk
		hip_roof(Mat.ROOF, xf * Transform3D(Basis.IDENTITY, Vector3(0, y - 0.2, 0)), s, s, 2.0, s * 0.32 + 1.6, 0.9,
			Color(1, 0.5, 1))
		if detail:
			# clochettes de bronze aux quatre coins du toit
			var e := s / 2.0 + s * 0.32 + 1.6 - 0.3
			for cx: float in [-e, e]:
				for cz: float in [-e, e]:
					var at := xf * Transform3D(Basis.IDENTITY, Vector3(cx, y - 0.2 + 0.9 - 1.25, cz))
					cylinder(Mat.GOLD, at, 0.22, 0.12, 0.5, 8, Color.WHITE)
					box(Mat.WOOD, at * Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)), Vector3(0.04, 0.6, 0.04), Color.WHITE)
		y += 1.4
	var top := xf * Transform3D(Basis.IDENTITY, Vector3(0, y, 0))
	cylinder(Mat.GOLD, top, 0.4, 0.25, 10.0, 8, Color.WHITE)
	for r in 6:
		cylinder(Mat.GOLD, top * Transform3D(Basis.IDENTITY, Vector3(0, 1.5 + r * 1.2, 0)), 1.1 - r * 0.1, 1.1 - r * 0.1,
			0.25, 10, Color.WHITE)
	return y + 10.0


## Donjon de chateau : base de pierre en talus, trois niveaux enduits de
## blanc a fenetres, toits a faitage, ornements dores.
func castle(xf: Transform3D) -> void:
	box(Mat.STONE, xf, Vector3(40.0, 13.0, 32.0), Color(1, 0.5, 1), 0.82)
	var y := 13.0
	var floors := [[30.0, 22.0, 7.0], [24.0, 17.0, 6.0], [17.0, 12.0, 5.5], [11.0, 8.0, 5.0]]
	for k in floors.size():
		var f: Array = floors[k]
		box(Mat.PLASTER, xf * Transform3D(Basis.IDENTITY, Vector3(0, y, 0)), Vector3(f[0], f[2], f[1]),
			Color(WALL_CASTLE, 0.5, 1))
		y += f[2]
		var last: bool = k == floors.size() - 1
		hip_roof(Mat.ROOF, xf * Transform3D(Basis.IDENTITY, Vector3(0, y - 0.3, 0)), f[0], f[1], 4.2 if last else 2.6,
			3.2, 0.8, Color(1, 0.35, 1))
		y += 1.6 if not last else 0.0
	# shachihoko dores aux bouts du faitage
	for sx: float in [-1.0, 1.0]:
		box(Mat.GOLD, xf * Transform3D(Basis.IDENTITY, Vector3(sx * 1.6, y + 3.9, 0)), Vector3(0.9, 1.8, 0.6), Color.WHITE)


## Pavillon de temple : socle de pierre, poteaux vermillon et panneaux blancs,
## grand toit, petit toit superieur.
func temple(xf: Transform3D, w: float, d: float) -> void:
	box(Mat.STONE, xf, Vector3(w + 6.0, 1.8, d + 6.0), Color(1, 0.5, 1), 0.96)
	box(Mat.PLASTER, xf * Transform3D(Basis.IDENTITY, Vector3(0, 1.8, 0)), Vector3(w, 8.0, d), Color(WALL_TEMPLE, 0.5, 1))
	hip_roof(Mat.ROOF, xf * Transform3D(Basis.IDENTITY, Vector3(0, 9.6, 0)), w, d, 7.5, 4.5, 1.3, Color(1, 0.5, 1))
	box(Mat.PLASTER, xf * Transform3D(Basis.IDENTITY, Vector3(0, 13.5, 0)), Vector3(w * 0.45, 3.0, d * 0.45),
		Color(WALL_TEMPLE, 0.5, 1))
	hip_roof(Mat.ROOF, xf * Transform3D(Basis.IDENTITY, Vector3(0, 16.3, 0)), w * 0.45, d * 0.45, 3.5, 2.6, 0.8,
		Color(1, 0.5, 1))


## Lanterne de pierre (toro), haute de ~3 m, a fenetre de papier lumineuse.
func stone_lantern(xf: Transform3D) -> void:
	cylinder(Mat.STONE, xf, 0.7, 0.6, 0.4, 8, Color(1, 0.5, 1))
	cylinder(Mat.STONE, xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.4, 0)), 0.22, 0.2, 1.3, 8, Color(1, 0.5, 1))
	box(Mat.STONE, xf * Transform3D(Basis.IDENTITY, Vector3(0, 1.7, 0)), Vector3(1.0, 0.25, 1.0), Color(1, 0.5, 1))
	box(Mat.PAPER, xf * Transform3D(Basis.IDENTITY, Vector3(0, 1.95, 0)), Vector3(0.6, 0.6, 0.6), Color.WHITE)
	hip_roof(Mat.STONE, xf * Transform3D(Basis.IDENTITY, Vector3(0, 2.6, 0)), 0.7, 0.7, 0.55, 0.35, 0.12, Color(1, 0.5, 1))


## Torii de `span` m entre piliers et `height` m sous le linteau : piliers
## vermillon sur socles noirs, nuki, shimaki vermillon et kasagi noir aux
## bouts releves.
func torii(xf: Transform3D, span: float, height: float) -> void:
	var half := span / 2.0
	var r := maxf(0.4, span * 0.03)
	for side: float in [-1.0, 1.0]:
		var at := xf * Transform3D(Basis.IDENTITY, Vector3(side * half, 0, 0))
		cylinder(Mat.LACQUER, at, r * 1.1, r * 0.95, height + r * 4.0, 16, Color.WHITE)
		cylinder(Mat.WOOD, at, r * 1.35, r * 1.3, r * 2.0, 16, Color.WHITE)
	var nuki_y := height * 0.78
	box(Mat.LACQUER, xf * Transform3D(Basis.IDENTITY, Vector3(0, nuki_y, 0)), Vector3(span + r * 5.0, r * 1.1, r * 0.9), Color.WHITE)
	var top_y := height + r * 2.6
	box(Mat.LACQUER, xf * Transform3D(Basis.IDENTITY, Vector3(0, top_y, 0)), Vector3(span + r * 7.0, r * 1.0, r * 1.5), Color.WHITE)
	box(Mat.WOOD, xf * Transform3D(Basis.IDENTITY, Vector3(0, top_y + r * 1.0, 0)), Vector3(span + r * 5.0, r * 0.9, r * 1.9), Color.WHITE)
	for side: float in [-1.0, 1.0]:
		var tip := Transform3D(Basis(Vector3.BACK, side * deg_to_rad(10.0)), Vector3(side * (half + r * 4.2), top_y + r * 1.3, 0))
		box(Mat.WOOD, xf * tip, Vector3(r * 5.0, r * 0.8, r * 1.9), Color.WHITE)
	box(Mat.WOOD, xf * Transform3D(Basis.IDENTITY, Vector3(0, nuki_y + r * 0.6, 0)), Vector3(r * 2.4, top_y - nuki_y - r * 0.6, r * 0.5), Color.WHITE)
