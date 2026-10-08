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
##   HAUTE    tout, MSAA 2x + SMAA (lisse aussi les nervures des
##            conteneurs, sans trainee sur la pluie comme le TAA) ;
##            l'eclairage global est coupe au-dela de SDFGI_MAX_VIEWS vues,
##            le volumetrique au-dela de VOLUMETRIC_MAX_VIEWS, l'eclairage
##            indirect proche au-dela de SSIL_MAX_VIEWS
##   MOYENNE  SSAO seul, MSAA 2x
##   BASSE    aucun effet, anticrenelage FXAA (le moins couteux)

enum Quality { HIGH, MEDIUM, LOW }

const NAMES: PackedStringArray = ["haute", "moyenne", "basse"]
## Au-dela, l'eclairage indirect est coupe meme en qualite haute.
const SSIL_MAX_VIEWS := 2
## Au-dela, les reflets sont coupes meme en qualite haute.
const SSR_MAX_VIEWS := 4
## Au-dela, le brouillard volumetrique est coupe meme en qualite haute (il est
## calcule une fois par vue).
const VOLUMETRIC_MAX_VIEWS := 2
## Au-dela, l'eclairage global est coupe meme en qualite haute (calcule une
## fois par vue : 117 -> 81 images/s a 2 vues, 96 -> 54 a 4 sur Radeon 780M).
const SDFGI_MAX_VIEWS := 2


## Regle les effets de `env` pour la qualite et le nombre de vues 3D a
## l'ecran. L'environnement est une ressource partagee : a rappeler a chaque
## entree de scene (menu, course).
static func apply_environment(env: Environment, quality: int, views: int) -> void:
	if env == null:
		return
	var high := quality == Quality.HIGH
	env.ssao_enabled = quality != Quality.LOW
	env.ssr_enabled = high and views <= SSR_MAX_VIEWS
	env.ssil_enabled = high and views <= SSIL_MAX_VIEWS
	# eclairage global et volumetrique : seulement si l'environnement en decrit
	if env.has_meta(&"sdfgi") or env.sdfgi_enabled:
		env.set_meta(&"sdfgi", true)
		env.sdfgi_enabled = high and views <= SDFGI_MAX_VIEWS
	if env.has_meta(&"volumetric") or env.volumetric_fog_enabled:
		env.set_meta(&"volumetric", true)
		env.volumetric_fog_enabled = high and views <= VOLUMETRIC_MAX_VIEWS


## Anticrenelage d'une vue (fenetre principale ou SubViewport de l'ecran
## partage : une vue ne recoit pas le reglage du projet).
static func apply_viewport(vp: Viewport, quality: int) -> void:
	if vp == null:
		return
	if quality == Quality.LOW:
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	else:
		vp.msaa_3d = Viewport.MSAA_2X
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA if quality == Quality.HIGH \
			else Viewport.SCREEN_SPACE_AA_DISABLED


## Plein ecran sans bordure <-> fenetre (F11).
static func toggle_fullscreen() -> void:
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
