class_name ControllerDiagram
extends Control

## Schema de la manette PlayStation 5 DualSense (disposition Forza Horizon du
## jeu) dessine en vectoriel : aucun asset, aucun glyphe de police (les
## symboles Croix, Rond, Carre, Triangle sont traces). Coque bicolore blanche
## et noire, pave tactile, barre lumineuse, sticks symetriques.
##
## Chaque commande a une legende (touche + action) reliee par un trait au
## bouton, dont le contour s'allume. Legendes de gauche vers les commandes de
## gauche, de droite vers celles de droite, triees de haut en bas : les traits
## ne se croisent pas ; un trait qui passerait sur un autre bouton le
## contourne par des points de passage.
##
## Repere de conception W x H, mis a l'echelle et centre dans le controle.
## `callouts()` et `label_rect()` exposent la mise en page (tests : chaque
## commande presente, aucune legende ne chevauche une autre ni ne deborde).

const W := 1260.0
const H := 470.0
const LABEL_W := 330.0
## La manette est dessinee dans son propre repere, decale de CX.
const CX := 80.0
const ROW_TOP := 70.0
const ROW_STEP := 60.0

const SHELL := Color(0.93, 0.94, 0.96)
const SHELL_EDGE := Color(0.62, 0.65, 0.72)
const CORE := Color(0.07, 0.075, 0.09)
const KEY := Color(0.13, 0.14, 0.17)
## Charte arcade neon (UiKit) : traits et touches en cyan.
## Couleur des liserés : le focus de l'habillage (UiKit).
var ACCENT: Color:
	get:
		return UiKit.CYAN
const TEXT := Color(0.95, 0.95, 0.97)
const LIGHT_BAR := Color(0.25, 0.55, 1.0)

# commandes, dans le repere de la manette
const P_L2 := Vector2(420, 112)
const P_L1 := Vector2(420, 138)
const P_R2 := Vector2(680, 112)
const P_R1 := Vector2(680, 138)
const P_CREATE := Vector2(456, 166)
const P_OPTIONS := Vector2(644, 166)
const P_TOUCH := Vector2(550, 190)
const P_DPAD := Vector2(400, 246)
const P_LSTICK := Vector2(480, 290)
const P_RSTICK := Vector2(620, 290)
const P_TRIANGLE := Vector2(695, 182)
const P_CIRCLE := Vector2(730, 216)
const P_CROSS := Vector2(695, 250)
const P_SQUARE := Vector2(660, 216)
const P_PS := Vector2(550, 305)
const FACE_R := 16.0

## side : -1 legende a gauche, +1 a droite ; row : rang de haut en bas ;
## ring : rayon de l'anneau qui allume la commande ; via : pour chaque bouton
## vise, points de passage de son trait (repere de la manette) ; icon :
## symbole PlayStation trace dans le badge de la touche.
const CALLOUTS: Array[Dictionary] = [
	{"key": "L2", "text": "Freiner / marche arrière", "anchors": [P_L2], "side": -1, "row": 0, "ring": 11.0},
	{"key": "L1", "text": "Klaxon", "anchors": [P_L1], "side": -1, "row": 1, "ring": 10.0},
	{"key": "Create / pavé tactile", "text": "Reset sur la piste", "anchors": [P_CREATE, P_TOUCH],
		"side": -1, "row": 2, "ring": 13.0, "via": [[], [Vector2(455, 202)]]},
	{"key": "Stick gauche", "text": "Diriger", "anchors": [P_LSTICK], "side": -1, "row": 4, "ring": 30.0},
	{"key": "R2", "text": "Accélérer (progressif)", "anchors": [P_R2], "side": 1, "row": 0, "ring": 11.0},
	{"key": "R1", "text": "Frein à main / dérapage (drift)", "anchors": [P_R1], "side": 1, "row": 1, "ring": 10.0},
	{"key": "Options", "text": "Reset sur la piste", "anchors": [P_OPTIONS], "side": 1, "row": 2,
		"ring": 13.0, "via": [[Vector2(720, 150)]]},
	{"key": "Triangle", "text": "Largage de remorque (recharge 30 s)", "anchors": [P_TRIANGLE], "side": 1,
		"row": 3, "ring": 20.0, "icon": "triangle", "via": [[Vector2(770, 190)]]},
	{"key": "Carré", "text": "Nitro boost (recharge 6 s)", "anchors": [P_SQUARE], "side": 1, "row": 4,
		"ring": 20.0, "icon": "square", "via": [[Vector2(645, 265)]]},
	{"key": "Croix", "text": "Frein à main / dérapage (drift)", "anchors": [P_CROSS], "side": 1, "row": 5,
		"ring": 20.0, "icon": "cross"},
	{"key": "R3 / stick droit", "text": "Changer de vue (1re / 3e personne)", "anchors": [P_RSTICK],
		"side": 1, "row": 6, "ring": 30.0},
]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func callouts() -> Array[Dictionary]:
	return CALLOUTS


## Cadre d'une legende (touche + action sur deux lignes), repere de conception.
static func label_rect(c: Dictionary) -> Rect2:
	var y := ROW_TOP + ROW_STEP * int(c["row"]) - 24.0
	var x := 0.0 if int(c["side"]) < 0 else W - LABEL_W
	return Rect2(x, y, LABEL_W, 56.0)


## Point de depart du trait : bord interieur de la legende, a mi-hauteur.
static func label_anchor(c: Dictionary) -> Vector2:
	var r := label_rect(c)
	return Vector2(r.end.x + 8.0 if int(c["side"]) < 0 else r.position.x - 8.0, r.position.y + 28.0)


func _draw() -> void:
	var s := minf(size.x / W, size.y / H)
	var origin := (size - Vector2(W, H) * s) / 2.0
	var shift := Vector2(CX, 0.0)
	draw_set_transform(origin + shift * s, 0.0, Vector2(s, s))
	_draw_controller()
	draw_set_transform(origin, 0.0, Vector2(s, s))
	# traits par-dessus la manette (lisere sombre), jusqu'au bord de l'anneau
	for c in CALLOUTS:
		var vias: Array = c.get("via", [])
		var anchors: Array = c["anchors"]
		for k in anchors.size():
			var pts := PackedVector2Array([label_anchor(c)])
			pts.append(Vector2(pts[0].x + (40.0 if int(c["side"]) < 0 else -40.0), pts[0].y))
			if k < vias.size():
				for v: Vector2 in vias[k]:
					pts.append(v + shift)
			var target: Vector2 = anchors[k] + shift
			pts.append(target + (pts[pts.size() - 1] - target).normalized() * float(c["ring"]))
			draw_polyline(pts, Color(0, 0, 0, 0.85), 6.0, true)
			draw_polyline(pts, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.4), 4.0, true)
			draw_polyline(pts, ACCENT, 2.0, true)
	for c in CALLOUTS:
		for a: Vector2 in c["anchors"]:
			var center: Vector2 = a + shift
			var ring_r: float = float(c["ring"])
			draw_arc(center, ring_r + 3.0, 0.0, TAU, 32, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.25), 2.0, true)
			draw_arc(center, ring_r, 0.0, TAU, 32, ACCENT, 2.5, true)
		draw_circle(label_anchor(c), 5.0, ACCENT)
		draw_circle(label_anchor(c), 2.5, Color.WHITE)
	_draw_labels()


func _draw_controller() -> void:
	# gachettes L2 / R2 (au fond) et boutons L1 / R1
	for side: float in [-1.0, 1.0]:
		var cx := 550.0 + side * 130.0
		_rounded_rect(Rect2(cx - 52, 99, 104, 26), 12.0, CORE)
		_rounded_rect(Rect2(cx - 48, 102, 96, 20), 10.0, KEY.lightened(0.08))
		_rounded_rect(Rect2(cx - 55, 128, 110, 20), 9.0, SHELL_EDGE)
		_rounded_rect(Rect2(cx - 52, 130, 104, 16), 8.0, SHELL)
	_centered_text("L2", Vector2(440, 112), 13, TEXT)
	_centered_text("R2", Vector2(660, 112), 13, TEXT)
	_centered_text("L1", Vector2(440, 138), 12, CORE)
	_centered_text("R1", Vector2(660, 138), 12, CORE)

	# ombre, puis coque blanche (bloc superieur arrondi et deux poignees)
	_rounded_rect(Rect2(344, 150, 412, 170), 78.0, Color(0, 0, 0, 0.45))
	draw_circle(Vector2(408, 350), 96.0, Color(0, 0, 0, 0.4))
	draw_circle(Vector2(692, 350), 96.0, Color(0, 0, 0, 0.4))
	for pass_i in 2:
		var g := 3.0 if pass_i == 0 else 0.0
		var col := SHELL_EDGE if pass_i == 0 else SHELL
		_rounded_rect(Rect2(348 - g, 148 - g, 404 + g * 2, 166 + g * 2), 76.0 + g, col)
		draw_circle(Vector2(410, 345), 90.0 + g, col)
		draw_circle(Vector2(690, 345), 90.0 + g, col)
	# ombrage des poignees
	draw_circle(Vector2(404, 360), 64.0, SHELL.darkened(0.07))
	draw_circle(Vector2(696, 360), 64.0, SHELL.darkened(0.07))
	# piece centrale noire (sticks, bouton PS)
	_rounded_rect(Rect2(440, 222, 220, 112), 46.0, CORE)
	# pave tactile, et barre lumineuse sur ses deux bords
	_rounded_rect(Rect2(474, 150, 152, 78), 16.0, SHELL_EDGE)
	_rounded_rect(Rect2(477, 150, 146, 74), 14.0, SHELL.darkened(0.03))
	for side: float in [-1.0, 1.0]:
		var x := 550.0 + side * 79.0
		draw_line(Vector2(x, 156), Vector2(x - side * 4.0, 222), Color(LIGHT_BAR.r, LIGHT_BAR.g, LIGHT_BAR.b, 0.35), 8.0)
		draw_line(Vector2(x, 156), Vector2(x - side * 4.0, 222), LIGHT_BAR.lightened(0.2), 3.0)
	# Create et Options (petites pilules de part et d'autre du pave)
	for p: Vector2 in [P_CREATE, P_OPTIONS]:
		_rounded_rect(Rect2(p.x - 5, p.y - 11, 10, 22), 5.0, KEY)
	# croix directionnelle PlayStation : quatre fleches separees
	_draw_dpad(P_DPAD)
	# sticks symetriques
	_draw_stick(P_LSTICK)
	_draw_stick(P_RSTICK)
	# bouton PS et micro
	draw_circle(P_PS, 11.0, KEY.lightened(0.1))
	_centered_text("PS", P_PS, 10, TEXT)
	_rounded_rect(Rect2(P_PS.x - 9, P_PS.y + 16, 18, 5), 2.0, Color(1.0, 0.45, 0.2, 0.9))
	# boutons de forme
	for p: Vector2 in [P_TRIANGLE, P_CIRCLE, P_CROSS, P_SQUARE]:
		draw_circle(p, FACE_R + 2.5, SHELL_EDGE)
		draw_circle(p, FACE_R, KEY)
	draw_ps_symbol(self, "triangle", P_TRIANGLE, 8.0)
	draw_ps_symbol(self, "circle", P_CIRCLE, 8.0)
	draw_ps_symbol(self, "cross", P_CROSS, 8.0)
	draw_ps_symbol(self, "square", P_SQUARE, 8.0)


## Symbole PlayStation trace (couleurs d'origine), centre en `p`, rayon `r`.
static func draw_ps_symbol(ci: CanvasItem, kind: String, p: Vector2, r: float) -> void:
	match kind:
		"triangle":
			var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r * 0.95, r * 0.7),
				p + Vector2(-r * 0.95, r * 0.7), p + Vector2(0, -r)])
			ci.draw_polyline(pts, Color(0.25, 0.85, 0.7), 2.5, true)
		"circle":
			ci.draw_arc(p, r * 0.85, 0.0, TAU, 24, Color(1.0, 0.35, 0.4), 2.5, true)
		"cross":
			var c := Color(0.45, 0.65, 1.0)
			ci.draw_line(p + Vector2(-r, -r) * 0.75, p + Vector2(r, r) * 0.75, c, 2.5, true)
			ci.draw_line(p + Vector2(-r, r) * 0.75, p + Vector2(r, -r) * 0.75, c, 2.5, true)
		"square":
			ci.draw_rect(Rect2(p - Vector2(r, r) * 0.72, Vector2(r, r) * 1.44), Color(1.0, 0.45, 0.8), false, 2.5)


func _draw_stick(p: Vector2) -> void:
	draw_circle(p, 30.0, Color(0.02, 0.02, 0.03))
	draw_circle(p, 26.0, KEY.lightened(0.05))
	for ang in 12:
		var d := Vector2.from_angle(ang * TAU / 12.0)
		draw_line(p + d * 20.0, p + d * 25.0, KEY.lightened(0.2), 2.0)
	draw_circle(p, 17.0, KEY)


func _draw_dpad(p: Vector2) -> void:
	for k in 4:
		var d := Vector2.from_angle(k * PI / 2.0)
		var n := Vector2(-d.y, d.x)
		# fleche : pointe vers le centre, large vers l'exterieur
		var tip := p + d * 8.0
		var far := p + d * 28.0
		var poly := PackedVector2Array([tip - n * 2.0, tip + n * 2.0, p + d * 16.0 + n * 9.0, far + n * 9.0,
			far - n * 9.0, p + d * 16.0 - n * 9.0])
		draw_colored_polygon(poly, SHELL_EDGE)
		var inner := PackedVector2Array()
		for q in poly:
			inner.append(p + (q - p) * 0.9 + d * 1.0)
		draw_colored_polygon(inner, SHELL.darkened(0.12))


func _draw_labels() -> void:
	var font := UiKit.font(800, false)
	for c in CALLOUTS:
		var r := label_rect(c)
		var is_left := int(c["side"]) < 0
		var align := HORIZONTAL_ALIGNMENT_RIGHT if is_left else HORIZONTAL_ALIGNMENT_LEFT
		var key_str: String = c["key"]
		var icon: String = c.get("icon", "")
		var icon_w := 26.0 if icon != "" else 0.0
		var key_w := font.get_string_size(key_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 20.0 + icon_w
		var badge_x := (r.end.x - key_w) if is_left else r.position.x
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.11, 0.16, 0.85)
		sb.border_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.6)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(6)
		draw_style_box(sb, Rect2(badge_x, r.position.y + 2.0, key_w, 24.0))
		if icon != "":
			draw_ps_symbol(self, icon, Vector2(badge_x + 17.0, r.position.y + 14.0), 7.0)
		draw_string(font, Vector2(badge_x + 10.0 + icon_w, r.position.y + 20.0), key_str,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ACCENT)
		draw_string(font, Vector2(r.position.x, r.position.y + 48.0), c["text"], align, r.size.x, 18, TEXT)


func _centered_text(text: String, center: Vector2, font_size: int, color: Color) -> void:
	var font := get_theme_default_font()
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, center + Vector2(-w / 2.0, font_size * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		font_size, color)


func _rounded_rect(r: Rect2, radius: float, color: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(roundi(radius))
	sb.anti_aliasing = true
	draw_style_box(sb, r)
