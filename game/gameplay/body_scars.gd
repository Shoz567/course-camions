class_name BodyScars
extends RefCounted

## Cicatrices de la carrosserie (2026-10-07 : « des sortes de traits blancs
## [...] pas tres realiste ; quitte a avoir des vraies cicatrices »). Elles
## remplacent les decalques : la peinture du camion (truck_body.gdshader)
## les dessine elle-meme, au pixel pres, sur toutes les faces touchees -
##   - au coeur du choc la peinture saute a bord dechiquete : appret gris et
##     tole nue, rayee dans le sens du frottement (horizontal) ;
##   - autour, peinture eraflee et ternie (plus de vernis), rayures fines ;
##   - tole froissee (relief des plis) d'autant plus que le choc est violent ;
##   - sur les gros chocs, le centre est noirci (suie, peinture brulee).
## Chaque maillage touche garde au plus SLOTS cicatrices (parametres
## d'instance scar0..scar7, dans son repere : centre, rayon et gravite) : un
## nouveau choc pres d'une cicatrice l'agrandit et l'aggrave, sinon il prend
## une place libre, ou s'ajoute a la plus proche quand tout est pris. Rien
## ne s'efface avant clear() (reapparition, nouvelle remorque). Purement
## visuel, aucun maillage modifie.

const SLOTS := 8
const PARAMS: Array[StringName] = [&"scar0", &"scar1", &"scar2", &"scar3", &"scar4", &"scar5", &"scar6", &"scar7"]
## Rayon maximal d'une cicatrice (m, repere du maillage ; code sur 3 bits).
const MAX_RADIUS := 7.9
const META := &"body_scars"

## Cicatrice de rayon `radius` (m) et de gravite `severity` (0 .. 1) au point
## monde `point`, sur toutes les carrosseries sous `root` a portee. Renvoie le
## nombre de maillages marques.
static func add(root: Node3D, point: Vector3, radius: float, severity: float) -> int:
	if root == null or radius <= 0.0 or severity <= 0.0:
		return 0
	var count := 0
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var xf := mi.global_transform
		if not (xf * mi.get_aabb()).grow(radius).has_point(point):
			continue
		var s := absf(xf.basis.get_scale().x)
		if s < 1e-4:
			continue
		_add_local(mi, xf.affine_inverse() * point, radius / s, severity)
		count += 1
	return count

## Cicatrices d'un maillage : Array de Vector4 (centre local, rayon) et
## gravites (tests, copie).
static func of(mi: MeshInstance3D) -> Array:
	return mi.get_meta(META, [])

## Carrosseries sous `root` remises a neuf (plus aucune cicatrice).
static func clear(root: Node3D) -> void:
	if root == null:
		return
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for n in meshes:
		var mi := n as MeshInstance3D
		if not mi.has_meta(META):
			continue
		mi.remove_meta(META)
		for p in PARAMS:
			mi.set_instance_shader_parameter(p, Vector4.ZERO)

## Nombre de maillages marques sous `root` (tests).
static func scarred(root: Node3D) -> int:
	var count := 0
	for n in root.find_children("*", "MeshInstance3D", true, false):
		if not of(n as MeshInstance3D).is_empty():
			count += 1
	return count

static func _add_local(mi: MeshInstance3D, p: Vector3, r: float, sev: float) -> void:
	# [centre, rayon, gravite] par cicatrice
	var list: Array = of(mi).duplicate(true)
	var nearest := -1
	var nearest_d := INF
	for i in list.size():
		var c: Vector3 = list[i][0]
		var d := c.distance_to(p) - float(list[i][1])
		if d < nearest_d:
			nearest_d = d
			nearest = i
	# un choc sur une cicatrice (ou plus de place) : elle s'etend et s'aggrave
	if nearest >= 0 and (nearest_d < r * 0.5 or list.size() >= SLOTS):
		var c: Vector3 = list[nearest][0]
		var r0: float = list[nearest][1]
		var s0: float = list[nearest][2]
		var w := sev * r / (sev * r + s0 * r0)
		var c2 := c.lerp(p, w)
		# le nouveau disque reste couvert
		var r2 := maxf(maxf(r0 + c.distance_to(c2) * 0.5, r + p.distance_to(c2) * 0.5), r0 * 1.08)
		list[nearest] = [c2, minf(r2, MAX_RADIUS), minf(maxf(s0, sev) + 0.25 * minf(s0, sev), 1.0)]
	else:
		list.append([p, minf(r, MAX_RADIUS), clampf(sev, 0.0, 1.0)])
	mi.set_meta(META, list)
	for i in SLOTS:
		mi.set_instance_shader_parameter(PARAMS[i], _pack(list[i]) if i < list.size() else Vector4.ZERO)

## Centre (xyz) et w = gravite (1 .. 255) * 8 + rayon (< 8) : decode par
## truck_body.gdshader.
static func _pack(scar: Array) -> Vector4:
	var c: Vector3 = scar[0]
	var level := clampi(roundi(float(scar[2]) * 255.0), 1, 255)
	return Vector4(c.x, c.y, c.z, level * 8.0 + clampf(scar[1], 0.05, MAX_RADIUS))
