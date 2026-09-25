class_name PhysicsTest
extends Node3D

## Socle commun des scenes de test physique headless (CLAUDE.md §10).
##
## Une scene de test herite de cette classe et surcharge trois crochets :
##
##   _test_setup()    une fois, avant le premier tick : construire la scene et
##                    prendre les mesures de reference "au tick 0".
##   _test_tick(t)    a chaque tick physique, t = 1 .. duration_ticks.
##   _test_finish()   une fois, au dernier tick : poser les verifications.
##
## Le socle se charge du reste : compter en ticks (jamais en temps reel, cf.
## CLAUDE.md §7), lire baseline.json, afficher chaque mesure avec sa valeur, et
## sortir avec le bon code.
##
## Codes de sortie, lus par tests/cli_runner.gd :
##   0   PASS  toutes les verifications passent
##   1   FAIL  au moins une echoue, ou aucune n'a ete posee
##   77  SKIP  une valeur de reference manque dans baseline.json
##
## Chaque scene se termine par une ligne "RESULT PASS|FAIL|SKIP". Le runner
## EXIGE cette ligne : un script qui plante sans conclure n'est jamais compte
## comme reussi, meme si Godot sort en code 0.
##
## Exemple minimal :
##
##   extends PhysicsTest
##
##   var _head_y0: float
##
##   func _test_setup() -> void:
##       duration_ticks = 600
##       _head_y0 = $Character.get_bone_body(&"head").global_position.y
##
##   func _test_finish() -> void:
##       var head_y: float = $Character.get_bone_body(&"head").global_position.y
##       check_ratio_above("tete debout apres 10 s", head_y, _head_y0, 0.92)

const EXIT_PASS := 0
const EXIT_FAIL := 1
const EXIT_SKIP := 77

const BASELINE_PATH := "res://tests/baseline.json"

## Duree du test en ticks physiques (60 par seconde). Modifiable dans
## _test_setup().
@export var duration_ticks: int = 600

## Tick physique courant : 0 pendant _test_setup(), puis 1 .. duration_ticks.
var tick: int = 0

var _check_count: int = 0
var _fail_count: int = 0
var _skip_reason: String = ""
var _done: bool = false

static var _baseline: Dictionary = {}
static var _baseline_loaded: bool = false


# --- crochets a surcharger ---------------------------------------------------

func _test_setup() -> void:
	pass


func _test_tick(_t: int) -> void:
	pass


func _test_finish() -> void:
	pass


# --- boucle ------------------------------------------------------------------

func _ready() -> void:
	_test_setup()
	if _done:
		return
	print("TEST %s  duree=%d ticks" % [scene_file_path.get_file(), duration_ticks])


func _physics_process(_delta: float) -> void:
	if _done:
		return
	tick += 1
	_test_tick(tick)
	if _done:
		return
	if tick >= duration_ticks:
		_test_finish()
		_conclude()


# --- verifications -----------------------------------------------------------

## Verification brute. `detail` doit contenir la valeur mesuree : sur un jeu
## physique, un PASS sans son nombre ne vaut rien.
func check(label: String, ok: bool, detail: String = "") -> bool:
	_check_count += 1
	if not ok:
		_fail_count += 1
	print("  CHECK  %-36s %s -> %s" % [label, detail, "PASS" if ok else "FAIL"])
	return ok


## `measured` a +/- `tolerance` de `expected`. Jamais d'egalite exacte sur une
## valeur physique (CLAUDE.md §10) : la tolerance est obligatoire.
func check_near(label: String, measured: float, expected: float, tolerance: float) -> bool:
	var ok := is_finite(measured) and absf(measured - expected) <= tolerance
	return check(label, ok, "mesure=%.4f attendu=%.4f +/-%.4f" % [measured, expected, tolerance])


func check_above(label: String, measured: float, threshold: float) -> bool:
	var ok := is_finite(measured) and measured > threshold
	return check(label, ok, "mesure=%.4f seuil>%.4f" % [measured, threshold])


func check_below(label: String, measured: float, threshold: float) -> bool:
	var ok := is_finite(measured) and measured < threshold
	return check(label, ok, "mesure=%.4f seuil<%.4f" % [measured, threshold])


## Critere en ratio par rapport a une reference mesuree dans la scene elle-meme
## (CLAUDE.md §10, regle a). C'est la forme a privilegier.
func check_ratio_above(label: String, measured: float, reference: float, min_ratio: float) -> bool:
	if not is_finite(reference) or absf(reference) < 1e-9:
		return check(label, false, "reference invalide (%.4f)" % reference)
	var ratio := measured / reference
	var ok := is_finite(ratio) and ratio >= min_ratio
	return check(label, ok, "mesure=%.4f ref=%.4f ratio=%.3f seuil>=%.3f"
		% [measured, reference, ratio, min_ratio])


## Detecte les NaN et les infinis : le symptome d'un solveur qui a explose.
func check_finite(label: String, v: Vector3) -> bool:
	return check(label, v.is_finite(), "valeur=%s" % v)


# --- arrets anticipes --------------------------------------------------------

## Saute le test, explicitement. A utiliser quand une donnee de reference
## manque : un test qui inventerait son seuil ne mesurerait rien.
func skip(reason: String) -> void:
	if _done:
		return
	_skip_reason = reason
	_conclude()


## Echec immediat, sans attendre la fin (solveur explose, noeud introuvable...).
func abort(reason: String) -> void:
	if _done:
		return
	_fail_count += 1
	print("  ABORT  %s" % reason)
	_conclude()


# --- baseline.json -----------------------------------------------------------

## Valeur de reference, ou null si absente ou pas encore mesuree.
func baseline(key: String) -> Variant:
	_load_baseline()
	return _baseline.get(key)


## Comme baseline(), mais SAUTE le test si la valeur est null. C'est la regle de
## CLAUDE.md §10 : les tests qui dependent d'une valeur pas encore calibree (les
## impulsions, par exemple) se sautent au lieu de prendre un defaut.
func require_baseline(key: String) -> Variant:
	var v: Variant = baseline(key)
	if v == null:
		skip("baseline.json : '%s' vaut null (pas encore mesure)" % key)
	return v


static func _load_baseline() -> void:
	if _baseline_loaded:
		return
	_baseline_loaded = true
	var f := FileAccess.open(BASELINE_PATH, FileAccess.READ)
	if f == null:
		push_warning("PhysicsTest : %s introuvable" % BASELINE_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_baseline = parsed as Dictionary
	else:
		push_warning("PhysicsTest : %s n'est pas un objet JSON valide" % BASELINE_PATH)


# --- utilitaires de scene ----------------------------------------------------

## Sol statique dont la surface est a y = 0.
func add_floor(size: float = 40.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Floor"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size, 0.4, size)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0.0, -0.2, 0.0)
	add_child(body)
	return body


# --- conclusion --------------------------------------------------------------

func _conclude() -> void:
	if _done:
		return
	_done = true

	var code := EXIT_PASS
	if _skip_reason != "":
		code = EXIT_SKIP
		print("RESULT SKIP  %s" % _skip_reason)
	elif _fail_count > 0:
		code = EXIT_FAIL
		print("RESULT FAIL  %d/%d verification(s) en echec, tick %d"
			% [_fail_count, _check_count, tick])
	elif _check_count == 0:
		# Un test qui ne verifie rien n'est pas un test.
		code = EXIT_FAIL
		print("RESULT FAIL  aucune verification posee")
	else:
		print("RESULT PASS  %d verification(s), tick %d" % [_check_count, tick])

	get_tree().quit(code)
