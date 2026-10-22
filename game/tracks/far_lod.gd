class_name FarLod
extends RefCounted

## Arbres pres en 3D, loin en 2D (2026-10-22 : « pour les assets de loin, fait
## du trick en 2D tourne, sans que ca fasse tache ») :
##   - pres de la camera : les MultiMesh 3D (tronc, couronne...), coupes en
##     cases de CELL m posees a leur centre ; une case n'est plus dessinee
##     au-dela de NEAR_END m (sans fondu : le sprite est deja la) ;
##   - loin : un seul MultiMesh de sprites (2 triangles par arbre) qui
##     tournent autour de la verticale pour faire face a la camera
##     (impostor.gdshader). Le sprite est une PHOTO du modele 3D
##     (dev/bake_impostors.gd, tracks/impostors/*.png), meme silhouette, memes
##     couleurs. Il apparait par arbre au-dela de FAR_BEGIN m, en fondu
##     trame ; plus pres, son quad est ecrase en un point (aucun pixel a
##     calculer). Un arbre a moins de NEAR_END - demi-diagonale d'une case (~165
##     m) a toujours sa case 3D : FAR_BEGIN + FAR_FADE reste en deca, jamais
##     de trou ; entre les deux, l'arbre 3D cache le sprite.
## Un palmier 3D de Playa pese ~900 triangles, un sprite 2 : au loin, le
## decor ne coute presque plus rien, et les ombres (a 220 m) n'y perdent rien.

const CELL := 120.0
const NEAR_END := 250.0
const FAR_BEGIN := 145.0
const FAR_FADE := 25.0

## Sprites : photo carree de `size` m de cote (taille de reference), base du
## modele a `bottom` m sous le bas de l'image ; modele de reference de
## hauteur `ref` (le tronc d'un palmier de 12 m, d'un cerisier de 5,5 m).
const KINDS := {
	"palm": {"path": "res://tracks/impostors/palm.png", "size": 20.0, "bottom": 0.5, "ref": 12.0},
	"cherry": {"path": "res://tracks/impostors/cherry.png", "size": 15.0, "bottom": 0.5, "ref": 5.5},
}

static var _materials: Dictionary = {}


## Ajoute sous `root` les couches 3D `layers` ([{name, mesh, xfs, colors,
## shadows}], memes arbres dans le meme ordre) coupees en cases, et, si
## `kind` n'est pas vide, leurs sprites lointains : un par arbre, pose en
## `bases[k]` (pied de l'arbre), a l'echelle `scales[k]` (hauteur / ref),
## teinte `tints[k]` (vide : blanc).
static func add(root: Node3D, base_name: String, layers: Array, kind: String = "", bases: PackedVector3Array = PackedVector3Array(),
		scales: PackedFloat32Array = PackedFloat32Array(), tints: PackedColorArray = PackedColorArray()) -> void:
	for layer: Dictionary in layers:
		_add_chunks(root, String(layer["name"]), layer["mesh"] as Mesh, layer["xfs"], layer.get("colors", PackedColorArray()),
			bool(layer.get("shadows", true)))
	if kind != "" and not bases.is_empty():
		root.add_child(sprites(base_name + "Far", kind, bases, scales, tints))


## Un MultiMesh par case de CELL m, pose au centre de sa case (la portee de
## vue se mesure depuis la : une case lointaine n'est plus dessinee).
static func _add_chunks(root: Node3D, layer_name: String, mesh: Mesh, xfs: Array, colors: PackedColorArray, shadows: bool) -> void:
	var cells := {}
	for k in xfs.size():
		var o: Vector3 = (xfs[k] as Transform3D).origin
		var key := Vector2i(floori(o.x / CELL), floori(o.z / CELL))
		if not cells.has(key):
			cells[key] = []
		(cells[key] as Array).append(k)
	var n := 0
	for key: Vector2i in cells:
		var ids: Array = cells[key]
		var center := Vector3((key.x + 0.5) * CELL, 0.0, (key.y + 0.5) * CELL)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = not colors.is_empty()
		mm.mesh = mesh
		mm.instance_count = ids.size()
		for j in ids.size():
			var k: int = ids[j]
			var xf: Transform3D = xfs[k]
			mm.set_instance_transform(j, Transform3D(xf.basis, xf.origin - center))
			if mm.use_colors:
				mm.set_instance_color(j, colors[k])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s%d" % [layer_name, n]
		mmi.multimesh = mm
		mmi.position = center
		# sans fondu : un objet en fondu passe dans la passe transparente (cher) ;
		# le sprite est deja la quand la case disparait
		mmi.visibility_range_end = NEAR_END
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# hors de l'eclairage global : il ne revoxelise plus des centaines
		# d'arbres quand la camera avance (leur rebond ne se voyait pas)
		mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		root.add_child(mmi)
		n += 1


## MultiMesh de sprites tournes (sans ombre) : un quad par arbre.
static func sprites(node_name: String, kind: String, bases: PackedVector3Array, scales: PackedFloat32Array,
		tints: PackedColorArray) -> MultiMeshInstance3D:
	var spec: Dictionary = KINDS[kind]
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	# pied du quad au sol de l'arbre
	quad.center_offset = Vector3(0.0, 0.5 - float(spec["bottom"]) / float(spec["size"]), 0.0)
	quad.material = material(kind)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = bases.size()
	var size: float = spec["size"]
	for k in bases.size():
		var sc := size * (scales[k] if k < scales.size() else 1.0)
		mm.set_instance_transform(k, Transform3D(Basis.IDENTITY.scaled(Vector3(sc, sc, sc)), bases[k]))
		mm.set_instance_color(k, tints[k] if k < tints.size() else Color.WHITE)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# les sprites tournent dans le shader : boite englobante elargie
	mmi.extra_cull_margin = size
	return mmi


static func material(kind: String) -> ShaderMaterial:
	if _materials.has(kind):
		return _materials[kind]
	var m := ShaderMaterial.new()
	m.shader = preload("res://tracks/materials/impostor.gdshader")
	var path := String(KINDS[kind]["path"])
	if ResourceLoader.exists(path):
		m.set_shader_parameter("albedo", load(path))
	m.set_shader_parameter("fade_begin", FAR_BEGIN)
	m.set_shader_parameter("fade_length", FAR_FADE)
	_materials[kind] = m
	return m
