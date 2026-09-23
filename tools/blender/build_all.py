"""Regenere tous les assets 3D du projet.

    blender -b -P tools/blender/build_all.py

Phase 0 : ne genere encore rien, mais tourne et sort en code 0. C'est un
critere de sortie de la phase 0 — la chaine doit etre branchee avant d'avoir
quelque chose a y faire passer.

Chaque script de build enregistre ci-dessous doit, d'apres
docs/ART_PIPELINE.md §2 :
  - partir d'une scene vide,
  - etre idempotent,
  - sortir en code non nul avec un message clair en cas d'echec,
  - imprimer en derniere ligne le chemin produit et le nombre de triangles.
"""

import sys
from pathlib import Path

sys.path.append(str(Path(__file__).parent))

# Racine du depot (tools/blender/build_all.py -> remonte de 2 niveaux).
REPO_ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = REPO_ROOT / "game" / "assets" / "generated"

# (script, arguments) — rempli au fil des phases.
# Phase 5 : build_character.py, build_arena_01.py
BUILDS = []


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    print("=== build_all : %d asset(s) a generer ===" % len(BUILDS))

    if not BUILDS:
        print("Aucun asset enregistre (attendu jusqu'a la phase 5).")
        print("OK sortie=%s" % OUT_DIR)
        return 0

    for script, args in BUILDS:
        raise SystemExit("build_all : execution non implementee (%s)" % script)

    return 0


if __name__ == "__main__":
    sys.exit(main())
