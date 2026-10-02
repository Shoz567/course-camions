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
# Un .blend par modele, a ouvrir dans Blender. Hors de game/ : Godot
# importerait les .blend tout seul (CLAUDE.md §2 : jamais de .blend dans Godot).
BLEND_DIR = REPO_ROOT / "blend"

HERE = Path(__file__).resolve().parent

# Un .glb par modele, range par categorie (docs/ART_PIPELINE.md §4 ter) :
#   vehicules/   camions et engins, avec leurs points d'accroche Socket_*
#   armes/       equipements montes sur un Socket_* du camion
#   projectiles/ ce qui part du camion (missile, grenade, voitures...)
#   effets/      enveloppes et faisceaux a etirer (bouclier, laser)
VEHICLES = ["citerne", "betaillere", "remorque", "porte_voitures", "grue",
            "chasse_neige", "pompier", "chariot_elevateur"]
ITEMS = {
    "armes": ["lance_missiles", "scie_geante_g", "scie_geante_d", "mitrailleuse",
              "laser_emetteur", "bouclier_emetteur", "boomerang_aimante"],
    "projectiles": ["missile", "grenade", "camion_projectile", "doudou_geant",
                    "voiture_rouge", "voiture_bleue", "voiture_jaune", "voiture_verte",
                    "voiture_blanche"],
    "effets": ["bouclier_coque", "laser_faisceau"],
}

# (script, arguments) — rempli au fil des phases.
# Phase 5 : build_truck.py, build_track_01.py
BUILDS = (
    [("build_vehicle.py", ["--variant=" + v, "--out=" + str(OUT_DIR / "vehicules" / (v + ".glb")),
                           "--blend=" + str(BLEND_DIR / "vehicules" / (v + ".blend"))])
     for v in VEHICLES]
    + [("build_item.py", ["--item=" + i, "--out=" + str(OUT_DIR / cat / (i + ".glb")),
                          "--blend=" + str(BLEND_DIR / cat / (i + ".blend"))])
       for cat, names in ITEMS.items() for i in names]
)


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    BLEND_DIR.mkdir(parents=True, exist_ok=True)

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
    print("OK sortie=%s blend=%s" % (OUT_DIR, BLEND_DIR))
    return 0


if __name__ == "__main__":
    sys.exit(main())
