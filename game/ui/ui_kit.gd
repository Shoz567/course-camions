class_name UiKit
extends RefCounted

## Charte des menus (2026-10-16 : « fait une vraie belle UI de jeu video »),
## declinee par circuit (2026-10-19 : « quand on selectionne une des 3 vibes
## ca change aussi le UI ... la DA entiere change ») : trois habillages
## (Look), choisis par le circuit du menu (skin_for_track) et gardes jusqu'a
## la course (ecran de chargement, HUD) :
##   NEON   (Cyber City) arcade neon : fonds bleu nuit translucides, rose pour
##          ce qui est choisi, cyan pour le focus, or pour l'action
##          principale ; parallelogrammes et texte gras penche ;
##   PLAYA  (Playa Del Sol) bord de mer : tuiles de bois flotte, lagon
##          turquoise pour le choix, corail pour le focus, bouton soleil ;
##          parallelogrammes (comme partout), texte droit et rond ;
##   SAKURA (Sakura) Japon : cases de bois de miel cadrees de bois sombre,
##          laque vermillon pour le choix, rose cerisier pour le focus, plaque
##          de laque noire a lettres d'or pour l'action ; parallelogrammes,
##          police a empattements (Mincho).
## Les couleurs sont des variables (apply_skin) : un menu se reconstruit
## pour changer d'habillage. Le texte courant reste clair dans les trois
## (lisible sur tous les fonds sombres) ; le texte des tuiles (BTN_TEXT)
## suit leur fond.

enum Look { NEON, PLAYA, SAKURA }

## Couleur de chaque joueur (BLEU, ROUGE, JAUNE, VERT, VIOLET, ORANGE ; en
## ligne, jusqu'a 12 : ROSE, CYAN, BLANC, CITRON, BRONZE, MENTHE).
const PLAYER_COLORS: Array[Color] = [Color(0.2, 0.55, 1.0), Color(1.0, 0.24, 0.24),
	Color(1.0, 0.84, 0.15), Color(0.25, 0.9, 0.4), Color(0.7, 0.32, 1.0), Color(1.0, 0.52, 0.12),
	Color(1.0, 0.45, 0.75), Color(0.2, 0.9, 1.0), Color(0.95, 0.95, 0.97), Color(0.75, 1.0, 0.2),
	Color(0.8, 0.55, 0.3), Color(0.55, 1.0, 0.78)]

static var skin: int = Look.NEON
## Fond (voiles, barres), panneau, tuile sombre (cartes, cases a plat).
static var NIGHT := Color(0.025, 0.03, 0.075)
static var PANEL := Color(0.045, 0.05, 0.11, 0.9)
static var TILE := Color(0.09, 0.1, 0.19, 0.94)
static var TILE_HOVER := Color(0.14, 0.15, 0.28, 0.96)
## Choisi (rose en neon), focus et intitules (cyan), action (or), succes.
static var PINK := Color(1.0, 0.17, 0.52)
static var CYAN := Color(0.16, 0.9, 1.0)
static var GOLD := Color(1.0, 0.79, 0.12)
static var GOOD := Color(0.32, 1.0, 0.5)
## Texte sur les fonds sombres, et secondaire.
static var TEXT := Color(0.97, 0.97, 1.0)
static var DIM := Color(0.62, 0.66, 0.82)
## Texte sur les tuiles, sur une tuile choisie, sur le bouton d'action.
static var BTN_TEXT := Color(0.97, 0.97, 1.0)
static var SEL_TEXT := Color(0.97, 0.97, 1.0)
static var PRIMARY_FILL := Color(1.0, 0.79, 0.12)
static var PRIMARY_TEXT := Color(0.025, 0.03, 0.075)
static var PRIMARY_BORDER := Color(1, 1, 1, 0.35)
## Logo : CRAZY, WHEELS, ombre.
static var LOGO_TOP := Color(0.97, 0.97, 1.0)
static var LOGO_BOTTOM := Color(1.0, 0.79, 0.12)
static var LOGO_SHADOW := Color(1.0, 0.17, 0.52)
## Inclinaison des boites (decalage horizontal par pixel de hauteur), rayon
## des coins, epaisseur des liserés.
static var SKEW := 0.2
static var RADIUS := 3
## Police : familles, penchee ou non.
static var FONT_NAMES := PackedStringArray(["Bahnschrift", "Segoe UI", "Arial", "sans-serif"])
static var ITALIC := true
## Tuiles texturees (bois) : null = a plat (TILE). `tint_texture` : le meme
## bois en gris, a teinter (boutons des joueurs) : la couleur du joueur y
## reste franche, la ou le bois de miel la virerait au brun ou au vert.
static var tile_texture: Texture2D = null
static var tint_texture: Texture2D = null
## Couleur du cadre des tuiles (trait lisse du bord des parallelogrammes).
static var tile_edge := Color(0, 0, 0, 0)

static var _fonts: Dictionary = {}
static var _textures: Dictionary = {}


## Habillage d'un circuit (GameState.TRACKS) : Cyber City, Playa, Sakura.
static func skin_for_track(track: int) -> int:
	match track:
		1: return Look.PLAYA
		2: return Look.SAKURA
	return Look.NEON


## Pose l'habillage `s` : couleurs, formes, police, textures. Les controles
## deja construits ne changent pas (le menu se reconstruit).
static func apply_skin(s: int) -> void:
	skin = s
	match s:
		Look.PLAYA:
			NIGHT = Color(0.0, 0.13, 0.18)
			PANEL = Color(0.01, 0.17, 0.22, 0.92)
			TILE = Color(0.03, 0.24, 0.29, 0.94)
			TILE_HOVER = Color(0.05, 0.33, 0.38, 0.96)
			PINK = Color(0.0, 0.66, 0.72)
			CYAN = Color(1.0, 0.5, 0.38)
			GOLD = Color(1.0, 0.8, 0.22)
			GOOD = Color(0.45, 1.0, 0.6)
			TEXT = Color(1.0, 0.99, 0.95)
			DIM = Color(0.74, 0.9, 0.9)
			BTN_TEXT = Color(0.12, 0.2, 0.24)
			SEL_TEXT = Color(1.0, 1.0, 1.0)
			PRIMARY_FILL = Color(1.0, 0.78, 0.2)
			PRIMARY_TEXT = Color(0.02, 0.22, 0.28)
			PRIMARY_BORDER = Color(1, 1, 1, 0.9)
			LOGO_TOP = Color(1.0, 1.0, 1.0)
			LOGO_BOTTOM = Color(1.0, 0.82, 0.25)
			LOGO_SHADOW = Color(0.0, 0.55, 0.62)
			# parallelogrammes comme Cyber City (2026-10-20, « garder la meme
			# forme de parallelogramme dans tous les menus »)
			SKEW = 0.2
			RADIUS = 3
			tile_edge = Color(0.98, 0.97, 0.93)
			FONT_NAMES = PackedStringArray(["Segoe UI", "Arial", "sans-serif"])
			ITALIC = false
			tile_texture = plank_texture(Color(0.86, 0.81, 0.72), Color(0.66, 0.6, 0.52), Color(0.98, 0.97, 0.93), 3)
			tint_texture = plank_texture(Color(1.0, 1.0, 1.0), Color(0.76, 0.76, 0.76), Color(1.0, 1.0, 1.0), 3)
		Look.SAKURA:
			NIGHT = Color(0.075, 0.04, 0.028)
			PANEL = Color(0.11, 0.065, 0.042, 0.94)
			TILE = Color(0.2, 0.12, 0.075, 0.95)
			TILE_HOVER = Color(0.29, 0.17, 0.1, 0.97)
			PINK = Color(0.8, 0.13, 0.06)
			CYAN = Color(1.0, 0.64, 0.75)
			GOLD = Color(0.95, 0.76, 0.34)
			GOOD = Color(0.5, 0.9, 0.45)
			TEXT = Color(0.99, 0.95, 0.87)
			DIM = Color(0.84, 0.74, 0.64)
			BTN_TEXT = Color(0.2, 0.1, 0.05)
			SEL_TEXT = Color(1.0, 0.94, 0.8)
			PRIMARY_FILL = Color(0.07, 0.045, 0.04)
			PRIMARY_TEXT = Color(0.97, 0.8, 0.4)
			PRIMARY_BORDER = Color(0.95, 0.76, 0.34)
			LOGO_TOP = Color(0.99, 0.95, 0.87)
			LOGO_BOTTOM = Color(0.86, 0.16, 0.08)
			LOGO_SHADOW = Color(0.03, 0.02, 0.02)
			SKEW = 0.2
			RADIUS = 2
			tile_edge = Color(0.2, 0.11, 0.06)
			# Cambria avant Georgia (2026-10-20) : sans Yu Mincho (option du
			# japonais sous Windows), Georgia ecrit les chiffres a l'ancienne
			# (« o manette », « J1 » bas) et elargit les legendes ; Cambria a
			# des chiffres alignes et tient dans les cases
			FONT_NAMES = PackedStringArray(["Yu Mincho", "MS Mincho", "Cambria", "Georgia", "serif"])
			ITALIC = false
			tile_texture = plank_texture(Color(0.72, 0.5, 0.29), Color(0.52, 0.33, 0.17), Color(0.2, 0.11, 0.06), 7)
			tint_texture = plank_texture(Color(1.0, 1.0, 1.0), Color(0.7, 0.7, 0.7), Color(0.2, 0.11, 0.06), 7)
		_:
			skin = Look.NEON
			NIGHT = Color(0.025, 0.03, 0.075)
			PANEL = Color(0.045, 0.05, 0.11, 0.9)
			TILE = Color(0.09, 0.1, 0.19, 0.94)
			TILE_HOVER = Color(0.14, 0.15, 0.28, 0.96)
			PINK = Color(1.0, 0.17, 0.52)
			CYAN = Color(0.16, 0.9, 1.0)
			GOLD = Color(1.0, 0.79, 0.12)
			GOOD = Color(0.32, 1.0, 0.5)
			TEXT = Color(0.97, 0.97, 1.0)
			DIM = Color(0.62, 0.66, 0.82)
			BTN_TEXT = TEXT
			SEL_TEXT = TEXT
			PRIMARY_FILL = GOLD
			PRIMARY_TEXT = NIGHT
			PRIMARY_BORDER = Color(1, 1, 1, 0.35)
			LOGO_TOP = TEXT
			LOGO_BOTTOM = GOLD
			LOGO_SHADOW = PINK
			SKEW = 0.2
			RADIUS = 3
			tile_edge = Color(0, 0, 0, 0)
			FONT_NAMES = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial", "sans-serif"])
			ITALIC = true
			tile_texture = null
			tint_texture = null


## Planches de bois (une case) : veinage etire dans la longueur, cernes,
## nuances par planche, cadre `frame` de 5 px biseaute. Deterministe, mise en
## cache. Bois de miel (Sakura), bois flotte blanchi (Playa).
static func plank_texture(light: Color, dark: Color, frame: Color, seed_value: int) -> Texture2D:
	var key := "%s%s%s%d" % [light, dark, frame, seed_value]
	if _textures.has(key):
		return _textures[key]
	var w := 256
	var h := 96
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 1.0
	# trois planches : une large au milieu (le texte d'un bouton n'y est pas
	# barre par un joint), deux etroites en haut et en bas
	var joints := [0.0, 0.2, 0.8, 1.0]
	for y in h:
		var v := float(y) / h
		var plank := 0 if v < joints[1] else (1 if v < joints[2] else 2)
		var tone := 0.88 + 0.24 * fposmod(sin(plank * 12.9 + seed_value) * 43.7, 1.0)
		for x in w:
			var n := noise.get_noise_2d(x * 0.012, y * 0.22 + plank * 7.0)
			var ring := 0.5 + 0.5 * sin((y + n * 26.0) * 0.55 + plank * 2.0)
			var grain := noise.get_noise_2d(x * 0.08, y * 1.4) * 0.5 + 0.5
			var c := dark.lerp(light, clampf(0.35 + 0.45 * ring * grain + 0.2 * n, 0.0, 1.0)) * tone
			# joint entre deux planches
			if absf(v - joints[1]) < 0.015 or absf(v - joints[2]) < 0.015:
				c = c.darkened(0.45)
			c.a = 1.0
			img.set_pixel(x, y, c)
	# cadre biseaute : clair en haut a gauche, sombre en bas a droite
	var border := 5
	for y in h:
		for x in w:
			var d := mini(mini(x, y), mini(w - 1 - x, h - 1 - y))
			if d < border:
				var c := frame
				if d == border - 1:
					c = frame.lightened(0.25) if (x < w / 2 and y < h / 2) else frame.darkened(0.3)
				img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_textures[key] = tex
	return tex


## Police de l'habillage, grasse, penchee si `italic` et si l'habillage
## penche (la variation penche les glyphes : pas besoin d'une police
## italique installee).
static func font(weight: int = 800, italic: bool = true) -> Font:
	var slanted := italic and ITALIC
	var key := "%s%d%s" % [",".join(FONT_NAMES), weight, slanted]
	if _fonts.has(key):
		return _fonts[key]
	var base := SystemFont.new()
	base.font_names = FONT_NAMES
	base.font_weight = weight
	base.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	var v := FontVariation.new()
	v.base_font = base
	if weight >= 700:
		v.variation_embolden = 0.35 if skin != Look.SAKURA else 0.2
	if slanted:
		v.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(0.2, 1.0), Vector2.ZERO)
	_fonts[key] = v
	return v


## Boite de l'habillage : fond, liseré, halo (ombre coloree sans decalage).
## `skew` / `radius` < 0 : ceux de l'habillage.
static func box(fill: Color, border: Color = Color(0, 0, 0, 0), border_width: int = 0,
		skew: float = -1.0, radius: int = -1, glow: Color = Color(0, 0, 0, 0), glow_size: int = 0,
		keep_glow: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(RADIUS if radius < 0 else radius)
	sb.skew = Vector2(SKEW if skew < 0.0 else skew, 0.0)
	sb.shadow_color = glow
	sb.shadow_size = glow_size
	# halo lumineux : neon seulement (2026-10-20, « sur Sakura et Playa,
	# quand c'est selectionne, pas vraiment d'effet neon ») ; ailleurs une
	# ombre portee sombre et courte, comme une tuile posee. `keep_glow` : le
	# halo dans tous les habillages (page Choix du convoi, neon partout)
	if skin != Look.NEON and glow_size > 0 and not keep_glow:
		sb.shadow_color = Color(0, 0, 0, 0.32 if glow.a > 0.0 else 0.0)
		sb.shadow_size = mini(glow_size, 6)
		sb.shadow_offset = Vector2(0, 3)
	sb.set_content_margin_all(12)
	sb.anti_aliasing = true
	return sb


## Case texturee (bois) de l'habillage, teintee par `tint` ; null sans texture.
## `grey` : le bois gris (tint_texture), pour une teinte franche.
static func tile_box(tint: Color = Color.WHITE, grey: bool = false) -> StyleBox:
	if tile_texture == null:
		return null
	# parallelogramme comme les boites a plat (SkewTileBox)
	var sb := SkewTileBox.new()
	sb.texture = tint_texture if grey and tint_texture != null else tile_texture
	sb.modulate_color = tint
	sb.skew = SKEW
	sb.edge = tile_edge
	sb.set_content_margin_all(12)
	return sb


static func label(text: String, size: int, color: Color = Color(-1, -1, -1), weight: int = 800, italic: bool = true,
		outline: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight, italic))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", TEXT if color.r < 0.0 else color)
	if outline > 0:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Bouton de choix : tuile (bois texture selon l'habillage), choisi a la
## couleur PINK (en bois : le bois gris teinte de cette couleur, la texture
## reste), liseré de focus.
static func style_choice(b: Button, font_size: int, selected: Color = Color(-1, -1, -1)) -> void:
	var sel := PINK if selected.r < 0.0 else selected
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", font(800))
	b.add_theme_font_size_override("font_size", font_size)
	var textured := tile_texture != null
	if textured:
		b.add_theme_stylebox_override("normal", tile_box())
		b.add_theme_stylebox_override("hover", tile_box(Color(1.14, 1.12, 1.08)))
		b.add_theme_stylebox_override("disabled", tile_box(Color(0.7, 0.7, 0.7, 0.55)))
	else:
		b.add_theme_stylebox_override("normal", box(TILE, Color(1, 1, 1, 0.07), 1))
		b.add_theme_stylebox_override("hover", box(TILE_HOVER, Color(CYAN, 0.45), 1))
		b.add_theme_stylebox_override("disabled", box(Color(TILE, 0.5), Color(1, 1, 1, 0.04), 1))
	if textured:
		b.add_theme_stylebox_override("pressed", tile_box(sel, true))
		b.add_theme_stylebox_override("hover_pressed", tile_box(sel.lightened(0.15), true))
	else:
		b.add_theme_stylebox_override("pressed", box(sel, Color(1, 1, 1, 0.25), 1, -1.0, -1, Color(sel, 0.45), 10))
		b.add_theme_stylebox_override("hover_pressed", box(sel.lightened(0.1), Color(1, 1, 1, 0.45), 1,
			-1.0, -1, Color(sel, 0.55), 12))
	b.add_theme_stylebox_override("focus", focus_box())
	for c: String in ["font_color", "font_hover_color", "font_focus_color"]:
		b.add_theme_color_override(c, BTN_TEXT)
	for c: String in ["font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, SEL_TEXT)
	b.add_theme_color_override("font_disabled_color", Color(BTN_TEXT, 0.5))


## Cadre de focus : liseré CYAN et halo, sans fond.
static func focus_box() -> StyleBoxFlat:
	var f := box(Color(0, 0, 0, 0), CYAN, 3, -1.0, -1, Color(CYAN, 0.5), 8)
	f.draw_center = false
	# cadre seul : pas d'ombre hors neon (elle salirait la tuile en dessous)
	if skin != Look.NEON:
		f.shadow_size = 0
	f.expand_margin_left = 3
	f.expand_margin_right = 3
	f.expand_margin_top = 3
	f.expand_margin_bottom = 3
	return f


## Bouton d'action principale (PRET) : or et texte nuit (neon), soleil
## (plage), laque noire a lettres d'or (Japon).
static func style_primary(b: Button, font_size: int) -> void:
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", font(900))
	b.add_theme_font_size_override("font_size", font_size)
	var bw := 2 if skin == Look.NEON else 3
	b.add_theme_stylebox_override("normal", box(PRIMARY_FILL, PRIMARY_BORDER, bw, -1.0, -1, Color(PRIMARY_BORDER, 0.35), 10))
	b.add_theme_stylebox_override("hover", box(PRIMARY_FILL.lightened(0.15), PRIMARY_BORDER.lightened(0.3), bw, -1.0, -1,
		Color(PRIMARY_BORDER, 0.6), 16))
	b.add_theme_stylebox_override("pressed", box(PRIMARY_FILL.darkened(0.12), PRIMARY_BORDER, bw, -1.0, -1,
		Color(PRIMARY_BORDER, 0.5), 8))
	b.add_theme_stylebox_override("focus", focus_box())
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, PRIMARY_TEXT)


## Petit bouton d'icone (son, parametres) : galet rond a l'habillage
## (2026-10-22, « ca blend pas ») - neon : nuit a tube cyan lumineux ; plage :
## lagon profond cercle de sable blanc, ombre posee ; Japon : laque noire
## cerclee d'or, lettres d'or. Survol : liseré de la couleur de focus.
static func style_icon(b: Button, font_size: int) -> void:
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", font(800, false))
	b.add_theme_font_size_override("font_size", font_size)
	var fill := Color(PANEL, 0.85)
	var edge := Color(CYAN, 0.55)
	var width := 2
	var text := TEXT
	match skin:
		Look.PLAYA:
			fill = Color(PANEL, 0.95)
			edge = Color(tile_edge, 0.95)
			width = 3
		Look.SAKURA:
			fill = Color(PRIMARY_FILL, 0.96)
			edge = PRIMARY_BORDER
			text = PRIMARY_TEXT
	var normal := box(fill, edge, width, 0.0, 28, Color(edge, 0.3), 8)
	var hover := box(fill.lightened(0.08), CYAN, width, 0.0, 28, Color(CYAN, 0.55), 14)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", normal)
	b.add_theme_stylebox_override("hover_pressed", hover)
	var f := box(Color(0, 0, 0, 0), CYAN, 3, 0.0, 28, Color(CYAN, 0.5), 8)
	f.draw_center = false
	if skin != Look.NEON:
		f.shadow_size = 0
	f.expand_margin_left = 3
	f.expand_margin_right = 3
	f.expand_margin_top = 3
	f.expand_margin_bottom = 3
	b.add_theme_stylebox_override("focus", f)
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, text)


## Couleur des pictos dessines sur un bouton d'icone (roue des parametres).
static func icon_color() -> Color:
	return PRIMARY_TEXT if skin == Look.SAKURA else TEXT


## Intitule de section : repere puis le texte en capitales - trait cyan
## incline (neon), galet corail (plage), sceau vermillon (Japon).
static func section(text: String, size: int = 18) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tick := Panel.new()
	var mark := CYAN
	var tick_skew := 0.35
	var tick_radius := 1
	var tick_w := 10
	match skin:
		Look.PLAYA:
			tick_skew = 0.0
			tick_radius = 8
			tick_w = 14
		Look.SAKURA:
			mark = PINK
			tick_skew = 0.0
			tick_radius = 1
			tick_w = size + 2
	tick.custom_minimum_size = Vector2(tick_w, size + 4)
	tick.add_theme_stylebox_override("panel", box(mark, Color(GOLD, 0.8) if skin == Look.SAKURA else Color(0, 0, 0, 0),
		1 if skin == Look.SAKURA else 0, tick_skew, tick_radius, Color(mark, 0.5), 4))
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
	g.set_color(0, Color(NIGHT, 0.95))
	g.set_color(1, Color(NIGHT.lightened(0.04), 0.82))
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
	var sb := box(Color(NIGHT, 0.9), Color(0, 0, 0, 0), 0, 0.0, 0)
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
static func card(border: Color = Color(-1, -1, -1), width: float = 0.0) -> PanelContainer:
	var edge := CYAN if border.r < 0.0 else border
	var p := PanelContainer.new()
	var sb := box(PANEL, Color(edge, 0.75), 2, 0.0, 6, Color(edge, 0.18), 18)
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


## Interrupteur (CheckButton : son, FPS...) : texte de l'habillage, pastille
## dessinee a ses couleurs (eteinte : tuile ; allumee : couleur du choix),
## survol en tuile claire, cadre de focus.
static func style_toggle(b: CheckButton, font_size: int) -> void:
	b.add_theme_font_override("font", font(600, false))
	b.add_theme_font_size_override("font_size", font_size)
	var empty := box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0.0)
	var hover := box(Color(TILE_HOVER, 0.6), Color(0, 0, 0, 0), 0, 0.0)
	for sb: StyleBoxFlat in [empty, hover]:
		sb.content_margin_left = 6
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
	for st: String in ["normal", "pressed", "disabled"]:
		b.add_theme_stylebox_override(st, empty)
	for st: String in ["hover", "hover_pressed"]:
		b.add_theme_stylebox_override(st, hover)
	b.add_theme_stylebox_override("focus", focus_box())
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, TEXT)
	b.add_theme_color_override("font_disabled_color", Color(TEXT, 0.45))
	for on: bool in [true, false]:
		var icon := switch_icon(on)
		var key := "checked" if on else "unchecked"
		for suffix: String in ["", "_mirrored", "_disabled", "_disabled_mirrored"]:
			b.add_theme_icon_override(key + suffix, icon)


## Pastille d'interrupteur 48 x 26 : piste arrondie, bouton rond ; allumee a
## la couleur du choix (PINK), bouton a droite. Mise en cache par couleurs.
static func switch_icon(on: bool) -> Texture2D:
	var track := PINK if on else Color(TILE.lightened(0.12), 1.0)
	var knob := Color.WHITE if on else DIM
	var key := "switch%s%s%s" % [on, track, knob]
	if _textures.has(key):
		return _textures[key]
	var w := 48
	var h := 26
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var r := h / 2.0
	var kx := (w - r) if on else r
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			# piste : capsule ; bouton : disque un peu plus petit
			var d := p.distance_to(Vector2(clampf(p.x, r, w - r), r))
			var c := Color(track, clampf(r - d, 0.0, 1.0))
			c = c.blend(Color(knob, clampf(r - 3.0 - p.distance_to(Vector2(kx, r)), 0.0, 1.0)))
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_textures[key] = tex
	return tex


## Liste deroulante (qualite graphique) : tuile de l'habillage, texte droit,
## liste deroulee sur un panneau de l'habillage.
static func style_option(o: OptionButton, font_size: int) -> void:
	o.add_theme_font_override("font", font(600, false))
	o.add_theme_font_size_override("font_size", font_size)
	o.add_theme_stylebox_override("normal", box(TILE, Color(1, 1, 1, 0.1), 1))
	o.add_theme_stylebox_override("hover", box(TILE_HOVER, Color(CYAN, 0.45), 1))
	o.add_theme_stylebox_override("pressed", box(TILE_HOVER, Color(CYAN, 0.6), 1))
	o.add_theme_stylebox_override("focus", focus_box())
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		o.add_theme_color_override(c, TEXT)
	var popup := o.get_popup()
	popup.add_theme_font_override("font", font(600, false))
	popup.add_theme_font_size_override("font_size", font_size)
	popup.add_theme_stylebox_override("panel", box(Color(PANEL, 0.98), Color(CYAN, 0.5), 1, 0.0))
	popup.add_theme_stylebox_override("hover", box(Color(PINK, 0.85), Color(0, 0, 0, 0), 0, 0.0))
	popup.add_theme_color_override("font_color", TEXT)
	popup.add_theme_color_override("font_hover_color", SEL_TEXT)


## Curseur (volume) : piste de tuile, partie remplie a la couleur du choix,
## bouton rond blanc cerne de cette couleur.
static func style_slider(s: HSlider) -> void:
	var track := box(Color(TILE.lightened(0.12), 1.0), Color(0, 0, 0, 0), 0, 0.0, 4)
	var fill := box(PINK, Color(0, 0, 0, 0), 0, 0.0, 4)
	for sb: StyleBoxFlat in [track, fill]:
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	s.add_theme_stylebox_override("focus", focus_box())
	var knob := knob_icon()
	s.add_theme_icon_override("grabber", knob)
	s.add_theme_icon_override("grabber_highlight", knob)


## Bouton rond 22 px du curseur.
static func knob_icon() -> Texture2D:
	var key := "knob%s" % PINK
	if _textures.has(key):
		return _textures[key]
	var n := 22
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var r := n / 2.0
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(r, r))
			var c := Color(PINK, clampf(r - d, 0.0, 1.0))
			c = c.blend(Color(Color.WHITE, clampf(r - 3.0 - d, 0.0, 1.0)))
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_textures[key] = tex
	return tex
