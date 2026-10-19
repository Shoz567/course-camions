class_name LoadingScreen
extends CanvasLayer

## Ecran de chargement (2026-10-17 : « un ecran de chargement tant que tout
## n'est pas charge », AVANT le depart, jamais en pleine course). Charte
## arcade neon (UiKit). Il vit a la racine de l'arbre, au-dessus des scenes,
## et traverse le changement de scene :
##   1. CHARGEMENT : la scene de course se charge dans un thread
##      (ResourceLoader.load_threaded_request) ; la barre suit sa progression,
##      l'image ne gele pas (le reseau continue d'etre servi) ;
##   2. PREPARATION : la course est posee sous l'ecran ; il reste tant qu'elle
##      n'est pas prete (scene.loading_done() : modeles, carrosseries,
##      prechauffe des effets), puis SETTLE_FRAMES images de rendu ;
##   3. l'ecran s'efface en fondu et libere le depart (scene.release_start()) :
##      hors ligne, le compte a rebours ne part qu'a ce moment.
## En headless (tests), pas d'ecran : changement de scene direct.

signal finished

enum Step { LOADING, PREPARING, FADING }

## Images rendues apres « pret » avant de s'effacer : les premieres images de
## la course (compilation des materiaux vus pour la premiere fois) restent
## sous l'ecran.
const SETTLE_FRAMES := 20
## Au-dela, on s'efface quoi qu'il arrive (s) : jamais bloque sur un ecran.
const MAX_PREPARE_S := 12.0
const FADE_S := 0.35
const TIPS: PackedStringArray = [
	"Le frein à main (Croix ou R1) fait déraper la remorque : prenez les virages en glisse.",
	"Larguez la remorque (Triangle) devant un poursuivant : elle reste sur la piste.",
	"La nitro (Carré) se recharge en 6 s : gardez-la pour la sortie des virages.",
	"Un baril explosif fait voler les camions… et leurs pièces.",
	"Sans remorque, le tracteur file 20 % plus vite.",
	"Paramètres → Réaffecter la manette : chaque bouton se change.",
]

static var _current: LoadingScreen

var path: String = ""
var step: Step = Step.LOADING
var progress: float = 0.0
var _scene: Node
var _settle: int = 0
var _prepare_s: float = 0.0
var _fade: float = 0.0
var _root: Control
var _bar_fill: Panel
var _bar_w: float = 0.0
var _status: Label
var _tip: Label
var _time: float = 0.0
## Travail de preparation, sur le thread principal par tranches de SLICE_MS par
## image pendant le chargement (l'ecran reste anime) : gabarits des camions et
## des remorques de la course, puis leurs carrosseries deformables (~0,5 s par
## modele a la premiere course). Un thread n'y gagne rien : ces lectures de
## maillages attendent le thread principal a chaque appel.
## ~10 images/s : l'ecran reste vivant, et le rendu entre deux tranches ne
## double pas l'attente (a 25 ms, 12 s au lieu de 7 a 4 joueurs).
const SLICE_MS := 90
var _queue: Array = []
var _items: int = 0
var _items_done: int = 0


## Vrai tant qu'un ecran de chargement couvre la scene (la course attend).
static func covering() -> bool:
	return _current != null and is_instance_valid(_current) and _current.step != Step.FADING


## Charge `scene_path` derriere l'ecran de chargement, puis y entre.
static func go(tree: SceneTree, scene_path: String) -> LoadingScreen:
	if DisplayServer.get_name() == "headless":
		tree.change_scene_to_file(scene_path)
		return null
	if _current != null and is_instance_valid(_current):
		_current.queue_free()
	var s := LoadingScreen.new()
	s.path = scene_path
	_current = s
	tree.root.add_child(s)
	return s


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_start_models()
	if ResourceLoader.load_threaded_request(path, "PackedScene", true) != OK:
		# chargement direct en dernier recours
		get_tree().change_scene_to_file(path)
		step = Step.PREPARING
		_status.text = "PRÉPARATION DE LA PISTE…"


func _exit_tree() -> void:
	if _current == self:
		_current = null


func _process(delta: float) -> void:
	_time += delta
	_tip.text = TIPS[int(_time / 4.0) % TIPS.size()]
	match step:
		Step.LOADING:
			var p := []
			var st := ResourceLoader.load_threaded_get_status(path, p)
			_work()
			if not p.is_empty():
				# scene : 0 .. 0,25 ; camions : 0,25 .. 0,7
				_set_progress(0.25 * float(p[0]) + 0.45 * float(_items_done) / maxf(_items, 1))
			if st == ResourceLoader.THREAD_LOAD_LOADED and not _queue.is_empty():
				pass
			elif st == ResourceLoader.THREAD_LOAD_LOADED:
				var packed := ResourceLoader.load_threaded_get(path) as PackedScene
				_set_progress(0.72)
				_status.text = "PRÉPARATION DE LA PISTE…"
				step = Step.PREPARING
				# la course se construit dans cet appel (modeles, carrosseries) :
				# l'ecran reste affiche, l'image du dessus ne bouge plus un instant
				get_tree().change_scene_to_packed(packed)
			elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				push_warning("LoadingScreen : %s illisible, chargement direct" % path)
				step = Step.PREPARING
				get_tree().change_scene_to_file(path)
		Step.PREPARING:
			_prepare_s += delta
			_scene = get_tree().current_scene
			var done := _scene != null and _scene.is_node_ready() \
					and (not _scene.has_method("loading_done") or bool(_scene.call("loading_done")))
			if done:
				_settle += 1
				_set_progress(lerpf(0.85, 1.0, float(_settle) / SETTLE_FRAMES))
				_status.text = "EN PISTE !"
			else:
				_set_progress(minf(progress + delta * 0.08, 0.84))
			if _settle >= SETTLE_FRAMES or _prepare_s > MAX_PREPARE_S:
				step = Step.FADING
				if _scene != null and _scene.has_method("release_start"):
					_scene.call("release_start")
		Step.FADING:
			_fade += delta / FADE_S
			_root.modulate.a = 1.0 - clampf(_fade, 0.0, 1.0)
			if _fade >= 1.0:
				finished.emit()
				queue_free()


## File de preparation de la course : un modele par joueur (LocalRace.MODELS)
## et sa remorque choisie.
func _start_models() -> void:
	var consts: Dictionary = (load("res://dev/local_race.gd") as GDScript).get_script_constant_map()
	var all: PackedStringArray = consts.get("MODELS", PackedStringArray())
	var n := clampi(GameState.requested_players, 1, maxi(all.size(), 1))
	for i in mini(n, all.size()):
		if not _queue.has([all[i], false]):
			_queue.append([all[i], false])
		var t := TrailerCatalog.at(GameState.trailer_choice[i] if i < GameState.trailer_choice.size() else 0)
		if t != null and t.model != "" and not _queue.has([t.model, true]):
			_queue.append([t.model, true])
	_items = _queue.size() * 4


## Une tranche : des elements de la file jusqu'a SLICE_MS. Un gabarit
## ([chemin, remorque ?]) se lit (ou sort du cache) et ajoute ses maillages ;
## un maillage se prepare.
func _work() -> void:
	var t0 := Time.get_ticks_msec()
	while not _queue.is_empty() and Time.get_ticks_msec() - t0 < SLICE_MS:
		var item: Variant = _queue.pop_front()
		_items_done += 1
		if item is Mesh:
			BodyDamage.prewarm_mesh(item as Mesh)
			continue
		var ps := TruckVisual.template_for(String(item[0]), bool(item[1]))
		if ps == null:
			continue
		var inst := ps.instantiate() as Node3D
		# remorque d'origine du modele : cachee en course (celle du catalogue
		# la remplace), rien a preparer
		var own := inst.get_node_or_null(NodePath(TruckVisual.TRAILER_PIVOT))
		if own != null:
			own.free()
		var meshes := BodyDamage.detached_meshes(inst)
		inst.free()
		_items += meshes.size() - 3
		_queue.append_array(meshes)

func _set_progress(v: float) -> void:
	progress = clampf(maxf(progress, v), 0.0, 1.0)
	if _bar_fill != null:
		_bar_fill.size.x = maxf(_bar_w * progress, 1.0)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var bg := TextureRect.new()
	var tex := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.025, 0.07))
	g.set_color(1, Color(0.07, 0.02, 0.12))
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(1, 1)
	bg.texture = tex
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	# logo, comme l'accueil : CRAZY blanc, WHEELS or, ombre rose
	for pair: Array in [["CRAZY", UiKit.TEXT, Vector2(64, 40)], ["WHEELS", UiKit.GOLD, Vector2(120, 120)]]:
		var l := UiKit.label(String(pair[0]), 96, pair[1] as Color, 900)
		l.add_theme_color_override("font_shadow_color", Color(UiKit.PINK, 0.9))
		l.add_theme_constant_override("shadow_offset_x", 6)
		l.add_theme_constant_override("shadow_offset_y", 6)
		l.position = pair[2] as Vector2
		_root.add_child(l)
	# circuit et categorie
	var t: Dictionary = GameStateNode.TRACKS[clampi(GameState.selected_track, 0, GameStateNode.TRACKS.size() - 1)]
	var c: Dictionary = GameStateNode.SPEED_CLASSES[clampi(GameState.speed_class, 0, GameStateNode.SPEED_CLASSES.size() - 1)]
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_left = 64
	box.offset_right = -64
	box.offset_top = -330
	box.offset_bottom = -60
	box.add_theme_constant_override("separation", 12)
	_root.add_child(box)
	box.add_child(UiKit.section("Prochaine course"))
	box.add_child(UiKit.label(String(t["name"]).to_upper(), 64, UiKit.TEXT, 900))
	var tag := String(t["tagline"])
	box.add_child(UiKit.label("%s  ·  %s %s  ·  4 tours" % [tag.left(1).to_upper() + tag.substr(1), c["cc"],
		String(c["name"]).to_upper()], 22, UiKit.CYAN, 700))
	box.add_child(UiKit.gap(10))
	# barre inclinee : fond nuit, remplissage rose
	var bar := Panel.new()
	bar.custom_minimum_size = Vector2(0, 26)
	bar.add_theme_stylebox_override("panel", UiKit.box(Color(UiKit.TILE, 0.95), Color(1, 1, 1, 0.12), 1))
	box.add_child(bar)
	_bar_fill = Panel.new()
	_bar_fill.add_theme_stylebox_override("panel", UiKit.box(UiKit.PINK, Color(1, 1, 1, 0.3), 1, UiKit.SKEW, 3,
		Color(UiKit.PINK, 0.5), 12))
	_bar_fill.position = Vector2(3, 3)
	_bar_fill.size = Vector2(1, 20)
	bar.add_child(_bar_fill)
	bar.resized.connect(func() -> void:
		_bar_w = bar.size.x - 6.0
		_set_progress(progress))
	var row := HBoxContainer.new()
	box.add_child(row)
	_status = UiKit.label("CHARGEMENT…", 24, UiKit.GOLD, 900)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_status)
	_tip = UiKit.label(TIPS[0], 20, UiKit.DIM, 600, false)
	box.add_child(_tip)
