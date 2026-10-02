"""Publie le catalogue dans Assets_Visuels/ (versionne par Git LFS).

    blender -b --factory-startup -P tools/blender/publish_assets.py

Copie, pour chaque modele du catalogue, le .glb (game/assets/generated/) et
le .blend (blend/) produits par `make assets` vers
Assets_Visuels/Armes_et_camions/<categorie>/, a cote des modeles de
l'equipe. Les fichiers inchanges ne sont pas recopies (pas de faux
changement dans git). Lance par Blender pour ne dependre d'aucun Python
installe (projet developpe sous Windows).
"""

import filecmp
import shutil
import sys
from pathlib import Path

sys.path.append(str(Path(__file__).parent))
from build_all import BLEND_DIR, ITEMS, OUT_DIR, REPO_ROOT, VEHICLES  # noqa: E402

DEST = REPO_ROOT / "Assets_Visuels" / "Armes_et_camions"


def main():
    models = [("vehicules", v) for v in VEHICLES]
    models += [(cat, i) for cat, names in ITEMS.items() for i in names]
    missing, copied = [], 0
    for cat, name in models:
        glb, blend = OUT_DIR / cat / (name + ".glb"), BLEND_DIR / cat / (name + ".blend")
        for src in (glb, blend):
            if not src.exists():
                missing.append(str(src.relative_to(REPO_ROOT)))
        if missing:
            continue
        d_glb, d_blend = DEST / cat / (name + ".glb"), DEST / cat / (name + ".blend")
        d_glb.parent.mkdir(parents=True, exist_ok=True)
        # Un .blend n'est jamais identique octet pour octet d'une sauvegarde a
        # l'autre : on ne le recopie que si le modele (.glb) a change.
        same = d_glb.exists() and filecmp.cmp(glb, d_glb, shallow=False)
        if same and d_blend.exists():
            continue
        shutil.copyfile(glb, d_glb)
        shutil.copyfile(blend, d_blend)
        copied += 2
    if missing:
        raise SystemExit("publish_assets : lancer d'abord make assets, absents : %s" % missing)
    print("OK %d fichier(s) copie(s) vers %s" % (copied, DEST))


if __name__ == "__main__":
    main()
