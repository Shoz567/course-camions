class_name ControllerDiagram
extends Control

## Schema de la manette (disposition Switch, profil MK8 du jeu) dessine en
## vectoriel : aucun asset. Chaque commande a une legende (touche + action)
## reliee par un trait au bouton, dont le contour s'allume. Les legendes de
## gauche visent les commandes de gauche, celles de droite les commandes de
## droite, triees de haut en bas : les traits ne se croisent pas ; un trait
## qui passerait sur un autre bouton le contourne par un point de passage.
##
## Tout est dessine dans un repere de conception W x H, mis a l'echelle et
## centre dans la taille du controle. `callouts()` et `label_rect()` exposent
## la mise en page (tests : chaque commande presente, aucune legende ne
## chevauche une autre ni ne deborde).

const W := 1260.0
const H := 470.0
const LABEL_W := 330.0
## La manette est dessinee dans son propre repere, decale de CX : les poignees
## restent a ~50 unites des legendes.
const CX := 80.0
const ROW_TOP := 70.0
const ROW_STEP := 80.0

const BODY := Color(0.17, 0.19, 0.24)
const BODY_EDGE := Color(0.55, 0.6, 0.7)
const BUTTON := Color(0.28, 0.31, 0.38)
const ACCENT := Color(1.0, 0.62, 0.12)
const TEXT := Color(0.95, 0.95, 0.97)

# boutons, dans le repere de conception
const P_ZL := Vector2(400, 111)
const P_L := Vector2(405, 139)
const P_ZR := Vector2(700, 111)
const P_R := Vector2(695, 139)
const P_MINUS := Vector2(505, 180)
const P_PLUS := Vector2(595, 180)
const P_LSTICK := Vector2(430, 218)
const P_DPAD := Vector2(490, 292)
const P_RSTICK := Vector2(612, 292)
const P_X := Vector2(675, 182)
const P_A := Vector2(710, 218)
const P_B := Vector2(675, 254)
const P_Y := Vector2(640, 218)
const FACE_R := 17.0

## side : -1 legende a gauche, +1 a droite ; row : rang de haut en bas ;
## ring : rayon de l'anneau qui allume la commande ; via : pour chaque bouton
## vise, points de passage de son trait (repere de la manette).
const CALLOUTS: Array[Dictionary] = [
	{"key": "ZL", "text": "Drop de cargo (recharge 30 s)", "anchors": [P_ZL], "side": -1, "row": 0, "ring": 11.0},
	{"key": "L", "text": "Nitro boost (recharge 4 s)", "anchors": [P_L], "side": -1, "row": 1, "ring": 10.0},
	{"key": "-", "text": "Reset sur la piste", "anchors": [P_MINUS], "side": -1, "row": 2, "ring": 16.0,
		"via": [[Vector2(390, 168)]]},
	{"key": "Stick gauche", "text": "Diriger", "anchors": [P_LSTICK], "side": -1, "row": 3, "ring": 38.0},
	{"key": "Croix", "text": "Klaxon", "anchors": [P_DPAD], "side": -1, "row": 4, "ring": 33.0},
	{"key": "R / ZR", "text": "Dérapage (drift)", "anchors": [P_ZR, P_R], "side": 1, "row": 0, "ring": 11.0},
	{"key": "+", "text": "Commencer / rejouer", "anchors": [P_PLUS], "side": 1, "row": 1, "ring": 16.0,
		"via": [[Vector2(622, 150)]]},
	{"key": "X", "text": "Changer de vue (1re / 3e personne)", "anchors": [P_X], "side": 1, "row": 2, "ring": 21.0,
		"via": [[Vector2(722, 168)]]},
	{"key": "A / Y", "text": "Accélérer", "anchors": [P_A, P_Y], "side": 1, "row": 3, "ring": 21.0,
		"via": [[], [Vector2(672, 222)]]},
	{"key": "B", "text": "Freiner / marche arrière", "anchors": [P_B], "side": 1, "row": 4, "ring": 21.0},
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
	draw_set_transform(origin, 0.0, Vector2(s, s))
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
			draw_polyline(pts, Color(0, 0, 0, 0.75), 5.0, true)
			draw_polyline(pts, ACCENT, 2.0, true)
	# contour allume des commandes legendees
	for c in CALLOUTS:
		for a: Vector2 in c["anchors"]:
			draw_arc(a + shift, float(c["ring"]), 0.0, TAU, 32, ACCENT, 3.0, true)
		draw_circle(label_anchor(c), 4.0, ACCENT)
	_draw_labels()


func _draw_controller() -> void:
	# ombre, contour, puis corps : bloc central arrondi et deux poignees
	for pass_i in 2:
		var grow := 5.0 if pass_i == 0 else 0.0
		var col := BODY_EDGE if pass_i == 0 else BODY
		_rounded_rect(Rect2(350 - grow, 150 - grow, 400 + grow * 2, 190 + grow * 2), 70.0 + grow, col)
		draw_circle(Vector2(405, 350), 95.0 + grow, col)
		draw_circle(Vector2(695, 350), 95.0 + grow, col)
	# gachettes et boutons de tranche
	_rounded_rect(Rect2(362, 100, 120, 22), 10.0, BUTTON.darkened(0.2))
	_rounded_rect(Rect2(618, 100, 120, 22), 10.0, BUTTON.darkened(0.2))
	_rounded_rect(Rect2(368, 129, 118, 20), 8.0, BUTTON)
	_rounded_rect(Rect2(614, 129, 118, 20), 8.0, BUTTON)
	_centered_text("ZL", Vector2(440, 111), 14, TEXT)
	_centered_text("ZR", Vector2(660, 111), 14, TEXT)
	_centered_text("L", Vector2(445, 139), 14, TEXT)
	_centered_text("R", Vector2(655, 139), 14, TEXT)
	# sticks
	for p: Vector2 in [P_LSTICK, P_RSTICK]:
		draw_circle(p, 34.0, BUTTON.darkened(0.3))
		draw_circle(p, 24.0, BUTTON)
	# croix directionnelle
	draw_rect(Rect2(P_DPAD.x - 9, P_DPAD.y - 28, 18, 56), BUTTON)
	draw_rect(Rect2(P_DPAD.x - 28, P_DPAD.y - 9, 56, 18), BUTTON)
	# - et +
	draw_rect(Rect2(P_MINUS.x - 10, P_MINUS.y - 3, 20, 6), TEXT)
	draw_rect(Rect2(P_PLUS.x - 10, P_PLUS.y - 3, 20, 6), TEXT)
	draw_rect(Rect2(P_PLUS.x - 3, P_PLUS.y - 10, 6, 20), TEXT)
	# boutons de face (couleurs facon Super Nintendo)
	var faces := [[P_X, "X", Color(0.25, 0.45, 0.95)], [P_A, "A", Color(0.9, 0.2, 0.2)],
		[P_B, "B", Color(0.95, 0.8, 0.15)], [P_Y, "Y", Color(0.2, 0.7, 0.3)]]
	for f: Array in faces:
		draw_circle(f[0], FACE_R, f[2])
		_centered_text(f[1], f[0], 16, Color.WHITE)


func _draw_labels() -> void:
	var font := get_theme_default_font()
	for c in CALLOUTS:
		var r := label_rect(c)
		var align := HORIZONTAL_ALIGNMENT_RIGHT if int(c["side"]) < 0 else HORIZONTAL_ALIGNMENT_LEFT
		draw_string(font, Vector2(r.position.x, r.position.y + 22.0), c["key"], align, r.size.x, 22, ACCENT)
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
