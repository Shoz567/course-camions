extends PhysicsTest

## Test de la ressource CharacterTuning (tache 1.4). Logique pure, sans rig.
##
## Verifie :
##   - que default_tuning.tres est valide et couvre les 12 articulations ;
##   - que la formule des gains respecte l'amortissement critique ;
##   - que validate() ATTRAPE les erreurs (un validateur jamais vu echouer ne
##     prouve rien) ;
##   - que les noms d'os sont les memes que cote Blender (tools/blender/lib/
##     rig.py) : c'est le contrat de docs/RIG_SPEC.md §2.

const TUNING_PATH := "res://characters/ragdoll/default_tuning.tres"
const RIG_PY := "../tools/blender/lib/rig.py"


func _test_setup() -> void:
	duration_ticks = 1


func _test_finish() -> void:
	var res: Resource = load(TUNING_PATH)
	if not check("default_tuning.tres est un CharacterTuning", res is CharacterTuning,
			"type=%s" % ("null" if res == null else res.get_class())):
		return
	var tuning := res as CharacterTuning

	# --- ressource livree ---------------------------------------------------
	var errors := tuning.validate()
	check("validate() : aucune erreur", errors.is_empty(), "erreurs=%s" % str(errors))

	var missing: PackedStringArray = []
	for name in CharacterTuning.DRIVEN_BONES:
		if tuning.get_bone(name) == null:
			missing.append(name)
	check("les 12 articulations presentes", missing.is_empty(),
		"%d/12, manquantes=%s" % [12 - missing.size(), str(missing)])
	check("pelvis (racine) non pilote", tuning.get_bone(&"pelvis") == null,
		"get_bone(pelvis)=%s" % tuning.get_bone(&"pelvis"))

	# --- formules -----------------------------------------------------------
	# Cuisse : capsule 8 kg, 0,36 m -> I ~ m L^2 / 12.
	var thigh := tuning.get_bone(&"thigh_l")
	var inertia := 8.0 * 0.36 * 0.36 / 12.0
	var kp := thigh.kp(inertia)
	var kd := thigh.kd(inertia)
	var critical := 2.0 * sqrt(kp * inertia)
	check_near("kd = 2*sqrt(kp*I) a damping_ratio 1", kd,
		critical * thigh.damping_ratio, 1e-6)
	check_near("couple max proportionnel a la masse", thigh.max_torque(16.0),
		2.0 * thigh.max_torque(8.0), 1e-6)

	# --- validate() attrape les erreurs --------------------------------------
	check("validate() : articulation manquante detectee",
		_errors_for(_without(tuning, &"head")).size() > 0,
		"erreurs=%s" % str(_errors_for(_without(tuning, &"head"))))
	check("validate() : doublon detecte",
		_errors_for(_with_extra(tuning, &"spine")).size() > 0,
		"erreurs=%s" % str(_errors_for(_with_extra(tuning, &"spine"))))
	check("validate() : racine pilotee detectee",
		_errors_for(_with_extra(tuning, &"pelvis")).size() > 0,
		"erreurs=%s" % str(_errors_for(_with_extra(tuning, &"pelvis"))))
	check("validate() : valeur par defaut (0) refusee",
		_errors_for(_with_blank(tuning, &"forearm_r")).size() > 0,
		"erreurs=%s" % str(_errors_for(_with_blank(tuning, &"forearm_r"))))

	# --- contrat de nommage avec Blender ------------------------------------
	var blender := _read_blender_bones()
	var godot_side: Array[StringName] = CharacterTuning.DRIVEN_BONES.duplicate()
	godot_side.append(CharacterTuning.ROOT_BONE)
	var diff: PackedStringArray = []
	for n in godot_side:
		if not blender.has(n):
			diff.append("%s absent de rig.py" % n)
	for n in blender:
		if not godot_side.has(n):
			diff.append("%s absent de CharacterTuning" % n)
	check("noms d'os identiques a tools/blender/lib/rig.py",
		blender.size() == 13 and diff.is_empty(),
		"rig.py=%d os, ecarts=%s" % [blender.size(), str(diff)])


# --- fabriques de ressources volontairement fausses --------------------------

func _errors_for(t: CharacterTuning) -> PackedStringArray:
	return t.validate()


func _copy(t: CharacterTuning) -> CharacterTuning:
	var c := CharacterTuning.new()
	var list: Array[BoneTuning] = []
	for b in t.bones:
		list.append(b)
	c.bones = list
	return c


func _without(t: CharacterTuning, bone: StringName) -> CharacterTuning:
	var c := _copy(t)
	var list: Array[BoneTuning] = []
	for b in c.bones:
		if b.bone != bone:
			list.append(b)
	c.bones = list
	return c


func _with_extra(t: CharacterTuning, bone: StringName) -> CharacterTuning:
	var c := _copy(t)
	var extra := BoneTuning.new()
	extra.bone = bone
	extra.frequency = 5.0
	extra.damping_ratio = 1.0
	extra.max_torque_per_kg = 5.0
	c.bones.append(extra)
	return c


func _with_blank(t: CharacterTuning, bone: StringName) -> CharacterTuning:
	var c := _without(t, bone)
	var blank := BoneTuning.new()   # tous les reglages a leur defaut : 0
	blank.bone = bone
	c.bones.append(blank)
	return c


## Extrait la liste BONES de rig.py (fichier Python, hors de res://).
func _read_blender_bones() -> Array[StringName]:
	var out: Array[StringName] = []
	var path := ProjectSettings.globalize_path("res://").path_join(RIG_PY)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var text := f.get_as_text()
	var start := text.find("BONES = [")
	var end := text.find("]", start)
	if start < 0 or end < 0:
		return out
	var re := RegEx.new()
	re.compile("\"([a-z_]+)\"")
	for m in re.search_all(text.substr(start, end - start)):
		out.append(StringName(m.get_string(1)))
	return out
