class_name GraphicsSettings
extends RefCounted

## Qualite graphique (ecran des parametres, GameState.graphics_quality) :
## quels effets d'eclairage de l'environnement sont actifs, et quel
## anticrenelage recoit chaque vue. Purement visuel.
##
## Les environnements (tracks/*.tres) decrivent le rendu COMPLET : reflets
## (SSR), eclairage indirect (SSIL), occlusion ambiante (SSAO). Ici, on en
## retire selon la qualite choisie et le nombre de vues de l'ecran partage :
##
##   HAUTE    SSR + SSIL + SSAO, MSAA 2x ; l'eclairage indirect (le plus
##            couteux) est coupe au-dela de SSIL_MAX_VIEWS vues
##   MOYENNE  SSAO seul, MSAA 2x
##   BASSE    aucun effet, anticrenelage FXAA (le moins couteux)

enum Quality { HIGH, MEDIUM, LOW }

const NAMES: PackedStringArray = ["haute", "moyenne", "basse"]
## Au-dela, l'eclairage indirect est coupe meme en qualite haute.
const SSIL_MAX_VIEWS := 2
## Au-dela, les reflets sont coupes meme en qualite haute.
const SSR_MAX_VIEWS := 4


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
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED


## Plein ecran sans bordure <-> fenetre (F11).
static func toggle_fullscreen() -> void:
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
