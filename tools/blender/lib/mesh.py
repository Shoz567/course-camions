"""Primitives, booleens, remesh, lissage.

Phase 5 (tache 5.2). Tous les parametres (rayons, taille de voxel, budget de
triangles) sont des constantes en tete de ce fichier, pas des nombres disperses
dans le code.

Rappel de docs/ART_PIPELINE.md : le mesh n'a AUCUNE autorite sur la physique.
Les masses et longueurs de docs/RIG_SPEC.md sont le contrat ; le maillage s'y
conforme. On ne derive jamais une masse du volume d'un membre.
"""

# Budgets — build_all.py echoue si l'un est depasse (c'est volontaire).
TRI_BUDGET_CHARACTER = 2000
TRI_BUDGET_ARENA = 20000
TRI_BUDGET_ARENA_COL = 2000
TRI_BUDGET_PROP = 800

# Style "pate a modeler" : le visuel enveloppe la physique, donc les rayons
# sont legerement superieurs aux capsules de collision de RIG_SPEC.md §3.
VOXEL_SIZE = 0.02
RADIUS_MARGIN = 0.01


def tri_count(obj):
    """Nombre de triangles d'un objet mesh."""
    mesh = obj.data
    return sum(len(p.vertices) - 2 for p in mesh.polygons)
