class_name PadGlyph
extends Control

## Picto d'une commande, dessine (aucune image) : boutons PlayStation (croix,
## rond, carre, triangle, gachettes, Options), croix directionnelle (fleche
## gauche / droite / haut / bas mise en avant) et touche de clavier
## (« key:Entrée »). Pour les aides des menus et la page de selection.

## cross, circle, square, triangle, l1, r1, options, dpad, dpad_left,
## dpad_right, dpad_lr, dpad_ud, key:<texte>.
@export var kind: String = "cross":
	set(value):
		kind = value
		queue_redraw()
@export var tint: Color = Color(0.97, 0.97, 1.0)

const SHAPE_COLORS := {
	"cross": Color(0.55, 0.7, 1.0), "circle": Color(1.0, 0.45, 0.5),
	"square": Color(1.0, 0.55, 0.85), "triangle": Color(0.35, 0.95, 0.8),
}


## Largeur du picto pour une hauteur donnee (touches et gachettes plus larges).
static func width_for(k: String, height: float) -> float:
	if k.begins_with("key:"):
		return maxf(height, 14.0 + k.length() * height * 0.32)
	if k in ["l1", "r1", "options"]:
		return height * 1.6
	return height


func _draw() -> void:
	var s := size
	var c := s / 2.0
	var r := minf(s.x, s.y) / 2.0 - 1.0
	var line := maxf(2.0, r * 0.16)
	if kind.begins_with("key:"):
		_key(kind.substr(4), s)
		return
	match kind:
		"cross", "circle", "square", "triangle":
			draw_circle(c, r, Color(0.08, 0.09, 0.16, 0.95))
			draw_arc(c, r, 0.0, TAU, 32, Color(tint, 0.35), 1.5, true)
			var col: Color = SHAPE_COLORS[kind]
			var k := r * 0.42
			match kind:
				"cross":
					draw_line(c + Vector2(-k, -k), c + Vector2(k, k), col, line, true)
					draw_line(c + Vector2(-k, k), c + Vector2(k, -k), col, line, true)
				"circle":
					draw_arc(c, k, 0.0, TAU, 24, col, line, true)
				"square":
					draw_rect(Rect2(c - Vector2(k, k) * 0.9, Vector2(k, k) * 1.8), col, false, line)
				"triangle":
					var p := PackedVector2Array([c + Vector2(0, -k), c + Vector2(k * 0.95, k * 0.7),
						c + Vector2(-k * 0.95, k * 0.7), c + Vector2(0, -k)])
					draw_polyline(p, col, line, true)
		"l1", "r1", "options":
			var rect := Rect2(Vector2(1, 1), s - Vector2(2, 2))
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.08, 0.09, 0.16, 0.95)
			sb.border_color = Color(tint, 0.45)
			sb.set_border_width_all(1)
			sb.set_corner_radius_all(int(s.y / 2.0) if kind == "options" else 5)
			draw_style_box(sb, rect)
			_text({"l1": "L1", "r1": "R1", "options": "OPT"}[kind], rect, s.y * 0.48)
		_:
			_dpad(c, r)


func _dpad(c: Vector2, r: float) -> void:
	var arm := r * 0.36
	var dim := Color(tint, 0.3)
	var hot := Color(0.16, 0.9, 1.0)
	var dirs := {"dpad_left": [Vector2.LEFT], "dpad_right": [Vector2.RIGHT],
		"dpad_lr": [Vector2.LEFT, Vector2.RIGHT], "dpad_ud": [Vector2.UP, Vector2.DOWN]}
	var lit: Array = dirs.get(kind, [])
	for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var center := c + d * (r - arm)
		var rect := Rect2(center - Vector2(arm, arm), Vector2(arm, arm) * 2.0)
		var on := lit.has(d)
		draw_rect(rect, hot if on else dim, true)
		if on:
			# petite fleche sombre dans la branche allumee
			var tip := center + d * arm * 0.55
			var side := Vector2(-d.y, d.x) * arm * 0.5
			var back := center - d * arm * 0.35
			draw_colored_polygon(PackedVector2Array([tip, back + side, back - side]), Color(0.05, 0.06, 0.12))
	draw_rect(Rect2(c - Vector2(arm, arm), Vector2(arm, arm) * 2.0), dim, true)


func _key(text: String, s: Vector2) -> void:
	var rect := Rect2(Vector2(1, 1), s - Vector2(2, 3))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.13, 0.22, 0.95)
	sb.border_color = Color(tint, 0.5)
	sb.set_border_width_all(1)
	sb.border_width_bottom = 3
	sb.set_corner_radius_all(4)
	draw_style_box(sb, rect)
	_text(text, rect, s.y * 0.48)


func _text(text: String, rect: Rect2, font_size: float) -> void:
	var f := UiKit.font(800, false)
	var fs := int(font_size)
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2(rect.position.x + (rect.size.x - w) / 2.0,
		rect.position.y + (rect.size.y + f.get_ascent(fs) - f.get_descent(fs)) / 2.0)
	draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tint)
