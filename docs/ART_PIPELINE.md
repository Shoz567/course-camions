# ART_PIPELINE.md — Blender headless → Godot

Règle fondatrice : **le script Python est la source de vérité, pas le `.blend`.**
Tout asset se régénère depuis zéro par `make assets`. Rien d'artistique n'est
committé en binaire (le hook `pre-commit` refuse les `.glb` et `.blend`).

Pourquoi : un agent peut itérer seul sur un script (générer, mesurer, corriger)
alors qu'il ne peut pas cliquer dans Blender. Et un diff de paramètres est
lisible, un diff de `.blend` ne l'est pas.

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
game/vehicles/*.tscn, game/tracks/*.tscn
```

## 2. Squelette d'un script de build

```python
import bpy, sys, argparse
from pathlib import Path

sys.path.append(str(Path(__file__).parent))
from lib import mesh, export

def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--variant", default="default")
    p.add_argument("--out", required=True)
    return p.parse_args(argv)

def main():
    args = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)   # scène vierge, toujours
    objects = build(args.variant)
    export.apply_transforms(objects)
    export.to_glb(args.out, objects)
    print(f"OK {args.out} tris={sum(mesh.tri_count(o) for o in objects)}")
```

Exigences pour tout script de build :
- part d'une scène vide, ne dépend d'aucun état antérieur ;
- **idempotent** : deux exécutions produisent le même résultat ;
- `raise SystemExit("message")` en cas d'échec (code de sortie non nul) ;
- imprime en dernière ligne le chemin produit et le nombre de triangles ;
- chemins construits avec `pathlib`, jamais par concaténation (projet développé
  sous Windows).

## 3. Réglages d'export

Centralisés dans `tools/blender/lib/export.py`, **seul endroit** où l'on appelle
`bpy.ops.export_scene.gltf` : GLB, `export_yup=True`, modificateurs appliqués,
**rotation et échelle appliquées, location conservée**, pas de caméra ni de
lumière.

✅ **Validé** (acquis A6 de `docs/SPIKE.md`) : un cube de 1 m arrive à
1,0000 m dans Godot, les noms sont conservés.

✅ **Validé par le spike V4** (acquis A13) : chassis + 4 roues séparées, pivots
à 0,0000 m du moyeu dans Godot. La location n'est **jamais** appliquée : c'est
elle qui porte le pivot. L'appliquer mettait les roues à 2,24 m du moyeu.

## 4. Le camion

### Objets et noms — un contrat

Un camion est exporté en **objets séparés**, nommés selon
`docs/VEHICLE_SPEC.md` §4 :

| Objet | Rôle | Pivot (origine) |
|---|---|---|
| `Body` | carrosserie : cabine + châssis | origine du camion (au sol, centré) |
| `Wheel_FL`, `Wheel_FR`, `Wheel_RL`, `Wheel_RR` | roues | **exactement au moyeu** |

Le pivot au moyeu n'est pas un détail : c'est autour de lui que Godot fera
tourner la roue (rotation) et la braquera (direction). Un pivot décalé de 2 cm
donne une roue qui « boite ».

Un renommage appliqué d'un seul côté ne produit pas d'erreur bruyante : la roue
n'est pas trouvée, elle reste immobile. Les noms se changent dans
`VEHICLE_SPEC.md` d'abord, dans le même commit des deux côtés.

### Le maillage n'a aucune autorité sur la physique

Le modèle **suit** `VEHICLE_SPEC.md` (dimensions, positions et rayon des roues),
il ne le définit pas. La physique utilise deux boîtes de collision et quatre
rayons définis côté Godot ; on ne dérive jamais une masse, un centre de masse ou
une forme de collision du maillage. Si le camion paraît trop haut, c'est la
carrosserie qu'on ajuste, pas la suspension.

### Style

Formes franches et lisibles de loin — en écran partagé à 4, chaque camion
occupe une petite portion d'une petite vue. Silhouettes de cabine distinctes
d'une variante à l'autre, couleur dominante par joueur. Aucun camion, logo ou
marque existants.

## 5. Les pistes

Deux objets exportés par piste :
- `Track01` : le visuel ;
- `Track01-col` : une version simplifiée. Le suffixe `-col` fait générer par
  Godot un `StaticBody3D` avec `ConcavePolygonShape3D` à l'import.

Rappels :
- concave = **statique uniquement**. Tout obstacle mobile a une collision
  convexe (boîte), donc se construit comme tel ;
- chaque zone de collision porte sa **surface** (`asphalt`, `dirt`, `grass`,
  `ice` : `VEHICLE_SPEC.md` §8), via une propriété personnalisée exportée en
  métadonnée ;
- l'épaisseur des murs respecte le minimum fixé par le spike V2 ;
- les checkpoints, zones de reset et points de réapparition ne sont **pas** de
  l'art : ils sont posés côté Godot par le `track-designer`.

## 6. Budgets

| Asset | Triangles | Matériaux |
|---|---|---|
| Camion (carrosserie) | < 6 000 | 1–2 |
| Roue | < 400 | 1 |
| Piste (visuel) | < 60 000 | ≤ 4 |
| Piste (collision) | < 8 000 | — |
| Prop | < 800 | 1 |

Constantes en tête de `tools/blender/lib/mesh.py`. `build_all.py` échoue si un
budget est dépassé. Les budgets de piste sont **provisoires** : le spike V3
(écran partagé à 4 sur GPU intégré) les confirme ou les réduit. En écran
partagé à 4, chaque triangle est rendu quatre fois.

## 7. Couleurs plutôt que textures

En phase 5 : couleurs vertex + un `StandardMaterial3D` avec
`vertex_color_use_as_albedo = true`. Zéro UV à gérer, zéro poids, variantes de
couleur triviales (couleur de camion par joueur). Les textures ne reviennent en
discussion qu'en phase 7, si le besoin est réel.

## 8. Itération rapide

Pendant le travail sur un asset, ne lance pas `make assets` complet :

```bash
blender -b -P tools/blender/build_truck.py -- --variant=default \
  --out=game/assets/generated/truck_default.glb
godot --headless --path game --import
```

Si la boucle dépasse 30 s, simplifie le modèle pendant l'itération.
