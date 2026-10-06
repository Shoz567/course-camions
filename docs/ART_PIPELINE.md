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

**Passages de roue** (2026-10-06, « en drift, à l'atterrissage, en virage, les
roues traversent ») : le modèle laissait ~10 cm sous ses garde-boue, alors que
la roue visuelle suit tout le débattement (mesuré : +36 cm à l'atterrissage,
+24 cm en drift) et que la carrosserie penche vers elle (5,5°, ~14 cm). Le
support de marchepied était même dans la roue avant au repos. `TruckVisual`
corrige, toujours sans toucher à la physique :

- garde-boue et emblèmes relevés de 12 cm, marchepieds reculés de 20 cm ;
- roues de la tête réduites de 8 %, bas du pneu au sol (elles restent plus
  grandes que la spec) : jeu sous les passages porté de 12 / 14 cm à 20 / 36 cm
  (avant / arrière) ;
- **butée visuelle** : jeu mesuré roue par roue sur la géométrie au chargement ;
  à chaque tick, la roue ne monte pas au-delà, penche de la carrosserie compris
  aux deux bords du pneu ;
- braquage visuel borné à ce que les passages de roue avant laissent passer
  (mesuré : 45°, au-delà du braquage max, après le recul des marchepieds) ;
- roues **arrière** : montée visuelle bornée à 8 cm (`REAR_WHEEL_MAX_UP`), car
  la remorque pivote et penche juste au-dessus d'elles (§4 ter, zone balayée).

`truck_wheel_arch_test` le vérifie : chute de 4 m, braquage à fond, drift,
contre-braquage, freinage ; aucun sommet de carrosserie dans un pneu. Sans ces
corrections : 247 sommets traversés (cabine, garde-boue, joint de porte, siège).

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
sol). Seule la semi-remorque `Remorque` (pivot à la sellette) change, et
**chacune est unique, structure comprise** : aucune ne partage de châssis,
d'essieux ni de roues avec une autre (décision du 2026-10-06).

| Remorque | Caisse | Châssis | Train roulant |
|---|---|---|---|
| Conteneur | conteneur de l'équipe | squelette porte-conteneur rouge, verrous tournants | 3 essieux jumelés, jantes alu |
| Citerne | citerne de l'équipe | autoportante : berceaux avant / arrière, tubes à flexibles, protections tubulaires | 3 essieux, roues simples larges, jantes blanches, garde-boue inox |
| Bétaillère | caisse de l'équipe | cadre périmétrique, jupes latérales vertes | 3 essieux très écartés, jumelés, jantes noires, feux en colonne |
| Porte-voitures | cadre et voitures de l'équipe | train surbaissé, rampes relevées | 3 essieux serrés, petites roues violettes |
| Saleuse | semi-trémie en V, bâche, convoyeur, épandeur, échelle | faux-châssis | 2 essieux, roues simples larges orange |
| Pompier | fourgon d'un seul bloc jusqu'aux jupes, rideaux alu, grande échelle, enrouleurs | caisse autoportante, col rehaussé | 2 essieux jumelés, jantes chromées |
| Grue | semi-grue : tourelle, cabine, contrepoids, flèche télescopique couchée | poutre-caisson jaune, stabilisateurs | 4 essieux jumelés, jantes jaunes |
| Porte-engins | deux chariots élévateurs arrimés, panneau convoi | surbaissé : col de cygne, plancher bas en bois, rampes | 3 essieux, petites roues jumelées grises |

**Zone balayée au-dessus du tracteur** (2026-10-06) : en virage, la remorque
pivote jusqu'à ±35° et penche jusqu'à ±6° juste au-dessus des roues arrière
du tracteur. Rien ne doit y entrer : le script le vérifie à chaque remorque
(`swing_violations`, faces échantillonnées et pas seulement les sommets, roues
en position haute) et refuse la remorque sinon. En pratique, tout ce qui est
bas commence derrière y ≈ −3,9 m (Blender) : béquilles, longerons, jupes,
tubes, plancher bas. Les caisses de l'équipe y sont adaptées par le script :
petites pièces en cause retirées entières, cadre du porte-voitures coupé net
(son plancher bas commence derrière les roues du tracteur), ventre de la
citerne remonté à l'avant en pente douce (une cuve ne se coupe pas).
`truck_trailer_wheels_test` le vérifie en jeu, les 8 remorques à 35°. Avant :
165 sommets de la citerne dans une roue du tracteur en drift.

**Qualité, au niveau de la tête** (2026-10-06, « des qualités graphiques
beaucoup moins élevées que la tête ») :

- toutes les pièces générées sont **chanfreinées et lissées** (arêtes vives
  au-delà de 35°), comme la tête ; aucune texture, des matériaux réglés comme
  ceux de la tête (chrome, aluminium, peinture semi-brillante, pneu mat, feux
  émissifs) ;
- **roues de révolution** : pneu profilé (talons, flancs bombés, épaulements
  arrondis, deux rainures), jante à fût et voile emboutie, moyeu, écrous
  hexagonaux, tambours ; nombre d'écrous et d'ajours propre à chaque remorque ;
- **détails de vraie semi-remorque** : marquage de contour rétroréfléchissant
  (flancs et arrière), feux de gabarit latéraux, blocs de feux arrière avec
  catadioptres triangulaires, pare-cycliste zébré, têtes d'accouplement et
  flexibles d'air spiralés rouge et bleu, roue de secours, coffre à outils,
  dévidoirs du pompier, damier des véhicules de secours ;
- 18 000 à 39 000 triangles par remorque (la tête : 25 600), sauf porte-engins
  (77 000) et porte-voitures (113 000) à cause de leur chargement.

**Remorque vivante** (2026-10-06, « les roues de la remorque passent dans le
sol, la remorque est trop rigide ») : chaque essieu est un objet à part
(`Gen_Essieu_N`, origine au centre de l'essieu). En jeu, `TruckVisual` pose la
remorque affichée sur le sol sous son train de roues (tangage autour de la
sellette, roulis), donne à chaque essieu sa suspension et fait tourner les
roues (remorque et tête). Purement visuel : la caisse de collision reste
articulée en lacet seulement (VEHICLE_SPEC §5 bis). `truck_trailer_ground_test`
le vérifie sur un relief de 6° : enfoncement max 3,7 cm (1,26 m sans).

Tout ce qui est généré porte le préfixe `Gen_` ; le script est idempotent
(deux exécutions donnent des fichiers identiques à l'octet). À relancer si la
tête change :

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
| `Socket_Conteneur` | `Remorque` | arrière du châssis, propre à chaque remorque |

Les quatre premiers sont sur la tête : **mêmes coordonnées partout**, par
construction. Les deux derniers suivent la remorque (et pivotent avec elle).
Les camions de course `Camion_*.glb` n'ont pas encore de sockets.

En jeu, seule la remorque de ces véhicules sert : c'est la remorque au choix
du sas READY (VEHICLE_SPEC §5 bis), chargée par `TruckVisual.set_trailer_type`.
Triangles par remorque : voir « Qualité » ci-dessus. Les roues sont générées en
bas poly. **Restent au-dessus du budget** : le porte-engins (53 000, les deux
chariots élévateurs) et le porte-voitures (97 000, les cinq voitures).

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
