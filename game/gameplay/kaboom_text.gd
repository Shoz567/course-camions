class_name KaboomText
extends Label3D

## « KABOOM ! » de bande dessinee au-dessus d'une explosion (baril,
## 2026-10-16 : « fait les Kaboom qd on les hit ») : jaillit (echelle 0 ->
## 1,35 -> 1), tremble, monte et s'efface, puis se libere. Toujours face a la
## camera, jamais cache par le decor. Purement visuel (rendu, _process).

const LIFE_S := 1.4
const POP_S := 0.22
const RISE_M := 3.5

var _t: float = 0.0
var _base: Vector3


## Pose le texte a `at` (monde) sous `parent`.
static func spawn(parent: Node, at: Vector3, label: String = "KABOOM !") -> KaboomText:
	var k := KaboomText.new()
	k.text = label
	var base := parent as Node3D
	k.position = base.global_transform.affine_inverse() * at if base != null and base.is_inside_tree() else at
	parent.add_child(k)
	return k


func _ready() -> void:
	name = "Kaboom"
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	fixed_size = false
	shaded = false
	double_sided = true
	render_priority = 10
	outline_render_priority = 9
	font_size = 200
	outline_size = 48
	pixel_size = 0.018
	modulate = Color(1.0, 0.86, 0.15)
	outline_modulate = Color(0.45, 0.05, 0.0)
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Impact", "Arial Black", "Arial"])
	f.font_weight = 900
	font = f
	_base = position
	scale = Vector3.ONE * 0.01
	rotation.z = deg_to_rad(randf_range(-10.0, 10.0))


func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFE_S:
		queue_free()
		return
	var s: float
	if _t < POP_S:
		s = lerpf(0.01, 1.35, _t / POP_S)
	else:
		s = lerpf(1.35, 1.0, minf((_t - POP_S) / 0.18, 1.0))
	scale = Vector3.ONE * s
	var u := _t / LIFE_S
	var jitter := Vector3(sin(_t * 61.0), sin(_t * 47.0 + 1.0), 0.0) * 0.12 * (1.0 - u)
	position = _base + Vector3.UP * RISE_M * u + jitter
	# rouge-orange en vieillissant, puis fondu sur le dernier tiers
	var fade := clampf((1.0 - u) * 3.0, 0.0, 1.0)
	modulate = Color(1.0, lerpf(0.86, 0.45, u), lerpf(0.15, 0.05, u), fade)
	outline_modulate.a = fade
