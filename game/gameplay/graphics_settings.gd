class_name GraphicsSettings
extends RefCounted

## Qualite graphique (ecran des parametres, GameState.graphics_quality) :
## quels effets d'eclairage de l'environnement sont actifs, et quel
## anticrenelage recoit chaque vue. Purement visuel.
##
## Les environnements (tracks/*.tres) decrivent le rendu COMPLET : reflets
## (SSR), eclairage indirect proche (SSIL) et global (SDFGI : la lumiere du
## ciel et des neons rebondit, le dessous des remorques s'assombrit),
## occlusion ambiante (SSAO), brouillard volumetrique (Cyber City : halo des
## phares dans la bruine). Ici, on en retire selon la qualite choisie et le
## nombre de vues de l'ecran partage :
##
##   EXTREME  (2026-10-22, « pour les PC avec GPU, la 4K ») tout, a toutes
##            les vues jusqu'a EXTREME_MAX_VIEWS, reglages des effets au
##            maximum (apply_render_quality : occlusion et eclairage indirect
##            ultra a pleine resolution, ombres douces ultra sur un atlas de
##            8192, reflets a 128 pas, eclairage global a 128 rayons), MSAA
##            4x + SMAA, detail maximal des maillages, filtrage anisotrope
##            16x ; ombre du soleil a 4 cascades et 1,6 fois plus loin. Le
##            decor se construit alors plus dense et plus detaille
##            (extreme_assets : arbres a branches et fleurs, batiments
##            ouvrages, plus de 3D au loin). Le menu demande confirmation ;
##   HAUTE    tout, MSAA 2x + SMAA (lisse aussi les nervures des
##            conteneurs, sans trainee sur la pluie comme le TAA) ;
##            l'eclairage global est coupe au-dela de SDFGI_MAX_VIEWS vues
##            et sur une puce Intel (sdfgi_supported),
##            le volumetrique au-dela de VOLUMETRIC_MAX_VIEWS, l'eclairage
##            indirect proche au-dela de SSIL_MAX_VIEWS
##   MOYENNE  SSAO seul, MSAA 2x
##   BASSE    aucun effet, anticrenelage FXAA (le moins couteux)
##
## Le post-traitement de chaque camera (ScreenFx : aberration, vignettage,
## brume de chaleur ; ~0,3 ms par vue) est pose par ChaseCamera en
## qualite haute et moyenne.
##
## Independamment de la qualite, DynamicResolution baisse la resolution de la
## 3D (FSR 1) quand le GPU ne tient plus 60 images/s ; les cases de l'ecran
## partage passees ici sont suivies (groupe DynamicResolution.GROUP).

## EXTREME en dernier : les valeurs deja enregistrees (0 a 2) ne bougent pas.
enum Quality { HIGH, MEDIUM, LOW, EXTREME }

const NAMES: PackedStringArray = ["haute", "moyenne", "basse", "extrême"]
## Ordre d'affichage dans les parametres : de la plus riche a la plus legere.
const MENU_ORDER: Array[int] = [Quality.EXTREME, Quality.HIGH, Quality.MEDIUM, Quality.LOW]
## Avertissement avant de passer en extreme (menu).
const EXTREME_WARNING := "Attention, ce paramètre requiert un GPU pour tourner stable, voulez-vous poursuivre ?"
## En extreme, tous les effets restent actifs jusqu'a ce nombre de vues.
const EXTREME_MAX_VIEWS := 4
## Ombre du soleil : portee multipliee en extreme.
const EXTREME_SHADOW_REACH := 1.6
## Au-dela, l'eclairage indirect est coupe meme en qualite haute.
const SSIL_MAX_VIEWS := 2
## Au-dela, les reflets sont coupes meme en qualite haute.
const SSR_MAX_VIEWS := 4
## Au-dela, le brouillard volumetrique est coupe meme en qualite haute (il est
## calcule une fois par vue).
const VOLUMETRIC_MAX_VIEWS := 2
## Au-dela, l'eclairage global est coupe meme en qualite haute (calcule une
## fois par vue : 117 -> 81 images/s a 2 vues, 96 -> 54 a 4 sur RTX 5060 Ti).
const SDFGI_MAX_VIEWS := 2
## Au-dela, l'ombre du soleil passe de 4 a 2 cascades (apply_sun).
const SHADOW_FULL_MAX_VIEWS := 2


## Qualite proposee au lancement d'apres la carte graphique (2026-10-09,
## « gros problemes de performance sur les petites configurations ») : haute
## sur une carte dediee, moyenne sur une puce integree (le rendu complet - GI,
## reflets, brouillard volumetrique - y coute plusieurs fois une image a
## 60 Hz), basse en rendu logiciel. Le joueur la change dans les parametres.
static func default_quality(adapter: int = RenderingServer.get_video_adapter_type()) -> int:
	match adapter:
		RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
			return Quality.MEDIUM
		RenderingDevice.DEVICE_TYPE_CPU:
			return Quality.LOW
	return Quality.HIGH


## Eclairage global (SDFGI) sur une puce Intel (2026-10-16, « le noir devient
## blanc ») : sur Iris Xe (pilote 31.0.101.4032), il blanchit et rosit la route
## et les portiques noirs de Cyber City, meme seul sur la qualite moyenne ;
## SSIL, SSR, volumetrique et SMAA n'y sont pour rien. Coupe sur Intel, meme
## en qualite haute.
static func sdfgi_supported(vendor: String = RenderingServer.get_video_adapter_vendor()) -> bool:
	return not vendor.to_lower().contains("intel")


## Regle les effets de `env` pour la qualite et le nombre de vues 3D a
## l'ecran. L'environnement est une ressource partagee : a rappeler a chaque
## entree de scene (menu, course).
static func apply_environment(env: Environment, quality: int, views: int) -> void:
	if env == null:
		return
	var high := quality == Quality.HIGH
	var extreme := quality == Quality.EXTREME and views <= EXTREME_MAX_VIEWS
	env.ssao_enabled = quality != Quality.LOW
	env.ssr_enabled = (high or quality == Quality.EXTREME) and views <= SSR_MAX_VIEWS
	env.ssil_enabled = extreme or (high and views <= SSIL_MAX_VIEWS)
	# eclairage global et volumetrique : seulement si l'environnement en decrit
	if env.has_meta(&"sdfgi") or env.sdfgi_enabled:
		env.set_meta(&"sdfgi", true)
		env.sdfgi_enabled = (extreme or (high and views <= SDFGI_MAX_VIEWS)) and sdfgi_supported()
	if env.has_meta(&"volumetric") or env.volumetric_fog_enabled:
		env.set_meta(&"volumetric", true)
		env.volumetric_fog_enabled = extreme or (high and views <= VOLUMETRIC_MAX_VIEWS)
	# reflets plus fins (pas de marche) : valeur d'origine gardee. Les cascades
	# de l'eclairage global restent celles de l'environnement : a 6, leurs
	# grosses cellules lointaines tachaient de sombre les reflets de la mer
	if not env.has_meta(&"ssr_steps"):
		env.set_meta(&"ssr_steps", env.ssr_max_steps)
	env.ssr_max_steps = maxi(int(env.get_meta(&"ssr_steps")), 128) if extreme else int(env.get_meta(&"ssr_steps"))
	# extreme : le reflet du ciel (eau, route mouillee, carrosseries) en 1024 px
	# au lieu de 128 ; les ciels sont statiques, il n'est calcule qu'une fois
	if env.sky != null:
		if not env.has_meta(&"radiance"):
			env.set_meta(&"radiance", env.sky.radiance_size)
			env.set_meta(&"sky_mode", env.sky.process_mode)
		var radiance := Sky.RADIANCE_SIZE_1024 if quality == Quality.EXTREME else int(env.get_meta(&"radiance"))
		if env.sky.radiance_size != radiance:
			env.sky.radiance_size = radiance
		env.sky.process_mode = Sky.PROCESS_MODE_QUALITY if quality == Quality.EXTREME else int(env.get_meta(&"sky_mode"))
	apply_render_quality(quality)


## Le decor se construit-il en version extreme (plus dense, plus detaillee) ?
## Lu une fois, a la construction du circuit.
static func extreme_assets() -> bool:
	# dans l'editeur (decors @tool), pas de GameState : decor ordinaire
	if Engine.is_editor_hint() or GameState.graphics_quality != Quality.EXTREME:
		return false
	# ecran partage sur puce integree : la course passe en qualite basse
	# (split_quality), le decor reste ordinaire aussi (2026-10-22 : 7 images/s
	# a 6 joueurs sur Radeon 780M avec le decor extreme)
	return split_quality(Quality.EXTREME, maxi(1, GameState.requested_players)) == Quality.EXTREME


## Reglages globaux du rendu (communs a toutes les vues) : au maximum en
## extreme, sinon ceux du projet.
static func apply_render_quality(quality: int) -> void:
	var x := quality == Quality.EXTREME
	var ps := func(key: String, fallback: Variant) -> Variant: return ProjectSettings.get_setting(key, fallback)
	RenderingServer.directional_shadow_atlas_set_size(8192 if x else int(ps.call(
		"rendering/lights_and_shadows/directional_shadow/size", 4096)), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_ULTRA if x else int(ps.call(
		"rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", 2)))
	RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_ULTRA if x else int(ps.call(
		"rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality", 2)))
	if x:
		RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_ULTRA, false, 0.5, 3, 50.0, 300.0)
		RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_ULTRA, false, 0.5, 4, 50.0, 300.0)
	else:
		RenderingServer.environment_set_ssao_quality(int(ps.call("rendering/environment/ssao/quality", 2)),
			bool(ps.call("rendering/environment/ssao/half_size", true)), float(ps.call("rendering/environment/ssao/adaptive_target", 0.5)),
			int(ps.call("rendering/environment/ssao/blur_passes", 2)), float(ps.call("rendering/environment/ssao/fadeout_from", 50.0)),
			float(ps.call("rendering/environment/ssao/fadeout_to", 300.0)))
		RenderingServer.environment_set_ssil_quality(int(ps.call("rendering/environment/ssil/quality", 2)),
			bool(ps.call("rendering/environment/ssil/half_size", true)), float(ps.call("rendering/environment/ssil/adaptive_target", 0.5)),
			int(ps.call("rendering/environment/ssil/blur_passes", 4)), float(ps.call("rendering/environment/ssil/fadeout_from", 50.0)),
			float(ps.call("rendering/environment/ssil/fadeout_to", 300.0)))
	RenderingServer.environment_set_sdfgi_ray_count(RenderingServer.ENV_SDFGI_RAY_COUNT_128 if x else int(ps.call(
		"rendering/global_illumination/sdfgi/probe_ray_count", 1)))
	RenderingServer.gi_set_use_half_resolution(false if x else bool(ps.call(
		"rendering/global_illumination/gi/use_half_resolution", true)))
	RenderingServer.environment_set_volumetric_fog_volume_size(160 if x else int(ps.call(
		"rendering/environment/volumetric_fog/volume_size", 64)), 128 if x else int(ps.call(
		"rendering/environment/volumetric_fog/volume_depth", 64)))


## Budget de l'ecran partage sur puce integree (spike V3, 2026-10-17, machine
## de reference Iris Xe, 1080p) : a 4 vues, Forward+ en qualite moyenne pleine
## resolution tient 16 images/s (48 ms GPU) ; qualite basse + 3D a 60 % +
## ombre du soleil coupee : 49 images/s (15 ms GPU). A partir de
## SPLIT_BUDGET_VIEWS vues sur une puce integree, la course passe donc en
## qualite basse et sans ombre de soleil ; la resolution dynamique (active par
## defaut) descend la 3D jusqu'a 60 %. Une carte dediee garde la qualite
## choisie.
const SPLIT_BUDGET_VIEWS := 3


## Qualite appliquee a la course : celle choisie, ou le budget de l'ecran
## partage sur puce integree.
static func split_quality(quality: int, views: int,
		adapter: int = RenderingServer.get_video_adapter_type()) -> int:
	if adapter == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU and views >= SPLIT_BUDGET_VIEWS:
		return Quality.LOW
	return quality


## Ombre du soleil (ou de la lune) : 4 cascades jusqu'a SHADOW_FULL_MAX_VIEWS
## vues, 2 au-dela - chaque vue est alors petite (960 x 540 a 4), la
## difference ne se voit pas, et chaque cascade redessine toute la scene dans
## chaque vue (2026-10-09, performance : -26 % d'appels de dessin a 4 vues).
## Qualite basse a partir de SPLIT_BUDGET_VIEWS vues : pas d'ombre du tout
## (budget du spike V3). L'ombre d'origine de la lumiere est gardee en meta :
## la lumiere est partagee par les courses successives.
static func apply_sun(light: DirectionalLight3D, views: int, quality: int = Quality.MEDIUM) -> void:
	if light == null:
		return
	if not light.has_meta(&"shadow"):
		light.set_meta(&"shadow", light.shadow_enabled)
	light.shadow_enabled = bool(light.get_meta(&"shadow")) \
			and not (quality == Quality.LOW and views >= SPLIT_BUDGET_VIEWS)
	var extreme := quality == Quality.EXTREME
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS \
		if views <= SHADOW_FULL_MAX_VIEWS or (extreme and views <= EXTREME_MAX_VIEWS) \
		else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	# extreme : l'ombre porte plus loin (portee d'origine gardee en meta)
	if not light.has_meta(&"shadow_reach"):
		light.set_meta(&"shadow_reach", light.directional_shadow_max_distance)
	light.directional_shadow_max_distance = float(light.get_meta(&"shadow_reach")) * (EXTREME_SHADOW_REACH if extreme else 1.0)


## Anticrenelage d'une vue (fenetre principale ou SubViewport de l'ecran
## partage : une vue ne recoit pas le reglage du projet).
static func apply_viewport(vp: Viewport, quality: int) -> void:
	if vp == null:
		return
	# case de l'ecran partage : suivie par la resolution dynamique
	if vp is SubViewport:
		vp.add_to_group(DynamicResolution.GROUP)
	if quality == Quality.LOW:
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	else:
		vp.msaa_3d = Viewport.MSAA_4X if quality == Quality.EXTREME else Viewport.MSAA_2X
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA if quality == Quality.HIGH or quality == Quality.EXTREME \
			else Viewport.SCREEN_SPACE_AA_DISABLED
	# extreme : maillages a leur detail maximal, textures filtrees en 16x
	vp.mesh_lod_threshold = 0.0 if quality == Quality.EXTREME else 1.0
	if &"anisotropic_filtering_level" in vp:
		vp.set(&"anisotropic_filtering_level", Viewport.ANISOTROPY_16X if quality == Quality.EXTREME else Viewport.ANISOTROPY_4X)


## Plein ecran sans bordure <-> fenetre (F11).
static func toggle_fullscreen() -> void:
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
