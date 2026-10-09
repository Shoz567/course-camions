class_name DynamicResolution
extends Node

## Resolution dynamique (2026-10-09, « continue l'optimisation pour les
## petites configurations avec GPU integre en conservant le plus possible les
## graphismes ») : tous les effets restent ; seule la resolution de la 3D
## baisse, et seulement quand la carte graphique ne tient plus 60 images/s.
## L'image est alors remise a la taille de l'ecran par FSR 1 (mise a
## l'echelle avec accentuation des contours) ; l'interface (HUD, menus) reste
## a pleine resolution.
##
## Mesure (RTX 5060 Ti, Cyber City, qualite moyenne, 1080p) : 3D a 77 % ->
## -27 % de temps de rendu, a 67 % -> -39 % ; aucun autre reglage n'en
## approche (SSAO ou ombres en qualite reduite : moins de 2 %). Sur une puce
## integree, limitee par le nombre de pixels a remplir, l'ecart est plus grand.
##
## Toutes les VIEW_WINDOW secondes : temps GPU moyen de toutes les vues
## (fenetre + cases de l'ecran partage). Au-dessus du budget, l'echelle
## descend d'un coup a la valeur estimee (cout proportionnel au nombre de
## pixels) ; nettement en dessous, elle remonte d'un palier, au plus toutes
## les RAISE_HOLD secondes : chaque changement realloue les tampons de rendu,
## d'ou des paliers de SCALE_STEP plutot qu'un reglage continu.
## Une carte qui tient le budget reste a 100 %, sans FSR.

## Vues de l'ecran partage a suivre (GraphicsSettings.apply_viewport) ; la
## fenetre principale est toujours suivie.
const GROUP := &"dynamic_resolution_views"
## Budget du temps GPU par image : 60 images/s avec 15 % de marge.
const TARGET_MS := 1000.0 / 60.0 * 0.85
## En dessous de RAISE_RATIO x budget, l'echelle peut remonter.
const RAISE_RATIO := 0.7
const MIN_SCALE := 0.6
const SCALE_STEP := 0.05
const VIEW_WINDOW := 0.5
const RAISE_HOLD := 2.0

## Echelle 3D appliquee (1.0 = pleine resolution).
var scale: float = 1.0
## Budget GPU vise (ms) ; TARGET_MS sauf pour une mesure.
var target_ms: float = TARGET_MS

var _gpu_sum: float = 0.0
var _frames: int = 0
var _wait: float = VIEW_WINDOW
var _since_change: float = 0.0
var _measured: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	var views := _views()
	if not GameState.dynamic_resolution:
		if scale != 1.0:
			set_scale(1.0, views)
		return
	_since_change += delta
	var gpu := 0.0
	for vp in views:
		# case de l'ecran partage creee depuis le dernier changement
		if absf(vp.scaling_3d_scale - (scale if scale < 0.999 else 1.0)) > 0.001:
			apply_to(vp, scale)
		var rid := vp.get_viewport_rid()
		if not _measured.has(rid):
			_measured[rid] = true
			RenderingServer.viewport_set_measure_render_time(rid, true)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	_gpu_sum += gpu
	_frames += 1
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = VIEW_WINDOW
	var avg := _gpu_sum / maxi(_frames, 1)
	_gpu_sum = 0.0
	_frames = 0
	var next := next_scale(scale, avg, _since_change, target_ms)
	if next != scale:
		set_scale(next, views)


## Echelle suivante pour un temps GPU moyen `gpu_ms` mesure a l'echelle
## `current`, `since_change` secondes apres le dernier changement. 0 ms (pas
## de mesure : rendu factice, premiere image) ne change rien.
static func next_scale(current: float, gpu_ms: float, since_change: float,
		target_ms: float = TARGET_MS) -> float:
	if gpu_ms <= 0.0:
		return current
	if gpu_ms > target_ms:
		# cout ~ pixels ~ echelle au carre ; arrondi au palier inferieur
		var want := current * sqrt(target_ms / gpu_ms)
		return clampf(floorf(want / SCALE_STEP + 0.001) * SCALE_STEP, MIN_SCALE, current)
	if current < 1.0 and since_change >= RAISE_HOLD and gpu_ms < target_ms * RAISE_RATIO:
		var up := minf(current + SCALE_STEP, 1.0)
		# pas de remontee qui repasserait au-dessus du budget
		if gpu_ms * (up * up) / (current * current) < target_ms:
			return up
	return current


## Applique l'echelle `s` a `views` : FSR 1 en dessous de 100 %, rien au-dessus.
func set_scale(s: float, views: Array[Viewport]) -> void:
	scale = s
	_since_change = 0.0
	for vp in views:
		apply_to(vp, s)


static func apply_to(vp: Viewport, s: float) -> void:
	var full := s >= 0.999
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR if full else Viewport.SCALING_3D_MODE_FSR
	vp.scaling_3d_scale = 1.0 if full else s


func _views() -> Array[Viewport]:
	var out: Array[Viewport] = [get_viewport()]
	for n in get_tree().get_nodes_in_group(GROUP):
		out.append(n as Viewport)
	return out
