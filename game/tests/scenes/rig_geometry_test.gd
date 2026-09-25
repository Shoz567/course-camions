extends PhysicsTest

## Tache 1.3 — conformite geometrique du rig a docs/RIG_SPEC.md §3-4.
##
## Mesure prise AU REPOS, juste apres le demarrage de la simulation : c'est la
## geometrie du rig qu'on verifie, pas sa tenue (le rig est inerte en 1.1).
## Les valeurs attendues viennent de baseline.json (mesurees au spike S4).
##
## Pourquoi c'est le premier test a passer : un centre de masse faux rend
## l'equilibre IMPOSSIBLE a regler, quels que soient les gains du PD. Le
## chercher ici coute une minute ; le chercher en tunant coute des jours.

const RIG_SCENE := "res://characters/ragdoll/character_ragdoll.tscn"
const TOLERANCE_M := 0.03   # RIG_SPEC.md §4 : +/- 3 cm

var _rig: CharacterRagdoll


func _test_setup() -> void:
	duration_ticks = 2
	add_floor()
	_rig = (load(RIG_SCENE) as PackedScene).instantiate() as CharacterRagdoll
	add_child(_rig)


func _test_finish() -> void:
	# --- structure ---------------------------------------------------------
	var missing: PackedStringArray = []
	for n in CharacterTuning.DRIVEN_BONES:
		if _rig.get_bone(n) == null:
			missing.append(n)
	if _rig.get_bone(CharacterTuning.ROOT_BONE) == null:
		missing.append(CharacterTuning.ROOT_BONE)
	check("13 os physiques presents", missing.is_empty() and _rig.bones.size() == 13,
		"os=%d manquants=%s" % [_rig.bones.size(), str(missing)])

	check_near("masse totale (kg)", _rig.get_total_mass(), 70.0, 0.001)

	# --- geometrie au repos ------------------------------------------------
	var head_expected: Variant = require_baseline("head_y_rest_m")
	var com_expected: Variant = require_baseline("com_y_rest_m")
	if head_expected == null or com_expected == null:
		return
	check_near("hauteur de la tete au repos (m)", _rig.get_head().global_position.y,
		float(head_expected), TOLERANCE_M)
	check_near("centre de masse au repos (m)", _rig.get_center_of_mass().y,
		float(com_expected), TOLERANCE_M)

	# --- symetrie ----------------------------------------------------------
	var com := _rig.get_center_of_mass()
	check_near("centre de masse centre en X (symetrie g/d)", com.x, 0.0, 0.005)

	# --- materiaux (RIG_SPEC.md §6) ----------------------------------------
	# PhysicalBone3D.friction refuse > 1 ; le builder pose 1,2 directement sur le
	# corps via PhysicsServer3D. On lit la valeur REELLE cote serveur.
	var foot_friction := PhysicsServer3D.body_get_param(
		_rig.get_bone(&"foot_l").get_rid(), PhysicsServer3D.BODY_PARAM_FRICTION) as float
	check_near("friction des pieds cote serveur", foot_friction, 1.2, 0.001)

	# --- mains (RIG_SPEC.md §2) --------------------------------------------
	var hand_l := _rig.get_bone(&"forearm_l").get_node_or_null("hand_l")
	var hand_r := _rig.get_bone(&"forearm_r").get_node_or_null("hand_r")
	check("marqueurs hand_l et hand_r presents", hand_l != null and hand_r != null,
		"hand_l=%s hand_r=%s" % [hand_l != null, hand_r != null])
