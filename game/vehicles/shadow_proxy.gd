class_name ShadowProxy
extends RefCounted

## Silhouettes d'ombre des camions (2026-10-09, « gros problemes de
## performance sur les petites configurations ») : un camion compte ~140
## pieces, chacune redessinee dans les 4 cascades de l'ombre du soleil de
## chaque vue - 8 600 des 12 000 appels de dessin d'une course a 4 (mesure).
## Les pieces fixes d'une partie rigide (carrosserie, remorque) projettent
## desormais leur ombre par UN maillage fusionne, invisible a l'image (ombre
## seule), avec ses niveaux de detail ; elles-memes ne projettent plus rien.
## La silhouette est un MultiMeshInstance3D (une instance) : les parcours
## des MeshInstance3D (degats, cicatrices, matieres) ne la voient pas.
## Restent a part, avec leur propre ombre : ce qui bouge (roues, essieux),
## le verre, ce qui n'en projetait pas. Une piece arrachee (BodyDamage)
## libere la silhouette de sa partie : chaque piece y retrouve son ombre,
## l'ombre d'une piece partie ne reste pas au sol. Les creux des chocs ne
## deforment pas la silhouette (ecart de quelques centimetres dans l'ombre).

const NODE_NAME := &"ShadowProxy"
## Meta posee sur les pieces couvertes : leur reglage d'ombre d'origine.
const META := &"shadow_proxied"

static var _material: StandardMaterial3D


## Ajoute a `group` la silhouette de ses pieces fixes ; `moving` : prefixes
## des sous-arbres qui bougent seuls (exclus), `skip` : pieces exclues.
## Renvoie le nombre de pieces couvertes.
static func build(group: Node3D, moving: PackedStringArray, skip: PackedStringArray) -> int:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	var covered: Array[MeshInstance3D] = []
	_collect(group, Transform3D.IDENTITY, moving, skip, verts, normals, idx, covered)
	if covered.size() < 2:
		return 0
	var im := ImporterMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, _shadow_material())
	im.generate_lods(60.0, 25.0, [])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = im.get_mesh()
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D.IDENTITY)
	var node := MultiMeshInstance3D.new()
	node.name = NODE_NAME
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	group.add_child(node)
	for mi in covered:
		mi.set_meta(META, int(mi.cast_shadow))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return covered.size()


## `part` va disparaitre (arrachee) : la silhouette qui la couvre s'efface,
## les pieces qu'elle couvrait retrouvent leur ombre.
static func release(part: Node) -> void:
	if not part.has_meta(META):
		return
	var n := part.get_parent()
	while n != null:
		var proxy := n.get_node_or_null(NodePath(NODE_NAME)) as GeometryInstance3D
		if proxy != null and proxy.visible:
			proxy.visible = false
			for c in n.find_children("*", "MeshInstance3D", true, false):
				if c.has_meta(META):
					(c as MeshInstance3D).cast_shadow = int(c.get_meta(META)) as GeometryInstance3D.ShadowCastingSetting
			return
		n = n.get_parent()


static func _collect(node: Node, xf: Transform3D, moving: PackedStringArray, skip: PackedStringArray,
		verts: PackedVector3Array, normals: PackedVector3Array, idx: PackedInt32Array,
		covered: Array[MeshInstance3D]) -> void:
	for c in node.get_children():
		var n3 := c as Node3D
		if n3 == null or not n3.visible or _starts(c.name, moving):
			continue
		var cxf := xf * n3.transform
		var mi := c as MeshInstance3D
		if mi != null and mi.mesh != null and mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
				and not _starts(c.name, skip) and _opaque(mi.mesh):
			_append(mi.mesh, cxf, verts, normals, idx)
			covered.append(mi)
		_collect(c, cxf, moving, skip, verts, normals, idx, covered)


static func _append(mesh: Mesh, xf: Transform3D, verts: PackedVector3Array, normals: PackedVector3Array,
		idx: PackedInt32Array) -> void:
	var nb := xf.basis.inverse().transposed()
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var nr = a[Mesh.ARRAY_NORMAL]
		var base := verts.size()
		for i in v.size():
			verts.append(xf * v[i])
			normals.append((nb * (nr as PackedVector3Array)[i]).normalized() if nr != null else Vector3.UP)
		if a[Mesh.ARRAY_INDEX] != null:
			for k: int in (a[Mesh.ARRAY_INDEX] as PackedInt32Array):
				idx.append(base + k)
		else:
			for k in v.size():
				idx.append(base + k)


## Toutes les surfaces opaques (le verre ne projette pas d'ombre).
static func _opaque(mesh: Mesh) -> bool:
	for s in mesh.get_surface_count():
		var m := mesh.surface_get_material(s) as BaseMaterial3D
		if m != null and (m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
				or m.resource_name.to_lower().begins_with("vitre")):
			return false
	return true


static func _starts(node_name: StringName, prefixes: PackedStringArray) -> bool:
	var s := String(node_name)
	for p in prefixes:
		if s.begins_with(p):
			return true
	return false


static func _shadow_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		# pieces minces (voiles de jante, toles) : les deux faces projettent
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _material
