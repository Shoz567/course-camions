"""Genere un objet d'arme (accessoire ou projectile) en .glb.

    blender -b --factory-startup -P tools/blender/build_item.py -- \
        --item=mitrailleuse --out=game/assets/generated/armes/mitrailleuse.glb

Visuels seulement. Convention (docs/ART_PIPELINE.md §4 ter) : origine de la
racine = point d'accroche (ou centre pour un projectile), avant en +Y Blender
(-Z Godot), pieces mobiles separees et pivotees sur leur axe.
"""

import argparse
import sys
from pathlib import Path

import bpy

sys.path.append(str(Path(__file__).parent))
from lib import export, items, kit, mesh  # noqa: E402

CATALOG = {
    "lance_missiles": items.missile_launcher,
    "missile": items.missile,
    "scie_geante_d": lambda: items.saw("D"),
    "scie_geante_g": lambda: items.saw("G"),
    "mitrailleuse": items.machine_gun,
    "grenade": items.grenade,
    "camion_projectile": items.truck_projectile,
    "doudou_geant": items.teddy,
    "voiture_rouge": lambda: [items.car("Voiture", "Rouge")],
    "voiture_bleue": lambda: [items.car("Voiture", "Bleu")],
    "voiture_jaune": lambda: [items.car("Voiture", "Jaune")],
    "voiture_verte": lambda: [items.car("Voiture", "Vert")],
    "voiture_blanche": lambda: [items.car("Voiture", "Blanc")],
    "bouclier_emetteur": items.shield_emitter,
    "bouclier_coque": items.shield_shell,
    "laser_emetteur": items.laser_emitter,
    "laser_faisceau": items.laser_beam,
    "boomerang_aimante": items.boomerang,
}

# Effets plein cadre (coque du bouclier) : budget a part.
FX = {"bouclier_coque"}


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--item", required=True, choices=sorted(CATALOG))
    p.add_argument("--out", required=True)
    p.add_argument("--blend", default="", help="sauvegarde aussi un .blend de ce seul modele")
    return p.parse_args(argv)


def main():
    args = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    objects = CATALOG[args.item]()
    budget = mesh.TRI_BUDGET_FX if args.item in FX else mesh.TRI_BUDGET_ITEM
    total = kit.tris(objects)
    if total > budget:
        raise SystemExit("%s : %d triangles > budget %d" % (args.item, total, budget))
    export.apply_transforms(objects)
    out = export.to_glb(args.out, objects)
    if args.blend:
        export.to_blend(args.blend, objects, args.item)
    print("OK %s tris=%d" % (out, total))


if __name__ == "__main__":
    main()
