class_name DebugDrawNode
extends Node

## Overlay de debug 3D : primitives de trace.
##
## Autoload `DebugDraw`. Usage, depuis n'importe quel _physics_process :
##
##   DebugDraw.line(hub, contact_point, Color.CYAN, DebugDraw.CH_SUSPENSION)
##   DebugDraw.arrow(contact_point, tire_force * 0.001, Color.RED, DebugDraw.CH_FORCES)
##   DebugDraw.point(truck.global_transform * com, 0.2, Color.YELLOW, DebugDraw.CH_COM)
##   DebugDraw.polyline(racing_line, false, Color.GREEN, DebugDraw.CH_TRACK)
##
## Trois regles de conception :
##
## 1. AUCUNE ALLOCATION a l'appel. Ces fonctions sont appelees depuis
##    _physics_process, ou CLAUDE.md §5 interdit d'allouer. Les segments vivent
##    dans des tableaux pre-alloues UNE fois (capacite MAX_SEGMENTS). Au-dela,
##    les segments sont ignores et comptes dans dropped_count() — jamais de
##    reallocation.
##
## 2. CHAQUE TRACE EST DESACTIVABLE (CLAUDE.md §6) : par canal
##    (set_channel_enabled) ou d'un coup (enabled). Un canal coupe coute un
##    test de dictionnaire, rien d'autre.
##
## 3. DUREE EN TICKS, pas en secondes (CLAUDE.md §7). Par defaut un trace vit
##    1 tick : il faut le redessiner a chaque tick, ce qui est le cas normal
##    pour un centre de masse ou un couple. `duration_ticks` > 1 sert a garder
##    une trace (un choc, une sortie de piste).
##
##    Chaque trace memorise le tick physique ou il EXPIRE (compteur
##    Engine.get_physics_frames()), et l'expiration compare a ce compteur. Le
##    resultat ne depend donc pas de l'ordre d'execution entre DebugDraw et les
##    noeuds qui dessinent. Premiere version : un simple compte a rebours
##    decremente au debut du tick — un noeud qui dessinait AVANT DebugDraw
##    voyait ses traces effacees avant meme d'etre rendus (capture d'ecran
##    vide, tests headless pourtant verts).
##
## Le rendu est un ImmediateMesh reconstruit a chaque frame, dessine par-dessus
## la scene (sans test de profondeur). En headless, rien n'est rendu, mais la
## logique tourne a l'identique — c'est ce qui la rend testable.

## Capacite fixe. 4096 segments couvrent largement 4 camions : par camion,
## 4 rayons de suspension, 4 x 2 fleches de force de pneu (6 segments chacune),
## le centre de masse (3), soit ~60 segments ; plus les traces de piste.
const MAX_SEGMENTS := 4096

## Canaux predefinis. N'importe quel StringName peut servir de canal ; un canal
## jamais configure est actif.
const CH_GENERAL := &"general"
const CH_SUSPENSION := &"suspension"   # rayons de suspension, points de contact
const CH_FORCES := &"forces"           # forces de pneu : traction, adherence laterale
const CH_COM := &"com"                 # centre de masse du camion
const CH_TRACK := &"track"             # trajectoire, checkpoints, ligne de course

## Interrupteur global. Actif par defaut en build de debug uniquement.
var enabled: bool = OS.is_debug_build()

var _starts: PackedVector3Array = PackedVector3Array()
var _ends: PackedVector3Array = PackedVector3Array()
var _colors: PackedColorArray = PackedColorArray()
var _expires: PackedInt64Array = PackedInt64Array()   # tick physique d'expiration
var _count: int = 0
var _dropped: int = 0
var _warned_overflow: bool = false

var _channels: Dictionary = {}   # StringName -> bool ; absent = actif

var _mesh: ImmediateMesh
var _material: StandardMaterial3D
var _render: bool = false


func _init() -> void:
	# Seule allocation du module, une fois pour toutes.
	_starts.resize(MAX_SEGMENTS)
	_ends.resize(MAX_SEGMENTS)
	_colors.resize(MAX_SEGMENTS)
	_expires.resize(MAX_SEGMENTS)


func _ready() -> void:
	_mesh = ImmediateMesh.new()
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.no_depth_test = true

	_render = DisplayServer.get_name() != "headless"
	if _render:
		var mi := MeshInstance3D.new()
		mi.name = "DebugDrawMesh"
		mi.mesh = _mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


# --- primitives --------------------------------------------------------------

## Segment de `a` a `b`.
func line(a: Vector3, b: Vector3, color: Color = Color.WHITE,
		channel: StringName = CH_GENERAL, duration_ticks: int = 1) -> void:
	if not _accepts(channel):
		return
	_push(a, b, color, duration_ticks)


## Fleche de `origin` a `origin + vector` (3 segments). Pour un couple ou une
## force, passer le vecteur deja mis a l'echelle.
func arrow(origin: Vector3, vector: Vector3, color: Color = Color.WHITE,
		channel: StringName = CH_GENERAL, duration_ticks: int = 1) -> void:
	if not _accepts(channel):
		return
	var length := vector.length()
	if length < 1e-6:
		return
	var dir := vector / length
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		side = dir.cross(Vector3.RIGHT)
	side = side.normalized()
	var tip := origin + vector
	var head := length * 0.2
	_push(origin, tip, color, duration_ticks)
	_push(tip, tip - dir * head + side * head * 0.5, color, duration_ticks)
	_push(tip, tip - dir * head - side * head * 0.5, color, duration_ticks)


## Croix a trois axes centree sur `p` (3 segments).
func point(p: Vector3, size: float = 0.05, color: Color = Color.WHITE,
		channel: StringName = CH_GENERAL, duration_ticks: int = 1) -> void:
	if not _accepts(channel):
		return
	var h := size * 0.5
	_push(p - Vector3(h, 0.0, 0.0), p + Vector3(h, 0.0, 0.0), color, duration_ticks)
	_push(p - Vector3(0.0, h, 0.0), p + Vector3(0.0, h, 0.0), color, duration_ticks)
	_push(p - Vector3(0.0, 0.0, h), p + Vector3(0.0, 0.0, h), color, duration_ticks)


## Ligne brisee. `closed` relie le dernier point au premier (polygone).
## Le tableau appartient a l'appelant : garde-le en cache pour ne pas allouer.
func polyline(points: PackedVector3Array, closed: bool = false, color: Color = Color.WHITE,
		channel: StringName = CH_GENERAL, duration_ticks: int = 1) -> void:
	if not _accepts(channel):
		return
	var n := points.size()
	if n < 2:
		return
	for i in n - 1:
		_push(points[i], points[i + 1], color, duration_ticks)
	if closed and n > 2:
		_push(points[n - 1], points[0], color, duration_ticks)


# --- controle ----------------------------------------------------------------

func set_channel_enabled(channel: StringName, on: bool) -> void:
	_channels[channel] = on


func is_channel_enabled(channel: StringName) -> bool:
	return _channels.get(channel, true)


## Efface toutes les traces en cours.
func clear() -> void:
	_count = 0


## Nombre de segments actuellement en file.
func segment_count() -> int:
	return _count


## Segments ignores faute de place depuis le demarrage.
func dropped_count() -> int:
	return _dropped


# --- boucle ------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	# Retire les traces expires et compacte sur place, sans allouer. Un trace
	# pose a ce tick-ci expire au plus tot au suivant : peu importe que ce
	# noeud passe avant ou apres ceux qui dessinent.
	var now := Engine.get_physics_frames()
	var kept := 0
	for i in _count:
		if _expires[i] > now:
			if kept != i:
				_starts[kept] = _starts[i]
				_ends[kept] = _ends[i]
				_colors[kept] = _colors[i]
				_expires[kept] = _expires[i]
			kept += 1
	_count = kept


func _process(_delta: float) -> void:
	if _render:
		build_mesh()


## Reconstruit le maillage de rendu. Retourne le nombre de sommets emis.
## Public pour les tests ; appele automatiquement quand il y a un rendu.
func build_mesh() -> int:
	_mesh.clear_surfaces()
	if _count == 0 or not enabled:
		return 0
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _material)
	for i in _count:
		_mesh.surface_set_color(_colors[i])
		_mesh.surface_add_vertex(_starts[i])
		_mesh.surface_set_color(_colors[i])
		_mesh.surface_add_vertex(_ends[i])
	_mesh.surface_end()
	return _count * 2


# --- interne -----------------------------------------------------------------

func _accepts(channel: StringName) -> bool:
	return enabled and _channels.get(channel, true)


func _push(a: Vector3, b: Vector3, color: Color, duration_ticks: int) -> void:
	if _count >= MAX_SEGMENTS:
		_dropped += 1
		if not _warned_overflow:
			_warned_overflow = true
			push_warning("DebugDraw : capacite de %d segments atteinte, traces ignores" % MAX_SEGMENTS)
		return
	_starts[_count] = a
	_ends[_count] = b
	_colors[_count] = color
	_expires[_count] = Engine.get_physics_frames() + maxi(1, duration_ticks)
	_count += 1
