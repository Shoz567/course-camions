"""Generation du squelette + skinning automatique.

Phase 5 (tache 5.1). Les noms d'os sont un CONTRAT avec le code Godot : ils
sont listes dans docs/RIG_SPEC.md §2, que personne ne modifie unilateralement.

Un renommage applique d'un seul cote ne produit pas d'erreur bruyante : le
personnage s'effondre, et on cherche le bug dans le PD pendant une journee.
"""

# Contrat de nommage — doit correspondre exactement a docs/RIG_SPEC.md §2.
BONES = [
    "pelvis", "spine", "head",
    "upperarm_l", "forearm_l",
    "upperarm_r", "forearm_r",
    "thigh_l", "shin_l", "foot_l",
    "thigh_r", "shin_r", "foot_r",
]


def assert_bone_names(armature):
    """Echoue si le contrat de nommage est rompu."""
    present = {b.name for b in armature.data.bones}
    missing = [b for b in BONES if b not in present]
    if missing:
        raise SystemExit("Os manquants: %s" % missing)
    return True
