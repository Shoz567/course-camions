class_name HudDial
extends Control

## Cadran de course (2026-10-19 : « un peu comme RL, le cercle avec les CD et
## la vitesse »), dessine a la main (_draw) en bas a droite de chaque vue :
##   - au centre, la vitesse en grand, « km/h » dessous ;
##   - anneau exterieur : la jauge de nitro (cyan, orange pendant le boost,
##     verte quand elle est prete), sur 270 deg ;
##   - arc interieur dore : la recharge du largage de remorque ;
##   - a gauche, deux pastilles rondes, une par pouvoir (croix gauche,
##     droite) : arc de recharge, secondes au centre ou PRET, nom dessous.
## Lit ce que RaceHud lui donne (set_state) ; ne decide rien.

## Taille de reference du cadran (px a ui_scale 1).
const SIZE := 250.0
const BADGE := 82.0
const START_DEG := 135.0
const SWEEP_DEG := 270.0

var ui_scale: float = 1.0
var speed_kmh: int = 0
var boost: float = 1.0
var boosting: bool = false
var boost_text: String = ""
var cargo: float = -1.0
## Par pouvoir : {"name": String, "ready": float 0..1, "left": int (s),
## "active": bool} ; vide si l'emplacement est libre.
var powers: Array[Dictionary] = [{}, {}]

var _font: Font
var _font_light: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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


func _draw() -> void:
	var k := ui_scale
	var r := SIZE * 0.5 * k
	var c := Vector2(size.x - r, size.y - r)
	# fond
	draw_circle(c, r, Color(UiKit.NIGHT, 0.72))
	draw_arc(c, r - 1.0, 0.0, TAU, 64, Color(UiKit.CYAN, 0.25), maxf(1.0, 2.0 * k), true)
	# nitro : anneau exterieur
	var ring := r - 14.0 * k
	var w := 14.0 * k
	_arc(c, ring, 1.0, Color(1, 1, 1, 0.08), w)
	var tint := Color(1.0, 0.55, 0.12) if boosting else (UiKit.GOOD if boost >= 1.0 else UiKit.CYAN)
	_arc(c, ring, boost, tint, w)
	# cargo : arc interieur
	if cargo >= 0.0:
		var inner := r - 34.0 * k
		_arc(c, inner, 1.0, Color(1, 1, 1, 0.06), 5.0 * k)
		_arc(c, inner, cargo, UiKit.GOLD if cargo >= 1.0 else Color(UiKit.GOLD, 0.6), 5.0 * k)
	# vitesse
	var big := maxi(12, roundi(78 * k))
	var txt := str(speed_kmh)
	var tw := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
	var speed_col := Color(1.0, 0.7, 0.25) if boosting else (UiKit.CYAN if speed_kmh >= 140 else UiKit.TEXT)
	_text(_font, txt, c + Vector2(-tw / 2.0, big * 0.32), big, speed_col)
	var small := maxi(9, roundi(20 * k))
	var unit := "km/h"
	var uw := _font_light.get_string_size(unit, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
	_text(_font_light, unit, c + Vector2(-uw / 2.0, big * 0.32 + small * 1.2), small, UiKit.DIM)
	if boost_text != "":
		var bw := _font_light.get_string_size(boost_text, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
		_text(_font_light, boost_text, c + Vector2(-bw / 2.0, r - 8.0 * k), small, tint)
	# pouvoirs : deux pastilles a gauche du cadran, l'une au-dessus de l'autre
	var br := BADGE * 0.5 * k
	for i in 2:
		var p := powers[i] if i < powers.size() else {}
		var bc := Vector2(c.x - r - 10.0 * k - br, c.y - r * 0.62 + i * (br * 2.0 + 36.0 * k))
		_badge(bc, br, i, p)


func _badge(c: Vector2, r: float, slot: int, p: Dictionary) -> void:
	var k := ui_scale
	draw_circle(c, r, Color(UiKit.NIGHT, 0.75))
	var small := maxi(8, roundi(15 * k))
	var arrow := "◄" if slot == 0 else "►"
	if p.is_empty():
		draw_arc(c, r - 2.0, 0.0, TAU, 40, Color(1, 1, 1, 0.12), maxf(1.0, 2.0 * k), true)
		var aw := _font.get_string_size(arrow, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
		_text(_font, arrow, c + Vector2(-aw / 2.0, small * 0.35), small, Color(UiKit.DIM, 0.6))
		return
	var ready := float(p.get("ready", 0.0))
	var active := bool(p.get("active", false))
	var col := UiKit.PINK if active else (UiKit.GOOD if ready >= 1.0 else UiKit.CYAN)
	draw_arc(c, r - 4.0 * k, 0.0, TAU, 40, Color(1, 1, 1, 0.08), 6.0 * k, true)
	if ready > 0.0:
		draw_arc(c, r - 4.0 * k, -PI / 2.0, -PI / 2.0 + TAU * ready, 40, col, 6.0 * k, true)
	var mid := "ON" if active else ("GO" if ready >= 1.0 else str(int(p.get("left", 0))))
	var mf := maxi(10, roundi(26 * k))
	var mw := _font.get_string_size(mid, HORIZONTAL_ALIGNMENT_LEFT, -1, mf).x
	_text(_font, mid, c + Vector2(-mw / 2.0, mf * 0.36), mf, col)
	var label := "%s %s" % [arrow, String(p.get("name", ""))]
	var lw := _font_light.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
	_text(_font_light, label, c + Vector2(-lw / 2.0, r + small * 1.1), small, Color(col, 0.95))


## Arc de la jauge : de START_DEG, sur `fraction` de SWEEP_DEG.
func _arc(c: Vector2, radius: float, fraction: float, color: Color, width: float) -> void:
	if fraction <= 0.0:
		return
	var a0 := deg_to_rad(START_DEG)
	var a1 := a0 + deg_to_rad(SWEEP_DEG) * clampf(fraction, 0.0, 1.0)
	draw_arc(Vector2(c), radius, a0, a1, maxi(8, roundi(48 * fraction)), color, width, true)


func _text(f: Font, s: String, at: Vector2, font_size: int, color: Color) -> void:
	draw_string_outline(f, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, maxi(2, roundi(font_size / 7.0)), Color(0, 0, 0, 0.8))
	draw_string(f, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
