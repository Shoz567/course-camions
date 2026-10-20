class_name SkewTileBox
extends StyleBox

## Tuile de bois (Playa, Sakura) en parallelogramme (2026-10-20 : « que les
## boutons gardent la meme forme de parallelogramme dans tous les menus,
## comme dans Cyber City ») : StyleBoxTexture ne sait pas pencher. La texture
## (planches et cadre, UiKit.plank_texture) est posee sur le parallelogramme,
## teintee par `modulate_color` ; le bord est repasse d'un trait lisse a la
## couleur du cadre. Meme inclinaison que les StyleBoxFlat (haut decale a
## droite de skew * hauteur / 2, bas a gauche d'autant).

var texture: Texture2D
var modulate_color: Color = Color.WHITE
var skew: float = 0.0
## Couleur du trait de bord (le cadre de la texture), avant teinte.
var edge: Color = Color(0, 0, 0, 0)


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if texture == null:
		return
	var d := skew * rect.size.y * 0.5
	var pts := PackedVector2Array([rect.position + Vector2(d, 0.0), rect.position + Vector2(rect.size.x + d, 0.0),
		rect.end - Vector2(d, 0.0), rect.position + Vector2(-d, rect.size.y)])
	var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	RenderingServer.canvas_item_add_polygon(to_canvas_item, pts, PackedColorArray([modulate_color]), uvs,
		texture.get_rid())
	if edge.a > 0.0:
		var outline := pts.duplicate()
		outline.append(pts[0])
		RenderingServer.canvas_item_add_polyline(to_canvas_item, outline,
			PackedColorArray([Color(edge * modulate_color, edge.a)]), 1.5, true)
