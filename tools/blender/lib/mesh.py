"""Primitives, booleens, lissage.

Phase 5 (art). Tous les parametres (dimensions, budgets de triangles) sont des
constantes en tete de ce fichier, pas des nombres disperses dans le code.

Rappel de docs/ART_PIPELINE.md : le mesh n'a AUCUNE autorite sur la physique.
Les dimensions, la masse et les positions de roues de docs/VEHICLE_SPEC.md sont
le contrat ; le maillage s'y conforme. La physique du camion utilise des formes
de collision simples definies cote Godot, jamais le mesh.
"""

# Budgets — build_all.py echoue si l'un est depasse (c'est volontaire : en
# ecran partage a 4, chaque camion est rendu 4 fois).
TRI_BUDGET_TRUCK = 6000        # cabine + chassis, roues comprises
TRI_BUDGET_WHEEL = 400         # par roue (objet separe, cf. ART_PIPELINE.md)
TRI_BUDGET_TRACK = 60000       # visuel d'une piste complete
TRI_BUDGET_TRACK_COL = 8000    # collision de la piste
TRI_BUDGET_PROP = 800
# Vehicule complet : tracteur + roues + semi-remorque et son chargement
# (2026-10-02, catalogue de vehicules, docs/ART_PIPELINE.md §6).
TRI_BUDGET_VEHICLE_TOTAL = 16000
TRI_BUDGET_ITEM = 2500         # arme ou projectile (toutes pieces comprises)
TRI_BUDGET_FX = 4000           # effet enveloppant (coque du bouclier)


def tri_count(obj):
    """Nombre de triangles d'un objet mesh."""
    mesh = obj.data
    return sum(len(p.vertices) - 2 for p in mesh.polygons)
