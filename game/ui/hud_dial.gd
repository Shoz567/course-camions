class_name HudDial
extends Control

## Cadran de course (2026-10-19 : « un peu comme RL, le cercle avec les CD et
## la vitesse »), dessine a la main (_draw) en bas a droite de chaque vue :
##   - au centre, la vitesse en grand, « km/h » dessous ;
##   - anneau exterieur : la jauge de nitro, sur 270 deg ;
##   - arc interieur : la recharge du largage de remorque ;
##   - a gauche, deux tuiles, une par pouvoir (croix gauche, droite) : la
##     recharge les remplit par le bas, secondes au centre ou GO, nom dessous.
## Lit ce que RaceHud lui donne (set_state) ; ne decide rien.
##
## Habille comme le circuit (UiKit.skin, 2026-10-22 : « c'est des bons trucs
## mais visuellement ca blend pas, refais-les dans le style du jeu ») :
##   NEON   cadran de nuit, jauge en diodes qui s'allument du cyan au rose,
##          tubes lumineux ; tuiles en parallelogramme a liseré neon ;
##   PLAYA  bouee de sauvetage corail et blanche (la jauge) autour d'un lagon,
##          cordage ; tuiles de bois flotte cerclees de blanc ;
##   SAKURA disque de laque noire cercle d'or, jauge de laque vermillon a
##          graduations dorees, une fleur de cerisier en tete de jauge ;
##          tuiles en ema (plaquettes votives de bois, toit en pointe, cordon
##          rouge).

## Taille de reference du cadran (px a ui_scale 1).
const SIZE := 250.0
const BADGE := 82.0
const START_DEG := 135.0
const SWEEP_DEG := 270.0
## Diodes de la jauge neon.
const LEDS := 36

var ui_scale: float = 1.0
var speed_kmh: int = 0
var boost: float = 1.0
var boosting: bool = false
var boost_text: String = ""
var cargo: float = -1.0
## Par pouvoir : {"name": String, "ready": float 0..1, "left": int (s),
## "active": bool, "effect": float 0..1 (part de l'effet qui reste),
## "effect_left": int (s)} ; vide si l'emplacement est libre. Pouvoir actif :
## la tuile se vide avec l'effet, puis la recharge reprend.
var powers: Array[Dictionary] = [{}, {}]
## Habillage dessine (UiKit.Look), pris a la creation.
var look: int = UiKit.Look.NEON

var _font: Font
var _font_light: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	look = UiKit.skin
	_font = UiKit.font(900)
	_font_light = UiKit.font(700)
	var k := ui_scale
	custom_minimum_size = Vector2(SIZE + BADGE + 18.0, SIZE) * k
	size = custom_minimum_size


func set_state(kmh: int, charge: float, is_boosting: bool, label: String, cargo_charge: float,
		slots: Array[Dictionary]) -> void:
	speed_kmh = kmh
	boost = clampf(charge, 0.0, 1.0)
	boosting = is_boosting
	boost_text = label
	cargo = cargo_charge
	powers = slots
	queue_redraw()


## Couleur de la jauge de nitro (et du texte BOOST) selon l'etat.
func gauge_color() -> Color:
	match look:
		UiKit.Look.PLAYA:
			return Color(1.0, 0.62, 0.15) if boosting else (Color(1.0, 0.86, 0.25) if boost >= 1.0 else Color(1.0, 0.42, 0.3))
		UiKit.Look.SAKURA:
			return Color(1.0, 0.45, 0.12) if boosting else (UiKit.CYAN if boost >= 1.0 else UiKit.PINK)
	return Color(1.0, 0.55, 0.12) if boosting else (UiKit.GOOD if boost >= 1.0 else UiKit.CYAN)


func _draw() -> void:
	var k := ui_scale
	var r := SIZE * 0.5 * k
	var c := Vector2(size.x - r, size.y - r)
	match look:
		UiKit.Look.PLAYA:
			_dial_playa(c, r, k)
		UiKit.Look.SAKURA:
			_dial_sakura(c, r, k)
		_:
			_dial_neon(c, r, k)
	_speed(c, r, k)
	# pouvoirs : deux tuiles a gauche du cadran, l'une au-dessus de l'autre
	var bw := BADGE * k
	var bh := BADGE * 0.7 * k
	for i in 2:
		var p := powers[i] if i < powers.size() else {}
		var bc := Vector2(c.x - r - 12.0 * k - bw / 2.0, c.y - r * 0.6 + i * (bh + 40.0 * k))
		_badge(Rect2(bc - Vector2(bw, bh) / 2.0, Vector2(bw, bh)), i, p, k)


# --- cadrans ------------------------------------------------------------------

## Neon : nuit, tube cyan lumineux, diodes de nitro du cyan au rose.
func _dial_neon(c: Vector2, r: float, k: float) -> void:
	draw_circle(c, r, Color(UiKit.NIGHT, 0.8))
	draw_circle(c, r * 0.74, Color(UiKit.NIGHT.lightened(0.06), 0.6))
	_glow_arc(c, r - 1.5 * k, 0.0, TAU, Color(UiKit.CYAN, 0.75), maxf(1.0, 2.0 * k), k)
	var ring := r - 15.0 * k
	var w := 13.0 * k
	var pulse := 0.75 + 0.25 * sin(_now() * 5.0)
	for j in LEDS:
		var f0 := float(j) / LEDS
		var f1 := (j + 0.7) / LEDS
		var lit := (j + 0.5) / LEDS <= boost
		var col := Color(1, 1, 1, 0.07)
		if lit:
			col = UiKit.CYAN.lerp(UiKit.PINK, f0)
			if boosting:
				col = Color(1.0, 0.5, 0.1).lerp(UiKit.GOLD, f0) * (0.85 + 0.15 * sin(_now() * 30.0 + j))
			elif boost >= 1.0:
				col = Color(col, pulse)
			_seg(c, ring, f0, f1, Color(col, 0.18 * col.a), w + 8.0 * k)
		_seg(c, ring, f0, f1, col, w)
	# graduations : une diode sur six
	for j in range(0, LEDS + 1, 6):
		var a := _angle(float(j) / LEDS)
		draw_line(c + Vector2.from_angle(a) * (r - 6.0 * k), c + Vector2.from_angle(a) * (r - 2.5 * k),
			Color(UiKit.TEXT, 0.5), maxf(1.0, 1.5 * k), true)
	_cargo_arc(c, r - 34.0 * k, k, UiKit.GOLD, true)


## Playa : bouee de sauvetage corail et blanche (la jauge), cordage, lagon.
func _dial_playa(c: Vector2, r: float, k: float) -> void:
	# lagon : turquoise profond, eclat de soleil en haut
	draw_circle(c, r - 22.0 * k, Color(0.02, 0.34, 0.42, 0.94))
	draw_circle(c, r - 30.0 * k, Color(0.03, 0.42, 0.5, 0.94))
	draw_arc(c, r - 44.0 * k, deg_to_rad(205.0), deg_to_rad(250.0), 16, Color(1, 1, 1, 0.18), 4.0 * k, true)
	var ring := r - 12.0 * k
	var w := 20.0 * k
	# bouee : contour sombre, puis huit quartiers corail / blanc sur 270 deg
	_arc(c, ring, 1.0, Color(0.02, 0.2, 0.26, 0.9), w + 4.0 * k)
	var parts := 8
	for j in parts:
		var f0 := float(j) / parts
		var f1 := float(j + 1) / parts
		var col := Color(1.0, 0.42, 0.3) if j % 2 == 0 else Color(0.98, 0.97, 0.93)
		if boosting:
			col = col.lerp(Color(1.0, 0.75, 0.2), 0.35)
		# rempli : franc ; vide : delave
		var lit := clampf((boost - f0) / (f1 - f0), 0.0, 1.0)
		_seg(c, ring, f0, f1, Color(col.lerp(Color(0.5, 0.62, 0.66), 0.55), 0.55), w)
		if lit > 0.0:
			_seg(c, ring, f0, lerpf(f0, f1, lit), col, w)
	# reflet sur le haut de la bouee
	_arc_between(c, ring + w * 0.25, 0.25, 0.75, Color(1, 1, 1, 0.22), 3.0 * k)
	# cordage : quatre boucles beiges en travers de la bouee
	for f: float in [0.125, 0.375, 0.625, 0.875]:
		var a := _angle(f)
		var dir := Vector2.from_angle(a)
		var side := dir.orthogonal() * 4.0 * k
		draw_line(c + dir * (ring - w * 0.62) - side, c + dir * (ring + w * 0.62) + side, Color(0.86, 0.74, 0.52), 3.5 * k, true)
		draw_line(c + dir * (ring - w * 0.62) + side, c + dir * (ring + w * 0.62) - side, Color(0.7, 0.58, 0.38), 2.0 * k, true)
	if boost >= 1.0 and not boosting:
		var pulse := 0.5 + 0.5 * sin(_now() * 4.0)
		_arc(c, ring, 1.0, Color(1.0, 0.95, 0.6, 0.25 * pulse), w + 6.0 * k)
	_cargo_arc(c, r - 38.0 * k, k, Color(1.0, 0.85, 0.3), false)


## Sakura : laque noire cerclee d'or, jauge de laque vermillon graduee d'or,
## fleur de cerisier en tete de jauge.
func _dial_sakura(c: Vector2, r: float, k: float) -> void:
	draw_circle(c, r, Color(UiKit.PRIMARY_FILL, 0.95))
	draw_circle(c, r * 0.72, Color(0.13, 0.05, 0.035, 0.9))
	draw_arc(c, r - 1.5 * k, 0.0, TAU, 64, UiKit.PRIMARY_BORDER, maxf(1.0, 2.5 * k), true)
	draw_arc(c, r - 6.0 * k, 0.0, TAU, 64, Color(UiKit.PRIMARY_BORDER, 0.5), maxf(1.0, 1.0 * k), true)
	var ring := r - 18.0 * k
	var w := 12.0 * k
	_arc(c, ring, 1.0, Color(0.32, 0.07, 0.04, 0.55), w)
	var col := gauge_color()
	if boost >= 1.0 and not boosting:
		col = Color(col, 0.8 + 0.2 * sin(_now() * 4.0))
	_arc(c, ring, boost, col, w)
	# liseres d'or de part et d'autre de la jauge
	_arc(c, ring - w / 2.0 - 1.5 * k, 1.0, Color(UiKit.PRIMARY_BORDER, 0.55), maxf(1.0, 1.0 * k))
	_arc(c, ring + w / 2.0 + 1.5 * k, 1.0, Color(UiKit.PRIMARY_BORDER, 0.55), maxf(1.0, 1.0 * k))
	for j in 10:
		var a := _angle(j / 9.0)
		draw_line(c + Vector2.from_angle(a) * (ring - w / 2.0), c + Vector2.from_angle(a) * (ring + w / 2.0),
			Color(UiKit.PRIMARY_BORDER, 0.85), maxf(1.0, 1.5 * k), true)
	_cargo_arc(c, r - 36.0 * k, k, UiKit.PRIMARY_BORDER, false)
	if boost > 0.02:
		_blossom(c + Vector2.from_angle(_angle(boost)) * ring, 9.0 * k, _now() * 0.8)


## Vitesse au centre, « km/h » dessous, etat du boost en bas.
func _speed(c: Vector2, r: float, k: float) -> void:
	var big := maxi(12, roundi(78 * k))
	var txt := str(speed_kmh)
	var tw := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
	var at := c + Vector2(-tw / 2.0, big * 0.32)
	var col := UiKit.TEXT
	var unit_col := UiKit.DIM
	match look:
		UiKit.Look.NEON:
			col = Color(1.0, 0.72, 0.3) if boosting else (UiKit.CYAN.lerp(UiKit.TEXT, 0.35) if speed_kmh >= 140 else UiKit.TEXT)
			# halo neon autour des chiffres
			draw_string_outline(_font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, big, maxi(6, roundi(big / 5.0)),
				Color(UiKit.CYAN if not boosting else Color(1.0, 0.5, 0.1), 0.22))
		UiKit.Look.PLAYA:
			col = Color(1.0, 0.88, 0.4) if boosting else Color(1.0, 0.99, 0.95)
			unit_col = Color(0.98, 0.86, 0.62)
		UiKit.Look.SAKURA:
			col = Color(1.0, 0.7, 0.4) if boosting else UiKit.TEXT
			unit_col = UiKit.PRIMARY_BORDER
	_text(_font, txt, at, big, col)
	var small := maxi(9, roundi(20 * k))
	var unit := "km/h"
	var uw := _font_light.get_string_size(unit, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
	_text(_font_light, unit, c + Vector2(-uw / 2.0, big * 0.32 + small * 1.2), small, unit_col)
	if boost_text != "":
		var bw := _font_light.get_string_size(boost_text, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
		_text(_font_light, boost_text, c + Vector2(-bw / 2.0, r - 8.0 * k), small, gauge_color())


## Arc interieur du largage de remorque (rien sans remorque).
func _cargo_arc(c: Vector2, radius: float, k: float, col: Color, glow: bool) -> void:
	if cargo < 0.0:
		return
	_arc(c, radius, 1.0, Color(1, 1, 1, 0.07), 5.0 * k)
	var tint := col if cargo >= 1.0 else Color(col, 0.6)
	if glow and cargo >= 1.0:
		_arc(c, radius, cargo, Color(col, 0.22), 11.0 * k)
	_arc(c, radius, cargo, tint, 5.0 * k)


# --- tuiles des pouvoirs --------------------------------------------------------

func _badge(rect: Rect2, slot: int, p: Dictionary, k: float) -> void:
	var shape := _badge_shape(rect)
	var small := maxi(8, roundi(15 * k))
	var arrow := "◄" if slot == 0 else "►"
	if p.is_empty():
		draw_colored_polygon(shape, Color(UiKit.NIGHT, 0.45))
		_outline(shape, Color(UiKit.TEXT, 0.16), maxf(1.0, 1.5 * k), false)
		var aw := _font.get_string_size(arrow, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
		_text(_font, arrow, rect.get_center() + Vector2(-aw / 2.0, small * 0.35), small, Color(UiKit.DIM, 0.6))
		return
	var ready := float(p.get("ready", 0.0))
	var active := bool(p.get("active", false))
	var effect := float(p.get("effect", 0.0))
	var on := active or ready >= 1.0
	var fill := effect if active and effect > 0.0 else ready
	var hot := _hot_color()
	var cool := _cool_color()
	var col := hot if on else cool
	var pulse := 0.8 + 0.2 * sin(_now() * 5.0 + slot)
	# fond (bois teinte selon l'habillage), puis le remplissage par le bas
	var tex := UiKit.tile_texture
	if tex != null:
		var tint := Color(1, 1, 1) if on else Color(0.62, 0.6, 0.58)
		draw_colored_polygon(shape, tint, _uvs(shape, rect), tex)
	else:
		draw_colored_polygon(shape, Color(UiKit.NIGHT, 0.82))
	if fill > 0.0 and fill < 1.0 or active:
		var cut := rect.position.y + rect.size.y * (1.0 - clampf(fill, 0.0, 1.0))
		var band := PackedVector2Array([Vector2(rect.position.x - rect.size.x, cut),
			Vector2(rect.end.x + rect.size.x, cut), Vector2(rect.end.x + rect.size.x, rect.end.y + 4.0),
			Vector2(rect.position.x - rect.size.x, rect.end.y + 4.0)])
		for part in Geometry2D.intersect_polygons(shape, band):
			draw_colored_polygon(part, Color(col, 0.38 if tex == null else 0.5))
	# liseré : tube lumineux (neon), cadre blanc (plage), bois sombre (Japon)
	match look:
		UiKit.Look.NEON:
			_outline(shape, Color(col, pulse if on else 0.7), maxf(1.0, 2.0 * k), true)
		UiKit.Look.PLAYA:
			_outline(shape, Color(UiKit.tile_edge, 0.95), maxf(1.0, 3.0 * k), false)
			if on:
				_outline(shape, Color(col, 0.6 * pulse), maxf(1.0, 1.5 * k), false)
		UiKit.Look.SAKURA:
			_outline(shape, UiKit.tile_edge, maxf(1.0, 2.5 * k), false)
			# cordon rouge au sommet de l'ema
			var top := shape[3]
			draw_arc(top + Vector2(0, -5.0 * k), 5.0 * k, 0.0, TAU, 12, Color(0.85, 0.12, 0.08), maxf(1.0, 2.0 * k), true)
	var mid := "GO" if ready >= 1.0 else str(int(p.get("left", 0)))
	if active:
		mid = str(int(p.get("effect_left", 0))) if effect > 0.0 else "ON"
	var mf := maxi(10, roundi(26 * k))
	var mw := _font.get_string_size(mid, HORIZONTAL_ALIGNMENT_LEFT, -1, mf).x
	var text_col := col
	if tex != null:
		# sur le bois : texte sombre (Japon) ou blanc (plage), couleur d'etat en halo
		text_col = UiKit.BTN_TEXT if look == UiKit.Look.SAKURA else Color(1, 1, 1)
		if on:
			text_col = UiKit.PINK if look == UiKit.Look.SAKURA else Color(1.0, 0.98, 0.9)
	_text(_font, mid, rect.get_center() + Vector2(-mw / 2.0, mf * 0.36 + (2.0 * k if look == UiKit.Look.SAKURA else 0.0)),
		mf, text_col)
	var label := "%s %s" % [arrow, String(p.get("name", ""))]
	var lw := _font_light.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
	# sous la tuile, sur la route : texte clair cerne de sombre (le nom a la
	# couleur d'etat ne se lisait pas en plein jour)
	var name_col := col.lerp(UiKit.TEXT, 0.25) if look == UiKit.Look.NEON else UiKit.TEXT
	_text(_font_light, label, Vector2(rect.get_center().x - lw / 2.0, rect.end.y + small * 1.15), small, name_col)


## Contour de la tuile : parallelogramme (neon, plage), ema (Japon).
func _badge_shape(rect: Rect2) -> PackedVector2Array:
	var x0 := rect.position.x
	var x1 := rect.end.x
	var y0 := rect.position.y
	var y1 := rect.end.y
	if look == UiKit.Look.SAKURA:
		var roof := rect.size.y * 0.28
		return PackedVector2Array([Vector2(x0, y1), Vector2(x1, y1), Vector2(x1, y0 + roof),
			Vector2((x0 + x1) / 2.0, y0), Vector2(x0, y0 + roof)])
	var sk := UiKit.SKEW * rect.size.y * 0.5
	return PackedVector2Array([Vector2(x0 - sk, y1), Vector2(x1 - sk, y1), Vector2(x1 + sk, y0), Vector2(x0 + sk, y0)])


## Couleur d'un pouvoir pret ou actif, et en recharge.
func _hot_color() -> Color:
	match look:
		UiKit.Look.PLAYA:
			return Color(1.0, 0.86, 0.25)
		UiKit.Look.SAKURA:
			return UiKit.PINK
	return UiKit.GOOD


func _cool_color() -> Color:
	match look:
		UiKit.Look.PLAYA:
			return Color(1.0, 0.42, 0.3)
		UiKit.Look.SAKURA:
			return Color(0.55, 0.32, 0.2)
	return UiKit.CYAN


# --- primitives -----------------------------------------------------------------

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _angle(fraction: float) -> float:
	return deg_to_rad(START_DEG) + deg_to_rad(SWEEP_DEG) * fraction


## Arc de la jauge : de START_DEG, sur `fraction` de SWEEP_DEG.
func _arc(c: Vector2, radius: float, fraction: float, color: Color, width: float) -> void:
	if fraction <= 0.0:
		return
	_arc_between(c, radius, 0.0, clampf(fraction, 0.0, 1.0), color, width)


func _arc_between(c: Vector2, radius: float, f0: float, f1: float, color: Color, width: float) -> void:
	if f1 <= f0:
		return
	draw_arc(c, radius, _angle(f0), _angle(f1), maxi(4, roundi(48 * (f1 - f0))), color, width, true)


## Morceau de jauge entre les fractions f0 et f1 (diode, quartier de bouee).
func _seg(c: Vector2, radius: float, f0: float, f1: float, color: Color, width: float) -> void:
	_arc_between(c, radius, f0, f1, color, width)


## Arc lumineux (neon) : deux passes larges et pales sous le trait.
func _glow_arc(c: Vector2, radius: float, a0: float, a1: float, color: Color, width: float, k: float) -> void:
	draw_arc(c, radius, a0, a1, 64, Color(color, color.a * 0.12), width + 10.0 * k, true)
	draw_arc(c, radius, a0, a1, 64, Color(color, color.a * 0.3), width + 4.0 * k, true)
	draw_arc(c, radius, a0, a1, 64, color, width, true)


func _outline(shape: PackedVector2Array, color: Color, width: float, glow: bool) -> void:
	var loop := shape.duplicate()
	loop.append(shape[0])
	if glow:
		draw_polyline(loop, Color(color, color.a * 0.15), width * 5.0, true)
		draw_polyline(loop, Color(color, color.a * 0.35), width * 2.5, true)
	draw_polyline(loop, color, width, true)


func _uvs(shape: PackedVector2Array, rect: Rect2) -> PackedVector2Array:
	var uvs := PackedVector2Array()
	for v in shape:
		uvs.append((v - rect.position) / rect.size)
	return uvs


## Fleur de cerisier : cinq petales roses ovales, nervure soutenue, coeur
## clair.
func _blossom(at: Vector2, radius: float, spin: float) -> void:
	for j in 5:
		var a := spin + TAU * j / 5.0
		var dir := Vector2.from_angle(a)
		var center := at + dir * radius * 0.52
		var petal := PackedVector2Array()
		for q in 12:
			var t := TAU * q / 12.0
			petal.append(center + Vector2(cos(t) * radius * 0.5, sin(t) * radius * 0.34).rotated(a))
		draw_colored_polygon(petal, Color(1.0, 0.72, 0.82))
		draw_line(at, at + dir * radius * 0.45, Color(0.92, 0.42, 0.56), maxf(1.0, radius * 0.1), true)
	draw_circle(at, radius * 0.22, Color(1.0, 0.92, 0.55))


func _text(f: Font, s: String, at: Vector2, font_size: int, color: Color) -> void:
	var edge := Color(0, 0, 0, 0.8)
	if look == UiKit.Look.PLAYA:
		edge = Color(0.0, 0.16, 0.2, 0.85)
	elif look == UiKit.Look.SAKURA:
		edge = Color(0.05, 0.02, 0.01, 0.85) if color.get_luminance() > 0.35 else Color(1.0, 0.95, 0.85, 0.5)
	draw_string_outline(f, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, maxi(2, roundi(font_size / 7.0)), edge)
	draw_string(f, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
