class_name TrailerOverlay
extends CanvasLayer

## Habillage du trailer (dev/trailer.gd) : bandes noires du format cinema,
## flash blanc des coupes, textes qui claquent (grand titre italique a l'ombre
## rose, ligne cyan dessous), chiffres du compte a rebours, logo final
## (CRAZY blanc / WHEELS or, comme au menu) et fondu au noir. Tout s'anime a
## l'image (update(t) : temps de la video), jamais au temps reel ni au
## Engine.time_scale (les ralentis ne ralentissent pas les textes).

const BAR_H := 120.0
const W := 1920.0
const H := 1080.0

var _bars: Array[ColorRect] = []
var _flash: ColorRect
var _black: ColorRect
var _title: Label
var _sub: Label
var _count: Label
var _logo: Control
var _crazy: Label
var _wheels: Label
var _tag: Label
var _info: Label
## Echelle du titre courant, pour qu'il tienne dans l'image.
var _title_fit: float = 1.0
const TITLE_POS := Vector2(100, 650)
const SUB_POS := Vector2(112, 842)

## Textes programmes : [t0, t1, titre, sous-titre, couleur du titre].
var _texts: Array = []
## Flashs : [t0, duree, force].
var _flashes: Array = []
var bars_on: float = 1.0
var logo_at: float = INF
var black_from: float = INF
var black_to: float = INF
var count_marks: Array[float] = []


func _ready() -> void:
	layer = 90
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# flash des coupes : sur l'image, sous les textes et les bandes noires
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.size = Vector2(W, H)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_flash)
	_title = _big("M", 150, UiKit.TEXT)
	root.add_child(_title)
	# pivot au milieu du bord gauche : le titre grossit sur place
	_title.reset_size()
	_title.pivot_offset = Vector2(0.0, _title.size.y / 2.0)
	_title.text = ""
	_sub = UiKit.label("", 40, UiKit.CYAN, 800)
	_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_sub.add_theme_constant_override("outline_size", 10)
	root.add_child(_sub)
	_count = _big("", 300, UiKit.TEXT)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_count)
	_logo = Control.new()
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.size = Vector2(W, H)
	_logo.pivot_offset = Vector2(W / 2.0, H / 2.0 - 40.0)
	root.add_child(_logo)
	_crazy = _big("CRAZY", 230, UiKit.LOGO_TOP)
	_wheels = _big("WHEELS", 230, UiKit.LOGO_BOTTOM)
	for l: Label in [_crazy, _wheels]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size = Vector2(W, 260)
		l.add_theme_constant_override("shadow_offset_x", 12)
		l.add_theme_constant_override("shadow_offset_y", 12)
		_logo.add_child(l)
	_crazy.position = Vector2(-60, 250)
	_wheels.position = Vector2(60, 450)
	_tag = UiKit.label("COURSE DE CAMIONS ARCADE", 40, UiKit.CYAN, 800)
	_info = UiKit.label("", 30, UiKit.TEXT, 700)
	for l: Label in [_tag, _info]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size = Vector2(W, 60)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override("outline_size", 10)
		root.add_child(l)
	_tag.position = Vector2(0, 742)
	_info.position = Vector2(0, 810)
	for k in 2:
		var b := ColorRect.new()
		b.color = Color.BLACK
		b.size = Vector2(W, BAR_H)
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(b)
		_bars.append(b)
	_black = ColorRect.new()
	_black.color = Color(0, 0, 0, 0)
	_black.size = Vector2(W, H)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_black)


func _big(text: String, size: int, color: Color) -> Label:
	var l := UiKit.label(text, size, color, 900)
	l.add_theme_color_override("font_shadow_color", Color(UiKit.LOGO_SHADOW, 0.95))
	l.add_theme_constant_override("shadow_offset_x", 7)
	l.add_theme_constant_override("shadow_offset_y", 7)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 14)
	return l


func text(t0: float, t1: float, title: String, sub: String = "", color: Color = Color(-1, 0, 0)) -> void:
	_texts.append([t0, t1, title, sub, UiKit.TEXT if color.r < 0.0 else color])


func flash(t0: float, duration: float = 0.18, strength: float = 0.85) -> void:
	_flashes.append([t0, duration, strength])


static func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)


static func _back(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	var c := 1.9
	return 1.0 + (c + 1.0) * pow(x - 1.0, 3.0) + c * pow(x - 1.0, 2.0)


## Etat de l'habillage a l'instant `t` (s) de la video.
func update(t: float) -> void:
	# bandes noires (s'ouvrent pour le logo)
	var bh := BAR_H * bars_on
	_bars[0].position = Vector2(0, -BAR_H + bh)
	_bars[1].position = Vector2(0, H - bh)
	# flash
	var a := 0.0
	for f: Array in _flashes:
		var x := (t - float(f[0])) / float(f[1])
		if x >= 0.0 and x < 1.0:
			a = maxf(a, float(f[2]) * (1.0 - x) * (1.0 - x))
	_flash.color.a = a
	# grand titre (2026-10-23 : « des petits sauts visuels avec l'affichage du
	# texte ») : il claque sur place (grossi puis pose en 0,14 s), reste
	# parfaitement immobile et s'efface vite. Plus de derive lente : un texte
	# cale sur les pixels avancait par a-coups d'un pixel. Positions entieres.
	_title.visible = false
	_sub.visible = false
	for e: Array in _texts:
		var t0 := float(e[0])
		var t1 := float(e[1])
		if t < t0 or t > t1:
			continue
		if _title.text != String(e[2]):
			_title.text = String(e[2])
			var font := _title.get_theme_font(&"font")
			var fs := _title.get_theme_font_size(&"font_size")
			var width := font.get_string_size(_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 40.0
			_title_fit = minf(1.0, 1650.0 / maxf(width, 1.0))
		var into := _ease_out((t - t0) / 0.14)
		var out := clampf((t1 - t) / 0.12, 0.0, 1.0)
		var punch := lerpf(1.35, 1.0, into) * _title_fit
		_title.visible = true
		_title.add_theme_color_override("font_color", e[4])
		_title.scale = Vector2(punch, punch)
		_title.position = TITLE_POS
		_title.modulate.a = minf(clampf((t - t0) / 0.05, 0.0, 1.0), out)
		if String(e[3]) != "":
			_sub.visible = true
			_sub.text = String(e[3])
			_sub.position = SUB_POS
			_sub.modulate.a = minf(clampf((t - t0 - 0.12) / 0.12, 0.0, 1.0), out)
	# compte a rebours : chaque chiffre claque, grossit et s'efface en 1 s
	_count.visible = false
	for k in count_marks.size():
		var x := t - count_marks[k]
		if x >= 0.0 and x < 0.92:
			_count.visible = true
			_count.text = str(count_marks.size() - k)
			_count.size = Vector2(W, 360)
			_count.pivot_offset = Vector2(W / 2.0, 180)
			_count.position = Vector2(0, H / 2.0 - 200)
			var s := lerpf(1.7, 1.0, _ease_out(x / 0.12)) + x * 0.15
			_count.scale = Vector2(s, s)
			_count.modulate.a = clampf((0.92 - x) / 0.3, 0.0, 1.0)
	# logo : arrive en grand et se pose (rebond), puis respire
	var lx := t - logo_at
	_logo.visible = lx >= 0.0
	_tag.visible = lx >= 1.5
	_info.visible = lx >= 3.0
	if lx >= 0.0:
		var s := lerpf(2.6, 1.0, _back(lx / 0.34)) * (1.0 + 0.012 * sin(lx * 3.0))
		_logo.scale = Vector2(s, s)
		_logo.modulate.a = clampf(lx / 0.08, 0.0, 1.0)
		var shake := maxf(0.0, 0.35 - lx) * 40.0
		_logo.position = Vector2(sin(lx * 90.0) * shake, cos(lx * 77.0) * shake)
		_crazy.position.x = -60.0 - 500.0 * (1.0 - _ease_out(lx / 0.3))
		_wheels.position.x = 60.0 + 500.0 * (1.0 - _ease_out(lx / 0.3))
		_tag.modulate.a = clampf((lx - 1.5) / 0.25, 0.0, 1.0)
		_tag.position.x = 80.0 * (1.0 - _ease_out((lx - 1.5) / 0.3))
		_info.modulate.a = clampf((lx - 3.0) / 0.3, 0.0, 1.0)
	# fondu au noir
	if t >= black_from:
		_black.color.a = clampf((t - black_from) / maxf(black_to - black_from, 0.01), 0.0, 1.0)


func set_info(text_line: String) -> void:
	_info.text = text_line
