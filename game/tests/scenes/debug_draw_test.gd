extends PhysicsTest

## Test des primitives de DebugDraw. Logique pure : en headless
## rien n'est rendu, mais la file de segments se comporte a l'identique.
##
## Expiration : ce qui compte est ce qui est present AU RENDU (_process). Un
## trace de N ticks pose au tick P doit etre visible aux rendus qui suivent les
## ticks P .. P+N-1, et absent apres le tick P+N.
##
## Le rendu reel a ete verifie a part, sur une capture d'ecran : polygone,
## croix et fleches visibles, couleurs exactes au pixel pres.
##
## Ce noeud dessine volontairement AVANT l'autoload (priorite physique -100) :
## c'est l'ordre defavorable. La premiere version de DebugDraw y effacait les
## traces d'un tick avant leur rendu — invisible dans un test ou l'autoload
## passait en premier, visible seulement sur une vraie capture d'ecran.

const EXPIRY := &"test_expiry"

## Tick de pose des traces. Pas le tick 1 : au demarrage, Godot enchaine
## plusieurs ticks physiques sans rendu entre eux pour rattraper le temps de
## chargement, et les premiers ticks n'ont donc pas tous leur _process. Mesure
## faite : poser au tick 1 laissait les decalages 0 et 1 sans aucun rendu.
const PUSH_TICK := 30

var _push_frame: int = -1
var _visible_at: Dictionary = {}   # decalage en ticks depuis le trace -> segments au rendu


func _test_setup() -> void:
	duration_ticks = PUSH_TICK + 10
	process_physics_priority = -100
	DebugDraw.enabled = true

	# --- nombre de segments par primitive ----------------------------------
	_expect_segments("line = 1 segment", 1, func() -> void:
		DebugDraw.line(Vector3.ZERO, Vector3.UP))
	_expect_segments("arrow = 3 segments", 3, func() -> void:
		DebugDraw.arrow(Vector3.ZERO, Vector3(0.0, 0.0, 1.0)))
	_expect_segments("arrow verticale = 3 segments", 3, func() -> void:
		DebugDraw.arrow(Vector3.ZERO, Vector3.UP))
	_expect_segments("arrow nulle = 0 segment", 0, func() -> void:
		DebugDraw.arrow(Vector3.ZERO, Vector3.ZERO))
	_expect_segments("point = 3 segments", 3, func() -> void:
		DebugDraw.point(Vector3.ONE))
	var square := PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)])
	_expect_segments("polyline fermee (4 pts) = 4", 4, func() -> void:
		DebugDraw.polyline(square, true))
	_expect_segments("polyline ouverte (4 pts) = 3", 3, func() -> void:
		DebugDraw.polyline(square, false))

	# --- interrupteurs -----------------------------------------------------
	DebugDraw.set_channel_enabled(DebugDraw.CH_FORCES, false)
	_expect_segments("canal coupe : rien n'est ajoute", 0, func() -> void:
		DebugDraw.arrow(Vector3.ZERO, Vector3.UP, Color.RED, DebugDraw.CH_FORCES))
	_expect_segments("autre canal toujours actif", 1, func() -> void:
		DebugDraw.line(Vector3.ZERO, Vector3.UP, Color.RED, DebugDraw.CH_COM))
	DebugDraw.set_channel_enabled(DebugDraw.CH_FORCES, true)

	DebugDraw.enabled = false
	_expect_segments("interrupteur global coupe", 0, func() -> void:
		DebugDraw.line(Vector3.ZERO, Vector3.UP))
	DebugDraw.enabled = true

	# --- maillage ----------------------------------------------------------
	DebugDraw.clear()
	DebugDraw.polyline(square, true)
	check("build_mesh : 2 sommets par segment", DebugDraw.build_mesh() == 8,
		"sommets=%d pour %d segments" % [DebugDraw.build_mesh(), DebugDraw.segment_count()])

	# --- capacite fixe -----------------------------------------------------
	DebugDraw.clear()
	var dropped_before := DebugDraw.dropped_count()
	for i in DebugDraw.MAX_SEGMENTS + 10:
		DebugDraw.line(Vector3.ZERO, Vector3.UP)
	check("capacite plafonnee", DebugDraw.segment_count() == DebugDraw.MAX_SEGMENTS,
		"segments=%d max=%d" % [DebugDraw.segment_count(), DebugDraw.MAX_SEGMENTS])
	check("depassement compte", DebugDraw.dropped_count() - dropped_before == 10,
		"ignores=%d attendu=10" % (DebugDraw.dropped_count() - dropped_before))

	DebugDraw.clear()


func _test_tick(t: int) -> void:
	# Un trace de 1 tick et un trace de 5 ticks.
	if t == PUSH_TICK:
		_push_frame = Engine.get_physics_frames()
		DebugDraw.line(Vector3.ZERO, Vector3.UP, Color.WHITE, EXPIRY, 1)
		DebugDraw.line(Vector3.ZERO, Vector3.UP, Color.WHITE, EXPIRY, 5)


func _process(_delta: float) -> void:
	# Etat de la file au moment du rendu, pour chaque tick ecoule.
	if _push_frame >= 0:
		_visible_at[Engine.get_physics_frames() - _push_frame] = DebugDraw.segment_count()


func _test_finish() -> void:
	check("rendu du tick de pose : les 2 traces visibles", _visible_at.get(0) == 2,
		"segments=%s" % _visible_at.get(0))
	check("rendu du tick suivant : le trace de 1 tick a expire", _visible_at.get(1) == 1,
		"segments=%s" % _visible_at.get(1))
	check("5e tick : le trace de 5 ticks encore visible", _visible_at.get(4) == 1,
		"segments=%s" % _visible_at.get(4))
	check("6e tick : le trace de 5 ticks a expire", _visible_at.get(5) == 0,
		"segments=%s" % _visible_at.get(5))


## Vide la file, execute `draw`, et verifie le nombre de segments ajoutes.
func _expect_segments(label: String, expected: int, draw: Callable) -> void:
	DebugDraw.clear()
	draw.call()
	var got := DebugDraw.segment_count()
	check(label, got == expected, "segments=%d attendu=%d" % [got, expected])
