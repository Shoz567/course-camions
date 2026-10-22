extends PhysicsTest

## Qualite extreme (2026-10-22 : « un dernier setting Extreme ou tu mets plus
## d'assets et plus detailles, des branches crisp et des feuillages
## individuels, avec tous les effets mis en valeur ») : les trois circuits
## construits en qualite extreme (generation forcee en headless) :
##   - Playa : palmiers detailles (TreeKit, plus de 3 000 triangles chacun
##     contre ~340), plus serres, 3D jusqu'a FarLod.EXTREME_NEAR_END, sprites
##     photographies du palmier detaille ;
##   - Sakura : cerisiers detailles d'un seul bloc (bois et fleurs), un tiers
##     de plus, maisons detaillees (noren de tissu) ;
##   - Cyber City : tours detaillees le long de la piste ;
##   - decor de bord de piste vu de plus loin ;
##   - effets : tout actif a 4 vues, MSAA 4x, ombre a 4 cascades et plus loin.
## Puis retour en qualite haute : le decor redevient ordinaire.

const SCENES: PackedStringArray = ["res://tracks/track_01_blockout.tscn", "res://tracks/track_02_playa.tscn",
	"res://tracks/track_03_sakura.tscn"]

var _tracks: Array[TrackBlockout] = []
var _plain_palms: int = 0
var _was: int = 0


func _test_setup() -> void:
	duration_ticks = 3
	_was = GameState.graphics_quality
	RoadsideDressing.generate_in_headless = true
	PlayaBackdrop.generate_in_headless = true
	SakuraBackdrop.generate_in_headless = true
	CityBackdrop.generate_in_headless = true
	# reference : Playa en qualite haute
	GameState.graphics_quality = GraphicsSettings.Quality.HIGH
	var plain := (load(SCENES[1]) as PackedScene).instantiate() as TrackBlockout
	add_child(plain)
	_plain_palms = (plain.get_node("PlayaBackdrop/Playa").get_meta(&"palms", []) as Array).size()
	plain.queue_free()
	GameState.graphics_quality = GraphicsSettings.Quality.EXTREME
	for path in SCENES:
		var t := (load(path) as PackedScene).instantiate() as TrackBlockout
		add_child(t)
		_tracks.append(t)
	RoadsideDressing.generate_in_headless = false
	PlayaBackdrop.generate_in_headless = false
	SakuraBackdrop.generate_in_headless = false
	CityBackdrop.generate_in_headless = false


func _test_finish() -> void:
	var cyber := _tracks[0]
	var playa := _tracks[1]
	var sakura := _tracks[2]
	# Playa : palmiers detailles, plus nombreux, 3D plus loin
	var proot := playa.get_node("PlayaBackdrop/Playa")
	var palms: Array = proot.get_meta(&"palms", [])
	check_above("Playa : plus de palmiers qu'en haute (part)", float(palms.size()) / maxf(_plain_palms, 1.0), 1.15)
	var trunk := proot.find_children("PalmTrunks*", "MultiMeshInstance3D", false, false)
	var crown := proot.find_children("PalmCrowns*", "MultiMeshInstance3D", false, false)
	var palm_tris := 0
	if not trunk.is_empty() and not crown.is_empty():
		palm_tris = TreeKit.triangle_count((trunk[0] as MultiMeshInstance3D).multimesh.mesh) \
			+ TreeKit.triangle_count((crown[0] as MultiMeshInstance3D).multimesh.mesh)
	check_above("Playa : palmier detaille (triangles)", palm_tris, 3000.0)
	check("Playa : palmiers 3D jusqu'a %d m" % FarLod.EXTREME_NEAR_END, not trunk.is_empty()
		and is_equal_approx((trunk[0] as MultiMeshInstance3D).visibility_range_end, FarLod.EXTREME_NEAR_END))
	var far := proot.get_node_or_null("PalmFar") as MultiMeshInstance3D
	var mat := (far.multimesh.mesh as QuadMesh).material as ShaderMaterial if far != null else null
	var tex := mat.get_shader_parameter("albedo") as Texture2D if mat != null else null
	check("Playa : sprites lointains = photo du palmier detaille", tex != null and tex.resource_path.ends_with("palm_hd.png"))
	# Sakura : cerisiers detailles d'un bloc, un tiers de plus, maisons detaillees
	var sroot := sakura.get_node("SakuraBackdrop/Sakura")
	var trees: Array = sroot.get_meta(&"trees", [])
	var sb := sakura.get_node("SakuraBackdrop") as SakuraBackdrop
	check_above("Sakura : arbres (un tiers de plus)", trees.size(), sb.tree_target * 1.3)
	var hd := sroot.find_children("Crowns*", "MultiMeshInstance3D", false, false)
	var tree_mesh := (hd[0] as MultiMeshInstance3D).multimesh.mesh if not hd.is_empty() else null
	check("Sakura : cerisier detaille d'un bloc (bois + fleurs, plus de 5 000 triangles)", tree_mesh != null
		and tree_mesh.get_surface_count() == 2 and TreeKit.triangle_count(tree_mesh) > 5000
		and sroot.find_children("Trunks*", "", false, false).is_empty(),
		"%d" % (TreeKit.triangle_count(tree_mesh) if tree_mesh != null else 0))
	var cloth := 0
	for mi in sroot.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		for k in m.get_surface_count():
			var sm := m.surface_get_material(k) as BaseMaterial3D
			if sm != null and sm.vertex_color_use_as_albedo and sm.cull_mode == BaseMaterial3D.CULL_DISABLED:
				cloth += 1
	check_above("Sakura : maisons detaillees (noren de tissu)", cloth, 0.0)
	# Cyber City : tours detaillees
	var details := cyber.get_node_or_null("CityBackdrop/City/Details")
	check("Cyber City : tours detaillees le long de la piste", details != null and details.get_child_count() > 3,
		"%d cases" % (details.get_child_count() if details != null else 0))
	# decor de bord de piste vu de plus loin
	var cell := sakura.get_node("RoadsideDressing/Dressing").get_child(0) as MeshInstance3D
	check("bord de piste : vu jusqu'a %d m" % roundi(RoadsideDressing.VIEW_END * RoadsideDressing.EXTREME_VIEW),
		cell != null and is_equal_approx(cell.visibility_range_end, RoadsideDressing.VIEW_END * RoadsideDressing.EXTREME_VIEW))
	# effets : tout a 4 vues, MSAA 4x, ombre a 4 cascades, portee x1,6
	var env := Environment.new()
	env.sdfgi_enabled = true
	env.volumetric_fog_enabled = true
	GraphicsSettings.apply_environment(env, GraphicsSettings.Quality.EXTREME, 4)
	var all4 := env.ssao_enabled and env.ssr_enabled and env.ssil_enabled and env.volumetric_fog_enabled \
		and env.sdfgi_enabled == GraphicsSettings.sdfgi_supported()
	GraphicsSettings.apply_environment(env, GraphicsSettings.Quality.HIGH, 4)
	var high4 := env.ssil_enabled or env.volumetric_fog_enabled
	var vp := SubViewport.new()
	add_child(vp)
	GraphicsSettings.apply_viewport(vp, GraphicsSettings.Quality.EXTREME)
	var vp_ok := vp.msaa_3d == Viewport.MSAA_4X and vp.mesh_lod_threshold == 0.0
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 200.0
	add_child(sun)
	GraphicsSettings.apply_sun(sun, 4, GraphicsSettings.Quality.EXTREME)
	var sun_ok := sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS \
		and is_equal_approx(sun.directional_shadow_max_distance, 200.0 * GraphicsSettings.EXTREME_SHADOW_REACH)
	GraphicsSettings.apply_sun(sun, 4, GraphicsSettings.Quality.HIGH)
	sun_ok = sun_ok and is_equal_approx(sun.directional_shadow_max_distance, 200.0)
	check("effets extremes : tout actif a 4 vues (la haute en coupe), MSAA 4x, detail maximal",
		all4 and not high4 and vp_ok, "%s %s %s" % [all4, high4, vp_ok])
	check("ombre du soleil extreme : 4 cascades a 4 vues, 1,6 fois plus loin, puis rendue", sun_ok)
	GameState.graphics_quality = _was
	GraphicsSettings.apply_render_quality(_was)
