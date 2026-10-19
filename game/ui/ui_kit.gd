class_name UiKit
extends RefCounted

## Charte des menus (2026-10-16 : « fait une vraie belle UI de jeu video ») :
## arcade neon, comme le showroom de Cyber City derriere. Fonds bleu nuit
## translucides, rose neon pour ce qui est choisi, cyan pour le focus (manette,
## clavier), or pour l'action principale (PRET). Formes en parallelogramme
## (StyleBoxFlat.skew) et texte gras penche : ca file vers la droite.

const NIGHT := Color(0.025, 0.03, 0.075)
const PANEL := Color(0.045, 0.05, 0.11, 0.9)
const TILE := Color(0.09, 0.1, 0.19, 0.94)
const TILE_HOVER := Color(0.14, 0.15, 0.28, 0.96)
const PINK := Color(1.0, 0.17, 0.52)
const CYAN := Color(0.16, 0.9, 1.0)
const GOLD := Color(1.0, 0.79, 0.12)
const GOOD := Color(0.32, 1.0, 0.5)
const TEXT := Color(0.97, 0.97, 1.0)
const DIM := Color(0.62, 0.66, 0.82)
## Couleur de chaque joueur (BLEU, ROUGE, JAUNE, VERT, VIOLET, ORANGE).
const PLAYER_COLORS: Array[Color] = [Color(0.2, 0.55, 1.0), Color(1.0, 0.24, 0.24),
	Color(1.0, 0.84, 0.15), Color(0.25, 0.9, 0.4), Color(0.7, 0.32, 1.0), Color(1.0, 0.52, 0.12)]
## Inclinaison des boites (decalage horizontal par pixel de hauteur).
const SKEW := 0.2

static var _fonts: Dictionary = {}


## Police grasse, penchee si `italic` (la variation penche les glyphes : pas
## besoin d'une police italique installee).
static func font(weight: int = 800, italic: bool = true) -> Font:
	var key := "%d%s" % [weight, italic]
	if _fonts.has(key):
		return _fonts[key]
	var base := SystemFont.new()
	base.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial", "sans-serif"])
	base.font_weight = weight
	base.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	var v := FontVariation.new()
	v.base_font = base
	if weight >= 700:
		v.variation_embolden = 0.35
	if italic:
		v.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(0.2, 1.0), Vector2.ZERO)
	_fonts[key] = v
	return v


## Boite inclinee : fond, liseré, halo (ombre coloree sans decalage).
static func box(fill: Color, border: Color = Color(0, 0, 0, 0), border_width: int = 0,
		skew: float = SKEW, radius: int = 3, glow: Color = Color(0, 0, 0, 0), glow_size: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.skew = Vector2(skew, 0.0)
	sb.shadow_color = glow
	sb.shadow_size = glow_size
	sb.set_content_margin_all(12)
	sb.anti_aliasing = true
	return sb


static func label(text: String, size: int, color: Color = TEXT, weight: int = 800, italic: bool = true,
		outline: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight, italic))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Bouton de choix : tuile sombre, rose enfonce, liseré cyan lumineux au focus.
static func style_choice(b: Button, font_size: int, selected: Color = PINK) -> void:
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", font(800))
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_stylebox_override("normal", box(TILE, Color(1, 1, 1, 0.07), 1))
	b.add_theme_stylebox_override("hover", box(TILE_HOVER, Color(CYAN, 0.45), 1))
	b.add_theme_stylebox_override("pressed", box(selected, Color(1, 1, 1, 0.25), 1, SKEW, 3, Color(selected, 0.45), 10))
	b.add_theme_stylebox_override("hover_pressed", box(selected.lightened(0.1), Color(1, 1, 1, 0.45), 1, SKEW, 3,
		Color(selected, 0.55), 12))
	b.add_theme_stylebox_override("disabled", box(Color(TILE, 0.5), Color(1, 1, 1, 0.04), 1))
	b.add_theme_stylebox_override("focus", focus_box())
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, TEXT)
	b.add_theme_color_override("font_disabled_color", Color(DIM, 0.5))


## Cadre de focus : liseré cyan et halo, sans fond.
static func focus_box() -> StyleBoxFlat:
	var f := box(Color(0, 0, 0, 0), CYAN, 3, SKEW, 3, Color(CYAN, 0.5), 8)
	f.draw_center = false
	f.expand_margin_left = 3
	f.expand_margin_right = 3
	f.expand_margin_top = 3
	f.expand_margin_bottom = 3
	return f


## Bouton d'action principale (PRET) : or, texte nuit.
static func style_primary(b: Button, font_size: int) -> void:
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", font(900))
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_stylebox_override("normal", box(GOLD, Color(1, 1, 1, 0.35), 2, SKEW, 3, Color(GOLD, 0.35), 10))
	b.add_theme_stylebox_override("hover", box(GOLD.lightened(0.15), Color(1, 1, 1, 0.7), 2, SKEW, 3, Color(GOLD, 0.6), 16))
	b.add_theme_stylebox_override("pressed", box(GOLD.darkened(0.12), Color(1, 1, 1, 0.5), 2, SKEW, 3, Color(GOLD, 0.5), 8))
	b.add_theme_stylebox_override("focus", focus_box())
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, NIGHT)


## Petit bouton d'icone (son, parametres) : rond sombre, liseré au survol.
static func style_icon(b: Button, font_size: int) -> void:
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", font(800, false))
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_stylebox_override("normal", box(Color(PANEL, 0.85), Color(1, 1, 1, 0.12), 1, 0.0, 28))
	b.add_theme_stylebox_override("hover", box(TILE_HOVER, Color(CYAN, 0.6), 1, 0.0, 28))
	b.add_theme_stylebox_override("pressed", box(Color(PANEL, 0.85), Color(1, 1, 1, 0.12), 1, 0.0, 28))
	b.add_theme_stylebox_override("hover_pressed", box(TILE_HOVER, Color(CYAN, 0.6), 1, 0.0, 28))
	var f := box(Color(0, 0, 0, 0), CYAN, 3, 0.0, 28, Color(CYAN, 0.5), 8)
	f.draw_center = false
	b.add_theme_stylebox_override("focus", f)
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, TEXT)


## Intitule de section : trait cyan incline puis le texte en capitales.
static func section(text: String, size: int = 18) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tick := Panel.new()
	tick.custom_minimum_size = Vector2(10, size + 4)
	tick.add_theme_stylebox_override("panel", box(CYAN, Color(0, 0, 0, 0), 0, 0.35, 1, Color(CYAN, 0.5), 4))
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tick)
	var l := label(text.to_upper(), size, CYAN, 800)
	row.add_child(l)
	return row


static func gap(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Aide de commande : picto puis texte (« ✕ Valider »).
static func prompt(kind: String, text: String, size: int = 18) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := PadGlyph.new()
	g.kind = kind
	g.custom_minimum_size = Vector2(PadGlyph.width_for(kind, size + 10), size + 10)
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(g)
	row.add_child(label(text, size, TEXT, 600, false))
	return row


## Bandeau du haut et barre d'aide du bas d'une page (px, reference 1920 x 1080),
## comme la page de selection (LoadoutSelect).
const PAGE_TOP := 150.0
const PAGE_BOTTOM := 86.0


## Page plein ecran (2026-10-17, sur le modele de LoadoutSelect) : voile
## degrade sur le showroom, grand titre penche en haut a gauche, resume cyan
## a droite, filet rose, zone de contenu, barre d'aide en bas avec les pictos
## `prompts` ([[picto, texte], ...]). Le contenu se pose dans
## page_content(page) ; la page arrete les clics vers le menu derriere.
static func page(page_name: String, title: String, summary: String, prompts: Array) -> Control:
	var layer := Control.new()
	layer.name = page_name
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.visible = false
	var dim := TextureRect.new()
	var tex := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.025, 0.07, 0.95))
	g.set_color(1, Color(0.04, 0.02, 0.09, 0.82))
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(1, 1)
	dim.texture = tex
	dim.stretch_mode = TextureRect.STRETCH_SCALE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(dim)
	var head := label(title, 58, TEXT, 900)
	head.name = "Title"
	head.position = Vector2(64, 30)
	layer.add_child(head)
	var sum := label(summary, 22, CYAN, 800)
	sum.name = "Summary"
	sum.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	sum.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	sum.offset_top = 52
	sum.offset_right = -64
	sum.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	layer.add_child(sum)
	var rule := ColorRect.new()
	rule.color = Color(PINK, 0.8)
	rule.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	rule.offset_top = PAGE_TOP - 12
	rule.offset_bottom = PAGE_TOP - 10
	rule.offset_left = 64
	rule.offset_right = -64
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rule)
	var content := CenterContainer.new()
	content.name = "Content"
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_top = PAGE_TOP
	content.offset_bottom = -PAGE_BOTTOM
	content.offset_left = 40
	content.offset_right = -40
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(content)
	var bar := PanelContainer.new()
	bar.name = "HelpBar"
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -PAGE_BOTTOM + 14
	var sb := box(Color(0.02, 0.025, 0.06, 0.9), Color(0, 0, 0, 0), 0, 0.0, 0)
	sb.content_margin_left = 64
	bar.add_theme_stylebox_override("panel", sb)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bar)
	var help := HBoxContainer.new()
	help.add_theme_constant_override("separation", 34)
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(help)
	for p: Array in prompts:
		help.add_child(prompt(String(p[0]), String(p[1])))
	return layer


## Zone de contenu d'une page (centree entre le bandeau et la barre d'aide).
static func page_content(page_node: Control) -> Container:
	return page_node.get_node(^"Content") as Container


## Carte : fond nuit, liseré de couleur (cyan par defaut), coins droits comme
## les cartes de joueur de la page de selection.
static func card(border: Color = CYAN, width: float = 0.0) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(PANEL, Color(border, 0.75), 2, 0.0, 6, Color(border, 0.18), 18)
	sb.set_content_margin_all(28)
	p.add_theme_stylebox_override("panel", sb)
	if width > 0.0:
		p.custom_minimum_size = Vector2(width, 0)
	return p


## Champ de saisie (pseudo, adresse) : tuile sombre inclinee, liseré cyan au
## focus, texte gras droit, curseur cyan.
static func style_field(e: LineEdit) -> void:
	e.add_theme_font_override("font", font(700, false))
	e.add_theme_stylebox_override("normal", box(TILE, Color(1, 1, 1, 0.12), 1))
	e.add_theme_stylebox_override("focus", focus_box())
	e.add_theme_stylebox_override("read_only", box(Color(TILE, 0.5), Color(1, 1, 1, 0.05), 1))
	e.add_theme_color_override("font_color", TEXT)
	e.add_theme_color_override("font_placeholder_color", Color(DIM, 0.75))
	e.add_theme_color_override("caret_color", CYAN)
	e.add_theme_color_override("selection_color", Color(PINK, 0.45))
