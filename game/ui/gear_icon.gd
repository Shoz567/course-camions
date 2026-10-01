class_name GearIcon
extends Control

## Roue crantee dessinee (aucun asset, aucune police a pictogrammes) : dents
## trapezoidales et couronne evidee. Tourne lentement, plus vite quand le
## bouton qui la porte est survole ou selectionne (`fast`).

@export var color: Color = Color(0.93, 0.93, 0.93)
@export_range(5, 16) var teeth: int = 8
@export var spin_speed: float = 0.6
@export var fast_spin_speed: float = 3.0

var fast: bool = false
var _angle: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_angle = fmod(_angle + (fast_spin_speed if fast else spin_speed) * delta, TAU)
	queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	var r_out := minf(size.x, size.y) * 0.46
	var r_in := r_out * 0.74
	var r_hole := r_out * 0.32
	var step := TAU / teeth
	for j in teeth:
		var a := _angle + j * step
		var base := step * 0.28
		var top := step * 0.18
		draw_colored_polygon(PackedVector2Array([
			c + Vector2.from_angle(a - base) * r_in * 0.95,
			c + Vector2.from_angle(a - top) * r_out,
			c + Vector2.from_angle(a + top) * r_out,
			c + Vector2.from_angle(a + base) * r_in * 0.95,
		]), color)
	# couronne : un arc epais laisse le moyeu transparent
	draw_arc(c, (r_in + r_hole) / 2.0, 0.0, TAU, 48, color, r_in - r_hole, true)
