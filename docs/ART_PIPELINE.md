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

### 4 bis. Modèle externe des camarades (`Assets_Visuels/`)

Les modèles `Assets_Visuels/Camion/Camions_Course_Export/*.glb` sont faits à la
main, hors pipeline Blender scripté, et versionnés **par Git LFS** depuis le
2026-10-02 (`docs/ENVIRONMENT.md` §6.7 ; les `.fbx` sources restent hors
dépôt). `TruckVisual` (`game/vehicles/truck_visual.gd`) les charge **à
l'exécution** s'ils existent ; sinon le camion garde ses boîtes de blockout. Un
clone sans Git LFS et les tests (headless) ne dépendent donc d'aucun binaire. Un export du jeu
ne les embarquera pas : à régler en phase 7 (import dans le projet, licence et
origine confirmées).

Mesuré sur `Camion_Bleu.glb` (2026-09-28), **le modèle ne suit pas la spec** :

| Point du contrat | Spec | Modèle |
|---|---|---|
| Avant | −Z | +Z |
| Échelle | appliquée (1,0) | ×1,25 non appliqué sur la racine |
| Remorque | semi-remorque (depuis le 2026-09-28) | semi-remorque 3 essieux avec aileron : conservée |
| Longueur du tracteur | 5,8 m | 6,1 m |
| Largeur / hauteur | 2,5 / 3,2 m | 2,9 m (cabine), 3,7 m hors tout / 3,7 m (4,7 m échappements) |
| Empattement / voie | 3,8 / 2,1 m | 3,1 / 2,4 m |
| Rayon de roue | 0,55 m | 0,72 m (AV), 0,84 m (AR jumelées) |
| Noms des roues | `Wheel_FL`… pivot au moyeu | `Roue_AV_G`… groupes sans pivot au moyeu ; « G » est à droite une fois l'avant en −Z |

`TruckVisual` l'**ajuste** donc sans toucher à la physique : demi-tour,
échelle uniforme ×0,947 calculée sur le **tracteur** (5,8 m) et appliquée à tout
l'ensemble (semi-remorque exclue du calage mais affichée : 16,4 m hors tout),
centrage sur la caisse du tracteur, bas des pneus au sol, pivot recalé au moyeu
de chaque groupe de roues du tracteur, roues associées aux rayons **par
position** (pas par nom) ; les roues de remorque restent fixes. Le nœud
`Remorque` (toute la semi-remorque, aileron et roues compris) est accroché à un
pivot posé sur la sellette de la spec (0 ; 1,8 ; 1,2) et tourne avec l'angle de
remorque du camion (VEHICLE_SPEC §5 bis). Restent
visibles : cabine plus large (3,5 m) et plus haute (4,4 m) que sa collision, et
roues visuelles à l'empattement du modèle (≈ 3,0 m) au lieu de 3,8 m.
`truck_visual_test` vérifie l'ajustement ; il se saute sans le modèle.

**À corriger à la source** (blender-modeler / camarades) : avant en −Z, échelle
appliquée, empattement 3,8 m, voie 2,1 m, roues de 0,55 m, objets `Body` +
`Wheel_FL/FR/RL/RR` pivotés au moyeu (§4), caisse de remorque de 13,0 × 3,0 m
dont le bas est à 1,8 m (VEHICLE_SPEC §5). **À
vérifier** : les nœuds `Logo_001`, `Embleme_004/005` et `Plaque_AV_UE` ne
doivent reproduire aucune marque existante (`CLAUDE.md` §1).

### 4 ter. Catalogue de véhicules : même tête, remorque différente

Les véhicules de `Assets_Visuels/Armes_et_camions/vehicules/` (bétaillère,
citerne, porte-voitures, remorque, grue, pompier, chasse-neige, chariot
élévateur) partagent **tous la même tête** : le tracteur de `Camion_Bleu.glb`,
ajusté comme le fait `TruckVisual` (avant en −Z, tracteur de 6,96 m, pneus au
sol). Seule la semi-remorque `Remorque` (pivot à la sellette) change. Grue,
pompier, chasse-neige et chariot, à l'origine des porteurs, deviennent des
semi-remorques **dédiées** sur le châssis de `remorque.blend` : porte-grue sur
béquilles avec poutres sanglées, fourgon pompier et grande échelle sur toute la
longueur, trémie à sel sur toute la longueur, remorque à palettes avec ridelles
et chariot embarqué à l'arrière. Ils sont assemblés par script, à relancer si
la tête change :

```
blender -b -P tools/blender/catalogue_tete_commune.py
```

**Points d'accroche des armes** : 6 nœuds vides, mêmes noms sur chaque véhicule.

| Nœud | Parent | Position Godot (x ; y ; z) |
|---|---|---|
| `Socket_Avant` | `Body` | (0 ; 1,2 ; −3,25), pare-chocs |
| `Socket_Lateral_G` / `_D` | `Body` | (∓1,73 ; 1,1 ; 0), flancs entre les essieux |
| `Socket_Toit` | `Body` | (0 ; 4,39 ; −1,74), toit de cabine |
| `Socket_Arriere` | `Remorque` | arrière du chargement, propre à chaque remorque |
| `Socket_Conteneur` | `Remorque` | arrière du plateau / de la caisse, propre à chaque remorque |

Les quatre premiers sont sur la tête : **mêmes coordonnées partout**, par
construction. Les deux derniers suivent la remorque (et pivotent avec elle).
Les camions de course `Camion_*.glb` n'ont pas encore de sockets.

En jeu, seule la remorque de ces véhicules sert : c'est la remorque au choix
du sas READY (VEHICLE_SPEC §5 bis), chargée par `TruckVisual.set_trailer_type`.
**Budget dépassé, à reprendre** : 32 000 à 54 000 triangles par remorque,
123 000 pour le porte-voitures, à multiplier par 6 camions et jusqu'à 6 vues.

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
