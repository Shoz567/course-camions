extends PhysicsTest

## Reglages non negociables de CLAUDE.md §2 et §6, lus sur leur valeur
## EFFECTIVE. L'editeur Godot retire de project.godot les lignes egales au
## defaut (60 ticks/s, Forward+) : le texte du fichier ne prouve rien, la
## valeur chargee si.
##
## Affichage et rendu (demande du 2026-09-30) : base 1920 x 1080 sans
## fenetre reduite imposee, plein ecran sans bordure, MSAA 2x ; les deux
## environnements decrivent le rendu complet (reflets SSR, eclairage indirect
## SSIL, occlusion SSAO ; brouillard volumetrique de nuit) et GraphicsSettings
## en retire selon la qualite choisie et le nombre de vues.


func _test_setup() -> void:
	duration_ticks = 1


func _test_finish() -> void:
	check("tick physique = 60 Hz", Engine.physics_ticks_per_second == 60,
		"ticks=%d" % Engine.physics_ticks_per_second)
	var engine: String = ProjectSettings.get_setting("physics/3d/physics_engine", "")
	check("moteur physique = Jolt", engine == "Jolt Physics", "moteur=%s" % engine)
	var renderer: String = ProjectSettings.get_setting("rendering/renderer/rendering_method", "")
	check("renderer = Forward+", renderer == "forward_plus", "renderer=%s" % renderer)
	# Rendu fluide au-dela de 60 Hz, et camera de poursuite sans a-coups
	# (chase_camera.gd lit la transformation interpolee du camion).
	check("interpolation physique active",
		ProjectSettings.get_setting("physics/common/physics_interpolation", false) == true)
	_check_display()
	_check_lighting()


func _check_display() -> void:
	var w: int = ProjectSettings.get_setting("display/window/size/viewport_width", 0)
	var h: int = ProjectSettings.get_setting("display/window/size/viewport_height", 0)
	check("base 1920 x 1080", w == 1920 and h == 1080, "%d x %d" % [w, h])
	var ow: int = ProjectSettings.get_setting("display/window/size/window_width_override", 0)
	var oh: int = ProjectSettings.get_setting("display/window/size/window_height_override", 0)
	check("plus de fenetre reduite imposee (1280 x 720)", ow == 0 and oh == 0, "%d x %d" % [ow, oh])
	var mode: int = ProjectSettings.get_setting("display/window/size/mode", 0)
	check("plein ecran sans bordure", mode == DisplayServer.WINDOW_MODE_FULLSCREEN, "mode=%d" % mode)
	var msaa: int = ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", 0)
	check("anticrenelage MSAA 2x", msaa == Viewport.MSAA_2X, "msaa_3d=%d" % msaa)


func _check_lighting() -> void:
	for path: String in ["res://tracks/cyber_night.tres", "res://tracks/playa_sun.tres"]:
		var env := load(path) as Environment
		check("%s : SSR, SSIL et SSAO actifs" % path.get_file(), env.ssr_enabled and env.ssil_enabled and env.ssao_enabled,
			"ssr=%s ssil=%s ssao=%s" % [env.ssr_enabled, env.ssil_enabled, env.ssao_enabled])
	var env := (load("res://tracks/cyber_night.tres") as Environment).duplicate() as Environment
	var seen := []
	for c: Array in [[GraphicsSettings.Quality.HIGH, 1], [GraphicsSettings.Quality.HIGH, 4],
			[GraphicsSettings.Quality.HIGH, 6], [GraphicsSettings.Quality.MEDIUM, 1], [GraphicsSettings.Quality.LOW, 1]]:
		GraphicsSettings.apply_environment(env, c[0], c[1])
		seen.append([env.ssr_enabled, env.ssil_enabled, env.ssao_enabled])
	check("qualite haute : tout a 1 vue, sans SSIL a 4 vues, SSAO seul a 6 ; moyenne : SSAO ; basse : rien",
		seen == [[true, true, true], [true, false, true], [false, false, true], [false, false, true],
		[false, false, false]], str(seen))
	# brouillard volumetrique de Cyber City (halo des phares sous la pluie) :
	# qualite haute jusqu'a 2 vues seulement ; la plage n'en a pas
	var fog := []
	for c: Array in [[GraphicsSettings.Quality.HIGH, 1], [GraphicsSettings.Quality.HIGH, 2],
			[GraphicsSettings.Quality.HIGH, 4], [GraphicsSettings.Quality.MEDIUM, 1], [GraphicsSettings.Quality.HIGH, 1]]:
		GraphicsSettings.apply_environment(env, c[0], c[1])
		fog.append(env.volumetric_fog_enabled)
	var day := (load("res://tracks/playa_sun.tres") as Environment).duplicate() as Environment
	GraphicsSettings.apply_environment(day, GraphicsSettings.Quality.HIGH, 1)
	check("volumetrique : haute a 1-2 vues, coupe a 4 vues et en moyenne ; jamais a la plage",
		fog == [true, true, false, false, true] and not day.volumetric_fog_enabled, str(fog))
	# eclairage global (SDFGI) sur les deux circuits : qualite haute jusqu'a
	# 2 vues seulement
	var gi := []
	for e: Environment in [env, day]:
		for c: Array in [[GraphicsSettings.Quality.HIGH, 1], [GraphicsSettings.Quality.HIGH, 2],
				[GraphicsSettings.Quality.HIGH, 3], [GraphicsSettings.Quality.MEDIUM, 1],
				[GraphicsSettings.Quality.HIGH, 1]]:
			GraphicsSettings.apply_environment(e, c[0], c[1])
			gi.append(e.sdfgi_enabled)
	check("eclairage global : haute a 1-2 vues, coupe a 3 vues et en moyenne, sur les deux circuits",
		gi == [true, true, false, false, true, true, true, false, false, true], str(gi))
	var vp := SubViewport.new()
	GraphicsSettings.apply_viewport(vp, GraphicsSettings.Quality.HIGH)
	var high := vp.msaa_3d == Viewport.MSAA_2X and vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_SMAA
	GraphicsSettings.apply_viewport(vp, GraphicsSettings.Quality.MEDIUM)
	var medium := vp.msaa_3d == Viewport.MSAA_2X and vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED
	GraphicsSettings.apply_viewport(vp, GraphicsSettings.Quality.LOW)
	check("vues de l'ecran partage : MSAA 2x + SMAA (haute), MSAA 2x (moyenne), FXAA (basse)", high and medium
		and vp.msaa_3d == Viewport.MSAA_DISABLED and vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA)
	check("case de l'ecran partage suivie par la resolution dynamique", vp.is_in_group(DynamicResolution.GROUP))
	DynamicResolution.apply_to(vp, 0.75)
	var fsr := vp.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR and is_equal_approx(vp.scaling_3d_scale, 0.75)
	DynamicResolution.apply_to(vp, 1.0)
	check("resolution dynamique : FSR sous 100 %, mise a l'echelle simple a 100 %", fsr
		and vp.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR and vp.scaling_3d_scale == 1.0)
	vp.free()
	# resolution dynamique (2026-10-09, GPU integres) : pleine resolution tant
	# que le budget de 60 images/s tient ; au-dela, chute a l'echelle estimee
	# (cout ~ pixels), bornee a MIN_SCALE ; remontee d'un palier apres
	# RAISE_HOLD s, si elle ne repasse pas le budget ; sans mesure, rien
	var steps := [DynamicResolution.next_scale(1.0, 10.0, 0.0), DynamicResolution.next_scale(1.0, 20.0, 0.0),
		DynamicResolution.next_scale(1.0, 100.0, 0.0), DynamicResolution.next_scale(0.8, 8.0, 1.0),
		DynamicResolution.next_scale(0.8, 8.0, 3.0), DynamicResolution.next_scale(0.8, 0.0, 3.0),
		DynamicResolution.next_scale(0.95, 9.0, 3.0), DynamicResolution.next_scale(0.8, 12.0, 3.0)]
	var want := [1.0, 0.8, DynamicResolution.MIN_SCALE, 0.8, 0.85, 0.8, 1.0, 0.8]
	var same := true
	for i in want.size():
		same = same and is_equal_approx(float(steps[i]), float(want[i]))
	check("resolution dynamique : 100 % dans le budget, baisse au cout estime, remontee prudente",
		same, str(steps))
	# post-traitement (ScreenFx) : plus de flou de vitesse (2026-10-09, a la
	# demande de l'utilisateur)
	var fx_methods := (load("res://gameplay/screen_fx.gd") as Script).get_script_method_list().map(
		func(m: Dictionary) -> String: return m["name"])
	check("post-traitement : plus de flou de vitesse",
		not fx_methods.has("drive") and not fx_methods.has("blur_for"), str(fx_methods))
	# pluie (2026-10-08, particules) : chaque vue ne voit que la sienne
	var masks := []
	for i in RainFx.MAX_VIEWS:
		masks.append(RainFx.cull_mask_for(0xFFFFF, i))
	var own := true
	for i in RainFx.MAX_VIEWS:
		for k in RainFx.MAX_VIEWS:
			own = own and (int(masks[i]) & RainFx.view_bit(k) != 0) == (i == k)
	check("pluie : chaque camera voit sa pluie et pas celle des autres vues, le reste intact",
		own and int(masks[0]) & 0xFFF == 0xFFF, str(masks))
	# qualite au lancement selon la carte graphique (2026-10-09, performance) :
	# haute sur carte dediee (et sans carte : tests), moyenne sur puce
	# integree, basse en rendu logiciel
	var dq := [GraphicsSettings.default_quality(RenderingDevice.DEVICE_TYPE_DISCRETE_GPU),
		GraphicsSettings.default_quality(RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU),
		GraphicsSettings.default_quality(RenderingDevice.DEVICE_TYPE_CPU)]
	check("qualite par defaut : haute (carte dediee), moyenne (integree), basse (logiciel)",
		dq == [GraphicsSettings.Quality.HIGH, GraphicsSettings.Quality.MEDIUM, GraphicsSettings.Quality.LOW]
		and GameState.graphics_quality == GraphicsSettings.Quality.HIGH, str(dq))
	# budget de l'ecran partage sur puce integree (spike V3) : qualite basse a
	# partir de 3 vues ; une carte dediee garde la sienne
	var igpu := RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU
	var dgpu := RenderingDevice.DEVICE_TYPE_DISCRETE_GPU
	var budget := [GraphicsSettings.split_quality(GraphicsSettings.Quality.MEDIUM, 2, igpu),
		GraphicsSettings.split_quality(GraphicsSettings.Quality.MEDIUM, 3, igpu),
		GraphicsSettings.split_quality(GraphicsSettings.Quality.HIGH, 4, igpu),
		GraphicsSettings.split_quality(GraphicsSettings.Quality.HIGH, 4, dgpu)]
	check("budget ecran partage : integree basse a 3 vues et plus, dediee inchangee",
		budget == [GraphicsSettings.Quality.MEDIUM, GraphicsSettings.Quality.LOW, GraphicsSettings.Quality.LOW,
		GraphicsSettings.Quality.HIGH], str(budget))
	var lamp := DirectionalLight3D.new()
	lamp.shadow_enabled = true
	var shadows := []
	for c: Array in [[2, GraphicsSettings.Quality.LOW], [4, GraphicsSettings.Quality.LOW], [4, GraphicsSettings.Quality.MEDIUM]]:
		GraphicsSettings.apply_sun(lamp, c[0], c[1])
		shadows.append(lamp.shadow_enabled)
	lamp.free()
	check("budget ecran partage : ombre du soleil coupee en basse a 3 vues et plus, rendue sinon",
		shadows == [true, false, true], str(shadows))
	# ombre du soleil : 4 cascades jusqu'a 2 vues, 2 au-dela
	var sun := DirectionalLight3D.new()
	var modes := []
	for v in [1, 2, 3, 4]:
		GraphicsSettings.apply_sun(sun, v)
		modes.append(sun.directional_shadow_mode)
	sun.free()
	check("ombre du soleil : 4 cascades a 1-2 vues, 2 a 3-4 vues", modes == [2, 2, 1, 1], str(modes))
