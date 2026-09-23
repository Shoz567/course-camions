# ART_PIPELINE.md — Blender headless → Godot

Règle fondatrice : **le script Python est la source de vérité, pas le `.blend`.**
Tout asset se régénère depuis zéro par `make assets`. Rien d'artistique n'est
committé en binaire.

Pourquoi ce choix : un agent peut itérer seul sur un script (générer, mesurer,
corriger) alors qu'il ne peut pas cliquer dans Blender. Et un diff de paramètres
est lisible, un diff de `.blend` ne l'est pas.

---

## 1. Chaîne complète

```
tools/blender/build_*.py
        │  blender -b -P ...
        ▼
game/assets/generated/*.glb          (git-ignoré)
        │  godot --headless --import
        ▼
game/.godot/imported/                (git-ignoré)
        │  instanciation
        ▼
game/characters/*.tscn, game/levels/*.tscn
```

## 2. Squelette d'un script de build

```python
import bpy, sys, argparse
from pathlib import Path

sys.path.append(str(Path(__file__).parent))
from lib import rig, mesh, materials, export

def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--variant", default="default")
    p.add_argument("--out", required=True)
    return p.parse_args(argv)

def main():
    args = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)   # scène vierge, toujours

    arm = rig.build_armature()                          # noms issus de RIG_SPEC
    body = mesh.build_body(args.variant)
    rig.bind(body, arm)                                 # skinning automatique
    materials.apply_vertex_colors(body, args.variant)

    rig.assert_bone_names(arm)                          # échoue si le contrat est rompu
    export.to_glb(args.out, objects=[body, arm])
    print(f"OK {args.out} tris={mesh.tri_count(body)}")

if __name__ == "__main__":
    main()
```

Exigences pour tout script de build :
- part d'une scène vide, ne dépend d'aucun état antérieur ;
- **idempotent** : deux exécutions produisent le même résultat ;
- `raise SystemExit("message")` en cas d'échec (code de sortie non nul) ;
- imprime en dernière ligne le chemin produit et le nombre de triangles.

## 3. Réglages d'export (centralisés dans `lib/export.py`)

```python
bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format="GLB",
    export_yup=True,              # Y up / -Z forward : convention Godot
    export_apply=True,            # applique les modificateurs
    export_skins=True,
    export_all_influences=False,  # 4 poids max par sommet
    export_animations=True,       # seulement la pose idle
    export_morph=False,
    export_cameras=False,
    export_lights=False,
    use_selection=True,
)
```

Vérifie systématiquement **avant** l'export :
`bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)`.
Une échelle non appliquée est la cause n°1 de personnages géants ou minuscules
dans Godot.

> ⚠️ Ces réglages sont une **hypothèse tant que le spike S6 n'a pas tourné**
> (`docs/SPIKE.md`). S6 exporte un cube de 1 m et une armature aux longueurs
> connues, les mesure côté Godot, et confirme ou corrige ce bloc. Il coûte une
> heure et il se fait **avant** d'écrire le reste du pipeline : découvrir un
> facteur d'échelle une fois `build_character.py` terminé, c'est tout reprendre.

**Chemins.** Toute construction de chemin passe par `pathlib`, jamais par une
concaténation avec `/` ou `\`. Le projet est développé sous Windows et les
scripts doivent rester portables (cf. `docs/ENVIRONMENT.md` §4.3).

## 4. Génération du corps : technique recommandée

Pour le style « pâte à modeler » :

1. Poser des primitives (UV spheres, cylindres) aux positions des os définies
   dans `RIG_SPEC.md` §3 et §4, avec des rayons un peu supérieurs aux capsules
   de collision (le visuel enveloppe la physique).
2. Fusionner par booléen `UNION`.
3. `Remesh` modifier en mode **Voxel**, taille ~0,02 m → surface continue et
   lisse, membres qui se fondent l'un dans l'autre.
4. `Decimate` jusqu'à atteindre le budget (< 2 000 tris).
5. `Shade Smooth` + `Weighted Normal`.

Tous les paramètres (rayons, taille de voxel, budget) sont des constantes en tête
de `lib/mesh.py`, pas des nombres dispersés dans le code.

### Le mesh n'a aucune autorité sur la physique

Le maillage **suit** les longueurs et les positions de `RIG_SPEC.md` ; il ne les
définit pas, et il ne définit surtout pas les masses. La tentation, une fois le
corps généré, est de recalculer les masses depuis le volume réel des membres :
c'est explicitement interdit (`RIG_SPEC.md` §9).

La raison est simple : les masses sont l'entrée du tuning PD de la phase 1. Les
dériver du mesh en phase 5, c'est invalider des semaines de réglages au moment
précis où plus personne ne se souvient pourquoi les gains valent ce qu'ils
valent. Si un membre paraît visuellement trop lourd ou trop léger, **c'est le
rayon du mesh qu'on ajuste**, pas la masse.

## 5. Skinning

`rig.bind()` utilise `bpy.ops.object.parent_set(type="ARMATURE_AUTO")` (heat map
automatique). Sur un corps simple et fermé, c'est suffisant et ça évite d'écrire
des poids à la main.

Contrainte d'export Godot : **4 influences maximum par sommet**
(`export_all_influences=False`). Au-delà, les poids excédentaires sont écartés
silencieusement et le membre se déforme mal. Vérifie-le après le binding, en même
temps que le test de sommets non skinnés ci-dessous.

Vérification obligatoire après binding : aucun sommet sans influence.

```python
for v in body.data.vertices:
    assert sum(g.weight for g in v.groups) > 0.001, f"sommet {v.index} non skinné"
```

Un sommet non skinné reste à l'origine du monde et produit un triangle étiré
jusqu'au centre de la scène — visuel très reconnaissable, cause toujours celle-là.

## 6. Arènes

Deux objets exportés par arène :
- `Arena01` : le visuel ;
- `Arena01-col` : une version simplifiée. Le suffixe `-col` déclenche la
  génération automatique d'une `StaticBody3D` avec `ConcavePolygonShape3D` à
  l'import Godot.

Rappel : concave = **statique uniquement**. Toute plateforme mobile doit avoir
une collision convexe (boîte), donc être construite comme telle.

## 7. Budgets

| Asset | Triangles | Matériaux |
|---|---|---|
| Personnage | < 2 000 | 1 |
| Arène (visuel) | < 20 000 | ≤ 3 |
| Arène (collision) | < 2 000 | — |
| Prop / hazard | < 800 | 1 |

`build_all.py` échoue si un budget est dépassé. C'est volontaire : un dépassement
silencieux se paie à 4 joueurs en phase 6.

## 8. Couleurs plutôt que textures

En phase 5, aucune texture image : couleurs vertex + un `StandardMaterial3D` avec
`vertex_color_use_as_albedo = true`. Avantages : zéro UV à gérer, zéro poids,
variantes de couleur triviales, et ça suffit largement au style visé.

Les textures ne reviennent en discussion qu'en phase 7, si le besoin est réel.

## 9. Itération rapide

Pendant le travail sur un asset, ne lance pas `make assets` complet :

```bash
blender -b -P tools/blender/build_character.py -- --variant=default \
  --out=game/assets/generated/character_default.glb \
&& godot --headless --path game --import
```

Environ 10 s de boucle. Si ça dépasse 30 s, réduis la résolution du remesh
pendant l'itération et remonte-la dans `build_all.py`.
