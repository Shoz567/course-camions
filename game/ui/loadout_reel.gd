class_name LoadoutReel
extends Control

## Rouleau vertical de la page de selection, facon Mario Kart 8 : le choix
## courant au centre dans une grande tuile, le precedent et le suivant en
## petit, estompes, au-dessus et en dessous ; le rouleau glisse quand le choix
## change. Titre en haut (avec un picto : la fleche de la croix ou ira le
## pouvoir). Etats : en attente, actif (liseré cyan, fleches haut / bas),
## valide (liseré rose et coche).
##
## Un rouleau d'un seul choix (pouvoirs, tant qu'il n'y en a aucun) montre
## des tuiles « ??? » verrouillees au-dessus et en dessous.

signal clicked(zone: int)    # -1 haut, 0 centre, 1 bas

var title: String = ""
var glyph: String = ""
## Choix : [{"name": String, "sub": String}].
var items: Array[Dictionary] = []
var index: int = 0
var active: bool = false:
	set(value):
		active = value
		queue_redraw()
var validated: bool = false:
	set(value):
		validated = value
		queue_redraw()
var accent: Color = UiKit.PINK
var _slide: float = 0.0
var _pulse: float = 0.0


func set_index(i: int, dir: int = 0) -> void:
	index = i
	_slide = float(dir)
	queue_redraw()


func current() -> Dictionary:
	return items[posmod(index, items.size())] if not items.is_empty() else {"name": "", "sub": ""}


func _process(delta: float) -> void:
	_pulse += delta
	if absf(_slide) > 0.001:
		_slide = lerpf(_slide, 0.0, 1.0 - exp(-14.0 * delta))
		queue_redraw()
	elif _slide != 0.0:
		_slide = 0.0
		queue_redraw()
	if active:
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		clicked.emit(-1)
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		clicked.emit(1)
	elif mb.button_index == MOUSE_BUTTON_LEFT:
		var y := mb.position.y / size.y
		clicked.emit(-1 if y < 0.33 else (1 if y > 0.72 else 0))
	accept_event()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var f := UiKit.font(800)
	var f_plain := UiKit.font(600, false)
	# titre
	var head := 30.0
	var title_size := 17
	var gx := 0.0
	if glyph != "":
		var gs := 24.0
		var g_rect := Rect2(Vector2(0, (head - gs) / 2.0), Vector2(gs, gs))
		_draw_glyph(glyph, g_rect)
		gx = gs + 6.0
	draw_string(f, Vector2(gx, head * 0.72), title, HORIZONTAL_ALIGNMENT_LEFT, w - gx, title_size,
		UiKit.CYAN if active else UiKit.DIM)
	# zone du rouleau
	var top := head + 6.0
	var area := Rect2(0, top, w, h - top)
	var tile_h := area.size.y * 0.42
	var small_h := area.size.y * 0.22
	var center_y := area.position.y + area.size.y / 2.0
	var lone := items.size() <= 1
	# voisins (glissent avec _slide)
	for k: int in [-1, 1]:
		var y := center_y + k * (tile_h / 2.0 + small_h / 2.0 + 8.0) + _slide * small_h * 0.6
		var r := Rect2(w * 0.1, y - small_h / 2.0, w * 0.8, small_h)
		var fade := clampf(1.0 - absf(_slide) * 0.5, 0.0, 1.0)
		if lone:
			_tile(r, Color(UiKit.TILE, 0.45 * fade), Color(1, 1, 1, 0.06), 1, 0)
			_centered(f, "? ? ?", r, 16, Color(UiKit.DIM, 0.45 * fade))
		else:
			var it: Dictionary = items[posmod(index + k, items.size())]
			_tile(r, Color(UiKit.TILE, 0.7 * fade), Color(1, 1, 1, 0.07), 1, 0)
			_centered(f, String(it["name"]), r, 15, Color(UiKit.DIM, 0.85 * fade))
	# tuile centrale
	var cy := center_y + _slide * tile_h * 0.35
	var cr := Rect2(0, cy - tile_h / 2.0, w, tile_h)
	var border := Color(1, 1, 1, 0.12)
	var bw := 1
	var glow := 0
	var fill := Color(UiKit.TILE, 0.97)
	if validated:
		border = accent
		bw = 3
	if active:
		var p := 0.6 + 0.4 * sin(_pulse * 6.0)
		border = UiKit.CYAN
		bw = 3
		glow = int(8 + 6 * p)
		fill = Color(UiKit.TILE_HOVER, 0.97)
	_tile(cr, fill, border, bw, glow)
	var it_c := current()
	var label_text := String(it_c["name"])
	var size_name := 24 if label_text.length() <= 10 else (20 if label_text.length() <= 14 else 16)
	_centered(f, label_text, Rect2(cr.position + Vector2(0, -tile_h * 0.14), cr.size), size_name, UiKit.TEXT)
	_centered(f_plain, String(it_c.get("sub", "")), Rect2(cr.position + Vector2(0, tile_h * 0.2), cr.size), 13,
		UiKit.DIM)
	if validated:
		# coche dans le coin haut droit de la tuile
		var c := cr.position + Vector2(w - 18.0, 16.0)
		draw_circle(c, 11.0, accent)
		draw_polyline(PackedVector2Array([c + Vector2(-5, 0), c + Vector2(-1.5, 4), c + Vector2(5, -4)]),
			UiKit.NIGHT, 2.5, true)
	if active:
		# fleches haut / bas
		var ax := w / 2.0
		var up_y := cr.position.y - 7.0
		var dn_y := cr.end.y + 7.0
		var col := Color(UiKit.CYAN, 0.9)
		draw_colored_polygon(PackedVector2Array([Vector2(ax, up_y - 9), Vector2(ax + 9, up_y), Vector2(ax - 9, up_y)]), col)
		draw_colored_polygon(PackedVector2Array([Vector2(ax, dn_y + 9), Vector2(ax - 9, dn_y), Vector2(ax + 9, dn_y)]), col)


func _tile(r: Rect2, fill: Color, border: Color, bw: int, glow: int) -> void:
	var sb := UiKit.box(fill, border, bw, UiKit.SKEW * 0.6, 4, Color(UiKit.CYAN, 0.45), glow)
	draw_style_box(sb, r)


## Texte centre dans `r`, police reduite jusqu'a tenir dans sa largeur.
func _centered(f: Font, text: String, r: Rect2, fs: int, col: Color) -> void:
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	while tw > r.size.x - 18.0 and fs > 9:
		fs -= 1
		tw = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2(r.position.x + (r.size.x - tw) / 2.0,
		r.position.y + (r.size.y + f.get_ascent(fs) - f.get_descent(fs)) / 2.0)
	draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Picto de la croix directionnelle, dessine comme PadGlyph (sans noeud).
func _draw_glyph(kind: String, r: Rect2) -> void:
	var c := r.get_center()
	var rad := r.size.y / 2.0
	var arm := rad * 0.36
	var dim := Color(UiKit.TEXT, 0.3)
	var lit := Vector2.LEFT if kind == "dpad_left" else (Vector2.RIGHT if kind == "dpad_right" else Vector2.ZERO)
	for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var center := c + d * (rad - arm)
		draw_rect(Rect2(center - Vector2(arm, arm), Vector2(arm, arm) * 2.0), UiKit.CYAN if d == lit else dim, true)
	draw_rect(Rect2(c - Vector2(arm, arm), Vector2(arm, arm) * 2.0), dim, true)
