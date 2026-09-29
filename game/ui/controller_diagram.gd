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
			draw_polyline(pts, Color(0, 0, 0, 0.85), 6.0, true)
			draw_polyline(pts, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.4), 4.0, true)
			draw_polyline(pts, ACCENT, 2.0, true)
	# contour allume des commandes legendees avec viseur radar
	for c in CALLOUTS:
		for a: Vector2 in c["anchors"]:
			var center: Vector2 = a + shift
			var ring_r: float = float(c["ring"])
			# halo exterieur
			draw_arc(center, ring_r + 3.0, 0.0, TAU, 32, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.25), 2.0, true)
			# anneau principal
			draw_arc(center, ring_r, 0.0, TAU, 32, ACCENT, 2.5, true)
			# point central
			draw_circle(center, 2.5, ACCENT)
			# micro-croisillons
			for ang: float in [0.0, PI * 0.5, PI, PI * 1.5]:
				var dir := Vector2(cos(ang), sin(ang))
				draw_line(center + dir * (ring_r - 2.0), center + dir * (ring_r + 4.0), ACCENT, 2.0)
		draw_circle(label_anchor(c), 5.0, ACCENT)
		draw_circle(label_anchor(c), 2.5, Color.WHITE)
	_draw_labels()


func _draw_controller() -> void:
	# ombre portee sous la manette
	_rounded_rect(Rect2(346, 146, 408, 198), 74.0, Color(0.0, 0.0, 0.0, 0.45))
	draw_circle(Vector2(405, 355), 98.0, Color(0.0, 0.0, 0.0, 0.4))
	draw_circle(Vector2(695, 355), 98.0, Color(0.0, 0.0, 0.0, 0.4))

	# gachettes ZL et ZR (arriere-plan haut)
	_rounded_rect(Rect2(358, 96, 126, 26), 12.0, Color(0.12, 0.14, 0.18))
	_rounded_rect(Rect2(616, 96, 126, 26), 12.0, Color(0.12, 0.14, 0.18))
	_rounded_rect(Rect2(362, 100, 118, 20), 10.0, BUTTON.darkened(0.35))
	_rounded_rect(Rect2(620, 100, 118, 20), 10.0, BUTTON.darkened(0.35))
	_centered_text("ZL", Vector2(440, 111), 14, Color(0.85, 0.88, 0.95))
	_centered_text("ZR", Vector2(660, 111), 14, Color(0.85, 0.88, 0.95))

	# boutons de tranche L et R
	_rounded_rect(Rect2(364, 125, 122, 24), 9.0, BODY_EDGE.darkened(0.4))
	_rounded_rect(Rect2(614, 125, 122, 24), 9.0, BODY_EDGE.darkened(0.4))
	_rounded_rect(Rect2(368, 128, 116, 20), 8.0, BUTTON.darkened(0.1))
	_rounded_rect(Rect2(616, 128, 116, 20), 8.0, BUTTON.darkened(0.1))
	_centered_text("L", Vector2(445, 139), 14, TEXT)
	_centered_text("R", Vector2(655, 139), 14, TEXT)

	# chassis principal (corps ergonomique)
	# contour chanfreine
	_rounded_rect(Rect2(346, 146, 408, 198), 72.0, Color(0.28, 0.32, 0.40))
	draw_circle(Vector2(405, 350), 97.0, Color(0.28, 0.32, 0.40))
	draw_circle(Vector2(695, 350), 97.0, Color(0.28, 0.32, 0.40))
	# coque matte principale
	_rounded_rect(Rect2(350, 150, 400, 190), 70.0, Color(0.13, 0.15, 0.20))
	draw_circle(Vector2(405, 350), 94.0, Color(0.13, 0.15, 0.20))
	draw_circle(Vector2(695, 350), 94.0, Color(0.13, 0.15, 0.20))

	# revetement antiderapant sur les poignees (panneaux de grip)
	draw_circle(Vector2(395, 360), 72.0, Color(0.09, 0.10, 0.14))
	draw_circle(Vector2(705, 360), 72.0, Color(0.09, 0.10, 0.14))
	# micro-picots de prehension
	for gx: float in [-1.0, 1.0]:
		var hx: float = 550.0 + gx * 155.0
		for r_row: int in 4:
			for c_col: int in 3:
				var dot_p := Vector2(hx + c_col * 9.0 * gx, 335.0 + r_row * 12.0)
				draw_circle(dot_p, 1.5, Color(0.18, 0.21, 0.28))

	# plaque centrale biseautee
	_rounded_rect(Rect2(450, 160, 200, 160), 30.0, Color(0.11, 0.12, 0.16))

	# sticks analogiques Switch Pro (gauche et droite)
	_draw_stick(P_LSTICK)
	_draw_stick(P_RSTICK)

	# croix directionnelle (D-Pad)
	_draw_dpad(P_DPAD)

	# boutons de fonction centraux : Minus, Plus, Capture, Home
	# Minus (-)
	draw_circle(P_MINUS, 12.0, BUTTON.darkened(0.2))
	draw_rect(Rect2(P_MINUS.x - 7, P_MINUS.y - 2, 14, 4), TEXT)
	# Plus (+)
	draw_circle(P_PLUS, 12.0, BUTTON.darkened(0.2))
	draw_rect(Rect2(P_PLUS.x - 7, P_PLUS.y - 2, 14, 4), TEXT)
	draw_rect(Rect2(P_PLUS.x - 2, P_PLUS.y - 7, 4, 14), TEXT)
	# Capture (carre a gauche)
	draw_rect(Rect2(Vector2(505, 230) - Vector2(7, 7), Vector2(14, 14)), BUTTON.darkened(0.3))
	draw_circle(Vector2(505, 230), 3.5, BUTTON)
	# Home (cercle avec anneau cyan a droite)
	draw_circle(Vector2(595, 230), 9.0, BUTTON.darkened(0.3))
	draw_arc(Vector2(595, 230), 6.5, 0.0, TAU, 16, Color(0.1, 0.8, 1.0, 0.7), 1.5)

	# 4 voyants LED joueurs (centre bas)
	for i: int in 4:
		var led_pos := Vector2(532.0 + i * 12.0, 315.0)
		draw_rect(Rect2(led_pos.x - 2.5, led_pos.y - 2.5, 5, 5), Color(0.08, 0.85, 0.45, 0.9 if i == 0 else 0.2))

	# boutons de face (A, B, X, Y)
	# puits sous les boutons
	for p: Vector2 in [P_X, P_A, P_B, P_Y]:
		draw_circle(p, FACE_R + 3.0, Color(0.08, 0.09, 0.12))
	# boutons avec reflets et couleurs facon Super Nintendo / Switch
	var faces: Array = [
		[P_X, "X", Color(0.22, 0.48, 0.98)],
		[P_A, "A", Color(0.95, 0.22, 0.22)],
		[P_B, "B", Color(0.96, 0.80, 0.12)],
		[P_Y, "Y", Color(0.18, 0.78, 0.36)]
	]
	for f: Array in faces:
		var pos: Vector2 = f[0]
		var col: Color = f[2]
		# bouton
		draw_circle(pos, FACE_R, col.darkened(0.15))
		draw_circle(pos - Vector2(1, 1), FACE_R - 2.0, col)
		draw_circle(pos - Vector2(3, 3), FACE_R - 7.0, col.lightened(0.25))
		_centered_text(f[1], pos + Vector2(0, 1), 16, Color.WHITE)


func _draw_stick(p: Vector2) -> void:
	# puits du stick
	draw_circle(p, 38.0, Color(0.06, 0.07, 0.10))
	draw_circle(p, 36.0, Color(0.20, 0.23, 0.29))
	# bague caoutchouc externe avec 8 crans de grip
	draw_circle(p, 32.0, Color(0.14, 0.16, 0.20))
	for ang: int in 8:
		var rad := ang * TAU / 8.0
		var notch_p := p + Vector2(cos(rad), sin(rad)) * 30.0
		draw_line(notch_p - Vector2(cos(rad), sin(rad)) * 3.0, notch_p, Color(0.3, 0.35, 0.42), 2.0)
	# creux ergonomique concave
	draw_circle(p, 24.0, Color(0.18, 0.21, 0.27))
	draw_circle(p, 16.0, Color(0.13, 0.15, 0.19))
	# micro-croix de centrage
	draw_line(p - Vector2(6, 0), p + Vector2(6, 0), Color(0.28, 0.32, 0.40), 2.0)
	draw_line(p - Vector2(0, 6), p + Vector2(0, 6), Color(0.28, 0.32, 0.40), 2.0)


func _draw_dpad(p: Vector2) -> void:
	# puits de la croix
	draw_rect(Rect2(p.x - 12, p.y - 31, 24, 62), Color(0.06, 0.07, 0.10))
	draw_rect(Rect2(p.x - 31, p.y - 12, 62, 24), Color(0.06, 0.07, 0.10))
	# corps de la croix
	draw_rect(Rect2(p.x - 10, p.y - 29, 20, 58), BUTTON)
	draw_rect(Rect2(p.x - 29, p.y - 10, 58, 20), BUTTON)
	# depression centrale
	draw_circle(p, 7.0, BUTTON.darkened(0.25))
	# fleches de direction blanches
	_centered_text("▲", Vector2(p.x, p.y - 19), 11, TEXT)
	_centered_text("▼", Vector2(p.x, p.y + 19), 11, TEXT)
	_centered_text("◄", Vector2(p.x - 19, p.y), 11, TEXT)
	_centered_text("►", Vector2(p.x + 19, p.y), 11, TEXT)


func _draw_labels() -> void:
	var font := get_theme_default_font()
	for c in CALLOUTS:
		var r := label_rect(c)
		var is_left := int(c["side"]) < 0
		var align := HORIZONTAL_ALIGNMENT_RIGHT if is_left else HORIZONTAL_ALIGNMENT_LEFT
		# fond translucide et liseret neon pour la touche
		var key_str: String = c["key"]
		var key_w := font.get_string_size(key_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 20.0
		var badge_x := (r.end.x - key_w) if is_left else r.position.x
		var badge_r := Rect2(badge_x, r.position.y + 2.0, key_w, 24.0)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.11, 0.16, 0.85)
		sb.border_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.6)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(6)
		draw_style_box(sb, badge_r)
		draw_string(font, Vector2(badge_x + 10.0, r.position.y + 20.0), key_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ACCENT)
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
