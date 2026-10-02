"""Regenere tous les assets 3D du projet.

    blender -b -P tools/blender/build_all.py

Chaque build tourne dans son propre processus Blender (scene vierge,
--factory-startup) : aucun script ne depend de l'etat laisse par un autre.

Chaque script de build enregistre ci-dessous doit, d'apres
docs/ART_PIPELINE.md §2 :
  - partir d'une scene vide,
  - etre idempotent,
  - sortir en code non nul avec un message clair en cas d'echec,
  - imprimer en derniere ligne le chemin produit et le nombre de triangles.
"""

import subprocess
import sys
from pathlib import Path

import bpy

sys.path.append(str(Path(__file__).parent))

# Racine du depot (tools/blender/build_all.py -> remonte de 2 niveaux).
REPO_ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = REPO_ROOT / "game" / "assets" / "generated"

HERE = Path(__file__).resolve().parent

VEHICLES = ["citerne", "betaillere", "remorque", "porte_voitures", "grue",
            "chasse_neige", "pompier", "chariot_elevateur"]
ITEMS = ["lance_missiles", "missile", "scie_geante_d", "scie_geante_g",
         "mitrailleuse", "grenade", "camion_projectile", "doudou_geant",
         "voiture_rouge", "voiture_bleue", "voiture_jaune", "voiture_verte",
         "voiture_blanche", "bouclier_emetteur", "bouclier_coque",
         "laser_emetteur", "laser_faisceau", "boomerang_aimante"]

# (script, arguments) — rempli au fil des phases.
# Phase 5 : build_truck.py, build_track_01.py
BUILDS = (
    [("build_vehicle.py", ["--variant=" + v, "--out=" + str(OUT_DIR / "vehicules" / (v + ".glb"))])
     for v in VEHICLES]
    + [("build_item.py", ["--item=" + i, "--out=" + str(OUT_DIR / "armes" / (i + ".glb"))])
       for i in ITEMS]
)


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    print("=== build_all : %d asset(s) a generer ===" % len(BUILDS))

    if not BUILDS:
        print("Aucun asset enregistre (attendu jusqu'a la phase 5).")
        print("OK sortie=%s" % OUT_DIR)
        return 0

    failed = []
    for script, args in BUILDS:
        cmd = [bpy.app.binary_path, "-b", "--factory-startup", "-P",
               str(HERE / script), "--"] + args
        res = subprocess.run(cmd, capture_output=True, text=True)
        # Blender imprime encore quelques lignes apres le script : on cherche
        # la ligne de resultat du build plutot que la derniere ligne.
        lines = [l for l in res.stdout.splitlines() if l.startswith("OK ")]
        if res.returncode != 0 or not lines:
            failed.append(script + " " + " ".join(args[:1]))
            print("ECHEC %s %s" % (script, args[0]))
            print(res.stdout[-2000:])
            print(res.stderr[-2000:])
        else:
            print(lines[-1])

    if failed:
        raise SystemExit("build_all : %d echec(s) : %s" % (len(failed), failed))
    print("OK sortie=%s" % OUT_DIR)
    return 0


if __name__ == "__main__":
    sys.exit(main())
