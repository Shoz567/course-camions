extends PhysicsTest

## Rendu realiste des camions (2026-10-07 : « ameliore les graphismes, le plus
## realiste possible ») : matieres (TruckMaterials) et feux qui eclairent
## (TruckLights). SAUTE si les modeles sont absents (clone sans Git LFS).
##
##   A. matieres : la peinture est vernie, teinte d'origine un peu moins
##      saturee ; pneus en gomme noire mate, vitres lisses ; plus de cones de
##      flamme figes ; bavettes derriere les roues ; modeles detailles
##      (Realiste/) ; la salissure (truck_body.
##      gdshader) part du bas des pneus ;
##   B. de nuit : deux projecteurs sous les phares, qui visent l'avant du
##      camion et un peu le sol ; le phare central est coupe ; deux feux
##      arriere rouges au bout de la remorque, remplaces (pas ajoutes) quand
##      la remorque change ;
##   C. de jour : aucune lampe ajoutee, phare central d'origine ; les verres
##      des phares a peine lumineux (bien moins que la nuit) ;
##   D. remorque creuse : sa carrosserie (caisse, chassis) passe par
##      truck_body_hollow.gdshader (percee au coeur des chocs graves,
##      interieur visible) ; celle du tracteur reste pleine.

var _night: Truck
var _day: Truck
var _ok: bool = false


func _test_setup() -> void:
	duration_ticks = 2
	TruckVisual.load_external_in_headless = true
	add_floor(200.0)
	TruckLights.night = true
	_night = TruckTestUtil.spawn_truck(self, Vector3(0.0, 0.0, 0.0), Vector3(0.0, 30.0, 0.0))
	TruckLights.night = false
	_day = TruckTestUtil.spawn_truck(self, Vector3(40.0, 0.0, 0.0))
	for t: Truck in [_night, _day]:
		var v := t.get_node("Visual") as TruckVisual
		if not v.model_loaded:
			skip("modele externe absent (%s)" % v.external_model)
			return
	TruckLights.night = true
	var type := load("res://vehicles/trailers/citerne.tres") as TrailerType
	(_night.get_node("Visual") as TruckVisual).set_trailer_type(type)
	(_night.get_node("Visual") as TruckVisual).set_trailer_type(load("res://vehicles/trailers/conteneur.tres") as TrailerType)
	TruckLights.night = false
	_ok = true


## Materiau effectif de la premiere surface dont le materiau d'origine porte
## ce prefixe.
func _material(root: Node, prefix: String) -> Array:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			if src != null and src.resource_name.begins_with(prefix):
				return [src, mi.get_surface_override_material(s)]
	return []


func _lamps(root: Node, cls: String) -> Array[Node]:
	var out: Array[Node] = []
	for n in root.find_children("*", cls, true, false):
		if n.is_in_group(TruckLights.GROUP):
			out.append(n)
	return out


func _test_finish() -> void:
	TruckVisual.load_external_in_headless = false
	TruckLights.night = false
	if not _ok:
		return
	var vn := _night.get_node("Visual") as TruckVisual
	var vd := _day.get_node("Visual") as TruckVisual

	var paint := _material(vd, "Peinture_Cabine")
	var p := paint[1] as ShaderMaterial if paint.size() == 2 else null
	var src_col: Color = (paint[0] as BaseMaterial3D).albedo_color if paint.size() == 2 else Color.BLACK
	var col: Color = p.get_shader_parameter(&"albedo") if p != null else Color.BLACK
	check("A peinture vernie, teinte d'origine un peu moins saturee (pas un jouet)", p != null
		and float(p.get_shader_parameter(&"clearcoat")) >= 0.9 and absf(col.h - src_col.h) < 0.01
		and col.s < src_col.s and col.s > src_col.s * 0.7, "%s -> %s" % [src_col, col])
	var tyre := _material(vd, "Pneu")
	var r := tyre[1] as ShaderMaterial if tyre.size() == 2 else null
	var tyre_col: Color = r.get_shader_parameter(&"albedo") if r != null else Color.WHITE
	check("A pneus en gomme noire mate", r != null and tyre_col.get_luminance() < 0.06
		and float(r.get_shader_parameter(&"roughness")) >= 0.85)
	var glass := _material(vd, "Vitre")
	var g := glass[1] as BaseMaterial3D if glass.size() == 2 else null
	check("A vitres lisses", g != null and g.roughness <= 0.01)
	check("A plus de cones de flamme figes sur les cheminees", vd.find_children("Flamme*", "MeshInstance3D", true,
		false).is_empty())
	var flaps := vn.find_children(TruckDetails.FLAP_PREFIX + "_*", "MeshInstance3D", true, false)
	check("A bavettes derriere les roues du tracteur et de la remorque", flaps.size() >= 4, "%d" % flaps.size())
	# salissure : la hauteur au-dessus du sol vaut ~0 au bas des pneus
	var lowest := INF
	for n in vd.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var p_row: Variant = mi.get_instance_shader_parameter(&"height_row")
		if not mi.is_visible_in_tree() or p_row == null:
			continue
		var row: Vector4 = p_row
		var ab := mi.get_aabb()
		for k in 8:
			var c := ab.get_endpoint(k)
			lowest = minf(lowest, row.x * c.x + row.y * c.y + row.z * c.z + row.w)
	check_near("A salissure : hauteur au sol mesuree depuis le bas des pneus (m)", lowest, 0.0, 0.05)
	# modeles detailles (tools/blender/realisme_vehicules.py) : calandre,
	# optiques, antibrouillards... sur la tete ; garde-boue cintres sur la remorque
	check("A tete detaillee (Realiste/, pieces Detail_)", vd.external_model.contains("/Realiste/")
		and vd.find_children("Detail_Calandre_Grille*", "MeshInstance3D", true, false).size() == 1
		and vd.find_children("Detail_Antibrouillard*", "MeshInstance3D", true, false).size() == 2)
	# silhouette : le pare-brise est incline (son haut est plus en arriere que
	# son bas, au moins 15 cm), plus une face plate de boite
	var glass_rake := 0.0
	for n in vd.find_children("Pare_Brise*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var top_z := -INF
		var low_z := INF
		var top_back := 0.0
		var low_back := 0.0
		var inv := _day.global_transform.affine_inverse() * mi.global_transform
		for v: Vector3 in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			var q := inv * v
			if q.y > top_z:
				top_z = q.y
				top_back = q.z
			if q.y < low_z:
				low_z = q.y
				low_back = q.z
		glass_rake = top_back - low_back
	check_above("A cabine profilee : pare-brise incline (m)", glass_rake, 0.15)
	var skin := vn.get_trailer_skin()
	check("A remorque detaillee : garde-boue cintres", skin != null
		and not skin.find_children("Detail_Garde_Boue_Cintre*", "MeshInstance3D", true, false).is_empty())
	# relief (2026-10-07, « plus lisses et realistes, avec du relief ») : tole
	# ondulee du conteneur le long de la caisse (axe horizontal), sculptures
	# des pneus autour de l'axe de la roue (rayon de pneu)
	var box := _material(skin, "Conteneur") if skin != null else []
	var box_mat := box[1] as ShaderMaterial if box.size() == 2 else null
	var box_axis := _relief_axis(skin, "Conteneur")
	check("A conteneur en tole ondulee, ondes le long de la caisse", box_mat != null
		and int(box_mat.get_shader_parameter(&"relief")) == TruckMaterials.RELIEF_CORRUGATED
		and absf(box_axis.y) < 0.1 and Vector3(box_axis.x, box_axis.y, box_axis.z).length() > 0.9, str(box_axis))
	# rayon dans le repere du maillage : pneus de la tete refaits en unites du
	# modele (2026-10-09, roues comme celles de la remorque) - 0,72 a l'avant,
	# 0,84 a l'arriere ; un essieu entier donnerait sa voie (> 1,5)
	var tyre_axis := _relief_axis(vd, "Pneu")
	var tyre_mat := (_material(vd, "Pneu")[1]) as ShaderMaterial
	check("A pneus sculptes : axe de roue et rayon de pneu", tyre_mat != null
		and int(tyre_mat.get_shader_parameter(&"relief")) == TruckMaterials.RELIEF_TYRE
		and tyre_axis.w > 0.35 and tyre_axis.w < 0.9, str(tyre_axis))
	# tete en relief (2026-10-09) : marchepieds et plateau en tole larmee,
	# pare-chaleur perfores, calandre et prise d'air en nid d'abeille,
	# longerons perces ; chaque piece a son axe et son centre
	var heads := []
	for c: Array in [["Aluminium_Larme", TruckMaterials.RELIEF_TREAD_PLATE],
			["Chassis_Larme", TruckMaterials.RELIEF_TREAD_PLATE],
			["Aluminium_Perfore", TruckMaterials.RELIEF_PERFORATED],
			["Plastique_Grille", TruckMaterials.RELIEF_HONEYCOMB],
			["Chassis_Longeron", TruckMaterials.RELIEF_DRILLED]]:
		var mm := _material(vd, c[0])
		var sm := mm[1] as ShaderMaterial if mm.size() == 2 else null
		var ax := _relief_axis(vd, c[0])
		heads.append(sm != null and int(sm.get_shader_parameter(&"relief")) == c[1]
			and Vector3(ax.x, ax.y, ax.z).length() > 0.9)
	check("A tete : tole larmee, tole perforee, nid d'abeille, longerons perces", not heads.has(false),
		str(heads))
	# roues de la tete comme celles de la remorque (2026-10-09) : jante
	# emboutie avec ajours, moyeu et dix ecrous, sur chaque roue exterieure
	var vented := 0
	for n in vd.find_children("WheelPivot_*", "Node3D", true, false):
		for j in n.find_children("Jante*", "MeshInstance3D", true, false):
			vented += 1 if (j as MeshInstance3D).mesh.get_surface_count() == 2 else 0
	check("A roues de la tete : jantes embouties a ajours (une par groupe de roues)", vented == 4,
		"%d jantes a ajours" % vented)
	# silhouettes d'ombre (2026-10-09, performance) : la carrosserie et la
	# remorque projettent leur ombre par un maillage fusionne ; leurs pieces
	# n'en projettent plus, les pneus gardent la leur (ils eclatent). Une
	# piece arrachee rend leur ombre aux pieces de sa partie.
	var body := vd.get_node_or_null(NodePath("%s/Body" % TruckVisual.MODEL_ROOT)) as Node3D
	var proxy := body.get_node_or_null(NodePath(ShadowProxy.NODE_NAME)) as MultiMeshInstance3D if body != null else null
	var lit := 0
	var dark := 0
	# le verre ne fait pas partie de la silhouette : il garde son reglage
	var panes := 0
	for n in body.find_children("*", "MeshInstance3D", true, false) if body != null else []:
		if (n as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			dark += 1
		elif not ShadowProxy._opaque((n as MeshInstance3D).mesh):
			panes += 1
		else:
			lit += 1
	var tyres_lit := true
	for pivot in vd.find_children("WheelPivot_*", "Node3D", true, false):
		for n in pivot.find_children("Pneu*", "MeshInstance3D", true, false):
			tyres_lit = tyres_lit and (n as MeshInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var skin_proxy := skin != null and skin.get_node_or_null(NodePath(ShadowProxy.NODE_NAME)) != null
	check("A ombres : silhouette de la carrosserie et de la remorque, pneus a part", proxy != null
		and proxy.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and dark > 50 and lit == 0
		and tyres_lit and skin_proxy, "couvertes %d, a part %d, verre %d, pneus %s, remorque %s" % [dark, lit, panes, tyres_lit, skin_proxy])
	if proxy != null:
		var part: MeshInstance3D = null
		for n in body.find_children("Retro_*", "MeshInstance3D", true, false):
			part = n as MeshInstance3D
			break
		ShadowProxy.release(part)
		var back := 0
		for n in body.find_children("*", "MeshInstance3D", true, false):
			back += 1 if (n as MeshInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF else 0
		check("A piece arrachee : la silhouette s'efface, chaque piece retrouve son ombre",
			not proxy.visible and back == dark + panes, "%d / %d" % [back, dark + panes])
	# remorque creuse (2026-10-07, « des qu'elle s'abime on voit a
	# l'interieur ») : caisse et chassis de la remorque en coque percable,
	# vue des deux faces ; pas le tracteur
	check("D remorque creuse : sa caisse peut se trouer, l'interieur se voit", box_mat != null
		and box_mat.shader == TruckMaterials.HOLLOW_SHADER and box_mat.shader.code.contains("cull_disabled"))
	check("D tracteur : carrosserie pleine", p != null and p.shader == TruckMaterials.BODY_SHADER)
	var frame := _material(skin, "Chassis") if skin != null else []
	check("D chassis de la remorque aussi creux", frame.size() == 2
		and (frame[1] as ShaderMaterial).shader == TruckMaterials.HOLLOW_SHADER)

	var spots := _lamps(vn, "SpotLight3D")
	var fwd := -_night.global_basis.z
	var aimed := spots.size() == 2
	for s: Node in spots:
		var dir := -(s as Node3D).global_basis.z
		aimed = aimed and dir.dot(fwd) > 0.95 and dir.y < 0.0
	check("B nuit : deux projecteurs qui visent devant et le sol", aimed, "%d" % spots.size())
	check("B nuit : phare central coupe", not (_night.get_node("Headlights") as Node3D).visible)
	var tails := _lamps(vn, "OmniLight3D")
	var behind := tails.size() == 2
	for l: Node in tails:
		var local := _night.global_transform.affine_inverse() * (l as Node3D).global_position
		behind = behind and local.z > TruckSpec.KINGPIN.z + 8.0 and (l as OmniLight3D).light_color.r > 0.9
	check("B nuit : deux feux arriere rouges au bout de la remorque (remplaces au changement)", behind,
		"%d" % tails.size())

	check("C jour : aucune lampe ajoutee", _lamps(vd, "Light3D").is_empty())
	check("C jour : phare central d'origine", (_day.get_node("Headlights") as Node3D).visible)
	var lamp_day := _material(vd, "Phare")
	var lamp_night := _material(vn, "Phare")
	var ed := (lamp_day[1] as BaseMaterial3D).emission_energy_multiplier if lamp_day.size() == 2 else INF
	var en := (lamp_night[1] as BaseMaterial3D).emission_energy_multiplier if lamp_night.size() == 2 else 0.0
	check("C verres des phares : a peine lumineux de jour, allumes la nuit", ed * 4.0 < en, "%.2f / %.2f" % [ed, en])


## relief_axis du premier maillage dont un materiau d'origine porte ce prefixe.
func _relief_axis(root: Node, prefix: String) -> Vector4:
	if root == null:
		return Vector4.ZERO
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			if src != null and src.resource_name.begins_with(prefix):
				var v: Variant = mi.get_instance_shader_parameter(&"relief_axis")
				return v if v is Vector4 else Vector4.ZERO
	return Vector4.ZERO
