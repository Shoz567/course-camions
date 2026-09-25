class_name CharacterTuning
extends Resource

## Reglages du ragdoll actif (tache 1.4) : un BoneTuning par articulation.
##
## C'est ici, et nulle part ailleurs, que vivent les raideurs, amortissements
## et couples max (CLAUDE.md §5) : un designer doit pouvoir les changer dans
## default_tuning.tres sans toucher au code.
##
## 12 articulations, pas 13 : `pelvis` est la racine du rig, il n'a pas de
## parent, donc pas d'articulation a piloter. Son maintien vertical releve du
## BalanceController (tache 1.7), avec ses propres reglages.
##
## Usage cote JointDriver : recuperer les BoneTuning UNE FOIS dans _ready() et
## garder les references. get_bone() construit un index au premier appel ; ne
## l'appelle pas dans _physics_process (CLAUDE.md §5 : aucune allocation).

## Articulations pilotees par le JointDriver, dans l'ordre de docs/RIG_SPEC.md §2.
## Doit rester coherent avec tools/blender/lib/rig.py (le test
## character_tuning_test le verifie).
const DRIVEN_BONES: Array[StringName] = [
	&"spine", &"head",
	&"upperarm_l", &"forearm_l",
	&"upperarm_r", &"forearm_r",
	&"thigh_l", &"shin_l", &"foot_l",
	&"thigh_r", &"shin_r", &"foot_r",
]

## Racine du rig : jamais pilotee par le JointDriver.
const ROOT_BONE: StringName = &"pelvis"

## Interrupteur de debug global : coupe TOUS les PD d'articulation d'un coup
## (CLAUDE.md §6). Pour en couper un seul, voir BoneTuning.enabled.
@export var joint_drive_enabled: bool = true

## Un BoneTuning par articulation de DRIVEN_BONES.
@export var bones: Array[BoneTuning] = []

var _index: Dictionary = {}


## Reglages d'une articulation, ou null si elle n'est pas dans `bones`.
func get_bone(bone: StringName) -> BoneTuning:
	if _index.is_empty():
		for b in bones:
			if b != null:
				_index[b.bone] = b
	return _index.get(bone) as BoneTuning


## Liste des problemes de coherence. Vide = ressource valide.
## Appelee par le test character_tuning_test, et a appeler par le JointDriver
## dans _ready() (un assert() suffit : c'est un invariant de developpement).
func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	var seen: Dictionary = {}

	for b in bones:
		if b == null:
			errors.append("entree vide dans `bones`")
			continue
		if b.bone == ROOT_BONE:
			errors.append("'%s' est la racine : il n'a pas d'articulation a piloter" % b.bone)
		elif not DRIVEN_BONES.has(b.bone):
			errors.append("'%s' n'est pas un os de docs/RIG_SPEC.md" % b.bone)
		if seen.has(b.bone):
			errors.append("'%s' apparait deux fois" % b.bone)
		seen[b.bone] = true

		if b.frequency <= 0.0:
			errors.append("'%s' : frequency doit etre > 0" % b.bone)
		if b.damping_ratio <= 0.0:
			errors.append("'%s' : damping_ratio doit etre > 0 (0 = aucun amortissement, le membre oscille sans fin)" % b.bone)
		if b.max_torque_per_kg <= 0.0:
			errors.append("'%s' : max_torque_per_kg doit etre > 0" % b.bone)

	for name in DRIVEN_BONES:
		if not seen.has(name):
			errors.append("articulation manquante : '%s'" % name)

	return errors
